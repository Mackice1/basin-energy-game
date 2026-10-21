"""Stage-one joint electric/thermal GLPK acceptance and adversarial audit tests.

Run with real GLPK: PATH=/path/to/glpk/bin:$PATH python3 -m unittest discover
-s tests -p 'test_*dispatch_solver.py' -v. No thermal fallback is permitted.
"""
from __future__ import annotations

import copy
import importlib.util
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("thermal_backend_under_test", ROOT / "tools/dispatch_solver.py")
backend = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backend)
GLPK = shutil.which("glpsol")
EPS = 2e-6


def device(ident, kind, params=None, energy=None):
    result = {"id": ident, "kind": kind, "params": params or {}}
    if kind in backend.THERMAL_KINDS:
        result.update(model_profile="thermal_stage1_v1", model_profile_version=1)
    if energy is not None:
        result["state"] = {"energy_mwhth" if kind == "thermal_store" else "energy_mwh": energy}
    return result


def cable(source, target, cap=10, loss=0, boiler=False):
    result = {"from": source, "to": target, "capacity_mw": cap, "loss_fraction": loss}
    if boiler:
        result.update(from_port="out", to_port="ac_in", carrier="electricity_ac", unit="MW", voltage_level="AC_BUS")
    return result


def heat_line(source, target, source_kind="electric_boiler", target_kind="heat_exchanger", cap=10):
    fp, tp, grade = backend.THERMAL_ROUTES[(source_kind, target_kind)]
    return {"from": source, "to": target, "from_port": fp, "to_port": tp,
            "carrier": "heat_water", "unit": "MWth", "grade_id": grade,
            "capacity_mwth": cap, "loss_fraction": 0}


def step(generation=2, heat=2, *, time=0, dt=1, electricity=None):
    return {"time_s": time, "dt_h": dt, "available_mw": {"0": generation},
            "demand_mw": {} if electricity is None else {"5": electricity},
            "heat_demand_mwth": {"4": heat}}


def direct():
    return {"schema_version": 2, "devices": [device(0, "wind"),
            device(1, "station", {"capacity_mw": 10, "loss_fraction": 0}),
            device(2, "electric_boiler"), device(3, "heat_exchanger"), device(4, "heat_demand")],
            "links": [cable(0, 1), cable(1, 2, boiler=True), heat_line(2, 3),
                      heat_line(3, 4, "heat_exchanger", "heat_demand")],
            "steps": [step()], "options": {"timeout_s": 30}, "grid_capacity_mw": 4}


def with_store(energy=0, self_loss=0):
    snapshot = direct()
    snapshot["devices"].append(device(6, "thermal_store", {"self_discharge_per_h": self_loss}, energy))
    snapshot["links"].extend([heat_line(2, 6, "electric_boiler", "thermal_store"),
                              heat_line(6, 3, "thermal_store", "heat_exchanger")])
    return snapshot


class Base(unittest.TestCase):
    def solve(self, snapshot):
        before = copy.deepcopy(snapshot)
        result = backend.solve(snapshot, glpsol=GLPK)
        self.assertTrue(result["success"], result)
        self.assertEqual(result["status"], "optimal", result)
        self.assertEqual(result["objective"]["completed_stages"], 4)
        self.assertEqual(snapshot, before, "Predictions may not mutate live state")
        self.assertTrue(backend.validate_schedule(backend.normalize(snapshot), result["steps"])["valid"])
        for source, report in zip(snapshot["steps"], result["steps"]):
            heat = report["thermal"]
            self.assertAlmostEqual(report["produced_mw"]+report["discharge_mw"],
                report["served_mw"]+report["charge_mw"]+report["boiler_electric_mw"]+report["export_mw"]+report["network_loss_mw"], delta=EPS)
            self.assertAlmostEqual(heat["boiler_heat_mwth"]+heat["discharge_mwth"],
                heat["served_mwth"]+heat["charge_mwth"]+heat["exchanger_loss_mwth"]+heat["network_loss_mwth"], delta=EPS)
            self.assertAlmostEqual(heat["demand_mwth"], heat["served_mwth"]+heat["unserved_mwth"], delta=EPS)
            self.assertAlmostEqual(report["boiler_electric_mw"], heat["boiler_heat_mwth"]+report["boiler_conversion_loss_mw"], delta=EPS)
            self.assertAlmostEqual(heat["energy_balance_error_mwhth"], 0, delta=EPS)
            for node in snapshot["devices"]:
                if node["kind"] != "thermal_store":
                    continue
                detail = report["devices"][str(node["id"])]
                params = dict(backend.DEFAULTS["thermal_store"], **node["params"])
                dt = source["dt_h"]
                energy = detail["energy_before_mwhth"]*math.exp(-params["self_discharge_per_h"]*dt)
                energy += dt*(params["charge_efficiency"]*detail["charge_mwth"]-detail["discharge_mwth"]/params["discharge_efficiency"])
                self.assertAlmostEqual(detail["energy_mwhth"], energy, delta=EPS)
                self.assertLessEqual(min(detail["charge_mwth"], detail["discharge_mwth"]), EPS)
                self.assertNotIn("energy_mwh", detail)
                self.assertEqual(set(report["next_states"][str(node["id"])]), {"energy_mwhth"})
        return result

    def failure(self, snapshot, expected, executable=None):
        result = backend.solve(snapshot, glpsol=executable or GLPK or sys.executable)
        self.assertEqual(result["status"], expected, result)
        self.assertFalse(result["success"])
        self.assertFalse(result["steps"])
        return result


