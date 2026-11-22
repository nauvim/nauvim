use crate::api::display::{DisplayDestination, UiUpdate};
use crate::configuration;
use crate::display::Presenter;

use super::Command;
use super::attachment::{self, Attachment};
use super::history::History;
use super::input::{
    HostInput, Input, QueuedInput, completed, reset_input, start_input, stop_input,
};
use super::size::GridSize;
use super::updates::{Updates, message, open_window, window_action};

use nauvim_core::{Engine, EngineEvent, Error, HostSelection};
use tokio::sync::{mpsc, watch};
use tokio::time::{Duration, timeout};
use tokio_util::sync::CancellationToken;

use std::future::{Future, poll_fn};
use std::path::{Path, PathBuf};
use std::task::Poll;

pub(super) async fn run(
    path: Option<String>,
    state_path: Option<PathBuf>,
    mut commands: mpsc::Receiver<Command>,
    mut input: mpsc::Receiver<QueuedInput>,
    input_epoch: watch::Sender<CancellationToken>,
    updates: Updates,
) {
    let (config, options) = match configuration::load(path.as_deref().map(Path::new)) {
        Ok(config) => config,
        Err(e) => {
            let _ = updates.send(message("welcome", Some(e.to_string()))).await;
            return;
        }
    };

    let mut history_error = None;
    let history = match state_path
        .as_deref()
        .map_or_else(History::system, History::open)
    {
        Ok(history) => Some(history),
        Err(e) => {
            history_error = Some(format!("Open the last selected host database: {e}"));
            None
        }
    };
    let destination = history.as_ref().and_then(|history| match history.load() {
        Ok(destination) => destination,
        Err(e) => {
            history_error = Some(format!("Restore the last selected host: {e}"));
            None
        }
    });

    let startup = UiUpdate {
        kind: "ready".into(),
        hosts: config.hosts().map(str::to_owned).collect(),
        default_host: config.default_host().map(str::to_owned),
        destination: destination.map(|destination| DisplayDestination {
            alias: destination.into_alias(),
        }),
        key_bindings: options.key_bindings,
        fonts: options.fonts,
        window_options: options.window,
        ..UiUpdate::default()
    };
    if updates.send(startup).await.is_err() {
        return;
    }
    if let Some(error) = history_error {
        let _ = updates.send(message("error", Some(error))).await;
    }

    let mut engine = match Engine::new(config) {
        Ok(engine) => engine,
        Err(e) => {
            let _ = updates.send(message("welcome", Some(e.to_string()))).await;
            return;
        }
    };

    let mut presenter = Presenter::new();
    let task = None;
    tokio::pin!(task);
    let mut dimensions = GridSize::new(100, 30);
    let mut attachment = Attachment::Pending;
    let mut started = false;
    let mut reported_failure = None;

    loop {
        tokio::select! {
            () = updates.stop.cancelled() => break,
            command = commands.recv() => {
                let Some(command) = command else { break };

                let connection = match command {
                    Command::Start(size) if !started => {
                        started = true;
                        dimensions = size;
                        if let Some(host) = engine.config().startup_host() {
                            let alias = match host {
                                HostSelection::Default => None,
                                HostSelection::Alias(alias) => Some(alias),
                            };
                            remember(history.as_ref(), alias, &updates).await;
                            let _ = updates.send(connecting(alias.map(str::to_owned))).await;
                        }
                        begin(engine.start(dimensions.width(), dimensions.height())).await
                    }
                    Command::Start(..) => None,
                    Command::Connect(host, size) => {
                        started = true;
                        reported_failure = None;
                        reset_input(task.as_mut(), &mut input, &input_epoch);
                        presenter.reset();
                        attachment = Attachment::Pending;
                        dimensions = size;
                        remember(history.as_ref(), host.as_deref(), &updates).await;
                        let _ = updates.send(connecting(host.clone())).await;
                        match host {
                            Some(host) => {
                                begin(engine.connect(&host, dimensions.width(), dimensions.height())).await
                            }
                            None => {
                                begin(engine.connect_default(dimensions.width(), dimensions.height())).await
                            }
                        }
                    }
                    Command::Detach => {
                        reset_input(task.as_mut(), &mut input, &input_epoch);
                        presenter.reset();
                        attachment = Attachment::Pending;
                        if let Err(e) = engine.detach().await {
                            let _ = updates.send(message("error", Some(e.to_string()))).await;
                        }
                        None
                    }
                    Command::Resize(size) => {
                        dimensions = size;
                        resize(&mut engine, dimensions, &updates).await;
                        None
                    }
                };

                if let Some(Err(e)) = connection {
                    let error = e.to_string();
                    reported_failure = Some(error.clone());
                    let _ = updates.send(message("welcome", Some(error))).await;
                }
            }
            event = engine.next_event() => {
                let update = match event {
                    EngineEvent::Frame(frame) => {
                        if attachment.is_pending() {
                            // A viewport change during an in-flight attempt must
                            // be reapplied after that attachment becomes active.
                            resize(&mut engine, dimensions, &updates).await;
                            match attachment::synchronize(&engine, dimensions, &updates).await {
                                Ok(true) => {
                                    attachment.refresh(frame);
                                    continue;
                                }
                                Ok(false) if updates.stop.is_cancelled() => continue,
                                Ok(false) => (),
                                Err(e) => {
                                    let _ = updates.send(message("error", Some(e.to_string()))).await;
                                    let _ = engine.detach().await;
                                    continue;
                                }
                            }
                        }
                        let frame = match attachment.frame(frame, &mut presenter) {
                            Ok(Some(frame)) => frame,
                            Ok(None) => continue,
                            Err(e) => {
                                let _ = updates.send(message("error", Some(e.to_string()))).await;
                                let _ = engine.detach().await;
                                continue;
                            }
                        };
                        UiUpdate {
                            kind: "frame".into(),
                            frame: Some(presenter.frame(frame)),
                            ..UiUpdate::default()
                        }
                    }
                    EngineEvent::Welcome { error } => {
                        reset_input(task.as_mut(), &mut input, &input_epoch);
                        presenter.reset();
                        attachment = Attachment::Pending;
                        if error.is_some() && error == reported_failure.take() {
                            continue;
                        }
                        message("welcome", error)
                    }
                    EngineEvent::Error(error) => message("error", Some(error)),
                    EngineEvent::Connect { host } => {
                        reset_input(task.as_mut(), &mut input, &input_epoch);
                        presenter.reset();
                        attachment = Attachment::Pending;
                        remember(history.as_ref(), Some(&host), &updates).await;
                        connecting(Some(host))
                    }
                    EngineEvent::OpenWebview { handle, url, position, focus, focusable, window } => {
                        open_window(handle, url, position, focus, focusable, window)
                    }
                    EngineEvent::FocusWebview { handle } => window_action("focus_webview", handle),
                    EngineEvent::CloseWebview { handle } => window_action("close_webview", handle),
                    EngineEvent::Shutdown => break,
                };

                if updates.send(update).await.is_err() {
                    break;
                }
            }
            () = completed(task.as_mut()) => {
                task.set(None);
            }
            () = attachment.expired() => {
                let _ = updates.send(message("error", Some("Restore the attached editor display: completed frame timed out".into()))).await;
                attachment = Attachment::Pending;
                let _ = engine.detach().await;
            }
            operation = input.recv(), if task.is_none() && attachment.accepts_input() => {
                let Some(operation) = operation else { break };
                if let Some(operation) = operation.into_current() {
                    if !matches!(operation, Input::Host(HostInput::Focus(_)))
                        && let Some(frame) = presenter.dismiss_messages()
                    {
                        let _ = updates.send(UiUpdate {
                            kind: "frame".into(),
                            frame: Some(frame),
                            ..UiUpdate::default()
                        }).await;
                    }
                    task.set(start_input(&engine, operation, &updates));
                }
            }
        }
    }

    input_epoch.borrow().cancel();
    stop_input(task.as_mut(), &mut input);
    commands.close();
    input.close();
    finish(&mut engine, &updates).await;
}

