//! Validates the selected UI dictionary and resolves configuration-relative paths.

use crate::api::display::{
    DisplayDecorations, DisplayFont, DisplayMargins, DisplayStartupMode, DisplayWindowOptions,
};

use nauvim_core::{Config, Error, UiConfig, UiTable, UiValue};

use std::path::Path;
use std::str;

const UI_ID: &str = "com.naughie.nauvim.flutter";

#[derive(Default)]
pub(crate) struct UiOptions {
    pub(crate) fonts: Vec<DisplayFont>,
    pub(crate) window: Option<DisplayWindowOptions>,
}

impl UiOptions {
    fn parse(config: UiConfig) -> Result<Self, Error> {
        fields(config.root(), &["fonts", "window"], "UI options")?;
        Ok(Self {
            fonts: fonts(&config)?,
            window: window(&config)?,
        })
    }

    fn resolve_paths(&mut self, config_file: Option<&Path>) -> Result<(), Error> {
        for font in &mut self.fonts {
            let Some(path) = &mut font.path else { continue };
            if Path::new(path).is_absolute() {
                continue;
            }
            let root = config_file.and_then(Path::parent).ok_or_else(|| {
                invalid("Relative font paths require the configuration file's directory")
            })?;
            *path = root
                .join(&*path)
                .into_os_string()
                .into_string()
                .map_err(|_| invalid("The resolved font path must be valid UTF-8"))?;
        }
        Ok(())
    }
}

fn fonts(config: &UiConfig) -> Result<Vec<DisplayFont>, Error> {
    Ok(match config.get("fonts") {
        None | Some(UiValue::Nil) => Vec::new(),
        Some(UiValue::String(bytes)) => vec![DisplayFont {
            family: text(bytes, "fonts")?.to_owned(),
            subfamily: None,
            size: 15.0,
            path: None,
        }],
        Some(value) => {
            let fonts_table = table(config, value, "fonts")?;
            if fonts_table.get("family").is_some() {
                vec![font(fonts_table)?]
            } else {
                let mut entries = fonts_table
                    .entries()
                    .map(|(key, value)| {
                        let UiValue::Integer(index) = key else {
                            return Err(invalid(
                                "fonts must be a Font or a dense list of Font tables",
                            ));
                        };
                        let index = usize::try_from(*index)
                            .ok()
                            .filter(|index| *index > 0)
                            .ok_or_else(|| {
                                invalid("fonts list indices must be positive integers")
                            })?;
                        Ok((index, value))
                    })
                    .collect::<Result<Vec<_>, Error>>()?;
                entries.sort_unstable_by_key(|(index, _)| *index);
                let mut fonts = Vec::new();
                fonts
                    .try_reserve_exact(entries.len())
                    .map_err(|e| invalid(format!("Allocate configured fonts: {e}")))?;

                for (expected, (index, value)) in entries.into_iter().enumerate() {
                    if index.checked_sub(1) != Some(expected) {
                        return Err(invalid(
                            "fonts must be a dense list without missing indices",
                        ));
                    }
                    fonts.push(font(table(config, value, "fonts entry")?)?);
                }
                fonts
            }
        }
    })
}

fn window(config: &UiConfig) -> Result<Option<DisplayWindowOptions>, Error> {
    Ok(match config.get("window") {
        None | Some(UiValue::Nil) => None,
        Some(value) => {
            let window = table(config, value, "window")?;
            fields(
                window,
                &[
                    "width",
                    "height",
                    "margin",
                    "decorations",
                    "opacity",
                    "startup_mode",
                ],
                "window",
            )?;
            let margin = match window.get("margin") {
                None | Some(UiValue::Nil) => DisplayMargins::default(),
                Some(value) => {
                    let margin = table(config, value, "window.margin")?;
                    fields(margin, &["top", "bottom", "left", "right"], "window.margin")?;
                    DisplayMargins {
                        top: integer(margin.get("top"), "window.margin.top", 0)?.unwrap_or(0),
                        bottom: integer(margin.get("bottom"), "window.margin.bottom", 0)?
                            .unwrap_or(0),
                        left: integer(margin.get("left"), "window.margin.left", 0)?.unwrap_or(0),
                        right: integer(margin.get("right"), "window.margin.right", 0)?.unwrap_or(0),
                    }
                }
            };
            Some(DisplayWindowOptions {
                width: integer(window.get("width"), "window.width", 1)?,
                height: integer(window.get("height"), "window.height", 1)?,
                margin,
                decorations: match window.get("decorations") {
                    None | Some(UiValue::Nil) => None,
                    Some(UiValue::String(s)) if s == b"full" => Some(DisplayDecorations::Full),
                    Some(UiValue::String(s)) if s == b"none" => Some(DisplayDecorations::None),
                    _ => return Err(invalid("window.decorations must be 'full', 'none', or nil")),
                },
                opacity: opacity(window.get("opacity"))?,
                startup_mode: match window.get("startup_mode") {
                    None | Some(UiValue::Nil) => None,
                    Some(UiValue::String(s)) if s == b"windowed" => {
                        Some(DisplayStartupMode::Windowed)
                    }
                    Some(UiValue::String(s)) if s == b"maximized" => {
                        Some(DisplayStartupMode::Maximized)
                    }
                    Some(UiValue::String(s)) if s == b"fullscreen" => {
                        Some(DisplayStartupMode::Fullscreen)
                    }
                    _ => {
                        return Err(invalid(
                            "window.startup_mode must be 'windowed', 'maximized', 'fullscreen', or nil",
                        ));
                    }
                },
            })
        }
    })
}

