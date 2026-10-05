#!/usr/bin/env bash
# ai-cli-terminal test runner.
#
#   tests/run.sh              run unit + integration
#   tests/run.sh unit         only tests/unit
#   tests/run.sh integration  only tests/integration
#   tests/run.sh <file>       a single test file
#
# Rules honoured by everything below:
#   * no real AI CLI is ever started here
#   * no user file is ever touched (integration tests use a temp HOME)
#   * each test file runs in its own bash process

set -u

TESTS_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$TESTS_DIR/.." && pwd)

suites=("$@")
if [ ${#suites[@]} -eq 0 ]; then
    suites=(unit integration)
fi

total_files=0
failed_files=0
failed_names=()

for suite in "${suites[@]}"; do
    if [ -f "$suite" ]; then
        files=("$suite")
    else
        files=()
        while IFS= read -r f; do
            files+=("$f")
        done < <(find "$TESTS_DIR/$suite" -name 'test_*.sh' -type f 2>/dev/null | sort)
    fi

    if [ ${#files[@]} -eq 0 ]; then
        printf '## %s: no tests found\n' "$suite"
        continue
    fi

    for file in "${files[@]}"; do
        total_files=$((total_files + 1))
        printf '## %s\n' "${file#"$REPO_ROOT"/}"
        if REPO_ROOT="$REPO_ROOT" TESTS_DIR="$TESTS_DIR" bash "$file"; then
            :
        else
            failed_files=$((failed_files + 1))
            failed_names+=("${file#"$REPO_ROOT"/}")
        fi
        printf '\n'
    done
done

printf '# ==================================================\n'
printf '# test files: %d   failed: %d\n' "$total_files" "$failed_files"
if [ "$failed_files" -ne 0 ]; then
    for name in "${failed_names[@]}"; do
        printf '#   FAILED %s\n' "$name"
    done
    exit 1
fi
printf '# ALL GREEN\n'
