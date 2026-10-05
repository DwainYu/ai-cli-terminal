# References

Three projects were studied before any code was written. Nothing is copied as
a whole, none of them is a runtime dependency, and none of them is vendored.

---

## 1. `matrozov/windows-terminal-tweaks` (primary)

Studied for: `tab-title`, WSL handling, `OSC 0`, install/uninstall, backup,
idempotency.

### What was taken

| Idea | How it appears here |
| --- | --- |
| The tab title is produced by the *shell* emitting `OSC 0`, not by terminal configuration | the whole title path: `src/lib/title.sh` |
| Bash title belongs in `PS1`/prompt time, because the stock prompt redraws the title *after* `PROMPT_COMMAND` | `src/shell/bash/act-init.sh` installs a prompt hook that writes the project name whenever a prompt is drawn, so a plain `cd` also updates the tab |
| Marker blocks: `# >>> <feature> >>>` … `# <<< <feature> <<<`, replaced as a whole on re-run | `scripts/install.sh`, markers `# >>> ai-cli-terminal >>>` |
| Per-feature markers so several features can share one file without clobbering each other | the same mechanism, ready for a second block |
| Backup before edit: `<name>.bak-<YYYYMMDD-HHmmss>`, created only when the file actually changes | `scripts/install.sh` |
| `-WhatIf` / report mode as the default | `install.sh` defaults to `--dry-run`; `--apply` is the only mutating path |
| Uninstall = delete the block, leave everything else alone | `scripts/uninstall.sh` |
| A shell *function* shadows a program of the same name (function wins over `PATH`), and inside it the program is resolved with `command <name>` to avoid recursion | `src/lib/resolve.sh` applies the same "bypass yourself" rule to the wrapper |
| An explicit user argument (`--name`, `-n`) is never overridden | `act::adapter::args` for Qoder checks the user's argv first |
| Warn about `suppressApplicationTitle` profiles instead of silently editing them | `docs/compatibility.md`, `scripts/status.sh` |
| Edit `settings.json` textually by key, never round-trip through a JSON parser (JSONC comments and formatting would be destroyed) | the rule adopted for any future Windows Terminal / Qoder settings edit |

### What was not taken

- The PowerShell installer architecture (`Install-All.ps1`, `-WhatIfReport`,
  report pipeline, `Set-MarkedBlock` etc.). This project installs from bash
  inside WSL; a `pwsh` installer is a possible later addition, not a V1 need.
- `restore-directories` (`OSC 9;9`) — useful, but out of scope: this project
  sets titles, it does not restore window layouts.
- `claude-session-name` — the technique is reused conceptually (inject a name
  flag for the CLI that has one), but Claude Code is not one of our four CLIs.
- `cmd` support, oh-my-posh support, Git-for-Windows specific behaviour.
- Its `PS1` suffix form `\W` (basename only). Our title also carries the CLI
  name, so it must be computed, not delegated to prompt expansion.

Nothing from this repository is executed, sourced or depended on at runtime.

---

## 2. `MicrosoftDocs/terminal` (authoritative for Windows Terminal behaviour)

Studied for: `tabTitle`, `suppressApplicationTitle`, shell title behaviour,
`OSC` sequences, shell integration.

### Facts used (with sources)

| Fact | Source |
| --- | --- |
| `tabTitle` replaces `name` as the **starting** title; shells respond differently (PowerShell sets it, cmd sets it and appends the running command, Ubuntu ignores it and sets `user@machine:path`) | `TerminalDocs/tutorials/tab-title.md` |
| A shell has full control of its title: bash uses `echo -ne "\033]0;New Title\a"` | `TerminalDocs/tutorials/tab-title.md` |
| `suppressApplicationTitle: true` makes `tabTitle` the visible title **and suppresses any title change messages from the application** | `TerminalDocs/customize-settings/profile-advanced.md` ("Suppress title changes") |
| `name` is passed to the shell as the startup title; `tabTitle` overrides it | `TerminalDocs/customize-settings/profile-general.md` |
| Tab title follows the **focused pane** when a tab has several panes | `TerminalDocs/tutorials/tab-title.md` |
| `newTab` / `splitPane` actions accept their own `tabTitle` and `suppressApplicationTitle` (inherited from the profile when not given) | `TerminalDocs/customize-settings/actions.md` |
| `OSC 9;9` reports the working directory, `OSC 133` is shell-integration prompt marking — neither is a title mechanism | `TerminalDocs/tutorials/shell-integration.md` |

### Consequences for this project

1. Dynamic titles live exactly where the docs say a shell can put them:
   `OSC 0` written by the shell/CLI, with `suppressApplicationTitle` left off.
2. `tabTitle` is *not* used for `<project> · <CLI>`: it is a per-profile static
   value and cannot vary per tab.
3. The Ubuntu note ("bash may ignore the startup title") is why the title is
   written at runtime rather than configured once.
4. `OSC 9;9` is deliberately excluded from scope.

### What was not taken

- Anything from third-party descriptions of Terminal behaviour. Where a
  reference project and the official docs disagreed, the official docs won.
- Shell-integration marks, suggestions, working-directory reporting.

---

## 3. `Kuddev/pebrel` (product-shape reference only)

Studied for: how a tool organises `terminal / session / workspace / AI CLI`.

### What was taken

- Vocabulary discipline: *tab* is a terminal, *session* is a conversation,
  *workspace* is a directory. This project uses only the directory dimension.
- Confirmation that the interesting part of such a product is the tab bar, and
  that a title is enough to communicate "which project, which agent".

### What was not taken — explicitly

Pebrel is a GPU-accelerated terminal emulator (Rust/GPUI) with split panes,
SSH/SFTP, saved workspaces, AI hooks, notifications, a reader pane, Lua config,
an agent sidebar, and session restoration. **None of that belongs here.**

This project is not a terminal, not an orchestrator, not a session manager,
not a workspace manager, and ships no GUI. If V1 ever grows a sidebar, it has
grown the wrong thing.

---

## Summary

```text
windows-terminal-tweaks  →  shell-side OSC 0, markers, backup, idempotent install/uninstall
MicrosoftDocs/terminal   →  which setting decides what, and where dynamic titles are allowed
pebrel                   →  what to refuse to become
```