fn opacity(value: Option<&UiValue>) -> Result<Option<f64>, Error> {
    let value = match value {
        None | Some(UiValue::Nil) => return Ok(None),
        Some(UiValue::Number(value)) => *value,
        Some(UiValue::Integer(value)) => *value as f64,
        _ => {
            return Err(invalid(
                "window.opacity must be a finite number in 0..=1 or nil",
            ));
        }
    };
    if !value.is_finite() || !(0.0..=1.0).contains(&value) {
        return Err(invalid(
            "window.opacity must be a finite number in 0..=1 or nil",
        ));
    }
    Ok(Some(value))
}

pub(crate) fn load(path: Option<&Path>) -> Result<(Config, UiOptions), Error> {
    let (config, mut options) = Config::load(path, UI_ID, UiOptions::parse)?;

    options.resolve_paths(
        config
            .client_info()
            .and_then(|info| info.config_file.as_deref()),
    )?;

    Ok((config, options))
}

fn invalid(message: impl Into<String>) -> Error {
    Error::Message(message.into())
}

fn table<'t>(config: &'t UiConfig, value: &UiValue, field: &str) -> Result<&'t UiTable, Error> {
    if let UiValue::Table(id) = value
        && let Some(table) = config.table(*id)
    {
        return Ok(table);
    }
    Err(invalid(format!("{field} must be a table")))
}

fn fields(table: &UiTable, names: &[&str], field: &str) -> Result<(), Error> {
    for (key, _) in table.entries() {
        if let UiValue::String(bytes) = key
            && names.iter().any(|name| name.as_bytes() == bytes)
        {
            continue;
        }
        return Err(invalid(format!("{field} contains an unknown field")));
    }
    Ok(())
}

fn text<'t>(bytes: &'t [u8], field: &str) -> Result<&'t str, Error> {
    let value =
        str::from_utf8(bytes).map_err(|_| invalid(format!("{field} must be valid UTF-8")))?;
    if value.is_empty() || value.contains('\0') {
        return Err(invalid(format!(
            "{field} must be non-empty and contain no NUL"
        )));
    }
    Ok(value)
}

fn string(value: Option<&UiValue>, field: &str) -> Result<Option<String>, Error> {
    match value {
        None | Some(UiValue::Nil) => Ok(None),
        Some(UiValue::String(bytes)) => Ok(Some(text(bytes, field)?.to_owned())),
        _ => Err(invalid(format!("{field} must be a string or nil"))),
    }
}

fn integer(value: Option<&UiValue>, field: &str, min: u32) -> Result<Option<u32>, Error> {
    match value {
        None | Some(UiValue::Nil) => Ok(None),
        Some(UiValue::Integer(value)) => u32::try_from(*value)
            .ok()
            .filter(|value| *value >= min)
            .map(Some)
            .ok_or_else(|| invalid(format!("{field} must be an integer in {min}..=4294967295"))),
        _ => Err(invalid(format!("{field} must be an integer or nil"))),
    }
}

fn font(table: &UiTable) -> Result<DisplayFont, Error> {
    fields(table, &["family", "subfamily", "size", "path"], "Font")?;
    Ok(DisplayFont {
        family: string(table.get("family"), "Font.family")?
            .ok_or_else(|| invalid("Font.family is required"))?,
        subfamily: string(table.get("subfamily"), "Font.subfamily")?,
        size: f64::from(integer(table.get("size"), "Font.size", 1)?.unwrap_or(15)),
        path: string(table.get("path"), "Font.path")?,
    })
}

#[cfg(test)]
mod tests;
