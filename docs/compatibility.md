# Compatibility matrix

Evidence from this machine (WSL Ubuntu-22.04, Windows Terminal), probes run
2026-10-05 with temp `HOME`s. Everything marked *machine-specific* is an
observation, not a universal claim — re-probe before trusting it elsewhere
(see `docs/design-decisions.md` for the V0 failure log behind that rule).

## Per-CLI strategies (D8 order: A → B → C → D)

| CLI | Version probed | Strategy | Evidence | Status |
| --- | --- | --- | --- | --- |
| **CodeBuddy** | 2.161.3 | A/B hybrid: `CODEBUDDY_CODE_DISABLE_TERMINAL_TITLE=1` + wrapper title | plain run writes `OSC 0`; with the variable set: **zero** `OSC 0` writes | probe-verified; end-to-end check pending |
| **Qoder** | qoderclicn 1.1.65 | A: inject `-n "<project> · QODER"` when the user did not pass `-n`/`--name` | with `--name "probe · QODER"` the tab shows `◇ probe · QODER \| Ready`; `ui.dynamicWindowTitle` default `true`; on exit it writes an **empty** `OSC 0` (wrapper restore runs after) | injection unit+integration tested; exact label needs the config step below |
| **OpenCode** | v2.0.23 | A: config `terminal.title: false`, wrapper title survives | binary has `setTerminalTitle("OpenCode")` gated by `terminal.title ?? true`; palette entry `terminal.title.toggle`; no plugin title hook. Tried `OPENCODE_CONFIG_CONTENT` and `tui.json`/`tui.jsonc` — neither suppressed it | **config path not yet found — pending** |
| **PI** | 1.0.3 | C: project-owned extension (`-e src/cli/pi-title.ts`) writes the title itself | PI emits `π - <cwd>` *after* `session_start`; extension schedules one deferred re-emit (400 ms, unref'd) from `session_start` and emits on other events; `ctx.ui.setTitle()` works only in command handlers | probe-verified mechanism; timing not finalized |

Notes:

- Qoder's `-n` injection and the user's own `-n`/`--name` never coexist: the
  adapter checks `ACT_USER_ARGS` first (AC3, integration tested).
- OpenCode is launched with `--standalone` where supported so no background
  service process is left behind (V0 lesson: background + `wait` was the bug).
- None of the config steps (`terminal.title`, `ui.hideWindowTitle`) are applied
  anywhere yet — they are Phase 2, `--apply`-gated work.

## Shell / platform matrix

| Environment | Project name | Title emission | Wrapper | Status |
| --- | --- | --- | --- | --- |
| WSL bash (this repo) | `basename($PWD)` | `OSC 0` via `act::title::emit` → `ACT_TITLE_SINK` / stdout / `/dev/tty` | `src/run/act-wrap.sh` + `bin/*` | implemented; unit + integration green |
| bash prompt (no CLI) | `basename($PWD)` | same helper, from the rc marker block's `PROMPT_COMMAND` hook | n/a | implemented; sourced-twice PATH/PROMPT guard tested |
| Windows PowerShell | `basename` of `(Get-Location)` (PowerShell equivalent of the WSL rule) | `Host.UI.RawUI.WindowTitle` with `OSC 0` fallback | `Invoke-ActCli` in `src/shell/powershell/Wrappers.ps1` | **written, untested — no `pwsh` on this machine** |
| cmd.exe | — | — | — | out of scope for V1 |

## Windows Terminal notes (from `MicrosoftDocs/terminal`, see `docs/references.md`)

- A profile's `tabTitle` fixes a static label and `suppressApplicationTitle`
  blocks `OSC 0`/`OSC 2` from the shell — our scheme assumes **neither** is set.
- Per-tab isolation (AC5/AC6) follows from `OSC 0` applying to the focused
  pane's tab; this is official behaviour but has **not** been re-verified in a
  real Terminal window as part of this repo yet.
- OSC 9;9 (working directory) and OSC 133 (prompt marks) are documented but
  deliberately out of scope for V1.

## Known gaps (also listed in `docs/v1-scope.md`)

1. OpenCode suppression config path not found yet.
2. Qoder `ui.hideWindowTitle` config step not implemented.
3. PI deferred-re-emit timing not finalized under a PTY test.
4. Real Windows Terminal verification of AC5/AC6/AC8 not done.
5. PowerShell side untested (no `pwsh` installed here).
6. V0 leftovers on this machine (`~/.local/bin/{pi,opencode,...}`, the
   `marvis-ai-cli-tab-title` block in `~/.bashrc`) are reported by
   `scripts/status.sh` but never modified by this project.
