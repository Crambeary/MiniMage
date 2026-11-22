# Touch scheme

Touch scheme picks how the on-screen control moves the mage: locked joystick, floating joystick, or a drag area.

## Sub-features

- `touch-show` shows the `Locked`, `Floating`, and `Drag` buttons on the top-right.
- `touch-floating` selects `Floating` when the game starts.
- `touch-switch` swaps the on-screen control when another scheme button is pressed.
- `touch-move` moves the mage when the active scheme is swiped.
- `touch-safe-area` keeps the switcher and the locked stick inside the safe area (notch, island, home indicator).

## How to get to it (user POV)

- Launch the game. The three buttons are drawn over the menu and over the level.
- Press `Locked`, `Floating`, or `Drag`.

## Driving it with mm-verify

Preconditions:

- `mm-verify doctor` prints `VERIFY_DOCTOR ok`.
- The window is the 960×540 verification window.

- **Automated.** `.cursor/skills/verify-mini-mage/helpers/mm-verify drive touch-scheme` presses each button, swipes, and checks the player moved. See SKILL.md for the recipe. Set `MM_VERIFY_RESOLUTION=844x390` or `390x844` to check a phone-sized layout.
- **Default scheme.** On launch, `Floating` is the pressed button.
- **Switch.** Press `Locked` or `Drag`. That button becomes the pressed one, and the previous scheme's control is gone.

## Gotchas

- The switcher is visible on a desktop run, not only on a phone. Its buttons share the window with `Start Game`. A click aimed at the top-right does not start the game.
- `walk` screenshots include the switcher because it is part of the window. That is not a scheme-switch proof.
- The safe area is zero on a desktop run. Notch insets only exist on a real iPhone (web export) or mobile build, so `touch-safe-area` is not proven by a desktop drive.
- A floating-stick press on a switcher button is ignored (`TouchControls.is_switcher_at`), so switching schemes from the floating scheme does not leave a stick behind.
- The web query `?touch=` is a different entry. This map's desktop path is the three buttons.
