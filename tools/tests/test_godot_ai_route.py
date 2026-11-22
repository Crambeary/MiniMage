"""Seam 2: the godot-ai routing hook as a black box.

Feeds PreToolUse event JSON on stdin of tools/hooks/godot_ai_route.py and
asserts on the decision JSON on stdout, against a small fake godot-ai server
(behind a test-only stdio bridge) serving canned session lists.

Run:  python3 -m unittest discover -s tools/tests -p 'test_*.py'
"""

import json
import os
import shlex
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOOK = os.path.join(os.path.dirname(__file__), "..", "hooks", "godot_ai_route.py")


class FakeGodotAi:
    """Minimal fake of the godot-ai server: initialize + session_manage(list)."""

    def __init__(self, sessions, sse=False):
        self._sessions = sessions  # list, or callable returning a list
        self.sse = sse
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                method = body.get("method")
                if method == "initialize":
                    result = {"protocolVersion": "2025-03-26", "capabilities": {},
                              "serverInfo": {"name": "fake", "version": "0"}}
                elif method == "tools/call":
                    assert body["params"]["name"] == "session_manage"
                    assert body["params"]["arguments"]["op"] == "list"
                    payload = {"sessions": outer.sessions, "count": len(outer.sessions)}
                    result = {"content": [{"type": "text", "text": json.dumps(payload)}]}
                else:  # notifications
                    self.send_response(202)
                    self.end_headers()
                    return
                msg = json.dumps({"jsonrpc": "2.0", "id": body.get("id"), "result": result})
                if outer.sse:
                    data, ctype = f"event: message\ndata: {msg}\n\n".encode(), "text/event-stream"
                else:
                    data, ctype = msg.encode(), "application/json"
                self.send_response(200)
                self.send_header("Content-Type", ctype)
                self.send_header("mcp-session-id", "fake-mcp-session")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    @property
    def sessions(self):
        return self._sessions() if callable(self._sessions) else self._sessions

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


def session(sid, path, pid=1):
    return {"session_id": sid, "project_path": path.rstrip("/") + "/",
            "editor_pid": pid, "readiness": "ready", "is_active": False}


class HookTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = os.path.realpath(self.tmp.name)  # the "worktree"
        with open(os.path.join(self.root, "project.godot"), "w"):
            pass
        os.makedirs(os.path.join(self.root, "scenes"))
        self.other = os.path.join(self.root, "other-worktree")
        os.makedirs(self.other)
        self.server = None

    def tearDown(self):
        if self.server:
            self.server.close()

    def serve(self, sessions, **kw):
        self.server = FakeGodotAi(sessions, **kw)
        return self.server

    def run_hook(self, tool_name, tool_input=None, cwd=None, url=None, extra_env=None):
        event = {"hook_event_name": "PreToolUse", "tool_name": tool_name,
                 "tool_input": tool_input or {}, "cwd": cwd or self.root}
        env = dict(os.environ)
        env["FAKE_ATTACH_URL"] = url or (self.server.url if self.server else "http://127.0.0.1:9")
        env["GODOT_AI_PORT"] = "18000"
        env["GODOT_AI_WS_PORT"] = "19500"
        env["GODOT_AI_ATTACH_CMD"] = shlex.join([
            sys.executable, os.path.join(os.path.dirname(__file__), "fake_attach.py")])
        env["GODOT_AI_LAUNCH_CMD"] = "echo launch-stub"
        env.update(extra_env or {})
        p = subprocess.run([sys.executable, HOOK], input=json.dumps(event),
                           capture_output=True, text=True, env=env, timeout=30)
        self.assertEqual(p.returncode, 0, p.stderr)
        out = p.stdout.strip()
        return json.loads(out)["hookSpecificOutput"] if out else None

    def assertDenied(self, decision, *needles):
        self.assertIsNotNone(decision)
        self.assertEqual(decision["permissionDecision"], "deny")
        for n in needles:
            self.assertIn(n, decision["permissionDecisionReason"])

    # --- pass-through ---------------------------------------------------

    def test_non_godot_ai_tool_is_untouched(self):
        self.assertIsNone(self.run_hook("Bash", {"command": "ls"}))
        self.assertIsNone(self.run_hook("mcp__other__thing", {"a": 1}))

    def test_resource_read_of_other_server_is_untouched(self):
        self.assertIsNone(self.run_hook(
            "ReadMcpResourceTool", {"server": "other", "uri": "file:///x"}))

    # --- own session ----------------------------------------------------

    def test_one_match_sets_session_id_on_flat_tool(self):
        self.serve([session("w@a1b2", self.root), session("o@ffff", self.other)])
        d = self.run_hook("mcp__godot-ai__editor_state", {})
        self.assertEqual(d["permissionDecision"], "allow")
        self.assertEqual(d["updatedInput"], {"session_id": "w@a1b2"})

    def test_one_match_sets_top_level_session_id_on_manage_rollup(self):
        self.serve([session("w@a1b2", self.root)])
        d = self.run_hook("mcp__godot-ai__scene_manage",
                          {"op": "create", "params": {"path": "res://a.tscn"}})
        self.assertEqual(d["permissionDecision"], "allow")
        self.assertEqual(d["updatedInput"], {
            "op": "create", "params": {"path": "res://a.tscn"}, "session_id": "w@a1b2"})

    def test_empty_session_id_is_filled_in(self):
        self.serve([session("w@a1b2", self.root)])
        d = self.run_hook("mcp__godot-ai__editor_state", {"session_id": ""})
        self.assertEqual(d["updatedInput"]["session_id"], "w@a1b2")

    def test_cwd_in_subdirectory_resolves_worktree_root(self):
        self.serve([session("w@a1b2", self.root)])
        d = self.run_hook("mcp__godot-ai__editor_state", {},
                          cwd=os.path.join(self.root, "scenes"))
        self.assertEqual(d["updatedInput"]["session_id"], "w@a1b2")

    def test_bridge_normalizes_upstream_response(self):
        self.serve([session("w@a1b2", self.root)], sse=True)
        d = self.run_hook("mcp__godot-ai__editor_state", {})
        self.assertEqual(d["updatedInput"]["session_id"], "w@a1b2")

    def test_two_matches_rejected_listing_sessions(self):
        self.serve([session("w@aaaa", self.root), session("w@bbbb", self.root)])
        self.assertDenied(self.run_hook("mcp__godot-ai__editor_state", {}),
                          "w@aaaa", "w@bbbb", "Own Session")


    def test_missing_endpoint_fails_without_launch(self):
        d = self.run_hook("mcp__godot-ai__editor_state", extra_env={"GODOT_AI_PORT": ""})
        self.assertDenied(d, "Set GODOT_AI_PORT")

    def test_restart_refreshes_session_pin(self):
        self.serve([session("old", self.root)])
        self.assertEqual(self.run_hook("mcp__godot-ai__editor_state")["updatedInput"]["session_id"], "old")
        self.server._sessions = [session("new", self.root)]
        self.assertEqual(self.run_hook("mcp__godot-ai__editor_state")["updatedInput"]["session_id"], "new")
        self.assertDenied(self.run_hook("mcp__godot-ai__editor_state", {"session_id": "old"}), "Own Session")

    def test_concurrent_worktrees_keep_separate_pins(self):
        self.serve([session("mine", self.root), session("other", self.other)])
        from concurrent.futures import ThreadPoolExecutor
        with open(os.path.join(self.other, "project.godot"), "w"):
            pass
        with ThreadPoolExecutor() as pool:
            results = list(pool.map(lambda path: self.run_hook("mcp__godot-ai__editor_state", cwd=path), [self.root, self.other]))
        self.assertEqual([r["updatedInput"]["session_id"] for r in results], ["mine", "other"])

    # --- auto-launch ----------------------------------------------------

    def stub_editor(self, appears):
        """Stand-in launch command: logs a line per call, creates a flag file
        (which the fake server watches), then lingers like a running editor."""
        log = os.path.join(self.tmp.name, "launches.log")
        flag = os.path.join(self.tmp.name, "editor-up.flag")
        pids = os.path.join(self.tmp.name, "stub.pids")
        script = (f"echo launched >> {shlex.quote(log)}; echo $$ >> {shlex.quote(pids)}; "
                  + (f"touch {shlex.quote(flag)}; " if appears else "")
                  + "exec sleep 120")
        def reap():
            if os.path.exists(pids):
                with open(pids) as f:
                    pid_list = f.read().split()
                for line in pid_list:
                    try:
                        os.kill(int(line), signal.SIGKILL)
                    except OSError:
                        pass
        self.addCleanup(reap)
        def launches():
            if not os.path.exists(log):
                return 0
            with open(log) as f:
                return f.read().count("launched")
        return f"sh -c {shlex.quote(script)}", flag, launches

    def launch_env(self, cmd, timeout="5"):
        # unique marker per test: the launch marker is keyed by worktree root
        return {"GODOT_AI_LAUNCH_CMD": cmd, "GODOT_AI_LAUNCH_TIMEOUT": timeout,
                "GODOT_AI_POLL_INTERVAL": "0.05"}

    def test_zero_matches_launches_editor_and_allows_once_session_appears(self):
        cmd, flag, launches = self.stub_editor(appears=True)
        mine = session("w@a1b2", self.root)
        self.serve(lambda: [session("o@ffff", self.other)]
                   + ([mine] if os.path.exists(flag) else []))
        d = self.run_hook("mcp__godot-ai__editor_state", {}, extra_env=self.launch_env(cmd))
        self.assertEqual(d["permissionDecision"], "allow")
        self.assertEqual(d["updatedInput"], {"session_id": "w@a1b2"})
        self.assertEqual(launches(), 1)

    def test_launch_when_server_is_not_up_yet(self):
        cmd, flag, launches = self.stub_editor(appears=True)
        # nothing listens on the port: the hook still launches (the first editor
        # is what starts the server), then times out
        d = self.run_hook("mcp__godot-ai__editor_state", {}, url="http://127.0.0.1:9",
                          extra_env=self.launch_env(cmd, timeout="0.3"))
        self.assertDenied(d, "editor still starting, retry")
        self.assertEqual(launches(), 1)

    def test_no_session_within_timeout_rejected_with_retry(self):
        cmd, flag, launches = self.stub_editor(appears=False)
        self.serve([session("o@ffff", self.other)])
        d = self.run_hook("mcp__godot-ai__editor_state", {},
                          extra_env=self.launch_env(cmd, timeout="0.5"))
        self.assertDenied(d, "editor still starting, retry")
        self.assertEqual(launches(), 1)

    def test_concurrent_retries_launch_only_once(self):
        from concurrent.futures import ThreadPoolExecutor
        cmd, flag, launches = self.stub_editor(appears=False)
        self.serve([])
        env = self.launch_env(cmd, timeout="0.3")
        with ThreadPoolExecutor() as pool:
            results = list(pool.map(lambda _: self.run_hook(
                "mcp__godot-ai__editor_state", extra_env=env), range(3)))
        for result in results:
            self.assertDenied(result, "editor still starting, retry")
        self.assertEqual(launches(), 1)

    def test_retry_while_still_starting_does_not_launch_a_second_editor(self):
        cmd, flag, launches = self.stub_editor(appears=False)
        self.serve([session("o@ffff", self.other)])
        env = self.launch_env(cmd, timeout="0.4")
        first = self.run_hook("mcp__godot-ai__editor_state", {}, extra_env=env)
        second = self.run_hook("mcp__godot-ai__editor_state", {}, extra_env=env)
        self.assertDenied(first, "editor still starting, retry")
        self.assertDenied(second, "editor still starting, retry")
        self.assertEqual(launches(), 1)

    def test_launched_editor_outlives_the_hook(self):
        cmd, flag, launches = self.stub_editor(appears=False)
        self.serve([])
        self.run_hook("mcp__godot-ai__editor_state", {},
                      extra_env=self.launch_env(cmd, timeout="0.2"))
        with open(os.path.join(self.tmp.name, "stub.pids")) as f:
            pid = int(f.read().split()[0])
        os.kill(pid, 0)  # raises if the editor died with the hook

    def test_failing_launch_command_rejected(self):
        self.serve([])
        d = self.run_hook("mcp__godot-ai__editor_state", {},
                          extra_env=self.launch_env("/nonexistent/launcher"))
        self.assertDenied(d, "Cannot start the editor")

    # --- pins -----------------------------------------------------------

    def test_foreign_session_id_rejected(self):
        self.serve([session("w@a1b2", self.root), session("o@ffff", self.other)])
        self.assertDenied(self.run_hook("mcp__godot-ai__editor_state",
                                        {"session_id": "o@ffff"}),
                          "o@ffff", "w@a1b2", "Own Session")

    def test_matching_session_id_passes_unchanged(self):
        self.serve([session("w@a1b2", self.root)])
        inp = {"op": "create", "params": {}, "session_id": "w@a1b2"}
        d = self.run_hook("mcp__godot-ai__scene_manage", inp)
        self.assertEqual(d["permissionDecision"], "allow")
        self.assertEqual(d.get("updatedInput", inp), inp)

    # --- blocked outright -----------------------------------------------

    def test_session_activate_rejected_even_without_server(self):
        d = self.run_hook("mcp__godot-ai__session_activate", {"session_id": "o@ffff"})
        self.assertDenied(d, "Routing is automatic", "Active Session")

    def test_resource_read_rejected_naming_tool_equivalent(self):
        for uri, tool in [("godot://editor/state", "editor_state"),
                          ("godot://scene/hierarchy", "scene_get_hierarchy"),
                          ("godot://node/properties", "node_get_properties")]:
            d = self.run_hook("ReadMcpResourceTool", {"server": "godot-ai", "uri": uri})
            self.assertDenied(d, tool)

    def test_unknown_resource_read_rejected_with_generic_pointer(self):
        d = self.run_hook("ReadMcpResourceTool",
                          {"server": "godot-ai", "uri": "godot://nothing/known"})
        self.assertDenied(d, "godot://nothing/known", "tool")

    # --- orphan cleanup -------------------------------------------------

    def test_orphaned_session_editor_is_killed(self):
        gone = os.path.join(self.root, "removed-worktree")  # does not exist
        dummy = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(300)", gone])
        self.addCleanup(lambda: (dummy.poll() is None and dummy.kill(), dummy.wait()))
        self.serve([session("w@a1b2", self.root),
                    session("gone@dead", gone, pid=dummy.pid)])
        d = self.run_hook("mcp__godot-ai__editor_state", {})
        self.assertEqual(d["updatedInput"]["session_id"], "w@a1b2")
        deadline = time.time() + 5
        while dummy.poll() is None and time.time() < deadline:
            time.sleep(0.05)
        self.assertIsNotNone(dummy.poll(), "orphan's editor pid should be killed")

    def test_orphan_pid_not_running_this_project_is_left_alone(self):
        gone = os.path.join(self.root, "removed-worktree")
        bystander = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(300)"])
        self.addCleanup(lambda: (bystander.kill(), bystander.wait()))
        self.serve([session("w@a1b2", self.root),
                    session("gone@dead", gone, pid=bystander.pid)])
        self.run_hook("mcp__godot-ai__editor_state", {})
        time.sleep(0.3)
        self.assertIsNone(bystander.poll())

    def test_session_with_existing_path_is_never_killed(self):
        other = self.other
        live = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(300)", other])
        self.addCleanup(lambda: (live.kill(), live.wait()))
        self.serve([session("w@a1b2", self.root),
                    session("other@beef", other, pid=live.pid)])
        self.run_hook("mcp__godot-ai__editor_state", {})
        time.sleep(0.3)
        self.assertIsNone(live.poll())

    def test_orphan_with_already_gone_pid_does_not_fail_call(self):
        gone = os.path.join(self.root, "removed-worktree")
        done = subprocess.Popen([sys.executable, "-c", "pass", gone])
        done.wait()
        self.serve([session("w@a1b2", self.root),
                    session("gone@dead", gone, pid=done.pid)])
        d = self.run_hook("mcp__godot-ai__editor_state", {})
        self.assertEqual(d["updatedInput"]["session_id"], "w@a1b2")


if __name__ == "__main__":
    unittest.main()
