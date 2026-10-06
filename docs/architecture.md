# Architecture

## 1. The model

```text
Terminal
    ↓
Current environment
    ├── Windows / PowerShell
    └── WSL / Bash
            ↓
Current working directory
            ↓
Project name            = basename($PWD)
            ↓
CLI wrapper / adapter    = one adapter per AI CLI
            ↓
CLI name                 = PI / OPENCODE / CODEBUDDY / QODER
            ↓
Dynamic terminal title   = "<project-name> · <CLI-name>" via OSC 0
            ↓
Windows Terminal tab label
```

The title string is deliberately one line of arithmetic:

```bash
projectName = basename(currentWorkingDirectory)
title       = projectName + " · " + cliName
```

No git remote, no git root, no `package.json`, no workspace registry, no
project database. If the directory is `/home/user/projects/tft-training-log`,
the project name is `tft-training-log`.

## 2. Runtime flow

```text
user types:  pi
     ↓
interactive bash resolves `pi` → <repo>/bin/pi  (PATH entry, marker guarded)
     ↓
bin/pi is a symlink → src/run/act-wrap.sh
     ↓
act-wrap.sh
  1. adapter id      = basename($0)                 [src/lib/adapter.sh]
  2. project name    = basename($PWD)               [src/lib/project.sh]
  3. title           = "<project> · <display>"      [src/lib/title.sh]
  4. real CLI        = first non-wrapper match on PATH, overridable
                                                       [src/lib/resolve.sh]
  5. adapter prepare = env / extra arguments         [src/cli/*.adapter]
  6. emit title      = OSC 0 to the controlling tty  [src/lib/title.sh]
  7. run real CLI    = foreground child, "$@" forwarded verbatim
  8. restore title   = OSC 0 with the project name, on exit
  9. exit            = the child's exit status
```

Step 7 is intentionally **foreground**. There is no `&`, no `sleep`, no
`wait`, no daemon, no polling loop. The wrapper is an ordinary shell script
whose child owns the terminal, exactly like `bash -c vim`.

### Why foreground + exit-trap instead of `exec`

`exec` would be the cheapest wrapper, but two acceptance criteria need code to
run *after* the CLI exits:

- **AC7** argument forwarding works with `exec`, but
- **AC8** *title restore after exit* does not: with `exec` the wrapper is gone.

Several CLIs actively clear or overwrite the title as they leave (observed for
Qoder: `OSC 0` with an empty payload on `process.on("exit")`, and OpenCode:
`setTerminalTitle("")` when its TUI terminal is destroyed). A wrapper that
survives the child can always write the restore title *after* those writes.

Signals: the wrapper and its child share one process group, so `Ctrl+C`
reaches the child the way it always does. `INT` is deliberately **not**
trapped or ignored — the real CLI receives it unchanged; when the child dies
from it, the wrapper continues to its `EXIT` trap and restores the title.
`TERM`/`HUP` are mapped to `143`/`129` so the same `EXIT` path runs.

## 3. Components

### 3.1 `src/lib/title.sh` — title primitive

The only place in the project that knows what an `OSC 0` sequence looks like.

| Function | Purpose |
| --- | --- |
| `act::title::sanitize` | removes `ESC`, `BEL`, `NUL`, `CR`, `LF`, `TAB` from a title, keeps UTF-8 |
| `act::title::format` | `"<project> · <cli>"`, both sides sanitized |
| `act::title::emit` | writes `ESC ] 0 ; <title> BEL` |

Emission target, in order:

1. `ACT_TITLE_SINK` — append raw bytes to a file (test hook, also usable for debugging),
2. `/dev/tty` — the controlling terminal, so a redirected `stdout` is never polluted,
3. `stdout` — last resort (no tty at all).

Keeping this thin and centralized is what makes ASCII / Chinese / spaces /
path-unicode testable in one place.

### 3.2 `src/lib/project.sh` — project name resolver

`act::project::name [dir]`:

