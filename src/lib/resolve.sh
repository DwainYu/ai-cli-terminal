# ai-cli-terminal — real CLI resolution
#
# The wrapper must find the *real* program, never itself, and (during the V0
# transition) never the old experimental wrappers either. The original CLI is
# never modified, renamed or replaced: we only choose which file to exec.
#
# shellcheck shell=bash

# act::resolve::is_wrapper <file> -> 0 when the file is a known wrapper
# Recognises this project's entry scripts and the V0 experimental wrappers so
# that a PATH that still contains them does not create a wrapper chain.
act::resolve::is_wrapper() {
    local file=$1
    [ -e "$file" ] || return 1
    # Only shell scripts can be wrappers; anything else (binaries, ELF) is safe.
    if head -c 2 -- "$file" 2>/dev/null | grep -q '#!'; then
        head -n 16 -- "$file" 2>/dev/null | grep -qE \
            'ai-cli-terminal wrapper|marvis dynamic tab-title wrapper'
        return $?
    fi
    return 1
}

# act::resolve::real -> stdout: absolute path of the real CLI, or status 1
#
# Order:
#   1. $<ACT_ADAPTER_REAL_ENV>   explicit override (ACT_REAL_PI, ...)
#   2. PATH scan for each $ACT_ADAPTER_BINS entry
#   3. $ACT_ADAPTER_FALLBACK_PATHS absolute candidates
#
# A candidate is skipped when it is the running wrapper, when it lives in this
# project's bin directory, or when it looks like a wrapper script.
act::resolve::real() {
    local override=${ACT_ADAPTER_REAL_ENV:-}
    if [ -n "$override" ] && [ -n "${!override-}" ]; then
        printf '%s' "${!override}"
        return 0
    fi

    local bin dir cand dir_real
    for bin in ${ACT_ADAPTER_BINS[@]+"${ACT_ADAPTER_BINS[@]}"}; do
        local rest=$PATH
        while [ -n "$rest" ]; do
            case $rest in
                *:*) dir=${rest%%:*}; rest=${rest#*:} ;;
                *) dir=$rest; rest='' ;;
            esac
            [ -n "$dir" ] || dir=.
            cand=$dir/$bin

            if [ -e "$cand" ] && [ -x "$cand" ]; then
                dir_real=$(cd -- "$dir" 2>/dev/null && pwd -P) || dir_real=$dir
                if [ "$dir_real" = "${ACT_BIN_DIR-}" ]; then
                    continue # our own wrapper directory
                fi
                if [ "${ACT_WRAP_RESOLVED-}" = "$(readlink -f -- "$cand" 2>/dev/null)" ]; then
                    continue # the file we are running from
                fi
                if act::resolve::is_wrapper "$cand"; then
                    continue # a wrapper (ours or V0), keep looking
                fi
                printf '%s' "$cand"
                return 0
            fi
        done
    done

    for cand in ${ACT_ADAPTER_FALLBACK_PATHS[@]+"${ACT_ADAPTER_FALLBACK_PATHS[@]}"}; do
        cand=${cand/#\~/$HOME}
        if [ -e "$cand" ] && [ -x "$cand" ] && ! act::resolve::is_wrapper "$cand"; then
            printf '%s' "$cand"
            return 0
        fi
    done

    return 1
}
