//! Parses window geometry, appearance, and startup mode.

use crate::api::display::{
    DisplayDecorations, DisplayLength, DisplayLengthUnit, DisplayMargins, DisplayStartupMode,
    DisplayWindowOptions,
};

use super::{fields, invalid, table};

use nauvim_core::{Error, UiConfig, UiValue};

#[derive(Clone, Copy, PartialEq)]
enum Minimum {
    Positive,
    Nonnegative,
}

pub(super) fn parse(config: &UiConfig) -> Result<Option<DisplayWindowOptions>, Error> {
    let window = match config.get("window") {
        None | Some(UiValue::Nil) => return Ok(None),
        Some(value) => table(config, value, "window")?,
    };
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

    let margin = margins(config, window.get("margin"))?;

    Ok(Some(DisplayWindowOptions {
        width: length(window.get("width"), "window.width", Minimum::Positive)?,
        height: length(window.get("height"), "window.height", Minimum::Positive)?,
        margin,
        decorations: match window.get("decorations") {
            None | Some(UiValue::Nil) => None,
            Some(UiValue::String(s)) if s == "full" => Some(DisplayDecorations::Full),
            Some(UiValue::String(s)) if s == "none" => Some(DisplayDecorations::None),
            _ => return Err(invalid("window.decorations must be 'full', 'none', or nil")),
        },
        opacity: opacity(window.get("opacity"))?,
        startup_mode: match window.get("startup_mode") {
            None | Some(UiValue::Nil) => None,
            Some(UiValue::String(s)) if s == "windowed" => Some(DisplayStartupMode::Windowed),
            Some(UiValue::String(s)) if s == "maximized" => Some(DisplayStartupMode::Maximized),
            Some(UiValue::String(s)) if s == "fullscreen" => Some(DisplayStartupMode::Fullscreen),
            _ => {
                return Err(invalid(
                    "window.startup_mode must be 'windowed', 'maximized', 'fullscreen', or nil",
                ));
            }
        },
    }))
}

fn margins(config: &UiConfig, value: Option<&UiValue>) -> Result<DisplayMargins, Error> {
    let margin = match value {
        None | Some(UiValue::Nil) => return Ok(DisplayMargins::default()),
        Some(value) => table(config, value, "window.margin")?,
    };
    fields(margin, &["top", "bottom", "left", "right"], "window.margin")?;

    let side = |key, field| {
        length(margin.get(key), field, Minimum::Nonnegative).map(Option::unwrap_or_default)
    };

    Ok(DisplayMargins {
        top: side("top", "window.margin.top")?,
        bottom: side("bottom", "window.margin.bottom")?,
        left: side("left", "window.margin.left")?,
        right: side("right", "window.margin.right")?,
    })
}

fn length(
    value: Option<&UiValue>,
    field: &str,
    min: Minimum,
) -> Result<Option<DisplayLength>, Error> {
    let invalid_length = || {
        let minimum = match min {
            Minimum::Positive => "positive",
            Minimum::Nonnegative => "nonnegative",
        };
        invalid(format!(
            "{field} must be {minimum} integer pixels, integer 'px', finite 'em', or nil",
        ))
    };

    let (value, unit) = match value {
        None | Some(UiValue::Nil) => return Ok(None),
        Some(UiValue::Integer(value)) => (
            f64::from(u32::try_from(*value).map_err(|_| invalid_length())?),
            DisplayLengthUnit::Px,
        ),
        Some(UiValue::String(s)) => {
            if let Some(s) = s.strip_suffix("px") {
                if s.starts_with('+') {
                    return Err(invalid_length());
                }
                (
                    f64::from(s.parse::<u32>().map_err(|_| invalid_length())?),
                    DisplayLengthUnit::Px,
                )
            } else if let Some(s) = s.strip_suffix("em") {
                (
                    s.parse::<f64>().map_err(|_| invalid_length())?,
                    DisplayLengthUnit::Em,
                )
            } else {
                return Err(invalid_length());
            }
        }
        _ => return Err(invalid_length()),
    };

    if !value.is_finite() || value < 0.0 || (min == Minimum::Positive && value == 0.0) {
        return Err(invalid_length());
    }

    Ok(Some(DisplayLength { value, unit }))
}

fn opacity(value: Option<&UiValue>) -> Result<Option<f64>, Error> {
    match value {
        None | Some(UiValue::Nil) => Ok(None),
        Some(UiValue::Number(value)) if (0.0..=1.0).contains(value) => Ok(Some(*value)),
        Some(UiValue::Integer(value @ (0 | 1))) => Ok(Some(*value as f64)),
        _ => Err(invalid(
            "window.opacity must be a finite number in 0..=1 or nil",
        )),
    }
}
