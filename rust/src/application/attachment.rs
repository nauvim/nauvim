use super::checkpoints::Checkpoints;
use super::size::GridSize;

use nauvim_core::{Checkpoint, Engine, Error};
use nvim_rpc_ui::api;
use tokio::task::spawn_blocking;
use tokio::time::{Duration, timeout};

use std::ptr;

pub(super) enum Attachment {
    Waiting,
    Connecting(Attempt),
    Ready(Option<Session>),
}

impl Attachment {
    pub(super) fn observe(&mut self, engine: &Engine) {
        if let Self::Ready(Some(session)) = self {
            session.observe(engine);
        }
    }
}

pub(super) struct Attempt {
    pub(super) alias: Option<String>,
    pub(super) dimensions: GridSize,
    pub(super) identity: Identity,
}

pub(super) enum Identity {
    Discovering,
    Fresh,
    Restoring(String),
    Verified(Option<String>),
}

pub(super) struct Session {
    token: String,
    latest: Option<Checkpoint>,
    saved: Option<Checkpoint>,
    reported_error: bool,
}

impl Session {
    pub(super) fn new(token: String) -> Self {
        Self {
            token,
            latest: None,
            saved: None,
            reported_error: false,
        }
    }

    fn observe(&mut self, engine: &Engine) {
        if let Some(checkpoint) = engine.checkpoint() {
            self.latest = Some(checkpoint);
        }
    }

    pub(super) async fn save(&mut self, store: &Checkpoints) -> Option<String> {
        let checkpoint = self.latest.as_ref()?;
        if self
            .saved
            .as_ref()
            .is_some_and(|saved| ptr::eq(saved.state(), checkpoint.state()))
        {
            return None;
        }

        let store = store.clone();
        let token = self.token.clone();
        let checkpoint = checkpoint.clone();
        let result = spawn_blocking(move || {
            store.save(&token, &checkpoint)?;
            Ok::<_, super::checkpoints::Error>(checkpoint)
        })
        .await;

        let error = match result {
            Ok(Ok(saved)) => {
                self.saved = Some(saved);
                self.reported_error = false;
                return None;
            }
            Ok(Err(e)) => e.to_string(),
            Err(e) => e.to_string(),
        };
        (!std::mem::replace(&mut self.reported_error, true))
            .then(|| format!("Save UI checkpoint: {error}"))
    }
}

pub(super) async fn session_token(engine: &Engine) -> Result<String, Error> {
    const SESSION: &str = r#"
local key = 'nauvim_flutter_checkpoint_session'
local token = rawget(_G, key)
if token == nil then
    local bytes, err = vim.uv.random(16)
    if bytes == nil then error(err) end
    token = (bytes:gsub('.', function(byte) return string.format('%02x', byte:byte()) end))
    rawset(_G, key, token)
end
return token
"#;

    let client = engine
        .client()
        .ok_or_else(|| Error::Message("No host Neovim is attached".into()))?;
    let token = timeout(
        Duration::from_secs(2),
        client
            .nvim()
            .request::<api::NvimExecLua, String>((SESSION, ())),
    )
    .await
    .map_err(|_| Error::Timeout("Identify Neovim for UI checkpoint"))??;

    if token.len() != 32 || !token.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(Error::Message("Invalid Neovim session token".into()));
    }
    Ok(token)
}
