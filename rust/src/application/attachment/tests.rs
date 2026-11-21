use super::*;

use nvim_rpc_ui::{Cell, Damage, Grid, GridId, Row, State, WindowViewport};

use std::sync::Arc;

fn frame(sequence: u64, events: Vec<Event>) -> Frame {
    Frame {
        sequence,
        state: Arc::new(State {
            grids: Arc::new(BTreeMap::from([(
                GridId(2),
                Arc::new(Grid {
                    width: 1,
                    height: 1,
                    rows: vec![Arc::new(Row {
                        cells: vec![Cell::default()],
                        wrap: false,
                    })],
                }),
            )])),
            viewports: Arc::new(BTreeMap::from([(
                GridId(2),
                WindowViewport {
                    window: Window(1000),
                    ..WindowViewport::default()
                },
            )])),
            ..State::default()
        }),
        damage: Damage::default(),
        events,
    }
}

#[test]
fn waits_for_completed_repaint_and_preserves_event_order() {
    let mut attachment = Attachment::Pending;
    let mut presenter = Presenter::new();
    attachment.refresh(frame(1, vec![Event::Bell]));

    assert!(!attachment.accepts_input());
    assert!(
        attachment
            .frame(frame(2, vec![Event::VisualBell]), &mut presenter)
            .unwrap()
            .is_none()
    );
    let marker = Event::Unknown {
        name: READY.into(),
        args: vec![
            Value::Array(vec![Value::Int(1000), Value::Int(1), Value::Int(2)].into()),
            Value::Array(vec![Value::Uint(1000), Value::Int(3), Value::Int(7)].into()),
        ],
    };
    let ready = attachment
        .frame(
            frame(3, vec![marker, Event::SetTitle("restored".into())]),
            &mut presenter,
        )
        .unwrap()
        .unwrap();

    assert!(attachment.accepts_input());
    assert!(ready.damage.full);
    assert!(
        matches!(ready.events.as_slice(), [Event::Bell, Event::VisualBell, Event::SetTitle(title)] if &**title == "restored")
    );
    let projected = presenter.frame(ready);
    let grid = projected.grids.iter().find(|g| g.id == 2).unwrap();
    assert!(!grid.hidden);
    assert_eq!((grid.row, grid.col), (3.0, 7.0));
}

#[test]
fn malformed_marker_leaves_positions_unrestored() {
    let mut attachment = Attachment::Pending;
    let mut presenter = Presenter::new();
    attachment.refresh(frame(1, Vec::new()));

    let marker = Event::Unknown {
        name: READY.into(),
        args: vec![
            Value::Array(vec![Value::Int(1000), Value::Int(3), Value::Int(7)].into()),
            Value::Nil,
        ],
    };
    let result = attachment.frame(frame(2, vec![marker]), &mut presenter);
    assert!(matches!(result, Err(ProtocolError::Invalid { event, .. }) if event == READY));

    let projected = presenter.frame(frame(3, Vec::new()));
    let grid = projected.grids.iter().find(|g| g.id == 2).unwrap();
    assert!(grid.hidden);
}

#[test]
fn rejects_malformed_repaint_positions() {
    for value in [
        Value::Nil,
        Value::Array(Vec::new().into()),
        Value::Array(vec![Value::Int(1000), Value::Int(-1), Value::Int(0)].into()),
    ] {
        assert!(
            matches!(position(&value), Err(ProtocolError::Invalid { event, .. }) if event == READY)
        );
    }
}
