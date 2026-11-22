#!/usr/bin/env python3
"""PostToolUse feedback for changed GDScript; no edits or tool-output replacement."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

from diagnostics import check, format_results


def feedback(text):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PostToolUse", "additionalContext": text}}))


def run(event):
    root = Path(__file__).resolve().parents[2]
    cwd = Path(event["cwd"]).resolve()
    actual_root = Path(subprocess.check_output(
        ["git", "-C", str(cwd), "rev-parse", "--show-toplevel"], text=True).strip()).resolve()
    if actual_root != root:
        raise ValueError("hook belongs to a different worktree")
    if event.get("hook_event_name") != "PostToolUse":
        return
    session = hashlib.sha256(event["session_id"].encode()).hexdigest()
    cache = root / ".godot" / "codex-lsp"
    cache.mkdir(parents=True, exist_ok=True)
    # Concurrent tool completions must not overwrite another completion's hashes.
    with (cache / f"{session}.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state_path = cache / f"{session}.json"
        state = json.loads(state_path.read_text()) if state_path.exists() else {}
        changed = subprocess.check_output(["git", "diff", "--name-only", "-z", "HEAD", "--", "*.gd"], cwd=root)
        untracked = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard", "-z", "--", "*.gd"], cwd=root)
        names = {os.fsdecode(p) for p in (changed + untracked).split(b"\0") if p} | state.keys()
        hashes = {}
        paths = []
        for name in sorted(names):
            path = (root / name).resolve()
            if not path.is_relative_to(root) or path.suffix != ".gd":
                raise ValueError(f"changed script is outside the worktree: {name}")
            if not path.is_file():
                continue
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            hashes[name] = digest
            if state.get(name) != digest:
                paths.append(path)
        if not paths:
            return
        port = int(os.environ["GODOT_LSP_PORT"])
        if not 1 <= port <= 65535:
            raise ValueError("GODOT_LSP_PORT must be between 1 and 65535")
        results = check(root, paths, port, timeout=10)
        # Only cache successfully checked contents; failures retry on the next tool.
        # Concurrent external edits are left uncached and checked again next time.
        for path in paths:
            name = path.relative_to(root).as_posix()
            if hashlib.sha256(path.read_bytes()).hexdigest() != hashes[name]:
                hashes.pop(name)
        state_path.write_text(json.dumps(hashes))
        feedback("Godot LSP diagnostics for on-disk scripts (file-scoped static analysis):\n" + format_results(results))


if __name__ == "__main__":
    try:
        run(json.load(sys.stdin))
    except (OSError, ValueError, KeyError, TypeError, EOFError, subprocess.SubprocessError) as error:
        feedback(f"Godot diagnostics unavailable; this is not a clean result: {error}. "
                 "Start this worktree's editor with a unique --lsp-port and set the same GODOT_LSP_PORT for Codex.")
