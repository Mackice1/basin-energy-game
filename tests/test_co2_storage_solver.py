"""Independent schema-9 CO2 aggregate storage tests using the real GLPK solver.

Run with BASIN_GLPK=/path/to/glpsol and isolated HOME/XDG directories:
    PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_co2_storage_solver.py -v

The arithmetic reference combines published power/time figures, not measured
same-cycle plant performance. CO2 mass, phase and internal heat are not states.
Reusable co2_case(), full_cycle_case(), mixed_material_case() and write_fixtures()
provide solver-independent requests for the Godot whole-report acceptance audit.
"""
from __future__ import annotations

import copy
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("co2_storage_backend", ROOT / "tools/dispatch_solver.py")
backend = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backend)
GLPK = shutil.which(os.environ.get("BASIN_GLPK", "glpsol"))
KIND = "co2_liquid_cycle_store"
PROFILE = "co2_liquid_cycle_store_v1"
EPS = 3e-6
CAPACITY = 794.24
ETA_IN = .8
ETA_OUT = 614. / 794.24
EXPECTED_DEFAULTS = {
    "capacity_mwh": CAPACITY, "charge_mw": 146., "discharge_mw": 100.,
    "charge_efficiency": ETA_IN, "discharge_efficiency": ETA_OUT,
    "self_discharge_per_h": 0., "initial_soc": 0.,
}
METADATA = {"model_profile": PROFILE, "model_profile_version": 1,
            "inventory_basis": "internal_equivalent_mwh", "working_fluid": "CO2",
            "working_inventory_calibrated": False}


def device(ident, kind, params=None, energy=None):
    row = {"id": ident, "kind": kind, "params": dict(params or {})}
    if kind == KIND:
        row.update(model_profile=PROFILE, model_profile_version=1)
    if energy is not None:
        row["state"] = {"energy_mwh": energy}
    return row


def cable(source, target, capacity=146., loss=0.):
    return {"from": source, "to": target, "capacity_mw": capacity, "loss_fraction": loss}


def step(generation=0., demand=0., time=0., dt=1.):
    return {"time_s": time, "dt_h": dt, "available_mw": {"0": generation}, "demand_mw": {"2": demand}}


def co2_case(params=None, energy=None):
    return {
        "schema_version": 9,
        "devices": [device(0, "pv", {"dc_capacity_mw": 240., "inverter_capacity_mw": 200.}),
                    device(1, "station", {"capacity_mw": 146., "loss_fraction": 0.}),
                    device(2, "load"), device(3, KIND, params, energy)],
        "links": [cable(0, 1), cable(1, 2), cable(1, 3)],
        "steps": [step(1.), step(0., 1., 3600.)],
        "options": {"timeout_s": 30.},
    }


def full_cycle_case():
    snapshot = co2_case()
    snapshot["steps"] = [step(146., dt=6.8), step(0., 100., 6.8*3600., 6.14)]
    return snapshot


def mixed_material_case():
    from test_material_solver import material_case
    snapshot = material_case(generation=.73)
    snapshot["schema_version"] = 9
    snapshot["devices"].append(device(7, KIND, {"capacity_mwh": 1., "charge_mw": 1., "discharge_mw": .5}))
    snapshot["links"].append(cable(1, 7))
    snapshot["options"]["terminal_soc_fraction"] = .1
    snapshot["options"]["terminal_hydrogen_kg"] = {"5": 1.}
    return snapshot


def tiny_material_case():
    snapshot = mixed_material_case()
    snapshot["options"].pop("terminal_hydrogen_kg")
    return snapshot


def tiny_mode_case():
    snapshot = co2_case({"capacity_mwh": 1., "charge_mw": 1e-6, "discharge_mw": 1e-6})
    snapshot["steps"] = [step(1e-6, dt=2000.), step(0., 1e-6, 2000.*3600., 1000.)]
    snapshot["options"]["terminal_soc_fraction"] = .0016-.001/ETA_OUT
    return snapshot


