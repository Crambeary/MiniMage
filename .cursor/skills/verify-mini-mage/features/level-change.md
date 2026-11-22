# Level change

Level change sends the mage to the next scene after they walk into an exit area.

## Sub-features

- `level-exit-1` leaves level 1 for level 2.
- `level-exit-2` leaves level 2 for the end screen.
- `level-end` shows the end-screen copy.

## How to get to it (user POV)

- Press `Start Game` to enter level 1 (`res://assets/scenes/levels/main.tscn`).
- Walk into the exit area on the upper side of that room (the area collision sits near `(-48, -96)`).
- On level 2 (`res://assets/scenes/levels/level_2.tscn`), walk into that level's exit.
- Read the end screen (`res://assets/scenes/ui/EndScreen.tscn`). The title block says `The End` and `Thank you for playing!`.

## Driving it with mm-verify

Preconditions:

- `mm-verify doctor` prints `VERIFY_DOCTOR ok`.
- Movement still uses `A` `D` `W` `S` only. Do not set the player's position to the exit.

- **Leave level 1.** There is no automated drive. `.cursor/skills/verify-mini-mage/helpers/mm-verify drive level-change` exits 3 and must not be reported as a pass.
- **Level 2 is open.** The current scene path is `res://assets/scenes/levels/level_2.tscn` and a player is in the level.
- **End screen.** After level 2's exit, the window shows `The End` and `Thank you for playing!`.

## Gotchas

- The level 1 exit is far from the spawn at `(-464, -24)`, and `D` is blocked near `x=-435`. Reaching the exit needs a real route around collisions and sentries. If that route is blocked, record the block. Do not teleport.
- Level 2's exit points at the end screen. Level 3 (`res://assets/scenes/levels/level_3.tscn`) is not on this chain. Opening level 3 directly is not this feature.
- `evidence/walk/` never changes scene past level 1.
