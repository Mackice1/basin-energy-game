"""Fixed air-storage volume screens, real GLPK parity and independent Godot audit."""
import copy
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_site_layout_solver import backend, layout, GLPK, GODOT, ROOT, snapshot

KINDS = ("caes_aboveground", "liquid_air_store")

def device(kind):
    return {"id": 3, "kind": kind, "params": copy.deepcopy(backend.SCHEMA_12_DEFAULTS[kind]),
            "site_geometry_profile": layout.SITE_GEOMETRY_PROFILE, "state": {"energy_mwh": 0.0}}

def request(kind, marked=True, small_high_eta=False):
    result = snapshot(marked=marked)
    item = device(kind)
    if not marked:
        item.pop("site_geometry_profile")
    if small_high_eta:
        item["params"]["capacity_mwh"] *= .5
        item["params"]["discharge_efficiency"] = 1.0
    result["devices"][3] = item
    result["steps"][1]["demand_mw"]["2"] = .04 if kind == "caes_aboveground" else .4
    return result

class AirStorageStaticScreenTests(unittest.TestCase):
    def test_default_stock_and_output_are_not_replaced_by_reference_fluid_states(self):
        for kind in KINDS:
            item = device(kind)
            before = copy.deepcopy(item)
            r = layout.assess_device(item)
            self.assertTrue(r["operable"])
            g = r["required_geometry"]
            self.assertEqual(g["requested_net_electric_mwh"], item["params"]["capacity_mwh"] * item["params"]["discharge_efficiency"])
            self.assertFalse(g["screen_is_performance_guarantee"])
            self.assertFalse(g["pressure_is_simulated"])
            self.assertFalse(g["soc_is_pressure_or_liquid_level"])
            self.assertEqual(g["external_heat_credit_mwh"], 0)
            self.assertEqual(item, before)

    def test_caes_integrated_no_heat_work_matches_closed_form(self):
        g = layout.required_geometry("caes_aboveground", device("caes_aboveground")["params"])
        gamma, ratio = 1.4, 1/50
        volume = 4 * math.pi * .8**2 * 13
        # Integrate ideal turbine work over released normalized mass, not pV alone.
        minimum_mass_fraction = ratio**(1/gamma)
        n = 20000
        dx = (1-minimum_mass_fraction)/n
        integral = math.fsum(((minimum_mass_fraction+(i+.5)*dx)**(gamma-1)-ratio**((gamma-1)/gamma))*dx for i in range(n))
        work = gamma/(gamma-1)*50e5*volume*integral/3.6e9
        self.assertAlmostEqual(work, g["ideal_adiabatic_no_reheat_mwh"], delta=1e-9)
        self.assertLess(g["ideal_adiabatic_no_reheat_mwh"], g["ideal_isothermal_availability_mwh"])
        self.assertAlmostEqual(g["net_electric_screen_mwh"], .19972593183091922, delta=1e-13)

    def test_liquid_screen_uses_actual_liquid_fill_and_net_not_internal_energy(self):
        g = layout.required_geometry("liquid_air_store", device("liquid_air_store")["params"])
        liquid_volume = 2 * math.pi * 1.7**2 * 7 * .8
        self.assertAlmostEqual(g["hardware_effective_volume_m3"], liquid_volume)
        self.assertAlmostEqual(g["reference_maximum_liquid_mass_kg"], liquid_volume*872.08)
        self.assertAlmostEqual(g["net_electric_screen_mwh"], liquid_volume*872.08*300/3.6e6)
        self.assertEqual(g["required_liquid_mass_kg"], 62400)
        self.assertEqual(g["net_specific_output_screen_kj_kg"], 300)
        self.assertEqual(g["literature_modeled_net_output_kj_kg"], 390)

    def test_internal_cylinders_fit_outer_silhouettes_without_crediting_heads(self):
        for kind in KINDS:
            g = layout.geometry(kind)
            self.assertLess(g["hardware"]["internal_radius_m"], g["outer_radius_m"])
            self.assertLess(g["hardware"]["straight_length_m"], g.get("outer_total_height_m", g.get("outer_total_length_m")))
            self.assertFalse(g["hardware"]["end_head_volume_counted"])

    def test_exact_coupled_boundary_and_adjacent_float(self):
        for kind in KINDS:
            item = device(kind)
            limit = layout.assess_device(item)["required_geometry"]["net_electric_screen_mwh"]
            item["params"]["discharge_efficiency"] = 1
            for value, supported in [(math.nextafter(limit, -math.inf), True), (limit, True), (math.nextafter(limit, math.inf), False)]:
                item["params"]["capacity_mwh"] = value
                r = layout.assess_device(item)
                self.assertEqual(r["operable"], supported, (kind, value, r))
                if not supported:
                    self.assertEqual(r["issues"][0]["code"], "energy_screen_exceeded")

    def test_high_eta_requires_smaller_capacity_not_a_global_eta_cap(self):
        for kind in KINDS:
            item = device(kind)
            item["params"]["discharge_efficiency"] = 1
            self.assertFalse(layout.assess_device(item)["operable"])
            item["params"]["capacity_mwh"] *= .5
            self.assertTrue(layout.assess_device(item)["operable"])

    def test_new_decoder_rejects_before_glpk_but_legacy_is_not_rewritten(self):
        for kind in KINDS:
            old = request(kind, marked=False)
            old["devices"][3]["params"]["discharge_efficiency"] = 1
            before = copy.deepcopy(old)
            backend.normalize(old)
            self.assertEqual(old, before)
            new = copy.deepcopy(old)
            for item in new["devices"]:
                item["site_geometry_profile"] = layout.SITE_GEOMETRY_PROFILE
            result = backend.solve(new, glpsol="/must/not/run")
            self.assertFalse(result["success"])
            self.assertFalse(result["solver_invoked"])
            self.assertIn("Capacity times discharge efficiency", " ".join(result["errors"]))

    @unittest.skipUnless(GODOT, "Godot required")
    def test_all_godot_specialized_cases_match_python(self):
        with tempfile.TemporaryDirectory(prefix="air-screen-godot-") as directory:
            env = isolated_env(Path(directory))
            run = subprocess.run([GODOT, "--headless", "--path", str(ROOT), "--script", "tests/test_air_storage_capacity_geometry.gd"], env=env, text=True, capture_output=True, timeout=90)
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        self.assertNotIn("SCRIPT ERROR", run.stderr)
        data = json.loads(next(line[len("AIR_SCREEN_CASES "):] for line in run.stdout.splitlines() if line.startswith("AIR_SCREEN_CASES ")))
        for case in data:
            compare(self, case["result"], layout.assess_device(case["device"]))


