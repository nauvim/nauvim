use crate::application::{self, Handle};
use crate::configuration::Source;
use crate::frb_generated::StreamSink;

use super::display::{InputAttachment, UiUpdate};

use flutter_rust_bridge::frb;

use std::path::PathBuf;

/// Sends application actions to the engine's dedicated I/O thread.
///
/// Actions return after queueing; host failures arrive through [`Self::updates()`].
/// Input actions retain their order within an attachment. Attachment changes
/// invalidate pending input, including senders waiting for queue capacity.
/// Dropping the application requests cleanup; [`Self::close()`] waits for it.
#[frb(opaque)]
pub struct Application {
    handle: Handle,
}

/// Starts the engine without blocking Flutter's UI isolate.
///
/// Configuration is loaded on the engine thread and delivered through
/// [`Application::updates()`]. Host attachment waits for [`Application::start()`]
/// or an explicit connection action. An error here means the thread could not start.
pub fn create_application(
    config_path: Option<String>,
    lua_module_paths: Vec<String>,
) -> Result<Application, String> {
    application::spawn(Source {
        path: config_path.map(PathBuf::from),
        lua_module_paths,
    })
    .map(|handle| Application { handle })
    .map_err(|e| e.to_string())
}

impl Application {
    /// Streams ordered updates to the application's single subscriber.
    ///
    /// Rejects a second subscription. A closed sink requests engine cleanup.
    pub async fn updates(&self, sink: StreamSink<UiUpdate>) -> Result<(), String> {
        let mut updates = self
            .handle
            .take_updates()
            .await
            .map_err(|e| e.to_string())?;

        while let Some(update) = updates.recv().await {
            if sink.add(update).is_err() {
                self.handle.cancel();
                break;
            }
        }

        Ok(())
    }

    /// Applies startup selection after Flutter measures the editor viewport.
    ///
    /// Width and height count Neovim grid cells; zero is clamped to one.
    /// Further calls are ignored after startup or an explicit connection action.
    pub async fn start(&self, width: u32, height: u32) -> Result<(), String> {
        self.handle
            .start(width, height)
            .await
            .map_err(|e| e.to_string())
    }

    /// Connects to a host alias with the viewport size in grid cells.
    pub async fn connect(&self, host: String, width: u32, height: u32) -> Result<(), String> {
        self.handle
            .connect(host, width, height)
            .await
            .map_err(|e| e.to_string())
    }

    /// Selects the independent default host, without resolving an alias.
    pub async fn connect_default(&self, width: u32, height: u32) -> Result<(), String> {
        self.handle
            .connect_default(width, height)
            .await
            .map_err(|e| e.to_string())
    }

    /// Detaches the GUI while preserving the host Neovim process.
    pub async fn detach(&self) -> Result<(), String> {
        self.handle.detach().await.map_err(|e| e.to_string())
    }

    /// Sends Neovim key notation; literal less-than characters use `<LT>`.
    pub async fn input(&self, keys: String) -> Result<(), String> {
        self.handle.input(keys).await.map_err(|e| e.to_string())
    }

    /// Sends keys only while the attachment that supplied the input remains active.
    pub async fn input_on_attachment(
        &self,
        keys: String,
        attachment: &InputAttachment,
    ) -> Result<(), String> {
        self.handle
            .input_on_attachment(keys, &attachment.0)
            .await
            .map_err(|e| e.to_string())
    }

    /// Pastes from the clipboard backend selected by core.
    pub async fn paste(&self) -> Result<(), String> {
        self.handle.paste().await.map_err(|e| e.to_string())
    }

    /// Updates viewport dimensions in grid cells, clamping each zero to one.
    pub async fn resize(&self, width: u32, height: u32) -> Result<(), String> {
        self.handle
            .resize(width, height)
            .await
            .map_err(|e| e.to_string())
    }

    /// Records the latest client-area size in logical pixels for orderly shutdown.
    /// Ignores measurements with a zero dimension.
    #[frb(sync)]
    pub fn record_window_size(&self, width: u32, height: u32) {
        self.handle.record_window_size(width, height);
    }

    /// Reports GUI focus to the attached Neovim.
    pub async fn focus(&self, focused: bool) -> Result<(), String> {
        self.handle.focus(focused).await.map_err(|e| e.to_string())
    }

    /// Accepts a completion item by its zero-based popup index.
    pub async fn select_popupmenu_item(&self, index: i64) -> Result<(), String> {
        self.handle
            .select_popupmenu_item(index)
            .await
            .map_err(|e| e.to_string())
    }

    /// Selects a Neovim tabpage handle.
    pub async fn set_current_tabpage(&self, tabpage: i64) -> Result<(), String> {
        self.handle
            .set_current_tabpage(tabpage)
            .await
            .map_err(|e| e.to_string())
    }

    /// Selects a Neovim buffer handle.
    pub async fn set_current_buffer(&self, buffer: i64) -> Result<(), String> {
        self.handle
            .set_current_buffer(buffer)
            .await
            .map_err(|e| e.to_string())
    }

    /// Waits for final cleanup while preserving the host Neovim.
    pub async fn close(&self) -> Result<(), String> {
        self.handle.close().await.map_err(|e| e.to_string())
    }
}
