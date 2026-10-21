# V23 validation provenance / 验证来源

Date: 2026-10-21. V23 extends the published [V22 baseline](https://github.com/Mackice1/basin-energy-game/tree/b06d64f85271a3a568205c89b146bc1e2cd35e71). This document records the original V23 acceptance results and the separate checks made while preparing the public source. It does not claim a new test run or certification of every historical test.

## Original targeted regression

The original V23 acceptance used Godot 4.6.3 and recorded **20 targeted suites, 37,700 assertions, zero failures**. The table below is transcribed from the original package's `regression_summary.json` and checked against its individual test logs. Runtime logs, private/local state snapshots, telemetry and screenshots are intentionally not published.

| Test script under `tests/` | Assertions | Failures |
| --- | ---: | ---: |
| `test_analysis_windows_v22.gd` | 142 | 0 |
| `test_camera_drag_v23.gd` | 21 | 0 |
| `test_device_entry_v23.gd` | 107 | 0 |
| `test_device_inspector_v23.gd` | 1,021 | 0 |
| `test_energy_model.gd` | 12,546 | 0 |
| `test_equipment_v22.gd` | 47 | 0 |
| `test_focus_safety.gd` | 556 | 0 |
| `test_fuel_station.gd` | 117 | 0 |
| `test_interaction_polish.gd` | 106 | 0 |
| `test_network_dispatch.gd` | 17,911 | 0 |
| `test_rankine_world_ui.gd` | 66 | 0 |
| `test_station_controller.gd` | 436 | 0 |
| `test_station_interaction_polish.gd` | 80 | 0 |
| `test_station_interior.gd` | 114 | 0 |
| `test_station_navigation_v23.gd` | 20 | 0 |
| `test_station_save.gd` | 598 | 0 |
| `test_thermal_device_ui.gd` | 3,340 | 0 |
| `test_tower_world_ui.gd` | 44 | 0 |
| `test_visual_annotation_camera.gd` | 318 | 0 |
| `test_workspace_ui_v22.gd` | 110 | 0 |
| **Total: 20 suites** | **37,700** | **0** |

Assertions are checks, not distinct features: the device inspector suite includes all 21 device types in metric and legacy illustrative dimensions plus framing checks. The historic selection-drag tests now explicitly enter Move mode before checking device movement; transaction, undo and cancellation assertions remain.

## Original native GUI verification

The original native desktop run verified left-drag camera movement without changing complete simulation state or selection; camera/state/selection isolation when dragging from UI; a subsequent click selecting a photovoltaic device; the actual entry button opening the secondary page; and return preserving state, camera and selection. The simulation clock advanced from approximately 303.33 to 314.92 seconds while details were open, with real power values refreshing from the main simulation.

Actual Godot-rendered captures covered 1440×900 and 1024×768, several electrical and thermal devices, original thermal/tower station interiors, connections, and model boundaries. This records what was checked in the original V23 run. It is not a claim that every GUI path, desktop platform or exported build was tested. The public source contains the isolated capture script, not its screenshots or recorded runtime state.

## Physics and runtime asset identity

Public preparation independently compared source files and hashes. Only `scripts/device_inspector.gd` (new), `scripts/map.gd`, `scripts/station_interior.gd` and `scripts/world_game.gd` changed among game scripts. Updated/new tests and UID metadata accompany those changes. The core scripts below are byte-identical in the original V22 source, original V23 source, public V22 baseline and public V23 copy:

| Core script / catalog | SHA-256 |
| --- | --- |
| `scripts/energy_model.gd` | `6add3fef45ba4ecbb5899a4afde00c7d3b02e3607f0a3eaec3992af17765f372` |
| `scripts/device_catalog.gd` | `c0cf3ca2798f622056baa2a0ff8d07cba536826793969a0335afb56f033977d3` |
| `scripts/network_dispatch.gd` | `73755a4d56eac854b2bf3d9ac5e5be093bc472f7f033bf9add6c3be5783f20db` |
| `scripts/thermal_dispatch.gd` | `9a77899534848b586ffdee7c9c8e83e5b7ec8576ee7b2499da4aa4ad70a8e785` |
| `scripts/rankine_cycle.gd` | `2129cbeb8173c563dc33777cc8e86821f0c13a4b7607dec3b6ab6ee4d7d4eece` |
| `scripts/solar_tower_thermal.gd` | `7263778a7ec52340adfdf1ec7e3f0e1d1215db249d805b265305acfbc233ded4` |
| `scripts/high_temp_thermal.gd` | `c7c5eabe0da9f5659133c97975f0320aff4a6e3a6cc2fca023fb9f6781573fd7` |
| `scripts/solar_thermal.gd` | `82ef1ac9ee507837bc3bfba084fcb1d5a628dc446d06b52f478286421eae7cd5` |
| `scripts/fuel_supply.gd` | `b26114fda920f956e18648abac856f225e58d8829715c2ad45ae9cbc4a76f713` |

All files under `addons/`, `assets/`, `generated/`, `art_source/`, `config/` and `third_party/`, together with `project.godot`, `main.tscn`, templates and solver tools, remain byte-identical to public V22. Public staging does not modify executable source: every V23 game/test script and UID is copied byte-for-byte from the accepted V23 source. Existing safe V22 synthetic GLPK fixtures and asset-hash receipts remain unchanged. No new project license is added.

## Reproduction and boundaries

Use the root README's Godot/dependency setup. After the first project import, each listed suite can be run from the repository root with:

```sh
godot --headless --editor --path . --import --quit
godot --headless --path . --script tests/test_camera_drag_v23.gd
```

Replace the final script with another listed suite. This is a reproduction example, not a claim that these commands were rerun during publication. Several historical tests have environment-specific prerequisites; inspect each before running. The original V23 targeted run did not rerun all earlier suites or all Python/GLPK tests. Earlier V22 figures remain [historical baseline results](VALIDATION_V22.md), not additional V23 passes.

For the optional native capture workflow, run `tests/capture_v23.gd` in a graphical session after import. Its generated files go to `evidence/v23/`, whose empty directory marker is retained; those outputs are ignored and should be reviewed before any future publication. The capture helper stays open for native input checks. It constructs an isolated synthetic scene, not a player save.

Terrain image-loading/export warnings and the prototype's physical/model boundaries remain. No cross-platform package or industrial engineering validity is certified. See the [V23 functional guide](NAVIGATION_DEVICE_DETAILS_V23_ZH.md) and [publication notes](PUBLICATION_NOTES.md).
