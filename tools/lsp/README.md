# Godot diagnostics for Codex and Claude Code

The selected integration is `@shin2344234/godot-mcp@0.1.2`, pinned with its
transitive dependencies in `upstream-trial/package-lock.json`. Codex exposes
only its four read-only status/code-analysis tools. Claude's project
`.mcp.json` launches the same read-only code toolset, including upstream's
read-only project info/settings and tool catalog. The companion addon is
vendored unchanged in `addons/godot_mcp`; godot-ai remains enabled for scene,
runtime and editor operations.

Follow [the agent workflow](../../docs/agents/gdscript-diagnostics.md) for setup,
when to run diagnostics, result interpretation and the command fallback.
After installing dependencies, restart the client in a trusted project and
approve Claude's `godot_lsp` project server when prompted. The launcher resolves the current worktree at runtime and
accepts `GODOT_BIN`; the config contains no machine-specific absolute paths.

## Verification

```sh
npm ci --prefix tools/lsp/upstream-trial --ignore-scripts
python3 tools/lsp/sync_upstream_addon.py
python3 -m unittest discover -s tools/lsp -p 'test_*.py'
```

The addon verifier compares all 103 upstream files byte-for-byte with the npm
package whose integrity is recorded in the lockfile. To restore a missing
addon directory from that package, run it with `--install`. It refuses to
silently overwrite an existing divergent addon.

The integration trial creates a disposable Git repository and linked worktree
with Worktrunk, installs the packaged addon there, launches two headed editors
through copies of `tools/open-editor.sh`, and calls the real MCP tools. It
checks syntax/type errors, clearing after disk edits, concurrent project
routing, outside-project paths, wrong/unavailable LSP endpoints, private-editor
fallback, and engine unavailability. It also checks discovery/tool filtering
and a diagnostic call through native Codex's app-server. No model is invoked.

```sh
python3 tools/lsp/trial_upstream.py \
  --package-root tools/lsp/upstream-trial/node_modules/@shin2344234/godot-mcp \
  --output docs/research/godot-diagnostics-fixtures/upstream-mcp-trial.json
```

For the actual project, first launch its own editor with an unused port pair:

```sh
tools/open-editor.sh --lsp-port 16005 --dap-port 16006
```

Then verify the checked-in `.codex/config.toml` through native Codex. The first
probe writes a temporary invalid script, checks it, fixes it, checks it again,
and removes it. The second checks the vendored addon in batches. Both require
the connected editor's LSP, not fallback validation.

```sh
python3 tools/lsp/probe_codex_mcp.py \
  --output docs/research/godot-diagnostics-fixtures/upstream-project-codex.json
python3 tools/lsp/probe_codex_mcp.py --addon \
  --output docs/research/godot-diagnostics-fixtures/upstream-addon-diagnostics.json
```

The [Claude evidence](../../docs/research/godot-diagnostics-fixtures/upstream-project-claude.json)
records actual Claude Code 2.1.311 model-turn tool calls in T3's Agent SDK
runtime: project config discovery, matching server/editor worktree paths,
syntax errors followed by a clean LSP result after a disk fix, and rejection
of absolute and parent-traversal paths. The SDK run used bypass-permissions
mode. Standalone `claude mcp get godot_lsp` found the project config but
reported pending approval; normal interactive CLI use requires approving it.
This is model-turn evidence, not a separate no-model native-client probe.

To repeat the Claude check, start a fresh Claude session in this worktree,
approve the server and ask it to call `godot_status`, create a unique temporary
`.gd` with `extends Node\nfunc broken(\n`, diagnose it, replace it with
`extends Node\nvar count: int = 1\n`, and diagnose it again sequentially.
Require `source: "lsp (connected editor)"`, errors on the first call and the
file under `clean` with zero errors on the second; remove the probe and any
generated `.uid`. Ask for an outside-project path and require `BAD_PARAMS`.

The Codex probes use invocation-only project trust for their ephemeral Codex
session; they do not change user trust records or run a model turn. Normal
Codex sessions still need the project marked trusted. Tests do not establish
that every model will remember to call diagnostics or that runtime behavior is
correct. Automatic post-edit hooks are not configured. GUT's headed-rendering
requirement remains in effect.

## Earlier experiments

`diagnostics.py` is the retained on-demand fallback; it verifies workspace
ownership before sending code and requires an explicit diagnostic publication.
`live_probe.py` tests that command and a directly invoked experimental hook.
`godot-lsp-bridge.py` serves stdio-LSP clients. `codex_hook.py` and
`probe_codex_hooks.py` remain research tools; there is no active hook manifest.
Earlier evidence is retained in `docs/research/godot-diagnostics-fixtures/`.

The earlier narrow `madewithscience/godot-lsp-mcp` candidate defaults to port
6005 in its tool path and can return no results after a timeout. It was not
adopted. Published upstream configuration is documented in
[shin2344234/godot-mcp setup](https://github.com/shin2344234/godot-mcp/blob/main/docs/setup.md).
