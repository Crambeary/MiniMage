# Touch scheme

Touch scheme picks how the on-screen control moves the mage: locked joystick, floating joystick, or a drag area. The player chooses it in Settings, and the choice persists in `user://settings.cfg` (section `touch`, key `scheme`).

## Sub-features

- `touch-settings` shows a `Touch` row with `Locked`, `Floating` and `Drag` in the Settings screen, with a one-line hint for the pressed scheme.
- `touch-floating` uses `Floating` when no scheme was ever saved (an existing `settings.cfg` without a `touch` section included).
- `touch-switch` swaps the scheme the moment its button is pressed, and saves it.
- `touch-move` moves the mage when the active scheme is swiped in the level.
- `touch-no-hud` puts no scheme buttons on the game screen; the level shows only the scheme itself.
- `touch-safe-area` keeps the locked stick inside the safe area (notch, island, home indicator).

## How to get to it (user POV)

- Launch the game. Press `Settings` under `Start Game`.
- Press `Locked`, `Floating`, or `Drag` in the `Touch` row. Press `Back`, then `Start Game`.

## Driving it with mm-verify

Preconditions:

- `mm-verify cleanup` then `mm-verify launch`, so the run starts with no saved scheme.
- `mm-verify doctor` prints `VERIFY_DOCTOR ok`.

- **Automated.** `.cursor/skills/verify-mini-mage/helpers/mm-verify drive touch-scheme` picks each scheme in Settings, starts the level, swipes, and checks the player moved. See SKILL.md for the recipe. Set `MM_VERIFY_RESOLUTION=844x390`, `390x844` or `1152x648` for the committed sizes.
- **Default scheme.** On a fresh run `TouchControls.get_scheme_name()` is `floating`, and `Floating` is the pressed button in Settings.
- **Switch.** Press `Locked` or `Drag` in Settings. That button becomes the pressed one, and the level opens with that scheme.

## Gotchas

- The scheme is hidden while Settings is open (`TouchControls.set_suspended`), so it never takes a slider or button touch. Its effect shows once the level opens.
- The level has no way back to the menu, so the drive reopens the menu by scene change between schemes. That reset is not part of the proof.
- The touch scheme also runs over the main menu. At the 360-unit minimum short side (a headless run's 360×360 window), the locked stick's grab radius reaches the `Start Game` button; real phone sizes keep them apart.
- The safe area is zero on a desktop run. Notch insets only exist on a real iPhone (web export) or mobile build, so `touch-safe-area` is not proven by a desktop drive.
- The web query `?touch=<scheme>` or `?touch=off` overrides the saved scheme for that page load. With `off` the Settings touch row is hidden.
- The drive leaves `drag` saved. A second drive without `cleanup` starts from it.
