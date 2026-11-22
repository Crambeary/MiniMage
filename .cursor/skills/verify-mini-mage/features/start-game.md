# Start the game

Start the game leaves the main menu and puts the mage in level 1.

## Sub-features

- `start-show` draws the title `Mini Mage` and a button labeled `Start Game`.
- `start-enter` loads level 1 when that button is released.
- `start-spawn` places the player at the level 1 spawn.

## How to get to it (user POV)

- Launch the game and wait on the main menu. That menu is the project main scene.
- Press the `Start Game` button.

## Driving it with mm-verify

Preconditions:

- `mm-verify doctor` prints `VERIFY_DOCTOR ok`.
- No drive is running for this repo.

- **Show the menu.** Run `.cursor/skills/verify-mini-mage/helpers/mm-verify drive start-game`. Before the click, `evidence/start-game/menu.png` shows the title `Mini Mage` and a button whose text is `Start Game`. `result.json` field `menu_title` is `Mini Mage`.
- **Enter level 1.** The same command clicks that button. `result.json` field `scene_after_click` is `res://assets/scenes/levels/main.tscn`. `evidence/start-game/level-before.png` shows the level, not the menu.
- **Confirm the spawn.** `result.json` field `player_before` has x `-464` and y `-24`, and `pass` is true. The log contains `VERIFY_PASS start-game`.

## Gotchas

- The button signal is `button_up`. A press without a release does not leave the menu.
- Click the button inside the menu, not the `Locked`, `Floating`, or `Drag` buttons. Those belong to the touch switcher and sit on the top-right of the window.
- `load()` of the main-scene uid fails before `mm-verify launch`. The symptom is an empty window and a missing player.
- `drive start-game` does not check keyboard movement. Use [Walk](./walk.md) for that.
