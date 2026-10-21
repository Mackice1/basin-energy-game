#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export HOME="${BASIN_TEST_HOME:-/tmp/basin-v13-all-tests}"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export PATH="/workspace/shared/glpk/bin:$PATH"
mkdir -p "$XDG_DATA_HOME"
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
{
bash tests/run_all.sh
python3 -m unittest discover -s tests -p test_dispatch_solver.py -v
godot --headless --path . --script tests/test_optimization_controller.gd
if [ -f tests/test_optimization_panel.gd ]; then godot --headless --path . --script tests/test_optimization_panel.gd; fi
godot --headless --path . --script tests/test_side_dock.gd
godot --headless --path . --script tests/test_speed_control.gd
godot --headless --path . --script tests/test_weather_orb.gd
godot --headless --path . --script tests/test_demand_entry.gd
godot --headless --path . --script tests/test_climate_model.gd
godot --headless --path . --script tests/test_weather_csv.gd
godot --headless --path . --script tests/test_climate_integration.gd
godot --headless --path . --script tests/test_scene_weather.gd

python3 -m unittest discover -s tests -p test_thermal_dispatch_solver.py -v
for thermal_test in runtime save device_ui optimization_ui controller; do
 godot --headless --path . --script "tests/test_thermal_${thermal_test}.gd"
done
for station_test in save facade interior controller; do
 godot --headless --path . --script "tests/test_station_${station_test}.gd"
done
for metric_test in spatial_dimensions metric_controller thermal_glb_visuals metric_wind_groundworks; do
 godot --headless --path . --script "tests/test_${metric_test}.gd"
done
for polish_test in interaction_polish station_interaction_polish visual_annotation_camera station_responsive focus_safety bounded_polish; do
 godot --headless --path . --script "tests/test_${polish_test}.gd"
done

# V17 single-device fuel stage: real runtime, independent shared resource,
# schema migration, rendered-asset contracts and true GLPK/GUI data isolation.
python3 -m unittest discover -s tests -p test_fuel_optimizer.py -v
for fuel_test in catalog_save dispatch controller station visual optimization_ui optimizer_world; do
 godot --headless --path . --script "tests/test_fuel_${fuel_test}.gd"
done
} 2>&1 | tee "$LOG"
if grep -E 'SCRIPT ERROR|Parse Error|FAIL |failures=[1-9]|, [1-9][0-9]* failures$' "$LOG"; then exit 1; fi
