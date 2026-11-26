use super::updates::{Updates, message};

use nauvim_core::{Client, Engine};
use nvim_rpc_ui::{Buffer, Tabpage};
use tokio::sync::{mpsc, watch};
use tokio_util::sync::CancellationToken;

use std::future::{Future, pending};
use std::pin::Pin;
use std::sync::Arc;

pub(super) enum Input {
    Paste,
    Host(HostInput),
}

pub(super) enum HostInput {
    Keys(String),
    Focus(bool),
    Popup(i64),
    Tab(Tabpage),
    Buffer(Buffer),
}

pub(super) struct QueuedInput {
    pub(super) epoch: Arc<CancellationToken>,
    pub(super) input: Input,
}

impl QueuedInput {
    pub(super) fn into_current(self) -> Option<Input> {
        (!self.epoch.is_cancelled()).then_some(self.input)
    }
}

pub(super) fn start_input<'a>(
    engine: &Engine,
    input: Input,
    updates: &'a Updates,
) -> Option<impl Future<Output = ()> + use<'a>> {
    enum Request<P> {
        Paste(P),
        Host(Client, HostInput),
    }

    let request = match input {
        Input::Paste => Request::Paste(engine.paste()),
        Input::Host(input) => Request::Host(engine.client()?, input),
    };
    Some(async move {
        let (client, input) = match request {
            Request::Paste(paste) => {
                // Core reports paste errors through EngineEvent::Error.
                let _ = paste.await;
                return;
            }
            Request::Host(client, input) => (client, input),
        };
        let result = match input {
            HostInput::Keys(keys) => client.input(&keys).await,
            HostInput::Focus(focused) => client.focus(focused).await,
            HostInput::Popup(index) => client.select_popupmenu_item(index, true, true).await,
            HostInput::Tab(tabpage) => client.set_current_tabpage(tabpage).await,
            HostInput::Buffer(buffer) => client.set_current_buffer(buffer).await,
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
    epoch: &watch::Sender<Arc<CancellationToken>>,
) {
    // A reserved channel permit can outlive the drain below. Cancelled stamps
    // remain invalid even if that sender enqueues after the next attachment.
    epoch
        .send_replace(Arc::new(CancellationToken::new()))
        .cancel();
    stop_input(task, input);
}

pub(super) fn stop_input<F>(
    mut task: Pin<&mut Option<F>>,
    input: &mut mpsc::Receiver<QueuedInput>,
) {
    task.set(None);
    while input.try_recv().is_ok() {}
}
