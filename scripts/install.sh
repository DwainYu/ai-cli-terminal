#!/usr/bin/env bash
# ai-cli-terminal installer.
#
#   ./scripts/install.sh            # dry run (default): prints what WOULD change
#   ./scripts/install.sh --apply    # the only way any user file is written
#
# What --apply may touch (nothing else, ever):
#   1. the shell rc file (default: $HOME/.bashrc) — marker block only
#   2. the runtime tree under ~/.local/share/ai-cli-terminal — our own directory
#
# Both paths are marker/idempotency based: a second run reports "unchanged".
# Phase-1 rule: development and tests run without --apply, against a temp HOME.
set -euo pipefail

usage() {
    cat <<'EOF'
usage: install.sh [--dry-run|--apply] [--rc FILE] [--share DIR] [--home DIR]

  --dry-run      default: print "would modify:"/"would create:" lines, write nothing
  --apply        write changes (rc marker block + runtime tree)
  --rc FILE      shell rc to manage (default: <home>/.bashrc)
  --share DIR    install directory (default: <home>/.local/share/ai-cli-terminal)
  --home DIR     home prefix used for the defaults (default: $HOME)
  -h, --help     this text
EOF
}

mode=dry
rc='' share='' home=${ACT_HOME:-${HOME:-}}

while [ $# -gt 0 ]; do
    case $1 in
        --apply) mode=apply ;;
        --dry-run) mode=dry ;;
        --rc) rc=${2:?--rc needs a value}; shift ;;
        --share) share=${2:?--share needs a value}; shift ;;
        --home) home=${2:?--home needs a value}; shift ;;
        -h | --help) usage; exit 0 ;;
        *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
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

if [ "$mode" = dry ]; then
    printf 'ai-cli-terminal install (dry run)\n'
    printf 'no files will be written; re-run with --apply to make changes.\n'
else
    printf 'ai-cli-terminal install (apply)\n'
fi

# 1. rc marker block ----------------------------------------------------------
act::install::rc_apply "$rc" "$share" "$mode"

# 2. runtime tree (bin/ + src/) ----------------------------------------------
if [ "$mode" = apply ]; then
    mkdir -p -- "$share"
fi
act::install::tree_sync "$repo_root/src" "$share/src" "$mode"
act::install::tree_sync "$repo_root/bin" "$share/bin" "$mode"

# 3. manifest — lets uninstall verify the directory is ours -------------------
manifest="$share/install-manifest"
if [ ! -f "$manifest" ]; then
    if [ "$mode" = apply ]; then
        printf 'ai-cli-terminal install manifest\nrepo: %s\n' "$repo_root" >"$manifest"
        printf 'created: %s\n' "$manifest"
    else
        printf 'would create: %s\n' "$manifest"
    fi
fi

# 4. V0 leftovers: report only — never modified by this project ---------------
act::install::v0_report "$rc" "$home" || true

if [ "$mode" = dry ]; then
    printf 'dry run complete: 0 files written.\n'
else
    printf 'apply complete. open a new shell (or `source %s`) to load the block.\n' "$rc"
fi
