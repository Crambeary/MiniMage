#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ROOT="$(mktemp -d /tmp/prove-play-analytics.XXXXXX)"
RECV_PID=""

cleanup() {
	if [[ -n "$RECV_PID" ]]; then
		kill "$RECV_PID" 2>/dev/null || true
		wait "$RECV_PID" 2>/dev/null || true
	fi
	rm -rf "$RUN_ROOT"
}
trap cleanup EXIT

find_godot() {
	if [[ -n "${GODOT:-}" && -x "$GODOT" ]]; then
		echo "$GODOT"
		return
	fi
	if command -v godot >/dev/null 2>&1; then
		command -v godot
		return
	fi
	local candidate="$HOME/.local/godot/Godot_v4.7-stable_linux.x86_64"
	if [[ -x "$candidate" ]]; then
		echo "$candidate"
		return
	fi
	echo "prove-play-analytics: Godot 4.7 binary not found. Set GODOT or install Godot_v4.7-stable_linux.x86_64 under \$HOME/.local/godot." >&2
	exit 127
}

isolate() {
	mkdir -p "$RUN_ROOT/xdg" "$RUN_ROOT/xdg-config" "$RUN_ROOT/xdg-cache"
	export XDG_DATA_HOME="$RUN_ROOT/xdg"
	export XDG_CONFIG_HOME="$RUN_ROOT/xdg-config"
	export XDG_CACHE_HOME="$RUN_ROOT/xdg-cache"
}

fail() {
	echo "PROVE_FAIL $*" >&2
	exit 1
}

BIN="$(find_godot)"
isolate
VER="$("$BIN" --version 2>&1 | head -n 1)"
if [[ "$VER" != 4.7* ]]; then
	fail "need Godot 4.7, got $VER"
fi

echo "prove-play-analytics: importing $ROOT with $VER"
if ! "$BIN" --headless --path "$ROOT" --import --quit; then
	fail "import failed"
fi

JSONL="$RUN_ROOT/events.jsonl"
HTTP_BODY="$RUN_ROOT/http-body.jsonl"
PORT_FILE="$RUN_ROOT/port"
python3 - "$HTTP_BODY" "$PORT_FILE" <<'PY' &
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

body_path = sys.argv[1]
port_path = sys.argv[2]

class Handler(BaseHTTPRequestHandler):
    def _cors(self, code):
        self.send_response(code)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_OPTIONS(self):
        self._cors(204)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        with open(body_path, "ab") as handle:
            handle.write(body)
            if not body.endswith(b"\n"):
                handle.write(b"\n")
        self._cors(204)

    def log_message(self, fmt, *args):
        return

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(port_path, "w", encoding="utf-8") as handle:
    handle.write(str(server.server_address[1]))
server.serve_forever()
PY
RECV_PID=$!

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
	if [[ -s "$PORT_FILE" ]]; then
		break
	fi
	if ! kill -0 "$RECV_PID" 2>/dev/null; then
		fail "analytics receiver exited before binding a port"
	fi
	sleep 0.05
done
if [[ ! -s "$PORT_FILE" ]]; then
	fail "analytics receiver did not report a port"
fi
PORT="$(cat "$PORT_FILE")"
export MINIMAGE_ANALYTICS_URL="http://127.0.0.1:${PORT}/events"
export MINIMAGE_ANALYTICS_LOG="$JSONL"

set +e
"$BIN" --headless --path "$ROOT" --script res://tools/prove_play_analytics.gd
STATUS=$?
set -e
if [[ "$STATUS" -ne 0 ]]; then
	fail "godot proof exited $STATUS"
fi

if ! python3 - "$JSONL" "$HTTP_BODY" <<'PY'
import json
import sys

required = ("play_pressed", "level_1_complete", "level_2_complete", "session_duration")

def load(path):
    events = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            text = line.strip()
            if not text:
                continue
            events.append(json.loads(text))
    return events

def check(events, label):
    names = [event.get("event") for event in events]
    for name in required:
        if name not in names:
            return "%s missing %s" % (label, name)
    session_ids = {event.get("session_id") for event in events}
    if len(session_ids) != 1 or None in session_ids or "" in session_ids:
        return "%s session ids %s" % (label, sorted(str(item) for item in session_ids))
    finals = [
        event
        for event in events
        if event.get("event") == "session_duration" and event.get("partial") is False
    ]
    if not finals:
        return "%s has no session_duration with partial false" % label
    return ""

errors = []
for path, label in ((sys.argv[1], "jsonl"), (sys.argv[2], "http")):
    try:
        events = load(path)
    except (OSError, json.JSONDecodeError) as exc:
        errors.append("%s unreadable %s" % (label, exc))
        continue
    problem = check(events, label)
    if problem:
        errors.append(problem)
if errors:
    print("; ".join(errors))
    sys.exit(1)
PY
then
	fail "event check failed"
fi
echo "PROVE_PASS"
