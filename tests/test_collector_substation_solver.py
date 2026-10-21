"""Independent schema-10 collector-substation acceptance with real GLPK.

The collector is a 200 MW maximum active-power collection node. It adds no
voltage, reactive power, MVA conversion or station-to-station cascade model.
The original 32-kind DEFAULTS and all legacy solver fixtures remain unchanged.
"""
from __future__ import annotations

import ast
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("collector_backend", ROOT / "tools/dispatch_solver.py")
backend = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backend)
GLPK = shutil.which(os.environ.get("BASIN_GLPK", "glpsol"))
KIND = "collector_substation"
PROFILE = "collector_substation_v1"
EPS = 3e-6


def collector(ident, params=None):
    return {"id": ident, "kind": KIND, "model_profile": PROFILE,
            "model_profile_version": 1, "params": dict(params or {}), "state": {}}


def cable(source, target, capacity=200., loss=0.):
    return {"from": source, "to": target, "capacity_mw": capacity, "loss_fraction": loss,
            "from_port": "out", "to_port": "in", "carrier": "electricity_ac",
            "unit": "MW", "voltage_level": "AC_BUS"}


def collector_case():
    return {"schema_version": 10,
            "devices": [{"id": 0, "kind": "wind", "params": {"rated_mw": 300.}},
                        collector(1), {"id": 2, "kind": "load", "params": {}}],
            "links": [cable(0, 1, 300.), cable(1, 2, 300.)],
            "steps": [{"time_s": 0., "dt_h": 1., "available_mw": {"0": 300.},
                       "demand_mw": {"2": 300.}}], "options": {"timeout_s": 30.}}


def shared_collector_case():
    """Ten sources and two loads all share one incoming terminal-throughput cap."""
    snapshot = collector_case()
    snapshot["devices"] = [{"id": i, "kind": "pv", "params": {"dc_capacity_mw": 36., "inverter_capacity_mw": 30.}} for i in range(10)]
    snapshot["devices"] += [collector(10), {"id": 11, "kind": "load", "params": {"priority": 0}},
                            {"id": 12, "kind": "load", "params": {"priority": 100}}]
    snapshot["links"] = [cable(i, 10, 30., .02) for i in range(10)]
    snapshot["links"] += [cable(10, 11, 200., .03), cable(10, 12, 200., .04)]
    snapshot["steps"][0].update(available_mw={str(i): 30. for i in range(10)}, demand_mw={"11": 100., "12": 200.})
    return snapshot


def co2_collector_case():
    from test_co2_storage_solver import full_cycle_case
    snapshot = full_cycle_case()
    snapshot["schema_version"] = 10
    snapshot["devices"][1] = collector(1)
    for line in snapshot["links"]: line["capacity_mw"] = 200.
    snapshot["steps"][0]["available_mw"]["0"] = 146./.99
    snapshot["steps"][1]["demand_mw"]["2"] = 99.
    return snapshot


def material_collector_case():
    from test_material_solver import material_case
    snapshot = material_case(generation=.53/.99)
    snapshot["schema_version"] = 10
    snapshot["devices"][1] = collector(1)
    return snapshot


def material_co2_collector_case():
    from test_co2_storage_solver import mixed_material_case
    snapshot = mixed_material_case()
    snapshot["schema_version"] = 10
    snapshot["devices"][1] = collector(1)
    return snapshot


def invalid_cascade_case():
    snapshot = collector_case()
    snapshot["devices"].append({"id": 3, "kind": "station", "params": {}})
    snapshot["links"].append(cable(3, 1))
    return snapshot


