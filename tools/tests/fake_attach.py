"""Test-only stdio bridge to the policy fixture. Never used by production."""
import json
import os
import sys
import urllib.request

for line in sys.stdin:
    body = json.loads(line)
    request = urllib.request.Request(os.environ["FAKE_ATTACH_URL"] + "/mcp",
        json.dumps(body).encode(), {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=2) as response:
            raw = response.read().decode()
        if not raw:
            continue
        if raw.startswith("event:"):
            raw = next(row[5:].strip() for row in raw.splitlines() if row.startswith("data:"))
        print(raw, flush=True)
    except Exception:
        sys.exit(1)
