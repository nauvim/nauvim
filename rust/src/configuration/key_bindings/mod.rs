//! Validates frontend actions and normalizes logical shortcut chords.

use crate::api::keys::{KeyAction, KeyBinding, KeyBindings};

use super::{dictionary, invalid, nonempty_text};

use nauvim_core::{Error, UiConfig, UiValue};

use std::borrow::Cow;

const CONTROL: u8 = 1;
const SHIFT: u8 = 2;
const ALT: u8 = 4;
const META: u8 = 8;

const FUNCTION_KEYS: [&str; 24] = [
    "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "f13", "f14", "f15",
    "f16", "f17", "f18", "f19", "f20", "f21", "f22", "f23", "f24",
];

#[derive(Clone, Copy)]
enum Context {
    Welcome,
    Clipboard,
    Webview,
}

impl Context {
    fn name(self) -> &'static str {
        match self {
            Self::Welcome => "welcome",
            Self::Clipboard => "clipboard",
            Self::Webview => "webview",
        }
    }

    fn action(self, name: &str) -> Result<KeyAction, Error> {
        let action = match (self, name) {
            (Self::Welcome, "select_next") => KeyAction::SelectNext,
            (Self::Welcome, "select_previous") => KeyAction::SelectPrevious,
            (Self::Welcome, "activate") => KeyAction::Activate,
            (Self::Welcome, "back") => KeyAction::Back,
            (Self::Welcome, "quit") => KeyAction::Quit,
            (Self::Clipboard, "copy") => KeyAction::Copy,
            (Self::Clipboard, "paste") => KeyAction::Paste,
            (Self::Webview, "reload") => KeyAction::Reload,
            (Self::Webview, "go_back") => KeyAction::GoBack,
            (Self::Webview, "go_forward") => KeyAction::GoForward,
            (Self::Webview, "close") => KeyAction::Close,
            (Self::Webview, "focus_editor") => KeyAction::FocusEditor,
            _ => {
                return Err(invalid(format!(
                    "Unknown action {name} in key_bindings.{}",
                    self.name()
                )));
            }
        };
        Ok(action)
    }
}

pub(super) fn parse(config: &UiConfig) -> Result<Option<KeyBindings>, Error> {
    let Some(root) = dictionary(config, config.get("key_bindings")) else {
        return Ok(None);
    };
    let [welcome, clipboard, webview] = [Context::Welcome, Context::Clipboard, Context::Webview];

    Ok(Some(KeyBindings {
        welcome: context(config, root.get(welcome.name()), welcome)?,
        clipboard: context(config, root.get(clipboard.name()), clipboard)?,
        webview: context(config, root.get(webview.name()), webview)?,
    }))
}

fn context(
    config: &UiConfig,
    value: Option<&UiValue>,
    context: Context,
) -> Result<Vec<KeyBinding>, Error> {
    let Some(entries) = dictionary(config, value) else {
        return Ok(Vec::new());
    };
    let entries = entries.entries();
    let mut bindings = Vec::new();
    bindings
        .try_reserve_exact(entries.len())
        .map_err(|e| invalid(format!("Allocate configured key bindings: {e}")))?;

    for (key, value) in entries {
        let UiValue::String(key) = key else {
            continue;
        };
        let source = nonempty_text(key, "key binding chord")?;
        let (key, modifiers) = chord(source)?;
        let action = match value {
            UiValue::Boolean(false) => None,
            UiValue::String(value) => {
                Some(context.action(nonempty_text(value, "key binding action")?)?)
            }
            UiValue::Boolean(true) => {
                return Err(invalid("Key binding actions must be strings or false"));
            }
            _ => continue,
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
            "Duplicate normalized key binding in {}: {}",
            context.name(),
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
            CONTROL
        } else if part.eq_ignore_ascii_case("shift") {
            SHIFT
        } else if ["alt", "option", "opt"]
            .iter()
            .any(|name| part.eq_ignore_ascii_case(name))
        {
            ALT
        } else if ["super", "meta", "cmd", "command"]
            .iter()
            .any(|name| part.eq_ignore_ascii_case(name))
        {
            META
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
        if c.is_ascii_uppercase() {
            const LETTERS: [&str; 26] = [
                "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p",
                "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
            ];
            // ASCII capitals are the consecutive bytes A through Z.
            let idx = usize::from(c as u8 - b'A');
            if let Some(letter) = LETTERS.get(idx) {
                return Ok((Cow::Borrowed(letter), modifiers | SHIFT));
            }
        }
        if c.is_ascii() {
            return Ok((Cow::Borrowed(key), modifiers));
        }
        if c.is_uppercase() {
            modifiers |= SHIFT;
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

    if let Some(key) = named_key(key) {
        return Ok((Cow::Borrowed(key), modifiers));
    }

    Err(invalid(format!(
        "Unknown key binding {source}; join modifiers with '-' or '_' and use Space for a space"
    )))
}

fn named_key(key: &str) -> Option<&'static str> {
    const MAX_NAME_LEN: usize = b"numpadenter".len();
    let mut buf = [0; MAX_NAME_LEN];
    let mut slots = buf.iter_mut();
    for byte in key.bytes().filter(|byte| !matches!(byte, b'-' | b'_')) {
        *slots.next()? = byte.to_ascii_lowercase();
    }
    let len = MAX_NAME_LEN.checked_sub(slots.len())?;

    Some(match buf.get(..len)? {
        b"escape" | b"esc" => "escape",
        b"enter" | b"return" => "enter",
        b"numpadenter" => "numpadenter",
        b"tab" => "tab",
        b"space" => " ",
        b"plus" => "+",
        b"minus" => "-",
        b"underscore" => "_",
        b"backspace" | b"bs" => "backspace",
        b"delete" | b"del" => "delete",
        b"insert" | b"ins" => "insert",
        b"up" | b"arrowup" => "arrowup",
        b"down" | b"arrowdown" => "arrowdown",
        b"left" | b"arrowleft" => "arrowleft",
        b"right" | b"arrowright" => "arrowright",
        b"home" => "home",
        b"end" => "end",
        b"pageup" | b"pgup" => "pageup",
        b"pagedown" | b"pgdown" | b"pgdn" => "pagedown",
        [b'f', digit @ b'1'..=b'9'] => {
            // The digit range gives an index in 0..=8.
            *FUNCTION_KEYS.get(usize::from(*digit - b'1'))?
        }
        [b'f', tens @ b'1'..=b'2', ones @ b'0'..=b'9'] => {
            // These digit ranges give an index in 9..=28.
            let idx = 9 + 10 * usize::from(*tens - b'1') + usize::from(*ones - b'0');
            *FUNCTION_KEYS.get(idx)?
        }
        _ => return None,
    })
}

#[cfg(test)]
mod tests;
