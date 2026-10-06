# ai-cli-terminal

Project-aware AI CLI tab titles for **Windows Terminal + WSL/Windows**.

```text
current project directory
        +
current AI CLI
        ↓
Windows Terminal tab
        ↓
<project-name> · <CLI-name>
```

Examples:

```text
tft-training-log · PI
tft-training-log · OPENCODE
hengguang-ai-platform-demo · CODEBUDDY
agent-toolbox · QODER
TFTAutoRecorder · PI
```

One question only: **which project directory am I in, which AI CLI did I start,
and can the Windows Terminal tab bar tell me right now?**

## 目标 (Goal)

```text
Project-aware AI CLI tab titles
```

The tab title is the whole UI of this project. Nothing is rendered by us; the
title is written as an `OSC 0` sequence into the existing terminal.

## 非目标 (Non-goals)

```text
Not a terminal emulator
Not a terminal replacement
Not an AI agent manager
Not an agent orchestration system
Not Orca
Not tmux
Not Zellij
Not a project manager
Not a shell theme framework
Not a replacement for Windows Terminal
```

## Status

**Phase 3 — V1 Release Candidate, both human gates complete.** Automated and
recorded manual layers are green; the real machine was modified exactly once,
by `./scripts/install.sh --apply` on **2026-10-06** (marker block + runtime
tree, timestamped backup kept, `uninstall.sh --apply` reverts it).

Version: `0.9.0` — release candidate. The two human items in
[`docs/release-checklist.md`](docs/release-checklist.md) are done (the first
real `--apply`, the four-tab Windows Terminal verification); `v1.0.0` is
tagged by hand, only after that checklist is committed with every box ticked.

| Area | State |
| --- | --- |
| Repository, docs, architecture | done |
| Title primitive (`OSC 0`) | implemented, unit tested |
| Project name resolver (WSL + Windows paths) | implemented, unit tested |
| CLI adapter interface + 4 adapters | implemented, unit tested |
| Wrapper runtime (`title → real CLI → restore`) | implemented, integration tested with fake CLIs |
| OpenCode title suppression (official per-process env) | implemented, probe-verified (D9); no plugin involved |
| `install --dry-run / --apply`, `uninstall`, `status` | implemented, integration tested against a temp `HOME` (+ V0 migration coverage) |
| Automated suite | **PASS — 8 files / 162 assertions, 0 failures** (`./scripts/test.sh`) |
| PowerShell side | harness `scripts/test-windows.ps1` **PASS 7/7** on Windows PowerShell 5.1; `Invoke-ActCli` untested (no AI CLI on Windows) |
| Real-environment WSL validation (4 real projects × 4 real CLIs) | **PASS 4/4** — manual layer, `tests/manual/wsl/` |
| Real `~/.bashrc` apply (2026-10-06) | **done once** — marker block + 21-file runtime tree, backup `~/.bashrc.bak-20261006171409`, byte-identical outside the markers, second run `unchanged`; `settings.json` still never written |
| Real Windows Terminal verification | **PASS 7/7** (2026-10-06, by hand, four tabs) — record in `tests/manual/windows/README.md`; one documented PI cold-start title race |

See [`docs/v1-scope.md`](docs/v1-scope.md) for the acceptance criteria and what
is deliberately left out.

## How it works (short version)

```text
shell (bash / PowerShell)
    → wrapper entry            bin/pi, bin/opencode, bin/codebuddy, bin/qoder
    → project resolver         basename of the current working directory
    → CLI adapter              strategy + argument forwarding + env for one CLI
    → title helper             one thin function that writes OSC 0
    → real CLI (foreground)
    → title restore on exit
```

Nothing in this project forks a background process, sleeps and waits for the
CLI to start, or polls for title ownership. See
[`docs/design-decisions.md`](docs/design-decisions.md) for why.

## Supported CLI

