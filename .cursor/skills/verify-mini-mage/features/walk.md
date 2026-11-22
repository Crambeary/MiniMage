# Walk

Walk moves the mage across level 1 with the keyboard after the player has started the game.

## Sub-features

- `walk-enter` reaches level 1 from `Start Game`.
- `walk-right` moves the mage right while `D` is held.
- `walk-stop` stops the extra travel when the mage meets a collision.

## How to get to it (user POV)

- Press `Start Game` on the main menu.
- Hold `D` on level 1. `A`, `W`, and `S` are the other movement keys.

## Driving it with mm-verify

Preconditions:

- `mm-verify doctor` prints `VERIFY_DOCTOR ok`.
- No drive is running for this repo.
- The run uses the 960×540 window the helper opens.

- **Enter level 1.** Run `.cursor/skills/verify-mini-mage/helpers/mm-verify drive walk`. The helper clicks `Start Game`. `evidence/walk/menu.png` shows `Mini Mage` and `Start Game`. `result.json` field `scene_after_click` is `res://assets/scenes/levels/main.tscn`.
- **Read the spawn.** `player_before` is the spawn near `{"x": -464, "y": -24}`. `evidence/walk/level-before.png` is the frame before any movement key.
- **Hold D.** The helper posts physical key `D` for 45 physics frames, then a key-up. `player_after.x` is at least 20 greater than `player_before.x`. `delta_x` records that gap. `evidence/walk/level-after.png` is the frame after the key-up.
- **Proof.** `pass` is true and `drive.log` contains `VERIFY_MOVED` plus `VERIFY_PASS walk`.

## Gotchas

- From the spawn, `D` meets a collision near `x=-435` (about 29 pixels). `delta_x` stays around that distance even if the key is held longer. Do not raise the bar above 20 pixels to demand a clear hallway.
- The player `Camera2D` follows the mage, so the sprite stays near the same screen point and the room shifts. Compare `level-before.png` with `level-after.png` together with `delta_x`.
- `A` from the spawn meets a wall within a few pixels. A short leftward nudge can look like a dropped key.
- Sentries stand to the right of the spawn. This recipe stops at the nearby collision and does not walk into them.
- Post the key every physics frame. One key-down from a script is not a held key.