fn connecting(alias: Option<String>) -> UiUpdate {
    UiUpdate {
        kind: "connecting".into(),
        message: Some(alias.clone().unwrap_or_else(|| "Local".into())),
        destination: Some(DisplayDestination { alias }),
        ..UiUpdate::default()
    }
}

async fn remember(history: Option<&History>, alias: Option<&str>, updates: &Updates) {
    if let Some(history) = history
        && let Err(e) = history.save(alias)
    {
        let _ = updates
            .send(message(
                "error",
                Some(format!("Remember the selected host: {e}")),
            ))
            .await;
    }
}

async fn finish(engine: &mut Engine, updates: &Updates) {
    // This finalization is deliberately outside select!: cancelling an earlier
    // next_event() may have interrupted core's SIGTERM cleanup.
    if let Err(e) = engine.shutdown().await {
        updates
            .final_update(message("error", Some(e.to_string())))
            .await;
    }
    loop {
        match engine.next_event().await {
            EngineEvent::Error(error) => updates.final_update(message("error", Some(error))).await,
            EngineEvent::CloseWebview { handle } => {
                updates
                    .final_update(window_action("close_webview", handle))
                    .await
            }
            EngineEvent::Shutdown => break,
            _ => (),
        }
    }
    updates.final_update(message("shutdown", None)).await;
}

// Core retains an attachment attempt when start()/connect() is dropped. Polling
// once initializes that owned attempt, then event reception drives it while
// commands and shutdown remain responsive. No borrowed future is retained.
async fn begin(future: impl Future<Output = Result<(), Error>>) -> Option<Result<(), Error>> {
    tokio::pin!(future);
    poll_fn(|cx| {
        Poll::Ready(match future.as_mut().poll(cx) {
            Poll::Ready(result) => Some(result),
            Poll::Pending => None,
        })
    })
    .await
}

async fn resize(engine: &mut Engine, dimensions: GridSize, updates: &Updates) {
    let result = tokio::select! {
        biased;
        () = updates.stop.cancelled() => return,
        result = timeout(Duration::from_secs(2), engine.resize(dimensions.width(), dimensions.height())) => result,
    };
    let error = match result {
        Ok(Ok(())) => return,
        Ok(Err(e)) => e.to_string(),
        Err(_) => "Resize the host Neovim: request timed out".into(),
    };
    let _ = updates.send(message("error", Some(error))).await;
}
