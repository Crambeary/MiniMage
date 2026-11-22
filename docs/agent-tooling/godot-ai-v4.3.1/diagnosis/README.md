# Migration failure diagnosis — 2026-10-29

Baseline: migration commit `f25b3c4`, Godot 4.7.2, NVIDIA 615.78.08,
OpenGL compatibility rendering, Linux desktop. No Godot editor was running
when this follow-up started. All processes launched for this investigation
were closed afterwards. Shared legacy servers and client settings were not changed.

## GUT: two full green runs, original failure cause unproved

Without changing game, addon, or test code:

| Run | Result | Evidence |
| --- | --- | --- |
| Full suite, normal user directories | 693/693, 5031 assertions, 194.257 s | [full-suite-before.log](full-suite-before.log) |
| Full suite, fresh XDG config/data/cache | 693/693, 5031 assertions, 204.274 s | [full-suite-fresh-xdg.log](full-suite-fresh-xdg.log) |
| Previously failing scripts, fresh user data | 33/33, 68 assertions | [focused-fresh-user.log](focused-fresh-user.log) |
| First held-touch test, 640×360 window | 1/1 | [small-window.log](small-window.log) |

The full command was `"$GODOT_BIN" --path . -s addons/gut/gut_cmdln.gd`,
headed with rendering. The isolated run set XDG_CONFIG_HOME, XDG_DATA_HOME,
and XDG_CACHE_HOME to fresh private directories before that same command.
The focused command added
`-gconfig=res://docs/agent-tooling/godot-ai-v4.3.1/gut-control-config.json`.

This clears the previous red full-suite verdict for the current checkout.
It does **not** establish why the old 22 failures occurred, or prove that
they cannot recur. The original UI-hit traces remain in the parent directory.
The green runs also emit pre-existing mock-node, malformed-config and UID
diagnostics; passing GUT assertions do not mean a diagnostic-free log.

## Import: reproducible below the v4 plugin

The checked-in [scan probe](../../../../tools/tests/diagnose_godot_ai_scan.py)
copies tracked public project bytes into disposable projects, omits the import
cache, isolates XDG state, and samples EditorFileSystem directly from a small
editor plugin. A bounded supervisor terminates only its own launched PIDs.
It never reads capability records or calls an unpinned MCP tool.

Observed controls:

- One minimal editor scans successfully with and without the v4 plugin:
  [without addon](scan-without-addon.log), [with addon](scan-with-addon.log).
- One cold full-project editor with v4 reached `ready`:
  [full-cold-scan-with-addon.log](full-cold-scan-with-addon.log).
- Two minimal editors scanned successfully:
  [two-minimal-cold-scans.log](two-minimal-cold-scans.log).
- Two cold full-project editors stayed `is_scanning=true` at progress `1.0`
  with v4 enabled, and also with the v4 editor plugin disabled:
  [enabled](two-full-cold-scans.log), [disabled](two-full-cold-scans-without-addon.log).
  Those runs overlapped the full GUT run. The disabled variant retains tracked
  addon files and project autoload configuration; it disables the editor plugin.
- A subsequent pair without concurrent GUT completed scanning in about 16 s:
  [instrumented control](two-full-cold-scans-dialogs.log).
- Running the actual game alongside two cold imports reproduced the stall
  twice with the v4 editor plugin disabled. At progress `1.0`, `is_importing`
  remained false; stopping the game after 25 seconds did not release the stall:
  [render-load run](two-cold-scans-render-load.log),
  [debugger run](two-cold-scans-debugger.log).

Reproduce that red-capable scenario from the migration worktree:

```sh
rtk proxy python3 tools/tests/diagnose_godot_ai_scan.py \
  --godot "$GODOT_BIN" --full-project --editors 2 --render-load-seconds 25 \
  --output docs/agent-tooling/godot-ai-v4.3.1/diagnosis/repro.log
```

The plugin deadline is 30 seconds. In stalled imports, Godot's normal quit
request itself can remain pending; the supervisor then terminates/kills its
owned editors. Initial debugging runs were explicitly force-closed after
their timeout evidence was captured. This fixture copies projects; it does
not create Git worktrees or alter the source project's plugin settings.

## Where the stalled editor is spending time

Two debugger snapshots captured the main thread sleeping and querying native
window geometry: [thread stacks](scan-stacks.txt),
[second main-thread stack](main-stack-full.txt). The binary is stripped, so
Godot function names are unavailable. [Disassembly](window-wait-disassembly.txt)
shows a bounded counter, a 10 ms sleep, window-attribute queries and width/height
comparisons. This matches the native resize polling in
[Godot 4.7.2 DisplayServerX11::window_set_size](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/linuxbsd/x11/display_server_x11.cpp#L2540).
Repeated polling during import is the identified blocking path; the exact
caller and window-manager interaction are not yet established.

Godot's [is_scanning implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/editor/file_system/editor_file_system.cpp#L1713)
includes the initial-scan completion flag. Thus scan progress `1.0` can coexist
with unfinished initialization. v4 correctly reports this engine state; making
its readiness gate ignore the state would hide the problem.

Attempted workarounds were not accepted:

- `--single-window` still stalled: [log](two-cold-scans-single-window.log).
- Native Wayland let one peer finish, but the other editor crashed with signal 11:
  [log](two-cold-scans-wayland.log). This is not a qualified alternate backend.

## Remaining rollout gate

**Follow-up acceptance:** the full two-editor authenticated scene/reconnect/
undo/runtime harness subsequently passed with no game/GUT process running
during initial import. See [the current rollout status](../README.md#latest-acceptance-status--2026-10-29)
and [the captured result](../two-editors-full-acceptance.json). This clears the
staged integration gate described below; it does not fix or qualify the
concurrent-render-load X11 stress case. Shared-client cutover is still pending.

The original assertion failures are currently green. The cold-import problem
is localized to the engine/windowing path and is reproducible without the v4
editor plugin; it is not diagnosed as an authentication or routing failure.
There is no engine fix or reliable concurrent-import workaround in this change.

For further validation, finish cold imports with no game/GUT process running,
then run the two-editor authenticated scene/reconnect/undo harness. This is a
test-order precaution, not a claim that all forms of parallel import are fixed.
The complete two-editor migration acceptance gate and shared-client cutover
remain unqualified. No game code or signed addon bytes were changed here.
