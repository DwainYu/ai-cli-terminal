#!/usr/bin/env bash
# Unit tests: title formatting, sanitizing and emission.
set -u

: "${REPO_ROOT:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
. "$REPO_ROOT/tests/lib.sh"
. "$REPO_ROOT/src/lib/title.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- format -----------------------------------------------------------------
t::eq "tft-training-log · PI" \
    "$(act::title::format 'tft-training-log' 'PI')" \
    "format: <project> · <cli>"

t::eq "agent-toolbox · OPENCODE" \
    "$(act::title::format 'agent-toolbox' 'OPENCODE')" \
    "format: second example from the brief"

t::eq "项目目录 · PI" \
    "$(act::title::format '项目目录' 'PI')" \
    "format: Chinese project name survives"

t::eq "my project · CODEBUDDY" \
    "$(act::title::format 'my project' 'CODEBUDDY')" \
    "format: spaces preserved"

t::eq "  spaced   ·   PI  " \
    "$(act::title::format '  spaced  ' '  PI  ')" \
    "format: padding preserved (caller decides trimming)"

# --- sanitize ---------------------------------------------------------------
t::eq 'evil' "$(act::title::sanitize $'e\033vil\x07')" \
    "sanitize: ESC and BEL removed"

t::eq 'onetwo' "$(act::title::sanitize $'one\r\ntwo')" \
    "sanitize: CR and LF removed (joined)"

t::eq '中文目录' "$(act::title::sanitize '中文目录')" \
    "sanitize: UTF-8 untouched"

t::eq 'D:\ghq\repo' "$(act::title::sanitize 'D:\ghq\repo')" \
    "sanitize: backslashes untouched"

# --- emission ---------------------------------------------------------------
sink="$tmp/title.bin"
: >"$sink"
ACT_TITLE_SINK=$sink act::title::emit 'tft-training-log · PI'
expected=$(printf '\033]0;%s\a' 'tft-training-log · PI')
got=$(cat "$sink")
t::eq "$expected" "$got" "emit: exact OSC 0 bytes (ESC ] 0 ; title BEL)"

: >"$sink"
ACT_TITLE_SINK=$sink act::title::emit $'bad\x1b]0;evil\x07title'
expected=$(printf '\033]0;%s\a' 'bad]0;eviltitle')
got=$(cat "$sink")
t::eq "$expected" "$got" "emit: injected control characters are neutralized"

: >"$sink"
ACT_TITLE_SINK=$sink act::title::emit ''
expected=$(printf '\033]0;\a')
got=$(cat "$sink")
t::eq "$expected" "$got" "emit: empty title is still a valid OSC"

: >"$sink"
ACT_TITLE_SINK=$sink act::title::emit 'hengguang-ai-platform-demo · QODER'
t::count_in_file "$sink" 'hengguang-ai-platform-demo · QODER' 1 \
    "emit: payload written once"

# --- no shell expansion -----------------------------------------------------
marker="$tmp/expanded"
: >"$marker" 2>/dev/null || true
rm -f "$marker"
: >"$sink"
ACT_TITLE_SINK=$sink act::title::emit '$(touch '"$marker"')'
ACT_TITLE_SINK=$sink act::title::emit '`touch '"$marker"'`'
if [ -e "$marker" ]; then
    t::_bad "format/emit: no command substitution happens on the title"
else
    t::_ok "format/emit: no command substitution happens on the title"
fi
t::file_contains "$sink" '$(touch' "emit: literal \$( ) survives in payload"
t::file_contains "$sink" '`touch' "emit: literal backticks survive in payload"

# --- stdout target ----------------------------------------------------------
out=$(ACT_TITLE_TARGET=stdout act::title::emit 'no-sink' | cat -v | head -1)
t::contains "$out" '^[]0;no-sink^G' "emit: ACT_TITLE_TARGET=stdout writes to stdout (cat -v)"

# --- restore ----------------------------------------------------------------
: >"$sink"
ACT_TITLE_SINK=$sink act::title::restore 'TFTAutoRecorder'
expected=$(printf '\033]0;%s\a' 'TFTAutoRecorder')
t::eq "$expected" "$(cat "$sink")" "restore: project-only title"

# --- sink is optional -------------------------------------------------------
t::summary
