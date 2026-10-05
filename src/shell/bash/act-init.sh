# shellcheck shell=bash
# The block that `scripts/install.sh --apply` writes between markers in the
# user's shell rc file. This file only *renders* it — it never writes anything
# when sourced, so it is safe to source in tests.
#
#   act::init::render <share-dir>
#
# Guarantees (architecture 3.6, D6/D7):
#   - one marker pair, replaced as a whole, never appended twice,
#   - PATH prepend behind a `case ":$PATH:"` membership guard,
#   - the OSC 0 printf lives in act::title::emit only: the block sources the
#     installed title library instead of re-implementing the escape sequence,
#   - everything outside the markers stays untouched.

act::init::begin_marker() { printf '%s\n' '# >>> ai-cli-terminal >>>'; }
act::init::end_marker()   { printf '%s\n' '# <<< ai-cli-terminal <<<'; }

act::init::render() {
    local share=$1
    [ -n "$share" ] || { printf '%s\n' 'act::init::render: missing share dir' >&2; return 1; }

    act::init::begin_marker
    cat <<EOF
# managed by ai-cli-terminal — do not edit by hand;
# change it with scripts/install.sh, remove it with scripts/uninstall.sh.
_act_share="$share"

# wrapper directory first, at most once, no matter how often this file is sourced
if [ -d "\$_act_share/bin" ]; then
    case ":\$PATH:" in
        *":\$_act_share/bin:"*) ;;
        *) PATH="\$_act_share/bin:\$PATH" ;;
    esac
    export PATH
fi

# while no CLI owns the tab, keep it on the current project (AC: project name
# at the prompt). Reuses the single title helper — no second escape sequence.
if [ -r "\$_act_share/src/lib/title.sh" ]; then
    # shellcheck source=/dev/null
    . "\$_act_share/src/lib/title.sh"
    act::prompt::title() {
        case \$- in *i*) ;; *) return 0 ;; esac
        [ -n "\${ACT_NO_PROMPT_TITLE:-}" ] && return 0
        local act_p
        act_p=\$(basename -- "\$PWD" 2>/dev/null) || return 0
        [ -n "\$act_p" ] || return 0
        act::title::emit "\$act_p"
    }
    case ";\${PROMPT_COMMAND:-};" in
        *";act::prompt::title;"*) ;;
        *) PROMPT_COMMAND="act::prompt::title\${PROMPT_COMMAND:+;\$PROMPT_COMMAND}" ;;
    esac
fi
unset _act_share
EOF
    act::init::end_marker
}
