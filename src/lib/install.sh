# shellcheck shell=bash
# Install primitives — every user-file write in the project goes through here
# (D7: one installer, backup + marker + idempotent + minimal diff).
#
# Functions (all take explicit paths; nothing reads $HOME directly, so tests
# can point them at a temp home):
#
#   act::install::rc_block       <rc> <share>        -> current block (text)
#   act::install::rc_render      <rc> <share>        -> rc with block applied
#   act::install::rc_apply       <rc> <share>        -> write; prints status
#   act::install::rc_remove      <rc>                -> drop block; prints status
#   act::install::tree_diff      <src> <dst>         -> "create|modify|<rel>"
#   act::install::tree_sync      <src> <dst> <apply> -> copy changed files
#
# Printing convention used by the scripts:
#   dry run   "would modify: <path>" / "would create: <path>"
#   applied   "modified: <path>"     / "created: <path>"
#   nothing   "unchanged: <path>"

ACT_INSTALL_MARKER_BEGIN='# >>> ai-cli-terminal >>>'
ACT_INSTALL_MARKER_END='# <<< ai-cli-terminal <<<'

act::install::timestamp() { date +%Y%m%d%H%M%S; }

# --- V0 (marvis) detection ---------------------------------------------------
# Coexistence rule: V0 blocks are READ ONLY. This project never removes or
# rewrites them — automatic migration cannot be done safely, so the honest
# outcome is a report (D-candidates in docs/compatibility.md).
# Prints one line when V0 markers are found; returns 0 if found, 1 otherwise.
act::install::v0_report() {
    local rc=$1 home=${2:-${HOME:-}} found=0
    if [ -f "$rc" ] && grep -qs -e 'marvis-ai-cli-tab-title' -e 'MARVIS-AI-CLI-WRAPPER' -- "$rc"; then
        printf 'v0 leftovers: detected in %s — manual migration required (see docs/compatibility.md)\n' "$rc"
        found=1
    fi
    local v0
    for v0 in "$home/.local/bin/pi" "$home/.local/bin/opencode" \
        "$home/.local/bin/codebuddy" "$home/.local/bin/qoder" \
        "$home/.local/bin/qoder-cn"; do
        if [ -f "$v0" ] && grep -qs 'marvis' -- "$v0"; then
            printf 'v0 leftovers: %s (unmanaged; never modified by this project)\n' "$v0"
            found=1
        fi
    done
    [ "$found" -eq 1 ]
}

# --- rc helpers -------------------------------------------------------------

# Print only our marker block currently present in $1 (all occurrences).
act::install::rc_block() {
    local rc=$1
    [ -f "$rc" ] || return 0
    awk -v b="$ACT_INSTALL_MARKER_BEGIN" -v e="$ACT_INSTALL_MARKER_END" '
        $0 == b { inb = 1 }
        inb     { print }
        $0 == e { inb = 0 }
    ' "$rc"
}

# Print $rc with our block replaced in place (or appended when absent).
# Everything outside the markers is copied byte for byte.
act::install::rc_render() {
    local rc=$1 share=$2 block_file out
    block_file=$(mktemp) || return 1
    out=$(mktemp) || { rm -f "$block_file"; return 1; }
    act::init::render "$share" >"$block_file"

    if [ -f "$rc" ]; then
        awk -v b="$ACT_INSTALL_MARKER_BEGIN" -v e="$ACT_INSTALL_MARKER_END" \
            -v bf="$block_file" '
            inb {
                if ($0 == e) { inb = 0; placed = 1 }
                next
            }
            $0 == b {
                if (!placed) {
                    while ((getline line < bf) > 0) print line
                    close(bf)
                    placed = 1
                }
                inb = 1
                next
            }
            { print }
            END {
                if (!placed) {
                    while ((getline line < bf) > 0) print line
                    close(bf)
                }
            }
        ' "$rc" >"$out"
    else
        cat "$block_file" >"$out"
    fi
    rm -f "$block_file"
    cat "$out"
    rm -f "$out"
}

