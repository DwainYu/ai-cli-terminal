# Design decisions

Every decision below states the reason, and where a decision rests on an
observation from the V0 experiment or from a live probe on one machine, that
is said explicitly. Nothing here is claimed as a general law of terminals.

Probes referenced in this document were run on **2026-10-05**, on
`WSL2 / Ubuntu 22.04.5`, with a throwaway `HOME`, spawning each CLI directly
(no wrapper, no shell rc) inside a pty, killing only the child pid the probe
itself started. Versions: `pi 1.0.3`, `opencode v2.0.23`,
`codebuddy 2.161.3`, `qoder/qoderclicn 1.1.65`.

---

## D1. Project + CLI is the context, not a profile

**Decision:** the title is `<basename($PWD)> · <CLI display name>`, computed at
runtime.

**Why:** a fixed Windows Terminal profile cannot express "which project am I
in" — a profile knows one directory at best, and V0 had to create one profile
per project. That approach was removed. The tab title must be derived from the
state of the shell, so the terminal stays configuration-free.

## D2. Fixed Windows Terminal profiles are the wrong abstraction

**Decision:** no profile is created, edited, or shipped.

**Reason (V0 lesson):** profiles tie a title to a launch configuration instead
of to a working directory; every new project means new terminal configuration,
and configuration drifts.

## D3. `suppressApplicationTitle` must stay off

**Decision:** this project never sets `suppressApplicationTitle: true` and
never edits Windows Terminal `settings.json` at all. V1 does not even read
the file: the requirement that it stay unset is documented
(`docs/compatibility.md`) and checked by hand in the Windows Terminal
procedure (`tests/manual/windows/README.md`), not by a warning in code.

**Reason:** with `suppressApplicationTitle: true`, Windows Terminal ignores
title-change messages from the application and shows `tabTitle` (or `name`).
The whole mechanism of this project — writing `OSC 0` from the shell — stops
working. Official wording (MicrosoftDocs/terminal, *Advanced Profile Settings*):
"any title change messages from the application will be suppressed".
See `docs/compatibility.md` for the citation and the per-setting breakdown.

## D4. `exec` cannot be the whole answer

**Decision:** the wrapper runs the real CLI as a foreground child and restores
the title after it exits.

**Reason (V0 lesson + code reading):** `exec` replaces the wrapper, so nothing
runs after the CLI exits, and AC8 (title restore) becomes impossible. Two of
the four CLIs clear the title themselves on exit (Qoder writes an empty
`OSC 0` in `process.on("exit")`; OpenCode calls `setTerminalTitle("")` when its
TUI terminal is destroyed), so a restore that runs *before* the CLI's own exit
write would be pointless.

## D5. No `background + sleep + wait`

**Decision:** forbidden as a default strategy. The wrapper uses neither `&`,
nor `sleep`, nor `wait`, nor a title daemon, nor polling.

**Reason (V0 lesson):** V0 used

```text
printf title → background real CLI → sleep 3 → printf title → wait
```

and on this machine PI and Qoder produced suspiciously sparse TUI output under
that harness, while OpenCode keeps background service processes, which makes
`wait` semantics unclear. Separating "the CLI runs" from "the terminal is
ours" was the expensive part of V0; V1 never puts the CLI in the background.

An in-process, one-shot delay inside a CLI-owned plugin is a different
situation (no second process, no `wait`, no terminal ownership change) and is
used only where a probe showed it is unavoidable — see D8.

## D6. PATH injection must be idempotent

**Decision:** the installed block prepends the wrapper directory with a `case`
guard and is written between markers, so repeated `install --apply` runs leave
exactly one occurrence.

```bash
case ":$PATH:" in
  *":$ACT_HOME/bin:"*) ;;
  *) PATH="$ACT_HOME/bin:$PATH" ;;
esac
```

**Reason (V0 lesson):** `~/.bashrc` on this machine grew repeated
`export PATH="$HOME/.local/bin:$PATH"` lines as the source chain
(`~/.profile` → `~/.bashrc`, plus re-sourcing) ran more often, and the directory
drifted forward on every source. Unconditional prepending is the bug; a
membership guard is the fix. `~/.profile` and `~/.bashrc` load behaviour is
documented in `docs/compatibility.md` rather than guessed.

## D7. One title helper, one marker, one install path

**Decision:** `printf '\033]0;%s\a'` exists in exactly one function
(`act::title::emit`). All user-file edits go through one installer with
`backup + marker + idempotent + minimal diff`.

**Reason:** V0 had the escape sequence copied into every wrapper, and edits
spread over several files. Centralizing the sequence is also what makes
ASCII / Chinese / space / special-character tests meaningful.

