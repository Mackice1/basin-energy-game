"""Finite shared site envelopes, non-mutating validation and runtime parity.

Run from the project root with only the Python standard library:
    python3 -m unittest discover -s tests -p 'test_site_layout_support.py' -v
The cross-language test additionally uses Godot when it is available.
"""
from __future__ import annotations

import copy
import importlib.util
import json
import math
import os
from pathlib import Path
import pickle
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
MODULE_SPEC = importlib.util.spec_from_file_location(
    "site_layout_support_under_test", ROOT / "tools/site_layout_support.py"
)
layout = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(layout)
SHARED = json.loads((ROOT / "data/site_layout_support_v1.json").read_text())
PROFILE = SHARED["site_geometry_profile"]
GODOT = shutil.which(os.environ.get("BASIN_GODOT", "godot"))


def device(kind, ident=7):
    """Use exact specification bounds, never a legacy display/default layout."""
    params = {key: bound["max"] for key, bound in SHARED["kinds"][kind]["bounds"].items()}
    # Rectangle maxima need not form a feasible coupled energy/efficiency pair.
    geometry = SHARED["kinds"][kind]["geometry"]
    if "screening_reference_discharge_efficiency" in geometry:
        params["discharge_efficiency"] = geometry["screening_reference_discharge_efficiency"]
    return {
        "id": ident,
        "kind": kind,
        "site_geometry_profile": PROFILE,
        "params": params,
    }


