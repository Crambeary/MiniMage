#!/usr/bin/env bash
# Shared stdio entrypoint: pin dependencies and resolve this worktree at launch.
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
server="$repo_root/tools/lsp/upstream-trial/node_modules/@shin2344234/godot-mcp/dist/index.js"
GODOT_BIN="${GODOT_BIN:-$HOME/.local/share/Ryko.GodotHub/godot-versions/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64}"
if [[ ! -f "$server" ]]; then
  echo 'Run npm ci --prefix tools/lsp/upstream-trial --ignore-scripts before starting the MCP client.' >&2
  exit 1
fi
if [[ ! -x "$GODOT_BIN" ]]; then
  echo 'Set GODOT_BIN to the Godot 4.7+ executable.' >&2
  exit 1
fi
exec node "$server" --project "$repo_root" --godot "$GODOT_BIN" --toolsets code --read-only