@unittest.skipUnless(GLPK, "Thermal integration tests require real glpsol")
class ThermalGLPKTests(Base):
    def test_integral_float_ids_after_json_save_restore(self):
        snapshot = with_store()
        original = backend.solve(snapshot, glpsol=GLPK)
        for node in snapshot["devices"]:
            node["id"] = float(node["id"])
        for line in snapshot["links"]:
            line["from"], line["to"] = float(line["from"]), float(line["to"])
        before = copy.deepcopy(snapshot)
        solved = backend.solve(snapshot, glpsol=GLPK)
        self.assertTrue(solved["success"], solved)
        self.assertTrue(solved["validation"]["valid"])
        self.assertEqual(solved["steps"], original["steps"])
        self.assertEqual(snapshot, before)

    def test_thermal_cli_round_trip_and_dimensioned_state(self):
        snapshot = with_store()
        snapshot["steps"] = [step(2, 0), step(0, 2, time=3600)]
        snapshot["metadata"] = {"request_id": "thermal-cli-test", "scene_revision": 17}
        with tempfile.TemporaryDirectory() as directory:
            source, target = Path(directory)/"input.json", Path(directory)/"output.json"
            source.write_text(json.dumps(snapshot))
            run = subprocess.run([sys.executable, str(ROOT/"tools/dispatch_solver.py"),
                                  "--input", str(source), "--output", str(target), "--glpsol", GLPK],
                                 capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
            result = json.loads(target.read_text())
        self.assertEqual(result["schema_version"], 2)
        self.assertEqual(result["metadata"], snapshot["metadata"])
        self.assertEqual(set(result["final_states"]["6"]), {"energy_mwhth"})
        self.assertTrue(result["validation"]["raw_decisions_validated"])
        self.assertAlmostEqual(result["steps"][1]["thermal"]["served_mwth"], 1.84473632, delta=EPS)

    def test_a_direct_heat_four_boundaries(self):
        result = self.solve(direct())
        report, heat = result["steps"][0], result["steps"][0]["thermal"]
        for field, value in (("boiler_heat_mwth", 1.96), ("served_mwth", 1.9208),
                             ("unserved_mwth", .0792), ("exchanger_loss_mwth", .0392)):
            self.assertAlmostEqual(heat[field], value, delta=EPS)
        self.assertAlmostEqual(report["boiler_electric_mw"], 2, delta=EPS)
        self.assertAlmostEqual(report["boiler_conversion_loss_mw"], .04, delta=EPS)
        self.assertEqual(report["unserved_mw"], 0)
        self.assertEqual(result["schema_version"], 2)

    def test_b_shared_electricity_and_heat(self):
        snapshot = direct()
        snapshot["devices"].append(device(5, "load", {"demand_mw": 1}))
        snapshot["links"].append(cable(1, 5))
        snapshot["steps"] = [step(2, .9604, electricity=1)]
        report = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(report["served_mw"], 1, delta=EPS)
        self.assertAlmostEqual(report["boiler_electric_mw"], 1, delta=EPS)
        self.assertAlmostEqual(report["thermal"]["served_mwth"], .9604, delta=EPS)

    def test_b_weighted_service_objective_under_competition(self):
        snapshot = direct()
        snapshot["devices"].append(device(5, "load", {"demand_mw": 1}))
        snapshot["links"].append(cable(1, 5))
        snapshot["steps"] = [step(1, .9604, electricity=1)]
        report = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(report["served_mw"], 1, delta=EPS)
        self.assertAlmostEqual(report["thermal"]["served_mwth"], 0, delta=EPS)
        snapshot["options"]["heat_service_weight"] = 2
        result = self.solve(snapshot)
        self.assertAlmostEqual(result["steps"][0]["thermal"]["served_mwth"], .9604, delta=EPS)
        self.assertAlmostEqual(result["steps"][0]["served_mw"], 0, delta=EPS)

    def test_c_two_hour_heat_storage_four_conversions(self):
        snapshot = with_store()
        snapshot["steps"] = [step(2, 0), step(0, 2, time=3600)]
        result = self.solve(snapshot)
        first, second = (report["thermal"] for report in result["steps"])
        self.assertAlmostEqual(first["charge_mwth"], 1.96, delta=EPS)
        self.assertAlmostEqual(first["energy_mwhth"], 1.9208, delta=EPS)
        self.assertAlmostEqual(second["discharge_mwth"], 1.882384, delta=EPS)
        self.assertAlmostEqual(second["served_mwth"], 1.84473632, delta=EPS)
        self.assertAlmostEqual(second["energy_mwhth"], 0, delta=EPS)
        self.assertEqual(result["initial_states"]["6"], {"energy_mwhth": 0})

    def test_d_isolated_storage_exact_decay_and_substeps(self):
        snapshot = {"schema_version": 2, "devices": [device(6, "thermal_store", {}, 1)],
                    "links": [], "steps": [{"time_s": 0, "dt_h": 1, "available_mw": {}, "demand_mw": {}, "heat_demand_mwth": {}}]}
        one = self.solve(snapshot)["steps"][0]["thermal"]
        self.assertAlmostEqual(one["energy_mwhth"], math.exp(-.002), delta=EPS)
        self.assertAlmostEqual(one["self_discharge_mwhth"], 1-math.exp(-.002), delta=EPS)
        snapshot["steps"] = [{"time_s": t*900, "dt_h": .25, "available_mw": {}, "demand_mw": {}, "heat_demand_mwth": {}} for t in range(4)]
        four = self.solve(snapshot)
        self.assertAlmostEqual(four["final_states"]["6"]["energy_mwhth"], one["energy_mwhth"], delta=EPS)

    def test_e_paused_step_freezes_every_exchange_and_inventory(self):
        snapshot = with_store(1, .002)
        snapshot["steps"] = [step(2, 2, dt=0)]
        snapshot["options"]["strict_supply"] = True
        result = self.solve(snapshot)
        report = result["steps"][0]
        self.assertEqual(report["thermal"]["energy_mwhth"], 1)
        self.assertEqual(report["thermal"]["self_discharge_mwhth"], 0)
        self.assertEqual(report["boiler_electric_mw"], 0)
        self.assertEqual(result["totals"]["thermal"]["unserved_mwhth"], 0)

    def test_e_empty_store_cannot_discharge(self):
        snapshot = with_store()
        snapshot["steps"] = [step(0, 2)]
        report = self.solve(snapshot)["steps"][0]
        self.assertEqual(report["thermal"]["discharge_mwth"], 0)
        self.assertEqual(report["thermal"]["served_mwth"], 0)

    def test_f_charged_store_supplies_without_boiler_electric_connection(self):
        snapshot = with_store(2)
        snapshot["links"].pop(1)
        snapshot["steps"] = [step(0, 1)]
        report = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(report["thermal"]["served_mwth"], 1, delta=EPS)
        self.assertAlmostEqual(report["boiler_electric_mw"], 0, delta=EPS)

    def test_f_split_and_merge_share_actual_capacities(self):
        snapshot = direct()
        snapshot["devices"].extend([device(7, "electric_boiler"), device(8, "heat_demand")])
        snapshot["links"].extend([cable(1, 7, boiler=True), heat_line(7, 3),
                                  heat_line(3, 8, "heat_exchanger", "heat_demand")])
        snapshot["steps"][0]["available_mw"]["0"] = 4
        snapshot["steps"][0]["heat_demand_mwth"]["8"] = 2
        report = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(report["devices"]["3"]["input_mwth"], 2, delta=EPS)
        self.assertAlmostEqual(report["thermal"]["served_mwth"], 1.96, delta=EPS)
        self.assertAlmostEqual(report["boiler_electric_mw"], 2/.98, delta=EPS)

    def test_g_exchanger_and_heat_line_bottlenecks(self):
        snapshot = direct()
        snapshot["devices"][3]["params"]["capacity_mwth"] = .5
        report = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(report["thermal"]["served_mwth"], .49, delta=EPS)
        snapshot["links"][2]["capacity_mwth"] = .25
        report = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(report["thermal"]["served_mwth"], .245, delta=EPS)

    def test_g_full_storage_and_no_demand_never_swallow_electricity(self):
        snapshot = with_store(4)
        snapshot["steps"] = [step(2, 0)]
        for export in (False, True):
            with self.subTest(export=export):
                if export:
                    snapshot["links"].append(cable(1, -1))
                report = self.solve(snapshot)["steps"][0]
                self.assertAlmostEqual(report["boiler_electric_mw"], 0, delta=EPS)
                self.assertAlmostEqual(report["thermal"]["charge_mwth"], 0, delta=EPS)
                self.assertAlmostEqual(report["export_mw"] if export else report["curtailed_mw"], 2, delta=EPS)

    def test_g_disconnected_outlet_and_unneeded_empty_storage_do_not_consume(self):
        for outlet in (False, True):
            snapshot = with_store()
            snapshot["steps"] = [step(2, 0)]
            if not outlet:
                snapshot["links"] = [line for line in snapshot["links"] if line["from"] != 2]
            report = self.solve(snapshot)["steps"][0]
            self.assertAlmostEqual(report["boiler_electric_mw"], 0, delta=EPS)
            self.assertAlmostEqual(report["thermal"]["energy_mwhth"], 0, delta=EPS)

    def test_losses_once_and_actual_dt_totals(self):
        snapshot = direct()
        snapshot["links"][0]["loss_fraction"] = .1
        snapshot["links"][1]["loss_fraction"] = .1
        snapshot["devices"][1]["params"]["loss_fraction"] = .1
        snapshot["steps"] = [step(2, 2, dt=.25)]
        result = self.solve(snapshot)
        report = result["steps"][0]
        self.assertAlmostEqual(report["boiler_electric_mw"], 2*.9**3, delta=EPS)
        self.assertAlmostEqual(report["thermal"]["served_mwth"], 2*.9**3*.98**2, delta=EPS)
        self.assertAlmostEqual(result["totals"]["thermal"]["served_mwhth"], .25*2*.9**3*.98**2, delta=EPS)

    def test_battery_can_power_boiler_without_cross_carrier_inventory(self):
        snapshot = direct()
        snapshot["devices"].append(device(9, "battery", {"capacity_mwh": 2, "discharge_efficiency": 1}, 1))
        snapshot["links"].append(cable(1, 9))
        snapshot["steps"] = [step(0, .9604)]
        result = self.solve(snapshot)
        self.assertAlmostEqual(result["steps"][0]["thermal"]["served_mwth"], .9604, delta=EPS)
        self.assertEqual(set(result["final_states"]["9"]), {"energy_mwh"})

    def test_terminal_heat_floor_is_separate_and_exact(self):
        snapshot = with_store()
        snapshot["steps"] = [step(2, 0)]
        snapshot["options"].update(terminal_soc_fraction=.9, terminal_heat_soc_fraction=.25)
        result = self.solve(snapshot)
        self.assertAlmostEqual(result["final_states"]["6"]["energy_mwhth"], 1, delta=EPS)
        self.assertAlmostEqual(result["steps"][0]["boiler_electric_mw"], 1/.98**2, delta=EPS)
        snapshot["options"].pop("terminal_heat_soc_fraction")
        self.assertAlmostEqual(self.solve(snapshot)["final_states"]["6"]["energy_mwhth"], 0, delta=EPS)

    def test_strict_heat_and_terminal_heat_infeasible(self):
        snapshot = direct()
        snapshot["options"]["strict_supply"] = True
        self.failure(snapshot, "infeasible")
        snapshot = with_store()
        snapshot["steps"] = [step(0, 0)]
        snapshot["options"]["terminal_heat_soc_fraction"] = .1
        self.failure(snapshot, "infeasible")

    def test_thermal_state_restore_has_identical_next_trajectory(self):
        snapshot = with_store()
        snapshot["steps"] = [step(2, 0), step(0, 2, time=3600)]
        result = self.solve(snapshot)
        resumed = with_store(result["steps"][0]["next_states"]["6"]["energy_mwhth"])
        resumed["steps"] = [step(0, 2, time=3600)]
        restored = self.solve(resumed)
        self.assertAlmostEqual(restored["steps"][0]["thermal"]["served_mwth"], result["steps"][1]["thermal"]["served_mwth"], delta=EPS)

    def test_tampered_reports_rejected_even_with_zero_residual_fields(self):
        snapshot = with_store()
        snapshot["steps"] = [step(2, 0), step(0, 2, time=3600)]
        result = self.solve(snapshot)
        problem = backend.normalize(snapshot)
        edits = [lambda r: r[0]["lines"][4].update(sent_mwth=1.5),
                 lambda r: r[0]["devices"]["6"].update(energy_mwhth=3),
                 lambda r: r[0]["next_states"]["6"].update(energy_mwhth=3),
                 lambda r: r[0]["thermal"].update(served_mwth=9),
                 lambda r: r[0]["devices"]["2"].update(boiler_electric_mw=0),
                 lambda r: r[0]["lines"][4].update(grade_id=backend.SECONDARY_GRADE),
                 lambda r: r[0]["devices"]["6"].update(mode_binary=0),
                 lambda r: r[0]["devices"]["3"].update(hot_return_c=41),
                 lambda r: r[0]["lines"].pop(),
                 lambda r: r[0]["next_states"]["6"].update(energy_mwh=1)]
        for edit in edits:
            reports = copy.deepcopy(result["steps"])
            edit(reports)
            with self.subTest(edit=edit):
                self.assertFalse(backend.validate_schedule(problem, reports)["valid"])

    def test_raw_physical_audit_is_independent_of_lp_rows_and_coefficients(self):
        snapshot = direct()
        problem = backend.normalize(snapshot)
        model = backend.build_model(problem)
        with tempfile.TemporaryDirectory() as tmp:
            import time
            run = backend.run_glpk(GLPK, model, 0, [], Path(tmp), time.monotonic()+10)
        self.assertEqual(run["status"], "optimal")
        values = run["values"]
        self.assertFalse(backend.validate_physical_decisions(problem, values))
        for field in ("boiler_0_2", "exchange_0_3", "heat_0_2", "heat_unmet_0_4"):
            modified = dict(values)
            modified[field] += .1
            self.assertTrue(backend.validate_physical_decisions(problem, modified), field)
        # A faulty LP could satisfy its own rows while wrongly increasing delivery.
        broken = copy.deepcopy(problem)
        broken["paths"][0]["received"] *= 1.1
        broken_model = backend.build_model(broken)
        with tempfile.TemporaryDirectory() as tmp:
            run = backend.run_glpk(GLPK, broken_model, 0, [], Path(tmp), time.monotonic()+10)
        self.assertFalse(backend.validate_decisions(broken_model, run["values"]))
        self.assertTrue(backend.validate_physical_decisions(broken, run["values"]))

    def test_feasible_unproven_thermal_solution_is_audited_and_labelled(self):
        real_run = backend.run_glpk
        def limited(*args, **kwargs):
            result = real_run(*args, **kwargs)
            result["status"] = "feasible"
            result["timed_out"] = True
            return result
        with mock.patch.object(backend, "run_glpk", side_effect=limited):
            result = backend.solve(direct(), GLPK)
        self.assertEqual(result["status"], "feasible", result)
        self.assertTrue(result["success"])
        self.assertFalse(result["optimal"])
        self.assertTrue(result["validation"]["valid"])
        self.assertEqual(result["termination_reason"], "timeout")

    def test_later_failure_keeps_only_prior_validated_thermal_incumbent(self):
        real_run = backend.run_glpk
        def fail_later(executable, model, stage, *args, **kwargs):
            if stage == 1:
                return {"status": "timeout", "values": {}, "log": "injected timeout"}
            return real_run(executable, model, stage, *args, **kwargs)
        with mock.patch.object(backend, "run_glpk", side_effect=fail_later):
            result = backend.solve(direct(), GLPK)
        self.assertEqual(result["status"], "feasible")
        self.assertEqual(result["objective"]["completed_stages"], 1)
        self.assertTrue(result["validation"]["valid"])
        self.assertAlmostEqual(result["steps"][0]["thermal"]["served_mwth"], 1.9208, delta=EPS)


class ThermalFailureTests(Base):
    def test_schema_parameters_states_and_typed_topology_rejected_atomically(self):
        cases = [lambda s: s.pop("schema_version"), lambda s: s.update(schema_version=4),
                 lambda s: s["devices"][2]["params"].update(thermal_efficiency=0),
                 lambda s: s["devices"][2]["params"].update(rated_electric_mw=True),
                 lambda s: s["devices"][2]["params"].update(rated_electric_mw=float("nan")),
                 lambda s: s["devices"][2]["params"].update(steam_temperature=90),
                 lambda s: s["devices"][2].update(model_profile="steam_v1"),
                 lambda s: s["devices"][2].update(model_profile_version=2),
                 lambda s: s["devices"][3]["params"].update(min_approach_k=20.01),
                 lambda s: s["devices"][4]["params"].update(priority=1.5),
                 lambda s: s["steps"][0].pop("heat_demand_mwth"),
                 lambda s: s["steps"][0]["heat_demand_mwth"].update({"99": 1}),
                 lambda s: s["links"][2].update(loss_fraction=.01),
                 lambda s: s["links"][2].update(capacity_mw=1),
                 lambda s: s["links"][2].update(unit="MW"),
                 lambda s: s["links"][2].update(carrier="steam"),
                 lambda s: s["links"][2].update(grade_id=backend.SECONDARY_GRADE),
                 lambda s: s["links"][2].update(from_port="steam_out"),
                 lambda s: s["links"][2].pop("to_port"),
                 lambda s: s["links"][2].update(to=4),
                 lambda s: s["links"][2].update(to=2),
                 lambda s: s["links"].append(copy.deepcopy(s["links"][2])),
                 lambda s: s["links"][1].update(to_port="heat_in"),
                 lambda s: s["links"][1].pop("to_port"),
                 lambda s: s["options"].update(heat_service_weight=True)]
        for edit in cases:
            snapshot = direct()
            edit(snapshot)
            with self.subTest(edit=edit), mock.patch.object(backend.subprocess, "Popen") as spawn:
                self.failure(snapshot, "error", sys.executable)
                spawn.assert_not_called()
        for energy in (-1, 4.1, float("nan"), True):
            snapshot = with_store(energy)
            self.failure(snapshot, "error", sys.executable)
        snapshot = with_store()
        snapshot["devices"][-1]["state"] = {"energy_mwh": 1}
        self.failure(snapshot, "error", sys.executable)

    def test_missing_solver_and_incomplete_decisions_never_fallback(self):
        result = self.failure(direct(), "error", "/nonexistent/glpsol")
        self.assertFalse(result["solver_invoked"])
        with mock.patch.object(backend, "run_glpk", return_value={"status": "optimal", "values": {}, "log": "invalid"}):
            result = self.failure(direct(), "error", sys.executable)
        self.assertTrue(result["solver_invoked"])

    def test_actual_process_timeout_cancellation_and_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            executable = Path(tmp)/"sleep-solver"
            executable.write_text("#!/usr/bin/env python3\nimport time\ntime.sleep(30)\n")
            executable.chmod(0o700)
            snapshot = direct()
            snapshot["options"]["timeout_s"] = .05
            self.failure(snapshot, "timeout", str(executable))
            snapshot["options"]["timeout_s"] = 5
            cancel = Path(tmp)/"cancel"
            timer = threading.Timer(.05, cancel.touch)
            timer.start()
            try:
                result = backend.solve(snapshot, str(executable), cancel)
            finally:
                timer.cancel()
                timer.join()
            self.assertEqual(result["status"], "cancelled")
            self.assertFalse(result["steps"])
            self.assertTrue(result["solver_invoked"])
            result = backend.solve(snapshot, str(executable), cancel)
            self.assertEqual(result["status"], "cancelled")
            self.assertFalse(result["solver_invoked"])
            executable.write_text("#!/usr/bin/env python3\nraise SystemExit(7)\n")
            self.failure(snapshot, "error", str(executable))


if __name__ == "__main__":
    unittest.main()
