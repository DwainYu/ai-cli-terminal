#!/usr/bin/env bash
# Integration: V0 (marvis) environment → V1 install, on a temp HOME.
#
# Fixture mirrors the real machine's ~/.bashrc V0 section (marker block at
# lines 177-179 + unmarked unconditional PATH prepend, read-only copy).
#
# Contract under test (migration rules):
#   * install never injects twice                 (idempotent, AC9)
#   * the old marker block is correctly DETECTED  (report, not rewrite)
#   * V1 works alongside V0                       ("can migrate" = V1 active,
#     V0 untouched; safe automatic removal of V0 is NOT attempted)
#   * uninstall restores the V0 file byte-for-byte (AC10)
#   * both install and status report: manual migration required
set -u

TESTS_DIR=${TESTS_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
REPO_ROOT=${REPO_ROOT:-$(cd -- "$TESTS_DIR/.." && pwd)}

# shellcheck source=tests/lib.sh
. "$TESTS_DIR/lib.sh"

REPO=$REPO_ROOT
S=$(mktemp -d /tmp/opencode/migtest.XXXXXX) || exit 1
cleanup() { rm -rf "$S"; }
trap cleanup EXIT

home="$S/home"
rc="$home/.bashrc"
mkdir -p "$home/.local/bin"
cp "$TESTS_DIR/fixtures/v0/bashrc-v0" "$rc"
orig=$(cat "$rc")

# V0 wrapper leftover (read-only for this project)
v0="$home/.local/bin/pi"
printf '# marvis dynamic tab-title wrapper\necho v0\n' >"$v0"
v0_orig=$(cat "$v0")

install() { bash "$REPO/scripts/install.sh" --home "$home" "$@"; }
uninstall() { bash "$REPO/scripts/uninstall.sh" --home "$home" "$@"; }
status() { bash "$REPO/scripts/status.sh" --home "$home" "$@"; }

# --- detection: report, never rewrite ---------------------------------------
out=$(install)
t::contains "$out" "manual migration required" \
    "install dry run reports V0 leftovers with manual migration required"
action_lines=$(printf '%s\n' "$out" | grep -E '^(would modify|would create):' || true)
t::not_contains "$action_lines" "$v0" \
    "no dry-run action line targets the V0 wrapper"

out=$(status)
t::contains "$out" "manual migration required" \
    "status reports manual migration required"
t::contains "$out" "v0 leftovers: detected in $rc" "status names the V0 rc block"

# --- install beside V0, twice ----------------------------------------------
out=$(install --apply)
t::count_in_file "$rc" '# >>> ai-cli-terminal >>>' 1 "one V1 marker after apply"
t::count_in_file "$rc" 'export PATH="$HOME/.local/bin:$PATH"' 1 \
    "V0 unconditional PATH line kept exactly once (not ours to touch)"
t::count_in_file "$rc" 'MARVIS-AI-CLI-WRAPPER' 2 "both V0 comments intact"

v0_region() {
    awk '/^# >>> marvis-ai-cli-tab-title >>>$/,/^# <<< marvis-ai-cli-tab-title <<<$/' "$rc"
}
v0_now=$(v0_region)
printf '%s\n' "$v0_now" | grep -q 'marvis-ai-cli-tab-title-bashrc.sh'
t::eq 0 $? "V0 marker block content preserved byte-for-byte"

out=$(install --apply)
t::contains "$out" "unchanged: $rc" "second apply: rc unchanged (no duplication)"
t::count_in_file "$rc" '# >>> ai-cli-terminal >>>' 1 "still one V1 marker after 2 applies"

# --- precedence: first source puts V1 wrappers before V0 --------------------
p=$(env -i HOME="$home" PATH=/usr/bin:/bin bash -c ". '$rc'; printf '%s' \"\$PATH\"" | tr ':' '\n')
ours=$(printf '%s\n' "$p" | grep -n 'ai-cli-terminal' | head -1 | cut -d: -f1)
theirs=$(printf '%s\n' "$p" | grep -n '.local/bin' | head -1 | cut -d: -f1)
t::ne "" "$ours" "our share bin is on PATH after sourcing"
t::ne "" "$theirs" "V0's .local/bin is on PATH after sourcing"
if [ -n "$ours" ] && [ -n "$theirs" ] && [ "$ours" -lt "$theirs" ]; then
    t::_ok "V1 wrapper dir precedes V0's .local/bin on first source"
else
    t::_bad "V1 wrapper dir precedes V0's .local/bin on first source" \
        "ours@$ours theirs@$theirs"
fi

# re-sourcing keeps our entry at most once (V0's own duplication is theirs)
n=$(env -i HOME="$home" PATH=/usr/bin:/bin bash -c ". '$rc'; . '$rc'; printf '%s' \"\$PATH\"" | tr ':' '\n' | grep -c 'ai-cli-terminal')
t::eq 1 "$n" "our PATH entry appears at most once even after double sourcing"

# --- uninstall: full restore of the V0 file --------------------------------
out=$(uninstall --apply)
t::eq "$orig" "$(cat "$rc")" \
    "uninstall restores the V0-era rc file byte-for-byte"
t::eq "no" "$([ -d "$home/.local/share/ai-cli-terminal" ] && echo yes || echo no)" \
    "install dir removed"
t::eq "$v0_orig" "$(cat "$v0")" "V0 wrapper file untouched"

# --- re-install after uninstall still works --------------------------------
out=$(install --apply)
t::count_in_file "$rc" '# >>> ai-cli-terminal >>>' 1 "re-install works after uninstall"
t::contains "$(status)" "manual migration required" \
    "status still reports migration after re-install"

t::summary
