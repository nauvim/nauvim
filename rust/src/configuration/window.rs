//! Parses window appearance, margins, and startup size.

use crate::api::display::{
    DisplayDecorations, DisplayLength, DisplayLengthUnit, DisplayMargins, DisplayStartupMode,
    DisplayWindowOptions,
};

use super::{dictionary, invalid};

use nauvim_core::{Error, UiConfig, UiValue};

#[derive(Clone, Copy, PartialEq)]
enum Minimum {
    Positive,
    Nonnegative,
}

pub(super) fn parse(config: &UiConfig) -> Result<Option<DisplayWindowOptions>, Error> {
    let Some(window) = dictionary(config, config.get("window")) else {
        return Ok(None);
    };

    let margin = margins(config, window.get("margin"))?;
    let startup_size = window.get("startup_size");
    let (startup_mode, width, height) = if let Some(UiValue::String(s)) = startup_size {
        let mode = match s.as_str() {
            "maximized" => DisplayStartupMode::Maximized,
            "fullscreen" => DisplayStartupMode::Fullscreen,
            _ => {
                return Err(invalid(
                    "window.startup_size must be a table, 'maximized', 'fullscreen', or nil",
                ));
            }
        };
        (Some(mode), None, None)
    } else if let Some(size) = dictionary(config, startup_size) {
        (
            Some(DisplayStartupMode::Windowed),
            length(
                size.get("width"),
                "window.startup_size.width",
                Minimum::Positive,
            )?,
            length(
                size.get("height"),
                "window.startup_size.height",
                Minimum::Positive,
            )?,
        )
    } else {
        (None, None, None)
    };

    Ok(Some(DisplayWindowOptions {
        width,
        height,
        margin,
        decorations: match window.get("decorations") {
            Some(UiValue::String(s)) => Some(match s.as_str() {
                "full" => DisplayDecorations::Full,
                "none" => DisplayDecorations::None,
                _ => return Err(invalid("window.decorations must be 'full', 'none', or nil")),
            }),
            _ => None,
        },
        opacity: opacity(window.get("opacity"))?,
        startup_mode,
    }))
}

fn margins(config: &UiConfig, value: Option<&UiValue>) -> Result<DisplayMargins, Error> {
    let Some(margin) = dictionary(config, value) else {
        return Ok(DisplayMargins::default());
    };

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
        _ => return Ok(None),
    };

    if !value.is_finite() || value < 0.0 || (min == Minimum::Positive && value == 0.0) {
        return Err(invalid_length());
    }

    Ok(Some(DisplayLength { value, unit }))
}

fn opacity(value: Option<&UiValue>) -> Result<Option<f64>, Error> {
    match value {
        Some(UiValue::Number(value)) if (0.0..=1.0).contains(value) => Ok(Some(*value)),
        Some(UiValue::Integer(value @ (0 | 1))) => Ok(Some(*value as f64)),
        Some(UiValue::Number(_) | UiValue::Integer(_)) => Err(invalid(
            "window.opacity must be a finite number in 0..=1 or nil",
        )),
        _ => Ok(None),
    }
}
