use super::grids::placement;
use super::widgets::cmdline_chunks;
use super::*;
use crate::api::display::DisplayFrame;

use nvim_rpc_ui::{
    Buffer, BufferItem, Cell, Chunk, Cmdline, CompletionItem, Cursor, Damage, Grid, GridId,
    GridPlacement, GridPlacementKind, Highlight, HighlightAttributes, HighlightId, Message, Mode,
    PopupAnchor, Popupmenu, Row, Tab, Tabline, Tabpage, Value, Window, WindowViewport,
};

use std::collections::BTreeMap;

fn frame(state: Arc<State>) -> Frame {
    Frame {
        sequence: 0,
        state,
        damage: Damage::default(),
        events: Vec::new(),
    }
}

fn undo_message(id: i64, text: &str) -> Message {
    Message {
        kind: Arc::from("undo"),
        content: vec![Chunk {
            highlight: HighlightId(0),
            text: Arc::from(text),
            hl_id: None,
        }],
        history: true,
        id: Value::Int(id),
        trigger: Arc::from(""),
    }
}

fn shown_messages(frame: &DisplayFrame) -> Vec<&str> {
    frame
        .widgets
        .as_ref()
        .unwrap()
        .iter()
        .filter(|widget| widget.kind == "message")
        .flat_map(|widget| widget.chunks.iter().map(|chunk| chunk.text.as_str()))
        .collect()
}

#[test]
fn dismisses_messages_on_input_without_mutating_history_or_replaying_events() {
    let mut state = State {
        grids: Arc::new(BTreeMap::from([(GridId(1), grid(&["abc"]))])),
        messages: Arc::new(Messages {
            visible: vec![
                undo_message(1, "first undo"),
                undo_message(2, "second undo"),
            ],
            showcmd: vec![Chunk {
                highlight: HighlightId(0),
                text: Arc::from("g"),
                hl_id: None,
            }],
            ..Messages::default()
        }),
        ..State::default()
    };
    let mut presenter = Presenter::new();
    assert!(presenter.dismiss_messages().is_none());
    let mut source = frame(Arc::new(state.clone()));
    source.events.push(Event::Bell);
    let first = presenter.frame(source);
    assert_eq!(shown_messages(&first), ["second undo"]);
    let cleared = presenter.dismiss_messages().unwrap();
    assert!(shown_messages(&cleared).is_empty());
    assert!(cleared.rows.is_empty());
    assert!(cleared.events.is_empty());
    assert!(!cleared.full);
    assert!(
        cleared
            .widgets
            .as_ref()
            .unwrap()
            .iter()
            .any(|w| w.kind == "status")
    );
    assert_eq!(state.messages.visible.len(), 2);
    assert!(state.messages.visible.iter().all(|message| message.history));
    assert!(presenter.dismiss_messages().is_none());
    assert!(
        presenter
            .frame(frame(Arc::new(state.clone())))
            .widgets
            .is_none()
    );

    Arc::make_mut(&mut state.messages)
        .visible
        .push(undo_message(3, "third undo"));
    let update = presenter.frame(frame(Arc::new(state.clone())));
    assert_eq!(shown_messages(&update), ["third undo"]);
    presenter.dismiss_messages();
    let messages = &mut Arc::make_mut(&mut state.messages).visible;
    messages.remove(0);
    messages.push(undo_message(4, "fourth undo"));
    let update = presenter.frame(frame(Arc::new(state.clone())));
    assert_eq!(shown_messages(&update), ["fourth undo"]);

    presenter.reset();
    let update = presenter.frame(frame(Arc::new(state)));
    assert_eq!(shown_messages(&update), ["fourth undo"]);
}

#[test]
fn coalesces_undo_reports_without_removing_other_messages() {
    let mut error = undo_message(2, "operation failed");
    error.kind = Arc::from("emsg");
    let state = State {
        messages: Arc::new(Messages {
            visible: vec![
                undo_message(1, "old undo"),
                error,
                undo_message(3, "latest undo"),
            ],
            ..Messages::default()
        }),
        ..State::default()
    };
    let mut presenter = Presenter::new();
    let update = presenter.frame(frame(Arc::new(state)));
    assert_eq!(shown_messages(&update), ["operation failed", "latest undo"]);
}

