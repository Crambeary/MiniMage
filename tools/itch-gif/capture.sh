#!/usr/bin/env bash
# Play Mini Mage from the menu into a short stealth route and write a GIF.
# Frames come from the game viewport. ffmpeg scales them with nearest-neighbor.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMES="${ITCH_GIF_FRAMES:-/tmp/itch-gif-frames}"
GIF="${1:-$ROOT/tools/itch-gif/menu-to-stealth.gif}"
RUN_ID="$(printf '%s' "$ROOT" | md5sum | cut -c1-8)"
RUN_ROOT="${VERIFY_RUN_DIR:-/tmp/verify-mini-mage-$RUN_ID}"

find_godot() {
	if [[ -n "${GODOT:-}" && -x "$GODOT" ]]; then
		echo "$GODOT"
		return
	fi
	if command -v godot >/dev/null 2>&1; then
		command -v godot
		return
	fi
	local candidate="$HOME/.local/godot/Godot_v4.7-stable_linux.x86_64"
	if [[ -x "$candidate" ]]; then
		echo "$candidate"
		return
	fi
	echo "capture.sh: Godot 4.7 binary not found. Set GODOT." >&2
	exit 127
}

if [[ -z "${DISPLAY:-}" ]]; then
	echo "capture.sh: DISPLAY is unset. The game window needs X11." >&2
	exit 1
fi

BIN="$(find_godot)"
VER="$("$BIN" --version 2>/dev/null | head -n 1)"
if [[ "$VER" != 4.7* ]]; then
	echo "capture.sh: need Godot 4.7.x, got: $VER" >&2
	exit 1
fi

mkdir -p "$RUN_ROOT/xdg" "$RUN_ROOT/xdg-config" "$RUN_ROOT/xdg-cache"
export XDG_DATA_HOME="$RUN_ROOT/xdg"
export XDG_CONFIG_HOME="$RUN_ROOT/xdg-config"
export XDG_CACHE_HOME="$RUN_ROOT/xdg-cache"

if [[ ! -f "$ROOT/.godot/uid_cache.bin" ]]; then
	echo "capture.sh: importing $ROOT"
	"$BIN" --headless --path "$ROOT" --import --quit
fi

rm -rf "$FRAMES"
mkdir -p "$FRAMES" "$(dirname "$GIF")"
LOG="$FRAMES/capture.log"

echo "capture.sh: playing $ROOT with $VER"
"$BIN" --path "$ROOT" \
	--resolution 960x540 --position 40,40 \
	--rendering-method gl_compatibility \
	--audio-driver Dummy \
	--script "$TOOL/capture.gd" -- \
	--out "$FRAMES" \
	> >(tee "$LOG") 2>&1

COUNT="$(find "$FRAMES" -name 'frame_*.png' | wc -l)"
if [[ "$COUNT" -lt 8 ]]; then
	echo "capture.sh: only $COUNT frames (log $LOG)" >&2
	exit 1
fi

ffmpeg -y -framerate 10 -i "$FRAMES/frame_%04d.png" \
	-filter_complex "scale=480:270:flags=neighbor,split[a][b];[a]palettegen=max_colors=256:stats_mode=diff:reserve_transparent=0[p];[b][p]paletteuse=dither=none" \
	-loop 0 "$GIF"

magic="$(head -c 6 "$GIF" || true)"
if [[ "$magic" != "GIF89a" ]]; then
	echo "capture.sh: $GIF is not a GIF89a file" >&2
	exit 1
fi
bytes="$(wc -c < "$GIF")"
if [[ "$bytes" -lt 50000 ]]; then
	echo "capture.sh: $GIF is only $bytes bytes" >&2
	exit 1
fi

echo "ITCH_GIF $GIF frames=$COUNT bytes=$bytes"
