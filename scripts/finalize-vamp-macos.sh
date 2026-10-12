#!/usr/bin/env bash
# In this independent repository, legacy names route only to the companion.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/scripts/finalize-vamp-companion.sh" "$@"
