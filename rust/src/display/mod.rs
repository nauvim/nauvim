//! Projects retained Neovim snapshots into changed rows and ordered UI updates.

use crate::api::display::DisplayFrame;

mod events;
mod grids;
mod style;
mod widgets;

use nvim_rpc_ui::{Event, Frame, Messages, State};

use std::sync::Arc;

pub(crate) struct Presenter {
    previous: Option<Arc<State>>,
    dismissed: Option<Arc<Messages>>,
    has_messages: bool,
}

impl Presenter {
    pub(crate) fn new() -> Self {
        Self {
            previous: None,
            dismissed: None,
            has_messages: false,
        }
    }

    pub(crate) fn reset(&mut self) {
        self.previous = None;
        self.dismissed = None;
        self.has_messages = false;
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

        let grid_changes = grids::changes(state, previous);
        let (repaint, highlights) = style::changes(state, previous);
        let grids = grids::geometry(state);
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
