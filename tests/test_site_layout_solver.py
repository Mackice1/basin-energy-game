"""Reference-layout decoder gating and real GLPK/Godot audit regression.

Set BASIN_GLPK to a real glpsol executable (or put it on PATH) to run the
integration tests. No solver substitute is used.
"""
from __future__ import annotations

import copy
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODULE_SPEC = importlib.util.spec_from_file_location("site_layout_solver_under_test", ROOT / "tools/dispatch_solver.py")
backend = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(backend)
layout = backend._SITE_LAYOUT_SUPPORT
SHARED = layout.spec()
PROFILE = layout.SITE_GEOMETRY_PROFILE
GLPK = shutil.which(os.environ.get("BASIN_GLPK", "glpsol"))
GODOT = shutil.which(os.environ.get("BASIN_GODOT", "godot"))


def snapshot(marked=True):
    devices = []
    for ident, kind in enumerate(["wind", "station", "load", "battery_sodium"]):
        item = {"id": ident, "kind": kind, "params": copy.deepcopy(backend.SCHEMA_12_DEFAULTS[kind])}
        if marked:
            item["site_geometry_profile"] = PROFILE
        if kind == "station":
            item["params"].update(capacity_mw=10.0, loss_fraction=0.0)
        if kind == "battery_sodium":
            item["params"]["initial_soc"] = 0.0
            item["state"] = {"energy_mwh": 0.0}
        devices.append(item)
    return {
        "schema_version": 7, "devices": devices,
        "links": [{"from": a, "to": b, "capacity_mw": 10.0, "loss_fraction": 0.0}
                  for a, b in [(0, 1), (1, 2), (1, 3)]],
        "steps": [
            {"time_s": 0.0, "dt_h": 1.0, "available_mw": {"0": 2.0}, "demand_mw": {"2": 0.0}},
            {"time_s": 3600.0, "dt_h": 1.0, "available_mw": {"0": 0.0}, "demand_mw": {"2": 1.0}},
        ],
        "options": {"timeout_s": 30.0}, "grid_capacity_mw": 4.0,
    }


class SiteLayoutDecoderTests(unittest.TestCase):
    def test_legal_marked_snapshot_normalizes_identically_to_unmarked_snapshot(self):
        marked = snapshot()
        before = copy.deepcopy(marked)
        self.assertEqual(backend.normalize(marked), backend.normalize(snapshot(marked=False)))
        self.assertEqual(marked, before)

    def test_unsupported_marked_ratings_reject_before_solver_is_invoked(self):
        item = snapshot()
        item["devices"][3]["params"]["capacity_mwh"] = 60.0
        before = copy.deepcopy(item)
        with self.assertRaisesRegex(backend.InputError, "Site layout support.*capacity_mwh"):
            backend.normalize(item)
        result = backend.solve(item, glpsol="/missing/but-must-not-be-invoked")
        self.assertFalse(result["success"])
        self.assertFalse(result["solver_invoked"])
        self.assertEqual(result["steps"], [])
        self.assertIn("Site layout support", " ".join(result["errors"]))
        self.assertEqual(item, before)

    def test_each_scoped_parameter_is_gated_before_other_decoder_work(self):
        for kind, entry in SHARED["kinds"].items():
            for key, bound in entry["bounds"].items():
                with self.subTest(kind=kind, parameter=key):
                    item = {
                        "id": 7, "kind": kind, "site_geometry_profile": PROFILE,
                        "params": {name: limit["max"] for name, limit in entry["bounds"].items()},
                    }
                    item["params"][key] = math.nextafter(float(bound["max"]), math.inf)
                    request = {"schema_version": 3, "devices": [item], "links": [],
                               "steps": [{"time_s": 0.0, "dt_h": 1.0, "available_mw": {}, "demand_mw": {}}]}
                    with self.assertRaisesRegex(backend.InputError, "Site layout support.*" + key):
                        backend.normalize(request)

    def test_historical_unmarked_oversized_capacity_is_not_silently_restricted(self):
        item = snapshot(marked=False)
        item["devices"][3]["params"]["capacity_mwh"] = 60.0
        before = copy.deepcopy(item)
        self.assertEqual(backend.normalize(item)["nodes"]["3"]["params"]["capacity_mwh"], 60.0)
        self.assertEqual(item, before)

    def test_null_unknown_and_partial_markers_cannot_bypass_the_gate(self):
        for marker in [None, "", "other", False, PROFILE]:
            item = snapshot(marked=False)
            item["devices"][3]["site_geometry_profile"] = marker
            with self.subTest(marker=marker), self.assertRaisesRegex(backend.InputError, "Site layout support"):
                backend.normalize(item)

    def test_marked_devices_require_complete_geometry_parameters(self):
        item = snapshot()
        del item["devices"][0]["params"]["rotor_diameter_m"]
        with self.assertRaisesRegex(backend.InputError, "rotor_diameter_m.*missing"):
            backend.normalize(item)

    def test_marker_is_accepted_by_every_strict_device_field_whitelist(self):
        cases = [
            ("thermal_store", 3), ("high_temp_store", 4), ("steam_generator", 5),
            ("molten_salt_store", 6), ("solid_thermal_store", 7),
            ("hydrogen_gas_store", 8), ("co2_liquid_cycle_store", 9),
            ("collector_substation", 10), ("hydrogen_liquid_store", 11),
            ("ammonia_synthesis_station", 12),
        ]
        for kind, schema in cases:
            item = {"id": 0, "kind": kind, "params": copy.deepcopy(backend.SCHEMA_12_DEFAULTS[kind]),
                    "site_geometry_profile": PROFILE}
            request = {"schema_version": schema, "devices": [item], "links": [],
                       "steps": [{"time_s": 0.0, "dt_h": 1.0, "available_mw": {}, "demand_mw": {},
                                  "weather": {"air_temp_c": 25.0}}]}
            if schema == 11:
                request.update(material_profile=backend.PHASE_PROFILE, material_profile_version=2)
            if schema == 12:
                request.update(material_profile=backend.CHEMICAL_PROFILE, material_profile_version=3)
            with self.subTest(kind=kind):
                self.assertEqual(backend.normalize(request)["nodes"]["0"]["kind"], kind)


