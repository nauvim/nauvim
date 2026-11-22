use super::*;

use tokio::net::UnixListener;
use tokio::time::{Duration, timeout};

use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command as ProcessCommand;

fn spawn(config_path: Option<String>) -> Result<Handle, Error> {
    let state_path = Path::new(config_path.as_deref().unwrap())
        .parent()
        .unwrap()
        .join("state.sqlite3");
    spawn_with_history(config_path, Some(state_path))
}

struct Host {
    nvim: PathBuf,
    socket: PathBuf,
}

impl Host {
    fn evaluate(&self, expression: &str) -> String {
        let output = ProcessCommand::new(&self.nvim)
            .arg("--server")
            .arg(&self.socket)
            .args(["--remote-expr", expression])
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8(output.stdout).unwrap().trim().to_owned()
    }
}

impl Drop for Host {
    fn drop(&mut self) {
        // A test must stop its own persistent host even after an assertion.
        let _ = ProcessCommand::new(&self.nvim)
            .arg("--server")
            .arg(&self.socket)
            .args(["--remote-expr", "execute('qa!')"])
            .output();
    }
}

async fn live_application(root: &Path) -> (Host, Handle, mpsc::Receiver<UiUpdate>) {
    use std::env;

    let host = Host {
        nvim: PathBuf::from(env::var_os("NVIM_BIN").expect("Set NVIM_BIN for this live test")),
        socket: root.join("host.sock"),
    };
    let config = root.join("init.lua");
    fs::write(
        &config,
        format!(
            r#"return {{
                default_host = 'test',
                hosts = {{test = {{
                    nvim = {{prog = {:?}, args = {{'-u', 'NONE', '-i', 'NONE', '-n'}}}},
                    socket = {:?},
                    policies = {{plugin = {{http = {{open_webview = {{
                        origins = {{'https://example.test'}},
                    }}}}}}}},
                }}}},
            }}"#,
            host.nvim.to_str().unwrap(),
            host.socket.to_str().unwrap(),
        ),
    )
    .unwrap();
    let app = spawn(Some(config.to_string_lossy().into_owned())).unwrap();
    let mut updates = app.take_updates().await.unwrap();
    receive(&mut updates, "ready").await;
    app.start(80, 24).await.unwrap();
    receive(&mut updates, "frame").await;

    (host, app, updates)
}

async fn receive(updates: &mut mpsc::Receiver<UiUpdate>, kind: &str) -> UiUpdate {
    timeout(Duration::from_secs(3), async {
        loop {
            let update = updates.recv().await.expect("The update stream ended");
            if update.kind == kind {
                return update;
            }
        }
    })
    .await
    .expect("The expected application update did not arrive")
}

#[tokio::test]
async fn starts_once_with_configured_aliases_and_reports_nonfatal_diagnostics() {
    let root = tempfile::tempdir().unwrap();
    let config = root.path().join("init.lua");
    fs::write(
        &config,
        r#"return {
            hosts = {local_alias = {}},
            clipboard = {backend = 'missing-test-backend', timeout_ms = 0},
        }"#,
    )
    .unwrap();
    let app = spawn(Some(config.to_string_lossy().into_owned())).unwrap();
    let mut updates = app.updates.lock().await.take().unwrap();
    let ready = receive(&mut updates, "ready").await;
    assert_eq!(ready.hosts, ["local_alias"]);
    assert_eq!(ready.default_host, None);
    app.start(80, 24).await.unwrap();
    let mut diagnostics = Vec::new();
    loop {
        let update = timeout(Duration::from_secs(3), updates.recv())
            .await
            .unwrap()
            .unwrap();
        match update.kind.as_str() {
            "error" => diagnostics.push(update.message.unwrap()),
            "welcome" => {
                assert_eq!(update.message, None);
                break;
            }
            kind => panic!("Unexpected startup update {kind}"),
        }
    }
    assert!(diagnostics.iter().any(|s| s.contains("timeout_ms")));
    assert!(
        diagnostics
            .iter()
            .any(|s| s.contains("missing-test-backend"))
    );
    app.start(100, 30).await.unwrap();
    assert!(
        timeout(Duration::from_millis(40), updates.recv())
            .await
            .is_err()
    );
    app.close().await.unwrap();
    receive(&mut updates, "shutdown").await;
}

