#!/usr/bin/env bash
# Real-environment validation on WSL — manual layer (never run by tests/run.sh:
# it starts real TUIs). See tests/manual/README.md.
#
#   ./tests/manual/wsl/validate.sh          # all four project+CLI pairs
#   ./tests/manual/wsl/validate.sh pi       # a single wrapper bin name
set -euo pipefail
dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
if [ $# -gt 0 ]; then
    exec python3 "$dir/validate.py" --only "$@"
fi
exec python3 "$dir/validate.py"