#[test]
fn displays_changed_identified_messages_after_dismissal() {
    let mut state = State {
        messages: Arc::new(Messages {
            visible: vec![undo_message(1, "first"), undo_message(2, "old")],
            ..Messages::default()
        }),
        ..State::default()
    };
    let mut presenter = Presenter::new();
    presenter.frame(frame(Arc::new(state.clone())));
    presenter.dismiss_messages();
    let message = Arc::make_mut(&mut state.messages)
        .visible
        .get_mut(1)
        .unwrap();
    *message = undo_message(2, "new");
    let update = presenter.frame(frame(Arc::new(state)));
    assert_eq!(shown_messages(&update), ["new"]);
}

#[test]
fn preserves_optional_default_colors_without_selecting_a_palette() {
    let mut presenter = Presenter::new();
    for (foreground, background) in [
        (None, None),
        (Some(0), None),
        (None, Some(0xffffff)),
        (Some(0x123456), Some(0xabcdef)),
        (None, None),
    ] {
        let mut state = State::default();
        state.default_colors.foreground = foreground;
        state.default_colors.background = background;
        let update = presenter.frame(frame(Arc::new(state)));
        assert_eq!(update.foreground, foreground);
        assert_eq!(update.background, background);
    }
}

#[test]
fn sends_changed_rows_and_retains_previous_snapshot() {
    let row = Arc::new(Row {
        cells: vec![
            Cell {
                text: Arc::from("界"),
                highlight: HighlightId(2),
            },
            Cell {
                text: Arc::from(""),
                highlight: HighlightId(2),
            },
        ],
        wrap: false,
    });
    let state = Arc::new(State {
        grids: Arc::new(BTreeMap::from([(
            GridId(1),
            Arc::new(Grid {
                width: 2,
                height: 1,
                rows: vec![row],
            }),
        )])),
        ..State::default()
    });
    let mut p = Presenter::new();
    let first = p.frame(frame(Arc::clone(&state)));
    assert!(first.full);
    assert_eq!(first.rows.len(), 1);
    assert_eq!(first.rows[0].cells[0].text, "界");
    assert_eq!(first.rows[0].cells[1].text, "");
    let second = p.frame(frame(state));
    assert!(!second.full);
    assert!(second.rows.is_empty());
    assert!(second.widgets.is_none());
}

fn grid(lines: &[&str]) -> Arc<Grid> {
    Arc::new(Grid {
        width: lines.first().map_or(0, |s| s.chars().count()),
        height: lines.len(),
        rows: lines
            .iter()
            .map(|s| {
                Arc::new(Row {
                    cells: s
                        .chars()
                        .map(|c| Cell {
                            text: Arc::from(c.to_string()),
                            highlight: HighlightId(0),
                        })
                        .collect(),
                    wrap: false,
                })
            })
            .collect(),
    })
}

#[test]
fn sends_only_changed_rows_when_damage_encloses_unchanged_rows() {
    let mut state = State {
        grids: Arc::new(BTreeMap::from([(GridId(1), grid(&["aa", "bb", "cc"]))])),
        ..State::default()
    };
    let mut presenter = Presenter::new();
    presenter.frame(frame(Arc::new(state.clone())));
    let rows =
        &mut Arc::make_mut(Arc::make_mut(&mut state.grids).get_mut(&GridId(1)).unwrap()).rows;
    rows[0] = grid(&["xx"]).rows[0].clone();
    rows[2] = grid(&["yy"]).rows[0].clone();
    let update = presenter.frame(frame(Arc::new(state)));
    assert_eq!(
        update.rows.iter().map(|r| r.row).collect::<Vec<_>>(),
        [0, 2]
    );
    assert_eq!(update.rows[0].cells[0].text, "x");
    assert_eq!(update.rows[1].cells[0].text, "y");
}

#[test]
fn visual_style_changes_repaint_without_copying_shared_cell_text() {
    let mut state = State {
        grids: Arc::new(BTreeMap::from([(GridId(1), grid(&["abc"]))])),
        ..State::default()
    };
    let mut presenter = Presenter::new();
    presenter.frame(frame(Arc::new(state.clone())));
    state.title = Arc::from("updated title");
    state.highlights = Arc::new(BTreeMap::from([(
        HighlightId(9),
        Highlight {
            rgb: HighlightAttributes {
                underdotted: true,
                ..HighlightAttributes::default()
            },
            ..Highlight::default()
        },
    )]));
    let update = presenter.frame(frame(Arc::new(state)));
    assert!(update.full);
    assert!(update.rows.is_empty());
    assert_eq!(update.highlights[0].decoration, "underdotted");
    assert_eq!(update.title, "updated title");
}