## D8. Per-CLI title strategy, chosen from evidence

Priority order (fixed by the project brief): **A** native name/title flag →
**B** `set title; exec real-cli "$@"` → **C** official plugin/hook →
**D** single-CLI special adaptation.

| CLI | Strategy | Evidence (this machine, 2026-10-05) | Status |
| --- | --- | --- | --- |
| **CodeBuddy** | A/B hybrid: suppress its own title with `CODEBUDDY_CODE_DISABLE_TERMINAL_TITLE=1`, then emit ours before start | probe (re-verified): plain run writes exactly one `OSC 0` with an **empty payload**; with the variable set, **zero** `OSC 0` writes | verified by probe |
| **Qoder** | A: inject `-n "<project> · QODER"` when the user did not pass `-n`/`--name`; exact tab label additionally needs `ui.hideWindowTitle` | probe (re-verified): **both** `-n` and `--name` accepted → `◇ probe · QODER \| Ready` (icon + padding); control run writes `◇ Qoder CLI CN \| Ready`; empty title on exit; `ui.dynamicWindowTitle` defaults to `true` | injection verified; config step not implemented yet |
| **OpenCode** | A: per-process env — `OPENCODE_CLI_CONFIG_CONTENT='{"terminal":{"title":false}}'` (verified) + `OPENCODE_DISABLE_TERMINAL_TITLE=true` (forward compat) | probe: control writes `OpenCode`; flag `=1` and `=true` still write on v2.0.23 (flag absent from this build; official upstream `packages/core/src/flag/flag.ts`); inline config → **zero writes**; wrapper end-to-end → only `<project> · OPENCODE` | verified by probe; see D9 |
| **PI** | C: project-owned extension loaded with `-e` that writes the title itself; one deferred re-emit is required because PI writes its own title *after* `session_start` | probe (real project, Phase 2): wrapper title → extension `session_start` emit → `π - agent-toolbox` → deferred re-emit **wins**; full `pi --help` contains no title-disable flag | verified end to end |

**Respecting user arguments (AC7):** if the user already passed `-n` or
`--name` (Qoder) the wrapper injects nothing. A second `--name` would break
argument parsing, and the user's choice wins.

**PI's own title format** is `π - <basename(cwd)>` (or
`π - <session name> - <basename(cwd)>` with `--name`). It already contains the
project name but not in our format and without the CLI name, which is why the
extension exists at all.

**OpenCode has no stable official plugin hook for the terminal title.** The
documented plugin event list (`message.*`, `session.*`, `tool.*`, `tui.*`, …)
contains no title event; the title is set by the TUI from configuration — and
D9 shows that configuration can be overridden **per process**. The V0 file
`~/.config/opencode/plugins/marvis-tab-title.ts` is therefore *not* carried
into V1: a plugin that fights the TUI on every render is exactly the kind of
fragile coupling this project is trying to avoid. If a stable title hook ever
appears, it becomes a normal adapter file in this repository.

## D9. OpenCode title suppression: official mechanisms only

**Decision (probed 2026-10-05, local opencode v2.0.23):**

1. **Primary, verified:** the official per-process inline config —
   `OPENCODE_CLI_CONFIG_CONTENT='{"terminal":{"title":false}}'`
   (docs: `opencode.ai/v2/docs/cli/config`, § *Inline config*; merges over
   `~/.config/opencode/cli.json`, the file itself is never written).
   Probe result: **zero `OSC 0` writes**; wrapper end-to-end shows only
   `<project> · OPENCODE`.
2. **Also exported, forward-compatible:** `OPENCODE_DISABLE_TERMINAL_TITLE=true`
   (official upstream flag: `anomalyco/opencode` `packages/core/src/flag/flag.ts`,
   documented in `cli.mdx` as "Disable automatic terminal title updates").
   Probe on v2.0.23: **ineffective** — `=1` and `=true` both still write
   `OpenCode`, and the flag string is absent from this build. Harmless where
   unsupported; takes effect on builds that carry the flag. Boolean string
   form `true` used, per upstream `truthy()` convention.
3. **No plugin.** The V0 `~/.config/opencode/plugins/marvis-tab-title.ts` is
   obsolete for V1: never loaded, never rewritten by this project; `status.sh`
   reports it (and the V0 rc markers) as *manual migration required*. Migration
   is a report, not an automatic rewrite — V0 files stay the user's to remove.

Phase-1 failed attempts are recorded in the adapter header so they are not
retried: the variable was `OPENCODE_CONFIG_CONTENT` (wrong name) and the file
was `tui.json` (since migrated to `cli.json` by OpenCode itself).