class SiteLayoutSupportTests(unittest.TestCase):
    def test_one_shared_spec_with_all_scoped_kinds(self):
        self.assertEqual(layout.shared_spec_version(), SHARED["spec_version"])
        self.assertEqual(len(SHARED["kinds"]), 39)
        for kind, spec in SHARED["kinds"].items():
            with self.subTest(kind=kind):
                self.assertEqual(layout.parameter_limits(kind), spec["bounds"])
                result = layout.assess_device(device(kind))
                self.assertEqual(result["spec_id"], SHARED["spec_id"])
                self.assertEqual(result["spec_version"], SHARED["spec_version"])
                self.assertEqual(result["profile_id"], PROFILE)
                self.assertEqual(result["supported_bounds"], spec["bounds"])
                self.assertTrue(result["applicable"])
                self.assertTrue(result["supported"])
                self.assertTrue(result["operable"])
                self.assertFalse(result["needs_migration"])
                self.assertEqual(result["issues"], [])

    def test_parameter_limits_are_independent_copies(self):
        for kind in SHARED["kinds"]:
            limits = layout.parameter_limits(kind)
            if limits:
                first = next(iter(limits))
                limits[first]["max"] = -1
            limits["new_field"] = {}
            self.assertEqual(layout.parameter_limits(kind), SHARED["kinds"][kind]["bounds"])
            self.assertTrue(layout.assess_device(device(kind))["operable"])
        self.assertEqual(layout.parameter_limits("unknown_kind"), {})

    def test_geometry_returns_independent_shared_spec_data(self):
        for kind, spec in SHARED["kinds"].items():
            result = layout.geometry(kind)
            self.assertEqual(result, spec["geometry"])
            result["method"] = "changed"
            if "hardware" in result:
                result["hardware"]["count"] = -1
            self.assertEqual(layout.geometry(kind), spec["geometry"])
        self.assertEqual(layout.geometry("unknown_kind"), {})

    def test_exact_upper_bound_is_inclusive_but_next_float_is_not(self):
        for kind, spec in SHARED["kinds"].items():
            for key, bound in spec["bounds"].items():
                with self.subTest(kind=kind, parameter=key):
                    item = device(kind)
                    item["params"][key] = math.nextafter(float(bound["max"]), math.inf)
                    before = copy.deepcopy(item)
                    result = layout.assess_device(item)
                    self.assertFalse(result["supported"])
                    self.assertFalse(result["operable"])
                    self.assertTrue(result["needs_migration"])
                    self.assertEqual(result["required_geometry"], {})
                    self.assertEqual(result["issues"], [{
                        "code": "outside_supported_range", "parameter": key,
                        "message": "Layout parameter is outside the supported site envelope.",
                        "actual": item["params"][key], "maximum": bound["max"],
                    }])
                    self.assertEqual(item, before)

    def test_lower_bounds_distinguish_capacity_from_zero_rate(self):
        for kind, spec in SHARED["kinds"].items():
            for key, bound in spec["bounds"].items():
                with self.subTest(kind=kind, parameter=key):
                    item = device(kind)
                    item["params"][key] = bound["min"]
                    self.assertEqual(layout.assess_device(item)["supported"], not bound["min_exclusive"])
                    item["params"][key] = math.nextafter(float(bound["min"]), -math.inf)
                    self.assertFalse(layout.assess_device(item)["supported"])

    def test_missing_parameters_are_not_silently_defaulted(self):
        for kind, spec in SHARED["kinds"].items():
            for key in spec["bounds"]:
                with self.subTest(kind=kind, parameter=key):
                    item = device(kind)
                    del item["params"][key]
                    before = copy.deepcopy(item)
                    result = layout.assess_device(item)
                    self.assertEqual(result["issues"], [{
                        "code": "missing_parameter", "parameter": key,
                        "message": "Layout parameter is missing.",
                    }])
                    self.assertFalse(result["operable"])
                    self.assertEqual(item, before)

    def test_nonfinite_bool_and_nonnumeric_values_fail_without_echoing_them(self):
        values = [None, True, False, "1", [], {}, float("nan"), float("inf"), -float("inf")]
        for kind, spec in SHARED["kinds"].items():
            for key in spec["bounds"]:
                for value in values:
                    with self.subTest(kind=kind, parameter=key, value=repr(value)):
                        item = device(kind)
                        item["params"][key] = value
                        before = pickle.dumps(item)
                        result = layout.assess_device(item)
                        self.assertEqual(result["issues"], [{
                            "code": "invalid_parameter", "parameter": key,
                            "message": "Layout parameter must be a finite number.",
                        }])
                        self.assertFalse(result["supported"])
                        self.assertFalse(result["operable"])
                        json.dumps(result, allow_nan=False)
                        self.assertEqual(pickle.dumps(item), before)

    def test_marker_is_explicit_and_does_not_rewrite_parameters(self):
        for kind in SHARED["kinds"]:
            for marker in [None, "", "legacy_illustrative", "flow_process_v2", True, 1]:
                with self.subTest(kind=kind, marker=marker):
                    item = device(kind)
                    if marker is None:
                        del item["site_geometry_profile"]
                    else:
                        item["site_geometry_profile"] = marker
                    before = copy.deepcopy(item)
                    result = layout.assess_device(item)
                    expected = {
                        "code": "profile_migration_required", "parameter": "site_geometry_profile",
                        "message": "Explicit site geometry migration is required; stored ratings and inventory must remain unchanged.",
                    }
                    if isinstance(marker, str):
                        expected["actual"] = marker
                    self.assertEqual(result["issues"], [expected])
                    self.assertTrue(result["supported"])
                    self.assertTrue(result["needs_migration"])
                    self.assertFalse(result["operable"])
                    self.assertTrue(result["required_geometry"])
                    self.assertEqual(item, before)

    def test_nested_or_visual_profile_is_not_a_site_migration_marker(self):
        item = device("solid_thermal_store")
        del item["site_geometry_profile"]
        item["params"].update(site_geometry_profile=PROFILE, visual_geometry_profile=PROFILE)
        result = layout.assess_device(item)
        self.assertTrue(result["needs_migration"])
        self.assertFalse(result["operable"])

    def test_all_issues_follow_bounds_order_then_migration(self):
        for kind, spec in SHARED["kinds"].items():
            item = {"id": "legacy", "kind": kind, "params": {}}
            result = layout.assess_device(item)
            self.assertEqual([issue["parameter"] for issue in result["issues"]],
                             list(spec["bounds"]) + ["site_geometry_profile"])
            self.assertEqual(result["id"], "legacy")

    def test_unsupported_legacy_capacity_is_retained_with_inventory_and_connections(self):
        for kind, spec in SHARED["kinds"].items():
            if "capacity_key" not in spec["geometry"]:
                continue
            item = device(kind, ident="retained-id")
            capacity_key = spec["geometry"]["capacity_key"]
            item["params"][capacity_key] = spec["bounds"][capacity_key]["max"] * 100
            item.update(state={"saved_inventory": 19.3}, x=13.2, z=-5.1,
                        links=[{"from": "retained-id", "to": 2}])
            item.pop("site_geometry_profile")
            before = copy.deepcopy(item)
            result = layout.assess_device(item)
            self.assertFalse(result["supported"])
            self.assertFalse(result["operable"])
            self.assertTrue(result["needs_migration"])
            self.assertEqual(item, before)

    def test_non_target_devices_are_not_certified_or_constrained(self):
        for kind in ["unknown_future_device", "decorative_annotation", "other_unscoped_type"]:
            item = {"kind": kind, "params": "not inspected", "site_geometry_profile": "other"}
            result = layout.assess_device(item)
            self.assertFalse(result["applicable"])
            self.assertTrue(result["supported"])
            self.assertTrue(result["operable"])
            self.assertFalse(result["needs_migration"])
            self.assertEqual(result["required_geometry"], {})
            self.assertEqual(result["supported_bounds"], {})
            self.assertEqual(result["issues"], [])

    def test_invalid_devices_and_kinds_fail_closed(self):
        for item in [None, [], 42, "not a device"]:
            with self.subTest(item=item):
                result = layout.assess_device(item)
                self.assertFalse(result["supported"])
                self.assertTrue(result["applicable"])
                self.assertTrue(result["needs_migration"])
                self.assertFalse(result["operable"])
                self.assertEqual(result["issues"], [{
                    "code": "invalid_device", "parameter": "",
                    "message": "Device must be a dictionary.",
                }])
        for kind in [None, "", 0, False, [], {}]:
            result = layout.assess_device({"kind": kind})
            self.assertFalse(result["operable"])
            self.assertEqual(result["issues"], [{
                "code": "invalid_device_kind", "parameter": "kind",
                "message": "Device kind must be a nonempty string.",
            }])

    def test_invalid_params_do_not_prevent_readable_migration_diagnostics(self):
        for params in [None, False, 5, [], "invalid"]:
            item = device("thermal_store")
            item["params"] = params
            result = layout.assess_device(item)
            self.assertEqual(result["issues"], [{
                "code": "invalid_parameters", "parameter": "params",
                "message": "Device params must be a dictionary.",
            }])
            self.assertFalse(result["operable"])

    def test_additional_non_geometry_parameters_do_not_change_assessment(self):
        for kind in SHARED["kinds"]:
            item = device(kind)
            expected = layout.assess_device(item)
            item["params"].update(site_support_ignored_test_value={"value": 0.25})
            item["state"] = {"inventory": 0.123}
            self.assertEqual(layout.assess_device(item), expected)

    def test_world_aggregation_keeps_individual_issues_unmodified(self):
        valid = device("thermal_store", "water")
        old = device("hydrogen_gas_store", "old-hydrogen")
        old.pop("site_geometry_profile")
        too_big = device("solid_thermal_store", "too-big")
        too_big["params"]["capacity_mwhth"] = 100.0
        items = [valid, old, too_big, {"id": "unscoped", "kind": "unknown_future_device"}]
        before = copy.deepcopy(items)
        result = layout.assess_world(items)
        self.assertFalse(result["supported"])
        self.assertTrue(result["needs_migration"])
        self.assertFalse(result["operable"])
        self.assertEqual(result["profile_id"], PROFILE)
        self.assertEqual(result["spec_version"], SHARED["spec_version"])
        self.assertEqual(result["devices"], [layout.assess_device(item) for item in items])
        self.assertEqual([issue["device_id"] for issue in result["issues"]], ["old-hydrogen", "too-big"])
        self.assertTrue(all("device_id" not in issue
                            for child in result["devices"] for issue in child["issues"]))
        self.assertEqual(items, before)

    def test_empty_and_supported_worlds_are_operable(self):
        for devices in [[], [device(kind) for kind in SHARED["kinds"]]]:
            result = layout.assess_world(devices)
            self.assertTrue(result["supported"])
            self.assertFalse(result["needs_migration"])
            self.assertTrue(result["operable"])
            self.assertEqual(result["issues"], [])

    def test_malformed_worlds_fail_closed(self):
        for devices in [None, {}, (), "devices", 5]:
            result = layout.assess_world(devices)
            self.assertFalse(result["operable"])
            self.assertFalse(result["supported"])
            self.assertTrue(result["needs_migration"])
            self.assertEqual(result["issues"], [{
                "code": "invalid_devices", "parameter": "devices",
                "message": "Devices must be an array.",
            }])

    def test_legacy_model_mode_does_not_reassess_or_mutate_historical_devices(self):
        old = device("thermal_store")
        old.pop("site_geometry_profile")
        old["params"]["capacity_mwhth"] = 4000
        before = copy.deepcopy(old)
        for items in [[], [old]]:
            result = layout.validate_for_model(items)
            self.assertTrue(result["operable"])
            self.assertFalse(result["applied"])
            self.assertEqual(result["mode"], "legacy_compatibility")
            self.assertEqual(result["devices"], [])
        self.assertEqual(old, before)
        self.assertFalse(layout.validate_for_model([old], require_reference=True)["operable"])

    def test_any_marker_opts_the_entire_model_into_strict_reference_validation(self):
        for marker in [None, "", "unknown", True, {}, PROFILE]:
            first = device("thermal_store", 1)
            first["site_geometry_profile"] = marker
            second = device("hydrogen_gas_store", 2)
            second.pop("site_geometry_profile")
            result = layout.validate_for_model([first, second])
            self.assertTrue(result["applied"])
            self.assertEqual(result["mode"], "reference_layout")
            self.assertFalse(result["operable"])
            self.assertTrue(result["needs_migration"])
            self.assertTrue(any(issue.get("device_id") == 2 for issue in result["issues"]))

    def test_required_reference_and_invalid_models_use_strict_results(self):
        for items in [[], [device(kind) for kind in SHARED["kinds"]]]:
            result = layout.validate_for_model(items, require_reference=True)
            self.assertTrue(result["operable"])
            self.assertTrue(result["applied"])
            self.assertEqual(result["mode"], "reference_layout")
        for items in [None, {}, ()]:
            result = layout.validate_for_model(items)
            self.assertFalse(result["operable"])
            self.assertTrue(result["applied"])

    def test_unreadable_or_wrong_version_spec_fails_closed(self):
        with tempfile.TemporaryDirectory(prefix="basin-invalid-layout-spec-") as directory:
            path = Path(directory) / "bad.json"
            for contents in ["not json", "[]", '{"spec_version": 2}', "null"]:
                path.write_text(contents)
                with mock.patch.object(layout, "_cache", {}), mock.patch.object(layout, "SPEC_PATH", path):
                    result = layout.assess_device(device("thermal_store"))
                    self.assertFalse(result["operable"])
                    self.assertEqual(result["issues"][0]["code"], "invalid_spec")


