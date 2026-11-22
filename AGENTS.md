# AGENTS.md

## Driving Godot through the godot-ai MCP server

Several agents work in parallel, each in its own git worktree, all sharing one
godot-ai server. See `tools/CONTEXT.md` for the vocabulary (Own Session, Active
Session, Pinned Call).

Claude Code agents are routed automatically by the PreToolUse hook in
`tools/hooks/godot_ai_route.py` (registered in `.claude/settings.json`). Other
agents (Codex etc.) get no enforcement, so follow these rules yourself:

- Always pass your own `session_id` on every godot-ai call. Find it with
  `session_manage(op="list")`: it is the session whose `project_path` matches
  your worktree root.
- Never call `session_activate`. It changes the server-wide Active Session and
  redirects every other agent's calls.
- Never read `godot://` resources. They read the Active Session, which may be
  another worktree's editor. Use the equivalent tool (`editor_state`,
  `scene_get_hierarchy`, `node_get_properties`, ...) with your `session_id`.
- Only launch an editor at your own worktree (`tools/open-editor.sh`).


## Agent skills

### Issue tracker

Issues live in GitHub Issues for Crambeary/MiniMage (via `gh`). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-label vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `GLOSSARY.md` + `docs/adr/`. See `docs/agents/domain.md`.
