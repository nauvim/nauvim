//! Serializable display and startup data shared with Flutter.

use super::keys::KeyBindings;

/// A typed bridge update. Frame rows contain only changes since the preceding update.
#[derive(Default)]
pub struct UiUpdate {
    pub kind: String,
    pub frame: Option<DisplayFrame>,
    pub message: Option<String>,
    pub hosts: Vec<String>,
    pub default_host: Option<String>,
    /// The remembered or connecting destination, independent of its display label.
    pub destination: Option<DisplayDestination>,
    pub key_bindings: Option<KeyBindings>,
    pub fonts: Vec<DisplayFont>,
    pub window_options: Option<DisplayWindowOptions>,
    pub window: Option<DisplayWindow>,
}

/// A host choice; an absent alias selects the independent default local host.
#[derive(Debug, PartialEq)]
pub struct DisplayDestination {
    pub alias: Option<String>,
}

/// A configured OpenType face and its logical-pixel em size.
pub struct DisplayFont {
    pub family: String,
    pub subfamily: Option<String>,
    pub size: f64,
    pub path: Option<String>,
}

/// Startup appearance, mode, client-area dimensions, and editor margins.
#[derive(Default)]
pub struct DisplayWindowOptions {
    pub width: Option<DisplayLength>,
    pub height: Option<DisplayLength>,
    pub margin: DisplayMargins,
    pub decorations: Option<DisplayDecorations>,
    /// Whole-window opacity, including text, controls, and native previews.
    pub opacity: Option<f64>,
    pub startup_mode: Option<DisplayStartupMode>,
}

/// Native window decorations requested at startup; omission selects full.
pub enum DisplayDecorations {
    Full,
    None,
}

/// Initial native window state; omission allows restoring a saved size.
pub enum DisplayStartupMode {
    Windowed,
    Maximized,
    Fullscreen,
}

/// A geometry value and its unit, resolved after editor cells are measured.
#[derive(Debug, Default, PartialEq)]
pub struct DisplayLength {
    pub value: f64,
    pub unit: DisplayLengthUnit,
}

/// The scale of a window geometry value; em uses the corresponding cell axis.
#[derive(Debug, Default, PartialEq)]
pub enum DisplayLengthUnit {
    #[default]
    Px,
    Em,
}

/// Nonnegative margins around the editor and command row.
#[derive(Default)]
pub struct DisplayMargins {
    pub top: DisplayLength,
    pub bottom: DisplayLength,
    pub left: DisplayLength,
    pub right: DisplayLength,
}

/// A native preview positioned in cells relative to its Neovim grid.
pub struct DisplayWindow {
    pub handle: i64,
    pub url: String,
    pub grid: i64,
    pub top: u16,
    pub left: u16,
    pub height: u16,
    pub width: u16,
}

/// A snapshot delta with ordered events independent of retained screen state.
///
/// `full` requests a complete repaint, not replacement of every retained row.
/// `grids` contains all retained grid geometry. Rows replace their indexed rows;
/// absent rows remain unchanged unless their grid was resized or removed.
/// `widgets = None` retains widgets, while an empty list clears them. `events`
/// must be handled once even when the screen snapshot is unchanged.
pub struct DisplayFrame {
    pub full: bool,
    pub grids: Vec<DisplayGrid>,
    pub removed_grids: Vec<i64>,
    pub rows: Vec<DisplayRow>,
    pub highlights: Vec<DisplayHighlight>,
    /// The host's default foreground; the visual design handles an unset value.
    pub foreground: Option<u32>,
    /// The host's default background; the visual design handles an unset value.
    pub background: Option<u32>,
    pub cursor: Option<DisplayCursor>,
    pub title: String,
    pub mode: String,
    pub busy: bool,
    pub widgets: Option<Vec<DisplayWidget>>,
    pub events: Vec<DisplayEvent>,
}
/// An ordered application event, handled once independently of painting.
pub struct DisplayEvent {
    pub kind: String,
    pub text: String,
}

/// Grid dimensions in cells and placement in primary-grid cell coordinates.
pub struct DisplayGrid {
    pub id: i64,
    pub width: u32,
    pub height: u32,
    pub row: f64,
    pub col: f64,
    pub zindex: i64,
    pub order: i64,
    pub hidden: bool,
}

/// One complete replacement row in a grid.
pub struct DisplayRow {
    pub grid: i64,
    pub row: u32,
    pub cells: Vec<DisplayCell>,
}

/// Cell text and its Neovim highlight handle.
///
/// An empty string can be a continuation cell of a wider glyph.
pub struct DisplayCell {
    pub text: String,
    pub highlight: i64,
}

/// A grid-local cursor with its shape and cell coverage percentage.
pub struct DisplayCursor {
    pub grid: i64,
    pub row: u32,
    pub col: u32,
    pub shape: String,
    pub percentage: u32,
}

/// Neovim highlight attributes, retaining unset colors for the frontend's defaults.
pub struct DisplayHighlight {
    pub id: i64,
    pub foreground: Option<u32>,
    pub background: Option<u32>,
    pub special: Option<u32>,
    pub reverse: bool,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub undercurl: bool,
    pub decoration: String,
    pub strikethrough: bool,
    pub blend: u8,
}

/// A highlighted UTF-8 text segment.
pub struct DisplayChunk {
    pub text: String,
    pub highlight: i64,
}
/// Unformatted completion fields supplied by the host Neovim.
pub struct DisplayCompletion {
    pub word: String,
    pub kind: String,
    pub menu: String,
    pub info: String,
}

/// An external UI widget with content selected by `kind`.
///
/// Command-line positions are UTF-8 byte offsets including the displayed prefix.
/// Completion fields remain separate; tabpage and buffer entries retain native
/// handles rather than deriving selection from their display names.
#[derive(Default)]
pub struct DisplayWidget {
    pub kind: String,
    pub grid: i64,
    pub row: f64,
    pub col: f64,
    pub selected: i64,
    pub chunks: Vec<DisplayChunk>,
    pub items: Vec<String>,
    pub handles: Vec<i64>,
    pub completions: Option<Vec<DisplayCompletion>>,
}
