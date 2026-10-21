#!/usr/bin/env bash
# Interactive X11 mouse/key driver; JSON lines on stdin. No simulation shortcuts.
set -euo pipefail
cd "$(dirname "$0")/.."
NUM=${POLISH_DISPLAY:-139}
Xorg :"$NUM" -config "$PWD/evidence/polish/performance/xorg_perf.conf" -listen tcp -nolisten unix -ac -noreset -logfile "/tmp/polish_native_${NUM}_xorg.log" >"/tmp/polish_native_${NUM}_xorg_out.log" 2>&1 &
XPID=$!
GPID=''
cleanup() { if [[ -n "$GPID" ]]; then kill "$GPID" 2>/dev/null || true; wait "$GPID" 2>/dev/null || true; fi; kill "$XPID" 2>/dev/null || true; wait "$XPID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 1
export DISPLAY="127.0.0.1:$NUM" HOME="/tmp/basin-polish-native-$NUM" LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=4
export XDG_DATA_HOME="$HOME/data" XDG_CONFIG_HOME="$HOME/config" XDG_CACHE_HOME="$HOME/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
godot --audio-driver Dummy --path . --script tests/capture_solar_native.gd >"/tmp/polish_native_${NUM}_godot.log" 2>&1 &
GPID=$!
sleep 10
python3 tests/native_solar_driver.py