class SiteLayoutNumericalGeometryTests(unittest.TestCase):
    def test_thermal_inventory_uses_material_not_display_size(self):
        expected_mass = {
            "thermal_store": 4.0 * 3.6e9 / (4180.0 * 30.0),
            "high_temp_store": 0.2 * 3.6e9 / 238000.0,
            "molten_salt_store": 0.5 * 3.6e9 / (1500.0 * 275.0),
            "solid_thermal_store": 8.0 * 3.6e9 / (450.0 * 30.0),
        }
        for kind, expected in expected_mass.items():
            result = layout.assess_device(device(kind))["required_geometry"]
            self.assertAlmostEqual(result["required_material_mass_kg"], expected, delta=1e-8)
            self.assertAlmostEqual(result["minimum_installed_material_mass_kg"], expected, delta=1e-8)
            self.assertAlmostEqual(result["required_effective_volume_m3"], expected / result["density_kg_m3"])
            self.assertFalse(result["as_built_verified"])
            self.assertTrue(result["hardware_capacity_sufficient"])

    def test_gas_full_stock_volume_has_no_untracked_heel_or_energy_change(self):
        expected = {
            "hydrogen_gas_store": (1000.0, 14.0),
            "hydrogen_storage_system": (20.0 * 1000.0 / 33.33, 14.0),
            "nitrogen_supply_boundary": (1000.0, 210.0),
            "ammonia_synthesis_station": (200.0, 3.3),
            "co2_supply_boundary": (1000.0, 1.75),
        }
        for kind, (mass, density) in expected.items():
            result = layout.assess_device(device(kind))["required_geometry"]
            self.assertAlmostEqual(result["required_material_mass_kg"], mass)
            self.assertAlmostEqual(result["required_effective_volume_m3"], mass / density)
            self.assertEqual(result["untracked_heel_kg"], 0)
            self.assertTrue(result["hardware_capacity_sufficient"])
            self.assertFalse(result["as_built_verified"])

    def test_operating_derate_never_shrinks_the_installed_geometry(self):
        for kind, entry in SHARED["kinds"].items():
            if entry["geometry"]["method"] == "bounded_existing_layout":
                continue
            item = device(kind)
            key = entry["geometry"]["capacity_key"]
            full = layout.assess_device(item)["required_geometry"]
            item["params"][key] *= 0.25
            lower = layout.assess_device(item)["required_geometry"]
            if "energy_screen_pass" in full:
                self.assertAlmostEqual(lower["required_effective_volume_m3"], full["required_effective_volume_m3"] * 0.25)
                for field in ["hardware_internal_volume_m3", "hardware_effective_volume_m3", "net_electric_screen_mwh", "hardware"]:
                    self.assertEqual(lower[field], full[field], f"{kind}.{field}")
                continue
            self.assertAlmostEqual(lower["required_material_mass_kg"], full["required_material_mass_kg"] * 0.25)
            for field in ["minimum_installed_material_mass_kg", "minimum_installed_effective_volume_m3",
                          "minimum_container_volume_m3", "hardware_internal_volume_m3", "hardware"]:
                self.assertEqual(lower[field], full[field], f"{kind}.{field}")

    def test_two_tanks_duplicate_container_volume_not_material_inventory(self):
        for kind in ["high_temp_store", "molten_salt_store"]:
            result = layout.assess_device(device(kind))["required_geometry"]
            expected = result["minimum_installed_effective_volume_m3"] * 2 / 0.8
            self.assertAlmostEqual(result["minimum_container_volume_m3"], expected)
            self.assertAlmostEqual(result["hardware_internal_volume_m3"], expected)
            self.assertEqual(result["required_material_mass_kg"], result["minimum_installed_material_mass_kg"])

    def test_capsules_include_two_hemispheres_only_once(self):
        for kind in ["hydrogen_gas_store", "hydrogen_storage_system", "nitrogen_supply_boundary",
                     "ammonia_synthesis_station"]:
            result = layout.assess_device(device(kind))["required_geometry"]
            hw = result["hardware"]
            radius, length = hw["internal_radius_m"], hw["straight_length_m"]
            expected = hw["count"] * (math.pi * radius**2 * length + 4 * math.pi * radius**3 / 3)
            self.assertAlmostEqual(result["hardware_internal_volume_m3"], expected)

    def test_undersized_shared_hardware_is_not_falsely_accepted(self):
        changed = layout.spec()
        changed["kinds"]["hydrogen_gas_store"]["geometry"]["hardware"]["count"] = 1
        with mock.patch.object(layout, "_cache", changed):
            result = layout.assess_device(device("hydrogen_gas_store"))
            self.assertFalse(result["supported"])
            self.assertFalse(result["operable"])
            self.assertEqual(result["issues"][0]["code"], "insufficient_spec_geometry")

    def test_bounded_existing_layout_does_not_claim_calculated_material_sizing(self):
        for kind, entry in SHARED["kinds"].items():
            if entry["geometry"]["method"] != "bounded_existing_layout":
                continue
            result = layout.assess_device(device(kind))["required_geometry"]
            self.assertFalse(result["as_built_verified"])
            self.assertNotIn("hardware_capacity_sufficient", result)
            self.assertNotIn("required_material_mass_kg", result)


