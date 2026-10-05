#!/usr/bin/env bash
# Unit tests: project name resolution for WSL and Windows paths.
set -u

: "${REPO_ROOT:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
. "$REPO_ROOT/tests/lib.sh"
. "$REPO_ROOT/src/lib/title.sh"
. "$REPO_ROOT/src/lib/project.sh"

# --- plain WSL paths --------------------------------------------------------
t::eq 'tft-training-log' \
    "$(act::project::name '/home/user/projects/tft-training-log')" \
    "wsl: projects path"

t::eq 'tft-training-log' \
    "$(act::project::name '/home/user/projects/tft-training-log/')" \
    "wsl: trailing slash removed"

t::eq 'agent-toolbox' \
    "$(act::project::name '/home/user/projects/agent-toolbox//')" \
    "wsl: several trailing slashes removed"

t::eq 'user' "$(act::project::name '/home/user')" "wsl: home directory"

t::eq '/' "$(act::project::name '/')" "root stays root"

t::eq 'hengguang-ai-platform-demo' \
    "$(act::project::name 'relative/path/hengguang-ai-platform-demo/')" \
    "relative path works too"

# --- Windows paths ----------------------------------------------------------
t::eq 'TFTAutoRecorder' \
    "$(act::project::name 'D:\ghq\github.com\DwainYu\TFTAutoRecorder')" \
    "windows: native path"

t::eq 'TFTAutoRecorder' \
    "$(act::project::name 'D:\ghq\github.com\DwainYu\TFTAutoRecorder\')" \
    "windows: trailing backslash"

t::eq 'TFTAutoRecorder' \
    "$(act::project::name 'D:/ghq/github.com/DwainYu/TFTAutoRecorder')" \
    "windows: forward slashes"

t::eq 'repo' "$(act::project::name '\\server\share\repo')" "windows: UNC path"

# --- unicode and odd names --------------------------------------------------
t::eq '深度学习实验' "$(act::project::name '/data/深度学习实验')" "unicode directory"

t::eq 'my project (v2)' "$(act::project::name '/home/user/my project (v2)')" \
    "spaces and parentheses"

t::eq 'a.b.c' "$(act::project::name '/tmp/a.b.c')" "dots in the name"

# --- default input ----------------------------------------------------------
here_name=$(basename -- "$PWD")
t::eq "$here_name" "$(act::project::name)" "default input is \$PWD"

sub="$PWD"
t::eq "$here_name" "$(act::project::name '')" "empty input falls back to \$PWD"

# --- combined title ---------------------------------------------------------
t::eq 'tft-training-log · PI' \
    "$(act::project::title 'PI' '/home/user/projects/tft-training-log')" \
    "project + cli is the whole title formula"

t::eq 'TFTAutoRecorder · PI' \
    "$(act::project::title 'PI' 'D:\ghq\github.com\DwainYu\TFTAutoRecorder')" \
    "windows project + cli"

t::summary
