#!/usr/bin/env python3
"""Claude Code PreToolUse hook: pin every godot-ai call to the agent's Own Session.

Vocabulary follows the Agent Tooling glossary (tools/CONTEXT.md).

Reads one PreToolUse event on stdin, writes one decision on stdout:
  * no output          -> not a godot-ai call, pass through untouched
  * permissionDecision -> "allow" (with updatedInput carrying session_id) or "deny"

Environment overrides:
  GODOT_AI_PORT / GODOT_AI_WS_PORT  explicit v4 endpoint pair (required)
  GODOT_AI_ATTACH_CMD  optional stdio launcher prefix (ports appended)
  GODOT_AI_LAUNCH_CMD  editor launch command  (default <worktree>/tools/open-editor.sh)
  GODOT_AI_LAUNCH_TIMEOUT  seconds to wait for a launched editor (default 90)
  GODOT_AI_POLL_INTERVAL   seconds between session-list polls     (default 1)
"""

import fcntl
import hashlib
import json
import os
import shlex
import signal
import subprocess
import sys
import tempfile
import time
from godot_ai_stdio import BridgeError, bridge_command, list_sessions

TOOL_PREFIX = "mcp__godot-ai__"
SERVER_NAME = "godot-ai"
DEFAULT_LAUNCH_TIMEOUT = 90
DEFAULT_POLL_INTERVAL = 1.0

# godot:// resource prefix -> the pinnable tool that returns the same data.
RESOURCE_EQUIVALENTS = [
    ("godot://editor/state", "editor_state"),
    ("godot://scene/hierarchy", "scene_get_hierarchy"),
    ("godot://scene/", "scene_manage"),
    ("godot://node/", "node_get_properties"),
    ("godot://selection/", "editor_manage"),
    ("godot://performance", "editor_manage"),
    ("godot://logs/", "logs_read"),
    ("godot://project/", "project_manage"),
    ("godot://script/", "script_manage"),
    ("godot://class/", "api_manage"),
    ("godot://input_map", "input_map_manage"),
    ("godot://materials", "material_manage"),
    ("godot://test/", "test_manage"),
    ("godot://sessions", "session_manage"),
]


def decision(kind, reason=None, updated_input=None):
    out = {"hookEventName": "PreToolUse", "permissionDecision": kind}
    if reason:
        out["permissionDecisionReason"] = reason
    if updated_input is not None:
        out["updatedInput"] = updated_input
    print(json.dumps({"hookSpecificOutput": out}))


def deny(reason):
    decision("deny", reason)


# --- worktree and server access ---------------------------------------------


