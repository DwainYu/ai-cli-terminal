#!/usr/bin/env python3
"""Phase 2 real-environment validation (WSL): wrapper + REAL CLI + REAL project.

For every pair below the wrapper is started inside a pty in the real project
directory, against the real CLI binary, with:

  * an isolated throwaway HOME   (never the real one — AC-P2-10)
  * a sanitized environment       (inherited OPENCODE_*/OC_* stripped)
  * OpenCode always via --standalone (TUI vs background service stay
    separate: the wrapper never waits on a service — section 16)

PASS = the FIRST OSC 0 written after start is exactly the expected
`<project> · <CLI>` title (the wrapper's own emission, before the child
runs); everything the CLI writes afterwards is recorded for the report.

Cleanup rules (AC-P2-08): only the process group this script created is
signalled; anything that escaped is listed by the unique temp-HOME marker and
terminated by exact pid. No broad kill patterns, no shell rc, no --apply.
"""
import fcntl
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))  # tests/manual/wsl -> repo root
if not os.path.isdir(os.path.join(REPO, "src")):
    REPO = "/home/user/projects/ai-cli-terminal"

HERMES = "/home/user/.hermes/node/bin"
QODER_ENTRY = "/home/user/.qoder-cn/entry/qoder-cn"
QODER_REAL = "/home/user/.qoder-cn/bin/qoderclicn/qoderclicn-1.1.65"
PROJECTS = "/home/user/projects"

PAIRS = [
    # (project dir, wrapper bin name, expected first title, extra args,
    #  real env, seconds — PI boots slower in a real project)
    (f"{PROJECTS}/agent-toolbox", "pi", "agent-toolbox · PI",
     ["--approve"],  # trust project-local files for this run (official flag)
     {"ACT_REAL_PI": f"{HERMES}/pi"}, 16.0),
    (f"{PROJECTS}/tft-training-log", "opencode", "tft-training-log · OPENCODE",
     ["--standalone"], {"ACT_REAL_OPENCODE": f"{HERMES}/opencode"}, 8.0),
    (f"{PROJECTS}/hengguang-ai-platform-demo", "codebuddy",
     "hengguang-ai-platform-demo · CODEBUDDY", [],
     {"ACT_REAL_CODEBUDDY": f"{HERMES}/codebuddy"}, 8.0),
    (f"{PROJECTS}/md-content-publisher", "qoder", "md-content-publisher · QODER",
     [], {"ACT_REAL_QODER": QODER_ENTRY}, 10.0),
]

OSC0 = re.compile(rb"\x1b\]0;(.*?)\x07", re.S)
OSC0_ST = re.compile(rb"\x1b\]0;(.*?)\x1b\\", re.S)


def build_env(home, extra):
    env = {
        "PATH": f"{HERMES}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "HOME": home,
        "TERM": "xterm-256color",
        "NO_COLOR": "1",
        "LANG": "C.UTF-8",
        "PI_OFFLINE": "1",
    }
    env.update(extra)
    return env


def probe(cmd, cwd, env, seconds=8.0, cols=100, rows=30):
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.chdir(cwd)
        except OSError:
            pass
        try:
            os.execve(cmd[0], cmd, env)
        except Exception as exc:  # pragma: no cover
            os.write(2, str(exc).encode())
            os._exit(127)

    winsize = struct.pack("HHHH", rows, cols, 0, 0)
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)
    except OSError:
        pass

    buf = b""
    deadline = time.time() + seconds
    while time.time() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if fd in ready:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk

    # only the group we created (pty child = session/group leader)
    try:
        os.killpg(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass
    try:
        os.close(fd)
    except OSError:
        pass
    return buf


def residuals(marker):
    """Processes carrying the unique temp-HOME marker: report then kill by pid."""
    try:
        out = subprocess.run(["pgrep", "-f", marker], capture_output=True, text=True)
        pids = [p for p in out.stdout.split() if p]
    except Exception:
        return []
    alive = []
    for p in pids:
        try:
            os.kill(int(p), 0)
            alive.append(int(p))
        except (ProcessLookupError, ValueError):
            continue
    for p in alive:
        try:
            os.kill(p, signal.SIGKILL)
        except ProcessLookupError:
            pass
    return alive


def main():
    only = None
    if len(sys.argv) > 2 and sys.argv[1] == "--only":
        only = set(sys.argv[2:])
    pairs = PAIRS if only is None else [p for p in PAIRS if p[1] in only]
    if not pairs:
        print("no matching pair for --only")
        return 2

    base = "/tmp/opencode/validate"
    os.makedirs(base, exist_ok=True)
    # launcher name the qoder dispatcher looks up (symlink to the REAL binary)
    shim_dir = os.path.join(base, "bin")
    os.makedirs(shim_dir, exist_ok=True)
    shim = os.path.join(shim_dir, "qoderclicn")
    if not os.path.lexists(shim):
        os.symlink(QODER_REAL, shim)

    passed = failed = 0
    for i, (proj, wrapper, expected, args, realenv, seconds) in enumerate(pairs, 1):
        name = os.path.basename(proj)
        if not os.path.isdir(proj):
            print(f"not ok {i} - {name} + {wrapper}: project dir missing")
            failed += 1
            continue

        home = f"{base}/home-{name}-{wrapper}"
        os.makedirs(home, exist_ok=True)
        env = build_env(home, realenv)
        env["PATH"] = shim_dir + ":" + env["PATH"]
        cmd = [os.path.join(REPO, "bin", wrapper)] + args

        buf = probe(cmd, proj, env, seconds=seconds)
        resid = residuals(home)

        titles = [m.decode("utf-8", "replace") for m in OSC0.findall(buf)]
        titles += [m.decode("utf-8", "replace") for m in OSC0_ST.findall(buf)]
        first = titles[0] if titles else None

        shown = [repr(t) for t in titles[:4]]
        detail = "bytes=%d titles=%s" % (len(buf), str(shown))
        if resid:
            detail += f" residual-killed-by-pid={resid}"
        if first == expected:
            print(f"ok {i} - {name} + {wrapper}: {expected!r}")
            print(f"#   {detail}")
            passed += 1
        else:
            print(f"not ok {i} - {name} + {wrapper}: first={first!r} expected={expected!r}")
            print(f"#   {detail}")
            print(f"#   raw tail: {buf[-160:]!r}")
            failed += 1

    print(f"# validated: {passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
