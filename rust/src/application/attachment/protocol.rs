use crate::application::size::GridSize;
use crate::application::updates::{Updates, message};

use nauvim_core::{Client, Engine, Error as CoreError};
use nvim_rpc_ui::{ClientError, api};
use tokio::time::{Duration, timeout};

use std::fmt;

#[derive(Debug)]
pub(in crate::application) enum Error {
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
pub(in crate::application) async fn synchronize(
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
            redraw_tabs(&client).await
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

async fn redraw_tabs(client: &Client) -> Result<(), Error> {
    // workaround (#18): Neovim can reuse an inactive tab's grid without
    // announcing its size to the new UI. Redraw each tab with multigrid off
    // to free those grids. nvim_win_call preserves the selected tab.
    const REDRAW_TABS: &str = r#"
local api = vim.api
local active = api.nvim_get_current_tabpage()
for _, tab in ipairs(api.nvim_list_tabpages()) do
    if tab ~= active then
        api.nvim_win_call(api.nvim_tabpage_get_win(tab), function()
            api.nvim__redraw({flush = true})
        end)
    end
end
api.nvim__redraw({valid = false, flush = true})
return true
"#;

    client
        .nvim()
        .request::<api::NvimExecLua, bool>((REDRAW_TABS, ()))
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