#[test]
fn drops_removed_grids_and_sends_complete_rows_after_reset() {
    let state = Arc::new(State {
        grids: Arc::new(BTreeMap::from([
            (GridId(1), grid(&["a"])),
            (GridId(2), grid(&["b"])),
        ])),
        ..State::default()
    });
    let mut presenter = Presenter::new();
    presenter.frame(frame(Arc::clone(&state)));
    let mut changed = state.as_ref().clone();
    Arc::make_mut(&mut changed.grids).remove(&GridId(2));
    let update = presenter.frame(frame(Arc::new(changed)));
    assert_eq!(update.removed_grids, [2]);
    presenter.reset();
    let update = presenter.frame(frame(state));
    assert!(update.full);
    assert_eq!(update.rows.len(), 2);
}

#[test]
fn preserves_repeated_events_in_receive_order() {
    let state = Arc::new(State::default());
    let mut source = frame(Arc::clone(&state));
    source.events = vec![
        Event::Bell,
        Event::SetTitle(Arc::from("first")),
        Event::RpcError {
            kind: 0,
            message: Arc::from("failure"),
        },
        Event::VisualBell,
        Event::Bell,
    ];
    let mut presenter = Presenter::new();
    let update = presenter.frame(source);
    assert_eq!(
        update
            .events
            .iter()
            .map(|e| (e.kind.as_str(), e.text.as_str()))
            .collect::<Vec<_>>(),
        [
            ("bell", ""),
            ("title", "first"),
            ("error", "failure"),
            ("visual_bell", ""),
            ("bell", ""),
        ]
    );
    assert!(presenter.frame(frame(state)).events.is_empty());
}

fn cmdline() -> Cmdline {
    Cmdline {
        content: vec![
            Chunk {
                text: Arc::from("界"),
                highlight: HighlightId(3),
                hl_id: None,
            },
            Chunk {
                text: Arc::from("aéz"),
                highlight: HighlightId(4),
                hl_id: None,
            },
        ],
        pos: 3,
        firstc: Arc::from(":"),
        prompt: Arc::from("é>"),
        indent: 2,
        level: 1,
        hl_id: None,
        special: None,
    }
}

#[test]
fn commandline_positions_include_prefix_and_count_utf8_bytes() {
    let mut state = State {
        cmdlines: Arc::new(BTreeMap::from([(1, Arc::new(cmdline()))])),
        popupmenu: Some(Arc::new(Popupmenu {
            anchor: PopupAnchor::Cmdline { byte_offset: 3 },
            selected: None,
            items: vec![CompletionItem {
                word: Arc::from("test"),
                kind: Arc::from("v"),
                menu: Arc::from("menu"),
                info: Arc::from("info"),
            }],
        })),
        ..State::default()
    };
    let mut presenter = Presenter::new();
    let update = presenter.frame(frame(Arc::new(state.clone())));
    let widgets = update.widgets.unwrap();
    let command = widgets.iter().find(|w| w.kind == "cmdline").unwrap();
    assert!(command.completions.is_none());
    assert_eq!(command.selected, 9);
    assert_eq!(
        command
            .chunks
            .iter()
            .map(|c| c.text.as_str())
            .collect::<String>(),
        ":é>  界aéz"
    );
    let popup = widgets.iter().find(|w| w.kind == "cmdline_popup").unwrap();
    assert_eq!(popup.col, 9.);
    Arc::make_mut(Arc::make_mut(&mut state.cmdlines).get_mut(&1).unwrap()).special =
        Some((Arc::from("^"), false));
    let update = presenter.frame(frame(Arc::new(state)));
    let widgets = update.widgets.unwrap();
    let command = widgets.iter().find(|w| w.kind == "cmdline").unwrap();
    assert_eq!(command.selected, 9);
    assert_eq!(
        command
            .chunks
            .iter()
            .map(|c| c.text.as_str())
            .collect::<String>(),
        ":é>  界^éz"
    );
}

