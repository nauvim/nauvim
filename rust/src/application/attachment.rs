use crate::display::{Presenter, WindowPosition};

use super::size::GridSize;
use super::updates::{Updates, message};

use nauvim_core::{Client, Engine, Error as CoreError};
use nvim_rpc_ui::{
    ClientError, Event, Frame, GridPlacementKind, Limits, ProtocolError, Value, Window, api,
};
use tokio::time::{Duration, Instant, sleep_until, timeout};

use std::collections::BTreeMap;
use std::fmt;
use std::future::pending;
use std::mem;

const READY: &str = "nauvim_attachment_ready";

pub(super) enum Attachment {
    Pending,
    Refreshing { frame: Frame, deadline: Instant },
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
        } = mem::replace(self, Self::Ready)
        else {
            return Ok(Some(next));
        };
        let limits = Limits::default();
        frame.coalesce_incremental(next, limits.max_pending_events, limits.max_grids)?;
        if let Some(positions) = frame.events.iter().find_map(|event| match event {
            Event::Unknown { name, args } if &**name == READY => Some(args),
            _ => None,
        }) {
            let grids = frame
                .state
                .grids
                .keys()
                .filter_map(|id| {
                    let window = match frame.state.placements.get(id).map(|p| &p.kind) {
                        Some(GridPlacementKind::Normal { window, .. }) => Some(*window),
                        _ => frame.state.viewports.get(id).map(|v| v.window),
                    }?;
                    Some((window, *id))
                })
                .collect::<BTreeMap<_, _>>();
            let positions = positions
                .iter()
                .map(position)
                .collect::<Result<Vec<_>, _>>()?;
            presenter.restore_positions(positions.into_iter().filter_map(|(window, row, col)| {
                grids.get(&window).map(|grid| WindowPosition {
                    grid: *grid,
                    window,
                    row,
                    col,
                })
            }));
            frame
                .events
                .retain(|event| !matches!(event, Event::Unknown { name, .. } if &**name == READY));
            Ok(Some(frame))
        } else {
            *self = Self::Refreshing { frame, deadline };
            Ok(None)
        }
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

#[derive(Debug)]
pub(super) enum Error {
    Host(CoreError),
    Unavailable,
    TimedOut,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("Restore the attached editor display: ")?;
        match self {
            Self::Host(e) => e.fmt(f),
            Self::Unavailable => f.write_str("the attachment is no longer active"),
            Self::TimedOut => f.write_str("request timed out"),
        }
    }
}

// Reinitializing multigrid frees Neovim's retained normal-window caches.
// With one attached UI, changing these UI flags keeps every other capability
// unchanged, including ext_messages. Never renegotiate another attached UI.
pub(super) async fn synchronize(
    engine: &Engine,
    size: GridSize,
    updates: &Updates,
) -> Result<bool, Error> {
    let client = engine.client().ok_or(Error::Unavailable)?;
    let identify = client
        .nvim()
        .request::<api::NvimExecLua, Vec<i64>>((IDENTIFY, (engine.client_id().get(),)));
    let identity = tokio::select! {
        biased;
        () = updates.stop.cancelled() => return Ok(false),
        result = timeout(Duration::from_secs(2), identify) => result.map_err(|_| Error::TimedOut)?.map_err(|e| Error::Host(ClientError::from(e).into()))?,
    };
    let [channel, count] = identity.as_slice() else {
        return Err(Error::Unavailable);
    };
    if *channel <= 0 {
        return Ok(false);
    }

    if *count == 1 {
        let reset = async {
            option(&client, "override", false).await?;
            option(&client, "ext_multigrid", false).await?;
            resize(&client, size).await?;
            redraw(&client).await
        };
        let result = timeout(Duration::from_secs(2), reset)
            .await
            .map_err(|_| Error::TimedOut)
            .and_then(|r| r);
        // Complete restoration even if shutdown or a request timeout interrupted
        // initialization. These are this connection's UI flags, not user options.
        let restore = async {
            option(&client, "ext_multigrid", true).await?;
            option(&client, "override", true).await?;
            resize(&client, size).await
        };
        let restored = timeout(Duration::from_secs(2), restore)
            .await
            .map_err(|_| Error::TimedOut)
            .and_then(|r| r);
        if let Err(e) = result {
            if let Err(restore) = restored {
                let _ = updates
                    .send(message("error", Some(restore.to_string())))
                    .await;
            }
            return Err(e);
        }
        restored?;
    }
    let complete = client
        .nvim()
        .request::<api::NvimExecLua, bool>((COMPLETE, (*channel,)));
    let marked = timeout(Duration::from_secs(2), complete)
        .await
        .map_err(|_| Error::TimedOut)?
        .map_err(|e| Error::Host(ClientError::from(e).into()))?;
    Ok(marked && !updates.stop.is_cancelled())
}

