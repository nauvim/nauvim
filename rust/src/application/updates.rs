use crate::api::display::{DisplayWindow, UiUpdate};

use nauvim_core::{ResourceHandle, WebviewPosition};
use tokio::sync::mpsc;
use tokio::time::Duration;
use tokio_util::sync::CancellationToken;

#[derive(Clone)]
pub(super) struct Updates {
    pub(super) sender: mpsc::Sender<UiUpdate>,
    pub(super) stop: CancellationToken,
}

impl Updates {
    pub(super) async fn send(&self, update: UiUpdate) -> Result<(), ()> {
        tokio::select! {
            biased;
            () = self.stop.cancelled() => Err(()),
            result = self.sender.send(update) => result.map_err(|_| ()),
        }
    }

    // Final diagnostics must survive the shutdown cancellation token. A bounded
    // wait also lets close() finish when Flutter has already lost its subscriber.
    pub(super) async fn final_update(&self, update: UiUpdate) {
        if let Err(e) = self
            .sender
            .send_timeout(update, Duration::from_secs(1))
            .await
            && let Some(message) = e.into_inner().message
        {
            eprintln!("Nauvim: {message}");
        }
    }
}

pub(super) fn message(kind: &str, message: Option<String>) -> UiUpdate {
    UiUpdate {
        kind: kind.into(),
        message,
        ..UiUpdate::default()
    }
}

pub(super) fn close_window(handle: ResourceHandle) -> UiUpdate {
    UiUpdate {
        kind: "close_webview".into(),
        window: Some(DisplayWindow {
            handle: handle.get(),
            url: String::new(),
            grid: 0,
            top: 0,
            left: 0,
            height: 0,
            width: 0,
        }),
        ..UiUpdate::default()
    }
}

pub(super) fn open_window(
    handle: ResourceHandle,
    url: String,
    position: WebviewPosition,
) -> UiUpdate {
    UiUpdate {
        kind: "open_webview".into(),
        window: Some(DisplayWindow {
            handle: handle.get(),
            url,
            grid: position.grid.0,
            top: position.top,
            left: position.left,
            height: position.height,
            width: position.width,
        }),
        ..UiUpdate::default()
    }
}
