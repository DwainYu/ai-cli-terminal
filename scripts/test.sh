#!/usr/bin/env bash
# Run the layered test suite: unit + integration (terminal/manual checks are
# recorded in docs, not executed here). Safe by construction: tests use a temp
# HOME, never start a real TUI, and only kill processes they started.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
exec bash "$script_dir/../tests/run.sh" "$@"