# Write the block into $rc. Prints the status line; returns 0 always unless
# the filesystem itself fails. Backup only when content really changes.
act::install::rc_apply() {
    local rc=$1 share=$2 mode=${3:-dry} tmp
    tmp=$(mktemp) || return 1
    act::install::rc_render "$rc" "$share" >"$tmp" || { rm -f "$tmp"; return 1; }

    if [ -f "$rc" ] && cmp -s "$tmp" "$rc"; then
        rm -f "$tmp"
        printf 'unchanged: %s\n' "$rc"
        return 0
    fi

    if [ "$mode" != apply ]; then
        rm -f "$tmp"
        if [ -f "$rc" ]; then printf 'would modify: %s\n' "$rc"
        else printf 'would create: %s\n' "$rc"; fi
        return 0
    fi

    local backup=''
    if [ -f "$rc" ]; then
        backup="$rc.bak-$(act::install::timestamp)"
        cp -p -- "$rc" "$backup" || { rm -f "$tmp"; return 1; }
        printf 'backup: %s\n' "$backup"
    fi
    mkdir -p -- "$(dirname -- "$rc")"
    mv -f -- "$tmp" "$rc"
    if [ -n "$backup" ]; then printf 'modified: %s\n' "$rc"
    else printf 'created: %s\n' "$rc"; fi
}

# Remove our block from $rc, leaving everything else (and backups) alone.
act::install::rc_remove() {
    local rc=$1 mode=${2:-dry} tmp
    [ -f "$rc" ] || { printf 'absent: %s\n' "$rc"; return 0; }
    if [ -z "$(act::install::rc_block "$rc")" ]; then
        printf 'unchanged: %s\n' "$rc"
        return 0
    fi

    tmp=$(mktemp) || return 1
    awk -v b="$ACT_INSTALL_MARKER_BEGIN" -v e="$ACT_INSTALL_MARKER_END" '
        inb { if ($0 == e) inb = 0; next }
        $0 == b { inb = 1; next }
        { print }
    ' "$rc" >"$tmp" || { rm -f "$tmp"; return 1; }

    if [ "$mode" != apply ]; then
        rm -f "$tmp"
        printf 'would modify: %s\n' "$rc"
        return 0
    fi

    local backup="$rc.bak-$(act::install::timestamp)"
    cp -p -- "$rc" "$backup" || { rm -f "$tmp"; return 1; }
    mv -f -- "$tmp" "$rc"
    printf 'backup: %s\n' "$backup"
    printf 'modified: %s\n' "$rc"
}

# --- runtime tree helpers ---------------------------------------------------

# Print one line per file: "create <rel>" or "modify <rel>" (empty = in sync).
act::install::tree_diff() {
    local src=$1 dst=$2 rel path target
    find "$src" \( -type f -o -type l \) -print | sort | while read -r path; do
        rel=${path#"$src"/}
        target="$dst/$rel"
        if [ ! -e "$target" ] && [ ! -L "$target" ]; then
            printf 'create %s\n' "$rel"
        elif [ -L "$path" ]; then
            if [ ! -L "$target" ] || [ "$(readlink -- "$path")" != "$(readlink -- "$target")" ]; then
                printf 'modify %s\n' "$rel"
            fi
        elif [ ! -f "$target" ]; then
            printf 'modify %s\n' "$rel"
        elif ! cmp -s -- "$path" "$target"; then
            printf 'modify %s\n' "$rel"
        fi
    done
}

# Copy changed/new files (and their directories) from src to dst.
# mode=dry only prints; mode=apply writes and reports per file.
act::install::tree_sync() {
    local src=$1 dst=$2 mode=${3:-dry} action rel existed
    act::install::tree_diff "$src" "$dst" | while read -r action rel; do
        if [ "$mode" = apply ]; then
            existed=0
            { [ -e "$dst/$rel" ] || [ -L "$dst/$rel" ]; } && existed=1
            mkdir -p -- "$(dirname -- "$dst/$rel")"
            cp -a -- "$src/$rel" "$dst/$rel"
            if [ "$existed" = 1 ]; then printf 'modified: %s\n' "$dst/$rel"
            else printf 'created: %s\n' "$dst/$rel"; fi
        else
            if [ "$action" = create ]; then printf 'would create: %s\n' "$dst/$rel"
            else printf 'would modify: %s\n' "$dst/$rel"; fi
        fi
    done
}
