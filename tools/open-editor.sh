#!/usr/bin/env bash
# Launch the Godot editor for the current worktree without registering it
# in GodotHub's project list. Every worktree gets its own project.godot,
# and the godot-ai MCP plugin only needs an editor pointed at the right
# one on disk. v4 endpoints live in Editor Settings; configure the matching
# GODOT_AI_PORT / GODOT_AI_WS_PORT for the routing hook (see tools/CONTEXT.md).
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-$HOME/.local/share/Ryko.GodotHub/godot-versions/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64}"

if [[ ! -x "$GODOT_BIN" ]]; then
	echo "error: Godot binary not found or not executable at $GODOT_BIN" >&2
	echo "set GODOT_BIN to override" >&2
	exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"

if [[ ! -f "$repo_root/project.godot" ]]; then
	echo "error: no project.godot at $repo_root" >&2
	exit 1
fi

# Godot consumes --lsp-port before plugins can inspect it. Repeat the selected
# port as a user argument so the code-analysis addon reports the real endpoint.
editor_args=("$@")
lsp_port=""
has_separator=false
for ((i = 0; i < ${#editor_args[@]}; i++)); do
	if [[ "${editor_args[i]}" == "--" ]]; then
		has_separator=true
		break
	elif [[ "${editor_args[i]}" == "--lsp-port" && $((i + 1)) -lt ${#editor_args[@]} ]]; then
		lsp_port="${editor_args[i + 1]}"
	fi
done
if [[ -n "$lsp_port" ]]; then
	if [[ "$has_separator" == false ]]; then
		editor_args+=(--)
	fi
	editor_args+=("--godot-mcp-lsp-port=$lsp_port")
fi
cmd=("$GODOT_BIN" --path "$repo_root" --editor "${editor_args[@]}")

# Under Hyprland, spawn the editor straight onto the "agents" workspace without
# stealing focus. The workspace rule applies when the window maps, so it never
# appears on (or takes keys from) your active workspace. Set OPEN_EDITOR_HERE=1
# to open it normally instead, when you want to watch it.
if [[ -z "${OPEN_EDITOR_HERE:-}" && -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl >/dev/null; then
	# Hyprland execs the command with its own environment, so carry ours across.
	quoted="$(printf '%q ' env "PATH=$PATH" "HOME=$HOME" ${GODOT_AI_PORT:+"GODOT_AI_PORT=$GODOT_AI_PORT"} ${GODOT_AI_WS_PORT:+"GODOT_AI_WS_PORT=$GODOT_AI_WS_PORT"} "${cmd[@]}")"
	lua_str="${quoted//\\/\\\\}"
	lua_str="${lua_str//\"/\\\"}"
	exec hyprctl dispatch "hl.dsp.exec_cmd(\"$lua_str\", { workspace = \"name:agents silent\" })"
fi
exec "${cmd[@]}"
