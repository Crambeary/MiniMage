# Routing hook: gating evidence (issue #43, 2026-10-15)

Two facts gate the routing hook. Both were checked live with a throwaway
PreToolUse probe hook (since removed) on `mcp__godot-ai__editor_state` that
logged the event and rewrote `session_id` to `gating-probe@0000`.

Hooks in a project's `.claude/settings.json` are only loaded at session start,
and an isolated subagent's worktree is created from the main checkout's HEAD,
so the probe was driven from a fresh `claude -p` session started in the
worktree that holds the settings file. That session spawned a subagent with
`isolation: "worktree"`.

## (a) Event cwd is the subagent's worktree: confirmed

Event logged for the subagent's call (trimmed):

```json
{"cwd": "/home/marc/Godot/projects/FryTruckGame/.worktrees/agent-a15942259458d8f5e",
 "agent_id": "a15942259458d8f5e", "agent_type": "claude",
 "hook_event_name": "PreToolUse", "tool_name": "mcp__godot-ai__editor_state",
 "tool_input": {}, "mcp_server": {"name": "godot-ai", "source": "user"}}
```

The parent session's own cwd was `.../agent-ae8a33508f9a69b24`; the event
carried the subagent's worktree, not the parent's.

## (b) `updatedInput` reaches the godot-ai tool: confirmed

The call had no arguments. The tool replied
`PLUGIN_DISCONNECTED: Godot session 'gating-probe@0000' not found ...
reason=session_not_found, session_id=gating-probe@0000`, so the rewritten
`session_id` arrived at the server. (With the hook off, the same call replies
`reason=no_active_session`.)

## Notes

- The server has no REST session endpoint; the hook lists sessions with
  `session_manage(op="list")` over MCP streamable HTTP at `/mcp`.
- The `ReadMcpResourceTool` input shape (`{server, uri}`) is assumed from the
  tool's schema, not captured live; the hook also rejects any `godot://` uri
  regardless of the `server` field.
