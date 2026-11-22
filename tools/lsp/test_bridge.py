#!/usr/bin/env python3
"""Protocol and workspace checks for the experimental Godot LSP bridge."""
import json
import os
from pathlib import Path
import socket
import subprocess
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]
BRIDGE = ROOT / "tools/lsp/godot-lsp-bridge.py"


def packet(message):
    body = json.dumps(message).encode()
    return b"Content-Length: %d\r\n\r\n" % len(body) + body


def receive(stream):
    headers = {}
    while (line := stream.readline()) not in (b"\r\n", b"\n", b""):
        key, value = line.decode().split(":", 1)
        headers[key.lower()] = value.strip()
    return json.loads(stream.read(int(headers["content-length"])))


class BridgeTests(unittest.TestCase):
    def run_bridge(self, workspace, document=None):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        listener.settimeout(5)
        port = listener.getsockname()[1]
        received = []

        def serve():
            try:
                conn, _ = listener.accept()
                with conn, conn.makefile("rb") as stream:
                    receive(stream)
                    conn.sendall(packet({"jsonrpc": "2.0", "method": "gdscript_client/changeWorkspace", "params": {"path": workspace}}))
                    conn.sendall(packet({"jsonrpc": "2.0", "id": 1, "result": {"capabilities": {}}}))
                    if document:
                        received.append(receive(stream))
            except (OSError, KeyError, ValueError):
                pass
            finally:
                listener.close()

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        init = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"rootUri": ROOT.as_uri(), "capabilities": {}}}
        data = packet(init) + (packet(document) if document else b"")
        result = subprocess.run(["python3", str(BRIDGE)], cwd=ROOT, env=dict(os.environ, GODOT_LSP_PORT=str(port)), input=data, capture_output=True, timeout=10)
        thread.join(5)
        return result, received

    def test_rejects_wrong_workspace_before_reply(self):
        result, _ = self.run_bridge("/different/worktree")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"does not match", result.stderr)

    def test_maps_gdscript_language_id(self):
        doc = {"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {"uri": (ROOT / "example.gd").as_uri(), "languageId": "plaintext", "version": 1, "text": "extends Node\n"}}}
        result, received = self.run_bridge(str(ROOT), doc)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(received[0]["params"]["textDocument"]["languageId"], "gdscript")

    def test_rejects_document_outside_worktree(self):
        doc = {"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {"uri": "file:///outside.gd", "languageId": "plaintext", "version": 1, "text": ""}}}
        result, _ = self.run_bridge(str(ROOT), doc)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"outside this worktree", result.stderr)


if __name__ == "__main__":
    unittest.main()
