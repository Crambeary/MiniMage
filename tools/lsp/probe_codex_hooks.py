#!/usr/bin/env python3
"""Inspect Codex hook metadata without starting a model or changing trust records."""
import argparse
import json
import os
from pathlib import Path
import queue
import subprocess
import threading


def primary_checkout(root):
    common = Path(subprocess.check_output(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        cwd=root, text=True).strip())
    return common.parent.resolve()


def trust_override(*roots):
    # Pass a whole TOML table: quoted path components in dotted -c keys fail.
    return "projects={" + ",".join(
        json.dumps(str(root)) + '={trust_level="trusted"}' for root in dict.fromkeys(roots)) + "}"


def list_hooks(root, overrides=()):
    args = ["codex", "app-server", "--stdio"]
    for override in overrides:
        args += ["-c", override]
    process = subprocess.Popen(args, cwd=root, stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    messages = queue.Queue()

    def read():
        for line in process.stdout:
            messages.put(json.loads(line))
        messages.put(None)

    reader = threading.Thread(target=read, daemon=True)
    reader.start()

    def request(number, method, params):
        process.stdin.write((json.dumps({"id": number, "method": method, "params": params}) + "\n").encode())
        process.stdin.flush()
        while True:
            response = messages.get(timeout=15)
            if response is None:
                raise EOFError("Codex app-server closed")
            if response.get("id") == number:
                if "error" in response:
                    raise ValueError(response["error"])
                return response["result"]

    try:
        request(1, "initialize", {"clientInfo": {"name": "godot-lsp-probe", "version": "1"},
                                 "capabilities": {"experimentalApi": True}})
        process.stdin.write(b'{"method":"initialized"}\n')
        process.stdin.flush()
        return request(2, "hooks/list", {"cwds": [str(root)]})
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
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--trust-project", action="store_true", help="invocation-only project trust for metadata inspection; does not trust hooks")
    parser.add_argument("--require-present", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    primary = primary_checkout(root)
    source = primary / ".codex/hooks.json"
    result = list_hooks(root, [trust_override(primary, root)] if args.trust_project else [])
    hooks = [{key: hook.get(key) for key in ("eventName", "enabled", "trustStatus")}
             for entry in result["data"] for hook in entry["hooks"]
             if hook.get("sourcePath") == str(source)]
    print(json.dumps({"linked_worktree": root != primary,
                      "hook_source": os.path.relpath(source, root),
                      "primary_hook_file_exists": source.is_file(),
                      "worktree_hook_file_exists": (root / ".codex/hooks.json").is_file(),
                      "project_hooks": hooks}, indent=2))
    return int(args.require_present and not hooks)


if __name__ == "__main__":
    raise SystemExit(main())
