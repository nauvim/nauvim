//! Parses configured fonts and resolves their paths relative to the configuration.

use crate::api::display::DisplayFont;

use super::{fields, invalid, nonempty_text, table};

use nauvim_core::{Error, UiConfig, UiTable, UiValue};

use std::path::Path;

const DEFAULT_SIZE: u32 = 15;

pub(super) fn parse(config: &UiConfig) -> Result<Vec<DisplayFont>, Error> {
    Ok(match config.get("fonts") {
        None | Some(UiValue::Nil) => Vec::new(),
        Some(UiValue::String(family)) => vec![DisplayFont {
            family: nonempty_text(family, "fonts")?.to_owned(),
            subfamily: None,
            size: f64::from(DEFAULT_SIZE),
            path: None,
        }],
        Some(value) => {
            let fonts_table = table(config, value, "fonts")?;
            if fonts_table.is_list() {
                font_list(config, fonts_table)?
            } else if fonts_table.get("family").is_some() {
                vec![font(fonts_table)?]
            } else if fonts_table.entries().len() == 0 {
                Vec::new()
            } else {
                return Err(invalid(
                    "fonts must be a Font or a dense list of Font tables",
                ));
            }
        }
    })
}

fn font_list(config: &UiConfig, fonts_table: &UiTable) -> Result<Vec<DisplayFont>, Error> {
    let entries = fonts_table.entries();
    let mut fonts = Vec::new();
    fonts
        .try_reserve_exact(entries.len())
        .map_err(|e| invalid(format!("Allocate configured fonts: {e}")))?;

    for (_, value) in entries {
        fonts.push(font(table(config, value, "fonts entry")?)?);
    }

    Ok(fonts)
}

pub(super) fn resolve_paths(
    fonts: &mut [DisplayFont],
    config_file: Option<&Path>,
) -> Result<(), Error> {
    let root = config_file.and_then(Path::parent);

    for font in fonts {
        let Some(path) = &mut font.path else { continue };
        if Path::new(path).is_absolute() {
            continue;
        }
        let root = root.ok_or_else(|| {
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

fn string<'t>(value: Option<&'t UiValue>, field: &str) -> Result<Option<&'t str>, Error> {
    match value {
        None | Some(UiValue::Nil) => Ok(None),
        Some(UiValue::String(value)) => nonempty_text(value, field).map(Some),
        _ => Err(invalid(format!("{field} must be a string or nil"))),
    }
}

fn size(value: Option<&UiValue>) -> Result<u32, Error> {
    match value {
        None | Some(UiValue::Nil) => Ok(DEFAULT_SIZE),
        Some(UiValue::Integer(value)) => u32::try_from(*value)
            .ok()
            .filter(|value| *value > 0)
            .ok_or_else(|| invalid("Font.size must be an integer in 1..=4294967295")),
        _ => Err(invalid("Font.size must be an integer or nil")),
    }
}

fn font(table: &UiTable) -> Result<DisplayFont, Error> {
    fields(table, &["family", "subfamily", "size", "path"], "Font")?;

    let family = string(table.get("family"), "Font.family")?
        .ok_or_else(|| invalid("Font.family is required"))?;
    let subfamily = string(table.get("subfamily"), "Font.subfamily")?;
    let size = f64::from(size(table.get("size"))?);
    let path = string(table.get("path"), "Font.path")?;

    Ok(DisplayFont {
        family: family.to_owned(),
        subfamily: subfamily.map(str::to_owned),
        size,
        path: path.map(str::to_owned),
    })
}
