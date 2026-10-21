"""Schema-7 storage: real GLPK conservation, routing and adversarial report tests.

Run from the project root with glpsol on PATH:
    python3 -m unittest discover -s tests -p 'test_expanded_storage_optimizer.py' -v
Only standard-library modules are required. Integration tests require real GLPK.
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
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("expanded_storage_backend", ROOT / "tools/dispatch_solver.py")
backend = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backend)
GLPK = shutil.which(os.environ.get("BASIN_GLPK", "glpsol"))
EPS = 2e-6
NEW_ELECTRIC = ("battery_sodium", "battery_flow", "caes_aboveground", "liquid_air_store", "hydrogen_storage_system")
NEW_STORAGE = NEW_ELECTRIC + ("solid_thermal_store",)
EXPECTED_DEFAULTS = {
    "battery_sodium": (6., 2., 2., .92, .92, .0001, 0.),
    "battery_flow": (12., 2., 2., .85, .85, .0002, 0.),
    "caes_aboveground": (.25, .1, .1, .75, .70, .002, 0.),
    "liquid_air_store": (8., 2., 1., .70, .65, .002, 0.),
    "hydrogen_storage_system": (20., 2., 1., .65, .50, .0001, 0.),
    "solid_thermal_store": (8., 2., 1., .95, .95, .001, 0.),
}


def device(ident, kind, params=None, energy=None):
    result = {"id": ident, "kind": kind, "params": params or {}}
    if kind in backend.THERMAL_KINDS:
        result.update(model_profile=backend.rankine_profile(kind), model_profile_version=1)
    if energy is not None:
        result["state"] = {"energy_mwhth" if kind in backend.THERMAL_STORAGE_KINDS else "energy_mwh": energy}
    return result


def cable(source, target, capacity=10., loss=0., auxiliary=False):
    result = {"from": source, "to": target, "capacity_mw": capacity, "loss_fraction": loss}
    if auxiliary:
        result.update(from_port="out", to_port="ac_in", carrier="electricity_ac", unit="MW")
    return result


def heat_line(source, target, source_kind, target_kind, capacity=10.):
    fp, tp, grade = backend.THERMAL_ROUTES[(source_kind, target_kind)]
    return {"from": source, "to": target, "from_port": fp, "to_port": tp,
            "carrier": "heat_water", "unit": "MWth", "grade_id": grade,
            "capacity_mwth": capacity, "loss_fraction": 0.}


def step(generation=0., demand=0., time=0., dt=1.):
    return {"time_s": time, "dt_h": dt, "available_mw": {"0": generation}, "demand_mw": {"2": demand}}


def electric_case(kind="hydrogen_storage_system", params=None, energy=None):
    return {"schema_version": 7,
            "devices": [device(0, "wind"), device(1, "station", {"capacity_mw": 10., "loss_fraction": 0.}),
                        device(2, "load"), device(3, kind, params, energy)],
            "links": [cable(0, 1), cable(1, 2), cable(1, 3)],
            "steps": [step(.1, 0.), step(0., 1., 3600.)],
            "options": {"timeout_s": 30.}, "grid_capacity_mw": 4.}


def solid_case(params=None, energy=None):
    return {"schema_version": 7,
            "devices": [device(0, "wind"), device(1, "station", {"capacity_mw": 10., "loss_fraction": 0.}),
                        device(2, "electric_boiler"), device(3, "solid_thermal_store", params, energy),
                        device(4, "heat_exchanger"), device(5, "heat_demand")],
            "links": [cable(0, 1), cable(1, 2, auxiliary=True),
                      heat_line(2, 3, "electric_boiler", "solid_thermal_store"),
                      heat_line(3, 4, "solid_thermal_store", "heat_exchanger"),
                      heat_line(4, 5, "heat_exchanger", "heat_demand")],
            "steps": [{"time_s": 0., "dt_h": 1., "available_mw": {"0": 1.}, "demand_mw": {}, "heat_demand_mwth": {"5": 0.}},
                      {"time_s": 3600., "dt_h": 1., "available_mw": {"0": 0.}, "demand_mw": {}, "heat_demand_mwth": {"5": 1.}}],
            "options": {"timeout_s": 30.}}


class ExpandedStorageInputTests(unittest.TestCase):
    def case(self, kind, **kwargs):
        return solid_case(**kwargs) if kind == "solid_thermal_store" else electric_case(kind, **kwargs)

    def test_exact_defaults_and_unchanged_lithium_fields(self):
        for kind, values in EXPECTED_DEFAULTS.items():
            with self.subTest(kind=kind):
                params = backend.normalize(self.case(kind))["nodes"]["3"]["params"]
                power, energy = ("mwth", "mwhth") if kind == "solid_thermal_store" else ("mw", "mwh")
                keys = (f"capacity_{energy}", f"charge_{power}", f"discharge_{power}", "charge_efficiency",
                        "discharge_efficiency", "self_discharge_per_h", "initial_soc")
                self.assertEqual(tuple(params[key] for key in keys), values)
                self.assertEqual(backend.normalize(self.case(kind))["nodes"]["3"]["energy"], 0.)
        self.assertEqual(backend.DEFAULTS["battery"], {"capacity_mwh": 10., "charge_mw": 3., "discharge_mw": 3.,
            "charge_efficiency": .9, "discharge_efficiency": .9, "self_discharge_per_h": 0., "initial_soc": .5})

    def test_expanded_kinds_reject_every_legacy_schema(self):
        for schema in range(1, 7):
            for kind in NEW_STORAGE:
                with self.subTest(schema=schema, kind=kind):
                    snapshot = self.case(kind)
                    snapshot["schema_version"] = schema
                    snapshot["devices"].insert(0, snapshot["devices"].pop(3))
                    with self.assertRaisesRegex(backend.InputError, "schema_version 7"):
                        backend.normalize(snapshot)

    def test_schema_seven_requires_expanded_storage(self):
        snapshot = electric_case("battery")
        with self.assertRaisesRegex(backend.InputError, "reserved"):
            backend.normalize(snapshot)
        for schema in (1, 2, 3):
            snapshot["schema_version"] = schema
            self.assertEqual(backend.normalize(snapshot)["nodes"]["3"]["energy"], 5.)
        for schema in (4, 5, 6, 8):
            snapshot["schema_version"] = schema
            with self.assertRaises(backend.InputError):
                backend.normalize(snapshot)

    def test_state_dimension_and_finiteness_are_strict(self):
        for kind in NEW_STORAGE:
            correct = "energy_mwhth" if kind == "solid_thermal_store" else "energy_mwh"
            wrong = "energy_mwh" if correct == "energy_mwhth" else "energy_mwhth"
            for state in ({wrong: 0.}, {correct: 0., wrong: 0.}, {}, {correct: -1.},
                          {correct: float("nan")}, {correct: float("inf")}, {correct: True}, {correct: 1e10}):
                with self.subTest(kind=kind, state=state):
                    snapshot = self.case(kind)
                    snapshot["devices"][3]["state"] = state
                    with self.assertRaises(backend.InputError):
                        backend.normalize(snapshot)
            snapshot = self.case(kind, params={"initial_soc": .25})
            expected = EXPECTED_DEFAULTS[kind][0]*.25
            self.assertEqual(backend.normalize(snapshot)["nodes"]["3"]["energy"], expected)

    def test_aboveground_caes_guardrails(self):
        for key, limit in (("capacity_mwh", 10.), ("charge_mw", 2.), ("discharge_mw", 2.)):
            self.assertEqual(backend.normalize(electric_case("caes_aboveground", {key: limit}))["nodes"]["3"]["params"][key], limit)
            with self.subTest(key=key), self.assertRaises(backend.InputError):
                backend.normalize(electric_case("caes_aboveground", {key: limit+.01}))
        for kind in ("caes_underground", "caes_cavern", "hydrogen_cavern"):
            with self.subTest(kind=kind), self.assertRaises(backend.InputError):
                backend.normalize(electric_case(kind))

    def test_invalid_efficiency_loss_and_power_are_rejected(self):
        for kind in NEW_STORAGE:
            power, energy = ("mwth", "mwhth") if kind == "solid_thermal_store" else ("mw", "mwh")
            edits = ((f"capacity_{energy}", 0.), (f"charge_{power}", -1.), (f"discharge_{power}", -1.),
                     ("charge_efficiency", 0.), ("charge_efficiency", 1.01), ("discharge_efficiency", 0.),
                     ("discharge_efficiency", float("nan")), ("self_discharge_per_h", -1.),
                     ("self_discharge_per_h", float("inf")), ("initial_soc", True), ("initial_soc", 1.1))
            for key, value in edits:
                with self.subTest(kind=kind, key=key, value=value), self.assertRaises(backend.InputError):
                    backend.normalize(self.case(kind, params={key: value}))

    def test_no_electric_storage_to_storage_or_export_paths(self):
        for kind in NEW_ELECTRIC:
            with self.subTest(kind=kind):
                snapshot = electric_case(kind)
                snapshot["devices"].append(device(4, "battery", energy=0.))
                snapshot["links"].extend([cable(1, 4), cable(1, -1)])
                problem = backend.normalize(snapshot)
                self.assertEqual([path["sink"] for path in problem["paths"] if path["source"] == "3"], ["2"])
                self.assertEqual([path["sink"] for path in problem["paths"] if path["source"] == "4"], ["2"])
                self.assertTrue(any(path["source"] == "0" and path["sink"] == "3" for path in problem["paths"]))

    def test_storage_ports_are_bidirectional_ac_and_no_direct_links(self):
        for kind in NEW_ELECTRIC:
            for reverse in (False, True):
                snapshot = electric_case(kind)
                snapshot["links"][2] = cable(3, 1) if reverse else cable(1, 3)
                line = backend.normalize(snapshot)["links"][2]
                self.assertEqual(line["from_port"] if reverse else line["to_port"], "ac")
            snapshot["links"][2] = cable(3, 2)
            with self.subTest(kind=kind), self.assertRaises(backend.InputError):
                backend.normalize(snapshot)

    def test_fixture_exporter_missing_glpk_is_a_clear_error_without_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)/"fixtures"
            run = subprocess.run([sys.executable, str(ROOT/"tests/export_expanded_storage_crosslanguage.py"),
                                  "--glpsol", str(Path(directory)/"missing-glpsol"), "--output-dir", str(output)],
                                 capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 2)
            self.assertIn("GLPK executable not found", run.stderr)
            self.assertFalse(output.exists())

    def test_solid_store_only_primary_water_routes_and_profile(self):
        self.assertEqual(backend.rankine_profile("solid_thermal_store"), "thermal_stage1_v1")
        self.assertEqual({route for route in backend.THERMAL_ROUTES if "solid_thermal_store" in route}, {
            ("electric_boiler", "solid_thermal_store"), ("fuel_boiler", "solid_thermal_store"),
            ("solar_thermal", "solid_thermal_store"), ("solid_thermal_store", "heat_exchanger")})
        for edits in ({"carrier": "heat_oil"}, {"grade_id": backend.OIL_GRADE}, {"unit": "MW"}, {"to_port": "ac"}):
            snapshot = solid_case()
            snapshot["links"][2].update(edits)
            with self.subTest(edits=edits), self.assertRaises(backend.InputError):
                backend.normalize(snapshot)
        for a, b in ((1, 3), (3, 1)):
            snapshot = solid_case()
            snapshot["links"].append(cable(a, b))
            with self.assertRaisesRegex(backend.InputError, "electricity route"):
                backend.normalize(snapshot)
        snapshot = solid_case()
        snapshot["devices"][3]["model_profile"] = backend.HIGH_TEMP_PROFILE
        with self.assertRaises(backend.InputError):
            backend.normalize(snapshot)


@unittest.skipUnless(GLPK, "Expanded-storage integration tests require real glpsol")
class ExpandedStorageGLPKTests(unittest.TestCase):
    def solve(self, snapshot):
        before = copy.deepcopy(snapshot)
        result = backend.solve(snapshot, glpsol=GLPK)
        self.assertTrue(result["success"], result)
        self.assertEqual(result["status"], "optimal", result)
        self.assertEqual(result["schema_version"], 7)
        self.assertEqual(snapshot, before, "A predicted schedule cannot mutate live storage")
        self.assertTrue(result["validation"]["raw_decisions_validated"])
        self.assertTrue(backend.validate_schedule(backend.normalize(snapshot), result["steps"])["valid"])
        for report in result["steps"]:
            self.assertAlmostEqual(report["energy_balance_error_mwh"], 0., delta=EPS)
            self.assertAlmostEqual(report["thermal"]["energy_balance_error_mwhth"], 0., delta=EPS)
        return result

    def test_all_electric_kinds_charge_then_discharge_with_exact_losses(self):
        for kind in NEW_ELECTRIC:
            for reverse in (False, True):
                with self.subTest(kind=kind, reverse=reverse):
                    snapshot = electric_case(kind)
                    if reverse:
                        snapshot["links"][2] = cable(3, 1)
                    result = self.solve(snapshot)
                    first, second = [report["devices"]["3"] for report in result["steps"]]
                    _, _, _, eta_c, eta_d, self_loss, _ = EXPECTED_DEFAULTS[kind]
                    charged = .1*eta_c
                    available = charged*math.exp(-self_loss)
                    self.assertAlmostEqual(first["charge_mw"], .1, delta=EPS)
                    self.assertAlmostEqual(first["energy_mwh"], charged, delta=EPS)
                    self.assertAlmostEqual(second["discharge_mw"], available*eta_d, delta=EPS)
                    self.assertAlmostEqual(second["energy_mwh"], 0., delta=EPS)
                    self.assertAlmostEqual(second["self_discharge_mwh"], charged-available, delta=EPS)
                    self.assertAlmostEqual(first["storage_conversion_loss_mw"], .1*(1-eta_c), delta=EPS)
                    self.assertAlmostEqual(second["storage_conversion_loss_mw"], available*(1-eta_d), delta=EPS)
                    self.assertEqual(set(result["initial_states"]["3"]), {"energy_mwh"})
                    self.assertEqual(set(result["final_states"]["3"]), {"energy_mwh"})
                    for detail in (first, second):
                        self.assertNotIn("energy_mwhth", detail)
                        self.assertLessEqual(min(detail["charge_mw"], detail["discharge_mw"]), EPS)

    def test_default_empty_stores_cannot_create_power(self):
        for kind in NEW_ELECTRIC:
            snapshot = electric_case(kind)
            snapshot["steps"] = [step(0., 1.)]
            with self.subTest(kind=kind):
                report = self.solve(snapshot)["steps"][0]
                self.assertAlmostEqual(report["served_mw"], 0., delta=EPS)
                self.assertAlmostEqual(report["energy_mwh"], 0., delta=EPS)

    def test_self_discharge_and_available_inventory_limit_output(self):
        params = {"capacity_mwh": 1., "charge_mw": 1., "discharge_mw": .2,
                  "charge_efficiency": .8, "discharge_efficiency": .5, "self_discharge_per_h": .1}
        for kind in NEW_ELECTRIC:
            snapshot = electric_case(kind, params, .4)
            snapshot["steps"] = [step(0., 2.)]
            with self.subTest(kind=kind):
                report = self.solve(snapshot)["steps"][0]
                self.assertAlmostEqual(report["served_mw"], .4*math.exp(-.1)*.5, delta=EPS)
                self.assertAlmostEqual(report["energy_mwh"], 0., delta=EPS)

    def test_charge_headroom_terminal_floor_and_discharge_power(self):
        for kind in NEW_ELECTRIC:
            params = {"capacity_mwh": 1., "charge_mw": .5, "discharge_mw": .2,
                      "charge_efficiency": .8, "discharge_efficiency": .5, "self_discharge_per_h": 0.}
            snapshot = electric_case(kind, params, .9)
            snapshot["steps"] = [step(1., 0.)]
            snapshot["options"]["terminal_soc_fraction"] = 1.
            with self.subTest(kind=kind):
                report = self.solve(snapshot)["steps"][0]
                self.assertAlmostEqual(report["charge_mw"], .125, delta=EPS)
                self.assertAlmostEqual(report["energy_mwh"], 1., delta=EPS)
                snapshot["options"].pop("terminal_soc_fraction")
                snapshot["steps"] = [step(0., 1.)]
                report = self.solve(snapshot)["steps"][0]
                self.assertAlmostEqual(report["discharge_mw"], .2, delta=EPS)
                self.assertAlmostEqual(report["energy_mwh"], .5, delta=EPS)

    def test_no_export_or_storage_transfer_even_when_economically_tempting(self):
        for kind in NEW_ELECTRIC:
            snapshot = electric_case(kind, {"capacity_mwh": 1., "self_discharge_per_h": 0.}, 1.)
            snapshot["devices"].append(device(4, "battery", {"capacity_mwh": 1.}, 0.))
            snapshot["links"].extend([cable(1, -1), cable(1, 4)])
            snapshot["steps"] = [step()]
            with self.subTest(kind=kind):
                report = self.solve(snapshot)["steps"][0]
                self.assertAlmostEqual(report["export_mw"], 0., delta=EPS)
                self.assertAlmostEqual(report["charge_mw"], 0., delta=EPS)
                self.assertAlmostEqual(report["discharge_mw"], 0., delta=EPS)
                snapshot["options"]["terminal_soc_fraction"] = .2
                result = backend.solve(snapshot, glpsol=GLPK)
                self.assertEqual(result["status"], "infeasible", result)
                self.assertFalse(result["steps"])

    def test_zero_duration_and_disconnected_storage_never_exchange_energy(self):
        for kind in NEW_ELECTRIC:
            snapshot = electric_case(kind, {"capacity_mwh": 1., "self_discharge_per_h": .1}, .4)
            snapshot["steps"] = [step(1., 1., dt=0.)]
            with self.subTest(kind=kind):
                report = self.solve(snapshot)["steps"][0]
                self.assertEqual(report["energy_mwh"], .4)
                self.assertEqual(report["charge_mw"], 0.)
                self.assertEqual(report["discharge_mw"], 0.)
                snapshot["steps"] = [step(1., 1.)]
                snapshot["links"].pop()
                report = self.solve(snapshot)["steps"][0]
                self.assertAlmostEqual(report["energy_mwh"], .4*math.exp(-.1), delta=EPS)
                self.assertEqual(report["charge_mw"], 0.)
                self.assertEqual(report["discharge_mw"], 0.)

    def test_shared_station_and_cable_caps_include_all_storage(self):
        snapshot = electric_case("battery_sodium", {"capacity_mwh": 1., "self_discharge_per_h": 0.}, 1.)
        snapshot["devices"].append(device(4, "hydrogen_storage_system", {"capacity_mwh": 1., "self_discharge_per_h": 0.}, 1.))
        snapshot["devices"][1]["params"].update(capacity_mw=.15, loss_fraction=.1)
        snapshot["links"][2].update(capacity_mw=.1, loss_fraction=.1)
        snapshot["links"].append(cable(1, 4, capacity=.1, loss=.1))
        snapshot["links"][1]["loss_fraction"] = .1
        snapshot["steps"] = [step(0., 1.)]
        report = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(report["served_mw"], .15*.9*.9, delta=EPS)
        self.assertLessEqual(report["devices"]["1"]["input_mw"], .15+EPS)
        self.assertTrue(all(line["sent_mw"] <= line["capacity_mw"]+EPS for line in report["lines"]))

    def test_solid_thermal_store_round_trip_and_water_grade_ledger(self):
        result = self.solve(solid_case())
        first, second = [report["devices"]["3"] for report in result["steps"]]
        self.assertAlmostEqual(first["charge_mwth"], .98, delta=EPS)
        self.assertAlmostEqual(first["energy_mwhth"], .98*.95, delta=EPS)
        self.assertAlmostEqual(second["discharge_mwth"], .98*.95*math.exp(-.001)*.95, delta=EPS)
        self.assertAlmostEqual(result["steps"][1]["thermal"]["served_mwth"], .98*.95*math.exp(-.001)*.95*.98, delta=EPS)
        for report in result["steps"]:
            detail = report["devices"]["3"]
            self.assertEqual(detail["model_profile"], "thermal_stage1_v1")
            self.assertEqual(detail["output_mw"], 0.)
            self.assertEqual(detail["input_mw"], 0.)
            self.assertNotIn("energy_mwh", detail)
            self.assertEqual(set(report["next_states"]["3"]), {"energy_mwhth"})
            self.assertAlmostEqual(report["thermal"]["energy_mwhth"], detail["energy_mwhth"], delta=EPS)
            self.assertAlmostEqual(report["energy_mwh"], 0., delta=EPS)
        self.assertEqual(set(result["initial_states"]["3"]), {"energy_mwhth"})
        self.assertEqual(set(result["final_states"]["3"]), {"energy_mwhth"})

    def test_solid_thermal_pause_empty_and_disconnected_decay(self):
        snapshot = solid_case(energy=1.)
        snapshot["steps"] = [dict(snapshot["steps"][0], dt_h=0.)]
        detail = self.solve(snapshot)["steps"][0]["devices"]["3"]
        self.assertEqual(detail["energy_mwhth"], 1.)
        self.assertEqual(detail["charge_mwth"], 0.)
        self.assertEqual(detail["discharge_mwth"], 0.)
        snapshot["steps"][0]["dt_h"] = 1.
        snapshot["links"] = [snapshot["links"][0], snapshot["links"][1], snapshot["links"][4]]
        detail = self.solve(snapshot)["steps"][0]["devices"]["3"]
        self.assertAlmostEqual(detail["energy_mwhth"], math.exp(-.001), delta=EPS)
        snapshot = solid_case()
        snapshot["steps"] = [dict(snapshot["steps"][1], time_s=0.)]
        self.assertEqual(self.solve(snapshot)["steps"][0]["thermal"]["served_mwth"], 0.)

    def test_hydrogen_net_lhv_stages_mass_and_model_disclosures(self):
        result = self.solve(electric_case())
        first, second = [report["devices"]["3"] for report in result["steps"]]
        self.assertAlmostEqual(first["hydrogen_produced_mw_lhv"], .1*.65, delta=EPS)
        self.assertAlmostEqual(first["hydrogen_charge_loss_mw"], .1*.35, delta=EPS)
        self.assertAlmostEqual(first["hydrogen_mass_kg"], .1*.65*1000/33.33, delta=EPS)
        consumed = .1*.65*math.exp(-.0001)
        self.assertAlmostEqual(second["hydrogen_consumed_mw_lhv"], consumed, delta=EPS)
        self.assertAlmostEqual(second["hydrogen_discharge_loss_mw"], consumed*.5, delta=EPS)
        self.assertAlmostEqual(second["hydrogen_mass_kg"], 0., delta=EPS)
        for detail in (first, second):
            self.assertEqual(detail["hydrogen_energy_basis"], "LHV")
            self.assertAlmostEqual(detail["hydrogen_produced_mw_lhv"]+detail["hydrogen_charge_loss_mw"], detail["charge_mw"], delta=EPS)
            self.assertAlmostEqual(detail["hydrogen_consumed_mw_lhv"], detail["discharge_mw"]+detail["hydrogen_discharge_loss_mw"], delta=EPS)
        assumptions = result["expanded_storage_assumptions"]
        self.assertEqual(assumptions["hydrogen_energy_basis"], "LHV")
        self.assertEqual(assumptions["hydrogen_lhv_kwh_per_kg"], 33.33)
        self.assertIn("no underground", assumptions["caes"])
        self.assertIn("transients", assumptions["limitations"])

    def test_independent_audit_rejects_each_forged_hydrogen_metric(self):
        snapshot = electric_case()
        result = self.solve(snapshot)
        problem = backend.normalize(snapshot)
        fields = ("hydrogen_charge_loss_mw", "hydrogen_discharge_loss_mw", "hydrogen_produced_mw_lhv",
                  "hydrogen_consumed_mw_lhv", "hydrogen_mass_kg", "charge_conversion_loss_mw", "discharge_conversion_loss_mw")
        for field in fields:
            for value in (123., float("nan"), float("inf"), True):
                with self.subTest(field=field, value=value):
                    reports = copy.deepcopy(result["steps"])
                    reports[0]["devices"]["3"][field] = value
                    self.assertFalse(backend.validate_schedule(problem, reports)["valid"])
        for basis in ("HHV", "LHV + HHV", None):
            reports = copy.deepcopy(result["steps"])
            reports[0]["devices"]["3"]["hydrogen_energy_basis"] = basis
            self.assertFalse(backend.validate_schedule(problem, reports)["valid"])
        reports = copy.deepcopy(result["steps"])
        del reports[0]["devices"]["3"]["hydrogen_mass_kg"]
        self.assertFalse(backend.validate_schedule(problem, reports)["valid"])

    def test_independent_path_audit_rejects_forged_storage_export_and_decisions(self):
        snapshot = electric_case()
        snapshot["links"].append(cable(1, -1))
        result = self.solve(snapshot)
        problem = backend.normalize(snapshot)
        for field, value in (("source_id", 3), ("sink_id", -1), ("station_id", 0), ("sent_mw", 42.)):
            reports = copy.deepcopy(result["steps"])
            flow = next(flow for flow in reports[0]["path_flows"] if flow["source_id"] == 0 and flow["sink_id"] == 2)
            flow[field] = value
            with self.subTest(field=field):
                self.assertFalse(backend.validate_schedule(problem, reports)["valid"])
        reports = copy.deepcopy(result["steps"])
        reports[0]["path_flows"].append({"source_id": 3, "station_id": 1, "sink_id": -1, "sent_mw": .1})
        self.assertFalse(backend.validate_schedule(problem, reports)["valid"])

    def test_mixed_legacy_storage_and_expanded_store_aggregate_soc(self):
        snapshot = electric_case("battery_sodium", energy=1.)
        snapshot["devices"].append(device(4, "battery", energy=2.))
        snapshot["links"].append(cable(1, 4))
        snapshot["steps"] = [step(dt=0.)]
        report = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(report["energy_mwh"], 3., delta=EPS)
        self.assertAlmostEqual(report["soc"], 3./16., delta=EPS)
        self.assertEqual(set(report["next_states"]), {"3", "4"})

    def test_schema_seven_coexists_with_tower_and_rankine(self):
        from test_tower_optimizer import case
        snapshot = case()
        snapshot["schema_version"] = 7
        snapshot["devices"].append(device(9, "battery_sodium", energy=.1))
        snapshot["links"].append(cable(1, 9))
        result = self.solve(snapshot)
        self.assertTrue(result["steps"][0]["tower"])
        self.assertTrue(result["steps"][0]["rankine"])
        problem = backend.normalize(snapshot)
        self.assertIn("9", [path["sink"] for path in problem["paths"] if path["source"] == "4"])
        self.assertNotIn("-1", [path["sink"] for path in problem["paths"] if path["source"] == "9"])

    def test_fixture_exporter_regenerates_all_six_auditable_pairs(self):
        with tempfile.TemporaryDirectory() as directory:
            run = subprocess.run([sys.executable, str(ROOT/"tests/export_expanded_storage_crosslanguage.py"),
                                  "--glpsol", GLPK, "--output-dir", directory],
                                 capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
            summary = json.loads(run.stdout)
            self.assertTrue(summary["success"])
            self.assertEqual({fixture["kind"] for fixture in summary["fixtures"]}, set(NEW_STORAGE))
            self.assertEqual(len(list(Path(directory).glob("*.json"))), 12)
            for kind in NEW_STORAGE:
                snapshot = json.loads((Path(directory)/(kind+"_request.json")).read_text())
                result = json.loads((Path(directory)/(kind+"_result.json")).read_text())
                self.assertTrue(result["solver_invoked"])
                self.assertEqual(result["status"], "optimal")
                self.assertTrue(backend.validate_schedule(backend.normalize(snapshot), result["steps"])["valid"])

    def test_cli_round_trip_keeps_correlation_and_dimensioned_states(self):
        snapshot = electric_case()
        snapshot["metadata"] = {"request_id": "expanded-storage-test", "scene_revision": 7}
        with tempfile.TemporaryDirectory() as directory:
            source, target = Path(directory)/"input.json", Path(directory)/"output.json"
            source.write_text(json.dumps(snapshot))
            run = subprocess.run([sys.executable, str(ROOT/"tools/dispatch_solver.py"), "--input", str(source),
                                  "--output", str(target), "--glpsol", GLPK], capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
            result = json.loads(target.read_text())
        self.assertTrue(result["success"], result)
        self.assertEqual(result["schema_version"], 7)
        self.assertEqual(result["metadata"], snapshot["metadata"])
        self.assertEqual(result["steps"][0]["devices"]["3"]["hydrogen_energy_basis"], "LHV")
        self.assertEqual(set(result["final_states"]["3"]), {"energy_mwh"})


if __name__ == "__main__":
    unittest.main()