def write_fixtures(directory, glpsol=None):
    """Persist requests and actual solver reports only after independent auditing."""
    executable = shutil.which(glpsol or GLPK or "glpsol")
    if not executable: raise RuntimeError("Real GLPK executable is required")
    cases = {"collector_shared_capacity": shared_collector_case(),
             "collector_co2_full_cycle": co2_collector_case(),
             "collector_material_cycle": material_collector_case(),
             "collector_material_co2": material_co2_collector_case()}
    staged = []
    summary = []
    for name, snapshot in cases.items():
        result = backend.solve(snapshot, glpsol=executable)
        if not (result.get("success") and result.get("solver_invoked") and result.get("status") == "optimal"
                and result.get("validation", {}).get("raw_decisions_validated")):
            raise RuntimeError(f"{name}: GLPK solve failed: {result}")
        audit = backend.validate_schedule(backend.normalize(snapshot), result["steps"])
        if not audit["valid"]: raise RuntimeError(f"{name}: independent audit failed: {audit}")
        staged.append((name, snapshot, result))
        summary.append({"name": name, "solver_invoked": True, "max_residual": audit["max_residual"]})
    invalid = invalid_cascade_case()
    rejected = backend.solve(invalid, glpsol=executable)
    if rejected["success"] or rejected["solver_invoked"] or rejected["steps"]:
        raise RuntimeError("Station cascade was not rejected before solver invocation")
    staged.append(("collector_invalid_cascade", invalid, rejected))
    summary.append({"name": "collector_invalid_cascade", "solver_invoked": False, "status": rejected["status"]})
    output = Path(directory)
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".collector_fixtures_", dir=output) as staging:
        for name, request, result in staged:
            for suffix, data in (("request", request), ("result", result)):
                (Path(staging)/(name+"_"+suffix+".json")).write_text(json.dumps(data, indent=2, allow_nan=False)+"\n", encoding="utf-8")
        for path in Path(staging).iterdir(): os.replace(path, output/path.name)
    return {"fixtures": summary, "output_dir": str(output)}


