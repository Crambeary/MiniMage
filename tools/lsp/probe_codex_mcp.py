#!/usr/bin/env python3
"""Verify a local MCP server through Codex's app-server without invoking a model."""
import argparse
import json
from pathlib import Path
import queue
import subprocess
import threading
import tempfile

ALLOWED_TOOLS = ["godot_status", "godot_code_diagnostics", "godot_code_symbols", "godot_code_lookup"]


def probe(root, primary, command=None, args=None, env=None, *,
          server_name="godot_lsp_trial", project_config=False,
          script="res://sample.gd", expect_errors=True, paths=None):
    process = subprocess.Popen(["codex", "app-server", "--stdio"], cwd=root,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True)
    messages = queue.Queue()

    def read():
        for line in process.stdout:
            messages.put(json.loads(line))
        messages.put(None)

    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    number = 0

    def rpc(method, params):
        nonlocal number
        number += 1
        process.stdin.write(json.dumps({"id": number, "method": method, "params": params}) + "\n")
        process.stdin.flush()
        while True:
            message = messages.get(timeout=60)
            if message is None:
                raise EOFError("Codex app-server exited")
            if message.get("id") == number:
                if "error" in message:
                    raise ValueError(message["error"])
                return message["result"]

    try:
        rpc("initialize", {"clientInfo": {"name": "godot-lsp-mcp-probe", "version": "1"},
                           "capabilities": {"experimentalApi": True}})
        process.stdin.write('{"method":"initialized"}\n')
        process.stdin.flush()
        config = {
            "features.hooks": False,
            "projects": {str(p): {"trust_level": "trusted"} for p in [root, primary]},
        }
        if not project_config:
            config[f"mcp_servers.{server_name}"] = {
                "command": command, "args": args, "env": env or {},
                "enabled_tools": ALLOWED_TOOLS,
                "startup_timeout_sec": 60, "tool_timeout_sec": 60,
            }
        thread = rpc("thread/start", {"cwd": str(root), "ephemeral": True, "config": config})
        thread_id = thread["thread"]["id"]
        inventory = rpc("mcpServerStatus/list", {"threadId": thread_id, "serverName": server_name})
        own = [entry for entry in inventory["data"] if entry["name"] == server_name]
        assert len(own) == 1, "Codex did not discover the trial MCP server"
        names = sorted(own[0]["tools"])
        assert names == sorted(ALLOWED_TOOLS), names
        requested = paths or [script]
        result = rpc("mcpServer/tool/call", {"threadId": thread_id, "server": server_name,
                     "tool": "godot_code_diagnostics", "arguments": {"paths": requested}})
        assert not result.get("isError"), result
        data = result.get("structuredContent") or json.loads(result["content"][0]["text"])
        assert data["checked"] == len(requested) and (data["errors"] > 0) == expect_errors and not data.get("unchecked"), data
        # Ephemeral threads have no rollout to archive; process shutdown drops it.
        return {"codex_version": subprocess.check_output(["codex", "--version"], text=True).strip(),
                "scope": "native Codex MCP discovery and tool call; no model turn or automatic hook",
                "tools": names, "diagnostics": data}
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        reader.join(timeout=2)
        process.stdin.close()
        process.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--addon", action="store_true", help="validate all vendored addon scripts instead of a temporary error/fix")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    primary = Path(subprocess.check_output(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=root, text=True).strip()).parent

    def check(**kwargs):
        result = probe(root, primary, server_name="godot_lsp", project_config=True, **kwargs)
        assert result["diagnostics"]["source"] == "lsp (connected editor)", result
        return result

    if args.addon:
        paths = ["res://" + p.relative_to(root).as_posix() for p in sorted((root / "addons/godot_mcp").rglob("*.gd"))]
        result = {"addon_batches": [check(paths=paths[i:i + 50], expect_errors=False)
                                    for i in range(0, len(paths), 50)]}
    else:
        with tempfile.NamedTemporaryFile(suffix=".gd", prefix="codex_upstream_", dir=root) as file:
            path = Path(file.name)
            try:
                path.write_text("extends Node\nfunc broken(\n")
                invalid = check(script="res://" + path.name)
                path.write_text("extends Node\nvar count: int = 1\n")
                fixed = check(script="res://" + path.name, expect_errors=False)
                result = json.loads(json.dumps({"invalid": invalid, "fixed": fixed}).replace(path.name, "<probe>.gd"))
            finally:
                path.unlink(missing_ok=True)
                Path(str(path) + ".uid").unlink(missing_ok=True)
    result["scope"] = "actual project config through native Codex MCP; no model turn or automatic hook"
    serialized = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.write_text(serialized)
    print(serialized)


if __name__ == "__main__":
    main()
