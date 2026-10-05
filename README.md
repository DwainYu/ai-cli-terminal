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

**Phase 1 (design + skeleton + primitives). Not applied to any machine.**

| Area | State |
| --- | --- |
| Repository, docs, architecture | done |
| Title primitive (`OSC 0`) | implemented, unit tested |
| Project name resolver (WSL + Windows paths) | implemented, unit tested |
| CLI adapter interface + 4 adapters | implemented, unit tested |
| Wrapper runtime (`title → real CLI → restore`) | implemented, integration tested with fake CLIs |
| OpenCode title suppression (official per-process env) | implemented, probe-verified (D9) |
| `install --dry-run / --apply`, `uninstall`, `status` | implemented, integration tested against a temp `HOME` (+ V0 migration coverage) |
| PowerShell side | harness `scripts/test-windows.ps1` **PASS 7/7** on Windows PowerShell 5.1; `Invoke-ActCli` untested (no AI CLI on Windows) |
| Real-environment WSL validation (4 real projects × 4 real CLIs) | **PASS 4/4** — manual layer, `tests/manual/wsl/` |
| Real `~/.bashrc` / `~/.profile` / `settings.json` apply | **not done, never run here** |
| Real Windows Terminal verification | **not done** (procedure in `tests/manual/windows/`) |

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

## Usage (once V1 passes in isolation)

```bash
./scripts/install.sh            # dry run (default): prints what would change
./scripts/install.sh --apply    # the only way user files are ever touched
./scripts/status.sh
./scripts/uninstall.sh
./scripts/test.sh
```

Until `--apply` is run explicitly, this project changes **nothing** outside its
own repository directory.

Manual validation layers (never part of `./scripts/test.sh` — they start real
TUIs or target a real Windows machine):

```bash
./tests/manual/wsl/validate.sh             # WSL: real CLIs in real projects
```

```powershell
.\scripts\test-windows.ps1                 # Windows: harness + fixture check
```

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — components and data flow
- [`docs/design-decisions.md`](docs/design-decisions.md) — decisions, including V0 failure lessons
- [`docs/references.md`](docs/references.md) — what was learned from the three reference projects
- [`docs/v1-scope.md`](docs/v1-scope.md) — scope, acceptance criteria, test layers
- [`docs/compatibility.md`](docs/compatibility.md) — Windows Terminal settings facts + per-CLI strategy matrix

## License

[MIT](LICENSE)
