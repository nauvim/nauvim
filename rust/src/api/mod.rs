//! Defines the stable Flutter bridge contract and its application/font entry points.

pub(crate) mod application;
pub use application::{Application, create_application};

pub(crate) mod display;
pub use display::{
    DisplayCell, DisplayChunk, DisplayCompletion, DisplayCursor, DisplayDecorations, DisplayEvent,
    DisplayFont, DisplayFrame, DisplayGrid, DisplayHighlight, DisplayLength, DisplayLengthUnit,
    DisplayMargins, DisplayRow, DisplayStartupMode, DisplayWebview, DisplayWidget, DisplayWindow,
    DisplayWindowOptions, UiUpdate,
};

pub(crate) mod fonts;
pub use fonts::{
    FontCandidate, FontInfo, FontRange, FontRequest, FontResolution, FontVariation, ResolvedFont,
    resolve_fonts,
};

pub(crate) mod keys;
pub use keys::{KeyAction, KeyBinding, KeyBindings};
