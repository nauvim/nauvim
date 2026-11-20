//! Projects retained Neovim snapshots into changed rows and ordered UI updates.

use crate::api::display::DisplayFrame;

mod events;
mod grids;
pub(crate) use grids::WindowPosition;
mod style;
mod widgets;

use nvim_rpc_ui::{Event, Frame, GridId, Messages, State};

use std::collections::BTreeMap;
use std::mem;
use std::sync::Arc;

pub(crate) struct Presenter {
    previous: Option<Arc<State>>,
    dismissed: Option<Arc<Messages>>,
    has_messages: bool,
    widgets_dirty: bool,
    positions: BTreeMap<GridId, WindowPosition>,
}

impl Presenter {
    pub(crate) fn new() -> Self {
        Self {
            previous: None,
            dismissed: None,
            has_messages: false,
            widgets_dirty: false,
            positions: BTreeMap::new(),
        }
    }

    pub(crate) fn reset(&mut self) {
        self.previous = None;
        self.dismissed = None;
        self.has_messages = false;
        self.widgets_dirty = false;
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
        let state = Arc::clone(self.previous.as_ref()?);
        self.dismissed = Some(Arc::clone(&state.messages));
        if !self.has_messages {
            return None;
        }
        self.widgets_dirty = true;
        Some(self.project(state, Vec::new()))
    }

    pub(crate) fn frame(&mut self, frame: Frame) -> DisplayFrame {
        self.project(frame.state, frame.events)
    }

    fn project(&mut self, snapshot: Arc<State>, events: Vec<Event>) -> DisplayFrame {
        let state = &snapshot;
        self.positions.retain(|id, position| {
            state.grids.contains_key(id)
                && !state.placements.contains_key(id)
                && state
                    .viewports
                    .get(id)
                    .is_some_and(|v| v.window == position.window)
        });
        let damage = self.previous.as_ref().map(|s| state.diff_since(s));
        let full = damage.as_ref().is_none_or(|d| d.full);

        let previous = self.previous.as_deref();
        let rows = grids::rows(state, previous);
        let highlights = style::highlights(state, previous);
        let grids = grids::geometry(state, &self.positions);
        let cursor = style::cursor(state);

        let widgets_dirty = mem::take(&mut self.widgets_dirty);
        let widgets_changed =
            self.previous.is_none() || damage.as_ref().is_some_and(|d| d.widgets) || widgets_dirty;
        let widgets = if widgets_changed {
            let (widgets, has_messages) = widgets::project(state, self.dismissed.as_deref());
            self.has_messages = has_messages;
            Some(widgets)
        } else {
            None
        };

        let events = events.into_iter().filter_map(events::project).collect();

        let ret = DisplayFrame {
            full,
            grids,
            rows,
            highlights,
            removed_grids: damage
                .map(|d| d.removed_grids.into_iter().map(|id| id.0).collect())
                .unwrap_or_default(),
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
