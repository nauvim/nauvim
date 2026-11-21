use crate::display::{Presenter, WindowPosition};

mod protocol;
pub(super) use protocol::synchronize;

use nvim_rpc_ui::{Event, Frame, GridPlacementKind, Limits, ProtocolError, Value, Window};
use tokio::time::{Duration, Instant, sleep_until};

use std::collections::BTreeMap;
use std::future::pending;
use std::iter;
use std::mem;

const READY: &str = "nauvim_attachment_ready";

pub(super) enum Attachment {
    Pending,
    Refreshing {
        frame: Frame,
        deadline: Instant,
        checked_events: usize,
    },
    Ready,
}

impl Attachment {
    pub(super) fn is_pending(&self) -> bool {
        matches!(self, Self::Pending)
    }

    pub(super) fn accepts_input(&self) -> bool {
        !matches!(self, Self::Refreshing { .. })
    }

    pub(super) fn refresh(&mut self, frame: Frame) {
        *self = Self::Refreshing {
            frame,
            deadline: Instant::now()
                .checked_add(Duration::from_secs(2))
                .unwrap_or_else(Instant::now),
            checked_events: 0,
        };
    }

    pub(super) fn frame(
        &mut self,
        next: Frame,
        presenter: &mut Presenter,
    ) -> Result<Option<Frame>, ProtocolError> {
        let Self::Refreshing {
            mut frame,
            deadline,
            checked_events,
        } = mem::replace(self, Self::Ready)
        else {
            return Ok(Some(next));
        };
        // The presenter has no previous snapshot for this attachment. Keep
        // ordered events and the latest state for its first full repaint.
        frame.coalesce(next, Limits::default().max_pending_events)?;
        let Some(args) = frame
            .events
            .iter()
            .skip(checked_events)
            .find_map(|event| match event {
                Event::Unknown { name, args } if &**name == READY => Some(args),
                _ => None,
            })
        else {
            *self = Self::Refreshing {
                checked_events: frame.events.len(),
                frame,
                deadline,
            };
            return Ok(None);
        };

        // Validate every position before changing the presenter. Later entries
        // for the same window replace earlier ones.
        let mut positions = BTreeMap::new();
        for value in args {
            let (window, row, col) = position(value)?;
            positions.insert(window, (row, col));
        }
        let state = &frame.state;
        // If a frame has more than one grid for a window, keep the highest ID.
        let mut grids = state.grids.keys().rev();
        presenter.restore_positions(iter::from_fn(|| {
            if positions.is_empty() {
                return None;
            }
            grids.find_map(|grid| {
                let window = match state.placements.get(grid).map(|p| &p.kind) {
                    Some(GridPlacementKind::Normal { window, .. }) => Some(*window),
                    _ => state.viewports.get(grid).map(|v| v.window),
                }?;
                let (row, col) = positions.remove(&window)?;
                Some(WindowPosition {
                    grid: *grid,
                    window,
                    row,
                    col,
                })
            })
        }));
        frame
            .events
            .retain(|event| !matches!(event, Event::Unknown { name, .. } if &**name == READY));
        Ok(Some(frame))
    }

    pub(super) async fn expired(&self) {
        match self {
            Self::Refreshing { deadline, .. } => sleep_until(*deadline).await,
            _ => pending().await,
        }
    }
}

fn position(value: &Value) -> Result<(Window, i64, i64), ProtocolError> {
    fn integer(value: &Value) -> Option<i64> {
        match value {
            Value::Int(value) => Some(*value),
            Value::Uint(value) => i64::try_from(*value).ok(),
            _ => None,
        }
    }

    let invalid = || ProtocolError::Invalid {
        event: READY.into(),
        reason: "invalid window position",
    };
    let Value::Array(record) = value else {
        return Err(invalid());
    };
    let [window, row, col] = record.as_ref() else {
        return Err(invalid());
    };
    let window = integer(window).filter(|n| *n > 0).ok_or_else(invalid)?;
    let row = integer(row).filter(|n| *n >= 0).ok_or_else(invalid)?;
    let col = integer(col).filter(|n| *n >= 0).ok_or_else(invalid)?;
    Ok((Window(window), row, col))
}

#[cfg(test)]
mod tests;
