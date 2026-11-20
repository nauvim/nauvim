use crate::api::display::{DisplayChunk, DisplayCompletion, DisplayWidget};

use nvim_rpc_ui::{Chunk, Cmdline, Message, Messages, PopupAnchor, State};

use std::iter;

pub(super) fn project(state: &State, dismissed: Option<&Messages>) -> (Vec<DisplayWidget>, bool) {
    let mut has_messages = false;
    let mut widgets = Vec::new();

    for cmdline in state.cmdlines.values() {
        let (chunks, prefix_len) = cmdline_chunks(cmdline);
        widgets.push(DisplayWidget {
            kind: "cmdline".into(),
            grid: 1,
            row: 0.,
            col: 0.,
            selected: i64::try_from(prefix_len.saturating_add(cmdline.pos)).unwrap_or(i64::MAX),
            chunks,
            ..DisplayWidget::default()
        });
    }
    for content in state.cmdline_block.iter() {
        widgets.push(text_widget("cmdline_block", content));
    }
    for message in current_messages(&state.messages, dismissed) {
        if !message.content.is_empty() {
            has_messages = true;
            widgets.push(text_widget("message", &message.content));
        }
    }
    for content in [
        &state.messages.showmode,
        &state.messages.showcmd,
        &state.messages.ruler,
    ] {
        if !content.is_empty() {
            widgets.push(text_widget("status", content));
        }
    }
    if let Some(history) = &state.messages.history {
        for message in history {
            widgets.push(text_widget("message", &message.content));
        }
    }
    if let Some(popup) = &state.popupmenu {
        let (kind, grid, row, col) = match popup.anchor {
            PopupAnchor::Grid { grid, row, col } => ("popup", grid.0, row as f64, col as f64),
            PopupAnchor::Cmdline { byte_offset } => {
                let prefix_len = state.cmdlines.values().next_back().map_or(0, |c| {
                    c.firstc
                        .len()
                        .saturating_add(c.prompt.len())
                        .saturating_add(c.indent)
                });
                (
                    "cmdline_popup",
                    1,
                    0.,
                    prefix_len.saturating_add(byte_offset) as f64,
                )
            }
        };
        widgets.push(DisplayWidget {
            kind: kind.into(),
            grid,
            row,
            col,
            selected: popup
                .selected
                .and_then(|s| i64::try_from(s).ok())
                .unwrap_or(-1),
            completions: Some(
                popup
                    .items
                    .iter()
                    .map(|i| DisplayCompletion {
                        word: i.word.to_string(),
                        kind: i.kind.to_string(),
                        menu: i.menu.to_string(),
                        info: i.info.to_string(),
                    })
                    .collect(),
            ),
            ..DisplayWidget::default()
        });
    }
    if let Some(tabline) = &state.tabline {
        widgets.push(DisplayWidget {
            kind: "tabs".into(),
            grid: 1,
            row: 0.,
            col: 0.,
            selected: tabline
                .tabs
                .iter()
                .position(|t| t.tab == tabline.current)
                .and_then(|n| i64::try_from(n).ok())
                .unwrap_or(-1),
            items: tabline.tabs.iter().map(|t| t.name.to_string()).collect(),
            handles: tabline.tabs.iter().map(|t| t.tab.0).collect(),
            ..DisplayWidget::default()
        });
        widgets.push(DisplayWidget {
            kind: "buffers".into(),
            selected: tabline
                .buffers
                .iter()
                .position(|b| Some(b.buffer) == tabline.current_buffer)
                .and_then(|n| i64::try_from(n).ok())
                .unwrap_or(-1),
            items: tabline.buffers.iter().map(|b| b.name.to_string()).collect(),
            handles: tabline.buffers.iter().map(|b| b.buffer.0).collect(),
            ..DisplayWidget::default()
        });
    }

    (widgets, has_messages)
}

fn current_messages<'a>(
    messages: &'a Messages,
    dismissed: Option<&'a Messages>,
) -> impl Iterator<Item = &'a Message> {
    let previous = dismissed.map_or(&[][..], |messages| messages.visible.as_slice());
    // Neovim updates identified messages in place and removes oldest entries
    // at the configured bound. Align the retained prefix once, then compare in
    // order, without allocating another ID collection or scanning per message.
    let offset = messages
        .visible
        .first()
        .and_then(|message| previous.iter().position(|old| old.id == message.id))
        .unwrap_or(previous.len());
    // Undo/redo reports describe the latest change, including when multiple
    // input steps are coalesced before the next delivered frame.
    let undo = messages
        .visible
        .iter()
        .rposition(|message| &*message.kind == "undo");
    messages
        .visible
        .iter()
        .enumerate()
        .filter_map(move |(index, message)| {
            if &*message.kind == "undo" && Some(index) != undo {
                return None;
            }
            let unchanged = previous
                .get(offset.saturating_add(index))
                .is_some_and(|old| {
                    old.id == message.id
                        && old.kind == message.kind
                        && old.content == message.content
                        && old.history == message.history
                        && old.trigger == message.trigger
                });
            (!unchanged).then_some(message)
        })
}

fn chunk(c: &Chunk) -> DisplayChunk {
    DisplayChunk {
        text: c.text.to_string(),
        highlight: c.highlight.0,
    }
}

pub(super) fn cmdline_chunks(cmdline: &Cmdline) -> (Vec<DisplayChunk>, usize) {
    let mut prefix = cmdline.firstc.to_string();
    prefix.push_str(&cmdline.prompt);
    prefix.extend(iter::repeat_n(' ', cmdline.indent));
    let prefix_len = prefix.len();
    let mut chunks = vec![DisplayChunk {
        text: prefix,
        highlight: 0,
    }];
    let mut special = cmdline.special.as_ref();
    let mut remaining = cmdline.pos;
    let mut overwrite_next = false;
    for c in &cmdline.content {
        let mut text = c.text.as_ref();
        if overwrite_next && let Some(first) = text.chars().next() {
            text = text.get(first.len_utf8()..).unwrap_or_default();
            overwrite_next = false;
        }
        if let Some((s, shift)) = special {
            if let (Some(before), Some(after)) = (text.get(..remaining), text.get(remaining..)) {
                chunks.push(DisplayChunk {
                    text: before.to_owned(),
                    highlight: c.highlight.0,
                });
                chunks.push(DisplayChunk {
                    text: s.to_string(),
                    highlight: c.highlight.0,
                });
                text = after;
                if !shift {
                    if let Some(first) = text.chars().next() {
                        text = text.get(first.len_utf8()..).unwrap_or_default();
                    } else {
                        overwrite_next = true;
                    }
                }
                special = None;
            } else {
                remaining = remaining.saturating_sub(text.len());
            }
        }
        if !text.is_empty() {
            chunks.push(DisplayChunk {
                text: text.to_owned(),
                highlight: c.highlight.0,
            });
        }
    }
    if let Some((s, _)) = special
        && remaining == 0
    {
        chunks.push(DisplayChunk {
            text: s.to_string(),
            highlight: 0,
        });
    }
    (chunks, prefix_len)
}

fn text_widget(kind: &str, content: &[Chunk]) -> DisplayWidget {
    DisplayWidget {
        kind: kind.into(),
        grid: 1,
        row: 0.,
        col: 0.,
        selected: -1,
        chunks: content.iter().map(chunk).collect(),
        ..DisplayWidget::default()
    }
}
