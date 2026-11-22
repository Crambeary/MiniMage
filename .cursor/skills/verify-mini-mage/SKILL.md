---
name: verify-mini-mage
description: "Drive the Mini Mage Godot 4 desktop game and prove a user-facing feature. Use when launching the game, checking that a checkout can be driven, or collecting screenshot and position evidence for the menu, walking, sentries, level changes, or the touch scheme switcher."
---

# Verify Mini Mage

Mini Mage is a Godot 4 top-down stealth game (`project.godot` name `GJ_TinyWorlds`, features `4.7`). The player-facing surface is the game window. The main scene is `res://assets/scenes/ui/MainMenu.tscn` (uid `uid://mea4cjnbdw1w`). Editor tooling under `addons/godot_ai` is a separate surface; this skill does not drive the editor and must not call `session_activate`.

There is no Playwright suite. `tests/pin_sentry_detection.gd` builds a bare scene and moves nodes by setting positions. It is not a player session, and a pass there does not prove a feature in this map. The helper `helpers/mm-verify` imports the project, starts Godot, and `helpers/drive.gd` sends the same window events a player produces: a left click on the button whose text is `Start Game`, then physical key `D` (InputMap action `move_right`, physical keycode 68).

## Launch

From the repo root, with Godot 4.7.x available (see Helpers):

```bash
chmod +x .cursor/skills/verify-mini-mage/helpers/mm-verify
.cursor/skills/verify-mini-mage/helpers/mm-verify launch
```

Launch runs `godot --headless --path <repo> --import --quit` with `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME` pointed at `/tmp/verify-mini-mage-<hash-of-repo>/`. Ready means the process exits 0 and prints `VERIFY_READY import`. That import fills `.godot/` (gitignored) so packed scenes such as `player.tscn` and `castle_tileset.tscn` resolve. A process that only answers `--version` is not ready. Launch does not leave a game window open. Each drive starts its own process.

The game keeps no account and no migrateable save. `user://` for a run is the isolated `XDG_DATA_HOME`.

## Doctor

```bash
.cursor/skills/verify-mini-mage/helpers/mm-verify doctor
```

Doctor is read-only. It passes only when all of these are true:

- `godot --version` starts with `4.7`
- `project.godot` exists and declares `config/features=PackedStringArray("4.7")`
- `mm-verify launch` has completed for this repo since the last cleanup (`.godot/uid_cache.bin` exists and the run marker is present)
- `DISPLAY` is set (screenshots need X11 plus OpenGL; Vulkan is not required)
- no `drive.gd` process is already running against this repo path

A healthy doctor prints `VERIFY_DOCTOR ok`.

## Drive

```bash
.cursor/skills/verify-mini-mage/helpers/mm-verify drive walk
```

`start-game` and `touch-scheme` are the other automated features. `sentry-detection` and `level-change` are mapped but not automated: `drive` exits 3 and does not write a pass.

The window is 960×540 at (40, 40) unless `MM_VERIFY_RESOLUTION=WxH` is set, in which case the evidence directory gets a `-WxH` suffix. A tiling compositor (Hyprland, sway) ignores `--resolution`; run through `GODOT=helpers/godot-gamescope GODOT_BIN=<godot>` to get the exact size in a nested gamescope. gamescope may make `drive` exit 1 after `VERIFY_PASS` ("Broken pipe" on teardown); `result.json` is the verdict.

Stretch is `canvas_items`/`expand` and `ScreenLayout` sets the content scale, so viewport units are not window pixels: a 960×540 window is 1066×600 units. `drive.gd` converts every point with `root.get_final_transform()` before `push_input`.

The renderer is `gl_compatibility` and the audio driver is `Dummy`. `drive.gd` loads the project main scene, waits until a `Button` with text `Start Game` has a real rectangle, left-clicks that rectangle through `Viewport.push_input`, and waits until the current scene is `res://assets/scenes/levels/main.tscn` with a node in group `player`. `walk` then posts a physical `D` key-down on every physics frame for 45 frames and one key-up. A script has no OS key repeat, so the repeated key-down is how the held key reaches `Input.get_vector("move_left", "move_right", "move_up", "move_down")`. The driver never writes `position` or `velocity`.

