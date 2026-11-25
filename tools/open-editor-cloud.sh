#!/usr/bin/env bash
# Launch the Godot editor for this worktree in a cloud container (no display).
# Uses Xvfb + the compatibility (OpenGL 3) renderer, in the background.
# Log: /tmp/godot-editor.log
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-/opt/godot/godot}"
repo_root="$(git rev-parse --show-toplevel)"

if [[ ! -x "$GODOT_BIN" ]]; then
	echo "error: Godot not found at $GODOT_BIN (set GODOT_BIN)" >&2
	exit 1
fi

nohup xvfb-run -a -s "-screen 0 1280x720x24" \
	"$GODOT_BIN" --editor --rendering-driver opengl3 --path "$repo_root" "$@" \
	> /tmp/godot-editor.log 2>&1 &
echo "editor starting (pid $!), log: /tmp/godot-editor.log"