#[tokio::test]
async fn reports_alias_failure_once_and_preserves_the_welcome_page() {
    let root = tempfile::tempdir().unwrap();
    let config = root.path().join("init.lua");
    fs::write(
        &config,
        r#"return {hosts = {local_alias = {
            nvim = function() error('selected-local-alias') end,
        }}}"#,
    )
    .unwrap();
    let app = spawn(Some(config.to_string_lossy().into_owned())).unwrap();
    let mut updates = app.updates.lock().await.take().unwrap();
    receive(&mut updates, "ready").await;
    app.start(80, 24).await.unwrap();
    receive(&mut updates, "welcome").await;
    app.connect("local_alias".into(), 80, 24).await.unwrap();
    assert_eq!(
        receive(&mut updates, "connecting").await.message.as_deref(),
        Some("local_alias")
    );
    let welcome = receive(&mut updates, "welcome").await;
    assert!(welcome.message.unwrap().contains("selected-local-alias"));
    assert!(
        timeout(Duration::from_millis(40), updates.recv())
            .await
            .is_err()
    );
    app.paste().await.unwrap();
    assert_eq!(
        receive(&mut updates, "error").await.message.as_deref(),
        Some("No host Neovim is attached")
    );
    app.close().await.unwrap();
    receive(&mut updates, "shutdown").await;
}

#[tokio::test]
async fn restores_the_requested_host_without_waiting_for_shutdown() {
    use crate::api::display::DisplayDestination;

    let root = tempfile::tempdir().unwrap();
    let config = root.path().join("init.lua");
    fs::write(
        &config,
        r#"return {hosts = {local_alias = {
            nvim = function() error('selected-local-alias') end,
        }}}"#,
    )
    .unwrap();
    let app = spawn(Some(config.to_string_lossy().into_owned())).unwrap();
    let mut updates = app.take_updates().await.unwrap();
    assert_eq!(receive(&mut updates, "ready").await.destination, None);
    app.connect("local_alias".into(), 80, 24).await.unwrap();
    assert_eq!(
        receive(&mut updates, "connecting").await.destination,
        Some(DisplayDestination {
            alias: Some("local_alias".into())
        }),
    );
    receive(&mut updates, "welcome").await;

    // Reopen while the first instance is alive: persistence cannot depend on
    // graceful shutdown or a successful attachment.
    let restarted = spawn(Some(config.to_string_lossy().into_owned())).unwrap();
    let mut restored_updates = restarted.take_updates().await.unwrap();
    assert_eq!(
        receive(&mut restored_updates, "ready").await.destination,
        Some(DisplayDestination {
            alias: Some("local_alias".into())
        }),
    );
    restarted.start(80, 24).await.unwrap();
    receive(&mut restored_updates, "welcome").await;
    restarted.close().await.unwrap();
    app.close().await.unwrap();
}

#[tokio::test]
async fn storage_failure_does_not_prevent_host_selection() {
    let root = tempfile::tempdir().unwrap();
    let config = root.path().join("init.lua");
    fs::write(
        &config,
        r#"return {hosts = {local_alias = {
            nvim = function() error('selected-local-alias') end,
        }}}"#,
    )
    .unwrap();
    fs::write(root.path().join("state.sqlite3"), b"damaged database").unwrap();
    let app = spawn(Some(config.to_string_lossy().into_owned())).unwrap();
    let mut updates = app.take_updates().await.unwrap();
    receive(&mut updates, "ready").await;
    assert!(
        receive(&mut updates, "error")
            .await
            .message
            .unwrap()
            .contains("application state database")
    );
    app.connect("local_alias".into(), 80, 24).await.unwrap();
    receive(&mut updates, "connecting").await;
    assert!(
        receive(&mut updates, "welcome")
            .await
            .message
            .unwrap()
            .contains("selected-local-alias")
    );
    app.close().await.unwrap();
    assert_eq!(
        fs::read(root.path().join("state.sqlite3")).unwrap(),
        b"damaged database"
    );
}

