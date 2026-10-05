#!/usr/bin/env bash
# ai-cli-terminal status — read-only. Never writes, never needs --apply.
#
# Reports: rc marker state, runtime tree state, current-shell PATH entry,
# and (informational only) V0 leftovers this project does not manage.
set -euo pipefail

rc='' share='' home=${ACT_HOME:-${HOME:-}}
while [ $# -gt 0 ]; do
    case $1 in
        --rc) rc=${2:?--rc needs a value}; shift ;;
        --share) share=${2:?--share needs a value}; shift ;;
        --home) home=${2:?--home needs a value}; shift ;;
        -h | --help)
            printf 'usage: status.sh [--rc FILE] [--share DIR] [--home DIR]\n'
            exit 0 ;;
        *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$home" ] || { printf 'error: no home; pass --home\n' >&2; exit 2; }
rc=${ACT_RC:-${rc:-$home/.bashrc}}
share=${ACT_SHARE:-${share:-$home/.local/share/ai-cli-terminal}}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/.." && pwd -P)
# shellcheck source=src/shell/bash/act-init.sh
. "$repo_root/src/shell/bash/act-init.sh"
# shellcheck source=src/lib/install.sh
. "$repo_root/src/lib/install.sh"

printf 'ai-cli-terminal status\n'

if [ -f "$rc" ]; then
    block=$(act::install::rc_block "$rc")
    if [ -n "$block" ]; then printf 'rc block:      present in %s\n' "$rc"
    else printf 'rc block:      absent in %s\n' "$rc"; fi
else
    printf 'rc file:       %s (does not exist)\n' "$rc"
fi

if [ -d "$share" ] && [ -f "$share/install-manifest" ]; then
    n=$(find "$share" \( -type f -o -type l \) | wc -l)
    printf 'runtime tree:  installed at %s (%s files)\n' "$share" "$n"
elif [ -e "$share" ]; then
    printf 'runtime tree:  %s exists but has no manifest (not ours)\n' "$share"
else
    printf 'runtime tree:  not installed (%s)\n' "$share"
fi

case ":$PATH:" in
    *":$share/bin:"*) printf 'PATH entry:    present (this shell)\n' ;;
    *) printf 'PATH entry:    absent (this shell)\n' ;;
esac

# Informational only — V0 artifacts are never read, written or removed here.
act::install::v0_report "$rc" "$home" || true

exit 0
