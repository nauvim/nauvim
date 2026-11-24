//! Validates the selected UI dictionary and resolves configuration-relative paths.

use crate::api::display::{DisplayFont, DisplayWindowOptions};
use crate::api::keys::KeyBindings;

mod fonts;
mod key_bindings;
mod window;

use nauvim_core::{Config, Error, UiConfig, UiTable, UiValue};

use std::path::Path;

const UI_ID: &str = "com.naughie.nauvim.flutter";

#[derive(Default)]
pub(crate) struct UiOptions {
    pub(crate) fonts: Vec<DisplayFont>,
    pub(crate) window: Option<DisplayWindowOptions>,
    pub(crate) key_bindings: Option<KeyBindings>,
}

impl UiOptions {
    fn parse(config: UiConfig) -> Result<Self, Error> {
        Ok(Self {
            fonts: fonts::parse(&config)?,
            window: window::parse(&config)?,
            key_bindings: key_bindings::parse(&config)?,
        })
    }

    fn resolve_paths(&mut self, config_file: Option<&Path>) -> Result<(), Error> {
        fonts::resolve_paths(&mut self.fonts, config_file)
    }
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

fn table<'t>(config: &'t UiConfig, value: Option<&UiValue>) -> Option<&'t UiTable> {
    match value {
        Some(UiValue::Table(id)) => config.table(*id),
        _ => None,
    }
}

fn dictionary<'t>(config: &'t UiConfig, value: Option<&UiValue>) -> Option<&'t UiTable> {
    table(config, value).filter(|table| !table.is_list())
}

fn nonempty_text<'t>(value: &'t str, field: &str) -> Result<&'t str, Error> {
    if value.is_empty() {
        return Err(invalid(format!("{field} must be non-empty")));
    }
    Ok(value)
}

#[cfg(test)]
mod tests;