#[test]
fn preserves_completion_metadata_without_formatting_or_trimming() {
    for anchor in [
        PopupAnchor::Grid {
            grid: GridId(1),
            row: 2,
            col: 3,
        },
        PopupAnchor::Cmdline { byte_offset: 3 },
    ] {
        let state = State {
            grids: Arc::new(BTreeMap::from([(
                GridId(1),
                grid(&["....", "....", "...."]),
            )])),
            cmdlines: Arc::new(BTreeMap::from([(1, Arc::new(cmdline()))])),
            popupmenu: Some(Arc::new(Popupmenu {
                anchor,
                selected: Some(1),
                items: vec![
                    CompletionItem {
                        word: Arc::from(" 界 "),
                        kind: Arc::from(" f "),
                        menu: Arc::from("\t source "),
                        info: Arc::from("first line\n second line "),
                    },
                    CompletionItem {
                        word: Arc::from("plain"),
                        kind: Arc::from(""),
                        menu: Arc::from(""),
                        info: Arc::from(""),
                    },
                ],
            })),
            ..State::default()
        };
        let mut presenter = Presenter::new();
        let update = presenter.frame(frame(Arc::new(state)));
        let widgets = update.widgets.unwrap();
        let popup = widgets
            .iter()
            .find(|w| w.kind == "popup" || w.kind == "cmdline_popup")
            .unwrap();
        assert_eq!(popup.selected, 1);
        assert!(popup.items.is_empty());
        assert!(popup.chunks.is_empty());
        assert_eq!(
            popup
                .completions
                .as_ref()
                .unwrap()
                .iter()
                .map(|item| (
                    item.word.as_str(),
                    item.kind.as_str(),
                    item.menu.as_str(),
                    item.info.as_str(),
                ))
                .collect::<Vec<_>>(),
            [
                (" 界 ", " f ", "\t source ", "first line\n second line "),
                ("plain", "", "", ""),
            ]
        );
    }
}

#[test]
fn special_commandline_characters_preserve_highlights_and_shift_semantics() {
    for (shift, expected) in [(true, ":é>  界^aéz"), (false, ":é>  界^éz")] {
        let mut cmdline = cmdline();
        cmdline.special = Some((Arc::from("^"), shift));
        let (chunks, prefix_len) = cmdline_chunks(&cmdline);
        assert_eq!(prefix_len, 6);
        assert_eq!(
            chunks.iter().map(|c| c.text.as_str()).collect::<String>(),
            expected
        );
        assert_eq!(chunks.last().unwrap().highlight, 4);
    }
}

#[test]
fn preserves_tabpage_and_buffer_handles() {
    let state = Arc::new(State {
        tabline: Some(Arc::new(Tabline {
            current: Tabpage(4),
            current_buffer: Some(Buffer(8)),
            tabs: vec![Tab {
                tab: Tabpage(4),
                name: Arc::from("tab"),
            }],
            buffers: vec![BufferItem {
                buffer: Buffer(8),
                name: Arc::from("buf"),
            }],
        })),
        ..State::default()
    });
    let widgets = Presenter::new().frame(frame(state)).widgets.unwrap();
    let tabs = widgets.iter().find(|w| w.kind == "tabs").unwrap();
    let buffers = widgets.iter().find(|w| w.kind == "buffers").unwrap();
    assert_eq!(tabs.handles, [4]);
    assert_eq!(tabs.selected, 0);
    assert_eq!(buffers.handles, [8]);
    assert_eq!(buffers.selected, 0);
}

#[test]
fn resolves_floating_anchors_and_hides_cyclic_placements() {
    let mut state = State {
        grids: Arc::new(BTreeMap::from([
            (GridId(1), grid(&["root"])),
            (GridId(2), grid(&["base"])),
            (GridId(3), grid(&["xx", "xx"])),
        ])),
        placements: Arc::new(BTreeMap::from([
            (
                GridId(2),
                GridPlacement {
                    hidden: false,
                    kind: GridPlacementKind::Normal {
                        window: Window(2),
                        row: 5,
                        col: 7,
                        width: 4,
                        height: 1,
                    },
                },
            ),
            (
                GridId(3),
                GridPlacement {
                    hidden: false,
                    kind: GridPlacementKind::Floating {
                        window: Window(3),
                        anchor: Arc::from("SE"),
                        anchor_grid: GridId(2),
                        anchor_row: 3.5,
                        anchor_col: 4.5,
                        mouse_enabled: true,
                        zindex: 50,
                        compindex: Some(9),
                        screen_row: None,
                        screen_col: None,
                    },
                },
            ),
        ])),
        ..State::default()
    };
    assert_eq!(
        placement(&state, GridId(3), state.grids.len(), &BTreeMap::new()),
        Some((6.5, 9.5, 50))
    );
    let mut presenter = Presenter::new();
    let update = presenter.frame(frame(Arc::new(state.clone())));
    assert_eq!(update.grids.iter().find(|g| g.id == 3).unwrap().order, 9);
    let GridPlacementKind::Floating { anchor_grid, .. } = &mut Arc::make_mut(&mut state.placements)
        .get_mut(&GridId(3))
        .unwrap()
        .kind
    else {
        panic!("Expected a floating grid");
    };
    *anchor_grid = GridId(3);
    let update = presenter.frame(frame(Arc::new(state)));
    assert!(update.grids.iter().find(|g| g.id == 3).unwrap().hidden);
}

