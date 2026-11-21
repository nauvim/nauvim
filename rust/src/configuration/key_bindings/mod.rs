use crate::api::keys::{KeyAction, KeyBinding, KeyBindings};

use super::{fields, invalid, table, text};

use nauvim_core::{Error, UiConfig, UiValue};

pub(super) fn parse(config: &UiConfig) -> Result<Option<KeyBindings>, Error> {
    let root = match config.get("key_bindings") {
        None | Some(UiValue::Nil) => return Ok(None),
        Some(value) => table(config, value, "key_bindings")?,
    };
    fields(root, &["welcome", "clipboard", "webview"], "key_bindings")?;
    Ok(Some(KeyBindings {
        welcome: context(config, root.get("welcome"), "welcome")?,
        clipboard: context(config, root.get("clipboard"), "clipboard")?,
        webview: context(config, root.get("webview"), "webview")?,
    }))
}

fn context(
    config: &UiConfig,
    value: Option<&UiValue>,
    name: &str,
) -> Result<Vec<KeyBinding>, Error> {
    let entries = match value {
        None | Some(UiValue::Nil) => return Ok(Vec::new()),
        Some(value) => table(config, value, "key binding context")?,
    };
    let mut bindings = Vec::new();
    for (key, value) in entries.entries() {
        let UiValue::String(key) = key else {
            return Err(invalid("Key binding chords must be strings"));
        };
        let source = text(key, "key binding chord")?;
        let (key, modifiers) = chord(source)?;
        let action = match value {
            UiValue::Boolean(false) => None,
            UiValue::String(bytes) => Some(action(name, text(bytes, "key binding action")?)?),
            _ => return Err(invalid("Key binding actions must be strings or false")),
        };
        bindings.push(KeyBinding {
            key,
            modifiers,
            action,
        });
    }
    // Lua table traversal order does not affect the bridge or shortcut hints.
    bindings.sort_unstable_by(|a, b| (&a.key, a.modifiers).cmp(&(&b.key, b.modifiers)));
    if let Some((binding, _)) = bindings
        .iter()
        .zip(bindings.iter().skip(1))
        .find(|(a, b)| a.key == b.key && a.modifiers == b.modifiers)
    {
        return Err(invalid(format!(
            "Duplicate normalized key binding in {name}: {}",
            binding.key
        )));
    }
    Ok(bindings)
}

fn chord(source: &str) -> Result<(String, u8), Error> {
    let mut parts = source.split('+');
    let key = parts.next_back().unwrap_or_default().trim();
    let mut modifiers = 0;
    for part in parts {
        let bit = match part.trim().to_ascii_lowercase().as_str() {
            "ctrl" | "control" => 1,
            "shift" => 2,
            "alt" | "option" | "opt" => 4,
            "super" | "meta" | "cmd" | "command" => 8,
            _ => {
                return Err(invalid(format!(
                    "Unknown modifier in key binding: {source}"
                )));
            }
        };
        if modifiers & bit != 0 {
            return Err(invalid(format!(
                "Repeated modifier in key binding: {source}"
            )));
        }
        modifiers |= bit;
    }
    let mut lower = key.to_uppercase();
    lower.make_ascii_lowercase();
    if let Some(n) = lower.strip_prefix('f').and_then(|s| s.parse::<u8>().ok())
        && (1..=24).contains(&n)
    {
        return Ok((format!("f{n}"), modifiers));
    }
    let key = match lower.as_str() {
        "esc" | "escape" => "escape",
        "return" | "enter" => "enter",
        "numpadenter" => "numpadenter",
        "space" => " ",
        "plus" => "+",
        "minus" => "-",
        "backspace" | "bs" => "backspace",
        "delete" | "del" => "delete",
        "insert" | "ins" => "insert",
        "up" | "arrowup" => "arrowup",
        "down" | "arrowdown" => "arrowdown",
        "left" | "arrowleft" => "arrowleft",
        "right" | "arrowright" => "arrowright",
        "pageup" | "pgup" => "pageup",
        "pagedown" | "pgdown" | "pgdn" => "pagedown",
        "tab" | "home" | "end" => return Ok((lower, modifiers)),
        _ if key.chars().count() == 1
            && !key.chars().any(|c| c.is_control() || c.is_whitespace()) =>
        {
            return Ok((lower, modifiers));
        }
        _ => {
            return Err(invalid(format!(
                "Unknown key in binding {source}; use Plus for '+' and Space for a space"
            )));
        }
    };
    Ok((key.to_owned(), modifiers))
}

fn action(context: &str, name: &str) -> Result<KeyAction, Error> {
    Ok(match (context, name) {
        ("welcome", "select_next") => KeyAction::SelectNext,
        ("welcome", "select_previous") => KeyAction::SelectPrevious,
        ("welcome", "activate") => KeyAction::Activate,
        ("welcome", "back") => KeyAction::Back,
        ("welcome", "quit") => KeyAction::Quit,
        ("clipboard", "copy") => KeyAction::Copy,
        ("clipboard", "paste") => KeyAction::Paste,
        ("webview", "reload") => KeyAction::Reload,
        ("webview", "go_back") => KeyAction::GoBack,
        ("webview", "go_forward") => KeyAction::GoForward,
        ("webview", "close") => KeyAction::Close,
        ("webview", "focus_editor") => KeyAction::FocusEditor,
        _ => {
            return Err(invalid(format!(
                "Unknown action {name} in key_bindings.{context}"
            )));
        }
    })
}

#[cfg(test)]
mod tests;
