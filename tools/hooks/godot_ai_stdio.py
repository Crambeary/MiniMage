"""Bounded MCP stdio client. Credentials belong exclusively to upstream attach.

No HTTP fallback and no capability-file reader. One fresh bridge per discovery
allows backend restarts to refresh both authentication and Editor Session IDs.
"""
import json
import math
import os
import selectors
import shlex
import signal
import subprocess
import time

MAX_FRAME = 2 * 1024 * 1024
MAX_MESSAGES = 128


class BridgeError(ValueError):
    """Safe diagnostic: never includes bridge output or credential material."""


def bridge_command():
    try:
        port = int(os.environ["GODOT_AI_PORT"])
        ws = int(os.environ["GODOT_AI_WS_PORT"])
        if not (1024 <= port <= 65535 and 1024 <= ws <= 65535 and port != ws):
            raise ValueError
    except (KeyError, ValueError):
        raise BridgeError("Set GODOT_AI_PORT and GODOT_AI_WS_PORT to the distinct "
                          "effective v4 Editor Settings ports (1024..65535).") from None
    prefix = os.environ.get("GODOT_AI_ATTACH_CMD")
    try:
        parsed = shlex.split(prefix) if prefix else None
    except ValueError:
        raise BridgeError("Invalid GODOT_AI_ATTACH_CMD quoting") from None
    command = parsed if prefix else [
        "uvx", "--isolated", "--no-config", "--no-env-file", "--no-sources",
        "--no-build", "--index-strategy", "first-index", "--keyring-provider",
        "disabled", "--index", "https://pypi.org/simple", "--default-index",
        "https://pypi.org/simple", "--find-links", "https://pypi.org/simple/godot-ai/",
        "--link-mode", "copy", "--from", "godot-ai==4.3.1", "godot-ai", "attach"]
    if not command:
        raise BridgeError("Empty GODOT_AI_ATTACH_CMD")
    return command + ["--port", str(port), "--ws-port", str(ws)]


class StdioClient:
    def __init__(self, command, timeout=10):
        if not math.isfinite(timeout) or timeout <= 0:
            raise BridgeError("Invalid bridge timeout")
        self.command, self.timeout = command, timeout
        self.buffer = b""
        self.sequence = 0

    def __enter__(self):
        try:
            self.proc = subprocess.Popen(self.command, stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                start_new_session=True, bufsize=0)
        except OSError:
            raise BridgeError("Cannot launch authenticated godot-ai attach bridge") from None
        os.set_blocking(self.proc.stdin.fileno(), False)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.proc.stdout, selectors.EVENT_READ)
        try:
            result = self.request("initialize", {
                "protocolVersion": "2025-03-26", "capabilities": {},
                "clientInfo": {"name": "frytruck-route", "version": "4"}})
            if not isinstance(result, dict) or not result.get("protocolVersion"):
                raise BridgeError("Invalid bridge initialization")
            self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *_):
        # Own process group only. Never signal a shared backend. Upstream starts
        # attach-owned backends in their own session and manages them by lease.
        self.proc.stdin.close()
        try:
            self.proc.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            pass
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(self.proc.pid, sig)
            except ProcessLookupError:
                break
            try:
                self.proc.wait(timeout=0.5)
            except subprocess.TimeoutExpired:
                continue
        self.proc.wait()
        self.selector.close()
        self.proc.stdout.close()

    def send(self, message):
        data = json.dumps(message).encode() + b"\n"
        if len(data) > MAX_FRAME:
            raise BridgeError("Outgoing attach frame exceeds bound")
        deadline = time.monotonic() + self.timeout
        with selectors.DefaultSelector() as writable:
            writable.register(self.proc.stdin, selectors.EVENT_WRITE)
            while data:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not writable.select(remaining):
                    raise BridgeError("Attach bridge write timed out")
                try:
                    count = os.write(self.proc.stdin.fileno(), data[:65536])
                    data = data[count:]
                except BlockingIOError:
                    continue
                except OSError:
                    raise BridgeError("Attach bridge closed stdin") from None

    def receive(self, deadline):
        # MCP stdio uses one JSON message per newline, not HTTP/SSE framing.
        while b"\n" not in self.buffer:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not self.selector.select(remaining):
                raise BridgeError("Attach bridge timed out")
            chunk = os.read(self.proc.stdout.fileno(), 65536)
            if not chunk:
                raise BridgeError("Attach bridge exited before response")
            self.buffer += chunk
            if len(self.buffer) > MAX_FRAME:
                raise BridgeError("Attach bridge frame exceeds bound")
        line, self.buffer = self.buffer.split(b"\n", 1)
        try:
            message = json.loads(line)
        except (ValueError, UnicodeDecodeError):
            raise BridgeError("Malformed attach bridge frame") from None
        if not isinstance(message, dict) or message.get("jsonrpc") != "2.0":
            raise BridgeError("Invalid attach bridge message")
        return message

    def request(self, method, params):
        self.sequence += 1
        request_id = self.sequence
        self.send({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params})
        deadline = time.monotonic() + self.timeout
        for _ in range(MAX_MESSAGES):
            response = self.receive(deadline)
            if "method" in response:
                if "id" in response:
                    self.send({"jsonrpc": "2.0", "id": response["id"],
                               "result": {}} if response["method"] == "ping" else {
                               "jsonrpc": "2.0", "id": response["id"],
                               "error": {"code": -32601, "message": "Unsupported request"}})
                continue
            if response.get("id") != request_id:
                raise BridgeError("Unexpected attach response ID")
            if "error" in response or "result" not in response:
                raise BridgeError("Attach bridge returned an MCP error")
            return response["result"]
        raise BridgeError("Attach bridge message count exceeds bound")

    def call(self, name, arguments):
        result = self.request("tools/call", {"name": name, "arguments": arguments})
        if not isinstance(result, dict) or result.get("isError"):
            raise BridgeError("Attach tool call failed")
        payload = result.get("structuredContent")
        if payload is None:
            try:
                payload = json.loads(result["content"][0]["text"])
            except (KeyError, IndexError, TypeError, ValueError):
                raise BridgeError("Malformed attach tool result") from None
        return payload


def list_sessions(command):
    try:
        timeout = float(os.environ.get("GODOT_AI_BRIDGE_TIMEOUT", "30"))
        with StdioClient(command, timeout) as client:
            payload = client.call("session_manage", {"op": "list"})
        sessions = payload["sessions"]
        if not isinstance(sessions, list) or any(
            not isinstance(row, dict) or
            not isinstance(row.get("session_id"), str) or not row["session_id"] or
            not isinstance(row.get("project_path"), str) or not row["project_path"]
            for row in sessions
        ):
            raise BridgeError("Invalid session inventory")
        return sessions
    except (KeyError, IndexError, TypeError, ValueError) as exc:
        if isinstance(exc, BridgeError):
            raise
        raise BridgeError("Malformed session inventory") from None
