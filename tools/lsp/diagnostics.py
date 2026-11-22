#!/usr/bin/env python3
"""Read current on-disk GDScript diagnostics from an explicitly selected editor."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import socket
import sys
import time

spec = importlib.util.spec_from_file_location("bridge", Path(__file__).with_name("godot-lsp-bridge.py"))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


def check(root, paths, port, timeout=10):
    """Require an explicit diagnostic publication for every file, even clean files."""
    root = Path(root).resolve()
    if not (root / "project.godot").is_file():
        raise ValueError("no project.godot at workspace root")
    documents = {}
    for path in paths:
        path = Path(path).resolve()
        if not path.is_relative_to(root) or path.suffix != ".gd":
            raise ValueError(f"not a GDScript file inside this worktree: {path}")
        documents[path.as_uri()] = (path.relative_to(root).as_posix(), path.read_text())
    if not documents:
        return []
    deadline = time.monotonic() + timeout
    with socket.create_connection(("127.0.0.1", int(port)), timeout=timeout) as sock:
        stream = sock.makefile("rb")

        def send(method, params, request_id=None):
            message = {"jsonrpc": "2.0", "method": method, "params": params}
            if request_id is not None:
                message["id"] = request_id
            sock.sendall(bridge.encode(message))

        def receive():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("editor did not publish diagnostics for every requested file")
            sock.settimeout(remaining)
            message = bridge.read_message(stream)
            if message.get("method") == "gdscript_client/changeWorkspace":
                workspace = message.get("params", {}).get("path")
                if not workspace or Path(workspace).resolve() != root:
                    raise ValueError(f"editor workspace {workspace!r} does not match {str(root)!r}")
            return message

        send("initialize", {"processId": os.getpid(), "rootUri": root.as_uri(), "capabilities": {}}, 1)
        verified = initialized = False
        while not (verified and initialized):
            message = receive()
            verified |= message.get("method") == "gdscript_client/changeWorkspace"
            if message.get("id") == 1:
                if "error" in message:
                    raise ValueError(f"editor rejected initialization: {message['error']}")
                initialized = True
        send("initialized", {})
        results = []
        # Open one document at a time; never use a quiet period as proof of success.
        for uri, (name, source) in documents.items():
            send("textDocument/didOpen", {"textDocument": {
                "uri": uri, "languageId": "gdscript", "version": 1, "text": source}})
            while True:
                message = receive()
                params = message.get("params", {})
                if message.get("method") == "textDocument/publishDiagnostics" and params.get("uri") == uri:
                    diagnostics = params.get("diagnostics")
                    if not isinstance(diagnostics, list):
                        raise ValueError("invalid diagnostics publication")
                    results.append({"path": name, "diagnostics": diagnostics})
                    break
            send("textDocument/didClose", {"textDocument": {"uri": uri}})
        return results


def format_results(results):
    lines = []
    for result in results:
        if not result["diagnostics"]:
            lines.append(f"{result['path']}: clean (editor published an empty diagnostic list)")
        for diagnostic in result["diagnostics"]:
            start = diagnostic["range"]["start"]
            severity = {1: "error", 2: "warning", 3: "info", 4: "hint"}.get(diagnostic.get("severity"), "diagnostic")
            lines.append(f"{result['path']}:{start['line'] + 1}:{start['character'] + 1}: {severity}: {diagnostic['message']}")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--port", type=int, default=os.environ.get("GODOT_LSP_PORT"))
    parser.add_argument("--timeout", type=float, default=10)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if not args.port or not 1 <= args.port <= 65535 or args.timeout <= 0:
        parser.error("set GODOT_LSP_PORT or --port (1–65535), and a positive --timeout")
    try:
        results = check(Path.cwd(), args.paths, args.port, args.timeout)
        print(json.dumps(results) if args.json else format_results(results))
        return int(any(d.get("severity", 1) == 1 for r in results for d in r["diagnostics"]))
    except (OSError, ValueError, KeyError, TypeError, EOFError) as error:
        print(f"godot diagnostics unavailable: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