def worktree_root(cwd):
    """Nearest ancestor of cwd holding project.godot (a worktree root)."""
    d = os.path.realpath(cwd)
    while True:
        if os.path.exists(os.path.join(d, "project.godot")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def norm(path):
    return os.path.realpath(path.rstrip("/") or "/")


# --- orphan cleanup -----------------------------------------------------------


def close_orphans(sessions):
    """Close editors whose project_path no longer exists on disk.

    Safety: only signal a pid whose command line names that project path
    (Godot is launched with --path <root>), so a recycled pid is never hit.
    """
    for s in sessions:
        path, pid = s.get("project_path"), s.get("editor_pid")
        if not path or not isinstance(pid, int) or pid <= 1 or os.path.exists(path):
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().decode(errors="replace").split("\0")
            if path.rstrip("/") not in cmdline and path not in cmdline:
                continue
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass


# --- auto-launch ----------------------------------------------------------------


def own_sessions(sessions, root):
    return [s for s in sessions
            if s.get("project_path") and norm(s["project_path"]) == root]


def _pid_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except OSError:
        return True
    try:  # a zombie is not a running editor
        with open(f"/proc/{pid}/stat") as f:
            return f.read().rsplit(")", 1)[1].split()[0] != "Z"
    except (OSError, IndexError):
        return True


def launch_editor_once(root, launch_cmd):
    """Start this worktree's editor detached, unless a launch is already in flight.

    A marker file (keyed by worktree root) records the launched pid; while that
    process is alive a retry reuses it instead of starting a second editor.
    """
    key = hashlib.sha1(root.encode()).hexdigest()[:16]
    marker = os.path.join(tempfile.gettempdir(), f"godot-ai-launch-{key}.pid")
    fd = os.open(marker, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        raw = os.read(fd, 32).decode().strip()
        if raw.isdigit() and _pid_alive(int(raw)):
            return
        proc = subprocess.Popen(
            shlex.split(launch_cmd), cwd=root, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True)
        os.ftruncate(fd, 0)
        os.lseek(fd, 0, os.SEEK_SET)
        os.write(fd, str(proc.pid).encode())
    finally:
        os.close(fd)  # also releases the flock


def launch_and_wait(root, launch_cmd, attach_cmd):
    """Start the editor (once), poll until it has an Editor Session or time runs out.

    Returns the session list at the end; an unreachable server counts as empty
    because the first editor is what starts it.
    """
    try:
        timeout = float(os.environ.get("GODOT_AI_LAUNCH_TIMEOUT", DEFAULT_LAUNCH_TIMEOUT))
        interval = float(os.environ.get("GODOT_AI_POLL_INTERVAL", DEFAULT_POLL_INTERVAL))
    except ValueError:
        timeout, interval = DEFAULT_LAUNCH_TIMEOUT, DEFAULT_POLL_INTERVAL
    try:
        launch_editor_once(root, launch_cmd)
    except (OSError, ValueError) as e:
        return None, f"could not start the editor with `{launch_cmd}`: {e}"
    deadline = time.monotonic() + timeout
    while True:
        try:
            sessions = list_sessions(attach_cmd)
            if own_sessions(sessions, root):
                return sessions, None
        except (BridgeError, OSError, ValueError, KeyError, IndexError):
            pass
        if time.monotonic() >= deadline:
            return None, None
        time.sleep(min(interval, max(0.0, deadline - time.monotonic())))


# --- policy ---------------------------------------------------------------------


def resource_equivalent(uri):
    for prefix, tool in RESOURCE_EQUIVALENTS:
        if uri.startswith(prefix):
            return tool
    return None


def reject_resource(uri):
    tool = resource_equivalent(uri)
    hint = (f"Use the pinnable tool `{tool}` instead." if tool else
            "Use the equivalent godot-ai tool instead (e.g. editor_state, "
            "scene_get_hierarchy, node_get_properties).")
    deny(f"Reading {uri} is blocked: godot:// resources read the server's Active "
         f"Session, not your Own Session, so they can show another worktree's "
         f"editor. {hint}")


def describe(sessions):
    return ", ".join(f"{s['session_id']} ({s.get('project_path')})" for s in sessions)


def main():
    event = json.load(sys.stdin)
    tool = event.get("tool_name", "")
    tool_input = event.get("tool_input") or {}

    if tool == "ReadMcpResourceTool":
        uri = str(tool_input.get("uri", ""))
        if tool_input.get("server") == SERVER_NAME or uri.startswith("godot://"):
            reject_resource(uri)
        return
    if not tool.startswith(TOOL_PREFIX):
        return
    name = tool[len(TOOL_PREFIX):]

    if name == "session_activate":
        deny("session_activate is blocked: it changes the server-wide Active Session "
             "and would redirect every other agent's calls. Routing is automatic: "
             "this hook pins every godot-ai call to your Own Session (the Editor "
             "Session for this worktree).")
        return

    root = worktree_root(event.get("cwd") or os.getcwd())
    if root is None:
        deny(f"No worktree found: no project.godot at or above {event.get('cwd')}. "
             "godot-ai calls can only be routed from inside a worktree.")
        return

    try:
        attach_cmd = bridge_command()
    except BridgeError as exc:
        deny(str(exc))
        return
    launch_cmd = os.environ.get("GODOT_AI_LAUNCH_CMD") or os.path.join(
        root, "tools", "open-editor.sh")

    try:
        sessions = list_sessions(attach_cmd)
    except (BridgeError, OSError, ValueError, KeyError, IndexError):
        sessions = []  # no server yet: the first editor starts it

    close_orphans(sessions)
    own = own_sessions(sessions, root)

    if not own:
        sessions, err = launch_and_wait(root, launch_cmd, attach_cmd)
        if err:
            deny(f"Cannot start the editor for this worktree ({root}): {err}")
            return
        if sessions is None:
            deny(f"editor still starting, retry. The editor for this worktree "
                 f"({root}) was launched but has not connected to the godot-ai "
                 f"configured v4 endpoint yet; call again shortly (no second editor "
                 "will be started).")
            return
        own = own_sessions(sessions, root)
    if len(own) > 1:
        deny(f"Ambiguous Own Session: {len(own)} Editor Sessions are connected for "
             f"this worktree ({root}): {describe(own)}. Close all but one editor, "
             "then retry.")
        return

    own_id = own[0]["session_id"]
    pinned = tool_input.get("session_id")
    if pinned and pinned != own_id:
        deny(f"session_id `{pinned}` is not your Own Session. Your Own Session is "
             f"`{own_id}` (this worktree, {root}). Omit session_id and routing is "
             "automatic; you may not drive another worktree's editor.")
        return
    if pinned == own_id:
        decision("allow")
        return
    decision("allow", updated_input={**tool_input, "session_id": own_id})


if __name__ == "__main__":
    main()
