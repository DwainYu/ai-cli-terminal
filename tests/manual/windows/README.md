# Windows manual validation

> **This is a HUMAN VERIFICATION, not CI.** Nothing in this directory runs
> from `./scripts/test.sh` or `tests/run.sh`, nothing here is automated, and
> no result below is ever simulated. If a check has not been done by a person
> in a real Windows Terminal window, it stays **NOT VERIFIED**.

Status (2026-10-05):

| Item | Status |
| --- | --- |
| PowerShell harness (`scripts/test-windows.ps1`) | **READY — executed, 7/7 PASS** (Windows PowerShell 5.1, run from WSL via `powershell.exe`) |
| Project fixture `D:\ghq\github.com\DwainYu\TFTAutoRecorder` | **PASS** — `Get-ActProjectName` → `TFTAutoRecorder` |
| AI CLIs on Windows | **NOT AVAILABLE** for pi/opencode/codebuddy/qoder — not installed, and this harness never installs them |
| Real Windows Terminal 4-tab check (AC5/AC6/AC8) | **NOT VERIFIED** — procedure below |

## Running the harness on a real Windows machine

From a checkout on a Windows disk:

```powershell
cd <checkout>
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-windows.ps1
# or, with PowerShell 7:
pwsh -File .\scripts\test-windows.ps1
```

From WSL (what was executed for this record):

```bash
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
  -NoProfile -ExecutionPolicy Bypass \
  -File '\\wsl.localhost\<distro>\<checkout>\scripts\test-windows.ps1'
```

Expected: `1..7` / `# PASS 7`, exit code 0, followed by four
`NOT AVAILABLE` availability notes. The harness is read-only: no install, no
`settings.json` edit, no AI CLI installation; the only side effect is a
window-title round trip that restores the original title.

## Four-tab Windows Terminal procedure (AC-P2-07)

Run this **by hand**, in a real Windows Terminal window, watched by a human.
It is human verification — not a CI job, not a test-suite layer, and it must
not be automated. Default profile settings
only — `tabTitle` and `suppressApplicationTitle` must stay unset (see
`docs/references.md`), otherwise `OSC 0` never reaches the tab label.

Verify exactly five things: **project + CLI title**, **tab isolation**,
**title persistence**, **title restore**, and a working shell afterwards.

1. Open Windows Terminal with four tabs; in **each** tab enter WSL:
   `wsl` (or set the WSL profile as default).
2. Install once for the machine — this is the **USER ACTION REQUIRED**
   `--apply` (see `docs/release-checklist.md`): review
   `./scripts/install.sh --dry-run`, then run `./scripts/install.sh --apply`
   once. Opening a **new** tab afterwards loads the block; do not re-run it
   in every tab (a second run would just report `unchanged`).
3. Start one pair per tab:

   | Tab | command | expected tab title |
   | --- | --- | --- |
   | A | `cd ~/projects/agent-toolbox && pi` | `agent-toolbox · PI` |
   | B | `cd ~/projects/tft-training-log && opencode` | `tft-training-log · OPENCODE` |
   | C | `cd ~/projects/hengguang-ai-platform-demo && codebuddy` | `hengguang-ai-platform-demo · CODEBUDDY` |
   | D | `cd ~/projects/md-content-publisher && qoder` | `md-content-publisher · QODER` |

4. Record, for each pair:
   - [ ] the tab label shows `<project> · <CLI>` while the TUI runs (AC1-AC4),
   - [ ] switching tabs does **not** change any other tab's label (AC5, AC6),
   - [ ] `pwd` inside each tab matches that tab's project (cwd isolation),
   - [ ] after exiting the CLI (`Ctrl+C` / exit), the tab returns to the
         project-only title and the shell prompt still works (AC8),
   - [ ] the label stays stable during normal TUI use (typing, streaming).
5. Windows-side checks that WSL cannot prove:
   - CodeBuddy's empty `OSC 0` is fully suppressed (harness: zero writes —
     confirm the tab never blanks),
   - Qoder's decorated `◇ <project> · QODER | Ready` label vs the exact
     `<project> · QODER` — the decorated label **passes** this procedure; the
     exact plain label is optional polish only (optional
     `ui.hideWindowTitle` in `~/.qoder-cn/settings.json`, never written by
     this project, see `docs/compatibility.md`).

Nothing in this procedure may be automated by the test suite: it starts real
TUIs and needs a human watching real tabs.
