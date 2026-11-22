"""Transport failure tests independent of routing policy and real credentials."""
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
from godot_ai_stdio import BridgeError, StdioClient, bridge_command, list_sessions


class TransportTest(unittest.TestCase):
    def script(self, body):
        return [sys.executable, "-u", "-c", body]

    def test_effective_ports_are_explicit_and_version_pinned(self):
        with patch.dict(os.environ, {"GODOT_AI_PORT": "18321", "GODOT_AI_WS_PORT": "19321"}, clear=True):
            command = bridge_command()
        self.assertIn("godot-ai==4.3.1", command)
        self.assertEqual(command[-4:], ["--port", "18321", "--ws-port", "19321"])
        for port, ws in [("", "9500"), ("8000", "8000"), ("80", "9500")]:
            with patch.dict(os.environ, {"GODOT_AI_PORT": port, "GODOT_AI_WS_PORT": ws}, clear=True):
                with self.assertRaises(BridgeError):
                    bridge_command()

    def test_timeout_reaps_bridge(self):
        client = StdioClient(self.script("import time; time.sleep(30)"), timeout=0.1)
        started = time.monotonic()
        with self.assertRaisesRegex(BridgeError, "timed out"):
            with client:
                pass
        self.assertLess(time.monotonic() - started, 2)
        self.assertIsNotNone(client.proc.poll())

    def test_malformed_oversized_eof_wrong_id_and_error_are_bounded(self):
        frames = ["not json", "x" * (2 * 1024 * 1024 + 1),
                  json.dumps({"jsonrpc": "2.0", "id": 999, "result": {}}),
                  json.dumps({"jsonrpc": "2.0", "id": 1, "error": {"message": "PRIVATE"}})]
        for frame in frames:
            code = "print('x' * (2 * 1024 * 1024 + 1), flush=True)" if len(frame) > 100000 else f"print({frame!r}, flush=True)"
            client = StdioClient(self.script(code), timeout=1)
            with self.assertRaises(BridgeError) as error:
                with client:
                    pass
            self.assertNotIn("PRIVATE", str(error.exception))
            self.assertIsNotNone(client.proc.poll())
        with self.assertRaisesRegex(BridgeError, "exited"):
            with StdioClient(self.script("pass"), timeout=1):
                pass

    def test_timeout_cleans_up_bridge_descendants(self):
        with tempfile.TemporaryDirectory() as directory:
            pid_file = Path(directory) / "child.pid"
            body = f"""
import subprocess,sys,time
from pathlib import Path
child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)'])
Path({str(pid_file)!r}).write_text(str(child.pid))
time.sleep(30)
"""
            with self.assertRaises(BridgeError):
                with StdioClient(self.script(body), timeout=.3):
                    pass
            child = int(pid_file.read_text())
            # An orphaned zombie is already terminated and cannot retain pipes.
            stat = Path(f"/proc/{child}/stat")
            deadline = time.monotonic() + 1
            while stat.exists() and stat.read_text().rsplit(")", 1)[1].split()[0] != "Z":
                self.assertLess(time.monotonic(), deadline, "bridge descendant survived cleanup")
                time.sleep(.02)

    def test_bridge_that_stops_reading_cannot_block_writes(self):
        body = """
import json,sys,time
m=json.loads(sys.stdin.readline())
print(json.dumps({'jsonrpc':'2.0','id':m['id'],'result':{'protocolVersion':'2025-03-26'}}),flush=True)
time.sleep(30)
"""
        with StdioClient(self.script(body), timeout=.2) as client:
            with self.assertRaisesRegex(BridgeError, "write timed out"):
                client.send({"jsonrpc": "2.0", "method": "test", "params": "x" * 1000000})
            with self.assertRaisesRegex(BridgeError, "exceeds bound"):
                client.send({"params": "x" * 3000000})

    def test_partial_frames_notifications_ping_and_structured_result(self):
        body = r'''
import json, sys, time
for line in sys.stdin:
    message=json.loads(line)
    if "id" not in message:
        continue
    if message.get("method")=="initialize":
        result={"protocolVersion":"2025-03-26"}
    else:
        print(json.dumps({"jsonrpc":"2.0","method":"notifications/message","params":{}}),flush=True)
        print(json.dumps({"jsonrpc":"2.0","id":"ping","method":"ping"}),flush=True)
        result={"structuredContent":{"sessions":[{"session_id":"own","project_path":"/own"}]}}
    raw=json.dumps({"jsonrpc":"2.0","id":message["id"],"result":result})+"\n"
    sys.stdout.write(raw[:8]); sys.stdout.flush(); time.sleep(.01)
    sys.stdout.write(raw[8:]); sys.stdout.flush()
    if message.get("method")=="tools/call":
        assert json.loads(sys.stdin.readline())["id"]=="ping"
'''
        self.assertEqual(list_sessions(self.script(body))[0]["session_id"], "own")

    def test_malformed_session_inventory_is_rejected(self):
        for payload in [None, {}, {"sessions": "oops"}, {"sessions": [None]},
                        {"sessions": [{"session_id": "foreign"}]}]:
            body = f"""
import json,sys
for line in sys.stdin:
 m=json.loads(line)
 if 'id' not in m: continue
 r={{'protocolVersion':'2025-03-26'}} if m['method']=='initialize' else {{'structuredContent':{payload!r}}}
 print(json.dumps({{'jsonrpc':'2.0','id':m['id'],'result':r}}),flush=True)
"""
            with self.assertRaises(BridgeError):
                list_sessions(self.script(body))


if __name__ == "__main__":
    unittest.main()
