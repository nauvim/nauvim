//! Projects retained Neovim snapshots into changed rows and ordered UI updates.

use crate::api::display::DisplayFrame;

mod events;
mod grids;
pub(crate) use grids::WindowPosition;
mod style;
mod widgets;

use nvim_rpc_ui::{Event, Frame, GridId, Messages, State};

use std::collections::BTreeMap;
use std::sync::Arc;

pub(crate) struct Presenter {
    previous: Option<Arc<State>>,
    dismissed: Option<Arc<Messages>>,
    has_messages: bool,
    positions: BTreeMap<GridId, WindowPosition>,
}

impl Presenter {
    pub(crate) fn new() -> Self {
        Self {
            previous: None,
            dismissed: None,
            has_messages: false,
            positions: BTreeMap::new(),
        }
    }

    pub(crate) fn reset(&mut self) {
        self.previous = None;
        self.dismissed = None;
        self.has_messages = false;
        self.positions.clear();
    }

    pub(crate) fn restore_positions(
        &mut self,
        positions: impl IntoIterator<Item = WindowPosition>,
    ) {
        self.positions
            .extend(positions.into_iter().map(|p| (p.grid, p)));
    }

    /// Clears the GUI's transient message area without changing Neovim history.
    pub(crate) fn dismiss_messages(&mut self) -> Option<DisplayFrame> {
        let state = self.previous.as_ref()?;
        self.dismissed = Some(Arc::clone(&state.messages));
        if !self.has_messages {
            return None;
        }

        Some(self.project(Arc::clone(state), Vec::new(), true))
    }

    pub(crate) fn frame(&mut self, frame: Frame) -> DisplayFrame {
        self.project(frame.state, frame.events, false)
    }

    fn project(
        &mut self,
        snapshot: Arc<State>,
        events: Vec<Event>,
        force_widgets: bool,
    ) -> DisplayFrame {
        let state = &snapshot;
        let previous = self.previous.as_deref();

        // workaround (#18): win_hide cannot hide a grid with no RPC placement.
        // Reconstructed positions belong to the tab active at attachment.
        if !self.positions.is_empty()
            && let Some(old) = previous.and_then(|s| s.tabline.as_deref())
            && let Some(tabline) = state.tabline.as_deref()
            && old.current != tabline.current
        {
            self.positions.clear();
        }

        let grid_changes = grids::changes(state, previous);
        let (repaint, highlights) = style::changes(state, previous);
        let grids = grids::geometry(state, &mut self.positions);
        let cursor = style::cursor(state);

        let widgets = if force_widgets || widgets::changed(state, previous) {
            let (widgets, has_messages) = widgets::project(state, self.dismissed.as_deref());
            self.has_messages = has_messages;
            Some(widgets)
        } else {
            None
        };

        let events = events.into_iter().filter_map(events::project).collect();

        let ret = DisplayFrame {
            full: repaint,
            grids,
            rows: grid_changes.rows,
            highlights,
            removed_grids: grid_changes.removed,
            foreground: state.default_colors.foreground,
            background: state.default_colors.background,
            cursor,
            title: state.title.to_string(),
            mode: state.mode.name.to_string(),
            busy: state.busy,
            widgets,
            events,
        };
        self.previous = Some(snapshot);

        ret
    }
}

#[cfg(test)]
mod tests;
