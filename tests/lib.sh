#!/usr/bin/env bash
# Tiny TAP-style assertion helpers. No external dependencies on purpose:
# the test suite has to run on a bare Ubuntu 22.04 with only bash.

T_TOTAL=0
T_FAILED=0

t::_ok() {
    T_TOTAL=$((T_TOTAL + 1))
    printf 'ok %d - %s\n' "$T_TOTAL" "$1"
}

t::_bad() {
    T_TOTAL=$((T_TOTAL + 1))
    T_FAILED=$((T_FAILED + 1))
    printf 'not ok %d - %s\n' "$T_TOTAL" "$1"
    if [ -n "${2-}" ]; then
        printf '#   %s\n' "$2"
    fi
}

# t::eq <expected> <actual> <label>
t::eq() {
    if [ "$1" = "$2" ]; then
        t::_ok "$3"
    else
        t::_bad "$3" "expected: <$1>  actual: <$2>"
    fi
}

# t::ne <not-expected> <actual> <label>
t::ne() {
    if [ "$1" != "$2" ]; then
        t::_ok "$3"
    else
        t::_bad "$3" "did not expect: <$1>"
    fi
}

# t::contains <haystack> <needle> <label>
t::contains() {
    case $1 in
        *"$2"*) t::_ok "$3" ;;
        *) t::_bad "$3" "needle not found: <$2>" ;;
    esac
}

# t::not_contains <haystack> <needle> <label>
t::not_contains() {
    case $1 in
        *"$2"*) t::_bad "$3" "unexpected needle: <$2>" ;;
        *) t::_ok "$3" ;;
    esac
}

# t::status <expected-status> <label> <command...>
t::status() {
    local want=$1 label=$2
    shift 2
    local got=0
    "$@" >/dev/null 2>&1 || got=$?
    if [ "$got" -eq "$want" ]; then
        t::_ok "$label"
    else
        t::_bad "$label" "expected status $want, got $got"
    fi
}

# t::file_contains <file> <needle> <label>
t::file_contains() {
    local text=
    [ -r "$1" ] && text=$(cat "$1")
    t::contains "$text" "$2" "$3"
}

# t::count_in_file <file> <needle> <expected-count> <label>
t::count_in_file() {
    local text= n=0
    [ -r "$1" ] && text=$(cat "$1")
    n=$(printf '%s' "$text" | grep -c -F -- "$2" || true)
    t::eq "$3" "$n" "$4"
}

t::summary() {
    printf '1..%d\n' "$T_TOTAL"
    if [ "$T_FAILED" -ne 0 ]; then
        printf '# FAILED %d of %d\n' "$T_FAILED" "$T_TOTAL"
        exit 1
    fi
    printf '# PASS %d\n' "$T_TOTAL"
    exit 0
}
