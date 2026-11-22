#!/usr/bin/env python3
"""Exercise diagnostic acknowledgments, routing failures and Codex feedback."""
from contextlib import contextmanager, redirect_stdout
import io
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import codex_hook
from diagnostics import bridge, check


@contextmanager
def server(root, diagnostics=None, publish=True):
    errors = []
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        listener.settimeout(2)

        def serve():
            try:
                conn, _ = listener.accept()
                with conn, conn.makefile("rb") as stream:
                    bridge.read_message(stream)
                    conn.sendall(bridge.encode({"jsonrpc": "2.0", "id": 1, "result": {"capabilities": {}}}))
                    conn.sendall(bridge.encode({"jsonrpc": "2.0", "method": "gdscript_client/changeWorkspace", "params": {"path": str(root)}}))
                    while True:
                        msg = bridge.read_message(stream)
                        if msg.get("method") == "textDocument/didOpen":
                            doc = msg["params"]["textDocument"]
                            if doc["languageId"] != "gdscript":
                                raise AssertionError("wrong language ID")
                            if publish:
                                conn.sendall(bridge.encode({"jsonrpc": "2.0", "method": "textDocument/publishDiagnostics", "params": {"uri": doc["uri"], "diagnostics": diagnostics or []}}))
            except (EOFError, ConnectionError, socket.timeout):
                pass
            except Exception as error:
                errors.append(error)

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        yield listener.getsockname()[1]
        thread.join(3)
        if thread.is_alive():
            raise AssertionError("fake server did not terminate")
        if errors:
            raise errors[0]


class DiagnosticsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "project.godot").write_text('[application]\nconfig/name="LSP tests"\n')
        self.script = self.root / "example.gd"
        self.script.write_text("extends Node\n")

    def test_explicit_empty_publication_means_clean(self):
        with server(self.root) as port:
            self.assertEqual(check(self.root, [self.script], port), [{"path": "example.gd", "diagnostics": []}])

    def test_preserves_error_location_and_message(self):
        diagnostic = {"severity": 1, "message": "Bad type", "range": {"start": {"line": 2, "character": 4}, "end": {"line": 2, "character": 5}}}
        with server(self.root, [diagnostic]) as port:
            self.assertEqual(check(self.root, [self.script], port)[0]["diagnostics"], [diagnostic])

    def test_quiet_server_is_not_clean(self):
        with server(self.root, publish=False) as port:
            with self.assertRaises(TimeoutError):
                check(self.root, [self.script], port, timeout=.1)

    def test_wrong_workspace_is_rejected(self):
        with server(self.root / "other") as port:
            with self.assertRaisesRegex(ValueError, "does not match"):
                check(self.root, [self.script], port)

    def test_outside_symlink_is_rejected_before_connect(self):
        outside = self.root / "outside"
        outside.mkdir()
        link = outside / "link.gd"
        link.symlink_to(self.script)
        (outside / "project.godot").write_text("")
        with self.assertRaisesRegex(ValueError, "inside this worktree"):
            check(outside, [link], 1)

    def test_absent_editor_is_not_clean(self):
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        with self.assertRaises(OSError):
            check(self.root, [self.script], port)

    def test_hook_rechecks_fixes_and_reverts_and_retries_failures(self):
        def git(*args):
            subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)
        git("init")
        git("add", ".")
        git("-c", "user.name=Test", "-c", "user.email=test@example.test", "commit", "-m", "baseline", "--no-verify")
        event = {"cwd": str(self.root), "session_id": "test", "hook_event_name": "PostToolUse", "tool_name": "Bash"}
        output = io.StringIO()
        checked = []

        def fake_check(root, paths, port, timeout):
            checked.append([p.read_text() for p in paths])
            return [{"path": "example.gd", "diagnostics": []}]

        with patch.object(codex_hook, "__file__", str(self.root / "tools/lsp/codex_hook.py")), patch.dict(os.environ, GODOT_LSP_PORT="16005"), redirect_stdout(output), patch.object(codex_hook, "check", side_effect=fake_check):
            codex_hook.run(event)
            self.assertEqual(checked, [])
            self.script.write_text("extends Node\nvar count: int = 1\n")
            codex_hook.run(event)
            codex_hook.run(event)
            self.assertEqual(len(checked), 1)
            self.script.write_text("extends Node\n")
            codex_hook.run(event)
            self.assertEqual(len(checked), 2)
            self.script.write_text("extends Node\nvar count: int = 2\n")
            with patch.object(codex_hook, "check", side_effect=TimeoutError("unavailable")):
                with self.assertRaises(TimeoutError):
                    codex_hook.run(event)
            codex_hook.run(event)
            self.assertEqual(len(checked), 3)
        for line in output.getvalue().splitlines():
            self.assertIn("additionalContext", json.loads(line)["hookSpecificOutput"])


if __name__ == "__main__":
    unittest.main()
