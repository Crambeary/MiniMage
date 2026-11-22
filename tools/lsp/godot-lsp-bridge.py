#!/usr/bin/env python3
"""Connect a stdio LSP client to the explicitly selected Godot editor."""
import json
import os
from pathlib import Path
import socket
import sys
import threading
from urllib.parse import unquote, urlparse


def read_message(stream):
    headers = {}
    while True:
        line = stream.readline()
        if not line:
            raise EOFError("connection closed")
        if line in (b"\r\n", b"\n"):
            break
        key, value = line.decode("ascii").split(":", 1)
        headers[key.lower()] = value.strip()
    length = int(headers["content-length"])
    if length < 0 or length > 32 * 1024 * 1024:
        raise ValueError("invalid message length")
    body = stream.read(length)
    if len(body) != length:
        raise EOFError("truncated message")
    return json.loads(body)


def encode(message):
    body = json.dumps(message, ensure_ascii=False, separators=(",", ":")).encode()
    return b"Content-Length: %d\r\n\r\n" % len(body) + body


def main():
    root = Path.cwd().resolve()
    if not (root / "project.godot").is_file():
        raise ValueError("run from the Godot project root")
    port = int(os.environ["GODOT_LSP_PORT"])
    if not 1 <= port <= 65535:
        raise ValueError("GODOT_LSP_PORT must be between 1 and 65535")
    first = read_message(sys.stdin.buffer)
    if first.get("method") != "initialize" or "id" not in first:
        raise ValueError("first client message must be initialize")
    root_uri = first.get("params", {}).get("rootUri")
    if root_uri:
        uri = urlparse(root_uri)
        if uri.scheme != "file" or uri.netloc not in ("", "localhost") or Path(unquote(uri.path)).resolve() != root:
            raise ValueError("client workspace does not match this worktree")

    with socket.create_connection(("127.0.0.1", port), timeout=10) as sock:
        sock.settimeout(10)
        upstream = sock.makefile("rb")
        sock.sendall(encode(first))
        pending = []
        verified = False
        initialized = False
        while not (verified and initialized):
            message = read_message(upstream)
            pending.append(message)
            if len(pending) > 100:
                raise ValueError("too many messages before workspace verification")
            if message.get("method") == "gdscript_client/changeWorkspace":
                path = message.get("params", {}).get("path")
                if not path or Path(path).resolve() != root:
                    raise ValueError(f"editor workspace {path!r} does not match {str(root)!r}")
                verified = True
            if message.get("id") == first["id"]:
                if "error" in message:
                    raise ValueError(f"editor rejected initialization: {message['error']}")
                initialized = True
        sock.settimeout(None)
        for message in pending:
            sys.stdout.buffer.write(encode(message))
        sys.stdout.buffer.flush()

        failed = threading.Event()
        input_done = threading.Event()

        def forward_input():
            try:
                while True:
                    message = read_message(sys.stdin.buffer)
                    doc = message.get("params", {}).get("textDocument", {})
                    if "uri" in doc:
                        uri = urlparse(doc["uri"])
                        if (uri.scheme != "file" or uri.netloc not in ("", "localhost")
                                or not Path(unquote(uri.path)).resolve().is_relative_to(root)):
                            raise ValueError("document is outside this worktree")
                    if message.get("method") == "textDocument/didOpen":
                        uri = urlparse(doc["uri"])
                        if uri.scheme == "file" and unquote(uri.path).lower().endswith(".gd"):
                            doc["languageId"] = "gdscript"
                    sock.sendall(encode(message))
            except EOFError:
                pass
            except (OSError, ValueError, KeyError, TypeError) as error:
                failed.set()
                print(f"godot-lsp-bridge: client: {error}", file=sys.stderr, flush=True)
            finally:
                input_done.set()
                try:
                    sock.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass

        threading.Thread(target=forward_input, daemon=True).start()
        try:
            while True:
                message = read_message(upstream)
                if message.get("method") == "gdscript_client/changeWorkspace":
                    path = message.get("params", {}).get("path")
                    if not path or Path(path).resolve() != root:
                        raise ValueError("editor changed to a different workspace")
                sys.stdout.buffer.write(encode(message))
                sys.stdout.buffer.flush()
        except EOFError:
            if not input_done.is_set():
                raise ValueError("editor disconnected")
        if failed.is_set():
            raise ValueError("client forwarding failed")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, EOFError) as error:
        print(f"godot-lsp-bridge: {error}", file=sys.stderr)
        sys.exit(1)
