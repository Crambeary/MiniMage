# Launching the Godot editor for godot-ai

The godot-ai MCP tools need a live Godot editor opened on **your own
worktree**. Without one, `session_manage(op="list")` returns nothing useful.

## Local machine (has a display)

```bash
tools/open-editor.sh
```

Uses the GodotHub-installed 4.7.2 binary (override with `GODOT_BIN`). Does not
register the project in GodotHub. Optional: `--lsp-port N --dap-port M`.

## Cloud container (no display)

```bash
tools/open-editor-cloud.sh
```

Runs the editor under Xvfb with the OpenGL3 renderer, in the background, using
`/opt/godot/godot` (override with `GODOT_BIN`). Log: `/tmp/godot-editor.log`.

The Vulkan init error in that log is harmless; the script forces OpenGL3.

## Verify it connected

Connection takes a few seconds after launch. Then:

```
session_manage(op="list")
```

Use the `session_id` whose `project_path` matches your worktree root, and pass
it on every godot-ai call (see `AGENTS.md`).

## Troubleshooting

- **Hook says "editor still starting, retry"** — the routing hook
  (`tools/hooks/godot_ai_route.py`) believes an editor was launched but it has
  not connected. In cloud sessions this auto-launch can silently fail: check
  `pgrep -a godot` and whether `/tmp/godot-editor.log` exists. If there is no
  process or log, run `tools/open-editor-cloud.sh` yourself, then retry.
- Wait for the connection with a polling loop (e.g. Monitor with
  `until grep -q "connected to server" /tmp/godot-editor.log; do sleep 2; done`),
  not long chained `sleep`s.
- Never launch an editor at another worktree, and never call
  `session_activate` (see `AGENTS.md`).

## Smoke-testing writes

```
filesystem_manage(op="write_text", params={"path": "res://mcp_write_test.txt", "content": "ok"}, session_id=<yours>)
```

Check the file on disk, then delete it so the tree stays clean.
