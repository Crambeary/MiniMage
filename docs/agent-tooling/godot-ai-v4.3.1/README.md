# Godot AI v4.3.1 vendoring and staged validation

## Shared checkout-hook rollout — 2026-10-29

The clone-wide installed `post-checkout` now matches the compatible tracked
hook in this branch. [Installation record](shared-hook-install.json) captures
the before/after digests and scope. Only that hook was replaced, atomically;
the previous copy is preserved in the common Git directory as
`hooks/post-checkout.pre-godot-ai-v4`. Every other installed hook was verified
unchanged. In particular, the newer main-branch Blender `post-merge` hook
was not overwritten by this branch's older copy. Do not run the all-hooks
installer from this branch as part of this rollout.

Read-only inventory found 153 worktrees: 152 with a v3 gitlink and the correct
relative addon symlink, and this physical v4 worktree. None overrides
`core.hooksPath`. No existing worktree required repair, and no other branch,
index, project setting or addon working copy was changed. The 74 worktrees
with local changes were left intact. No Godot editor/game process was running
at this checkpoint.

The installed hook consults the target worktree's **index**, not leftover
directories. It initializes/links only a stage-zero v3 gitlink; it leaves v4
tracked addon files alone even if an old submodule directory remains. For
legacy checkouts it refuses to replace physical content or an unexpected
symlink. Five focused tests cover these cases and initialization ordering;
fresh-worktree plumbing and all 34 routing/transport tests also pass.

Existing v3 branches remain on v3 until they integrate the migration PR.
Close their own editor before integrating, preserve any local submodule
changes, and review leftover `addons/godot-ai` content afterwards. Git can
leave that old working copy behind; keep its `.gdignore` until it can be
removed safely. Do not delete shared submodule storage. The installed hook
will not recreate the legacy symlink in a v4 checkout. Keep the matching v3
backend/client entry available until those worktrees migrate.

This completes shared checkout-hook preparation for the mixed-version
rollout. PR review/merge and authenticated T3/Codex/Claude client cutover are
still pending. Reinstalling a hook from an older v3 branch would undo this
protection; use the reviewed compatible hook for this clone.

## Latest acceptance status — 2026-10-29

The full two-editor authenticated harness now passes, using two full-game
worktrees (no lightweight peer). No editor, game or GUT process was running
before the run; the newly created peer had no import cache. Both editors
finished imports and reported `readiness=ready`, opened
`res://scenes/prologue_startup.tscn`, and returned separate pinned hierarchies.
Both plugin/server versions were 4.3.1. Restarting the primary editor while
the peer stayed connected refreshed its session ID; a property edit and real
editor undo verified `process_priority` 0 → 7 → 0. The subsequent main-scene
run reported `helper_live=true` and was stopped before editor cleanup.

Evidence: [full harness result](two-editors-full-acceptance.json) and
[public fixture/MCP event excerpts](two-editors-full-acceptance-events.log).
Reproduction from this worktree, after creating a fresh peer at the same
commit with `wt`:

```sh
rtk proxy python3 tools/tests/run_godot_ai_integration.py \
  --peer /path/to/owned-fresh-full-game-worktree --port 18435 --ws-port 19435 \
  --output docs/agent-tooling/godot-ai-v4.3.1/two-editors-full-acceptance.json
```

The harness exited 0. Project settings were restored, generated import
sidecars/settings were cleaned up, and both owned editors and their game
process were closed. Account client settings and the installed shared checkout
hook were unchanged. Together with the two 693/693 headed GUT reruns in
[the diagnosis](diagnosis/README.md), this clears staged migration acceptance.
The known X11 stall under concurrent rendering load remains unresolved; this
successful run does not qualify that stress scenario. Live harness connections
and the coordinated installed-hook/client cutover remain pending.

Earlier failed attempts below are retained as historical evidence; this
section supersedes their statements that the full two-editor gate is blocked.

