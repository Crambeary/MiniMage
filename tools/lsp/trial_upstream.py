#!/usr/bin/env python3
"""Trial pinned upstream MCP tools against two disposable Godot worktrees.

No model is run. Real MCP JSON-RPC requests exercise the packaged server and
real editors. Session capability files are consumed only by the upstream server.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import queue
import shutil
import socket
import subprocess
import tempfile
import threading
import time

from probe_codex_mcp import probe as probe_codex

REPO = Path(__file__).resolve().parents[2]
PACKAGE = "@shin2344234/godot-mcp"
VERSION = "0.1.2"
VALID = "extends Node\nvar count: int = 1\n"
SYNTAX = "extends Node\nfunc broken(\n"
TYPE = 'extends Node\nvar count: int = "bad"\n'


def run(args, cwd):
    return subprocess.check_output(args, cwd=cwd, text=True, stderr=subprocess.STDOUT)


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class Client:
    def __init__(self, package, root, godot, port):
        self.root = root
        self.messages = queue.Queue()
        self.counter = 0
        self.process = subprocess.Popen([
            "node", str(package / "dist/index.js"), "--project", str(root),
            "--godot", str(godot), "--toolsets", "code", "--read-only",
        ], cwd=root, env=dict(os.environ, GODOT_MCP_LSP_PORT=str(port),
                             GODOT_MCP_LSP_TIMEOUT_MS="5000",
                             GODOT_MCP_BRIDGE_TIMEOUT_MS="3000",
                             GODOT_MCP_HEADLESS_TIMEOUT_MS="20000"),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True)

        def read():
            for line in self.process.stdout:
                self.messages.put(json.loads(line))
            self.messages.put(None)

        self.reader = threading.Thread(target=read, daemon=True)
        self.reader.start()
        reply = self.rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                                       "clientInfo": {"name": "frytruck-upstream-trial", "version": "1"}})
        assert reply["serverInfo"]["version"] == VERSION, reply["serverInfo"]
        self.process.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
        self.process.stdin.flush()

    def rpc(self, method, params):
        self.counter += 1
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.counter,
                                            "method": method, "params": params}) + "\n")
        self.process.stdin.flush()
        deadline = time.monotonic() + 45
        while True:
            reply = self.messages.get(timeout=max(.01, deadline - time.monotonic()))
            if reply is None:
                raise EOFError("upstream MCP server exited")
            if reply.get("id") == self.counter:
                if "error" in reply:
                    raise ValueError(reply["error"])
                return reply["result"]

    def call(self, name, arguments):
        reply = self.rpc("tools/call", {"name": name, "arguments": arguments})
        data = reply.get("structuredContent")
        if data is None:
            text = reply["content"][0]["text"]
            try:
                data = json.loads(text)
            except json.JSONDecodeError:
                if not reply.get("isError"):
                    raise
                data = {"message": text}
        return {"isError": bool(reply.get("isError")), "data": data}

    def diagnose(self):
        return self.call("godot_code_diagnostics", {"paths": ["res://sample.gd"]})

    def close(self):
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.reader.join(timeout=2)
        self.process.stdin.close()
        self.process.stdout.close()


def assert_result(result, source, has_errors):
    assert not result["isError"], result
    data = result["data"]
    assert data["source"].startswith(source), result
    assert data["checked"] == 1 and not data.get("unchecked"), result
    assert (data["errors"] > 0) == has_errors, result
    assert ("res://sample.gd" in data["clean"]) != has_errors, result
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-root", required=True, type=Path,
                        help="installed @shin2344234/godot-mcp@0.1.2 directory")
    parser.add_argument("--godot", type=Path, default=Path(os.environ.get(
        "GODOT_BIN", str(Path.home() / ".local/share/Ryko.GodotHub/godot-versions/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64"))))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    package, godot = args.package_root.resolve(), args.godot.resolve()
    metadata = json.loads((package / "package.json").read_text())
    assert metadata["version"] == VERSION, metadata["version"]
    results = {}
    editors, clients = [], []
    with tempfile.TemporaryDirectory(prefix="frytruck-upstream-trial-") as temp:
        root = Path(temp) / "primary"
        root.mkdir()
        shutil.copytree(package / "addon/godot_mcp", root / "addons/godot_mcp")
        (root / "tools").mkdir()
        shutil.copy2(REPO / "tools/open-editor.sh", root / "tools/open-editor.sh")
        (root / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="Upstream LSP trial"\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
            '[editor_plugins]\nenabled=PackedStringArray("res://addons/godot_mcp/plugin.cfg")\n')
        (root / ".gitignore").write_text(".godot/\n")
        (root / "sample.gd").write_text(VALID)
        run(["git", "init", "-b", "main"], root)
        run(["git", "add", "."], root)
        run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.test",
             "commit", "-m", "Disposable LSP fixture", "--no-verify"], root)
        creation = run(["wt", "switch", "-c", "linked", "--base", "main", "--no-hooks",
                        "--format", "json", "--no-cd"], root)
        linked = Path(json.loads(creation.splitlines()[0])["path"])
        roots = [root, linked]
        ports = [free_port(), free_port()]

        def client(index, port=None, engine=godot):
            item = Client(package, roots[index], engine, port or ports[index])
            clients.append(item)
            return item

        try:
            for index, project in enumerate(roots):
                editor = subprocess.Popen([
                    "bash", "tools/open-editor.sh", "--lsp-port", str(ports[index]),
                    "--dap-port", str(free_port()),
                ], cwd=project, env=dict(os.environ, GODOT_BIN=str(godot)),
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                editors.append(editor)
            for index, port in enumerate(ports):
                deadline = time.monotonic() + 45
                while True:
                    if editors[index].poll() is not None:
                        raise RuntimeError("fixture editor exited before LSP startup")
                    try:
                        with socket.create_connection(("127.0.0.1", port), timeout=.2):
                            break
                    except OSError:
                        if time.monotonic() >= deadline:
                            raise TimeoutError("fixture editor did not start LSP")
                        time.sleep(.1)
            a, b = client(0), client(1)
            tools = a.rpc("tools/list", {})["tools"]
            assert all(t.get("annotations", {}).get("readOnlyHint") for t in tools), tools
            results["read_only_tools"] = [t["name"] for t in tools]
            for index, item in enumerate([a, b]):
                status = item.call("godot_status", {})["data"]
                assert status["editor_connected"], status
                assert Path(status["editor"]["project_path"]) == roots[index], status
            (root / "sample.gd").write_text(SYNTAX)
            (linked / "sample.gd").write_text(TYPE)
            with ThreadPoolExecutor(max_workers=2) as pool:
                futures = [pool.submit(item.diagnose) for item in [a, b]]
                bad = [assert_result(f.result(), "lsp (connected editor)", True) for f in futures]
            assert "Expected closing" in json.dumps(bad[0]), bad[0]
            assert "Cannot assign" in json.dumps(bad[1]), bad[1]
            results["concurrent_worktree_errors"] = bad
            for project in roots:
                (project / "sample.gd").write_text(VALID)
            results["cleared_after_disk_fix"] = [
                assert_result(item.diagnose(), "lsp (connected editor)", False) for item in [a, b]]
            outside = a.call("godot_code_diagnostics", {"paths": [str(linked / "sample.gd")]})
            assert outside["isError"], outside
            results["outside_worktree_rejected"] = outside
            (root / "sample.gd").write_text(SYNTAX)
            wrong = client(0, ports[1]).diagnose()
            assert_result(wrong, "script.validate (language server unavailable:", True)
            assert "another Godot editor" in wrong["data"]["source"], wrong
            results["wrong_editor_port"] = wrong
            unavailable = client(0, free_port()).diagnose()
            assert_result(unavailable, "script.validate (language server unavailable:", True)
            assert "not reachable" in unavailable["data"]["source"], unavailable
            results["unavailable_lsp_port"] = unavailable
            results["native_codex_mcp"] = probe_codex(
                root, root, "node", [str(package / "dist/index.js"), "--project", str(root),
                "--godot", str(godot), "--toolsets", "code", "--read-only"],
                {"GODOT_MCP_LSP_PORT": str(ports[0])})
            editors[1].terminate()
            editors[1].wait(timeout=10)
            (linked / "sample.gd").write_text(TYPE)
            private = client(1)
            results["editor_closed"] = assert_result(private.diagnose(), "lsp (private headless editor)", True)
            (linked / "sample.gd").write_text(VALID)
            results["private_editor_cleared"] = assert_result(private.diagnose(), "lsp (private headless editor)", False)
            private.close()
            clients.remove(private)
            missing = client(1, engine=Path(temp) / "missing-godot").diagnose()
            assert missing["isError"], missing
            results["editor_and_engine_unavailable"] = missing
        finally:
            for item in clients:
                item.close()
            for editor in editors:
                if editor.poll() is None:
                    editor.terminate()
                    try:
                        editor.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        editor.kill()
                        editor.wait()
            run(["wt", "remove", "linked", "--force", "--foreground", "--no-hooks", "--yes"], root)
        # Retain useful diagnostic evidence without machine-local fixture paths.
        text = json.dumps(results)
        for project, label in [(linked, "<linked>"), (root, "<primary>")]:
            text = text.replace(str(project), label)
        text = text.replace(temp, "<fixture>")
        report = {"package": PACKAGE, "version": VERSION, "scope": "real MCP and native Codex tool calls, two fixture editors; no automatic hook test",
                  "results": json.loads(text)}
        serialized = json.dumps(report, indent=2) + "\n"
        if args.output:
            args.output.write_text(serialized)
        print(serialized)


if __name__ == "__main__":
    main()