`touch-scheme` presses `Locked`, `Floating`, then `Drag` on the switcher. After each press it swipes with `InputEventScreenTouch`/`InputEventScreenDrag`: locked from the stick's centre to the right, floating at (0.3w, 0.65h) to the left, drag at (0.5w, 0.65h) to the right. It holds for 45 physics frames and releases. Pass: each press makes that scheme current, and each swipe moves the player at least 8 px the right way. Directions alternate because of the wall right of the spawn.

Pass for `walk`: the player's `global_position.x` increases by at least 20 pixels. From the level-1 spawn `(-464, -24)`, `D` stops near `x=-435` on a collision, so a longer hold does not mean a longer walk.

## Evidence

Proof for a drive is the directory `.cursor/skills/verify-mini-mage/evidence/<feature>/`:

- `menu.png` — menu before the click, with the title `Mini Mage` and the `Start Game` button
- `level-before.png` — level 1 after the click, before movement
- `level-after.png` — `walk` only, after the key-up
- `touch-<scheme>.png` — `touch-scheme` only, after each scheme's swipe
- `result.json` — feature id, pass flag, Godot version, click point, scene path, player position before and after, `delta_x`, window pixels and viewport units; `touch_runs` for `touch-scheme`
- `drive.log` — stdout and stderr, including `VERIFY_READY`, `VERIFY_MOVED`, and `VERIFY_PASS` or `VERIFY_FAIL`

Override the directory with `VERIFY_EVIDENCE_DIR`. The seed proof for `walk` is committed under `evidence/walk/`, and `touch-scheme` at phone landscape, phone portrait and design size under `evidence/touch-scheme-{844x390,390x844,1152x648}/`. The original (pre-stretch, 960×540 at zoom 3) `walk` run is in git history: `git show a380741:.cursor/skills/verify-mini-mage/evidence/walk/result.json` (and the PNGs at the same commit).

Standards: click, key and screen-touch events only (`InputEventScreenTouch`/`InputEventScreenDrag` for `touch-scheme`), then read the scene path and the player position back through public API (`TouchControls.get_scheme_name()`, `LockedJoystick.get_base_center()`), never underscore members. Screenshots show the window at the action and after it. Do not treat a log line alone as proof. Audio falling back to Dummy does not touch gameplay. `gl_compatibility` is the verification renderer because machines without Vulkan (including llvmpipe on X11) cannot start the default renderer.

## Cleanup

```bash
.cursor/skills/verify-mini-mage/helpers/mm-verify cleanup
```

Cleanup reads `/tmp/verify-mini-mage-<hash>/drive.pid` and signals that pid only when `/proc/<pid>/cmdline` contains both this repo path and `drive.gd`. It then deletes the run directory (XDG dirs and the import-ready marker). It does not delete `evidence/`. Run `launch` again before the next `drive`.

Do not run two drives against one project path. They share `.godot/` and the import. A second worktree is a different path and a different run directory. Set `VERIFY_RUN_DIR` only when you need to point the run files somewhere else.

## Helpers

`helpers/mm-verify` is the only command. `helpers/drive.gd` is the Godot main loop it passes to `--script`.

Godot resolution order: `$GODOT` if it is executable, else `godot` on `PATH`, else `$HOME/.local/godot/Godot_v4.7-stable_linux.x86_64`. The proof run used Godot `4.7.stable.official.5b4e0cb0f` from that last path. Install by unzipping `Godot_v4.7-stable_linux.x86_64.zip` from `https://github.com/godotengine/godot-builds/releases/download/4.7-stable/` into `$HOME/.local/godot` and `chmod +x` the binary. Any `4.7` version string is accepted.

## Maintenance

Keep the feature map current with `/maintain-verification-skill` as the game changes.