#[test]
fn restores_omitted_window_positions_until_neovim_supplies_them() {
    let mut state = State {
        grids: Arc::new(BTreeMap::from([
            (GridId(1), grid(&["root"])),
            (GridId(2), grid(&["buffer"])),
        ])),
        viewports: Arc::new(BTreeMap::from([(
            GridId(2),
            WindowViewport {
                window: Window(1000),
                ..WindowViewport::default()
            },
        )])),
        ..State::default()
    };
    let mut presenter = Presenter::new();
    presenter.restore_positions(vec![WindowPosition {
        grid: GridId(2),
        window: Window(1000),
        row: 3,
        col: 7,
    }]);
    let snapshot = Arc::new(state.clone());
    let first = presenter.frame(frame(Arc::clone(&snapshot)));
    let window = first.grids.iter().find(|g| g.id == 2).unwrap();

    assert!(!window.hidden);
    assert_eq!((window.row, window.col), (3.0, 7.0));
    assert!(state.placements.is_empty());

    let unchanged = presenter.frame(frame(snapshot));

    assert!(unchanged.rows.is_empty());
    assert!(!unchanged.grids.iter().find(|g| g.id == 2).unwrap().hidden);

    Arc::make_mut(&mut state.placements).insert(
        GridId(2),
        GridPlacement {
            hidden: true,
            kind: GridPlacementKind::Normal {
                window: Window(1000),
                row: 5,
                col: 9,
                width: 6,
                height: 1,
            },
        },
    );
    let authoritative = presenter.frame(frame(Arc::new(state.clone())));
    let window = authoritative.grids.iter().find(|g| g.id == 2).unwrap();

    assert!(window.hidden);
    assert_eq!((window.row, window.col), (5.0, 9.0));
    assert!(presenter.positions.is_empty());

    Arc::make_mut(&mut state.placements).clear();
    let closed = presenter.frame(frame(Arc::new(state)));

    assert!(closed.grids.iter().find(|g| g.id == 2).unwrap().hidden);
}

#[test]
fn discards_restored_positions_on_window_replacement_and_attachment_reset() {
    let state = State {
        grids: Arc::new(BTreeMap::from([(GridId(2), grid(&["buffer"]))])),
        viewports: Arc::new(BTreeMap::from([(
            GridId(2),
            WindowViewport {
                window: Window(2000),
                ..WindowViewport::default()
            },
        )])),
        ..State::default()
    };
    let mut presenter = Presenter::new();
    presenter.restore_positions(vec![WindowPosition {
        grid: GridId(2),
        window: Window(1000),
        row: 3,
        col: 7,
    }]);
    let replaced = presenter.frame(frame(Arc::new(state.clone())));

    assert!(replaced.grids.iter().find(|g| g.id == 2).unwrap().hidden);
    assert!(presenter.positions.is_empty());

    presenter.restore_positions(vec![WindowPosition {
        grid: GridId(2),
        window: Window(2000),
        row: 3,
        col: 7,
    }]);
    presenter.reset();
    let reattached = presenter.frame(frame(Arc::new(state)));

    assert!(reattached.grids.iter().find(|g| g.id == 2).unwrap().hidden);
}

#[test]
fn default_cursor_covers_the_full_cell() {
    let state = Arc::new(State {
        cursor: Some(Cursor {
            grid: GridId(1),
            row: 0,
            col: 0,
        }),
        mode: Mode {
            cursor_style_enabled: false,
            ..Mode::default()
        },
        ..State::default()
    });
    let cursor = Presenter::new().frame(frame(state)).cursor.unwrap();
    assert_eq!(cursor.shape, "block");
    assert_eq!(cursor.percentage, 100);
}
