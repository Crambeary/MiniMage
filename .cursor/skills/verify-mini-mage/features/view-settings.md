# View settings

View settings sets how much of the world the camera shows and how big the in-world HUD is. Every screen shows the same world area, portrait included, and both settings persist in `user://settings.cfg`. The same screen holds the touch scheme row; see [Touch scheme](./touch-scheme.md).

## Sub-features

- `settings-open` opens `res://assets/scenes/ui/SettingsMenu.tscn` from the menu's `Settings` button, with a frozen live copy of level 1 behind the panel.
- `settings-fov` changes the world view from 85% to 115% (linear extent), with the preview camera following at once.
- `settings-hud` changes the HUD size from 75% to 250%, applied to the sentry status bars and the detection arrow.
- `settings-readout` toggles the debug readout (orientation, viewport units, FOV, HUD, touch scheme, world px, tiles, zoom) in the top-left corner of the safe area, drawn above the touch scheme. `F3` toggles it too.
- `settings-persist` saves on `Back`, and the level opens with the saved values.

## How to get to it (user POV)

- Launch the game. Press `Settings` under `Start Game`.
- Drag or tap the `World view` and `HUD size` sliders, or pick a `Touch` scheme. Press `Back` to save and return.

## Driving it with mm-verify

Preconditions:

- `mm-verify cleanup` then `mm-verify launch`, so the run starts from default settings.
- `mm-verify doctor` prints `VERIFY_DOCTOR ok`.

- **Automated.** `.cursor/skills/verify-mini-mage/helpers/mm-verify drive view-settings` taps each slider end and the FOV middle with `InputEventScreenTouch`, checks that the `Touch` row has the active scheme pressed, then checks the saved file and the level. Set `MM_VERIFY_RESOLUTION=844x390`, `390x844` or `1152x648` for the committed sizes.
- **Constant area.** At 100% the camera shows 384×216 world px worth of area (82944 px²) at every size: 424×196 at 844×390, 196×424 at 390×844.

## Gotchas

- The touch scheme is hidden while Settings is open (`TouchControls.set_suspended`), so it never takes a slider touch.
- The preview level runs `_ready` and `_process` but no physics, so sentries do not patrol and nothing detects the mage.
- The drive leaves the readout on and FOV 115% / HUD 250% saved. A second drive without `cleanup` starts from those values.
- There is no pinch-to-zoom in the game. Safari's page pinch is blocked by the Web head include, not by game code.
