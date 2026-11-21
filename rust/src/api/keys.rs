//! Validated frontend key bindings shared with Flutter.

/// Per-context overrides; omitted chords retain their platform defaults.
#[derive(Default)]
pub struct KeyBindings {
    pub welcome: Vec<KeyBinding>,
    pub clipboard: Vec<KeyBinding>,
    pub webview: Vec<KeyBinding>,
}

/// A logical key chord; modifiers match exactly and an absent action unbinds it.
pub struct KeyBinding {
    pub key: String,
    /// Control = 1, Shift = 2, Alt = 4, Meta = 8; lock states are ignored.
    pub modifiers: u8,
    pub action: Option<KeyAction>,
}

/// A frontend command, validated against its binding context.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum KeyAction {
    SelectNext,
    SelectPrevious,
    Activate,
    Back,
    Quit,
    Copy,
    Paste,
    Reload,
    GoBack,
    GoForward,
    Close,
    FocusEditor,
}
