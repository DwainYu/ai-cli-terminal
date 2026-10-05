# Compatibility matrix

Evidence from this machine (WSL Ubuntu-22.04 + Windows via interop), probes
2026-10-05: Phase-1 baseline, Phase-2 re-probes and real-environment runs.
Everything marked *machine-specific* is an observation, not a universal claim —
re-probe before trusting it elsewhere (D14, and the V0 failure log in
`docs/design-decisions.md`).

## Per-CLI strategies (D8 order: A → B → C → D)

| CLI | Version probed | Strategy | Evidence (2026-10-05) | Status |
| --- | --- | --- | --- | --- |
| **CodeBuddy** | 2.161.3 | A/B hybrid: `CODEBUDDY_CODE_DISABLE_TERMINAL_TITLE=1` (per process) + wrapper title | control run: exactly one `OSC 0` with an **empty payload**; with the variable: **zero** writes; wrapper run: only `<project> · CODEBUDDY` | probe-verified; real-project run PASS |
| **Qoder** | qoderclicn 1.1.65 | A: inject `-n "<project> · QODER"` when the user did not pass `-n`/`--name` | **both `-n` and `--name` accepted** → `◇ probe · QODER \| Ready`; control run → `◇ Qoder CLI CN \| Ready`; empty `OSC 0` on exit (wrapper restore runs after) | injection probe-verified; real-project run PASS; exact plain label needs the config step below |
| **OpenCode** | v2.0.23 | A: per-process env — `OPENCODE_CLI_CONFIG_CONTENT='{"terminal":{"title":false}}'` + `OPENCODE_DISABLE_TERMINAL_TITLE=true` (forward compat) | suppression matrix below; wrapper run: only `<project> · OPENCODE` | **verified** (D9); plugin no longer part of any strategy |
| **PI** | 1.0.3 | C: project-owned extension (`-e src/cli/pi-title.ts`) + one deferred re-emit | full `pi --help` has **no title-disable flag**; real-project lifecycle: wrapper title → extension `session_start` emit → `π - agent-toolbox` → deferred re-emit **wins** (final title) | verified end to end |

### OpenCode suppression matrix (local v2.0.23, PTY, temp HOME)

| Mechanism | Result |
| --- | --- |
| control (no suppression) | writes `OpenCode` once |
| `OPENCODE_DISABLE_TERMINAL_TITLE=1` | still writes — **FAIL on this build** |
| `OPENCODE_DISABLE_TERMINAL_TITLE=true` | still writes — **FAIL on this build** |
| `OPENCODE_CLI_CONFIG_CONTENT='{"terminal":{"title":false}}'` | **zero writes — PASS** |

