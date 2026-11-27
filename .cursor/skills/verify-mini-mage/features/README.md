# Mini Mage verification map

This directory is the maintained source for verifying what a player can do in Mini Mage. Read this index, then follow one feature file. The game window is the surface. Paths below are project scenes the player actually lands on.

## Baseline preconditions

- Repo root contains `project.godot` with features `4.7`.
- `mm-verify launch` has printed `VERIFY_READY import` since the last `mm-verify cleanup`.
- `mm-verify doctor` prints `VERIFY_DOCTOR ok` for this repo path.
- `DISPLAY` is set. The drive opens a 960×540 window (or `MM_VERIFY_RESOLUTION`) with `--rendering-method gl_compatibility`.
- Do not drive a Godot process you did not start. Do not start a second drive against the same repo path.

## Driving conventions

- Run `helpers/mm-verify` from anywhere. It finds the repo by its own path.
- Start from the main menu unless the feature file says otherwise. The menu is the project main scene.
- Click the button whose text is `Start Game`. Do not call `_on_button_button_up` yourself.
- Movement is physical keys `A` `D` `W` `S`, which are `move_left`, `move_right`, `move_up`, and `move_down`.
- A drive that exits 3 is not a pass. That feature has no automated recipe yet.
- Leave `evidence/` in place during cleanup.

## Proof and skip reporting

- Record the feature id on every artifact. `result.json` does this for automated drives.
- UI proof is a screenshot of the menu action and a screenshot of the resulting scene, plus the scene path and player position in `result.json`.
- A position change is proof only when the value is read from the player after the key events.
- An automated pass for `walk` does not verify sentry detection, the level exit, or the touch schemes.
- If a path cannot be reached, keep the command and the reason. Do not replace it with a different feature.

## Feature entry contract

Each feature file has an H1, one opening paragraph, then these H2 headings in order: `Sub-features`, `How to get to it (user POV)`, `Driving it with mm-verify`, `Gotchas`.

## Features

- [Start the game](./start-game.md) opens level 1 from the main menu.
- [Walk](./walk.md) moves the mage with the keyboard on level 1.
- [Sentry detection](./sentry-detection.md) covers patrols noticing the mage.
- [Level change](./level-change.md) covers the exit from level 1 into level 2 and the end screen.
- [Touch scheme](./touch-scheme.md) covers the on-screen movement schemes, chosen in Settings.
- [View settings](./view-settings.md) covers the Settings screen: world view (FOV), HUD size and the debug readout.
