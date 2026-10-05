#!/usr/bin/env bash
# Unit tests: adapter registry, per-adapter behaviour, argument rules.
set -u

: "${REPO_ROOT:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
. "$REPO_ROOT/tests/lib.sh"

ACT_ROOT=$REPO_ROOT
. "$REPO_ROOT/src/lib/adapter.sh"

# --- registry: every shipped adapter loads ----------------------------------
for id in pi opencode codebuddy qoder; do
    if act::adapter::load "$id" 2>/dev/null; then
        t::_ok "adapter $id loads"
    else
        t::_bad "adapter $id loads"
    fi
done

act::adapter::load pi
t::eq 'PI' "$ACT_ADAPTER_DISPLAY" "pi display name is PI"
t::eq 'extension-title' "$ACT_ADAPTER_STRATEGY" "pi strategy recorded"

act::adapter::load opencode
t::eq 'OPENCODE' "$ACT_ADAPTER_DISPLAY" "opencode display name is OPENCODE"
t::eq 'env-suppress' "$ACT_ADAPTER_STRATEGY" "opencode strategy recorded"

# --- OpenCode: official per-process suppression (D9/D10) --------------------
out=$(
    act::adapter::load opencode
    act::adapter::prepare
    printf '%s|%s' "${OPENCODE_DISABLE_TERMINAL_TITLE-unset}" \
        "${OPENCODE_CLI_CONFIG_CONTENT-unset}"
)
t::eq 'true|{"terminal":{"title":false}}' "$out" \
    "opencode: both official suppression vars exported"

out=$(
    export OPENCODE_CLI_CONFIG_CONTENT='{"tabs":{"mode":"off"}}'
    act::adapter::load opencode
    act::adapter::prepare
    printf '%s' "$OPENCODE_CLI_CONFIG_CONTENT"
)
t::eq '{"tabs":{"mode":"off"}}' "$out" \
    "opencode: a user-set inline config keeps authority"

out=$(
    export OPENCODE_DISABLE_TERMINAL_TITLE=false
    act::adapter::load opencode
    act::adapter::prepare
    printf '%s' "$OPENCODE_DISABLE_TERMINAL_TITLE"
)
t::eq 'false' "$out" "opencode: an explicit user value for the flag is respected"

out=$(
    export ACT_KEEP_CLI_TITLE=1
    act::adapter::load opencode
    act::adapter::prepare
    printf '%s|%s' "${OPENCODE_DISABLE_TERMINAL_TITLE-unset}" \
        "${OPENCODE_CLI_CONFIG_CONTENT-unset}"
)
t::eq 'unset|unset' "$out" "opencode: ACT_KEEP_CLI_TITLE=1 opts out"

act::adapter::load codebuddy
t::eq 'CODEBUDDY' "$ACT_ADAPTER_DISPLAY" "codebuddy display name is CODEBUDDY"
t::eq 'env-suppress' "$ACT_ADAPTER_STRATEGY" "codebuddy strategy recorded"

act::adapter::load qoder
t::eq 'QODER' "$ACT_ADAPTER_DISPLAY" "qoder display name is QODER"
t::contains "${ACT_ADAPTER_BINS[*]}" "qoder" "qoder bins include qoder"

# --- name mapping -----------------------------------------------------------
act::adapter::load_for qoder-cn >/dev/null 2>&1
t::eq 'qoder' "$ACT_ADAPTER_ID" "qoder-cn maps to the qoder adapter"

act::adapter::load_for pi >/dev/null 2>&1
t::eq 'pi' "$ACT_ADAPTER_ID" "pi maps to itself"

t::status 1 "unknown invocation name fails" act::adapter::load_for definitely-not-a-cli

# --- CodeBuddy environment switch -------------------------------------------
out=$(
    act::adapter::load codebuddy
    act::adapter::prepare
    printf '%s' "${CODEBUDDY_CODE_DISABLE_TERMINAL_TITLE-unset}"
)
t::eq '1' "$out" "codebuddy: title switch exported"

out=$(
    ACT_KEEP_CLI_TITLE=1
    export ACT_KEEP_CLI_TITLE
    act::adapter::load codebuddy
    act::adapter::prepare
    printf '%s' "${CODEBUDDY_CODE_DISABLE_TERMINAL_TITLE-unset}"
)
t::eq 'unset' "$out" "codebuddy: ACT_KEEP_CLI_TITLE=1 opts out"

# --- Qoder: never override a user supplied -n/--name ------------------------
qoder_args() {
    ACT_TITLE=$1
    shift
    ACT_USER_ARGS=("$@")
    ACT_EXTRA_ARGS=()
    act::adapter::load qoder
    act::adapter::args
    printf '%s\n' "${ACT_EXTRA_ARGS[@]+"${ACT_EXTRA_ARGS[@]}"}"
}

out=$(qoder_args 'demo · QODER')
t::eq $'-n\ndemo · QODER' "$out" "qoder: injects -n with the title when absent"

out=$(qoder_args 'demo · QODER' --print 'hello')
t::eq $'-n\ndemo · QODER' "$out" "qoder: injection works alongside other flags"

out=$(qoder_args 'demo · QODER' --name 'my session')
t::eq '' "$out" "qoder: --name from the user is respected"

out=$(qoder_args 'demo · QODER' -n 'custom')
t::eq '' "$out" "qoder: -n from the user is respected"

out=$(qoder_args 'demo · QODER' --name=custom)
t::eq '' "$out" "qoder: --name=custom is respected"

out=$(qoder_args 'demo · QODER' -ncustom)
t::eq '' "$out" "qoder: -nattached is respected"

# --- PI: project owned extension --------------------------------------------
pi_args() {
    ACT_TITLE=$1
    ACT_USER_ARGS=("${@:2}")
    ACT_EXTRA_ARGS=()
    act::adapter::load pi
    act::adapter::args
    printf '%s\n' "${ACT_EXTRA_ARGS[@]+"${ACT_EXTRA_ARGS[@]}"}"
}

out=$(pi_args 'demo · PI')
t::contains "$out" "-e" "pi: loads the project extension"
t::contains "$out" "src/cli/pi-title.ts" "pi: extension path is inside the repo"

out=$(pi_args 'demo · PI' --help)
t::contains "$out" "pi-title.ts" "pi: extension still forwarded with --help"

# --- extension / adapter sync -----------------------------------------------
ext_cli_name=$(grep -oE 'CLI_NAME = "[A-Z]+"' "$REPO_ROOT/src/cli/pi-title.ts" | sed 's/.*"\(.*\)"/\1/')
act::adapter::load pi
t::eq "$ACT_ADAPTER_DISPLAY" "$ext_cli_name" \
    "pi extension CLI_NAME matches ACT_ADAPTER_DISPLAY"

# --- describe ----------------------------------------------------------------
act::adapter::load qoder
line=$(act::adapter::describe)
t::contains "$line" "qoder" "describe: id"
t::contains "$line" "QODER" "describe: display"

t::summary