def isolated_env(root):
    env = os.environ.copy()
    for key in ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
        path = root/key; path.mkdir()
        env[key] = str(path)
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    return env


def compare(test, a, b):
    if isinstance(b, dict):
        test.assertEqual(set(a), set(b))
        for key in b: compare(test, a[key], b[key])
    elif isinstance(b, list):
        test.assertEqual(len(a), len(b))
        for x,y in zip(a,b): compare(test,x,y)
    elif isinstance(b, (int,float)) and not isinstance(b,bool):
        test.assertTrue(math.isclose(a,b,rel_tol=2e-13,abs_tol=1e-12), (a,b))
    else: test.assertEqual(a,b)


@unittest.skipUnless(GLPK and GODOT, "Real GLPK and Godot required")
class AirStorageActualSolverTests(unittest.TestCase):
    def test_legal_default_and_small_high_eta_solve_identically_and_audit_in_godot(self):
        for kind in KINDS:
            for small in [False,True]:
                with self.subTest(kind=kind, small_high_eta=small):
                    original = request(kind,small_high_eta=small)
                    saved = copy.deepcopy(original)
                    result = backend.solve(original,glpsol=GLPK)
                    legacy = backend.solve(request(kind,marked=False,small_high_eta=small),glpsol=GLPK)
                    self.assertTrue(result["success"],result)
                    self.assertTrue(result["validation"]["valid"],result)
                    self.assertEqual(result["status"],"optimal")
                    for field in ["steps","totals","initial_states","final_states"]:
                        self.assertEqual(result[field],legacy[field])
                    self.assertGreater(result["steps"][1]["served_mw"],0)
                    self.assertEqual(original,saved)
                    script = '''extends SceneTree
const M=preload("res://scripts/energy_model.gd")
const S=preload("res://scripts/site_layout_support.gd")
func _initialize():
 var request=JSON.parse_string(%s)
 var result=JSON.parse_string(%s)
 var errors=M.Dispatch.audit_optimization_result(request,result)
 var forged=result.duplicate(true)
 forged.steps[0].next_states["3"].energy_mwh+=.01
 var forged_errors=M.Dispatch.audit_optimization_result(request,forged)
 print("AIR_SOLVER_AUDIT ",JSON.stringify({"errors":errors,"forged_errors":forged_errors}))
 quit(0 if S.validate_for_model(request.devices).operable and errors.is_empty() and not forged_errors.is_empty() else 1)
''' % (json.dumps(json.dumps(original)),json.dumps(json.dumps(result)))
                    with tempfile.TemporaryDirectory(prefix="air-capacity-real-audit-") as directory:
                        root=Path(directory);path=root/"audit.gd";path.write_text(script)
                        run=subprocess.run([GODOT,"--headless","--path",str(ROOT),"--script",str(path)],env=isolated_env(root),text=True,capture_output=True,timeout=90)
                    self.assertEqual(run.returncode,0,run.stdout+run.stderr)
                    self.assertNotIn("SCRIPT ERROR",run.stderr)