Implementation baseline: approved plan `62356c6fcf6e9232d436b9119143b14b99724e30`,
including main `e346267`. The previous gitlink was
`b1d767657fac87ef2a13a02c8ed58f4aa441db48` (v3.1.1). Its relative symlink was
`addons/godot_ai -> godot-ai/plugin/addons/godot_ai`. `.gitmodules` contained
only that upstream. The checkout hook initialized it and wrote `.gdignore`.
The implementation removed only this worktree's index entry, link and working
copy; it never deinitialized or changed shared submodule storage.

## Immutable verification inputs

`release/` contains the three canonical published assets downloaded from
<https://github.com/hi-godot/godot-ai/releases/tag/v4.3.1> (not the legacy
migration capsule). The signed manifest binds source commit
`35da2c2fe1e2c20e11b5be01841e966951d6314b`, repository, channel, tag, version,
archive digest and every installed path/byte. The upstream verifier rejects
extra files and links. `tools/vendor/godot-ai-v4.3.1/` preserves the unmodified
upstream CLI, sibling verifier, MIT license, source digests and pinned public
SPKI fingerprint `84ebbd811f3a12c09ff4e236bbbbb9310fc23e03fcfc3717ba546747d0d21072`.
These are public inputs. No capability record or credential is included.

Reproduce offline from the checked-in inputs (Python 3.11–3.14 and OpenSSL):

```sh
rtk proxy python3 tools/verify-godot-ai.py
```

Acquire the same published inputs, if needed, into an **empty** directory:

```sh
rtk gh release download v4.3.1 --repo hi-godot/godot-ai --pattern 'godot-ai-v4-*' --dir /path/to/empty-release
```

The CLI and verifier are exact blobs from the source commit above, at
`script/v4-release` and `src/godot_ai/release_verify.py`. `SOURCE.json` records
their digests for review. Verify against these pinned inputs, never a newly
fetched trust key. The installed tree is unmodified upstream release content.

To reproduce the clean install in a disposable project with its editor closed,
create `project.godot` and an `addons` directory, ensure `addons/godot_ai` does
not exist (including as a symlink), then run:

```sh
rtk proxy python3 tools/vendor/godot-ai-v4.3.1/script/v4-release install \
  --archive docs/agent-tooling/godot-ai-v4.3.1/release/godot-ai-v4-plugin.zip \
  --manifest docs/agent-tooling/godot-ai-v4.3.1/release/godot-ai-v4-plugin.manifest.json \
  --signature docs/agent-tooling/godot-ai-v4.3.1/release/godot-ai-v4-plugin.manifest.sig \
  --expected-repository hi-godot/godot-ai --expected-channel stable \
  --expected-tag v4.3.1 --expected-version 4.3.1 \
  --expected-source 35da2c2fe1e2c20e11b5be01841e966951d6314b \
  --project-root /path/to/disposable-project
```

`install-receipt.json` records the successful fresh installation and tree hash.
The successful pending marker was archived here and removed from the working
installation before activation: its `replace_owned_mismatches=true` would
otherwise authorize automatic account-wide client repinning on first startup.
No failed/pending recovery evidence was discarded. Update backup/quarantine
state must be preserved on an actual failure. This repository deployment is
an ordinary tracked fresh tree and does not carry a client-migration marker.

## Runtime and rollout contract

The final v4.3.1 plugin still registers `_mcp_game_helper` at
`res://addons/godot_ai/runtime/game_helper.gd` (`plugin.gd` constants and
`_ensure_game_helper_autoload`). The existing project setting is correct and
is deliberately retained. Older migration notes about removing it are not the
final runtime contract. Export stripping is implemented by the upstream plugin.

The hook launches pinned `uvx ... godot-ai==4.3.1 godot-ai attach` and obtains
`session_manage(list)` through its authenticated stdio protocol. No project
code reads capability records. Both `GODOT_AI_PORT` and `GODOT_AI_WS_PORT`
are required, distinct integers in 1024..65535. Copy the effective pair from
Editor Settings: `godot_ai/v4_endpoint_ports` takes precedence over legacy
`godot_ai/http_port` and `godot_ai/ws_port`. A missing pair fails closed before
launching an editor. Changing hook environment alone does not change Godot's
Editor Settings. `GODOT_AI_ATTACH_CMD` overrides the launcher prefix for
isolated tests; the hook always appends the selected pair.

