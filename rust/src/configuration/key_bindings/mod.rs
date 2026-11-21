use crate::api::keys::{KeyAction, KeyBinding, KeyBindings};

use super::{fields, invalid, table, text};

use nauvim_core::{Error, UiConfig, UiValue};

use std::borrow::Cow;

const FUNCTION_KEYS: [&str; 24] = [
    "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "f13", "f14", "f15",
    "f16", "f17", "f18", "f19", "f20", "f21", "f22", "f23", "f24",
];

const NAMED_KEYS: &[(&str, &str)] = &[
    ("escape", "escape"),
    ("esc", "escape"),
    ("enter", "enter"),
    ("return", "enter"),
    ("numpadenter", "numpadenter"),
    ("tab", "tab"),
    ("space", " "),
    ("plus", "+"),
    ("minus", "-"),
    ("underscore", "_"),
    ("backspace", "backspace"),
    ("bs", "backspace"),
    ("delete", "delete"),
    ("del", "delete"),
    ("insert", "insert"),
    ("ins", "insert"),
    ("up", "arrowup"),
    ("arrowup", "arrowup"),
    ("down", "arrowdown"),
    ("arrowdown", "arrowdown"),
    ("left", "arrowleft"),
    ("arrowleft", "arrowleft"),
    ("right", "arrowright"),
    ("arrowright", "arrowright"),
    ("home", "home"),
    ("end", "end"),
    ("pageup", "pageup"),
    ("pgup", "pageup"),
    ("pagedown", "pagedown"),
    ("pgdown", "pagedown"),
    ("pgdn", "pagedown"),
];

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
            key: key.into_owned(),
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

fn chord(source: &str) -> Result<(Cow<'_, str>, u8), Error> {
    let mut key = source.trim();
    let mut modifiers = 0;
    while let Some((part, rest)) = key.split_once(['-', '_']) {
        let part = part.trim();
        let bit = if ["ctrl", "control"]
            .iter()
            .any(|name| part.eq_ignore_ascii_case(name))
        {
            1
        } else if part.eq_ignore_ascii_case("shift") {
            2
        } else if ["alt", "option", "opt"]
            .iter()
            .any(|name| part.eq_ignore_ascii_case(name))
        {
            4
        } else if ["super", "meta", "cmd", "command"]
            .iter()
            .any(|name| part.eq_ignore_ascii_case(name))
        {
            8
        } else {
            break;
        };
        if modifiers & bit != 0 {
            return Err(invalid(format!(
                "Repeated modifier in key binding: {source}"
            )));
        }
        modifiers |= bit;
        key = rest.trim();
    }

    let mut chars = key.chars();
    if let Some(c) = chars.next()
        && chars.next().is_none()
        && !c.is_control()
        && !c.is_whitespace()
    {
        if modifiers != 0 && matches!(c, '-' | '_') {
            return Err(invalid(
                "Use Minus or Underscore for a separator key after a modifier",
            ));
        }
        if c.is_uppercase() {
            modifiers |= 2;
        }
        if c.is_ascii_alphabetic() {
            const LETTERS: [&str; 26] = [
                "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p",
                "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
            ];
            if let Some(letter) = LETTERS
                .iter()
                .find(|letter| key.eq_ignore_ascii_case(letter))
            {
                return Ok((Cow::Borrowed(letter), modifiers));
            }
        }
        // Keep single-scalar Unicode keyboard labels. An expanding uppercase
        // mapping (such as ß -> SS) must retain its original key identity.
        let mut upper = c.to_uppercase();
        if let Some(upper_c) = upper.next()
            && upper.next().is_none()
            && upper_c != c
        {
            return Ok((Cow::Owned(upper_c.to_string()), modifiers));
        }
        return Ok((Cow::Borrowed(key), modifiers));
    }

    if let Some((_, key)) = NAMED_KEYS.iter().find(|(name, _)| key_name_eq(key, name)) {
        return Ok((Cow::Borrowed(key), modifiers));
    }
    if let Some(key) = FUNCTION_KEYS.iter().find(|name| key_name_eq(key, name)) {
        return Ok((Cow::Borrowed(key), modifiers));
    }
    Err(invalid(format!(
        "Unknown key binding {source}; join modifiers with '-' or '_' and use Space for a space"
    )))
}

fn key_name_eq(key: &str, name: &str) -> bool {
    key.bytes()
        .filter(|b| !matches!(b, b'-' | b'_'))
        .map(|b| b.to_ascii_lowercase())
        .eq(name.bytes())
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
