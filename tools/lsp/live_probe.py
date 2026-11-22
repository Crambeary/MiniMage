#!/usr/bin/env python3
"""Opt-in live check: GODOT_LSP_PORT=... python3 tools/lsp/live_probe.py.

Creates one temporary script in this worktree, checks the command and Codex
hook input/output, then removes the script and its generated UID sidecar.
Does not start another Codex agent or prove Codex loaded/trusted the hook.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[2]
port = int(os.environ["GODOT_LSP_PORT"])
hook = root / "tools/lsp/codex_hook.py"
command = root / "tools/lsp/diagnostics.py"
event = {"cwd": str(root), "session_id": f"live-probe-{os.getpid()}",
         "hook_event_name": "PostToolUse", "tool_name": "Bash"}
reports = []
with tempfile.NamedTemporaryFile(suffix=".gd", prefix="codex_lsp_", dir=root) as file:
    path = Path(file.name)
    try:
        for label, source, expected in [
            ("syntax", "extends Node\nfunc broken(\n", 1),
            ("type", 'extends Node\nvar count: int = "bad"\n', 1),
            ("fixed", "extends Node\nvar count: int = 1\n", 0),
        ]:
            path.write_text(source)
            start = time.monotonic()
            result = subprocess.run([sys.executable, str(command), "--port", str(port), str(path)], cwd=root, capture_output=True, text=True, timeout=15)
            assert result.returncode == expected, (result.stdout, result.stderr)
            report = {"case": label, "exit": result.returncode,
                      "seconds": round(time.monotonic() - start, 3),
                      "diagnostics": result.stdout.replace(path.name, "<probe>.gd")}
            result = subprocess.run([sys.executable, str(hook)], cwd=root, input=json.dumps(event), capture_output=True, text=True, timeout=15)
            context = json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"]
            assert ("error:" in context) == bool(expected), context
            assert "unavailable" not in context, context
            report["hook_context"] = context.replace(path.name, "<probe>.gd")
            repeat = subprocess.run([sys.executable, str(hook)], cwd=root, input=json.dumps(event), capture_output=True, text=True, timeout=15)
            assert repeat.stdout == "", repeat.stdout
            report["unchanged_hook_silent"] = True
            reports.append(report)
    finally:
        Path(str(path) + ".uid").unlink(missing_ok=True)
print(json.dumps({"scope": "live editor plus direct Codex hook invocation; no native Codex delivery test", "results": reports}, indent=2))
