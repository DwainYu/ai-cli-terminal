# V1 release checklist

Version target: **`0.9.0` (release candidate)** → **`v1.0.0`** when every box
below is ticked. Nothing in this file is automated; boxes are ticked by a
human after the evidence exists.

Last full run: 2026-10-06 — `./scripts/test.sh` → 8 files / 162 assertions,
0 failures.

Final acceptance run: **2026-10-06** — real `--apply` + migration + four-tab
Windows Terminal verification (evidence in the two boxes below). Only the tag
item remains.

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
- [x] **Windows Terminal human verification** — **PASS 7/7, by hand on
  2026-10-06** in a real Windows Terminal window (four WSL tabs, procedure
  `tests/manual/windows/README.md`, results recorded there): label
  `<project> · <CLI>` for all four pairs (AC1–AC4), tab isolation (AC5/AC6),
  four distinct `pwd` (cwd isolation), title restore + working prompt after
  exit (AC8), stable label while typing and streaming, CodeBuddy's empty
  `OSC 0` never blanks the tab, Qoder's decorated `◇ … | Ready` accepted per
  the procedure. Every tab resolved the **V1** wrapper
  (`command -v <cli>` → `~/.local/share/ai-cli-terminal/bin/<cli>`;
  `ACT_DEBUG=1` → adapter/strategy/real + `-e pi-title.ts`). One deviation
  observed and recorded under *Not blockers*: the PI cold-start title race.
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

- [x] **Real `--apply`** — run on the real machine **2026-10-06** (by the
  release acceptance assistant, on the user's explicit go-ahead), in the
  documented order (dry-run reviewed → `--apply` → four-tab verification):

  ```text
  install.sh --apply   backup: ~/.bashrc.bak-20261006171409 (sha256 = pre-apply copy)
                       marker block 186–219, exactly one pair; runtime tree 21 files
  outside the markers  byte-identical to the pre-apply copy (cmp → IDENTICAL)
  second --apply       unchanged: /home/user/.bashrc           (AC9)
  status.sh            rc block present, runtime tree installed
  uninstall.sh (dry)   would modify ~/.bashrc, would remove the tree; 0 files written (AC10)
  ```

  Rollback: `./scripts/uninstall.sh --apply` (keeps backups).

  The same day the machine's manual V0 migration was completed, because
  Windows Terminal's `wsl.exe` starts a **login** shell and `~/.profile`
  prepends `~/.local/bin` *after* sourcing `~/.bashrc`: before the migration
  the V0 wrappers there outranked the V1 bin directory. The five V0 wrappers
  were moved to `~/.local/share/ai-cli-terminal-v0-retired/` (retired, not
  deleted) and the single `alias qoder-cn` line was retargeted; `~/.profile`
  itself was left untouched.
- [ ] **Tag `v1.0.0`** once every box above is ticked (only then — not before).

## Not blockers for V1

- Qoder exact plain label `<project> · QODER` (shown as
  `◇ <project> · QODER | Ready`) — optional polish; would need the optional
  `ui.hideWindowTitle` setting in `~/.qoder-cn/settings.json`, which this
  project never writes.
- `pwsh` (PowerShell 7) unavailable in this environment — 5.1 was validated.
- Windows AI CLIs not installed — by design, never installed by this project.
- **PI cold-start title race** (observed 2026-10-06, accepted as a documented
  deviation): the wrapper's single 400 ms deferred re-emit
  (`src/cli/pi-title.ts`) won in **2/2 instrumented runs** — timeline
  `wrapper → session_start emit → PI's own π - <project> (same batch) →
  deferred re-emit` — and in the repeated Windows Terminal run, but one real
  run showed PI's own `π - <project>` at idle, i.e. PI wrote later than
  +400 ms. Self-healing: the first turn's events re-emit the standard
  `<project> · PI` and the label does not flip back (verified by hand). AC1
  keeps `<project> · PI` as the contract; no second timer was added, because
  that would change the "exactly one timer in the project" invariant in
  `docs/design-decisions.md` and require re-running both human gates.
- `tests/manual/wsl/validate.py` asserts only the **first** OSC 0, so it cannot
  detect a later override by the CLI — this acceptance round caught exactly
  that by hand. Teaching the harness to assert the *last* title is future work.
- Long project names are cut off by the Windows Terminal tab width, which can
  hide the `· <CLI>` suffix (e.g. Tab C); the full label is visible on tab
  hover. Readability only — AC1–AC4 judge the label content, not how much of
  it the tab bar can draw.
- No per-CLI colour or icon beyond the text label (Qoder's `◇` comes from the
  CLI itself): V1's scope is the tab title only, so colouring would mean OSC 11
  / tab colour and is deliberately out of scope.