#[tokio::test]
async fn restores_the_last_client_area_only_when_startup_size_is_nil() {
    use crate::api::display::{DisplayLength, DisplayLengthUnit, DisplayStartupMode};

    let root = tempfile::tempdir().unwrap();
    let config_path = root.path().join("init.lua");
    let path = config_path.to_string_lossy().into_owned();

    fs::write(&config_path, "return {}").unwrap();
    let app = spawn(Some(path.clone())).unwrap();
    let mut updates = app.take_updates().await.unwrap();
    assert!(
        receive(&mut updates, "ready")
            .await
            .window_options
            .is_none()
    );
    app.record_window_size(800, 600);
    app.record_window_size(931, 677);
    app.record_window_size(0, 0);
    app.close().await.unwrap();
    receive(&mut updates, "shutdown").await;

    let restored = spawn(Some(path.clone())).unwrap();
    let mut updates = restored.take_updates().await.unwrap();
    let options = receive(&mut updates, "ready").await.window_options.unwrap();
    assert_eq!(
        (options.width.unwrap().value, options.height.unwrap().value),
        (931.0, 677.0),
    );
    restored.close().await.unwrap();

    let px = |value| {
        Some(DisplayLength {
            value,
            unit: DisplayLengthUnit::Px,
        })
    };
    for (window, expected, width, height) in [
        ("{opacity=0.75}", "restore", px(931.0), px(677.0)),
        (
            "{opacity=0.75,startup_size=nil}",
            "restore",
            px(931.0),
            px(677.0),
        ),
        (
            "{opacity=0.75,startup_size={width=720}}",
            "windowed",
            px(720.0),
            None,
        ),
        ("{opacity=0.75,startup_size={}}", "windowed", None, None),
        (
            "{opacity=0.75,startup_size='fullscreen'}",
            "fullscreen",
            None,
            None,
        ),
        (
            "{opacity=0.75,startup_size='maximized'}",
            "maximized",
            None,
            None,
        ),
    ] {
        fs::write(
            &config_path,
            format!("return {{ui_opts={{['com.naughie.nauvim.flutter']={{window={window}}}}}}}"),
        )
        .unwrap();
        let app = spawn(Some(path.clone())).unwrap();
        let mut updates = app.take_updates().await.unwrap();
        let options = receive(&mut updates, "ready").await.window_options.unwrap();
        let mode = match options.startup_mode {
            None => "restore",
            Some(DisplayStartupMode::Windowed) => "windowed",
            Some(DisplayStartupMode::Fullscreen) => "fullscreen",
            Some(DisplayStartupMode::Maximized) => "maximized",
        };
        assert_eq!(
            (mode, options.width, options.height, options.opacity),
            (expected, width, height, Some(0.75)),
            "{window}"
        );
        app.close().await.unwrap();
    }
}

