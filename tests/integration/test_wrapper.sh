#!/usr/bin/env bash
# Integration: wrapper runtime against a fake CLI (never a real TUI).
#
# Covers AC7 (verbatim args), AC8 (title restored after exit), the title
# ordering (title before the child, restore after), -n respect, unicode/space
# project names, exit-status propagation and stdout passthrough.
set -u

TESTS_DIR=${TESTS_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
REPO_ROOT=${REPO_ROOT:-$(cd -- "$TESTS_DIR/.." && pwd)}

# shellcheck source=tests/lib.sh
. "$TESTS_DIR/lib.sh"

REPO=$REPO_ROOT
FAKE="$TESTS_DIR/fixtures/bin/fake-cli"
S=$(mktemp -d /tmp/opencode/wraptest.XXXXXX) || exit 1
cleanup() { rm -rf "$S"; }
trap cleanup EXIT

# osc <title> -> the exact bytes act::title::emit writes
osc() { printf '\033]0;%s\a' "$1"; }

proj="$S/proj-x"
mkdir -p "$proj"

# --- AC2/AC8: exact title bytes, then restore -------------------------------
sink="$S/sink1"
: >"$sink"
(
    cd "$proj" || exit 1
    ACT_TITLE_SINK="$sink" ACT_REAL_PI="$FAKE" "$REPO/bin/pi" hello
) >"$S/out1" 2>"$S/err1"
status1=$?
t::eq 0 "$status1" "wrapper exits with the child's status 0"
t::eq "$(osc 'proj-x · PI')$(osc 'proj-x')" "$(cat "$sink")" \
    "emits '<project> · <CLI>' then restores '<project>' (AC1/AC8)"

# --- AC7: arguments forwarded verbatim (spaces, unicode, --flag=) -----------
args1="$S/args1"
sink="$S/sink2"
: >"$sink"
(
    cd "$proj" || exit 1
    FAKE_ARGS_OUT="$args1" ACT_TITLE_SINK="$sink" ACT_REAL_PI="$FAKE" \
        "$REPO/bin/pi" arg1 "arg two" --flag=值 "quote'inside"
) >/dev/null 2>&1
expected_args=$'-e\n'"$REPO/src/cli/pi-title.ts"$'\narg1\narg two\n--flag=值\nquote\'inside'
t::eq "$expected_args" "$(cat "$args1")" \
    "PI: extras + user args arrive byte-for-byte (AC7)"

# --- ordering: title exists before the child starts -------------------------
snap="$S/snap"
args1c="$S/args1c"
: >"$sink"
(
    cd "$proj" || exit 1
    FAKE_ARGS_OUT="$args1c" FAKE_SINK_SNAP="$snap" ACT_TITLE_SINK="$sink" \
        ACT_REAL_PI="$FAKE" "$REPO/bin/pi"
) >/dev/null 2>&1
t::eq "$(osc 'proj-x · PI')" "$(cat "$snap")" \
    "title is emitted before the CLI starts (strategy B ordering)"

# --- AC8: non-zero and signal-like exit statuses propagate ------------------
for code in 3 130; do
    sink="$S/sink-$code"
    : >"$sink"
    got=0
    (
        cd "$proj" || exit 1
        FAKE_EXIT=$code ACT_TITLE_SINK="$sink" ACT_REAL_PI="$FAKE" "$REPO/bin/pi"
    ) >/dev/null 2>&1 || got=$?
    t::eq "$code" "$got" "exit status $code propagates through the wrapper"
    t::eq "$(osc 'proj-x · PI')$(osc 'proj-x')" "$(cat "$sink")" \
        "restore still runs when the child exits $code"
done

# --- AC3: user-supplied -n is never overridden ------------------------------
argsn="$S/args-n"
(
    cd "$proj" || exit 1
    FAKE_ARGS_OUT="$argsn" ACT_TITLE_SINK="$S/sink-n" ACT_REAL_QODER="$FAKE" \
        "$REPO/bin/qoder" --name mine >/dev/null 2>&1
) >/dev/null 2>&1
t::eq $'--name\nmine' "$(cat "$argsn")" \
    "qoder: user --name passed through, no injected -n (AC3)"

argsn2="$S/args-n2"
(
    cd "$proj" || exit 1
    FAKE_ARGS_OUT="$argsn2" ACT_TITLE_SINK="$S/sink-n2" ACT_REAL_QODER="$FAKE" \
        "$REPO/bin/qoder" >/dev/null 2>&1
) >/dev/null 2>&1
t::eq $'-n\nproj-x · QODER' "$(cat "$argsn2")" \
    "qoder: -n '<project> · QODER' injected when the user did not name the session"

# --- unicode and spaces in the project name ---------------------------------
proj_u="$S/项目 dir"
mkdir -p "$proj_u"
sink_u="$S/sink-u"
: >"$sink_u"
(
    cd "$proj_u" || exit 1
    ACT_TITLE_SINK="$sink_u" ACT_REAL_PI="$FAKE" "$REPO/bin/pi"
) >/dev/null 2>&1
t::eq "$(osc '项目 dir · PI')$(osc '项目 dir')" "$(cat "$sink_u")" \
    "unicode + space project name flows through unchanged"

# --- stdout passthrough and ACT_TITLE_TARGET=stdout fallback ----------------
out_t="$S/out-target"
(
    cd "$proj" || exit 1
    ACT_TITLE_TARGET=stdout FAKE_STDOUT=1 ACT_REAL_PI="$FAKE" "$REPO/bin/pi"
) >"$out_t" 2>&1
t::contains "$(cat "$out_t")" "$(osc 'proj-x · PI')" \
    "with no sink and no tty, the title goes to stdout"
t::contains "$(cat "$out_t")" "fake-cli: stdout marker" \
    "the CLI's own stdout passes through the wrapper"
t::contains "$(cat "$out_t")" "$(osc 'proj-x')" \
    "restore reaches stdout as well"

# --- unknown adapter fails fast, without emitting any title -----------------
mkdir -p "$S/ghost"
ln -s "$REPO/src/run/act-wrap.sh" "$S/ghost/fakecli"
: >"$S/sink-bad"
got=0
ACT_TITLE_SINK="$S/sink-bad" "$S/ghost/fakecli" >/dev/null 2>&1 || got=$?
t::eq 127 "$got" "bin name without an adapter exits 127 before anything is emitted"
t::eq "" "$(cat "$S/sink-bad")" "no title bytes are written for an unknown adapter"

t::summary