| CLI | wrapper entry | title strategy (why this one) | status |
| --- | --- | --- | --- |
| **PI** | `pi` | project-owned extension via `-e` + one deferred re-emit — PI exposes no title-disable flag | probe + real-project verified |
| **OpenCode** | `opencode` | official per-process config/env suppression (`OPENCODE_CLI_CONFIG_CONTENT`, forward-compat flag) — no plugin, no global config written | probe-verified, official docs + upstream source |
| **CodeBuddy** | `codebuddy` (alias `cbc`) | official env switch `CODEBUDDY_CODE_DISABLE_TERMINAL_TITLE=1` — the CLI's own `TerminalTitleUpdater` reads it | probe-verified |
| **Qoder** | `qoder`, `qoder-cn` | official `-n/--name` argument, injected only when the user did not name the session | probe-verified |

Each adapter keeps its own strategy on purpose — see
[`docs/compatibility.md`](docs/compatibility.md) for the per-CLI evidence.

## Layout

```text
src/
├── lib/            title, project name, adapter registry, real-CLI resolution
├── cli/            one *.adapter per CLI + project-owned PI extension
├── run/            wrapper entry point (invoked through bin/<cli> symlink)
└── shell/
    ├── bash/       the marker block that install.sh writes into ~/.bashrc
    └── powershell/ Windows-side resolver, title writer, wrapper functions
scripts/            install.sh, uninstall.sh, status.sh, test.sh, test-windows.ps1
tests/              harness, unit, integration, fixtures (temp HOME only)
                    + manual layers: tests/manual/wsl, tests/manual/windows
docs/               architecture, design decisions, references, scope, compatibility
```

## Install / Uninstall

```bash
./scripts/install.sh            # dry run (default): prints "would modify:" lines
./scripts/install.sh --apply    # the only way user files are ever touched
./scripts/status.sh             # read-only state report
./scripts/uninstall.sh          # dry run
./scripts/uninstall.sh --apply  # removes exactly what install wrote
./scripts/test.sh               # unit + integration (temp HOME, no real TUI)
```

`--apply` writes exactly two things, nothing else ever:

1. the marker block in the shell rc (default `~/.bashrc`),
2. the runtime tree in `~/.local/share/ai-cli-terminal`.

Both are idempotent (a second run reports `unchanged`) and backed up
(`.bak-<timestamp>`) before any modification. Uninstall drops the marker
block, keeps backups, and never touches files this project did not write
(V0 `~/.local/bin/*` leftovers are reported, never modified).

Until `--apply` is run explicitly, this project changes **nothing** outside its
own repository directory.

Manual validation layers (never part of `./scripts/test.sh` — they start real
TUIs or target a real Windows machine; the Windows tab check is a **human
verification, not CI**):

```bash
./tests/manual/wsl/validate.sh             # WSL: real CLIs in real projects
```

```powershell
.\scripts\test-windows.ps1                 # Windows: harness + fixture check
```

## Limitations (V1)

```text
PI cold-start title race              intermittent: PI's own "π - <project>" can hold the tab at idle
                                      until the first turn re-emits <project> · PI (non-blocker, documented)
Long project name                     cut off by the Windows Terminal tab width; hover shows the full label
Per-CLI colour or icon                out of scope — V1's UI is the tab title text only
Qoder exact plain label               optional polish only: shows ◇ <project> · QODER | Ready
                                      unless ui.hideWindowTitle is set in ~/.qoder-cn/settings.json
                                      (never written by this project)
Windows AI CLIs                       pi/opencode/codebuddy/qoder NOT AVAILABLE — never installed here
PowerShell 7 (pwsh)                   not available in this environment; harness ran on 5.1
V0 (marvis) leftovers                 retired by hand 2026-10-06 → ~/.local/share/ai-cli-terminal-v0-retired/
                                      (moved, not deleted; the rc marker block stays, status.sh reports it)
No background process, no daemon,
no polling, no sleep, no broad kill   enforced by tests/unit/test_hard_limits.sh
```

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — components and data flow
- [`docs/design-decisions.md`](docs/design-decisions.md) — decisions, including V0 failure lessons
- [`docs/references.md`](docs/references.md) — what was learned from the three reference projects
- [`docs/v1-scope.md`](docs/v1-scope.md) — scope, acceptance criteria, test layers
- [`docs/compatibility.md`](docs/compatibility.md) — Windows Terminal settings facts + per-CLI strategy matrix
- [`docs/release-checklist.md`](docs/release-checklist.md) — V1 release gates and what still needs a human

## License

[MIT](LICENSE)
