# ai-cli-terminal — title primitives
#
# The only place in this project that knows what an OSC 0 sequence looks like.
# Source this file; never duplicate `printf '\033]0;...'` anywhere else.
#
# Title rules:
#   * payload is sanitized: C0 control characters and BEL would break or be
#     swallowed by the terminal, so they are removed;
#   * UTF-8 is passed through untouched (Chinese, accents, unicode paths);
#   * the sequence is written to the controlling terminal, never to a
#     redirected stdout, unless a test hook says otherwise.
#
# shellcheck shell=bash

# Separator between project name and CLI name: " · " (U+00B7 MIDDLE DOT).
: "${ACT_TITLE_SEPARATOR:= · }"

# act::title::sanitize <text> -> stdout
# Removes characters that must never appear inside an OSC payload.
act::title::sanitize() {
    local s=${1-}
    s=${s//$'\x1b'/} # ESC  — would start a new escape sequence
    s=${s//$'\x07'/} # BEL  — would terminate the OSC early
    s=${s//$'\r'/}   # CR
    s=${s//$'\n'/}   # LF
    s=${s//$'\t'/}   # TAB
    s=${s//$'\x0b'/} # VT
    s=${s//$'\x0c'/} # FF
    printf '%s' "$s"
}

# act::title::format <project-name> <cli-name> -> stdout
# The single title formula of this project: "<project> · <cli>".
act::title::format() {
    local project cli
    project=$(act::title::sanitize "${1-}")
    cli=$(act::title::sanitize "${2-}")
    printf '%s%s%s' "$project" "$ACT_TITLE_SEPARATOR" "$cli"
}

# act::title::emit <title>
# Writes OSC 0 (ESC ] 0 ; <title> BEL).
#
# Destination order:
#   1. $ACT_TITLE_SINK        append raw bytes to a file (tests / debugging)
#   2. $ACT_TITLE_TARGET      "stdout" forces stdout (tests, scripts without tty)
#   3. /dev/tty               the controlling terminal
#   4. stdout                 fallback when there is no terminal at all
act::title::emit() {
    local title seq
    title=$(act::title::sanitize "${1-}")
    printf -v seq '\033]0;%s\a' "$title"

    if [ -n "${ACT_TITLE_SINK-}" ]; then
        printf '%s' "$seq" >>"$ACT_TITLE_SINK"
        return 0
    fi
    if [ "${ACT_TITLE_TARGET-}" = "stdout" ]; then
        printf '%s' "$seq"
        return 0
    fi
    if { printf '%s' "$seq" >/dev/tty; } 2>/dev/null; then
        return 0
    fi
    printf '%s' "$seq"
    return 0
}

# act::title::restore <project-name>
# What the tab shows once the CLI is gone: the project alone.
act::title::restore() {
    act::title::emit "$(act::title::sanitize "${1-}")"
}
