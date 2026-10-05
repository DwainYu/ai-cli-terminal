#!/usr/bin/env bash
# ai-cli-terminal uninstaller — removes exactly what install.sh wrote.
#
#   ./scripts/uninstall.sh          # dry run (default)
#   ./scripts/uninstall.sh --apply
#
# Removes: the rc marker block, the runtime tree (only when it carries our
# install manifest). Keeps: backups, everything outside the markers, any file
# this project never wrote (e.g. V0 wrappers in ~/.local/bin).
set -euo pipefail

usage() {
    cat <<'EOF'
usage: uninstall.sh [--dry-run|--apply] [--rc FILE] [--share DIR] [--home DIR]

  --dry-run      default: print "would modify:" lines, write nothing
  --apply        remove the rc marker block and the installed runtime tree
  --rc FILE      shell rc to clean (default: <home>/.bashrc)
  --share DIR    install directory to remove (default: <home>/.local/share/ai-cli-terminal)
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
    printf 'ai-cli-terminal uninstall (dry run)\n'
else
    printf 'ai-cli-terminal uninstall (apply)\n'
fi

# 1. rc marker block ----------------------------------------------------------
act::install::rc_remove "$rc" "$mode"

# 2. runtime tree -------------------------------------------------------------
manifest="$share/install-manifest"
if [ -d "$share" ]; then
    if [ -f "$manifest" ]; then
        if [ "$mode" = apply ]; then
            rm -rf -- "$share"
            printf 'removed: %s\n' "$share"
        else
            printf 'would remove: %s\n' "$share"
        fi
    else
        printf 'skipped: %s (no install manifest; not created by this project)\n' "$share"
    fi
else
    printf 'absent: %s\n' "$share"
fi

if [ "$mode" = dry ]; then
    printf 'dry run complete: 0 files written.\n'
else
    printf 'uninstall complete. backups (if any) were kept.\n'
fi
