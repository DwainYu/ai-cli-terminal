#!/usr/bin/env bash
# Unit: project-wide safety limits — the rules Phase 2 must not regress.
#
#   * no broad process killing (pkill/killall) in any code file (AC-P2-08);
#   * the bash runtime never backgrounds, never sleeps, never waits —
#     foreground only (D5/D11);
#   * exactly one OSC 0 printf exists in the bash sources (D7).
#
# Excluded on purpose: src/cli/pi-title.ts — its single deferred in-process
# re-emit is a CLI-owned one-shot (D6 exception), not a wrapper mechanism.
set -u

TESTS_DIR=${TESTS_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
REPO_ROOT=${REPO_ROOT:-$(cd -- "$TESTS_DIR/.." && pwd)}

# shellcheck source=tests/lib.sh
. "$TESTS_DIR/lib.sh"

code_files=()
while IFS= read -r f; do code_files+=("$f"); done < <(
    find "$REPO_ROOT/src" "$REPO_ROOT/scripts" "$REPO_ROOT/tests" \
        \( -name '*.sh' -o -name '*.py' -o -name '*.ps1' -o -name '*.adapter' \) \
        -type f | sort
)

# --- AC-P2-08: no broad process killing -------------------------------------
hits=$(grep -nE '\b(pkill|killall)\b[[:space:]]+-' "${code_files[@]}" 2>/dev/null || true)
t::eq '' "$hits" "no pkill/killall command invocations anywhere (AC-P2-08)"

hits=$(grep -nE 'Stop-Process[[:space:]]+-Name|taskkill[[:space:]]+/' \
    "${code_files[@]}" 2>/dev/null | grep -vF -- "$0" || true)
t::eq '' "$hits" "no Windows broad kills (Stop-Process -Name / taskkill)"

# --- foreground-only bash runtime -------------------------------------------
runtime_code=$(sed 's/#.*//' "$REPO_ROOT/src/run/act-wrap.sh")
t::eq '' "$(printf '%s' "$runtime_code" | grep -E '(^|[^&[:alnum:]_])&([[:space:]]|$)')" \
    "act-wrap.sh never backgrounds a process (&)"
t::eq '' "$(printf '%s' "$runtime_code" | grep -wE 'sleep')" \
    "act-wrap.sh never sleeps"
t::eq '' "$(printf '%s' "$runtime_code" | grep -wE 'wait')" \
    "act-wrap.sh never waits"

adapter_hits=''
while IFS= read -r f; do
    code=$(sed 's/#.*//' "$f")
    case $code in
        *' sleep '* | *sleep\ * | *' wait '* | *wait\ *)
            adapter_hits="$adapter_hits$f: sleep/wait in adapter code"$'\n' ;;
    esac
done < <(find "$REPO_ROOT/src/cli" -name '*.adapter' -type f | sort)
t::eq '' "$adapter_hits" "adapters never sleep/wait"

# --- D7: one OSC 0 writer in the bash sources -------------------------------
n=$(grep -rlF ']0;' "$REPO_ROOT/src" --include='*.sh' | wc -l)
t::eq 1 "$n" "exactly one file in src/*.sh knows the OSC 0 sequence (D7)"
n=$(sed 's/#.*//' "$REPO_ROOT/src/lib/title.sh" | grep -cF ']0;')
t::eq 1 "$n" "the OSC 0 printf lives once, in act::title::emit (D7)"

# --- runtime never references user rc files (only installer may) ------------
hits=$(grep -nE '\.bashrc|\.profile' "$REPO_ROOT/src/run" "$REPO_ROOT/src/lib" 2>/dev/null || true)
t::eq '' "$hits" "runtime never touches shell rc files (only scripts/install.sh may)"

t::summary
