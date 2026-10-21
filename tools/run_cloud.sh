#!/bin/sh
# Portable source launcher; no desktop packaging claim.
# Set BASIN_GLPK to an installed glpsol executable when it is not on PATH.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
export BASIN_GLPK="${BASIN_GLPK:-glpsol}"
export BASIN_PYTHON="${BASIN_PYTHON:-python3}"
if ! command -v "$BASIN_GLPK" >/dev/null 2>&1; then
  printf '%s\n' 'Warning: GLPK is unavailable. Simulation can run; optimization requires glpsol on PATH or BASIN_GLPK=/path/to/glpsol.' >&2
fi
if ! command -v "$BASIN_PYTHON" >/dev/null 2>&1; then
  printf '%s\n' 'Warning: Python is unavailable. Optimization requires Python 3 or BASIN_PYTHON=/path/to/python3.' >&2
fi
exec godot --path "$ROOT" "$@"
