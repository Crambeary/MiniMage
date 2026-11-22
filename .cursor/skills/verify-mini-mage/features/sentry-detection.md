# Sentry detection

Sentry detection is the faculty patrol noticing the mage, showing a question mark or an exclamation, and ending the run when fully alerted.

## Sub-features

- `sentry-patrol` walks a sentry along its waypoint path.
- `sentry-suspicious` shows a question mark while the sentry is suspicious.
- `sentry-alert` shows an exclamation and leaves the level when the sentry is fully alerted.

## How to get to it (user POV)

- Press `Start Game`.
- Walk the mage into a sentry's view on level 1. Sentries start near `(-112, 0)` and `(-256, -64)`. The mage starts at `(-464, -24)`.
- Watch the mark above the sentry. A full alert is supposed to open the game-over screen.

## Driving it with mm-verify

Preconditions:

- `mm-verify doctor` prints `VERIFY_DOCTOR ok`.
- Level 1 is open, with the player still in group `player`.

- **Reach a sentry.** There is no automated drive. `.cursor/skills/verify-mini-mage/helpers/mm-verify drive sentry-detection` exits 3 and must not be reported as a pass.
- **Suspicious.** While the sentry can see the mage, the question-mark graphic is visible and the status bar above the sentry changes.
- **Alerted.** On a full alert the exclamation is visible and the game calls a scene change to `res://assets/scenes/ui/game_over_screen.tscn`.

## Gotchas

- `res://assets/scenes/ui/game_over_screen.tscn` is not in the project. A full alert's scene change fails. That missing scene is a real gap. Do not treat "the level stayed open" as a successful game over, and do not delete the scene change to make a run pass.
- The walk proof stops at the collision near `x=-435` and never enters sentry view. Do not cite `evidence/walk/` as detection proof.
- `tests/pin_sentry_detection.gd` places a sentry and a player node, then sets the player position. That is not this feature. Do not report its exit code as a playthrough.
- Sentry prints (`Sentry alertness_state changed to`) are not enough. The mark or the game-over scene has to be visible.