async fn option(client: &Client, name: &str, value: bool) -> Result<(), Error> {
    client
        .nvim()
        .request::<api::NvimUiSetOption, ()>((name, value))
        .await
        .map_err(|e| Error::Host(ClientError::from(e).into()))
}

async fn resize(client: &Client, size: GridSize) -> Result<(), Error> {
    client
        .nvim()
        .request::<api::NvimUiTryResize, ()>((i64::from(size.width()), i64::from(size.height())))
        .await
        .map_err(|e| Error::Host(ClientError::from(e).into()))
}

async fn redraw(client: &Client) -> Result<(), Error> {
    client
        .nvim()
        .request::<api::NvimExecLua, bool>((
            "vim.api.nvim__redraw({valid=false,flush=true}); return true",
            (),
        ))
        .await
        .map(|_| ())
        .map_err(|e| Error::Host(ClientError::from(e).into()))
}

// A sole UI identifies its own channel even when client-info registration failed.
const IDENTIFY: &str = r#"
local uis = vim.api.nvim_list_uis()
if #uis == 1 then return {uis[1].chan, 1} end
local name = 'nauvim-client-' .. ...
for _, ui in ipairs(uis) do
    local info = vim.api.nvim_get_chan_info(ui.chan)
    if info.client and info.client.name == name then return {ui.chan, #uis} end
end
return {0, #uis}
"#;

// This private marker shares the ordered redraw stream with the completed
// repaint. RPC replies alone can precede queued UI callbacks. Pair queried
// normal-window IDs with the final frame's grid metadata.
const COMPLETE: &str = r#"
local positions = {}
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local config = vim.api.nvim_win_get_config(win)
    if not config.external and not config.hide then
        if config.relative == '' then
            local position = vim.api.nvim_win_get_position(win)
            positions[#positions + 1] = {win, position[1], position[2]}
        else
            -- Re-emit native floating placement, including anchor and stack order.
            -- An empty update retains all user-provided configuration fields.
            vim.api.nvim_win_set_config(win, {})
        end
    end
end
vim.api.nvim__redraw({valid=false,flush=true})
vim.rpcnotify(..., 'redraw', {'nauvim_attachment_ready', positions}, {'flush', {}})
return true
"#;

#[cfg(test)]
mod tests {
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
            args: vec![Value::Array(
                vec![Value::Uint(1000), Value::Int(3), Value::Int(7)].into(),
            )],
        };
        let ready = attachment
            .frame(
                frame(3, vec![marker, Event::SetTitle("restored".into())]),
                &mut presenter,
            )
            .unwrap()
            .unwrap();

        assert!(attachment.accepts_input());
        assert!(
            matches!(ready.events.as_slice(), [Event::Bell, Event::VisualBell, Event::SetTitle(title)] if &**title == "restored")
        );
        let projected = presenter.frame(ready);
        let grid = projected.grids.iter().find(|g| g.id == 2).unwrap();
        assert!(!grid.hidden);
        assert_eq!((grid.row, grid.col), (3.0, 7.0));
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
}
