#!/usr/bin/env python3
"""Check desktop attachment, previews, switching, shutdown, and host reuse."""

import argparse
import http.server
import json
import os
import pathlib
import platform
import shutil
import signal
import subprocess
import tempfile
import threading
import time

PROJECT = pathlib.Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=pathlib.Path)
    parser.add_argument("--nvim", default=os.environ.get("NVIM_BIN", "nvim"))
    args = parser.parse_args()
    nvim = shutil.which(args.nvim)
    if nvim is None:
        parser.error("Neovim executable was not found")
    version = subprocess.check_output([nvim, "--version"], text=True, timeout=5)
    if version.splitlines()[0] != "NVIM v0.12.6":
        parser.error("This check requires Neovim v0.12.6")
    if platform.system() == "Darwin":
        binary = PROJECT / "build/macos/Build/Products/Release/Nauvim.app/Contents/MacOS/Nauvim"
    else:
        arch = "arm64" if platform.machine() in ("aarch64", "arm64") else "x64"
        binary = PROJECT / "build/linux" / arch / "release/bundle/nauvim"
    binary = (args.binary or binary).resolve()
    if not binary.is_file():
        parser.error(f"Build the release application first: {binary}")

    with tempfile.TemporaryDirectory(prefix="nauvim-gui-smoke-") as directory:
        root = pathlib.Path(directory)
        sockets = {name: root / f"{name}.sock" for name in ("first", "second")}
        config = root / "init.lua"
        hosts = ",".join(
            f"{name}={{nvim={{prog={json.dumps(nvim)},args={{'-u','NONE','-i','NONE','-n'}}}},"
            f"socket={json.dumps(str(socket))}}}"
            for name, socket in sockets.items()
        )
        config.write_text(f"return {{default_host='first',hosts={{{hosts}}}," + """
            ui_opts = { ["com.naughie.nauvim.flutter"] = {
                key_bindings = {
                    welcome = { ["Ctrl-q"] = "quit" },
                    clipboard = { ["Alt_v"] = "paste" },
                    webview = { ["F5"] = "reload", ["Escape"] = "focus_editor" },
                },
            }},
        }""")
        env = dict(os.environ)
        env["NVIM_LOG_FILE"] = str(root / "nvim.log")
        for key in ("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR"):
            path = root / key.lower()
            path.mkdir(mode=0o700)
            env[key] = str(path)
        process = None
        server = None

        def evaluate(host, expression):
            return subprocess.check_output(
                [nvim, "--server", str(sockets[host]), "--remote-expr", expression],
                env=env, text=True, stderr=subprocess.PIPE, timeout=5,
            ).strip()

        def lua(host, source):
            return evaluate(host, "luaeval('" + source.replace("'", "''") + "')")

        def wait_attachment(host, count):
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                if process is not None and process.poll() is not None:
                    raise RuntimeError(f"GUI exited before attachment: {process.returncode}")
                if sockets[host].exists():
                    try:
                        if evaluate(host, "len(nvim_list_uis())") == str(count):
                            return
                    except (subprocess.SubprocessError, ValueError):
                        pass
                time.sleep(0.1)
            raise RuntimeError(f"Host {host} did not reach {count} attached UIs")

        def stop():
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=20)
            assert process.returncode == 0, f"SIGTERM exit code: {process.returncode}"

        try:
            with (root / "gui.log").open("w") as log:
                process = subprocess.Popen([str(binary), "--config", str(config)], stdout=log,
                                           stderr=subprocess.STDOUT, env=env)
                wait_attachment("first", 1)
                first_pid = evaluate("first", "getpid()")
                print("Attached first host", first_pid, flush=True)

                # Exercise structured completion data through the real bridge.
                lua("first", """(function()
                    vim.o.completeopt = 'menuone,noselect,noinsert'
                    vim.keymap.set('i', '<F5>', function()
                        vim.fn.complete(1, {
                            {word='alpha', kind='f', menu='[LSP]', info='First item'},
                            {word='beta', kind='v', menu='[Buffer]', info='Second item'},
                        })
                    end)
                    vim.api.nvim_input('i<F5>')
                    return true
                end)()""")
                deadline = time.monotonic() + 5
                while evaluate("first", "pumvisible()") != "1":
                    if time.monotonic() >= deadline:
                        raise RuntimeError("Neovim completion menu did not open")
                    time.sleep(0.05)
                time.sleep(0.2)
                assert process.poll() is None, "GUI exited while displaying completions"
                lua("first", "vim.api.nvim_input('<Esc>')")
                print("Exercised structured completion updates", flush=True)

                fetched = threading.Event()

                class Handler(http.server.BaseHTTPRequestHandler):
                    def do_GET(self):
                        if self.path == "/index.html":
                            fetched.set()
                            self.send_response(200)
                            self.end_headers()
                            self.wfile.write(b"<h1>Nauvim preview</h1>")
                        else:
                            self.send_error(404)

                    def log_message(self, *_args):
                        pass

                server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
                threading.Thread(target=server.serve_forever, daemon=True).start()
                url = f"http://127.0.0.1:{server.server_port}/index.html#fragment"
                prefix = ("local u=vim.api.nvim_list_uis()[1]; "
                          "local id=tonumber(vim.api.nvim_get_chan_info(u.chan).client.name:match('(%d+)$')); ")
                handle = lua("first", "(function() " + prefix +
                             "return vim.rpcrequest(u.chan,'nauvim-plugin/http.open_webview',id," +
                             json.dumps(url) + ",{grid=1,top=1,left=1,height=3,width=16}) end)()")
                assert fetched.wait(15), "Native preview did not fetch its URL"
                lua("first", "(function() " + prefix +
                    "return vim.rpcnotify(u.chan,'nauvim-plugin/http.clear',id," + handle + ") end)()")
                print("Opened and cleared native HTTP preview", flush=True)

                lua("first", "(function() " + prefix +
                    "vim.rpcnotify(u.chan,'nauvim-plugin/client.connect',id,'second'); "
                    # This evaluation uses an independent control RPC channel;
                    # detach the identified GUI rather than that control channel.
                    "vim.fn.chanclose(u.chan); return true end)()")
                wait_attachment("second", 1)
                wait_attachment("first", 0)
                second_pid = evaluate("second", "getpid()")
                print("Switched to second host", second_pid, flush=True)

                stop()
                assert evaluate("second", "len(nvim_list_uis())") == "0"
                assert evaluate("second", "getpid()") == second_pid
                process = subprocess.Popen([str(binary), "--config", str(config)], stdout=log,
                                           stderr=subprocess.STDOUT, env=env)
                wait_attachment("first", 1)
                assert evaluate("first", "getpid()") == first_pid
                stop()
                assert evaluate("first", "len(nvim_list_uis())") == "0"
                assert evaluate("first", "getpid()") == first_pid
                print("SIGTERM cleanup and same-host reattachment passed", flush=True)
        except subprocess.CalledProcessError as error:
            print(error.stderr)
            print((root / "gui.log").read_text())
            raise
        except Exception:
            print((root / "gui.log").read_text())
            raise
        finally:
            if server is not None:
                server.shutdown()
                server.server_close()
            if process is not None and process.poll() is None:
                process.kill()
                process.wait()
            for host, socket in sockets.items():
                if socket.exists():
                    try:
                        evaluate(host, 'execute("qa!")')
                    except subprocess.SubprocessError:
                        pass


if __name__ == "__main__":
    main()
