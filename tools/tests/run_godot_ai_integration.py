#!/usr/bin/env python3
"""Headed integration for one or two explicitly owned worktrees.

Run from the implementation worktree. No account client configuration actions.
Uses private XDG Editor Settings and capabilities; never reads credentials.
Pass --peer only for another worktree you own, created with wt. The bootstrap
is temporarily the only enabled plugin, and project.godot is restored on exit.
Godot may regenerate unrelated import metadata; review/revert that separately.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
from godot_ai_stdio import BridgeError, StdioClient, bridge_command


def stop(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--peer", type=Path)
    parser.add_argument("--reads-only", action="store_true",
        help="Qualify two pinned state reads without requiring scene import completion")
    parser.add_argument("--lightweight-peer", action="store_true",
        help="Skip game assets in the disposable owned peer; root remains the full game")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--ws-port", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path.cwd().resolve()
    roots = [root] + ([args.peer.resolve()] if args.peer else [])
    assert len(set(roots)) == len(roots)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    processes, originals, log_handles = {}, {}, []
    peer_ignores = []
    # Keep private runtime state out of the repository and out of evidence.
    private = Path(tempfile.mkdtemp(prefix="fry-v4-integration-"))
    private.chmod(0o700)
    for directory in ("config", "data", "cache", "capabilities"):
        (private / directory).mkdir(mode=0o700)
    os.environ.update({
        "XDG_CONFIG_HOME": str(private / "config"),
        "XDG_DATA_HOME": str(private / "data"),
        "XDG_CACHE_HOME": str(private / "cache"),
        "GODOT_AI_CAPABILITY_DIR": str(private / "capabilities"),
        "GODOT_AI_DISABLE_TELEMETRY": "true",
        "GODOT_AI_PORT": str(args.port), "GODOT_AI_WS_PORT": str(args.ws_port),
    })
    command = bridge_command()
    results = {"ports": [args.port, args.ws_port], "headed": True}
    bridge = None

    def launch(path):
        # No migration marker can trigger automatic client repinning.
        assert not (path / "addons/.godot_ai_update/pending.json").exists()
        assert (path / "addons/godot_ai").is_dir()
        assert not (path / "addons/godot_ai").is_symlink()
        project = path / "project.godot"
        original = originals.setdefault(path, project.read_text())
        if path != root and args.lightweight_peer:
            for name in ["models", "resources", "scenes", "scripts", "tests", "docs"]:
                ignore = path / name / ".gdignore"
                if not ignore.exists():
                    ignore.write_text("")
                    peer_ignores.append(ignore)
            for addon in (path / "addons").iterdir():
                if addon.is_dir() and addon.name != "godot_ai":
                    ignore = addon / ".gdignore"
                    if not ignore.exists():
                        ignore.write_text("")
                        peer_ignores.append(ignore)
            original = ('config_version=5\n[application]\nconfig/name="Migration peer fixture"\n'
                'run/main_scene="res://tools/fixtures/godot-ai-smoke.tscn"\n'
                '[editor_plugins]\nenabled=PackedStringArray()\n')
        start = original.index("[editor_plugins]")
        end = original.find("\n[", start + 1)
        end = len(original) if end < 0 else end
        project.write_text(original[:start] + '[editor_plugins]\nenabled=PackedStringArray("res://tools/fixtures/godot-ai-bootstrap/plugin.cfg")\n' + original[end:])
        log = open(private / (path.name + ".log"), "a")
        log_handles.append(log)
        processes[path] = subprocess.Popen([str(path / "tools/open-editor.sh")],
            cwd=path, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)

    def inventory():
        deadline = time.monotonic() + 150
        while time.monotonic() < deadline:
            try:
                with StdioClient(command, timeout=15) as client:
                    rows = client.call("session_manage", {"op": "list"})["sessions"]
                own = {path: [row for row in rows if Path(row["project_path"]).resolve() == path
                             and row.get("editor_pid") == processes[path].pid]
                       for path in roots}
                if all(len(rows) == 1 for rows in own.values()):
                    return {path: rows[0] for path, rows in own.items()}
            except BridgeError:
                pass
            time.sleep(1)
        raise RuntimeError("Owned editors did not connect before deadline")

    try:
        # Initialize once before editor import starts. Keep the authenticated
        # lease alive so repeated discovery cannot idle-cycle a cold backend.
        bridge = StdioClient(command, timeout=90)
        bridge.__enter__()
        for path in roots:
            launch(path)
        sessions = inventory()
        results["sessions"] = list(sessions.values())
        with StdioClient(command, timeout=45) as client:
            results["pinned_reads"] = []
            for path, row in sessions.items():
                assert row["plugin_version"] == row["server_version"] == "4.3.1"
                sid = row["session_id"]
                if args.reads_only:
                    results["pinned_reads"].append({"project_path": str(path),
                        "session_id": sid,
                        "state": client.call("editor_state", {"session_id": sid})})
                    continue
                # Connection registration can precede filesystem import and
                # restored-scene readiness. Wait on this owned editor only.
                deadline = time.monotonic() + 150
                while True:
                    try:
                        client.call("editor_state", {"session_id": sid})
                        client.call("scene_open", {"path": "res://tools/fixtures/godot-ai-smoke.tscn" if path != root and args.lightweight_peer else "res://scenes/prologue_startup.tscn", "session_id": sid})
                        break
                    except BridgeError:
                        if time.monotonic() >= deadline:
                            raise
                        time.sleep(1)
                state = client.call("editor_state", {"session_id": sid})
                hierarchy = client.call("scene_get_hierarchy", {"session_id": sid})
                results["pinned_reads"].append({"project_path": str(path),
                    "session_id": sid, "state": state, "hierarchy": hierarchy})
        if args.reads_only:
            results["reads_only"] = True
            results["passed"] = True
            return
        old = sessions[root]["session_id"]
        # Keep the peer connected while the first editor reconnects.
        stop(processes[root])
        launch(root)
        sessions = inventory()
        sid = sessions[root]["session_id"]
        assert sid != old
        results["reconnect"] = {"old": old, "new": sid}
        with StdioClient(command, timeout=45) as client:
            pin = {"session_id": sid}
            hierarchy = client.call("scene_get_hierarchy", pin)
            path = hierarchy["nodes"][0]["path"]
            def read():
                return client.call("node_get_properties", dict(pin, path=path, fields=["process_priority"]))
            before = read()
            original = before["properties"][0]["value"]
            edit = client.call("node_set_property", dict(pin, path=path,
                property="process_priority", value=original + 7))
            changed = read()
            assert changed["properties"][0]["value"] == original + 7
            (private / "data/migration-undo").write_text(str(root) + "/")
            # Only the matching project consumes the public undo marker.
            time.sleep(1)
            after = read()
            assert after["properties"][0]["value"] == original
            results["undo"] = {"before": before, "edit": edit, "changed": changed, "after": after}
            try:
                run = client.call("project_run", dict(pin, mode="main", autosave=False))
                time.sleep(8)
                state = client.call("editor_state", pin)
                results["runtime"] = {"run": run, "state": state}
                assert state["helper_live"]
            finally:
                client.call("project_manage", dict(pin, op="stop"))
        results["passed"] = True
    finally:
        for proc in processes.values():
            stop(proc)
        if bridge is not None and hasattr(bridge, "proc") and bridge.proc.poll() is None:
            bridge.__exit__(None, None, None)
        for path, original in originals.items():
            (path / "project.godot").write_text(original)
        for ignore in peer_ignores:
            ignore.unlink(missing_ok=True)
        for log in log_handles:
            log.close()
        text = json.dumps(results, indent=2)
        for index, path in enumerate(roots):
            text = text.replace(str(path), "$WORKTREE" if index == 0 else "$PEER")
        args.output.write_text(text + "\n")
        # Private capability records are left to upstream lifecycle management;
        # they are never opened, printed or copied into the evidence.
    print("PASS: headed authenticated reads, reconnect, undo and live helper")


if __name__ == "__main__":
    main()