class CollectorInputTests(unittest.TestCase):
    def test_frozen_32_kind_defaults_and_legacy_station_are_unchanged(self):
        self.assertEqual(len(backend.DEFAULTS), 32)
        self.assertEqual(len(backend.DEFAULTS.keys()-{backend.CO2_STORAGE_KIND}-set(backend.MATERIAL_KINDS)), 27)
        self.assertEqual(len(backend.DEFAULTS.keys()-{backend.CO2_STORAGE_KIND}), 31)
        self.assertEqual(len(backend.SCHEMA_10_DEFAULTS), 33)
        self.assertNotIn(KIND, backend.DEFAULTS)
        self.assertEqual(backend.DEFAULTS["station"], {"capacity_mw": 4., "loss_fraction": .01})
        self.assertEqual(backend.RANGES["station"], {"capacity_mw": (0, 10000, True), "loss_fraction": (0, .999999)})
        self.assertEqual(backend.normalize(collector_case())["nodes"]["1"]["params"], {"capacity_mw": 200., "loss_fraction": .01})
        snapshot = collector_case()
        snapshot["devices"].append({"id": 3, "kind": "station", "params": {"capacity_mw": 10000.}})
        self.assertEqual(backend.normalize(snapshot)["nodes"]["3"]["params"]["capacity_mw"], 10000.)

    def test_helper_centralizes_role_without_treating_other_stations_as_electrical_buses(self):
        for kind in ("station", KIND): self.assertTrue(backend.is_electric_station(kind))
        for kind in (None, "fuel_cell_station", "electrolyzer_station", "pv", "grid", "STATION"):
            self.assertFalse(backend.is_electric_station(kind))
        tree = ast.parse((ROOT/"tools/dispatch_solver.py").read_text())
        for function in (n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name != "is_electric_station"):
            for node in ast.walk(function):
                if isinstance(node, ast.Compare):
                    self.assertFalse(any(isinstance(item, ast.Constant) and item.value == "station"
                                         for item in [node.left]+node.comparators), function.name)

    def test_earlier_schemas_reject_collector_and_schema_ten_is_reserved(self):
        for schema in range(1, 10):
            snapshot = collector_case(); snapshot["schema_version"] = schema
            with self.subTest(schema=schema), self.assertRaisesRegex(backend.InputError, "schema_version 10"):
                backend.normalize(snapshot)
        snapshot = collector_case(); snapshot["devices"][1] = {"id": 1, "kind": "station", "params": {}}
        with self.assertRaisesRegex(backend.InputError, "reserved"): backend.normalize(snapshot)
        for schema in (True, 10.1, 11, 0):
            snapshot = collector_case(); snapshot["schema_version"] = schema
            with self.subTest(schema=schema), self.assertRaises(backend.InputError): backend.normalize(snapshot)

    def test_capacity_hard_max_200_and_legacy_loss_range(self):
        for capacity in (1e-9, 1., 4., 199., 200.):
            snapshot = collector_case(); snapshot["devices"][1]["params"]["capacity_mw"] = capacity
            self.assertEqual(backend.normalize(snapshot)["nodes"]["1"]["params"]["capacity_mw"], capacity)
        for field, values in (("capacity_mw", (0., -1., 200.+1e-9, 10000., True, float("nan"), float("inf"), "200", None)),
                              ("loss_fraction", (-.01, 1., True, float("nan"), float("inf"), ".01", None))):
            for value in values:
                snapshot = collector_case(); snapshot["devices"][1]["params"][field] = value
                with self.subTest(field=field, value=value), self.assertRaises(backend.InputError): backend.normalize(snapshot)
        for loss in (0., .01, .999999):
            snapshot = collector_case(); snapshot["devices"][1]["params"]["loss_fraction"] = loss
            self.assertEqual(backend.normalize(snapshot)["nodes"]["1"]["params"]["loss_fraction"], loss)

    def test_exact_profile_empty_state_and_no_implicit_electrical_physics(self):
        edits = [("model_profile", value) for value in (None, "station", "collector_substation_v2", backend.CO2_STORAGE_PROFILE)]
        edits += [("model_profile_version", value) for value in (True, "1", 0, 2, None)]
        edits += [("state", value) for value in (None, [], {"energy_mwh": 0.}, {"voltage_kv": 110.})]
        edits += [("voltage_kv", 110.), ("capacity_mva", 200.)]
        for field, value in edits:
            snapshot = collector_case(); snapshot["devices"][1][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(backend.InputError): backend.normalize(snapshot)
        for field in ("voltage_kv", "power_factor", "capacity_mva", "transformer_ratio", "reactive_mvar"):
            snapshot = collector_case(); snapshot["devices"][1]["params"][field] = 1.
            with self.subTest(parameter=field), self.assertRaises(backend.InputError): backend.normalize(snapshot)

    def test_ports_are_ac_bus_in_and_out_only(self):
        problem = backend.normalize(collector_case())
        self.assertEqual(problem["links"][0]["to_port"], "in")
        self.assertEqual(problem["links"][1]["from_port"], "out")
        self.assertEqual(problem["paths"][0]["station"], "1")
        for field, value in (("voltage_level", "110kV"), ("unit", "MVA"), ("carrier", "electricity_dc"),
                             ("to_port", "ac_in"), ("capacity_mwth", 1.), ("grade_id", "HV")):
            snapshot = collector_case(); snapshot["links"][0][field] = value
            with self.subTest(field=field), self.assertRaises(backend.InputError): backend.normalize(snapshot)

    def test_all_station_cascades_are_rejected_even_if_both_devices_are_valid(self):
        for source_kind in ("station", KIND):
            for target_kind in ("station", KIND):
                snapshot = collector_case()
                snapshot["devices"] += [{"id": 3, "kind": source_kind, "params": {}},
                                        {"id": 4, "kind": target_kind, "params": {}}]
                snapshot["links"].append(cable(3, 4))
                with self.subTest(source=source_kind, target=target_kind), self.assertRaisesRegex(backend.InputError, "unsupported electricity route"):
                    backend.normalize(snapshot)

    def test_schema_ten_coexists_with_unchanged_co2_and_material_profile_one(self):
        problem = backend.normalize(material_co2_collector_case())
        self.assertTrue(problem["has_collector_substation"])
        self.assertTrue(problem["has_co2_storage"])
        self.assertTrue(problem["has_material"])
        self.assertEqual(backend._MATERIAL_DATA["profile_version"], 1)
        self.assertEqual(problem["nodes"]["7"]["kind"], backend.CO2_STORAGE_KIND)
        paths = {(p["source"], p["sink"]) for p in problem["paths"]}
        self.assertNotIn(("7", "4"), paths)
        self.assertNotIn(("7", "5"), paths)
        self.assertNotIn(("6", "7"), paths)
        self.assertIn(("0", "4"), paths)
        self.assertIn(("0", "5"), paths)
        self.assertIn(("6", "2"), paths)


@unittest.skipUnless(GLPK, "Real GLPK executable is required")
class CollectorGLPKTests(unittest.TestCase):
    def solve(self, snapshot):
        result = backend.solve(snapshot, glpsol=GLPK)
        self.assertTrue(result["success"], result)
        self.assertEqual(result["status"], "optimal", result)
        self.assertEqual(result["schema_version"], 10)
        self.assertTrue(result["solver_invoked"])
        self.assertTrue(result["validation"]["raw_decisions_validated"])
        audit = backend.validate_schedule(backend.normalize(snapshot), result["steps"])
        self.assertTrue(audit["valid"], audit)
        return result

    def test_many_sources_share_terminal_input_cap_and_losses(self):
        row = self.solve(shared_collector_case())["steps"][0]
        station = row["devices"]["10"]
        self.assertAlmostEqual(station["input_mw"], 200., delta=EPS)
        self.assertAlmostEqual(station["output_mw"], 198., delta=EPS)
        self.assertAlmostEqual(station["loss_mw"], 2., delta=EPS)
        self.assertAlmostEqual(row["station_loss_mw"], 2., delta=EPS)
        self.assertAlmostEqual(station["utilization"], 1., delta=EPS)
        self.assertAlmostEqual(row["devices"]["11"]["served_mw"], 100., delta=EPS)
        self.assertAlmostEqual(row["devices"]["12"]["served_mw"], (198.-100./.97)*.96, delta=EPS)
        self.assertAlmostEqual(sum(d["produced_mw"] for d in row["devices"].values() if d["kind"] == "pv"), 200./.98, delta=EPS)
        self.assertGreater(sum(d["produced_mw"] > EPS for d in row["devices"].values() if d["kind"] == "pv"), 1)

    def test_large_co2_cycle_uses_200mw_collector_without_increasing_storage_ratings(self):
        result = self.solve(co2_collector_case())
        charge, discharge = result["steps"]
        self.assertAlmostEqual(charge["devices"]["3"]["charge_mw"], 146., delta=EPS)
        self.assertAlmostEqual(charge["devices"]["3"]["energy_mwh"], 794.24, delta=EPS)
        self.assertAlmostEqual(discharge["devices"]["3"]["discharge_mw"], 100., delta=EPS)
        self.assertAlmostEqual(discharge["devices"]["3"]["energy_mwh"], 0., delta=EPS)
        self.assertAlmostEqual(discharge["served_mw"], 99., delta=EPS)
        self.assertAlmostEqual(discharge["served_mw"]*6.14, 607.86, delta=EPS)
        self.assertAlmostEqual(charge["devices"]["1"]["input_mw"], 146./.99, delta=EPS)
        self.assertEqual(result["collector_substation_assumptions"]["capacity_limit_mw"], 200.)
        self.assertIn("not MVA", result["collector_substation_assumptions"]["capacity_basis"])

    def test_2a_material_cycle_uses_real_collector_input_and_loss(self):
        result = self.solve(material_collector_case())
        first, second = result["steps"]
        self.assertAlmostEqual(first["material"]["hydrogen_inventory_kg"], 10., delta=EPS)
        self.assertAlmostEqual(first["material"]["electrolyzer_electric_mw"], .5, delta=EPS)
        self.assertAlmostEqual(first["material"]["compression_electric_mw"], .03, delta=EPS)
        self.assertAlmostEqual(first["devices"]["1"]["input_mw"], .53/.99, delta=EPS)
        expected = 10.*backend.MATERIAL_COEFFICIENTS["lhv_kwh_per_kg"]*.5/1000.
        self.assertAlmostEqual(second["material"]["fuel_cell_output_mw"], expected, delta=EPS)
        self.assertAlmostEqual(second["served_mw"], expected*.99, delta=EPS)
        self.assertAlmostEqual(second["material"]["hydrogen_inventory_kg"], 0., delta=EPS)

    def test_same_bus_storage_and_fuel_cell_cannot_supply_material_auxiliaries(self):
        snapshot = material_co2_collector_case()
        snapshot["steps"] = snapshot["steps"][:1]
        snapshot["steps"][0]["available_mw"]["0"] = 0.
        snapshot["steps"][0]["demand_mw"]["2"] = 1.
        snapshot["devices"][5]["state"]["material_inventory_kg"]["H2"] = 1.
        snapshot["devices"][7]["state"] = {"energy_mwh": 1.}
        snapshot["options"].pop("terminal_hydrogen_kg")
        snapshot["options"].pop("terminal_soc_fraction")
        row = self.solve(snapshot)["steps"][0]
        self.assertGreater(row["served_mw"], 0.)
        self.assertEqual(row["material"]["electrolyzer_electric_mw"], 0.)
        self.assertEqual(row["material"]["compression_electric_mw"], 0.)
        self.assertEqual(row["material"]["hydrogen_produced_kg_s"], 0.)
        for flow in row["path_flows"]:
            if flow["sink_id"] in (4, 5): self.assertEqual(flow["source_id"], 0)

    def test_separate_old_and_new_stars_keep_independent_capacity_and_loss_ledgers(self):
        snapshot = collector_case()
        snapshot["devices"] += [{"id": 3, "kind": "wind", "params": {}},
                                {"id": 4, "kind": "station", "params": {}},
                                {"id": 5, "kind": "load", "params": {}}]
        snapshot["links"] += [cable(3, 4), cable(4, 5)]
        snapshot["steps"][0]["available_mw"]["3"] = 5.
        snapshot["steps"][0]["demand_mw"]["5"] = 5.
        row = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(row["devices"]["1"]["input_mw"], 200., delta=EPS)
        self.assertAlmostEqual(row["devices"]["4"]["input_mw"], 4., delta=EPS)
        self.assertAlmostEqual(row["devices"]["2"]["served_mw"], 198., delta=EPS)
        self.assertAlmostEqual(row["devices"]["5"]["served_mw"], 3.96, delta=EPS)
        self.assertAlmostEqual(row["station_loss_mw"], 2.04, delta=EPS)
        self.assertNotIn("model_profile", row["devices"]["4"])

    def test_audit_rejects_collector_identity_capacity_utilization_and_loss_forgery(self):
        snapshot = collector_case(); result = self.solve(snapshot)
        for field in ("input_mw", "output_mw", "sent_mw", "received_mw", "capacity_mw", "utilization", "loss_mw"):
            for value in (42., True, float("nan"), float("inf")):
                rows = copy.deepcopy(result["steps"]); rows[0]["devices"]["1"][field] = value
                with self.subTest(field=field, value=value):
                    self.assertFalse(backend.validate_schedule(backend.normalize(snapshot), rows)["valid"])
        for field, value in (("kind", "station"), ("model_profile", "station"), ("model_profile_version", True)):
            rows = copy.deepcopy(result["steps"]); rows[0]["devices"]["1"][field] = value
            with self.subTest(field=field): self.assertFalse(backend.validate_schedule(backend.normalize(snapshot), rows)["valid"])
        for field in ("model_profile", "model_profile_version"):
            rows = copy.deepcopy(result["steps"]); rows[0]["devices"]["1"].pop(field)
            self.assertFalse(backend.validate_schedule(backend.normalize(snapshot), rows)["valid"])

    def test_original_topology_audit_rejects_forged_same_bus_material_provenance(self):
        snapshot = material_co2_collector_case(); result = self.solve(snapshot)
        for source in (6, 7):
            problem = backend.normalize(snapshot); rows = copy.deepcopy(result["steps"])
            # Forge both the cached helper path and its matching reported identity.
            # The independent material audit must reconstruct the original cables.
            index = next(i for i, p in enumerate(problem["paths"]) if p["source"] == "0" and p["sink"] == "4")
            problem["paths"][index]["source"] = str(source)
            rows[0]["path_flows"][index]["source_id"] = source
            audit = backend.validate_schedule(problem, rows)
            self.assertFalse(audit["valid"])
            self.assertTrue(any("eligible provenance" in e for e in audit["errors"]), audit)

    def test_raw_physics_rejects_feasible_model_with_forged_loss_helper(self):
        original = backend.build_model
        def wrong_model(problem):
            forged = copy.deepcopy(problem)
            for path in forged["paths"]:
                path["after"] = path["arriving"]
                path["received"] = path["arriving"]*(1-forged["links"][path["outgoing"]]["loss_fraction"])
            return original(forged)
        with mock.patch.object(backend, "build_model", side_effect=wrong_model):
            result = backend.solve(collector_case(), glpsol=GLPK)
        self.assertFalse(result["success"], result)
        self.assertEqual(result["steps"], [])
        self.assertTrue(result["solver_invoked"])
        self.assertEqual(result["status"], "error")

    def test_raw_physics_rejects_shared_capacity_constraint_removed_from_lp(self):
        original = backend.build_model
        def wrong_model(problem):
            model = original(problem)
            model.rows = [row for row in model.rows if not (row[1] == "<=" and row[2] == 200.
                         and row[0] == {"x_0_0": 1.})]
            return model
        with mock.patch.object(backend, "build_model", side_effect=wrong_model):
            result = backend.solve(collector_case(), glpsol=GLPK)
        self.assertFalse(result["success"], result)
        self.assertTrue(result["solver_invoked"])
        self.assertEqual(result["steps"], [])

    def test_audit_rejects_forged_storage_cable_direction(self):
        snapshot = material_co2_collector_case(); result = self.solve(snapshot)
        problem = backend.normalize(snapshot)
        index = next(i for i, line in enumerate(problem["links"]) if line.get("leaf") == "7")
        rows = copy.deepcopy(result["steps"])
        line = rows[0]["lines"][index]
        self.assertGreater(line["sent_mw"], .1)
        line["flow_from"], line["flow_to"] = line["flow_to"], line["flow_from"]
        line["direction"] *= -1
        line["signed_mw"] *= -1
        audit = backend.validate_schedule(problem, rows)
        self.assertFalse(audit["valid"])
        self.assertTrue(any("direction provenance" in error for error in audit["errors"]), audit)

    def test_dominant_direction_keeps_substantive_counterflow_and_both_audits_reject_it(self):
        snapshot = material_co2_collector_case()
        original = backend.run_glpk
        captured = []
        def capture(*args, **kwargs):
            result = original(*args, **kwargs)
            if result["status"] in ("optimal", "feasible"):
                captured.append(copy.deepcopy(result["values"]))
            return result
        with mock.patch.object(backend, "run_glpk", side_effect=capture):
            self.solve(snapshot)
        problem = backend.normalize(snapshot)
        values = captured[-1]
        index = next(i for i, path in enumerate(problem["paths"]) if path["source"] == "7" and path["sink"] == "2")
        values[f"x_0_{index}"] = .1
        rows = backend.assemble_schedule(problem, values)
        storage = rows[0]["devices"]["7"]
        self.assertGreater(storage["input_mw"], .1)
        self.assertAlmostEqual(storage["output_mw"], .1, delta=1e-12)
        line_index = next(i for i, line in enumerate(problem["links"]) if line.get("leaf") == "7")
        line = rows[0]["lines"][line_index]
        self.assertAlmostEqual(line["sent_mw"], storage["input_mw"]+.1, delta=1e-12)
        self.assertEqual(values[f"x_0_{index}"], .1)
        self.assertEqual(rows[0]["path_flows"][index]["sent_mw"], .1)
        self.assertTrue(backend.validate_decisions(backend.build_model(problem), values))
        audit = backend.validate_schedule(problem, rows)
        self.assertFalse(audit["valid"])
        self.assertTrue(any("storage" in error.lower() for error in audit["errors"]), audit)
        self.assertTrue(backend.validate_physical_decisions(problem, values))

    def test_zero_duration_and_strict_supply_do_not_bypass_collector_limit(self):
        snapshot = collector_case(); snapshot["steps"][0]["dt_h"] = 0.
        row = self.solve(snapshot)["steps"][0]
        self.assertEqual(row["devices"]["1"]["input_mw"], 0.)
        self.assertEqual(row["devices"]["1"]["output_mw"], 0.)
        self.assertEqual(row["next_states"], {})
        snapshot = collector_case(); snapshot["options"]["strict_supply"] = True
        result = backend.solve(snapshot, glpsol=GLPK)
        self.assertFalse(result["success"])
        self.assertEqual(result["status"], "infeasible")
        self.assertEqual(result["steps"], [])

    def test_schema_ten_preserves_material_and_co2_no_presolve_numerical_safeguards(self):
        for snapshot in (co2_collector_case(), material_collector_case(), material_co2_collector_case()):
            self.assertTrue(backend.build_model(backend.normalize(snapshot)).rankine_no_presolve)
        original = backend.run_glpk
        calls = []
        def first_invalid(executable, model, stage, locks, *args, **kwargs):
            calls.append((stage, copy.deepcopy(locks), copy.deepcopy(model.rows), tuple(model.binaries), kwargs.get("simplex_dual", False)))
            result = original(executable, model, stage, locks, *args, **kwargs)
            if len(calls) == 1: result["values"]["material_0_5"] = -1e-4
            return result
        with mock.patch.object(backend, "run_glpk", side_effect=first_invalid):
            result = self.solve(material_co2_collector_case())
        self.assertEqual(calls[0][:-1], calls[1][:-1])
        self.assertFalse(calls[0][-1]); self.assertTrue(calls[1][-1])
        self.assertTrue(result["solver_stages"][0]["rejected_initial_run"]["errors"])
        self.assertEqual(result["solver_stages"][0]["same_model_dual_retry"]["errors"], [])

    def test_schema_ten_does_not_normalize_substantive_negative_decisions(self):
        original = backend.run_glpk
        calls = []
        def invalid(*args, **kwargs):
            calls.append(kwargs.get("simplex_dual", False))
            result = original(*args, **kwargs)
            result["values"]["material_0_5"] = -1e-4
            return result
        with mock.patch.object(backend, "run_glpk", side_effect=invalid):
            result = backend.solve(material_co2_collector_case(), glpsol=GLPK)
        self.assertEqual(calls, [False, True])
        self.assertFalse(result["success"])
        self.assertEqual(result["steps"], [])
        self.assertNotIn("negative_zero_normalization", result)

    def test_schema_ten_negative_zero_requires_raw_audit_and_rebuilt_report(self):
        original = backend.run_glpk
        snapshot = material_collector_case()
        snapshot["steps"] = snapshot["steps"][:1]
        snapshot["steps"][0]["available_mw"]["0"] = 0.
        def negative_zero(*args, **kwargs):
            result = original(*args, **kwargs)
            if result["status"] in ("optimal", "feasible"):
                result["values"]["material_0_5"] = -1e-15
            return result
        with mock.patch.object(backend, "run_glpk", side_effect=negative_zero):
            result = self.solve(snapshot)
        note = result["negative_zero_normalization"]
        self.assertTrue(note["raw_decisions_audited_first"])
        self.assertTrue(note["report_rebuilt_and_reaudited"])
        self.assertEqual(note["exclusive_lower_bound"], -1e-12)
        self.assertGreaterEqual(note["decision_count"], 1)
        self.assertEqual(result["steps"][0]["next_states"]["5"]["material_inventory_kg"]["H2"], 0.)

    def test_fixture_writer_covers_audited_cases_and_pre_solver_cascade_rejection(self):
        with tempfile.TemporaryDirectory() as directory:
            summary = write_fixtures(directory, GLPK)
            self.assertEqual(len(summary["fixtures"]), 5)
            for fixture in summary["fixtures"]:
                name = fixture["name"]
                snapshot = json.loads((Path(directory)/(name+"_request.json")).read_text())
                result = json.loads((Path(directory)/(name+"_result.json")).read_text())
                if fixture["solver_invoked"]:
                    self.assertTrue(backend.validate_schedule(backend.normalize(snapshot), result["steps"])["valid"])
                else:
                    self.assertFalse(result["success"])
                    self.assertFalse(result["solver_invoked"])
                    self.assertFalse(result["steps"])


if __name__ == "__main__": unittest.main()
