use crate::api::display::DisplayEvent;

use nvim_rpc_ui::Event;

pub(super) fn project(event: Event) -> Option<DisplayEvent> {
    let (kind, text) = match event {
        Event::RpcError { message, .. } => ("error", message.to_string()),
        Event::Bell => ("bell", String::new()),
        Event::VisualBell => ("visual_bell", String::new()),
        Event::SetTitle(title) => ("title", title.to_string()),
        Event::SetIcon(icon) => ("icon", icon.to_string()),
        Event::Chdir(path) => ("cwd", path.to_string()),
        Event::Connect(address) => ("connect", address.to_string()),
        Event::Restart { address, .. } => ("restart", address.to_string()),
        Event::Suspend => ("suspend", String::new()),
        Event::Screenshot(path) => ("screenshot", path.to_string()),
        Event::ErrorExit(status) => ("error", format!("Host Neovim exited with status {status}")),
        Event::UpdateMenu | Event::UiSend(_) | Event::Extmark { .. } | Event::Unknown { .. } => {
            return None;
        }
    };
    Some(DisplayEvent {
        kind: kind.into(),
        text,
    })
}
