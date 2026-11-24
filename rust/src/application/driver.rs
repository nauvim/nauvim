use crate::api::display::{DisplayDestination, DisplayLength, DisplayLengthUnit, UiUpdate};
use crate::configuration;
use crate::display::Presenter;

use super::Command;
use super::attachment::{Attachment, Attempt, Identity, Session, session_token};
use super::checkpoints::Checkpoints;
use super::history::History;
use super::input::{
    HostInput, Input, QueuedInput, completed, reset_input, start_input, stop_input,
};
use super::size::{GridSize, WindowSize};
use super::updates::{Updates, message, navigate_window, open_window, window_action};

use nauvim_core::{Checkpoint, Engine, EngineEvent, Error, HostSelection};
use tokio::sync::{mpsc, watch};
use tokio::task::spawn_blocking;
use tokio::time::{Duration, MissedTickBehavior, interval, timeout};
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
    observed_size: watch::Receiver<Option<WindowSize>>,
    updates: Updates,
) {
    let (config, mut options) = match configuration::load(path.as_deref().map(Path::new)) {
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
            history_error = Some(format!("Open the application state database: {e}"));
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

    let mut window_error = None;
    if let Some(history) = &history
        && options
            .window
            .as_ref()
            .is_none_or(|window| window.startup_mode.is_none())
    {
        match history.load_window_size() {
            Ok(Some(size)) => {
                let window = options.window.get_or_insert_default();
                let pixels = |value| DisplayLength {
                    value: f64::from(value),
                    unit: DisplayLengthUnit::Px,
                };
                window.width = Some(pixels(size.width.get()));
                window.height = Some(pixels(size.height.get()));
            }
            Ok(None) => (),
            Err(e) => window_error = Some(format!("Restore the last window size: {e}")),
        }
    }

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
    for error in [history_error, window_error].into_iter().flatten() {
        let _ = updates.send(message("error", Some(error))).await;
    }

    let checkpoints = match state_path
        .as_deref()
        .map_or_else(Checkpoints::system, |path| Ok(Checkpoints::beside(path)))
    {
        Ok(store) => Some(store),
        Err(e) => {
            let _ = updates
                .send(message(
                    "error",
                    Some(format!("Open UI checkpoint storage: {e}")),
                ))
                .await;
            None
        }
    };

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
    let mut attachment = Attachment::Waiting;
    let mut started = false;
    let mut reported_failure = None;
    let mut checkpoint_tick = interval(Duration::from_secs(1));
    checkpoint_tick.set_missed_tick_behavior(MissedTickBehavior::Skip);

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
                                HostSelection::Alias(alias) => Some(alias.to_owned()),
                            };
                            remember(history.as_ref(), alias.as_deref(), &updates).await;
                            let _ = updates.send(connecting(alias.clone())).await;
                            connect(&mut engine, &mut attachment, alias, dimensions).await
                        } else {
                            begin(engine.start(dimensions.width(), dimensions.height())).await
                        }
                    }
                    Command::Start(..) => None,
                    Command::Connect(host, size) => {
                        started = true;
                        reported_failure = None;
                        reset_input(task.as_mut(), &mut input, &input_epoch);
                        presenter.reset();
                        attachment.observe(&engine);
                        save_checkpoint(&mut attachment, checkpoints.as_ref(), &updates).await;
                        dimensions = size;
                        remember(history.as_ref(), host.as_deref(), &updates).await;
                        let _ = updates.send(connecting(host.clone())).await;
                        connect(&mut engine, &mut attachment, host, dimensions).await
                    }
                    Command::Detach => {
                        reset_input(task.as_mut(), &mut input, &input_epoch);
                        presenter.reset();
                        attachment.observe(&engine);
                        save_checkpoint(&mut attachment, checkpoints.as_ref(), &updates).await;
                        attachment = Attachment::Waiting;
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

                reported_failure = report_connection_failure(connection, &updates)
                    .await
                    .or(reported_failure);
            }
            event = engine.next_event() => {
                if matches!(event, EngineEvent::Frame(_) | EngineEvent::OpenWebview { .. })
                    && let Attachment::Connecting(attempt) = &mut attachment
                    && !matches!(attempt.identity, Identity::Verified(_))
                {
                    let token = if checkpoints.is_some() {
                        session_token(&engine).await.map(Some)
                    } else {
                        Ok(None)
                    };
                    let actual = token.as_ref().ok().and_then(Option::as_deref);
                    if let Identity::Restoring(expected) = &attempt.identity
                        && actual != Some(expected)
                    {
                        let result = retry(&mut engine, attempt, dimensions).await;
                        reported_failure = report_connection_failure(result, &updates).await;
                        continue;
                    }
                    if matches!(attempt.identity, Identity::Discovering)
                        && let (Some(store), Some(token)) = (&checkpoints, actual)
                        && let Some(checkpoint) = load_checkpoint(store, token, &updates).await
                    {
                        // Core exposes RPC after UI registration. Identify
                        // the session before supplying its saved display state.
                        attempt.identity = Identity::Restoring(token.to_owned());
                        attempt.dimensions = dimensions;
                        let result = begin(connect_host(
                            &mut engine, attempt.alias.as_deref(), dimensions, Some(checkpoint),
                        )).await;
                        reported_failure = report_connection_failure(result, &updates).await;
                        continue;
                    }
                    let token = match token {
                        Ok(token) => token,
                        Err(e) => {
                            let _ = updates.send(message("error", Some(format!("Identify Neovim for UI checkpoint: {e}")))).await;
                            None
                        }
                    };
                    attempt.identity = Identity::Verified(token);
                }
                let update = match event {
                    EngineEvent::Frame(frame) => {
                        if let Attachment::Connecting(Attempt {
                            dimensions: initial,
                            identity: Identity::Verified(token),
                            ..
                        }) = &mut attachment
                        {
                            // An in-flight connection still uses its original viewport.
                            if *initial != dimensions {
                                resize(&mut engine, dimensions, &updates).await;
                            }
                            let session = token.take().map(Session::new);
                            attachment = Attachment::Ready(session);
                        }
                        attachment.observe(&engine);
                        UiUpdate {
                            kind: "frame".into(),
                            frame: Some(presenter.frame(frame)),
                            ..UiUpdate::default()
                        }
                    }
                    EngineEvent::Welcome { error } => {
                        if error.is_some()
                            && let Attachment::Connecting(attempt) = &mut attachment
                            && matches!(attempt.identity, Identity::Restoring(_))
                        {
                            let result = retry(&mut engine, attempt, dimensions).await;
                            reported_failure = report_connection_failure(result, &updates).await;
                            continue;
                        }
                        reset_input(task.as_mut(), &mut input, &input_epoch);
                        presenter.reset();
                        save_checkpoint(&mut attachment, checkpoints.as_ref(), &updates).await;
                        attachment = Attachment::Waiting;
                        if error.is_some() && error == reported_failure.take() {
                            continue;
                        }
                        message("welcome", error)
                    }
                    EngineEvent::Error(error) => message("error", Some(error)),
                    EngineEvent::Connect { host } => {
                        reset_input(task.as_mut(), &mut input, &input_epoch);
                        presenter.reset();
                        save_checkpoint(&mut attachment, checkpoints.as_ref(), &updates).await;
                        remember(history.as_ref(), Some(&host), &updates).await;
                        let _ = updates.send(connecting(Some(host.clone()))).await;
                        let result = connect(&mut engine, &mut attachment, Some(host), dimensions).await;
                        reported_failure = report_connection_failure(result, &updates).await;
                        continue;
                    }
                    EngineEvent::OpenWebview { handle, url, position, focus, focusable, close_on_blur, window } => {
                        open_window(handle, url, position, focus, focusable, close_on_blur, window)
                    }
                    EngineEvent::FocusWebview { handle } => window_action("focus_webview", handle),
                    EngineEvent::NavigateWebview { handle, url, replace_history, focus, window } => {
                        navigate_window(handle, url, replace_history, focus, window)
                    }
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
            _ = checkpoint_tick.tick(), if matches!(attachment, Attachment::Ready(Some(_))) => {
                attachment.observe(&engine);
                save_checkpoint(&mut attachment, checkpoints.as_ref(), &updates).await;
            }
            operation = input.recv(), if task.is_none() && !matches!(attachment, Attachment::Connecting(_)) => {
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
    attachment.observe(&engine);
    if let Attachment::Ready(Some(session)) = &mut attachment
        && let Some(store) = &checkpoints
        && let Some(error) = session.save(store).await
    {
        updates.final_update(message("error", Some(error))).await;
    }
    commands.close();
    input.close();
    let last_size = *observed_size.borrow();
    if let (Some(history), Some(size)) = (&history, last_size)
        && let Err(e) = history.save_window_size(size)
    {
        updates
            .final_update(message(
                "error",
                Some(format!("Save the last window size: {e}")),
            ))
            .await;
    }
    finish(&mut engine, &updates).await;
}

async fn connect(
    engine: &mut Engine,
    attachment: &mut Attachment,
    alias: Option<String>,
    dimensions: GridSize,
) -> Option<Result<(), Error>> {
    let result = begin(connect_host(engine, alias.as_deref(), dimensions, None)).await;
    *attachment = Attachment::Connecting(Attempt {
        alias,
        dimensions,
        identity: Identity::Discovering,
    });
    result
}

async fn connect_host(
    engine: &mut Engine,
    alias: Option<&str>,
    dimensions: GridSize,
    checkpoint: Option<Checkpoint>,
) -> Result<(), Error> {
    let width = dimensions.width();
    let height = dimensions.height();
    match (alias, checkpoint) {
        (Some(alias), Some(checkpoint)) => {
            engine
                .connect_with_checkpoint_reference(alias, width, height, checkpoint)
                .await
        }
        (None, Some(checkpoint)) => {
            engine
                .connect_default_with_checkpoint_reference(width, height, checkpoint)
                .await
        }
        (Some(alias), None) => engine.connect(alias, width, height).await,
        (None, None) => engine.connect_default(width, height).await,
    }
}

async fn retry(
    engine: &mut Engine,
    attempt: &mut Attempt,
    dimensions: GridSize,
) -> Option<Result<(), Error>> {
    attempt.identity = Identity::Fresh;
    attempt.dimensions = dimensions;
    begin(connect_host(
        engine,
        attempt.alias.as_deref(),
        dimensions,
        None,
    ))
    .await
}

async fn load_checkpoint(
    store: &Checkpoints,
    token: &str,
    updates: &Updates,
) -> Option<Checkpoint> {
    let store = store.clone();
    let token = token.to_owned();
    let error = match spawn_blocking(move || store.load(&token)).await {
        Ok(Ok(checkpoint)) => return checkpoint,
        Ok(Err(e)) => e.to_string(),
        Err(e) => e.to_string(),
    };
    let _ = updates
        .send(message(
            "error",
            Some(format!("Load UI checkpoint: {error}")),
        ))
        .await;
    None
}

async fn save_checkpoint(
    attachment: &mut Attachment,
    store: Option<&Checkpoints>,
    updates: &Updates,
) {
    if let (Attachment::Ready(Some(session)), Some(store)) = (attachment, store)
        && let Some(error) = session.save(store).await
    {
        let _ = updates.send(message("error", Some(error))).await;
    }
}

async fn report_connection_failure(
    result: Option<Result<(), Error>>,
    updates: &Updates,
) -> Option<String> {
    let Some(Err(e)) = result else {
        return None;
    };
    let error = e.to_string();
    let _ = updates.send(message("welcome", Some(error.clone()))).await;
    Some(error)
}

fn connecting(alias: Option<String>) -> UiUpdate {
    UiUpdate {
        kind: "connecting".into(),
        message: Some(alias.clone().unwrap_or_else(|| "Default host".into())),
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
