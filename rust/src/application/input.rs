use super::updates::{Updates, message};

use nauvim_core::Engine;
use nvim_rpc_ui::{Buffer, Tabpage};
use tokio::sync::{mpsc, watch};
use tokio_util::sync::CancellationToken;

use std::future::{Future, pending};
use std::pin::Pin;

pub(super) enum Input {
    Keys(String),
    Paste,
    Focus(bool),
    Popup(i64),
    Tab(i64),
    Buffer(i64),
}

pub(super) struct QueuedInput {
    pub(super) epoch: CancellationToken,
    pub(super) input: Input,
}

impl QueuedInput {
    pub(super) fn into_current(self) -> Option<Input> {
        (!self.epoch.is_cancelled()).then_some(self.input)
    }
}

pub(super) fn start_input(
    engine: &Engine,
    input: Input,
    updates: Updates,
) -> Option<impl Future<Output = ()> + use<>> {
    let client = engine.client();
    let paste = matches!(input, Input::Paste).then(|| engine.paste());
    if client.is_none() && paste.is_none() {
        return None;
    }
    Some(async move {
        if let Some(paste) = paste {
            // Core reports paste errors through EngineEvent::Error.
            let _ = paste.await;
            return;
        }
        let Some(client) = client else { return };
        let result = match input {
            Input::Keys(keys) => client.input(&keys).await,
            Input::Focus(focused) => client.focus(focused).await,
            Input::Popup(index) => client.select_popupmenu_item(index, true, true).await,
            Input::Tab(tabpage) => client.set_current_tabpage(Tabpage(tabpage)).await,
            Input::Buffer(buffer) => client.set_current_buffer(Buffer(buffer)).await,
            Input::Paste => return,
        };
        if let Err(e) = result {
            let _ = updates.send(message("error", Some(e.to_string()))).await;
        }
    })
}

pub(super) async fn completed<F: Future<Output = ()>>(task: Pin<&mut Option<F>>) {
    match task.as_pin_mut() {
        Some(task) => task.await,
        None => pending().await,
    }
}

pub(super) fn reset_input<F>(
    task: Pin<&mut Option<F>>,
    input: &mut mpsc::Receiver<QueuedInput>,
    epoch: &watch::Sender<CancellationToken>,
) {
    // A reserved channel permit can outlive the drain below. Cancelled stamps
    // remain invalid even if that sender enqueues after the next attachment.
    epoch.send_replace(CancellationToken::new()).cancel();
    stop_input(task, input);
}

pub(super) fn stop_input<F>(
    mut task: Pin<&mut Option<F>>,
    input: &mut mpsc::Receiver<QueuedInput>,
) {
    task.set(None);
    while input.try_recv().is_ok() {}
}
