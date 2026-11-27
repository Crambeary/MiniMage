#!/usr/bin/env bash
# Serve the Web export in build/web over plain HTTP for phone testing.
#
# Usage: tools/serve-web.sh [port]   (default 8060, bound to 127.0.0.1)
# Export first:
#   godot --headless --path . --export-release Web build/web/index.html
#
# The build uses no threads, so it needs no COOP/COEP headers or HTTPS on
# localhost. Every response is sent with no-cache headers so a phone reloading
# the page always gets the latest export, and .wasm is served as
# application/wasm so browsers can stream-compile it. Stop with Ctrl-C.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build/web"
port="${1:-8060}"

if [[ ! -f "$root/index.html" ]]; then
	echo "serve-web: $root/index.html is missing; export the Web preset first" >&2
	exit 1
fi

exec python3 -I - "$root" "$port" <<'PY'
import functools
import http.server
import sys

root, port = sys.argv[1], int(sys.argv[2])


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
    }

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


server = http.server.ThreadingHTTPServer(
    ("127.0.0.1", port), functools.partial(Handler, directory=root)
)
print(f"serve-web: http://127.0.0.1:{port}/ -> {root}", flush=True)
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
PY
