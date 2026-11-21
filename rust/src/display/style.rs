use crate::api::display::{DisplayCursor, DisplayHighlight};

use nvim_rpc_ui::{State, Value};

use std::sync::Arc;
use std::{ptr, str};

pub(super) fn changes(state: &State, previous: Option<&State>) -> (bool, Vec<DisplayHighlight>) {
    let Some(previous) = previous else {
        return (true, highlights(state));
    };
    if ptr::eq(state, previous) {
        return (false, Vec::new());
    }
    if !Arc::ptr_eq(&state.highlights, &previous.highlights) {
        return (true, highlights(state));
    }

    let colors = state.default_colors;
    let old = previous.default_colors;
    let repaint = colors.foreground != old.foreground
        || colors.background != old.background
        || colors.special != old.special
        || colors.cterm_foreground != old.cterm_foreground
        || colors.cterm_background != old.cterm_background
        || !Arc::ptr_eq(&state.options, &previous.options)
        || state.title != previous.title
        || state.icon != previous.icon
        || state.cwd != previous.cwd
        || state.mouse_enabled != previous.mouse_enabled;

    (repaint, Vec::new())
}

fn highlights(state: &State) -> Vec<DisplayHighlight> {
    state
        .highlights
        .iter()
        .map(|(id, hl)| {
            let rgb = &hl.rgb;
            let decoration = if rgb.undercurl {
                "undercurl"
            } else if rgb.underdouble {
                "underdouble"
            } else if rgb.underdotted {
                "underdotted"
            } else if rgb.underdashed {
                "underdashed"
            } else if rgb.underline {
                "underline"
            } else {
                ""
            };

            DisplayHighlight {
                id: id.0,
                foreground: rgb.foreground,
                background: rgb.background,
                special: rgb.special,
                reverse: rgb.reverse,
                bold: rgb.bold,
                italic: rgb.italic,
                underline: rgb.underline || rgb.underdouble || rgb.underdotted || rgb.underdashed,
                undercurl: rgb.undercurl,
                decoration: decoration.into(),
                strikethrough: rgb.strikethrough,
                blend: rgb.blend.unwrap_or(0),
            }
        })
        .collect()
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
            .unwrap_or("block");
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
            shape: shape.to_owned(),
            percentage,
        }
    })
}
