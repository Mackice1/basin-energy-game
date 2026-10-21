#!/bin/bash
cd /workspace/scratch/5fdfb85401e4/energy_ui_v22_20261020/source/Basin02
export HOME=/tmp/basin-v22-gui XDG_DATA_HOME=/tmp/basin-v22-gui/data XDG_CONFIG_HOME=/tmp/basin-v22-gui/config XDG_CACHE_HOME=/tmp/basin-v22-gui/cache
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
export BASIN_GLPK=/workspace/shared/glpk/bin/glpsol
export PATH=/workspace/shared/glpk/bin:$PATH
godot --audio-driver Dummy --path . --script tests/capture_ui_v22.gd > evidence/ui_v22/gui_final.log 2>&1
