# V1 scope

## In scope

1. A title primitive that writes `OSC 0` safely (ASCII, Chinese, spaces,
   special characters, unicode paths).
2. A project name resolver: `basename` of the current directory, for WSL/bash
   and for Windows paths.
3. A CLI adapter interface with four adapters: **PI**, **OpenCode**,
   **CodeBuddy**, **Qoder** (including the `qoder-cn` entry name).
4. A wrapper runtime that emits the title, runs the real CLI in the foreground
   with arguments forwarded verbatim, restores the title on exit, and returns
   the CLI's exit status.
5. `install` (`--dry-run` default, `--apply` explicit), `uninstall`, `status`,
   all idempotent, marker based, backed up.
6. Layered tests: unit → integration (fake CLIs, temp `HOME`) → terminal/manual
   (recorded, not automated).
7. PowerShell adapter infrastructure (compiles and is reviewable; activation
   is per machine, per CLI).

## Out of scope — V1

```text
git remote / git root detection
package.json, pyproject.toml, solution detection
workspace registry, project database
GUI, dashboard, sidebar, session database, agent monitor
terminal emulator, tmux, Zellij, Orca, Tabby, WezTerm
shell theme framework
Windows Terminal settings.json editing (warn-only in status)
background launch + fixed sleep + polling + title daemon
per-project Windows Terminal profiles
OSC 9;9 directory restoration, OSC 133 shell integration marks
installing any AI CLI that is missing on a machine
```

## Acceptance criteria

| AC | Statement | How V1 approaches it | State |
| --- | --- | --- | --- |
| AC1 | `cd project; pi` → `project · PI` | PI extension (`-e`) writes the title; PI's own title is emitted after `session_start`, so a deferred re-emit is used | implemented, probe-verified mechanism, not yet verified end to end |
| AC2 | `cd project; opencode` → `project · OPENCODE` | wrapper title + TUI config `terminal.title: false` | implemented; config step not applied anywhere yet |
| AC3 | `cd project; codebuddy` → `project · CODEBUDDY` | `CODEBUDDY_CODE_DISABLE_TERMINAL_TITLE=1` + wrapper title | implemented; verified by probe |
| AC4 | `cd project; qoder` → `project · QODER` | wrapper title + `-n` injection; exact label additionally needs `ui.hideWindowTitle` | partially implemented; config step pending |
| AC5 | Two projects at once, different titles | titles are per tab, computed per wrapper invocation | expected by construction; needs real Terminal check |
| AC6 | One tab's title change does not affect others | `OSC 0` is per pane; Windows Terminal binds the tab title to the focused pane | official docs; needs real Terminal check |
| AC7 | CLI arguments forwarded verbatim | `"$@"` plus adapter extras only where the adapter is allowed to add them | implemented, unit + integration tested |
| AC8 | Title restored after the CLI exits | wrapper survives the child and emits the project name in its exit path | implemented, integration tested (fake CLI) |
| AC9 | Repeated install causes no PATH/config duplication | marker block replaced as a whole + `case` guarded PATH prepend | implemented, integration tested against temp `HOME` |
| AC10 | `uninstall` removes what was written and restores the user's file | marker block deleted, backups kept, everything else untouched | implemented, integration tested |
| AC11 | Default development/testing never modifies the real environment | dry-run default, `HOME` overridden in tests, no `--apply` anywhere | enforced; verified by review of what tests touch |
| AC12 | Windows project is not forced through WSL | no cross-boundary launcher exists; PowerShell side is optional per CLI | by construction |

## Test layers

```text
unit            title formatting/sanitizing, project name (WSL + Windows paths,
                unicode, spaces), adapter metadata, argument forwarding rules,
                real-CLI resolution (self, wrapper, override)
integration     wrapper ↔ fake CLI: emitted bytes, exit codes, restore,
                -n respect; install/uninstall/status against a temp HOME,
                run three times in a row (AC9)
terminal        real OSC 0 in Windows Terminal, per-tab isolation (AC5/AC6)
manual          behaviour of the four real CLIs, recorded in compatibility.md
```

Unit and integration tests must be fast and deterministic and must never start
a real TUI. Terminal and manual checks are recorded, not automated.

## Phases

```text
Phase 1  (this commit series)
  repository, reference analysis, architecture, design decisions,
  title + project primitives, adapter interface, wrapper runtime,
  install/uninstall/status with dry-run default, layered tests

Phase 2  (after V1 passes in isolation, on explicit request)
  ./scripts/install.sh --dry-run   → prints the exact list of files it would touch
  ./scripts/install.sh --apply     → the only way ~/.bashrc, ~/.local/bin, … change
  per-CLI suppression config (OpenCode terminal.title, Qoder ui.hideWindowTitle)
  real Windows Terminal verification of AC5, AC6, AC8
  finalize PI extension timing with a PTY test

Later / never?
  PowerShell apply path, if a machine actually needs it
```

## Definition of "done" for Phase 1

- Repository exists locally and on GitHub with this documentation.
- Unit + integration suites pass from a clean checkout with no user-file writes.
- Every strategy claim in `docs/compatibility.md` is either probe-verified or
  explicitly marked *pending verification*.
- No `--apply` has been run on any machine.

## Phase 2 acceptance criteria (status 2026-10-05)

| AC | Claim | Status |
| --- | --- | --- |
| AC-P2-01 | OpenCode official title suppression investigated | **DONE** — docs (`cli.mdx`, `cli/config`), upstream source (`flag.ts`, `app.tsx`), local binary (`strings`); see D9 |
| AC-P2-02 | OpenCode per-process suppression tested | **PASS** — PTY matrix: flag `1`/`true` FAIL on v2.0.23, `OPENCODE_CLI_CONFIG_CONTENT` **zero writes**; wrapper end-to-end PASS |
| AC-P2-03 | No custom plugin required if official mechanism works | **DONE** — no plugin in V1; V0 plugin marked obsolete (migration = report only) |
| AC-P2-04 | PI / Qoder / CodeBuddy strategy documented individually | **DONE** — `docs/compatibility.md` table + D8 rows, each with probe evidence |
| AC-P2-05 | PowerShell manual test harness exists | **PASS** — `scripts/test-windows.ps1` executed on real Windows PowerShell 5.1: 7/7 |
| AC-P2-06 | WSL real-machine verification documented | **PASS** — `tests/manual/wsl/validate.sh` 4/4 + results in `docs/compatibility.md` |
| AC-P2-07 | Windows real-machine verification procedure documented | **DONE** — `tests/manual/windows/README.md` (4-tab procedure; real run NOT VERIFIED) |
| AC-P2-08 | No broad process killing in tests | **ENFORCED** — `tests/unit/test_hard_limits.sh`; harnesses kill only their own process group / exact pids |
| AC-P2-09 | All automated tests remain green | **PASS** — 8 test files, 0 failures (manual layers excluded by design) |
| AC-P2-10 | No real user environment modified | **NO** — no real `--apply`, temp `HOME` everywhere, probe results recorded |