Each discovery starts a fresh attach process, initializes MCP, requests only
the session inventory and closes the bridge. Newline JSON frames, message
counts and response deadlines are bounded; stderr is discarded so bridge
errors cannot disclose private material. MCP failures become safe diagnostics.
Discovery defaults to a 30-second bridge deadline (`GODOT_AI_BRIDGE_TIMEOUT`
can override it); cold package acquisition should be prewarmed before live
client cutover. Bridge exit/termination is reaped in a private process group. Shared backend
processes are outside that group and managed exclusively by upstream leases.
No direct HTTP fallback remains. Own Session pinning, ambiguity denial,
foreign-ID denial, resource prohibition, Active Session prohibition, and
per-worktree editor-launch deduplication remain in force.

## Live cutover remains separate

No shared server was stopped, no account client config changed, and no live
client was repinned. T3/Codex/Claude effective v4 connections therefore remain
unqualified until coordinated cutover. Keep v3 worktrees on their current
backend; choose a separate v4 pair in Editor Settings and supply that pair to
the hook and attach client entries. Configure/reopen only the intended clients,
then prove an authenticated handshake and a pinned read for each harness.
Reverting this branch cannot undo account-wide settings. Preserve old client
launch metadata privately and restore a matching v3 addon/helper/endpoint
combination if rolling back. Do not paste or inspect credentials.


The initial staged validation left the clone-wide v3 checkout hook unchanged.
The subsequent shared-hook rollout above replaces that copy with an
index-aware compatible hook, preserving legacy worktree initialization while
protecting the tracked physical v4 tree. Fresh-checkout coverage uses an
invocation-local hooksPath and does not itself modify shared hooks.
The historical curbside export utility now omits its unused MCP addon instead
of depending on the removed submodule working copy.


## Validation commands and results

- `python3 -m unittest discover -s tools/tests -p 'test_godot_ai*.py'`:
  34 policy/transport tests passed, including concurrent launch deduplication
  and timeout cleanup of bridge descendants. See `routing-tests.txt`.
- `bash tools/tests/test_worktree_plumbing.sh`: passed both physical checkout
  and launcher checks. See `plumbing-tests.txt`. It creates/removes fixtures
  through Worktrunk and uses an invocation-local hooksPath.
- `python3 tools/verify-godot-ai.py`: signature, identity, exact inventory,
  physical layout, and pinned verifier digests passed. Two upstream files
  contain trailing blank lines; they remain untouched signed release content.
- Godot 4.7.2 headed editor: plugin/server version 4.3.1, pinned hierarchy,
  reconnect session refresh, real undo (`process_priority` 0 → 7 → 0), and
  `helper_live=true` passed. See `initial-results.json`, `edit-results.json`,
  `runtime-results.json`, and sanitized editor logs. The first import emitted
  UID and inferred-type diagnostics outside the addon; the subsequent ready
  editor and running helper recovered without vendored changes.
- Full verdict: `Godot_v4.7.2-stable_linux.x86_64 --path . -s
  addons/gut/gut_cmdln.gd`, with rendering enabled, completed **693 tests:
  671 passing, 22 failing**, 5031 assertions, 217.53 seconds. See
  `gut-headed.log`. Failures are in `test_hold_drag_fries.gd` (5) and
  `test_phone_touch_navigation.gd` (17): touch/click selection and held-drag
  preconditions fail, with UI-hit traces. A green full-suite acceptance gate remains blocked; the control run below
  isolates whether the new runtime helper accounts for these failures.
- Shared legacy discovery after staged v4 tests still returned three v3.1.1
  plugin sessions (`legacy-backend-check.json`). No foreign editor command
  was sent. This proves discovery availability, not ownership-qualified
  pinned reads of other agents' worktrees.

The headed harness is reproducible from checked-in code:

```sh
rtk proxy python3 tools/tests/run_godot_ai_integration.py \
  --peer /path/to/another-owned-worktree --lightweight-peer --port 18435 --ws-port 19435 \
  --output docs/agent-tooling/godot-ai-v4.3.1/two-editors.json
```