- default input is `$PWD`,
- trailing slashes are stripped, `/` stays `/`,
- if the value looks like a Windows path (contains `\` and no `/`), it is split
  on `\` as well, so the same function answers for
  `D:\ghq\github.com\DwainYu\TFTAutoRecorder` → `TFTAutoRecorder`.

The PowerShell side has its own resolver
(`src/shell/powershell/Project.ps1`, `Split-Path -Leaf` semantics) because the
two shells should not have to share a parser.

### 3.3 `src/lib/adapter.sh` — adapter registry

An adapter is one sourceable file, `src/cli/<id>.adapter`, that declares:

```text
ACT_ADAPTER_ID          pi | opencode | codebuddy | qoder
ACT_ADAPTER_ALIASES     extra wrapper entry names (e.g. qoder-cn)
ACT_ADAPTER_DISPLAY     PI | OPENCODE | CODEBUDDY | QODER
ACT_ADAPTER_BINS        candidate real command names, in resolution order
ACT_ADAPTER_STRATEGY    see the strategy table below
ACT_ADAPTER_REAL_ENV    optional explicit override, e.g. ACT_REAL_PI
act::adapter::prepare   optional: export environment for the child
act::adapter::args      optional: append extra arguments (respecting user args)
act::adapter::after     optional: runs after the child exits
```

The wrapper contains no CLI-specific knowledge. Adding a fifth CLI means adding
one file.

### 3.4 `src/lib/resolve.sh` — real CLI resolution

The wrapper must never resolve to itself, and V1 must not resolve to the V0
experimental wrappers either. The resolver walks `PATH` and skips a candidate
when:

1. it is the running wrapper itself,
2. it lives in this project's `bin/` directory,
3. its first lines contain a known wrapper marker
   (`ai-cli-terminal wrapper` or the V0 `marvis dynamic tab-title wrapper`),
4. it is not executable.

Explicit override always wins: `ACT_REAL_PI`, `ACT_REAL_OPENCODE`,
`ACT_REAL_CODEBUDDY`, `ACT_REAL_QODER`. Adapters may also declare fallback
absolute paths for CLIs that are not reachable through `PATH` (Qoder's entry
script on this machine).

The original CLI is never modified, renamed or replaced. Wrappers are entries
in this project's own `bin/` directory only.

### 3.5 `src/run/act-wrap.sh` — the wrapper runtime

Single entry point, invoked through `bin/<cli>` symlinks. Responsibilities are
exactly the nine steps in section 2, nothing else.

### 3.6 `src/shell/bash/act-init.sh` — the shell block

Content that `scripts/install.sh --apply` writes between markers in
`~/.bashrc`:

```bash
# >>> ai-cli-terminal >>>
... PATH prepend (guarded, at most one occurrence) ...
... prompt title hook (project name while no CLI owns the title) ...
# <<< ai-cli-terminal <<<
```

Guarantees:

- the block is replaced as a whole on every run, never appended twice,
- the `PATH` line uses a `case ":$PATH:"` guard, so even if the block were
  sourced many times, `~/.local/share/.../bin` appears at most once,
- everything outside the markers is untouched.

### 3.7 `src/shell/powershell/` — Windows side

`Project.ps1` (project name), `Title.ps1` (OSC 0 writer), `Wrappers.ps1`
(function-per-CLI wrappers that are only defined when `Get-Command` finds the
real CLI). Windows support means *infrastructure that activates per machine*,
never "Windows ships with all AI CLIs".

## 4. Isolation rules

| Rule | Enforcement |
| --- | --- |
| Development and tests never touch the real user environment | tests set `HOME` to a temp dir; `install.sh` defaults to dry run |
| `--apply` is the only code path that writes user files — and it writes exactly two things: the rc marker block (default `~/.bashrc`) and the runtime tree under `~/.local/share/ai-cli-terminal` | `scripts/install.sh` header + `src/lib/install.sh`; nothing else is ever opened for writing (`~/.local/bin`, `~/.config/opencode`, `~/.qoder-cn`, `settings.json` are **never** written — see D10) |
| All modifications are `backup + marker + idempotent + minimal diff` | section 3.6, plus timestamped `.bak-` copies created only when content changes |
| Tests manage only processes they start | no `pkill`, no broad process killing anywhere in this repository |

## 5. Test architecture

```text
tests/
├── run.sh              harness (no external dependencies)
├── unit/               pure functions: title, project name, adapters, resolver,
│                       hard limits (no broad kill, no background runtime)
├── integration/        wrapper against fake CLIs, install/uninstall against temp HOME,
│                       V0 migration coexistence
├── fixtures/           fake CLIs and a V0-era rc fixture
└── manual/             never run by the suite: wsl/ (real CLIs, real projects)
                        and windows/ (PowerShell harness + real Terminal procedure)
```

- **unit** — fast, deterministic, no processes, no tty.
- **integration** — spawns only fake CLIs from `fixtures/`; captures emitted
  bytes through `ACT_TITLE_SINK`; uses a temporary `HOME`.
- **manual** — real `OSC 0` behaviour of Windows Terminal and the four real
  CLIs. Recorded in `docs/compatibility.md`, never run from `tests/run.sh`,
  never run in CI, never run in the background. The Windows tab procedure is
  a **human verification**, not a test (see `tests/manual/windows/README.md`).
