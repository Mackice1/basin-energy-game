#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
export HOME="${BASIN_TEST_HOME:-/tmp/basin-isolated-tests}"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$XDG_DATA_HOME"
for t in test_energy_model test_series_import test_save_validator test_equipment_visual test_equipment_polish test_construction_feedback test_controller_review test_controller_edges test_parameter_form test_visual_ui test_wind_curve test_wind_curve_audit test_storage_controller test_storage_save test_storage_save_restore test_storage_parameters test_storage_visuals test_network_dispatch test_blender_equipment; do
 godot --headless --path . --script "tests/$t.gd"
done
godot --headless --path . -- --game-self-test
