#!/usr/bin/env bash
# Integration: install / uninstall / status against a temp HOME.
#
# Covers AC9 (repeated install causes no duplication — run three times),
# AC10 (uninstall restores the user's file), AC11 (nothing outside the temp
# HOME is ever touched) and the V0-safety rule: files this project never
# wrote are left alone.
set -u

TESTS_DIR=${TESTS_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
REPO_ROOT=${REPO_ROOT:-$(cd -- "$TESTS_DIR/.." && pwd)}

# shellcheck source=tests/lib.sh
. "$TESTS_DIR/lib.sh"

REPO=$REPO_ROOT
S=$(mktemp -d /tmp/opencode/insttest.XXXXXX) || exit 1
cleanup() { rm -rf "$S"; }
trap cleanup EXIT

home="$S/home"
rc="$home/.bashrc"
mkdir -p "$home/.local/bin"
printf '# user bashrc\nexport FOO=1\n' >"$rc"
orig=$(cat "$rc")

# a V0 leftover that must never be read, written or removed
v0="$home/.local/bin/pi"
printf '# marvis dynamic tab-title wrapper\necho v0\n' >"$v0"
v0_before=$(cat "$v0")

install() { bash "$REPO/scripts/install.sh" --home "$home" "$@"; }
uninstall() { bash "$REPO/scripts/uninstall.sh" --home "$home" "$@"; }
status() { bash "$REPO/scripts/status.sh" --home "$home" "$@"; }

# --- dry run writes nothing (AC11) ------------------------------------------
out=$(install)
t::contains "$out" "would modify: $rc" "dry run names the rc file it would modify"
t::contains "$out" "would create:" "dry run lists files it would create"
t::contains "$out" "dry run complete: 0 files written." "dry run reports zero writes"
t::eq "$orig" "$(cat "$rc")" "dry run leaves the rc file untouched"
t::eq "no" "$([ -d "$home/.local/share/ai-cli-terminal" ] && echo yes || echo no)" \
    "dry run creates no install dir (explicit)"

# --- apply: markers + user content preserved --------------------------------
out=$(install --apply)
t::contains "$out" "modified: $rc" "apply reports the rc modification"
t::count_in_file "$rc" '# >>> ai-cli-terminal >>>' 1 "one begin marker after apply"
t::count_in_file "$rc" '# <<< ai-cli-terminal <<<' 1 "one end marker after apply"
t::file_contains "$rc" 'export FOO=1' "user content survives the block insert"
t::count_in_file "$rc" 'export FOO=1' 1 "user content not duplicated"
t::eq "yes" "$([ -f "$home/.local/share/ai-cli-terminal/install-manifest" ] && echo yes || echo no)" \
    "runtime tree installed with manifest"

# --- apply twice more: AC9 idempotency --------------------------------------
out2=$(install --apply)
out3=$(install --apply)
t::contains "$out2" "unchanged: $rc" "second apply: rc unchanged"
t::contains "$out3" "unchanged: $rc" "third apply: rc unchanged"
t::count_in_file "$rc" '# >>> ai-cli-terminal >>>' 1 "still one begin marker after 3 applies"
t::not_contains "$out2" "created:" "second apply creates no files"
t::not_contains "$out3" "created:" "third apply creates no files"
t::not_contains "$out2" "modified:" "second apply modifies no files"
# everything outside the markers is still exactly the user's original file
stripped=$(awk -v b='# >>> ai-cli-terminal >>>' -v e='# <<< ai-cli-terminal <<<' '
    inb { if ($0 == e) inb = 0; next }
    $0 == b { inb = 1; next }
    { print }
' "$rc")
t::eq "$orig" "$stripped" "content outside the markers equals the original file"

# --- PATH guard: sourcing twice adds the dir once ---------------------------
share="$home/.local/share/ai-cli-terminal"
n=$(env -i HOME="$home" PATH=/usr/bin:/bin bash -c ". '$rc'; . '$rc'; printf '%s' \"\$PATH\"" | tr ':' '\n' | grep -c ai-cli-terminal)
t::eq 1 "$n" "PATH entry appears exactly once even when sourced twice (AC9)"

# --- status (read-only) -----------------------------------------------------
out=$(status)
t::contains "$out" "rc block:      present" "status reports the rc block"
t::contains "$out" "runtime tree:  installed" "status reports the runtime tree"

# --- dry-run uninstall writes nothing --------------------------------------
out=$(uninstall)
t::contains "$out" "would modify: $rc" "uninstall dry run names the rc file"
t::contains "$out" "would remove: $share" "uninstall dry run names the install dir"
t::contains "$out" "dry run complete: 0 files written." "uninstall dry run reports zero writes"
t::count_in_file "$rc" '# >>> ai-cli-terminal >>>' 1 "block still present after dry run"

# --- apply uninstall: AC10 --------------------------------------------------
out=$(uninstall --apply)
t::eq "$orig" "$(cat "$rc")" "uninstall restores the rc file byte-for-byte (AC10)"
t::eq "no" "$([ -d "$share" ] && echo yes || echo no)" "install dir removed"
t::eq "yes" "$(ls "$rc".bak-* >/dev/null 2>&1 && echo yes || echo no)" "backup kept after uninstall"
t::eq "$v0_before" "$(cat "$v0")" "V0 wrapper file untouched by install+uninstall"

# install dry run must never *act* on the V0 wrapper either (reporting is fine)
out=$(install)
action_lines=$(printf '%s\n' "$out" | grep -E '^(would modify|would create):' || true)
t::not_contains "$action_lines" "$v0" "install dry run never targets the V0 wrapper"
t::contains "$out" "v0 leftovers: $v0" "install reports the V0 wrapper as leftover"
t::eq "$v0_before" "$(cat "$v0")" "V0 wrapper still untouched after a dry run"

# --- V0 leftovers are informational only ------------------------------------
out=$(status)
t::contains "$out" "v0 leftovers:" "status flags the V0 wrapper as unmanaged"
t::eq "$v0_before" "$(cat "$v0")" "status is read-only for V0 files"

t::summary
