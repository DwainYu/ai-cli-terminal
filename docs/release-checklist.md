# V1 release checklist

Version target: **`0.9.0` (release candidate)** → **`v1.0.0`** when every box
below is ticked. Nothing in this file is automated; boxes are ticked by a
human after the evidence exists.

Last full run: 2026-10-06 — `./scripts/test.sh` → 8 files / 162 assertions,
0 failures.

## Automated

- [x] **automated tests green** — `./scripts/test.sh`: unit 93 assertions
  (`test_adapters` 33, `test_hard_limits` 9, `test_project` 17,
  `test_resolve` 16, `test_title` 18), integration 69 assertions
  (`test_install` 34, `test_migration` 19, `test_wrapper` 16).
- [x] **no broad process kill** — enforced by `tests/unit/test_hard_limits.sh`
  (`pkill`/`killall`/`Stop-Process -Name`/`taskkill` absent from every code
  file; harnesses signal only pids/process groups they started).
- [x] **no background runtime** — `src/run/act-wrap.sh` contains no `&`, no
  `sleep`, no `wait`, no daemon; adapters are foreground-only
  (`test_hard_limits.sh`).
- [x] **OpenCode official strategy** — per-process official config/env
  (D9/D10); no custom plugin, no global OpenCode file ever written.

## Real environment

- [x] **WSL manual green** — `./tests/manual/wsl/validate.sh` → **4/4**
  (PI, OpenCode, CodeBuddy, Qoder in four real projects); results in
  `docs/compatibility.md`.
- [x] **Windows PowerShell green** — `./scripts/test-windows.ps1` → **7/7**
  on Windows PowerShell 5.1 (harness is read-only).
- [ ] **Windows Terminal human verification** — **NOT VERIFIED**.
  Procedure: `tests/manual/windows/README.md` (Tab A/B/C/D: correct
  `<project> · <CLI>` label, tab isolation, title persistence, title
  restore). This is a human verification, not CI — it must be run by hand in
  a real Windows Terminal window. Its step 2 needs an installed wrapper, so
  it follows the first real `--apply` (last item below).
- [x] **migration verified** — `tests/integration/test_migration.sh`: V0 rc
  block byte-identical after V1 install ×2, uninstall restores it
  byte-for-byte, V0 wrappers never modified.
- [x] **uninstall verified** — `tests/integration/test_install.sh`: marker
  block removed, everything outside the markers untouched, idempotent.

## Docs

- [x] **docs updated** — architecture, design decisions, compatibility
  matrix, scope, references.
- [x] **README accurate** — what / why / install / uninstall / supported CLI /
  Windows + WSL / limitations; V0 material labelled as V0/legacy/rejected.
- [x] **working tree clean** — `git status` clean on `main`, `origin` =
  `https://github.com/DwainYu/ai-cli-terminal.git`.

## Release

Order of operations: `--dry-run` review → **user** runs `--apply` → the
four-tab Windows Terminal verification above → tag `v1.0.0`. Nothing else in
this checklist writes to the real machine.

- [ ] **Real `--apply`** — **USER ACTION REQUIRED.**
  Run by hand, on the real machine, after the Windows Terminal check:

  ```bash
  ./scripts/install.sh --dry-run    # review the exact "would modify:" list first
  ./scripts/install.sh --apply      # the only command that writes user files
  ./scripts/status.sh               # rc block present, runtime tree installed
  ```

  Rollback: `./scripts/uninstall.sh --apply` (keeps backups).
- [ ] **Tag `v1.0.0`** once every box above is ticked (only then — not before).

## Not blockers for V1

- Qoder exact plain label `<project> · QODER` (shown as
  `◇ <project> · QODER | Ready`) — optional polish; would need the optional
  `ui.hideWindowTitle` setting in `~/.qoder-cn/settings.json`, which this
  project never writes.
- `pwsh` (PowerShell 7) unavailable in this environment — 5.1 was validated.
- Windows AI CLIs not installed — by design, never installed by this project.
