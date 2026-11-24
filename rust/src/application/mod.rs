//! Owns the engine thread, bounded action queues, and attachment lifetimes.

use crate::api::display::UiUpdate;

mod attachment;
mod checkpoints;
mod driver;
mod error;
pub(crate) use error::Error;
mod history;
mod input;
mod size;
use size::{GridSize, WindowSize};

mod updates;

use driver::run;
use input::{HostInput, Input, QueuedInput};
use updates::Updates;

use nvim_rpc_ui::{Buffer, Tabpage};
use tokio::sync::{Mutex, mpsc, watch};
use tokio_util::sync::CancellationToken;

use std::path::PathBuf;
use std::thread;

enum Command {
    Start(GridSize),
    Connect(Option<String>, GridSize),
    Resize(GridSize),
    Detach,
}

/// Sends application actions to the engine's dedicated I/O thread.
pub(crate) struct Handle {
    commands: mpsc::Sender<Command>,
    input: mpsc::Sender<QueuedInput>,
    input_epoch: watch::Receiver<CancellationToken>,
    stop: CancellationToken,
    stopped: watch::Receiver<bool>,
    window_size: watch::Sender<Option<WindowSize>>,
    updates: Mutex<Option<mpsc::Receiver<UiUpdate>>>,
}

/// Starts the engine without blocking Flutter's UI isolate.
pub(crate) fn spawn(config_path: Option<String>) -> Result<Handle, Error> {
    spawn_with_history(config_path, None)
}

fn spawn_with_history(
    config_path: Option<String>,
    state_path: Option<PathBuf>,
) -> Result<Handle, Error> {
    let (commands, receiver) = mpsc::channel(32);
    let (input, input_receiver) = mpsc::channel(256);
    let (input_epoch_tx, input_epoch) = watch::channel(CancellationToken::new());
    let (sender, update_receiver) = mpsc::channel(8);
    let stop = CancellationToken::new();
    let run_stop = stop.clone();
    let (stopped_tx, stopped) = watch::channel(false);
    let (window_size, observed_size) = watch::channel(None);

    thread::Builder::new()
        .name("nauvim-engine".into())
        .spawn(move || {
            let updates = Updates {
                sender,
                stop: run_stop,
            };
            match tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
            {
                Ok(runtime) => runtime.block_on(run(
                    config_path,
                    state_path,
                    receiver,
                    input_receiver,
                    input_epoch_tx,
                    observed_size,
                    updates,
                )),
                Err(e) => {
                    let _ = updates.sender.blocking_send(updates::message(
                        "welcome",
                        Some(format!("Start the Nauvim runtime: {e}")),
                    ));
                }
            }
            let _ = stopped_tx.send(true);
        })
        .map_err(Error::StartThread)?;

    Ok(Handle {
        commands,
        input,
        input_epoch,
        stop,
        stopped,
        window_size,
        updates: Mutex::new(Some(update_receiver)),
    })
}

impl Handle {
    pub(crate) async fn take_updates(&self) -> Result<mpsc::Receiver<UiUpdate>, Error> {
        self.updates
            .lock()
            .await
            .take()
            .ok_or(Error::AlreadySubscribed)
    }

    pub(crate) fn cancel(&self) {
        self.stop.cancel();
    }

    /// Applies startup selection after Flutter measures the editor viewport.
    pub(crate) async fn start(&self, width: u32, height: u32) -> Result<(), Error> {
        self.send(Command::Start(GridSize::new(width, height)))
            .await
    }

    pub(crate) async fn connect(&self, host: String, width: u32, height: u32) -> Result<(), Error> {
        self.send(Command::Connect(Some(host), GridSize::new(width, height)))
            .await
    }

    /// Selects the independent default host, without resolving an alias.
    pub(crate) async fn connect_default(&self, width: u32, height: u32) -> Result<(), Error> {
        self.send(Command::Connect(None, GridSize::new(width, height)))
            .await
    }

    pub(crate) async fn detach(&self) -> Result<(), Error> {
        self.send(Command::Detach).await
    }

    /// Sends Neovim key notation; literal less-than characters use `<LT>`.
    pub(crate) async fn input(&self, keys: String) -> Result<(), Error> {
        self.send_input(Input::Host(HostInput::Keys(keys))).await
    }

    /// Pastes from the clipboard backend selected by core.
    pub(crate) async fn paste(&self) -> Result<(), Error> {
        self.send_input(Input::Paste).await
    }

    pub(crate) async fn resize(&self, width: u32, height: u32) -> Result<(), Error> {
        self.send(Command::Resize(GridSize::new(width, height)))
            .await
    }

    pub(crate) fn record_window_size(&self, width: u32, height: u32) {
        if let Some(size) = WindowSize::new(width, height) {
            self.window_size.send_replace(Some(size));
        }
    }

    pub(crate) async fn focus(&self, focused: bool) -> Result<(), Error> {
        self.send_input(Input::Host(HostInput::Focus(focused)))
            .await
    }

    pub(crate) async fn select_popupmenu_item(&self, index: i64) -> Result<(), Error> {
        self.send_input(Input::Host(HostInput::Popup(index))).await
    }

    pub(crate) async fn set_current_tabpage(&self, tabpage: i64) -> Result<(), Error> {
        self.send_input(Input::Host(HostInput::Tab(Tabpage(tabpage))))
            .await
    }

    pub(crate) async fn set_current_buffer(&self, buffer: i64) -> Result<(), Error> {
        self.send_input(Input::Host(HostInput::Buffer(Buffer(buffer))))
            .await
    }

    /// Waits for final cleanup while preserving the host Neovim.
    pub(crate) async fn close(&self) -> Result<(), Error> {
        let mut stopped = self.stopped.clone();
        self.stop.cancel();

        while !*stopped.borrow_and_update() {
            // RecvError has no payload: closure of this watch channel means
            // the runtime ended without publishing its cleanup acknowledgement.
            stopped
                .changed()
                .await
                .map_err(|_| Error::CleanupUnconfirmed)?;
        }

        Ok(())
    }

    async fn send_input(&self, input: Input) -> Result<(), Error> {
        let epoch = self.input_epoch.borrow().clone();

        let permit = tokio::select! {
            biased;
            () = self.stop.cancelled() => return Err(Error::Stopping),
            () = epoch.cancelled() => return Ok(()),
            result = self.input.reserve() => result.map_err(|_| Error::Stopped)?,
        };

        if !epoch.is_cancelled() {
            permit.send(QueuedInput { epoch, input });
        }

        Ok(())
    }

    async fn send(&self, command: Command) -> Result<(), Error> {
        tokio::select! {
            biased;
            () = self.stop.cancelled() => Err(Error::Stopping),
            result = self.commands.send(command) => result.map_err(|_| Error::Stopped),
        }
    }
}

impl Drop for Handle {
    fn drop(&mut self) {
        self.stop.cancel();
    }
}

#[cfg(test)]
mod tests;