def write_fixtures(directory, glpsol=None):
    """Write only real-solver schedules independently audited before serialization."""
    executable = shutil.which(glpsol or GLPK or "glpsol")
    if not executable:
        raise RuntimeError("Real GLPK executable is required")
    cases = {"co2_full_cycle": full_cycle_case(), "co2_material_coexistence": mixed_material_case(),
             "co2_material_tiny": tiny_material_case(), "co2_tiny_mode": tiny_mode_case()}
    decay = co2_case({"self_discharge_per_h": .1}, energy=CAPACITY)
    decay["steps"] = [step(dt=2.), step(0., 100., 7200., 6.14)]
    cases["co2_idle_decay"] = decay
    fixtures = []
    for name, snapshot in cases.items():
        result = backend.solve(snapshot, glpsol=executable)
        if not (result.get("success") and result.get("solver_invoked") and result.get("status") == "optimal"
                and result.get("validation", {}).get("raw_decisions_validated")):
            raise RuntimeError(f"{name}: real GLPK solve failed: {result}")
        audit = backend.validate_schedule(backend.normalize(snapshot), result["steps"])
        if not audit["valid"]:
            raise RuntimeError(f"{name}: independent audit failed: {audit}")
        fixtures.append((name, json.dumps(snapshot, indent=2, allow_nan=False)+"\n",
                         json.dumps(result, indent=2, allow_nan=False)+"\n", audit["max_residual"]))
    output = Path(directory)
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".co2_fixtures_", dir=output) as staging:
        for name, request, result, _ in fixtures:
            (Path(staging)/(name+"_request.json")).write_text(request, encoding="utf-8")
            (Path(staging)/(name+"_result.json")).write_text(result, encoding="utf-8")
        for staged in Path(staging).iterdir():
            os.replace(staged, output/staged.name)
    return {"output_dir": str(output), "fixtures": [{"name": name, "max_residual": residual}
            for name, _, _, residual in fixtures]}


