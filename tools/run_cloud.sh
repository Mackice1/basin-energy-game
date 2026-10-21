#!/bin/sh
# Cloud-tested source launcher; no desktop packaging claim.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
export BASIN_GLPK="${BASIN_GLPK:-/workspace/shared/glpk/bin/glpsol}"
export BASIN_PYTHON="${BASIN_PYTHON:-python3}"
exec godot --path "$ROOT" "$@"