@unittest.skipUnless(GODOT, "Cross-language layout parity requires the Godot executable")
class SiteLayoutRuntimeParityTests(unittest.TestCase):
    def assert_equivalent(self, actual, expected, location="result"):
        if isinstance(expected, dict):
            self.assertIsInstance(actual, dict, location)
            self.assertEqual(set(actual), set(expected), location)
            for key in expected:
                self.assert_equivalent(actual[key], expected[key], location + "." + key)
        elif isinstance(expected, list):
            self.assertIsInstance(actual, list, location)
            self.assertEqual(len(actual), len(expected), location)
            for index, value in enumerate(expected):
                self.assert_equivalent(actual[index], value, f"{location}[{index}]")
        elif isinstance(expected, (int, float)) and not isinstance(expected, bool):
            self.assertIsInstance(actual, (int, float), location)
            self.assertTrue(math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-9),
                            f"{location}: {actual!r} != {expected!r}")
        else:
            self.assertEqual(actual, expected, location)

    def test_same_finite_inputs_match_gdscript_device_and_world_assessments(self):
        cases = [None, [], {"kind": []}, {"kind": ""}, {"kind": "unknown_future_device"}]
        for kind, spec in SHARED["kinds"].items():
            item = device(kind, ident=kind)
            cases.append(item)
            old = copy.deepcopy(item)
            old.pop("site_geometry_profile")
            cases.append(old)
            for key, bound in spec["bounds"].items():
                for value in [bound["min"], float(bound["max"]) + 1.0, True, "1", None]:
                    altered = copy.deepcopy(item)
                    altered["params"][key] = value
                    cases.append(altered)
            missing = copy.deepcopy(item)
            missing["params"] = {}
            cases.append(missing)
            bad_params = copy.deepcopy(item)
            bad_params["params"] = None
            cases.append(bad_params)
        unmarked = device("thermal_store")
        unmarked.pop("site_geometry_profile")
        null_marker = device("thermal_store")
        null_marker["site_geometry_profile"] = None
        mode_cases = [None, {}, [], [None], [unmarked], [device("thermal_store")],
                      [null_marker], [unmarked, device("hydrogen_gas_store")]]
        script = '''extends SceneTree
const Layout = preload("res://scripts/site_layout_support.gd")
func _initialize():
    var cases = JSON.parse_string(%s)
    var assessments: Array = []
    for item in cases:
        assessments.append(Layout.assess_device(item))
    var model_cases = JSON.parse_string(%s)
    var modes: Array = []
    for model in model_cases:
        modes.append(Layout.validate_for_model(model))
        modes.append(Layout.validate_for_model(model, true))
    var output = {"devices": assessments, "world": Layout.assess_world(cases), "modes": modes}
    print("PYTHON_SITE_PARITY ", JSON.stringify(output, "", false, true))
    quit(0)
''' % (json.dumps(json.dumps(cases, allow_nan=False)), json.dumps(json.dumps(mode_cases, allow_nan=False)))
        with tempfile.TemporaryDirectory(prefix="basin-site-layout-parity-") as directory:
            temp = Path(directory)
            script_path = temp / "site_layout_parity.gd"
            script_path.write_text(script)
            env = os.environ.copy()
            for name in ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
                path = temp / name.lower()
                path.mkdir()
                env[name] = str(path)
            env["GODOT_SILENCE_ROOT_WARNING"] = "1"
            run = subprocess.run(
                [GODOT, "--headless", "--path", str(ROOT), "--script", str(script_path)],
                env=env, text=True, capture_output=True, timeout=90,
            )
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertNotIn("SCRIPT ERROR", run.stderr, run.stdout + run.stderr)
        lines = [line[len("PYTHON_SITE_PARITY "):]
                 for line in run.stdout.splitlines() if line.startswith("PYTHON_SITE_PARITY ")]
        self.assertEqual(len(lines), 1, run.stdout + run.stderr)
        expected = {"devices": [layout.assess_device(item) for item in cases],
                    "world": layout.assess_world(cases),
                    "modes": [layout.validate_for_model(model, force)
                              for model in mode_cases for force in [False, True]]}
        self.assert_equivalent(json.loads(lines[0]), expected)


if __name__ == "__main__":
    unittest.main()