class CO2StorageInputTests(unittest.TestCase):
    def test_defaults_are_internal_equivalent_stock_not_nameplate_or_output_energy(self):
        node = backend.normalize(co2_case())["nodes"]["3"]
        self.assertEqual(node["params"], EXPECTED_DEFAULTS)
        self.assertEqual(node["energy"], 0.)
        self.assertAlmostEqual(146.*6.8*ETA_IN, CAPACITY, delta=1e-12)
        self.assertAlmostEqual(CAPACITY*ETA_OUT, 614., delta=1e-12)
        self.assertNotEqual(CAPACITY, 1000.)
        self.assertNotEqual(CAPACITY, 614.)
        self.assertEqual(backend.normalize(co2_case({"initial_soc": .25}))["nodes"]["3"]["energy"], CAPACITY*.25)

    def test_capacity_and_each_power_have_facility_specific_caps(self):
        for field, maximum in (("capacity_mwh", CAPACITY), ("charge_mw", 146.), ("discharge_mw", 100.)):
            for value in (maximum, maximum/2):
                with self.subTest(field=field, value=value):
                    self.assertEqual(backend.normalize(co2_case({field: value}))["nodes"]["3"]["params"][field], value)
            for value in (maximum+1e-9, maximum*2, 100000.):
                with self.subTest(field=field, value=value), self.assertRaises(backend.InputError):
                    backend.normalize(co2_case({field: value}))

    def test_invalid_numeric_parameters_are_rejected(self):
        invalid = [(key, value) for key in EXPECTED_DEFAULTS for value in (True, float("nan"), float("inf"))]
        invalid += [("capacity_mwh", 0.), ("charge_mw", -1.), ("discharge_mw", -1.),
                    ("charge_efficiency", 0.), ("charge_efficiency", 1.01),
                    ("discharge_efficiency", 0.), ("discharge_efficiency", 1.01),
                    ("initial_soc", -.1), ("initial_soc", 1.01),
                    ("self_discharge_per_h", -.1), ("self_discharge_per_h", 1.01)]
        for field, value in invalid:
            with self.subTest(field=field, value=value), self.assertRaises(backend.InputError):
                backend.normalize(co2_case({field: value}))

    def test_all_legacy_schemas_reject_co2_and_schema_nine_is_reserved(self):
        for schema in range(1, 9):
            snapshot = co2_case()
            snapshot["schema_version"] = schema
            with self.subTest(schema=schema), self.assertRaisesRegex(backend.InputError, "schema_version 9"):
                backend.normalize(snapshot)
        snapshot = co2_case()
        snapshot["devices"][3] = device(3, "battery")
        with self.assertRaisesRegex(backend.InputError, "reserved"):
            backend.normalize(snapshot)
        for schema in (0, 10, True, 9.1):
            snapshot["schema_version"] = schema
            with self.subTest(schema=schema), self.assertRaises(backend.InputError):
                backend.normalize(snapshot)

    def test_frozen_kind_sets_and_material_profile_remain_unchanged(self):
        legacy = set(backend.DEFAULTS)-{KIND}-set(backend.MATERIAL_KINDS)
        self.assertEqual(len(legacy), 27)
        self.assertEqual(len(legacy | set(backend.MATERIAL_KINDS)), 31)
        self.assertEqual(len(backend.DEFAULTS), 32)
        self.assertNotIn(KIND, backend.EXPANDED_STORAGE_KINDS)
        self.assertNotIn(KIND, backend.MATERIAL_KINDS)
        self.assertNotIn(KIND, backend.THERMAL_KINDS)
        problem = backend.normalize(mixed_material_case())
        self.assertTrue(problem["has_material"])
        self.assertEqual(problem["nodes"]["5"]["kind"], "hydrogen_gas_store")
        self.assertEqual(problem["nodes"]["7"]["energy"], 0.)
        self.assertEqual(backend._MATERIAL_DATA["profile_version"], 1)

    def test_model_profile_is_independent_and_version_is_strict(self):
        for field, value in (("model_profile", backend.MATERIAL_PROFILE), ("model_profile", "caes_aboveground"),
                             ("model_profile", None), ("model_profile_version", 0), ("model_profile_version", 2),
                             ("model_profile_version", True), ("model_profile_version", "1")):
            snapshot = co2_case()
            snapshot["devices"][3][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(backend.InputError):
                backend.normalize(snapshot)

    def test_state_is_only_finite_bounded_internal_energy(self):
        states = [{}, {"energy_mwhth": 0.}, {"material_inventory_kg": {"CO2": 10.}},
                  {"energy_mwh": 0., "internal_heat_mwhth": 1.},
                  {"energy_mwh": 0., "co2_mass_kg": 10.}]
        states += [{"energy_mwh": value} for value in (-1., CAPACITY+1e-8, True, float("inf"), float("nan"))]
        for state in states:
            snapshot = co2_case()
            snapshot["devices"][3]["state"] = state
            with self.subTest(state=state), self.assertRaises(backend.InputError):
                backend.normalize(snapshot)
        self.assertEqual(backend.normalize(co2_case(energy=CAPACITY))["nodes"]["3"]["energy"], CAPACITY)

    def test_no_mass_lhv_external_heat_or_purchase_parameters(self):
        for field in ("capacity_kg", "co2_mass_kg", "external_heat_mwth", "internal_heat_mwhth",
                      "lower_heating_value_kwh_per_kg", "co2_purchase_kg_s", "co2_vent_kg_s"):
            for target in ("params", "device"):
                snapshot = co2_case()
                node = snapshot["devices"][3]
                (node["params"] if target == "params" else node)[field] = 1.
                with self.subTest(field=field, target=target), self.assertRaises(backend.InputError):
                    backend.normalize(snapshot)

    def test_only_bidirectional_ac_port_and_no_thermal_or_material_links(self):
        for reverse in (False, True):
            snapshot = co2_case()
            snapshot["links"][2] = cable(3, 1) if reverse else cable(1, 3)
            line = backend.normalize(snapshot)["links"][2]
            self.assertEqual(line["from_port"] if reverse else line["to_port"], "ac")
        for edits in ({"carrier": "material_co2", "unit": "kg/s"}, {"carrier": "heat_water"},
                      {"carrier": "material_h2_gas"}, {"carrier": "water_steam"},
                      {"species_id": "CO2"}, {"to_port": "heat_in"}, {"capacity_mwth": 1.}):
            snapshot = co2_case()
            snapshot["links"][2].update(edits)
            with self.subTest(edits=edits), self.assertRaises(backend.InputError):
                backend.normalize(snapshot)
        snapshot["links"][2] = cable(3, 2)
        with self.assertRaises(backend.InputError):
            backend.normalize(snapshot)

    def test_storage_discharge_cannot_export_charge_other_storage_or_run_electrolysis(self):
        snapshot = mixed_material_case()
        snapshot["devices"].append(device(8, "battery", energy=0.))
        snapshot["links"] += [cable(1, 8), cable(1, -1)]
        problem = backend.normalize(snapshot)
        self.assertEqual({path["sink"] for path in problem["paths"] if path["source"] == "7"}, {"2"})
        self.assertTrue(any(path["source"] == "0" and path["sink"] == "7" for path in problem["paths"]))
        self.assertFalse(any(path["source"] == "6" and path["sink"] == "7" for path in problem["paths"]))
        snapshot["options"]["terminal_hydrogen_kg"] = {"7": 1.}
        with self.assertRaises(backend.InputError):
            backend.normalize(snapshot)


@unittest.skipUnless(GLPK, "real GLPK executable is required")
class CO2StorageGLPKTests(unittest.TestCase):
    def solve(self, snapshot):
        result = backend.solve(snapshot, glpsol=GLPK)
        self.assertTrue(result["success"], result)
        self.assertEqual(result["status"], "optimal", result)
        self.assertEqual(result["schema_version"], 9)
        self.assertTrue(result["solver_invoked"])
        self.assertTrue(result["validation"]["raw_decisions_validated"])
        audit = backend.validate_schedule(backend.normalize(snapshot), result["steps"])
        self.assertTrue(audit["valid"], audit)
        return result

    def test_full_teaching_cycle_992_8_input_794_24_stock_614_output(self):
        result = self.solve(full_cycle_case())
        first, second = (row["devices"]["3"] for row in result["steps"])
        self.assertAlmostEqual(first["charge_mw"]*6.8, 992.8, delta=EPS)
        self.assertAlmostEqual(first["energy_mwh"], CAPACITY, delta=EPS)
        self.assertAlmostEqual(first["soc"], 1., delta=EPS)
        self.assertAlmostEqual(first["charge_conversion_loss_mw"]*6.8, 198.56, delta=EPS)
        self.assertAlmostEqual(second["discharge_mw"]*6.14, 614., delta=EPS)
        self.assertAlmostEqual(second["discharge_conversion_loss_mw"]*6.14, 180.24, delta=EPS)
        self.assertAlmostEqual(second["energy_mwh"], 0., delta=EPS)
        self.assertAlmostEqual(result["steps"][1]["served_mw"], 100., delta=EPS)
        self.assertEqual(result["initial_states"]["3"], {"energy_mwh": 0.})
        self.assertEqual(set(result["final_states"]["3"]), {"energy_mwh"})

    def test_reports_disclose_uncalibrated_closed_inventory_without_mass_or_heat(self):
        result = self.solve(co2_case())
        for row in result["steps"]:
            detail = row["devices"]["3"]
            for key, value in METADATA.items():
                self.assertEqual(detail[key], value)
            self.assertFalse(any("kg" in key or "lhv" in key.lower() or key.endswith(("mwth", "mwhth")) for key in detail))
            self.assertEqual(set(row["next_states"]["3"]), {"energy_mwh"})
        notes = result["co2_storage_assumptions"]
        self.assertTrue(notes["closed_inventory"])
        self.assertFalse(notes["working_inventory_calibrated"])
        self.assertIn("not a measured same-cycle", notes["reference_note"])
        self.assertIn("uncalibrated teaching", notes["self_discharge"])
        self.assertIn("not working CO2 mass", notes["self_discharge"])
        self.assertIn("no separately spendable", notes["internal_heat"])

    def test_empty_zero_duration_and_disconnected_storage_cannot_create_energy(self):
        snapshot = co2_case()
        snapshot["steps"] = [step(0., 100.)]
        row = self.solve(snapshot)["steps"][0]
        self.assertEqual(row["served_mw"], 0.)
        self.assertEqual(row["energy_mwh"], 0.)
        snapshot = co2_case({"self_discharge_per_h": .1}, energy=10.)
        snapshot["steps"] = [step(146., 100., dt=0.)]
        row = self.solve(snapshot)["steps"][0]
        self.assertEqual(row["energy_mwh"], 10.)
        self.assertEqual(row["charge_mw"], 0.)
        self.assertEqual(row["discharge_mw"], 0.)
        snapshot["steps"] = [step(146., 100.)]
        snapshot["links"].pop()
        row = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(row["energy_mwh"], 10.*math.exp(-.1), delta=EPS)
        self.assertEqual(row["charge_mw"], 0.)
        self.assertEqual(row["discharge_mw"], 0.)

    def test_positive_idle_loss_only_removes_internal_energy_before_discharge(self):
        for duration in (.25, 1., 2.):
            snapshot = co2_case({"self_discharge_per_h": .1}, energy=10.)
            snapshot["steps"] = [step(0., 100., dt=duration)]
            row = self.solve(snapshot)["steps"][0]
            self.assertAlmostEqual(row["discharge_mw"]*duration, 10.*math.exp(-.1*duration)*ETA_OUT, delta=EPS)
            self.assertAlmostEqual(row["self_discharge_mwh"], 10.*(1-math.exp(-.1*duration)), delta=EPS)
            self.assertAlmostEqual(row["energy_mwh"], 0., delta=EPS)

    def test_ratings_and_charge_headroom_limit_port_energy(self):
        snapshot = co2_case({"capacity_mwh": 1., "charge_mw": .5, "discharge_mw": .2}, energy=.9)
        snapshot["steps"] = [step(1.)]
        snapshot["options"]["terminal_soc_fraction"] = 1.
        row = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(row["charge_mw"], .125, delta=EPS)
        self.assertAlmostEqual(row["energy_mwh"], 1., delta=EPS)
        snapshot["options"].pop("terminal_soc_fraction")
        snapshot["steps"] = [step(0., 1.)]
        row = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(row["discharge_mw"], .2, delta=EPS)
        self.assertAlmostEqual(row["energy_mwh"], .9-.2/ETA_OUT, delta=EPS)
        snapshot = co2_case({"capacity_mwh": 1., "charge_mw": .5})
        snapshot["steps"] = [step(1.), step(0., 1., 3600.)]
        row = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(row["charge_mw"], .5, delta=EPS)

    def test_delivery_losses_are_separate_from_internal_conversion(self):
        snapshot = co2_case()
        snapshot["devices"][1]["params"]["loss_fraction"] = .1
        for line in snapshot["links"]:
            line["loss_fraction"] = .1
        result = self.solve(snapshot)
        first, second = result["steps"]
        self.assertAlmostEqual(first["charge_mw"], .9**3, delta=EPS)
        self.assertAlmostEqual(first["energy_mwh"], .9**3*ETA_IN, delta=EPS)
        self.assertAlmostEqual(second["served_mw"], .9**6*ETA_IN*ETA_OUT, delta=EPS)

    def test_shared_station_and_cable_caps_include_co2_discharge(self):
        snapshot = co2_case(energy=10.)
        snapshot["devices"].append(device(4, "battery", energy=5.))
        snapshot["links"].append(cable(1, 4, capacity=.1, loss=.1))
        snapshot["links"][2].update(capacity_mw=.1, loss_fraction=.1)
        snapshot["links"][1]["loss_fraction"] = .1
        snapshot["devices"][1]["params"].update(capacity_mw=.15, loss_fraction=.1)
        snapshot["steps"] = [step(0., 1.)]
        row = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(row["served_mw"], .15*.9*.9, delta=EPS)
        self.assertLessEqual(row["devices"]["1"]["input_mw"], .15+EPS)
        self.assertTrue(all(line["sent_mw"] <= line["capacity_mw"]+EPS for line in row["lines"]))

    def test_no_export_storage_transfer_or_free_terminal_floor(self):
        snapshot = co2_case(energy=10.)
        snapshot["devices"].append(device(4, "battery", {"capacity_mwh": 1.}, energy=0.))
        snapshot["links"] += [cable(1, 4), cable(1, -1)]
        snapshot["steps"] = [step()]
        row = self.solve(snapshot)["steps"][0]
        self.assertEqual(row["discharge_mw"], 0.)
        self.assertEqual(row["charge_mw"], 0.)
        self.assertEqual(row["export_mw"], 0.)
        snapshot["options"]["terminal_soc_fraction"] = .1
        result = backend.solve(snapshot, glpsol=GLPK)
        self.assertFalse(result["success"])
        self.assertEqual(result["status"], "infeasible")
        self.assertFalse(result["steps"])

    def test_charge_discharge_modes_remain_mutually_exclusive(self):
        snapshot = co2_case({"capacity_mwh": 1.}, energy=.4)
        snapshot["steps"] = [step(1., .1), step(.1, 1., 3600.)]
        result = self.solve(snapshot)
        self.assertGreater(result["steps"][0]["charge_mw"], 0.)
        self.assertGreater(result["steps"][1]["discharge_mw"], 0.)
        for row in result["steps"]:
            detail = row["devices"]["3"]
            self.assertLessEqual(min(detail["charge_mw"], detail["discharge_mw"]), EPS)
            self.assertIn(detail["mode_binary"], (0., 1.))

    def test_co2_mode_uses_runtime_mw_epsilon_without_changing_old_storage(self):
        snapshot = co2_case({"capacity_mwh": 1., "charge_mw": 1e-6, "discharge_mw": 1e-6})
        # A long horizon keeps the tiny power's integrated energy above GLPK's
        # feasibility tolerance; it cannot satisfy the floor by dropping it.
        snapshot["steps"] = [step(1e-6, dt=1000.)]
        snapshot["options"]["terminal_soc_fraction"] = .0008
        row = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(row["charge_mw"], 1e-6, delta=1e-10)
        self.assertEqual(row["devices"]["3"]["mode"], "charge")
        snapshot = co2_case({"capacity_mwh": 1., "charge_mw": 1e-6, "discharge_mw": 1e-6}, energy=.002)
        snapshot["steps"] = [step(0., 1e-6, dt=1000.)]
        row = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(row["discharge_mw"], 1e-6, delta=1e-10)
        self.assertEqual(row["devices"]["3"]["mode"], "discharge")
        snapshot["devices"][3] = device(3, "battery_sodium", {"capacity_mwh": 1., "charge_mw": 1e-6, "discharge_mw": 1e-6}, energy=.002)
        snapshot["devices"].append(device(4, KIND))
        legacy = backend.solve(snapshot, glpsol=GLPK)
        self.assertTrue(legacy["success"], legacy)
        self.assertEqual(legacy["steps"][0]["devices"]["3"]["mode"], "idle")

    def test_schema_nine_derived_negative_heat_zero_is_audited_and_positive_flows_retained(self):
        # Retain the original adversarial coexistence case: the optimizer uses
        # CO2 while positive chemical flows remain at machine precision.
        snapshot = tiny_material_case()
        original_assemble = backend.assemble_schedule
        assembled = []
        def capture(*args, **kwargs):
            rows = original_assemble(*args, **kwargs)
            assembled.append(copy.deepcopy(rows))
            return rows
        with mock.patch.object(backend, "assemble_schedule", side_effect=capture):
            result = self.solve(snapshot)
        note = result["negative_zero_normalization"]
        self.assertGreater(note["derived_heat_count"], 0)
        self.assertEqual(note["derived_heat_exclusive_lower_bound"], -1e-12)
        self.assertTrue(note["raw_decisions_audited_first"])
        self.assertTrue(note["raw_report_audited_before_derived_heat_normalization"])
        self.assertTrue(note["report_rebuilt_and_reaudited"])
        raw, normalized = assembled[-2:]
        self.assertTrue(backend.validate_schedule(backend.normalize(snapshot), raw)["valid"])
        self.assertLess(raw[0]["devices"]["4"]["heat_rejected_mwth"], 0.)
        self.assertEqual(normalized[0]["devices"]["4"]["heat_rejected_mwth"], 0.)
        for before, after in zip(raw, normalized):
            for field in ("hydrogen_produced_kg_s", "hydrogen_consumed_kg_s", "water_withdrawn_kg_s"):
                self.assertEqual(before["material"][field], after["material"][field])
            for ident in ("3", "4", "5", "6"):
                self.assertGreaterEqual(after["devices"][ident]["heat_rejected_mwth"], 0.)
        self.assertGreater(normalized[0]["material"]["hydrogen_produced_kg_s"], 0.)

    def test_material_profile_one_coexists_without_co2_mass_or_heat_credit(self):
        result = self.solve(mixed_material_case())
        self.assertEqual(result["material_assumptions"]["model_profile"], backend.MATERIAL_PROFILE)
        self.assertEqual(result["material_assumptions"]["model_profile_version"], 1)
        self.assertGreater(result["steps"][0]["devices"]["7"]["charge_mw"], 0.)
        self.assertGreaterEqual(result["steps"][0]["material"]["hydrogen_inventory_kg"], 1.-EPS)
        for row in result["steps"]:
            self.assertNotIn("material_inventory_kg", row["next_states"]["7"])
            self.assertNotIn("co2_mass_kg", row["material"])
            self.assertEqual(row["devices"]["7"]["working_fluid"], "CO2")
        self.assertGreaterEqual(result["final_states"]["7"]["energy_mwh"], .1-EPS)

    def assert_tamper_rejected(self, snapshot, result, edit):
        rows = copy.deepcopy(result["steps"])
        edit(rows)
        audit = backend.validate_schedule(backend.normalize(snapshot), rows)
        self.assertFalse(audit["valid"], audit)
        self.assertTrue(audit["errors"], audit)

    def test_independent_audit_rejects_energy_loss_soc_and_mode_tampering(self):
        snapshot = co2_case()
        result = self.solve(snapshot)
        for field in ("energy_before_mwh", "energy_after_self_discharge_mwh", "self_discharge_mwh", "energy_mwh",
                      "capacity_mwh", "next_energy_mwh", "received_mw", "sent_mw",
                      "charge_mw", "discharge_mw", "charge_conversion_loss_mw", "discharge_conversion_loss_mw",
                      "storage_conversion_loss_mw", "storage_loss_mw", "soc", "soc_before", "mode_binary"):
            for value in (123., True, float("nan"), float("inf")):
                with self.subTest(field=field, value=value):
                    self.assert_tamper_rejected(snapshot, result, lambda rows, f=field, v=value: rows[0]["devices"]["3"].__setitem__(f, v))
        self.assert_tamper_rejected(snapshot, result, lambda rows: rows[0]["devices"]["3"].__setitem__("mode", "discharge"))

    def test_independent_audit_rejects_missing_or_forged_co2_identity(self):
        snapshot = co2_case()
        result = self.solve(snapshot)
        for field in METADATA:
            for value in (None, "forged", 123., True):
                with self.subTest(field=field, value=value):
                    self.assert_tamper_rejected(snapshot, result, lambda rows, f=field, v=value: rows[0]["devices"]["3"].__setitem__(f, v))
            self.assert_tamper_rejected(snapshot, result, lambda rows, f=field: rows[0]["devices"]["3"].pop(f))

    def test_independent_audit_rejects_invented_material_heat_or_lhv(self):
        snapshot = co2_case()
        result = self.solve(snapshot)
        for field in ("co2_mass_kg", "hydrogen_mass_kg", "energy_mwhth", "internal_heat_mwhth", "external_heat_mwth", "co2_lhv_mwh"):
            with self.subTest(field=field):
                self.assert_tamper_rejected(snapshot, result, lambda rows, f=field: rows[0]["devices"]["3"].__setitem__(f, 1.))
        for state in ({"energy_mwh": .8, "co2_mass_kg": 1.}, {"energy_mwhth": .8}, {"energy_mwh": 123.}):
            self.assert_tamper_rejected(snapshot, result, lambda rows, s=state: rows[0]["next_states"].__setitem__("3", s))

    def test_independent_audit_rejects_forged_storage_export_provenance(self):
        snapshot = co2_case()
        snapshot["links"].append(cable(1, -1))
        result = self.solve(snapshot)
        self.assert_tamper_rejected(snapshot, result, lambda rows: rows[0]["path_flows"].append(
            {"source_id": 3, "station_id": 1, "sink_id": -1, "sent_mw": .1}))

    def test_fixture_writer_emits_audited_real_glpk_requests_and_results(self):
        with tempfile.TemporaryDirectory() as directory:
            summary = write_fixtures(directory, GLPK)
            self.assertEqual(len(summary["fixtures"]), 5)
            for fixture in summary["fixtures"]:
                name = fixture["name"]
                snapshot = json.loads((Path(directory)/(name+"_request.json")).read_text())
                result = json.loads((Path(directory)/(name+"_result.json")).read_text())
                self.assertTrue(result["solver_invoked"])
                self.assertTrue(backend.validate_schedule(backend.normalize(snapshot), result["steps"])["valid"])
                for row in result["steps"]:
                    for state in row["next_states"].values():
                        if "energy_mwh" in state:
                            self.assertGreaterEqual(state["energy_mwh"], 0.)
                if name == "co2_idle_decay":
                    self.assertTrue(result["negative_zero_normalization"]["raw_decisions_audited_first"])


if __name__ == "__main__":
    unittest.main()