**Reason:** the brief's priority order — official mechanism first; a plugin
that fights the TUI on every render is exactly the fragile coupling V0 had.

## D10. Per-process configuration beats global user configuration

**Decision:** every behavior switch this project needs is set **per process**
(env var or argument exported by the wrapper for its child only):
`OPENCODE_CLI_CONFIG_CONTENT`, `OPENCODE_DISABLE_TERMINAL_TITLE`,
`CODEBUDDY_CODE_DISABLE_TERMINAL_TITLE`, Qoder's `-n`. Nothing is written to
`~/.config/opencode/cli.json`, `~/.qoder-cn/settings.json`, `~/.bashrc` (beyond
the marker block) or Windows Terminal `settings.json` during Phase 2 — those
remain `--apply`-gated at most, and Phase 2 never runs `--apply` on the real
machine (AC-P2-10).

A user-supplied value keeps authority: an existing `OPENCODE_CLI_CONFIG_CONTENT`
or `OPENCODE_DISABLE_TERMINAL_TITLE` is respected, and `ACT_KEEP_CLI_TITLE=1`
opts a CLI out entirely.

**Reason:** it preserves the behavior boundary the brief demands — plain
`opencode` → native OpenCode; wrapper-launched → `<project> · OPENCODE` —
and keeps the test suite runnable against a temp `HOME` without global state.

## D11. No background process wrappers for TUIs

**Decision:** every adapter runs its real CLI as a **foreground child** of the
wrapper (never background + `sleep` + `wait`, never a title daemon, never a
polling loop). This is enforced mechanically: `tests/unit/test_hard_limits.sh`
fails if `src/run/act-wrap.sh` or any adapter contains `&`, `sleep`, `wait`,
or if any code file contains a broad kill invocation (`pkill`/`killall`/
`Stop-Process -Name`/`taskkill`) — AC-P2-08.

The only timer in the project is PI's extension-side single deferred re-emit
(the D6 exception): in-process, one-shot, `unref`'d, owning no second process
and no terminal.

**Reason (V0 lesson):** `background + sleep + wait` produced sparse TUI output
and ambiguous `wait` semantics on this machine (D5). Note that `exec` is *not*
a free upgrade either: several CLIs clear or overwrite the title on exit, so
the wrapper deliberately outlives its child to restore the project title (AC8).

## D12. Environment boundary: Windows vs WSL

**Decision:** the Windows-native project (`D:\ghq\github.com\DwainYu\TFTAutoRecorder`) stays Windows-native. WSL projects stay in WSL. Nothing in this
project routes one into the other, and no fake wrapper is created for a CLI
that does not exist on a given side.

**Reason (V0 lesson):** mixing the two sides produced configuration that only
worked from one direction. Windows support here means "the PowerShell adapter
infrastructure exists and activates when `Get-Command` finds the CLI".

## D13. Test layers, and what may run where

**Decision:** unit → integration (fake CLIs, temp `HOME`) → terminal/manual
(real CLIs, real Windows Terminal). CI never launches a real TUI.

**Reason (V0 lesson):** OpenCode keeps background service processes, so any
test that cleans up "all opencode processes" can kill a session the user is
actually running. Rule for this repository: *a test may only kill pids it
started itself*, and every spawned pid is recorded (parent/child/process
group) by the harness.

## D14. Documentation must separate observation from fact

**Decision:** V0 findings and probe results are written as "observed on this
machine at this version", never as universal statements about a CLI.

**Reason:** the brief explicitly forbids turning unverified local phenomena
into general claims. When a CLI updates, the probe is cheap to rerun and the
row in `docs/compatibility.md` is cheap to correct.

---

## V0 failure log (recorded, not repeated)

These are observations from the V0 experiment on the author's machine. They are
the reason several decisions above exist.

1. **Fixed Windows Terminal profiles are not the right abstraction.** Titles
   must follow the working directory, not a launch configuration.
2. **Project + CLI is the right context.** The tab must answer both questions
   at once.
3. **`suppressApplicationTitle=true` blocks shell dynamic titles.** Confirmed
   against Microsoft's documentation, not only by experiment.
4. **`exec` alone cannot solve a CLI that overwrites the title.** The CLI owns
   the tty after `exec`; nothing is left to correct it, and nothing runs at exit.
5. **`background + sleep + wait` carries TUI risk.** PI and Qoder showed sparse
   TUI output in the V0 harness.
6. **OpenCode keeps background service processes**, which makes `wait` based
   wrappers and broad process cleanup unsafe.
7. **PATH injection must be idempotent.** Unconditional prepending duplicated
   and reordered `~/.local/bin` as the source chain ran repeatedly.
8. **Windows and WSL are separate environments** and must not be forced into
   one another.
