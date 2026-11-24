//! Parses configured fonts and resolves their paths relative to the configuration.

use crate::api::display::DisplayFont;

use super::{dictionary, invalid, nonempty_text, table};

use nauvim_core::{Error, UiConfig, UiTable, UiValue};

use std::path::Path;

const DEFAULT_SIZE: u32 = 15;

pub(super) fn parse(config: &UiConfig) -> Result<Vec<DisplayFont>, Error> {
    let value = config.get("fonts");
    if let Some(UiValue::String(family)) = value {
        return Ok(vec![DisplayFont {
            family: nonempty_text(family, "fonts")?.to_owned(),
            subfamily: None,
            size: f64::from(DEFAULT_SIZE),
            path: None,
        }]);
    }

    let Some(fonts) = table(config, value) else {
        return Ok(Vec::new());
    };
    if fonts.is_list() {
        return font_list(config, fonts);
    }
    Ok(font(fonts, true)?.into_iter().collect())
}

fn font_list(config: &UiConfig, fonts_table: &UiTable) -> Result<Vec<DisplayFont>, Error> {
    let entries = fonts_table.entries();
    let mut fonts = Vec::new();
    fonts
        .try_reserve_exact(entries.len())
        .map_err(|e| invalid(format!("Allocate configured fonts: {e}")))?;

    for (_, value) in entries {
        let entry = dictionary(config, Some(value))
            .ok_or_else(|| invalid("fonts entry must be a dictionary"))?;
        if let Some(font) = font(entry, false)? {
            fonts.push(font);
        }
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
        Some(UiValue::String(value)) => nonempty_text(value, field).map(Some),
        _ => Ok(None),
    }
}

fn size(value: Option<&UiValue>) -> Result<u32, Error> {
    match value {
        Some(UiValue::Integer(value)) => u32::try_from(*value)
            .ok()
            .filter(|value| *value > 0)
            .ok_or_else(|| invalid("Font.size must be an integer in 1..=4294967295")),
        _ => Ok(DEFAULT_SIZE),
    }
}

fn font(table: &UiTable, allow_empty: bool) -> Result<Option<DisplayFont>, Error> {
    let family = match table.get("family") {
        Some(UiValue::String(family)) => nonempty_text(family, "Font.family")?,
        None | Some(UiValue::Nil) => {
            if allow_empty
                && !matches!(table.get("size"), Some(UiValue::Integer(_)))
                && !matches!(table.get("path"), Some(UiValue::String(_)))
                && !matches!(table.get("subfamily"), Some(UiValue::String(_)))
            {
                return Ok(None);
            }
            return Err(invalid("Font.family is required"));
        }
        _ => return Ok(None),
    };
    let subfamily = string(table.get("subfamily"), "Font.subfamily")?;
    let size = f64::from(size(table.get("size"))?);
    let path = string(table.get("path"), "Font.path")?;

    Ok(Some(DisplayFont {
        family: family.to_owned(),
        subfamily: subfamily.map(str::to_owned),
        size,
        path: path.map(str::to_owned),
    }))
}