Create that peer with `wt`, using the implementation commit, and launch only
owned worktrees. The harness temporarily enables the bootstrap fixture,
sets only isolated Editor Settings, keeps an authenticated attach lease alive,
restores both project files, and closes only its launched editor PIDs. It
never invokes client Configure, Active Session changes, or resource reads.
Private runtime state is never used as repository evidence. Its first
cold-start two-editor attempt timed out; the revised harness starts and keeps
the attach lease before imports rather than cycling short-lived cold bridges.


A second two-editor attempt registered both authenticated sessions before
imports finished; the captured `two-editors-importing-attempt.json` shows one
session `no_scene` and the peer `importing`. Immediate `scene_open` failed.
The fixture now waits/retries pinned state and scene opening before asserting
scene behavior. Session discovery alone is not an import-completion barrier.
This observation was sent to the concurrent triage coordinator; it is not a
claim to have diagnosed that task's separate v3 import stall.


A subsequent full-game peer attempt kept answering pinned state reads but did
not leave `importing` within the 150-second scene-readiness window; see
`two-editors-import-timeout.json` (the primary full-game editor was ready).
That clean full-game peer import remains an acceptance blocker. The small
peer fixture is explicitly scoped to transport/session isolation, and does
not claim to qualify a clean full-game import. It temporarily ignores game
asset directories and other addons only in the disposable owned peer;
`finally` restores its project file and removes only ignores the fixture made.


`two-editor-pinned-states.json` records successful authenticated **pinned
read-only** calls to both owned editors: `FryTruckGame` was `ready`, and
`Migration peer fixture` was `importing`. Their project identities and paths
were distinct and correct. The lightweight peer's scene-readiness run was
stopped after preserving this evidence (`two-editors-lightweight-import-blocked.json`);
its editor processes were closed by the harness cleanup. The final harness
supports `--reads-only` to reproduce this narrower qualification separately
from the still-blocked full scene/import gate.

Both upstream v3.1.1 (gitlink baseline `b1d767657fac87ef2a13a02c8ed58f4aa441db48`)
and the committed v4 `connection.gd` compute `importing` directly from
`EditorInterface.get_resource_filesystem().is_scanning()`. An authenticated,
responsive state read does not imply that filesystem scanning is finished.
No cause for the stuck scan was established, and no plugin implementation
was changed to bypass the gate. These findings were sent to the concurrent
triage coordinator without changing or closing any v3 editor.


The same two failing scripts were then run headed in isolation, with the
checked-in `gut-control-config.json` and no editor process running. With the
project's v4 helper present, **33/33 passed** (`gut-with-helper-control.log`,
`gut-with-helper-result.json`). A preceding run with only the helper autoload
line temporarily removed had **32/33 passing**, with one location-switch HUD
assertion failing (`gut-without-helper-control.log`, `gut-control-result.json`).
The original project file was restored byte-for-byte after that control.
Command for both runs (the helper-disabled variant temporarily removes only
`autoload/_mcp_game_helper`):

```sh
rtk proxy "$GODOT_BIN" --path . -s addons/gut/gut_cmdln.gd \
  -gconfig=res://docs/agent-tooling/godot-ai-v4.3.1/gut-control-config.json
```

These focused results do not reproduce the full suite's failures as a
helper-specific regression. They do not replace or turn green the failed
full-suite verdict, nor establish whether suite order, UI timing or another
state caused it. No game code was changed in response. Full-suite acceptance
and a clean fresh-peer import remain open blockers. All task-owned editors
are closed and the disposable peer worktree was removed with Worktrunk.

Follow-up diagnosis (2026-10-29): two unchanged headed full-suite runs now pass
693/693, including a fresh-XDG run. The cold-import stall was reproduced with
the v4 editor plugin disabled and localized to native X11 resize polling;
neither single-window mode nor a Wayland trial supplied a qualified workaround.
See [the diagnosis and reproducible probe](diagnosis/README.md) for evidence,
controls, limitations, and the remaining two-editor acceptance gate.