@unittest.skipUnless(GLPK, "Reference-layout integration requires a real GLPK executable")
class SiteLayoutRealSolverTests(unittest.TestCase):
    def test_real_marked_solution_matches_legacy_physics_without_mutating_request(self):
        marked = snapshot()
        before = copy.deepcopy(marked)
        reference = backend.solve(marked, glpsol=GLPK)
        legacy = backend.solve(snapshot(marked=False), glpsol=GLPK)
        for result in [reference, legacy]:
            self.assertTrue(result["success"], result)
            self.assertTrue(result["solver_invoked"], result)
            self.assertEqual(result["status"], "optimal", result)
            self.assertTrue(result["validation"]["valid"], result)
        for field in ["steps", "totals", "initial_states", "final_states"]:
            self.assertEqual(reference[field], legacy[field], field)
        self.assertEqual(marked, before)
        self.assertAlmostEqual(reference["steps"][1]["served_mw"], 1.0, delta=2e-6)

    @unittest.skipUnless(GODOT, "Independent cross-language audit also requires Godot")
    def test_same_real_glpk_request_is_independently_audited_by_godot(self):
        request = snapshot()
        result = backend.solve(request, glpsol=GLPK)
        self.assertTrue(result["success"], result)
        self.assertTrue(result["solver_invoked"], result)
        self.assertEqual(result["status"], "optimal", result)
        script = '''extends SceneTree
const M = preload("res://scripts/energy_model.gd")
const Layout = preload("res://scripts/site_layout_support.gd")
func _initialize():
    var request = JSON.parse_string(%s)
    var result = JSON.parse_string(%s)
    var support = Layout.validate_for_model(request.devices)
    var errors = M.Dispatch.audit_optimization_result(request, result)
    var forged = result.duplicate(true)
    forged.steps[0].next_states["3"].energy_mwh += 0.01
    var forged_errors = M.Dispatch.audit_optimization_result(request, forged)
    print("SITE_SOLVER_GODOT_AUDIT ", JSON.stringify({"support": support, "errors": errors,
          "forged_errors": forged_errors}, "", false, true))
    quit(0 if support.operable and errors.is_empty() and not forged_errors.is_empty() else 1)
''' % (json.dumps(json.dumps(request, allow_nan=False)), json.dumps(json.dumps(result, allow_nan=False)))
        with tempfile.TemporaryDirectory(prefix="basin-site-solver-audit-") as directory:
            temp = Path(directory)
            script_path = temp / "audit_site_layout.gd"
            script_path.write_text(script)
            env = os.environ.copy()
            for name in ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
                path = temp / name.lower()
                path.mkdir()
                env[name] = str(path)
            env["GODOT_SILENCE_ROOT_WARNING"] = "1"
            run = subprocess.run([GODOT, "--headless", "--path", str(ROOT), "--script", str(script_path)],
                                 env=env, capture_output=True, text=True, timeout=90)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertNotIn("SCRIPT ERROR", run.stderr, run.stdout + run.stderr)
        lines = [line[len("SITE_SOLVER_GODOT_AUDIT "):]
                 for line in run.stdout.splitlines() if line.startswith("SITE_SOLVER_GODOT_AUDIT ")]
        self.assertEqual(len(lines), 1, run.stdout + run.stderr)
        audit = json.loads(lines[0])
        self.assertTrue(audit["support"]["operable"])
        self.assertEqual(audit["errors"], [])
        self.assertTrue(audit["forged_errors"])


if __name__ == "__main__":
    unittest.main()
