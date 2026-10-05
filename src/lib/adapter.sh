# ai-cli-terminal — adapter registry
#
# An adapter is one sourceable file, src/cli/<id>.adapter, that describes one
# AI CLI: which real binary it stands for, how it is called, and how the title
# is supposed to survive. The wrapper runtime contains no CLI-specific logic.
#
# Contract for an adapter file:
#   ACT_ADAPTER_ID            required, must equal the file name
#   ACT_ADAPTER_DISPLAY        required, the uppercase name used in the title
#   ACT_ADAPTER_ALIASES        optional, extra wrapper entry names
#   ACT_ADAPTER_BINS           optional, candidate real command names (array)
#   ACT_ADAPTER_FALLBACK_PATHS optional, absolute paths checked after PATH
#   ACT_ADAPTER_REAL_ENV       optional, env var that overrides resolution
#   ACT_ADAPTER_STRATEGY       required, one of the documented strategies
#   ACT_ADAPTER_NOTES          optional, human readable status
#   act::adapter::prepare      optional, export environment for the child
#   act::adapter::args         optional, append arguments (reads $ACT_EXTRA_ARGS)
#   act::adapter::after        optional, runs after the child exits
#
# Runtime variables handed to the hooks:
#   $ACT_TITLE          the formatted "<project> · <cli>" title
#   $ACT_PROJECT_NAME   the project name alone
#   $ACT_USER_ARGS      array, exactly what the user typed after the command
#
# shellcheck shell=bash

: "${ACT_ROOT:?ACT_ROOT must be set before sourcing adapter.sh}"

ACT_ADAPTER_DIR=${ACT_ADAPTER_DIR:-$ACT_ROOT/src/cli}

ACT_ADAPTER_ID=''
ACT_ADAPTER_DISPLAY=''
ACT_ADAPTER_ALIASES=()
ACT_ADAPTER_BINS=()
ACT_ADAPTER_FALLBACK_PATHS=()
ACT_ADAPTER_REAL_ENV=''
ACT_ADAPTER_STRATEGY=''
ACT_ADAPTER_NOTES=''

act::adapter::_drop_hooks() {
    unset -f act::adapter::prepare 2>/dev/null || true
    unset -f act::adapter::args 2>/dev/null || true
    unset -f act::adapter::after 2>/dev/null || true
}

# act::adapter::load <id>
act::adapter::load() {
    local id=$1 file=$ACT_ADAPTER_DIR/$1.adapter
    if [ ! -f "$file" ]; then
        printf 'ai-cli-terminal: no adapter named "%s" (%s)\n' "$id" "$file" >&2
        return 1
    fi

    act::adapter::_drop_hooks
    ACT_ADAPTER_ID=''
    ACT_ADAPTER_DISPLAY=''
    ACT_ADAPTER_ALIASES=()
    ACT_ADAPTER_BINS=()
    ACT_ADAPTER_FALLBACK_PATHS=()
    ACT_ADAPTER_REAL_ENV=''
    ACT_ADAPTER_STRATEGY=''
    ACT_ADAPTER_NOTES=''

    # shellcheck disable=SC1090
    . "$file"

    if [ -z "$ACT_ADAPTER_ID" ] || [ "$ACT_ADAPTER_ID" != "$id" ]; then
        printf 'ai-cli-terminal: adapter file %s declares id "%s"\n' \
            "$file" "${ACT_ADAPTER_ID:-<none>}" >&2
        return 1
    fi
    if [ -z "$ACT_ADAPTER_DISPLAY" ]; then
        printf 'ai-cli-terminal: adapter %s has no display name\n' "$id" >&2
        return 1
    fi
    if [ ${#ACT_ADAPTER_BINS[@]} -eq 0 ]; then
        ACT_ADAPTER_BINS=("$id")
    fi
    if [ -z "$ACT_ADAPTER_STRATEGY" ]; then
        ACT_ADAPTER_STRATEGY='unknown'
    fi
    return 0
}

# act::adapter::load_for <invoked-name>
# Maps `pi`, `qoder-cn`, ... to the adapter that owns them.
act::adapter::load_for() {
    local name=$1 base f id
    if [ -f "$ACT_ADAPTER_DIR/$name.adapter" ]; then
        act::adapter::load "$name"
        return $?
    fi

    # `qoder-cn` -> `qoder`
    base=${name%%-*}
    if [ "$base" != "$name" ] && [ -f "$ACT_ADAPTER_DIR/$base.adapter" ]; then
        act::adapter::load "$base"
        return $?
    fi

    # explicit alias scan (subshell: adapters must not leak state)
    for f in "$ACT_ADAPTER_DIR"/*.adapter; do
        [ -f "$f" ] || continue
        id=$(basename -- "$f" .adapter)
        if (
            # shellcheck disable=SC1090
            . "$f" >/dev/null 2>&1
            case " ${ACT_ADAPTER_ALIASES[*]-} " in
                *" $name "*) exit 0 ;;
            esac
            exit 1
        ); then
            act::adapter::load "$id"
            return $?
        fi
    done

    printf 'ai-cli-terminal: no adapter claims the name "%s"\n' "$name" >&2
    return 1
}

# act::adapter::describe -> stdout, one line, used by status.sh and tests
act::adapter::describe() {
    printf '%s\t%s\t%s\t%s\n' \
        "${ACT_ADAPTER_ID:-?}" \
        "${ACT_ADAPTER_DISPLAY:-?}" \
        "${ACT_ADAPTER_STRATEGY:-?}" \
        "${ACT_ADAPTER_NOTES:-}"
}
