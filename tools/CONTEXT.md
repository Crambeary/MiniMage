# Agent Tooling

How agents drive live Godot editors through the godot-ai MCP server while working in parallel across git worktrees.

## Language

**Editor Session**:
One live Godot editor connected to the shared godot-ai server, bound to exactly one worktree by its project path. Its identity is `<worktree-slug>@<opaque-suffix>`, and the suffix changes every time the editor starts.
_Avoid_: instance, connection, editor (when the session is meant)

**Active Session**:
The single server-wide default Editor Session that unpinned calls fall through to, shared by every agent. It is off-limits, because one agent changing it redirects every other agent's calls.
_Avoid_: current session, selected editor

**Pinned Call**:
A godot-ai tool call that names its target Editor Session explicitly rather than falling through to the Active Session.
_Avoid_: targeted call, routed call

**Own Session**:
The Editor Session whose project path matches the worktree an agent is running in. It is the only session that agent may drive.
_Avoid_: my editor, the agent's editor

**Orphaned Session**:
An Editor Session whose worktree has been removed from disk. It has nothing left to protect and is closed on sight.
_Avoid_: stale editor, zombie editor


## v4 discovery transport

The physical `addons/godot_ai` release is committed directly. Checkout hooks
must never recreate the former submodule or symlink in a v4 checkout. The
clone-wide compatible hook checks the current worktree index and retains
initialization only for older branches still tracking the v3 gitlink. Never
replace that installed hook with an older branch's destructive repair copy.
Verify upstream bytes with
`python3 tools/verify-godot-ai.py`.

Routing discovery uses authenticated `godot-ai attach` over stdio. Set both
`GODOT_AI_PORT` and `GODOT_AI_WS_PORT` to the effective Editor Settings pair;
`godot_ai/v4_endpoint_ports` overrides the legacy per-port settings. The hook
fails closed if the pair is missing or invalid. An environment setting does
not configure Godot itself. Never read capability records or persist tokens.
See `docs/agent-tooling/godot-ai-v4.3.1/README.md` for verification, staged
validation, and the separate live client cutover.