#[tokio::test]
async fn close_cancels_a_pending_attachment_and_preserves_its_socket() {
    let root = tempfile::tempdir().unwrap();
    let socket = root.path().join("host.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let config = root.path().join("init.lua");
    fs::write(
        &config,
        format!(
            "return {{hosts = {{slow = {{socket = {:?}}}}}}}",
            socket.to_str().unwrap()
        ),
    )
    .unwrap();
    let app = spawn(Some(config.to_string_lossy().into_owned())).unwrap();
    let mut updates = app.updates.lock().await.take().unwrap();
    receive(&mut updates, "ready").await;
    app.start(80, 24).await.unwrap();
    receive(&mut updates, "welcome").await;
    app.connect("slow".into(), 80, 24).await.unwrap();
    receive(&mut updates, "connecting").await;
    let (_host, _) = timeout(Duration::from_secs(3), listener.accept())
        .await
        .unwrap()
        .unwrap();
    timeout(Duration::from_secs(3), app.close())
        .await
        .unwrap()
        .unwrap();
    receive(&mut updates, "shutdown").await;
    assert!(socket.exists());
    let error = app.input("x".into()).await.unwrap_err();

    assert!(matches!(error, Error::Stopping));
    assert_eq!(error.to_string(), "The Nauvim engine is shutting down");
}

#[tokio::test]
async fn close_completes_when_the_update_queue_has_no_subscriber() {
    let root = tempfile::tempdir().unwrap();
    let config = root.path().join("init.lua");
    fs::write(&config, "return {hosts = {unused = {}}}").unwrap();
    let app = spawn(Some(config.to_string_lossy().into_owned())).unwrap();
    timeout(Duration::from_secs(3), app.close())
        .await
        .unwrap()
        .unwrap();
    assert!(*app.stopped.borrow());
}

#[tokio::test]
#[ignore = "Requires NVIM_BIN pointing to Neovim v0.12.6 and local Unix sockets"]
async fn live_orders_input_reuses_hosts_and_follows_plugin_switches() {
    use std::env;

    let nvim = PathBuf::from(env::var_os("NVIM_BIN").expect("Set NVIM_BIN for this live test"));
    let version = ProcessCommand::new(&nvim)
        .arg("--version")
        .output()
        .unwrap();
    assert!(String::from_utf8_lossy(&version.stdout).starts_with("NVIM v0.12.6\n"));
    let root = tempfile::tempdir().unwrap();
    let first = Host {
        nvim: nvim.clone(),
        socket: root.path().join("first.sock"),
    };
    let second = Host {
        nvim,
        socket: root.path().join("second.sock"),
    };
    let config = root.path().join("init.lua");
    let hosts = [&first, &second]
        .into_iter()
        .zip(["first", "second"])
        .map(|(host, name)| {
            format!(
                "{name}={{nvim={{prog={:?},args={{'-u','NONE','-i','NONE','-n'}}}},socket={:?}}}",
                host.nvim.to_str().unwrap(),
                host.socket.to_str().unwrap(),
            )
        })
        .collect::<Vec<_>>()
        .join(",");
    fs::write(
        &config,
        format!("return {{default_host='first',hosts={{{hosts}}}}}"),
    )
    .unwrap();
    let app = spawn(Some(config.to_string_lossy().into_owned())).unwrap();
    let mut updates = app.updates.lock().await.take().unwrap();
    receive(&mut updates, "ready").await;
    app.start(80, 24).await.unwrap();
    receive(&mut updates, "frame").await;
    let first_pid = first.evaluate("getpid()");
    assert_eq!(first.evaluate("len(nvim_list_uis())"), "1");
    app.input("iα".into()).await.unwrap();
    app.input("<LT>Esc><Esc>".into()).await.unwrap();
    timeout(Duration::from_secs(3), async {
        loop {
            let update = updates.recv().await.unwrap();
            if update.frame.is_some_and(|frame| {
                frame.rows.iter().any(|row| {
                    row.cells
                        .iter()
                        .map(|cell| cell.text.as_str())
                        .collect::<String>()
                        .contains("α<Esc>")
                })
            }) {
                break;
            }
        }
    })
    .await
    .unwrap();
    assert_eq!(first.evaluate("getline(1)"), "α<Esc>");
    // Replay captured special-key display bytes. The following ordered event
    // proves progress even if Neovim clears showcmd before frames are painted.
    assert_eq!(
        first.evaluate(r#"luaeval("(function() local u=vim.api.nvim_list_uis()[1]; vim.rpcnotify(u.chan,'redraw',{'msg_showcmd',{{{0,string.char(0x7e,0x40,0xfd),0}}}},{'set_title',{'key display checked'}},{'flush',{}}); return true end)()")"#),
        "true"
    );
    timeout(Duration::from_secs(3), async {
        loop {
            let update = updates.recv().await.unwrap();
            assert_ne!(
                update.kind, "welcome",
                "Unexpected detach: {:?}",
                update.message
            );

            assert_ne!(
                update.kind, "error",
                "Unexpected key-display error: {:?}",
                update.message
            );

            if update.frame.is_some_and(|frame| {
                frame
                    .events
                    .iter()
                    .any(|event| event.kind == "title" && event.text == "key display checked")
            }) {
                break;
            }
        }
    })
    .await
    .unwrap();
    assert_eq!(first.evaluate("len(nvim_list_uis())"), "1");
    let stale_stamp = app.input_epoch.borrow().clone();
    let stale_permit = app.input.reserve().await.unwrap();
    app.detach().await.unwrap();
    receive(&mut updates, "welcome").await;
    app.connect("first".into(), 90, 28).await.unwrap();
    receive(&mut updates, "frame").await;
    assert_eq!(first.evaluate("getpid()"), first_pid);
    assert_eq!(first.evaluate("getline(1)"), "α<Esc>");
    stale_permit.send(QueuedInput {
        epoch: stale_stamp,
        input: Input::Host(HostInput::Keys("iSTALE<Esc>".into())),
    });
    app.input("A!<Esc>".into()).await.unwrap();
    timeout(Duration::from_secs(3), async {
        loop {
            let update = updates.recv().await.unwrap();
            if update.frame.is_some_and(|frame| {
                frame
                    .rows
                    .iter()
                    .any(|row| row.cells.iter().any(|cell| cell.text.contains('!')))
            }) {
                break;
            }
        }
    })
    .await
    .unwrap();
    assert_eq!(first.evaluate("getline(1)"), "α<Esc>!");
    first.evaluate(r#"luaeval("(function() local ui=vim.api.nvim_list_uis()[1]; local name=vim.api.nvim_get_chan_info(ui.chan).client.name; local id=tonumber(name:match('(%d+)$')); vim.rpcnotify(ui.chan,'nauvim-plugin/client.connect',id,'second'); vim.fn.chanclose(ui.chan); return true end)()")"#);
    receive(&mut updates, "welcome").await;
    assert_eq!(
        receive(&mut updates, "connecting").await.message.as_deref(),
        Some("second")
    );
    receive(&mut updates, "frame").await;
    assert_eq!(first.evaluate("len(nvim_list_uis())"), "0");
    assert_eq!(second.evaluate("len(nvim_list_uis())"), "1");
    let second_pid = second.evaluate("getpid()");
    app.close().await.unwrap();
    receive(&mut updates, "shutdown").await;
    assert_eq!(second.evaluate("getpid()"), second_pid);
    assert_eq!(second.evaluate("len(nvim_list_uis())"), "0");
}

fn input_endpoint() -> (
    Handle,
    mpsc::Receiver<QueuedInput>,
    watch::Sender<CancellationToken>,
) {
    let (commands, _commands) = mpsc::channel(1);
    let (input, receiver) = mpsc::channel(1);
    let (epoch_tx, input_epoch) = watch::channel(CancellationToken::new());
    let (_updates, updates) = mpsc::channel(1);
    let (_stopped, stopped) = watch::channel(true);
    let (window_size, _) = watch::channel(None);
    (
        Handle {
            commands,
            input,
            input_epoch,
            stop: CancellationToken::new(),
            stopped,
            window_size,
            updates: Mutex::new(Some(updates)),
        },
        receiver,
        epoch_tx,
    )
}

#[tokio::test]
async fn cancels_a_blocked_input_sender_when_its_attachment_changes() {
    use std::future::{Future as _, poll_fn};
    use std::task::Poll;

    let (app, mut input, epoch) = input_endpoint();
    app.input("queued-old-input".into()).await.unwrap();
    let deferred = app.input("deferred-old-input".into());
    tokio::pin!(deferred);
    poll_fn(|cx| {
        assert!(deferred.as_mut().poll(cx).is_pending());
        Poll::Ready(())
    })
    .await;
    epoch.send_replace(CancellationToken::new()).cancel();
    assert!(input.try_recv().unwrap().into_current().is_none());
    deferred.await.unwrap();
    assert!(matches!(
        input.try_recv(),
        Err(mpsc::error::TryRecvError::Empty)
    ));
    app.input("new-input".into()).await.unwrap();
    let Some(Input::Host(HostInput::Keys(keys))) = input.recv().await.unwrap().into_current()
    else {
        panic!("Expected current-attachment keys");
    };
    assert_eq!(keys, "new-input");
}

#[tokio::test]
async fn rejects_input_enqueued_after_its_reserved_permit_outlives_an_attachment() {
    let (app, mut input, epoch) = input_endpoint();
    let stamp = app.input_epoch.borrow().clone();
    let permit = app.input.reserve().await.unwrap();
    epoch.send_replace(CancellationToken::new()).cancel();
    permit.send(QueuedInput {
        epoch: stamp,
        input: Input::Paste,
    });
    assert!(input.recv().await.unwrap().into_current().is_none());
    app.paste().await.unwrap();
    assert!(matches!(
        input.recv().await.unwrap().into_current(),
        Some(Input::Paste)
    ));
}

#[tokio::test]
#[ignore = "Requires NVIM_BIN pointing to Neovim v0.12.6 and local Unix sockets"]
async fn live_preview_checks_navigation_and_tracks_focus_and_close() {
    let root = tempfile::tempdir().unwrap();
    let (host, app, mut updates) = live_application(root.path()).await;
    let open = r#"luaeval("(function()
        local chan = vim.api.nvim_list_uis()[1].chan
        local name = vim.api.nvim_get_chan_info(chan).client.name
        local id = tonumber(name:match('(%d+)$'))
        local position = {grid=1, top=1, left=2, height=3, width=4}
        local handle = vim.rpcrequest(chan, 'nauvim-plugin/http.open_webview',
            id, 'https://example.test/preview', position, false, true)
        _G.preview_notify = function(method)
            vim.rpcnotify(chan, 'nauvim-plugin/http.' .. method, id, handle)
            return true
        end
        return handle
    end)()")"#;
    let handle = host
        .evaluate(&open.replace('\n', " "))
        .parse::<i64>()
        .unwrap();

    let preview = receive(&mut updates, "open_webview").await.window.unwrap();
    assert_eq!(preview.handle, handle);
    assert_eq!(preview.url, "https://example.test/preview");
    assert_eq!(
        (
            preview.grid,
            preview.top,
            preview.left,
            preview.height,
            preview.width
        ),
        (1, 1, 2, 3, 4),
    );
    assert!(!preview.focus);
    assert!(preview.focusable);

    let webview = preview.webview.unwrap();
    assert!(!webview.can_focus().await);
    assert!(webview.allows_navigation(preview.url).await);
    assert!(webview.opened().await);
    assert!(webview.can_focus().await);
    assert!(
        !webview
            .allows_navigation("https://other.test/redirect".into())
            .await
    );
    assert_eq!(
        receive(&mut updates, "error").await.message.as_deref(),
        Some("Client policy denies Webview navigation to \"https://other.test/redirect\"")
    );

    host.evaluate(r#"luaeval("_G.preview_notify('focus_webview')")"#);
    let focus = receive(&mut updates, "focus_webview").await.window.unwrap();
    assert_eq!(focus.handle, handle);
    assert!(focus.webview.is_none());

    host.evaluate(r#"luaeval("_G.preview_notify('clear')")"#);
    let close = receive(&mut updates, "close_webview").await.window.unwrap();
    assert_eq!(close.handle, handle);
    assert!(close.webview.is_none());
    assert!(!webview.can_focus().await);
    assert!(!webview.opened().await);

    app.close().await.unwrap();
    receive(&mut updates, "shutdown").await;
}

#[tokio::test]
#[ignore = "Requires NVIM_BIN pointing to Neovim v0.12.6 and local Unix sockets"]
async fn live_switches_tabs_after_reattachment() {
    use crate::api::display::DisplayFrame;

    async fn visible_buffer(
        updates: &mut mpsc::Receiver<UiUpdate>,
        text: &str,
    ) -> (i64, DisplayFrame) {
        timeout(Duration::from_secs(3), async {
            loop {
                let update = updates.recv().await.unwrap();
                assert_ne!(update.kind, "welcome", "{:?}", update.message);
                assert_ne!(update.kind, "error", "{:?}", update.message);

                let Some(frame) = update.frame else {
                    continue;
                };
                if let Some(row) = frame.rows.iter().find(|row| {
                    row.grid != 1
                        && row.row == 0
                        && row
                            .cells
                            .iter()
                            .map(|cell| cell.text.as_str())
                            .collect::<String>()
                            .starts_with(text)
                        && frame.grids.iter().any(|g| g.id == row.grid && !g.hidden)
                }) {
                    return (row.grid, frame);
                }
            }
        })
        .await
        .unwrap_or_else(|_| panic!("Did not draw {text:?} in a visible window"))
    }

    let root = tempfile::tempdir().unwrap();
    let (host, app, mut updates) = live_application(root.path()).await;
    let pid = host.evaluate("getpid()");

    app.input("ifirst tab buffer<Esc>".into()).await.unwrap();
    visible_buffer(&mut updates, "first tab buffer").await;
    for (keys, text) in [
        (":tabnew<CR>isecond tab buffer<Esc>", "second tab buffer"),
        (":tabnew<CR>ithird tab buffer<Esc>", "third tab buffer"),
    ] {
        app.input(keys.into()).await.unwrap();
        visible_buffer(&mut updates, text).await;
    }

    app.input(":detach<CR>".into()).await.unwrap();
    assert_eq!(receive(&mut updates, "welcome").await.message, None);

    app.connect("test".into(), 80, 24).await.unwrap();
    let (mut previous_grid, _) = visible_buffer(&mut updates, "third tab buffer").await;
    assert_eq!(host.evaluate("tabpagenr()"), "3");

    for (text, tab) in [("first tab buffer", "1"), ("second tab buffer", "2")] {
        app.input(":tabnext<CR>".into()).await.unwrap();
        let (grid, frame) = visible_buffer(&mut updates, text).await;
        assert_ne!(grid, previous_grid);
        assert!(
            frame
                .grids
                .iter()
                .all(|g| g.id != previous_grid || g.hidden),
            "Grid {previous_grid} stayed visible after switching to tab {tab}"
        );
        assert_eq!(host.evaluate("tabpagenr()"), tab);
        previous_grid = grid;
    }

    assert_eq!(host.evaluate("getpid()"), pid);
    assert_eq!(host.evaluate("len(nvim_list_uis())"), "1");

    app.close().await.unwrap();
    receive(&mut updates, "shutdown").await;
}

#[tokio::test]
#[ignore = "Requires NVIM_BIN pointing to Neovim v0.12.6 and local Unix sockets"]
async fn live_restores_split_buffers_before_input_after_detach_and_reattach() {
    let root = tempfile::tempdir().unwrap();
    let (host, app, mut updates) = live_application(root.path()).await;
    let pid = host.evaluate("getpid()");
    let snapshot = r#"luaeval("(function() local result={{vim.o.cmdheight,vim.o.laststatus,vim.o.guifont,vim.o.scrolloff,vim.o.sidescrolloff}}; for _,w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do local p=vim.api.nvim_win_get_position(w); local v=vim.api.nvim_win_call(w,vim.fn.winsaveview); result[#result+1]={w,p[1],p[2],vim.api.nvim_win_get_width(w),vim.api.nvim_win_get_height(w),v.lnum,v.col,v.coladd,v.curswant,v.topline,v.topfill,v.leftcol,v.skipcol} end; return vim.json.encode(result) end)()")"#;
    host.evaluate(r#"luaeval("(function() vim.api.nvim_buf_set_lines(0,0,-1,false,{'first buffer line','second buffer line','third buffer line'}); vim.cmd('vsplit'); vim.cmd('wincmd ='); return true end)()")"#);

    timeout(Duration::from_secs(3), async {
        let mut drawn = BTreeSet::new();
        loop {
            let update = updates.recv().await.unwrap();
            if let Some(frame) = update.frame {
                for row in frame.rows {
                    if row.row == 0
                        && row
                            .cells
                            .iter()
                            .map(|c| c.text.as_str())
                            .collect::<String>()
                            .contains("first buffer line")
                    {
                        drawn.insert(row.grid);
                    }
                }
            }
            if drawn.len() == 2 {
                break;
            }
        }
    })
    .await
    .unwrap();

    for _ in 0..2 {
        app.input(":detach<CR>".into()).await.unwrap();
        let welcome = receive(&mut updates, "welcome").await;
        assert_eq!(welcome.message, None);
        let preserved = host.evaluate(snapshot);
        app.connect("test".into(), 80, 24).await.unwrap();

        let first = timeout(Duration::from_secs(3), async {
            loop {
                let update = updates.recv().await.unwrap();
                assert_ne!(update.kind, "welcome", "{:?}", update.message);
                assert_ne!(update.kind, "error", "{:?}", update.message);
                if let Some(frame) = update.frame {
                    break frame;
                }
            }
        })
        .await
        .unwrap();
        let mut windows = first.grids.iter().filter(|g| g.id != 1).collect::<Vec<_>>();
        windows.sort_by(|a, b| a.col.total_cmp(&b.col));

        assert_eq!(windows.len(), 2);
        assert!(windows.iter().all(|g| !g.hidden));
        assert_eq!(
            (windows[0].row, windows[0].col, windows[1].row),
            (0.0, 0.0, 0.0)
        );
        assert!(windows[1].col >= f64::from(windows[0].width));
        for window in windows {
            let row = first
                .rows
                .iter()
                .find(|row| row.grid == window.id && row.row == 0)
                .unwrap();
            assert!(
                row.cells
                    .iter()
                    .map(|c| c.text.as_str())
                    .collect::<String>()
                    .contains("first buffer line"),
                "Grid {} first row: {:?}",
                window.id,
                row.cells
                    .iter()
                    .map(|c| c.text.as_str())
                    .collect::<String>()
            );
        }
        assert_eq!(host.evaluate("getpid()"), pid);
        assert_eq!(host.evaluate("&cmdheight"), "0");
        assert_eq!(host.evaluate("len(nvim_list_uis())"), "1");
        assert_eq!(host.evaluate(snapshot), preserved);
        assert_eq!(host.evaluate("nvim_list_uis()[0].ext_multigrid"), "true");
    }

    app.close().await.unwrap();
    receive(&mut updates, "shutdown").await;
    assert_eq!(host.evaluate("len(nvim_list_uis())"), "0");
}

#[tokio::test]
#[ignore = "Requires NVIM_BIN pointing to Neovim v0.12.6 and local Unix sockets"]
async fn live_restores_bordered_floats_before_input_after_reattachment() {
    let root = tempfile::tempdir().unwrap();
    let (host, app, mut updates) = live_application(root.path()).await;
    host.evaluate(r#"luaeval("(function() local b=vim.api.nvim_create_buf(false,true); vim.api.nvim_buf_set_lines(b,0,-1,false,{'floating first','second row'}); local w=vim.api.nvim_open_win(b,false,{relative='editor',row=3.5,col=5.25,width=24,height=3,border='single',title='first',zindex=60}); local b2=vim.api.nvim_create_buf(false,true); vim.api.nvim_buf_set_lines(b2,0,-1,false,{'floating second'}); local w2=vim.api.nvim_open_win(b2,false,{relative='win',win=w,row=1,col=2,width=18,height=2,border='double',zindex=70}); local hidden=vim.api.nvim_create_buf(false,true); vim.api.nvim_buf_set_lines(hidden,0,-1,false,{'hidden float'}); vim.api.nvim_open_win(hidden,false,{relative='editor',row=8,col=4,width=16,height=2,hide=true,zindex=80}); vim.g.float_windows={w,w2}; return true end)()")"#);

    let initial = timeout(Duration::from_secs(3), async {
        let mut drawn = BTreeSet::new();
        loop {
            let update = updates.recv().await.unwrap();
            if let Some(frame) = update.frame {
                for row in &frame.rows {
                    let text = row
                        .cells
                        .iter()
                        .map(|c| c.text.as_str())
                        .collect::<String>();
                    for expected in ["floating first", "floating second"] {
                        if text.contains(expected) {
                            drawn.insert(expected);
                        }
                    }
                }
                if drawn.len() == 2 {
                    break frame;
                }
            }
        }
    })
    .await
    .unwrap();
    let mut expected = initial
        .grids
        .iter()
        .filter(|g| g.zindex >= 60)
        .map(|g| (g.id, g.width, g.height, g.row, g.col, g.zindex, g.order))
        .collect::<Vec<_>>();
    assert_eq!(expected.len(), 2);
    let configs = r#"luaeval("(function() local ret={}; for _,w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do ret[#ret+1]={w,vim.api.nvim_win_get_config(w),vim.api.nvim_win_get_cursor(w)} end; return vim.inspect(ret) end)()")"#;

    for cycle in 0..2 {
        if cycle == 1 {
            host.evaluate(r#"luaeval("(function() local windows=vim.g.float_windows; vim.api.nvim_win_set_config(windows[2],{zindex=60}); vim.api.nvim_set_current_win(windows[1]); return true end)()")"#);
            let stacked = timeout(Duration::from_secs(3), async {
                loop {
                    if let Some(frame) = updates.recv().await.unwrap().frame {
                        let floats = frame
                            .grids
                            .iter()
                            .filter(|g| g.zindex == 60)
                            .collect::<Vec<_>>();
                        if floats.len() == 2 && floats[0].order > floats[1].order {
                            break frame;
                        }
                    }
                }
            })
            .await
            .unwrap();
            expected = stacked
                .grids
                .iter()
                .filter(|g| g.zindex == 60)
                .map(|g| (g.id, g.width, g.height, g.row, g.col, g.zindex, g.order))
                .collect();
        }
        app.input(":detach<CR>".into()).await.unwrap();
        assert_eq!(receive(&mut updates, "welcome").await.message, None);
        let preserved = host.evaluate(configs);
        app.connect("test".into(), 80, 24).await.unwrap();
        let restored = timeout(Duration::from_secs(3), async {
            loop {
                let update = updates.recv().await.unwrap();
                assert_ne!(update.kind, "welcome", "{:?}", update.message);
                assert_ne!(update.kind, "error", "{:?}", update.message);
                if let Some(frame) = update.frame {
                    break frame;
                }
            }
        })
        .await
        .unwrap();
        for (id, width, height, row, col, zindex, order) in &expected {
            let grid = restored.grids.iter().find(|g| g.id == *id).unwrap();
            assert!(!grid.hidden, "Float {id} is hidden");
            assert_eq!(
                (
                    grid.width,
                    grid.height,
                    grid.row,
                    grid.col,
                    grid.zindex,
                    grid.order
                ),
                (*width, *height, *row, *col, *zindex, *order)
            );
        }
        for expected in ["floating first", "floating second"] {
            assert!(
                restored.rows.iter().any(|row| row
                    .cells
                    .iter()
                    .map(|c| c.text.as_str())
                    .collect::<String>()
                    .contains(expected)),
                "Missing float text {expected:?}"
            );
        }
        assert_eq!(
            restored
                .grids
                .iter()
                .filter(|g| !g.hidden && g.zindex >= 50)
                .count(),
            2
        );
        assert_eq!(host.evaluate(configs), preserved);
        assert_eq!(host.evaluate("&cmdheight"), "0");
    }
    app.close().await.unwrap();
    receive(&mut updates, "shutdown").await;
}

#[tokio::test]
#[ignore = "Requires NVIM_BIN pointing to Neovim v0.12.6, /bin/sh, and local Unix sockets"]
async fn live_restores_terminal_float_and_mode_after_reattachment() {
    let root = tempfile::tempdir().unwrap();
    let (host, app, mut updates) = live_application(root.path()).await;
    host.evaluate(r#"luaeval("(function() local b=vim.api.nvim_create_buf(false,true); vim.api.nvim_open_win(b,true,{relative='editor',row=2,col=4,width=30,height=6,border='rounded',title='terminal',zindex=90}); vim.fn.jobstart({'/bin/sh','-c','printf terminal_float; sleep 30'},{term=true}); vim.cmd('startinsert'); return true end)()")"#);
    let initial = timeout(Duration::from_secs(3), async {
        loop {
            if let Some(frame) = updates.recv().await.unwrap().frame
                && frame.mode == "terminal"
                && frame.rows.iter().any(|row| {
                    row.cells
                        .iter()
                        .map(|c| c.text.as_str())
                        .collect::<String>()
                        .contains("terminal_float")
                })
            {
                break frame;
            }
        }
    })
    .await
    .unwrap();
    let expected = initial.grids.iter().find(|g| g.zindex == 90).unwrap();
    let config = r#"luaeval("vim.inspect(vim.api.nvim_win_get_config(0))")"#;
    let preserved = host.evaluate(config);
    assert_eq!(host.evaluate("mode()"), "t");
    app.detach().await.unwrap();
    assert_eq!(receive(&mut updates, "welcome").await.message, None);
    app.connect("test".into(), 80, 24).await.unwrap();
    let restored = timeout(Duration::from_secs(3), async {
        loop {
            let update = updates.recv().await.unwrap();
            assert_ne!(update.kind, "welcome", "{:?}", update.message);
            assert_ne!(update.kind, "error", "{:?}", update.message);
            if let Some(frame) = update.frame {
                break frame;
            }
        }
    })
    .await
    .unwrap();
    let grid = restored.grids.iter().find(|g| g.id == expected.id).unwrap();
    assert!(!grid.hidden);
    assert_eq!(
        (grid.row, grid.col, grid.width, grid.height, grid.zindex),
        (
            expected.row,
            expected.col,
            expected.width,
            expected.height,
            expected.zindex
        )
    );
    assert!(restored.rows.iter().any(|row| {
        row.grid == grid.id
            && row
                .cells
                .iter()
                .map(|c| c.text.as_str())
                .collect::<String>()
                .contains("terminal_float")
    }));
    assert_eq!(restored.mode, "terminal");
    assert_eq!(host.evaluate("mode()"), "t");
    assert_eq!(host.evaluate(config), preserved);
    app.close().await.unwrap();
    receive(&mut updates, "shutdown").await;
}
