# Record play analytics

You use these events to see how people play Mini Mage.

## What the four events answer

`play_pressed` counts presses of Start Game on the main menu.

`level_1_complete` records that this session finished the first level.

`level_2_complete` records that this session finished the second level.

`session_duration` records how long the session lasted.

## Read a JSON line

Each event is one JSON object on its own line.

Every event includes these fields.

- `event` is the event name.
- `session_id` is 32 hex characters. Each play press creates a new value.
- `unix_ms` is Unix time in milliseconds.
- `platform` is the operating system name Godot reports.

`level_1_complete` and `level_2_complete` also include `duration_ms`. That value is the number of milliseconds since `play_pressed` for this session.

`session_duration` also includes `duration_ms`, `partial`, and `reason`.

`partial` is false on the final row for that session. It is true on a heartbeat.

`reason` is `heartbeat`, `menu`, or `quit`.

A heartbeat is written every 15 seconds while the session is open.

`menu` means the player returned to the main menu.

`quit` means the game process exited. That row is the final row for the session.

The game also prints the same JSON to stdout on a line that starts with `ANALYTICS`.

## Set the endpoint

The game posts each event when an endpoint is set. An empty endpoint keeps events in the local log only.

If the endpoint accepts the connection and sends no reply, closing the game waits up to 3 seconds.

`MINIMAGE_ANALYTICS_URL` overrides the project setting when the variable is not empty.

```
MINIMAGE_ANALYTICS_URL=http://127.0.0.1:8080/events godot --path .
```

Open the project in Godot 4.7.

Choose Project, then Project Settings.

Search for `analytics/endpoint`.

If that setting is missing, add this section to `project.godot` and reload the project.

```
[analytics]

endpoint="https://example.com/events"
```

The editor then shows `analytics/endpoint`. Edit the value there.

This repo ships with no endpoint. Leave the value empty when you only want the local file.

## Accept the POST

The game sends the JSON body with `Content-Type` set to `text/plain`.

It sends no custom header and no auth header.

Put a key in the URL if you need one.

Answer with the header `Access-Control-Allow-Origin` set to `*` so the web export can read the response.

Save this receiver as `receiver.py`.

```python
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
	def _send(self, code):
		self.send_response(code)
		self.send_header("Access-Control-Allow-Origin", "*")
		self.end_headers()

	def do_OPTIONS(self):
		self._send(204)

	def do_POST(self):
		length = int(self.headers.get("Content-Length", "0"))
		body = self.rfile.read(length)
		print(body.decode("utf-8"), flush=True)
		self._send(204)


if __name__ == "__main__":
	HTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
```

Run the receiver.

```
python3 receiver.py
```

The receiver prints each body. `OPTIONS` returns the same origin header so a browser preflight can succeed.

## Read the local file

On Linux the log for this project is `~/.local/share/godot/app_userdata/GJ_TinyWorlds/analytics/events.jsonl`.

Set `MINIMAGE_ANALYTICS_LOG` to an absolute path when you want a different file. The game creates missing parent directories.

A web build keeps that file in the browser. The published itch build needs the endpoint.

## Keep sessions private

Each play press creates a random session id.

The game does not store that id.

The game does not send a device id.

The server sees the connection.

Do not log the IP address if you do not need it.

## Count plays and finishes

Count rows whose `event` is `play_pressed`. That count is the number of plays.

A session finished level 1 when a `level_1_complete` row exists for that `session_id`.

A session finished level 2 when a `level_2_complete` row exists for that `session_id`.

Duration for a session is the largest `duration_ms` on that `session_id`.

Use the `session_duration` row whose `partial` value is false when that row exists.

A closed browser tab can drop the final row. The last heartbeat is at most 15 seconds before the tab closed.
