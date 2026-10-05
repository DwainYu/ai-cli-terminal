#!/usr/bin/env bash
# ai-cli-terminal wrapper runtime — the single entry point behind bin/<cli>.
#
#   adapter → project name → title → resolve real CLI → run → restore → exit
#
# Deliberately absent: background launch, sleep, wait, polling, daemons.
# The real CLI runs as an ordinary foreground child and the wrapper outlives it
# so the title can be restored afterwards (AC8).
#
# shellcheck shell=bash
set -u

# --- locate ourselves (invoked through bin/<cli> symlink) --------------------
invoked_path=${BASH_SOURCE[0]}
while [ -L "$invoked_path" ]; do
    link_target=$(readlink -- "$invoked_path")
    case $link_target in
        /*) invoked_path=$link_target ;;
        *) invoked_path=$(dirname -- "$invoked_path")/$link_target ;;
    esac
done
ACT_WRAP_RESOLVED=$(cd -- "$(dirname -- "$invoked_path")" 2>/dev/null && pwd -P)/$(basename -- "$invoked_path")
ACT_ROOT=$(cd -- "$(dirname -- "$ACT_WRAP_RESOLVED")/../../" 2>/dev/null && pwd -P)

invoked_name=$(basename -- "${BASH_SOURCE[0]}")
ACT_BIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || ACT_BIN_DIR=''

# shellcheck source=src/lib/title.sh
. "$ACT_ROOT/src/lib/title.sh"
# shellcheck source=src/lib/project.sh
. "$ACT_ROOT/src/lib/project.sh"
# shellcheck source=src/lib/adapter.sh
. "$ACT_ROOT/src/lib/adapter.sh"
# shellcheck source=src/lib/resolve.sh
. "$ACT_ROOT/src/lib/resolve.sh"

if ! act::adapter::load_for "$invoked_name"; then
    exit 127
fi

# --- the two inputs of the title --------------------------------------------
ACT_PROJECT_NAME=$(act::project::name "${PWD-}")
ACT_TITLE=$(act::title::format "$ACT_PROJECT_NAME" "$ACT_ADAPTER_DISPLAY")
ACT_USER_ARGS=("$@")
ACT_EXTRA_ARGS=()

real=''
if ! real=$(act::resolve::real); then
    printf 'ai-cli-terminal: no real "%s" found for adapter %s.\n' \
        "${ACT_ADAPTER_BINS[0]}" "$ACT_ADAPTER_ID" >&2
    printf '                 Set %s=/path/to/the/real/cli and retry.\n' \
        "${ACT_ADAPTER_REAL_ENV:-ACT_REAL_<CLI>}" >&2
    exit 127
fi

if [ -n "${ACT_DEBUG-}" ]; then
    printf 'ai-cli-terminal: adapter=%s display=%s strategy=%s\n' \
        "$ACT_ADAPTER_ID" "$ACT_ADAPTER_DISPLAY" "$ACT_ADAPTER_STRATEGY" >&2
    printf 'ai-cli-terminal: project=%s title=%s\n' "$ACT_PROJECT_NAME" "$ACT_TITLE" >&2
    printf 'ai-cli-terminal: real=%s extra=(%s)\n' "$real" "${ACT_EXTRA_ARGS[*]-}" >&2
fi

declare -F act::adapter::prepare >/dev/null && act::adapter::prepare
declare -F act::adapter::args >/dev/null && act::adapter::args

if [ -n "${ACT_DEBUG-}" ]; then
    printf 'ai-cli-terminal: final extra=(%s)\n' "${ACT_EXTRA_ARGS[*]-}" >&2
fi

# --- title, then the CLI ----------------------------------------------------
act::title::emit "$ACT_TITLE"

# Restore on every way out. INT is *not* trapped or ignored: the real CLI must
# keep receiving Ctrl+C exactly as it would without this wrapper.
trap 'act::title::restore "$ACT_PROJECT_NAME"' EXIT
trap 'exit 143' TERM
trap 'exit 129' HUP

"$real" ${ACT_EXTRA_ARGS[@]+"${ACT_EXTRA_ARGS[@]}"} "$@"
status=$?

declare -F act::adapter::after >/dev/null && act::adapter::after "$status"

exit "$status"
