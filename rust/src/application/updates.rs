use crate::api::display::{DisplayWebview, DisplayWindow, UiUpdate};

use nauvim_core::{ResourceHandle, WebviewPosition, WebviewWindow};
use tokio::sync::mpsc;
use tokio::time::Duration;
use tokio_util::sync::CancellationToken;

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

pub(super) fn window_action(kind: &str, handle: ResourceHandle) -> UiUpdate {
    UiUpdate {
        kind: kind.into(),
        window: Some(DisplayWindow {
            handle: handle.get(),
            ..DisplayWindow::default()
        }),
        ..UiUpdate::default()
    }
}

pub(super) fn open_window(
    handle: ResourceHandle,
    url: String,
    position: WebviewPosition,
    focus: bool,
    focusable: bool,
    window: WebviewWindow,
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
            focus,
            focusable,
            webview: Some(DisplayWebview::new(window)),
        }),
        ..UiUpdate::default()
    }
}
