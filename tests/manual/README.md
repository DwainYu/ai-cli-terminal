# Manual validation layer

Nothing in this directory runs from `tests/run.sh` or `scripts/test.sh`:
these checks start **real TUIs** or target a **real Windows machine**, which
the automated layers must never do (AC-P2-09, AC-P2-10).

## wsl/ — real CLIs, real projects (AC-P2-06)

```bash
./tests/manual/wsl/validate.sh            # four project+CLI pairs, ~35 s
./tests/manual/wsl/validate.sh pi         # one pair
```

| Project | CLI | Expected first title |
| --- | --- | --- |
| `agent-toolbox` | PI | `agent-toolbox · PI` |
| `tft-training-log` | OpenCode (`--standalone`) | `tft-training-log · OPENCODE` |
| `hengguang-ai-platform-demo` | CodeBuddy | `hengguang-ai-platform-demo · CODEBUDDY` |
| `md-content-publisher` | Qoder | `md-content-publisher · QODER` |

Safety rules enforced by the harness:

- throwaway `HOME` per run — the real home and every real config file stay
  untouched (AC-P2-10);
- only the process group the harness created is signalled; escapees are
  matched by the unique temp-`HOME` marker and terminated **by exact pid** —
  no broad kills (AC-P2-08);
- OpenCode runs `--standalone` so the interactive TUI is never conflated
  with a background service;
- project directories are used as *cwd* only, never written to.

## windows/ — Windows 11 + Windows Terminal (AC-P2-05/07)

```powershell
.\scripts\test-windows.ps1                 # from a checkout on Windows
```

See [`windows/README.md`](windows/README.md) for the four-tab real-terminal
procedure (AC-P2-07) and the `TFTAutoRecorder` project-name fixture.
