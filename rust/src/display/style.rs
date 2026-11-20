use crate::api::display::{DisplayCursor, DisplayHighlight};

use nvim_rpc_ui::{State, Value};

use std::str;
use std::sync::Arc;

pub(super) fn highlights(state: &State, previous: Option<&State>) -> Vec<DisplayHighlight> {
    let highlights_changed =
        previous.is_none_or(|s| !Arc::ptr_eq(&s.highlights, &state.highlights));
    if highlights_changed {
        state
            .highlights
            .iter()
            .map(|(id, hl)| DisplayHighlight {
                id: id.0,
                foreground: hl.rgb.foreground,
                background: hl.rgb.background,
                special: hl.rgb.special,
                reverse: hl.rgb.reverse,
                bold: hl.rgb.bold,
                italic: hl.rgb.italic,
                underline: hl.rgb.underline
                    || hl.rgb.underdouble
                    || hl.rgb.underdotted
                    || hl.rgb.underdashed,
                undercurl: hl.rgb.undercurl,
                decoration: if hl.rgb.undercurl {
                    "undercurl"
                } else if hl.rgb.underdouble {
                    "underdouble"
                } else if hl.rgb.underdotted {
                    "underdotted"
                } else if hl.rgb.underdashed {
                    "underdashed"
                } else if hl.rgb.underline {
                    "underline"
                } else {
                    ""
                }
                .into(),
                strikethrough: hl.rgb.strikethrough,
                blend: hl.rgb.blend.unwrap_or(0),
            })
            .collect()
    } else {
        Vec::new()
    }
}

pub(super) fn cursor(state: &State) -> Option<DisplayCursor> {
    state.cursor.map(|c| {
        let style = state
            .mode
            .cursor_style_enabled
            .then(|| state.modes.get(state.mode.index))
            .flatten();
        let shape = style
            .and_then(|m| m.get("cursor_shape"))
            .and_then(|v| match v {
                Value::String(v) => str::from_utf8(v).ok(),
                _ => None,
            })
            .unwrap_or("block")
            .to_owned();
        let percentage = style
            .and_then(|m| m.get("cell_percentage"))
            .and_then(|v| match v {
                Value::Int(v) => u32::try_from(*v).ok(),
                Value::Uint(v) => u32::try_from(*v).ok(),
                _ => None,
            })
            .filter(|v| *v > 0 && *v <= 100)
            .unwrap_or(if shape == "block" { 100 } else { 25 });
        DisplayCursor {
            grid: c.grid.0,
            row: u32::try_from(c.row).unwrap_or(u32::MAX),
            col: u32::try_from(c.col).unwrap_or(u32::MAX),
            shape,
            percentage,
        }
    })
}
