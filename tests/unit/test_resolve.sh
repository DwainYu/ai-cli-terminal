#!/usr/bin/env bash
# Unit tests: real CLI resolution (never ourselves, never a wrapper chain).
set -u

: "${REPO_ROOT:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
. "$REPO_ROOT/tests/lib.sh"

ACT_ROOT=$REPO_ROOT
. "$REPO_ROOT/src/lib/adapter.sh"
. "$REPO_ROOT/src/lib/resolve.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/wrapperbin" "$tmp/realbin" "$tmp/v0bin"

ACT_BIN_DIR=$REPO_ROOT/bin
ACT_WRAP_RESOLVED=$(readlink -f -- "$REPO_ROOT/bin/pi")
ACT_ADAPTER_BINS=(fakecli)
ACT_ADAPTER_FALLBACK_PATHS=()
ACT_ADAPTER_REAL_ENV=ACT_REAL_FAKECLI
unset ACT_REAL_FAKECLI 2>/dev/null || true

# fake "real" CLI (plain script, no markers)
cat >"$tmp/realbin/fakecli" <<'EOF'
#!/usr/bin/env bash
echo "real fakecli $*"
EOF
chmod +x "$tmp/realbin/fakecli"

# a V0 style wrapper: must be skipped by marker detection
cat >"$tmp/v0bin/fakecli" <<'EOF'
#!/usr/bin/env bash
# marvis dynamic tab-title wrapper: <basename($PWD)> · <CLI>
printf '\033]0;old wrapper\a'
exec /bin/true
EOF
chmod +x "$tmp/v0bin/fakecli"

PATH="$tmp/wrapperbin:$tmp/v0bin:$tmp/realbin:/usr/bin:/bin"
export PATH

# --- PATH scan skips a V0 wrapper and finds the real one ---------------------
out=$(act::resolve::real)
t::eq "$tmp/realbin/fakecli" "$out" "V0 wrapper skipped, real CLI found later on PATH"

# --- explicit override wins --------------------------------------------------
out=$(ACT_REAL_FAKECLI=/opt/custom/fakecli act::resolve::real)
t::eq '/opt/custom/fakecli' "$out" "ACT_REAL_* override wins over PATH"

# --- the wrapper directory itself is skipped (no marker needed) -------------
cat >"$tmp/wrapperbin/fakecli" <<'EOF'
#!/usr/bin/env bash
echo "entry point of some wrapper"
EOF
chmod +x "$tmp/wrapperbin/fakecli"
saved_bin_dir=$ACT_BIN_DIR
ACT_BIN_DIR=$tmp/wrapperbin
out=$(act::resolve::real)
t::eq "$tmp/realbin/fakecli" "$out" "the wrapper bin directory is skipped"
ACT_BIN_DIR=$saved_bin_dir
rm -f "$tmp/wrapperbin/fakecli"

# --- the running wrapper itself is skipped ----------------------------------
ACT_WRAP_RESOLVED=$tmp/realbin/fakecli
out=$(act::resolve::real)
t::ne "$tmp/realbin/fakecli" "$out" "the running wrapper itself is not resolved"
ACT_WRAP_RESOLVED=$(readlink -f -- "$REPO_ROOT/bin/pi")
out=$(act::resolve::real)
t::eq "$tmp/realbin/fakecli" "$out" "normal resolution restored"

# --- nothing on PATH -> fallback path -> failure ----------------------------
PATH="/usr/bin:/bin"
export PATH
t::status 1 "nothing found -> failure status" act::resolve::real

ACT_ADAPTER_FALLBACK_PATHS=("$tmp/realbin/fakecli")
out=$(act::resolve::real)
t::eq "$tmp/realbin/fakecli" "$out" "fallback absolute path used when not on PATH"

# --- marker detection --------------------------------------------------------
if act::resolve::is_wrapper "$tmp/v0bin/fakecli"; then
    t::_ok "V0 wrapper detected by marker"
else
    t::_bad "V0 wrapper detected by marker"
fi
if act::resolve::is_wrapper "$tmp/realbin/fakecli"; then
    t::_bad "plain script not classified as wrapper"
else
    t::_ok "plain script not classified as wrapper"
fi
if act::resolve::is_wrapper "$REPO_ROOT/src/run/act-wrap.sh"; then
    t::_ok "our own runtime detected as wrapper"
else
    t::_bad "our own runtime detected as wrapper"
fi
if act::resolve::is_wrapper /bin/ls; then
    t::_bad "a binary is never a wrapper"
else
    t::_ok "a binary is never a wrapper"
fi

# --- shipped entry points ----------------------------------------------------
for name in pi opencode codebuddy qoder qoder-cn; do
    if [ -L "$REPO_ROOT/bin/$name" ] && [ -f "$REPO_ROOT/bin/$name" ]; then
        t::_ok "bin/$name is a symlink to the runtime"
    else
        t::_bad "bin/$name is a symlink to the runtime"
    fi
done

t::summary