Official status of the flag: documented in upstream `cli.mdx` ("Disable
automatic terminal title updates") and implemented in
`anomalyco/opencode` `packages/core/src/flag/flag.ts` (upstream repo —
`sst/opencode` now redirects there); the string is absent from the local
v2.0.23 binary, which is why it is exported for forward compatibility only.
Phase-1's failed attempts used the wrong variable
(`OPENCODE_CONFIG_CONTENT`) and the wrong file (`tui.json` → now `cli.json`);
do not retry them.

Notes:

- Qoder's `-n` injection and the user's own `-n`/`--name` never coexist: the
  adapter checks `ACT_USER_ARGS` first (AC3, integration tested).
- OpenCode validation runs use `--standalone` so the interactive TUI is never
  conflated with a background service (the wrapper does not wait on either).
- The exact Qoder label `<project> · QODER` (without `◇ … | Ready` decoration)
  additionally needs `ui.hideWindowTitle` in `~/.qoder-cn/settings.json` — a
  global, `--apply`-gated config step that Phase 2 deliberately does not write
  (D10); until then the wrapper's exact title is what the tab shows *before*
  Qoder's decorated refresh.

## Validation results

### WSL real environment (manual layer — AC-P2-06)

`./tests/manual/wsl/validate.sh` — real CLIs, real project directories,
isolated temp `HOME`, process-group-only cleanup:

| Project | CLI | First observed title | Result |
| --- | --- | --- | --- |
| `agent-toolbox` | PI | `agent-toolbox · PI` | **PASS** (4-title lifecycle ended on our title) |
| `tft-training-log` | OpenCode (`--standalone`) | `tft-training-log · OPENCODE` | **PASS** (no `OpenCode` write) |
| `hengguang-ai-platform-demo` | CodeBuddy | `hengguang-ai-platform-demo · CODEBUDDY` | **PASS** (single write, empty OSC suppressed) |
| `md-content-publisher` | Qoder | `md-content-publisher · QODER` | **PASS** (then Qoder's decorated refresh carries the same label) |

Isolation checks after the run: no file in any of the four project
directories was created or modified by the harness (concurrent activity on
the machine — a user-owned Qoder session since 21:01, vite/codegraph runs —
was distinguished by timestamps and temp-`HOME` pid markers).

### Windows (AC-P2-05 / AC-P2-07 / AC-P2-12)

| Item | Status |
| --- | --- |
| `scripts/test-windows.ps1` harness | **READY — executed on Windows PowerShell 5.1: 7/7 PASS** |
| `D:\ghq\github.com\DwainYu\TFTAutoRecorder` project name | **PASS** → `TFTAutoRecorder` |
| `pi` / `opencode` / `codebuddy` / `qoder` on Windows | **NOT AVAILABLE** (not installed; harness never installs) |
| Real Windows Terminal 4-tab check (AC5/AC6/AC8) | **NOT VERIFIED** — procedure in `tests/manual/windows/README.md` |

The harness is read-only: no install, no `settings.json` edit, the only side
effect is a window-title round trip that restores the original title.

## Shell / platform matrix

| Environment | Project name | Title emission | Wrapper | Status |
| --- | --- | --- | --- | --- |
| WSL bash (this repo) | `basename($PWD)` | `OSC 0` via `act::title::emit` → `ACT_TITLE_SINK` / stdout / `/dev/tty` | `src/run/act-wrap.sh` + `bin/*` | implemented; unit + integration green; real-environment run PASS |
| bash prompt (no CLI) | `basename($PWD)` | same helper, from the rc marker block's `PROMPT_COMMAND` hook | n/a | implemented; sourced-twice PATH/PROMPT guard tested |
| Windows PowerShell 5.1 | `basename` of `(Get-Location)` (PowerShell equivalent of the WSL rule) | `Host.UI.RawUI.WindowTitle`, `OSC 0` fallback, sink test hook | `Invoke-ActCli` in `src/shell/powershell/Wrappers.ps1` | **harness PASS (7/7); `Invoke-ActCli` itself untested — no AI CLI on Windows** |
| PowerShell 7 (`pwsh`) | — | — | — | **NOT AVAILABLE** on this machine (5.1 tested instead) |
| cmd.exe | — | — | — | out of scope for V1 |

## Windows Terminal notes (from `MicrosoftDocs/terminal`, see `docs/references.md`)

- A profile's `tabTitle` fixes a static label and `suppressApplicationTitle`
  blocks `OSC 0`/`OSC 2` from the shell — our scheme assumes **neither** is set.
- Per-tab isolation (AC5/AC6) follows from `OSC 0` applying to the focused
  pane's tab; this is official behaviour but has **not** been re-verified in a
  real Terminal window yet (procedure: `tests/manual/windows/README.md`).
- OSC 9;9 (working directory) and OSC 133 (prompt marks) are documented but
  deliberately out of scope for V1.

## Migration from V0 (marvis)

| Topic | Status |
| --- | --- |
| V0 rc markers (`marvis-ai-cli-tab-title`, `MARVIS-AI-CLI-WRAPPER`) | **detected, never rewritten** — install/status report *manual migration required* |
| V0 wrappers in `~/.local/bin` | read-only, reported as leftovers; V1's PATH entry is guarded and, on first source, precedes them |
| V0 `~/.config/opencode/plugins/marvis-tab-title.ts` | **obsolete for V1** — superseded by the official env strategy (D9); deleting it from the real machine is the user's manual step |
| Coexistence guarantees | tested in `tests/integration/test_migration.sh`: install ×2 idempotent, V0 block byte-identical, uninstall restores the V0-era file byte-for-byte |

## Known gaps

1. Qoder `ui.hideWindowTitle` config step not implemented (exact plain label;
   `--apply`-gated, D10).
2. Real Windows Terminal verification of AC5/AC6/AC8 not done (manual
   procedure ready).
3. Windows side has no AI CLIs → `Invoke-ActCli` runs only on WSL for now.
4. `pwsh` (PowerShell 7) unavailable here — harness validated on 5.1 only.
5. V0 leftovers on this machine (`~/.local/bin/{pi,opencode,codebuddy,qoder,
   qoder-cn}`, the `marvis-ai-cli-tab-title` block in `~/.bashrc`, the legacy
   OpenCode plugin) are reported by `scripts/status.sh` but never modified.
