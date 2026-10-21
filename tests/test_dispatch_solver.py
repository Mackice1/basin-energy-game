"""Numerical and failure-contract tests for the external GLPK dispatch backend.

Run from the project root with:
    python3 -m unittest discover -s tests -p 'test_dispatch_solver.py' -v

Real-solver tests are skipped when glpsol is not installed. Input validation,
missing-executable, and timeout tests do not require a GLPK installation.
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


PROJECT_ROOT = Path(__file__).resolve().parents[1]
BACKEND_PATH = PROJECT_ROOT / "tools" / "dispatch_solver.py"
GLPSOL = shutil.which("glpsol")
EPS = 2e-6


def load_backend():
    spec = importlib.util.spec_from_file_location("dispatch_solver_under_test", BACKEND_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load dispatch backend")
    module = importlib.util.module_from_spec(spec)
    # Dataclasses and other standard-library introspection consult sys.modules.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def device(identifier, kind, params=None, energy=None):
    result = {"id": identifier, "kind": kind, "params": params or {}}
    if energy is not None:
        result["state"] = {"energy_mwh": energy}
    return result


def cable(source, target, capacity=10.0, loss=0.0):
    return {"from": source, "to": target, "capacity_mw": capacity, "loss_fraction": loss}


def interval(available=2.0, demand=3.0, *, time=0.0, duration=1.0):
    return {"time_s": time, "dt_h": duration, "available_mw": {"0": available},
            "demand_mw": {"2": demand}}


def basic_snapshot():
    return {
        "devices": [device(0, "wind"), device(1, "station", {"capacity_mw": 10.0,
                                                               "loss_fraction": 0.0}),
                    device(2, "load", {"demand_mw": 3.0})],
        "links": [cable(0, 1), cable(1, 2)],
        "steps": [interval()],
        "options": {"strict_supply": False, "terminal_soc_fraction": None, "timeout_s": 30},
        "grid_capacity_mw": 4.0,
    }


class BackendTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.backend = load_backend()

    def assert_failed(self, result, status):
        self.assertIsInstance(result, dict)
        self.assertEqual(result.get("status"), status, result)
        self.assertIs(result.get("success"), False, result)
        # A rejected solve must not masquerade as an applicable dispatch.
        self.assertFalse(result.get("steps"), result)

    def assert_dispatch_invariants(self, snapshot, result):
        """Recompute physics from flows, without trusting reported residuals."""
        self.assertIs(result.get("success"), True, result)
        self.assertIn(result.get("status"), ("optimal", "feasible"), result)
        self.assertEqual(len(result["steps"]), len(snapshot["steps"]))
        nodes = {str(d["id"]): d for d in snapshot["devices"]}
        battery_defaults = {"capacity_mwh": 10.0, "charge_mw": 3.0,
                            "discharge_mw": 3.0, "charge_efficiency": 0.9,
                            "discharge_efficiency": 0.9, "self_discharge_per_h": 0.0,
                            "initial_soc": 0.5}
        batteries = {}
        energy = {}
        for identifier, node in nodes.items():
            if node["kind"] == "battery":
                params = dict(battery_defaults, **node.get("params", {}))
                batteries[identifier] = params
                energy[identifier] = node.get("state", {}).get(
                    "energy_mwh", params["capacity_mwh"] * params["initial_soc"])
        for source_step, report in zip(snapshot["steps"], result["steps"]):
            with self.subTest(time_s=source_step["time_s"]):
                self.assertEqual(set(report["devices"]), set(nodes))
                available = report["available_mw"]
                produced = available - report["curtailed_mw"]
                self.assertAlmostEqual(
                    produced + report["discharge_mw"],
                    report["served_mw"] + report["charge_mw"]
                    + report["delivered_mw"] + report["loss_mw"], delta=EPS)
                self.assertAlmostEqual(report["served_mw"] + report["unserved_mw"],
                                       report["demand_mw"], delta=EPS)
                self.assertGreaterEqual(report["delivered_mw"], -EPS)
                self.assertLessEqual(report["delivered_mw"],
                                     snapshot.get("grid_capacity_mw", 4.0) + EPS)
                self.assertEqual(len(report["lines"]), len(snapshot["links"]))
                line_loss = 0.0
                for line, link in zip(report["lines"], snapshot["links"]):
                    self.assertGreaterEqual(line["sent_mw"], -EPS)
                    self.assertLessEqual(line["sent_mw"], link["capacity_mw"] + EPS)
                    self.assertAlmostEqual(line["received_mw"],
                                           line["sent_mw"] * (1.0 - link["loss_fraction"]),
                                           delta=EPS)
                    self.assertAlmostEqual(line["loss_mw"],
                                           line["sent_mw"] - line["received_mw"], delta=EPS)
                    line_loss += line["sent_mw"] - line["received_mw"]
                station_loss = 0.0
                for identifier, node in nodes.items():
                    detail = report["devices"][identifier]
                    if node["kind"] == "station":
                        params = dict(capacity_mw=4.0, loss_fraction=0.01)
                        params.update(node.get("params", {}))
                        self.assertLessEqual(detail["input_mw"], params["capacity_mw"] + EPS)
                        self.assertAlmostEqual(detail["output_mw"], detail["input_mw"]
                                               * (1.0 - params["loss_fraction"]), delta=EPS)
                        station_loss += detail["input_mw"] - detail["output_mw"]
                    elif node["kind"] == "load":
                        self.assertGreaterEqual(detail["served_mw"], -EPS)
                        self.assertLessEqual(detail["served_mw"], detail["demand_mw"] + EPS)
                self.assertAlmostEqual(report["loss_mw"], line_loss + station_loss, delta=EPS)
                previous_total = sum(energy.values())
                conversion_loss = 0.0
                self_discharge = 0.0
                for identifier, params in batteries.items():
                    detail = report["devices"][identifier]
                    charge, discharge = detail["charge_mw"], detail["discharge_mw"]
                    self.assertGreaterEqual(charge, -EPS)
                    self.assertGreaterEqual(discharge, -EPS)
                    self.assertLessEqual(charge, params["charge_mw"] + EPS)
                    self.assertLessEqual(discharge, params["discharge_mw"] + EPS)
                    self.assertTrue(charge <= EPS or discharge <= EPS,
                                    "Battery simultaneously charges and discharges")
                    expected_mode = "charge" if charge > EPS else "discharge" if discharge > EPS else "idle"
                    self.assertEqual(detail["mode"], expected_mode)
                    remaining = energy[identifier] * math.exp(
                        -params["self_discharge_per_h"] * source_step["dt_h"])
                    self_discharge += energy[identifier] - remaining
                    expected = remaining + source_step["dt_h"] * (
                        params["charge_efficiency"] * charge
                        - discharge / params["discharge_efficiency"])
                    actual = report["next_states"][identifier]["energy_mwh"]
                    self.assertGreaterEqual(actual, -EPS)
                    self.assertLessEqual(actual, params["capacity_mwh"] + EPS)
                    self.assertAlmostEqual(actual, expected, delta=EPS)
                    self.assertAlmostEqual(detail["soc"], actual / params["capacity_mwh"], delta=EPS)
                    conversion_loss += charge * (1 - params["charge_efficiency"])
                    conversion_loss += discharge * (1 / params["discharge_efficiency"] - 1)
                    energy[identifier] = actual
                total_capacity = sum(p["capacity_mwh"] for p in batteries.values())
                self.assertAlmostEqual(report["energy_mwh"], sum(energy.values()), delta=EPS)
                self.assertAlmostEqual(report["soc"],
                                       sum(energy.values()) / total_capacity if total_capacity else 0.0,
                                       delta=EPS)
                expected_energy = previous_total - self_discharge + source_step["dt_h"] * (
                    produced - report["served_mw"] - report["delivered_mw"]
                    - line_loss - station_loss - conversion_loss)
                self.assertAlmostEqual(sum(energy.values()), expected_energy, delta=EPS)


@unittest.skipUnless(GLPSOL, "Integration tests require the glpsol executable")
class RealGLPKTests(BackendTestCase):
    def solve(self, snapshot):
        original = copy.deepcopy(snapshot)
        result = self.backend.solve(snapshot, glpsol=GLPSOL)
        self.assertEqual(snapshot, original, "Solving must not mutate the caller's live state")
        self.assert_dispatch_invariants(snapshot, result)
        return result

    def test_hand_computable_without_storage(self):
        snapshot = basic_snapshot()
        result = self.solve(snapshot)
        step = result["steps"][0]
        self.assertAlmostEqual(step["served_mw"], 2.0, delta=EPS)
        self.assertAlmostEqual(step["unserved_mw"], 1.0, delta=EPS)
        self.assertAlmostEqual(step["curtailed_mw"], 0.0, delta=EPS)
        self.assertAlmostEqual(step["loss_mw"], 0.0, delta=EPS)
        self.assertEqual(step["next_states"], {})
        self.assertEqual(result["status"], "optimal")

    def test_horizon_stores_surplus_then_supplies_later_load(self):
        snapshot = basic_snapshot()
        snapshot["devices"].append(device(3, "battery", {
            "capacity_mwh": 2.0, "charge_mw": 2.0, "discharge_mw": 2.0,
            "charge_efficiency": 0.8, "discharge_efficiency": 0.8}, energy=0.0))
        snapshot["links"].append(cable(1, 3))
        snapshot["steps"] = [interval(2.0, 0.0), interval(0.0, 1.28, time=3600.0)]
        snapshot["options"]["strict_supply"] = True
        first, second = self.solve(snapshot)["steps"]
        self.assertAlmostEqual(first["charge_mw"], 2.0, delta=EPS)
        self.assertAlmostEqual(first["energy_mwh"], 1.6, delta=EPS)
        self.assertAlmostEqual(second["discharge_mw"], 1.28, delta=EPS)
        self.assertAlmostEqual(second["served_mw"], 1.28, delta=EPS)
        self.assertAlmostEqual(second["energy_mwh"], 0.0, delta=EPS)

    def test_surplus_without_storage_need_does_not_charge_or_cycle(self):
        # Every load is already covered by renewable supply. Charging at the
        # beginning/end, or discharging between surplus periods, is gratuitous.
        for demands in [(0.0, 0.0, 0.0), (1.0, 1.0, 1.0)]:
            with self.subTest(demand_profile=demands):
                snapshot = basic_snapshot()
                snapshot["devices"].append(device(3, "battery", {"capacity_mwh": 2.0}, energy=0.0))
                snapshot["links"].append(cable(1, 3))
                snapshot["steps"] = [
                    interval(available, demand, time=index * 3600.0)
                    for index, (available, demand) in enumerate(zip((3.0, 1.0, 3.0), demands))
                ]
                result = self.solve(snapshot)
                for source_step, report in zip(snapshot["steps"], result["steps"]):
                    self.assertAlmostEqual(report["charge_mw"], 0.0, delta=EPS)
                    self.assertAlmostEqual(report["discharge_mw"], 0.0, delta=EPS)
                    self.assertAlmostEqual(report["energy_mwh"], 0.0, delta=EPS)
                    self.assertAlmostEqual(report["served_mw"], source_step["demand_mw"]["2"], delta=EPS)
                    self.assertAlmostEqual(report["curtailed_mw"],
                                           source_step["available_mw"]["0"] - source_step["demand_mw"]["2"],
                                           delta=EPS)
                self.assertAlmostEqual(result["totals"]["charge_mwh"], 0.0, delta=EPS)
                self.assertAlmostEqual(result["totals"]["discharge_mwh"], 0.0, delta=EPS)

    def test_positive_terminal_floor_charges_only_required_energy(self):
        snapshot = basic_snapshot()
        snapshot["devices"].append(device(3, "battery", {
            "capacity_mwh": 2.0, "charge_efficiency": 0.8}, energy=0.0))
        snapshot["links"].append(cable(1, 3))
        snapshot["steps"] = [interval(2.0, 0.0), interval(0.0, 0.0, time=3600.0)]
        snapshot["options"]["terminal_soc_fraction"] = 0.5
        first, second = self.solve(snapshot)["steps"]
        self.assertAlmostEqual(first["charge_mw"], 1.25, delta=EPS)
        self.assertAlmostEqual(first["curtailed_mw"], 0.75, delta=EPS)
        self.assertAlmostEqual(first["energy_mwh"], 1.0, delta=EPS)
        self.assertAlmostEqual(second["charge_mw"] + second["discharge_mw"], 0.0, delta=EPS)
        self.assertAlmostEqual(second["energy_mwh"], 1.0, delta=EPS)
        self.assertAlmostEqual(second["soc"], 0.5, delta=EPS)

    def test_storage_power_and_energy_limits(self):
        for energy, rating, duration, expected in [(5.0, 0.4, 1.0, 0.4),
                                                   (1.0, 3.0, 2.0, 0.4)]:
            with self.subTest(energy=energy, discharge_mw=rating, dt_h=duration):
                snapshot = basic_snapshot()
                snapshot["devices"].append(device(3, "battery", {
                    "discharge_mw": rating, "discharge_efficiency": 0.8}, energy=energy))
                snapshot["links"].append(cable(3, 1))
                snapshot["steps"] = [interval(0.0, 3.0, duration=duration)]
                step = self.solve(snapshot)["steps"][0]
                self.assertAlmostEqual(step["served_mw"], expected, delta=EPS)
        snapshot = basic_snapshot()
        snapshot["devices"].append(device(3, "battery", {
            "capacity_mwh": 1.0, "charge_efficiency": 0.5}, energy=0.75))
        snapshot["links"].append(cable(1, 3))
        snapshot["steps"] = [interval(2.0, 0.0)]
        snapshot["options"]["terminal_soc_fraction"] = 1.0
        step = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(step["charge_mw"], 0.5, delta=EPS)
        self.assertAlmostEqual(step["energy_mwh"], 1.0, delta=EPS)

    def test_disconnected_devices_cannot_exchange_energy(self):
        snapshot = basic_snapshot()
        snapshot["devices"].append(device(3, "battery", energy=1.0))
        snapshot["links"] = []
        step = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(step["served_mw"], 0.0, delta=EPS)
        self.assertAlmostEqual(step["unserved_mw"], 3.0, delta=EPS)
        self.assertAlmostEqual(step["curtailed_mw"], 2.0, delta=EPS)
        self.assertAlmostEqual(step["energy_mwh"], 1.0, delta=EPS)
        self.assertAlmostEqual(step["charge_mw"] + step["discharge_mw"], 0.0, delta=EPS)

    def test_each_network_bottleneck_and_losses(self):
        # Path yield is (1-.1)*(1-.2)*(1-.25) = .54.
        for incoming, station, outgoing, expected in [
            (1.0, 10.0, 10.0, 0.54),
            (10.0, 2.0, 10.0, 1.2),
            (10.0, 10.0, 1.0, 0.75),
        ]:
            with self.subTest(incoming=incoming, station=station, outgoing=outgoing):
                snapshot = basic_snapshot()
                snapshot["devices"][1]["params"] = {"capacity_mw": station, "loss_fraction": 0.2}
                snapshot["links"] = [cable(0, 1, incoming, 0.1), cable(1, 2, outgoing, 0.25)]
                snapshot["steps"] = [interval(5.0, 10.0)]
                step = self.solve(snapshot)["steps"][0]
                self.assertAlmostEqual(step["served_mw"], expected, delta=EPS)
                self.assertAlmostEqual(step["devices"]["0"]["sent_mw"], expected / 0.54, delta=EPS)

    def test_export_requires_explicit_cable_and_obeys_grid_limit(self):
        snapshot = basic_snapshot()
        snapshot["steps"] = [interval(3.0, 0.0)]
        without_export = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(without_export["delivered_mw"], 0.0, delta=EPS)
        self.assertAlmostEqual(without_export["curtailed_mw"], 3.0, delta=EPS)
        snapshot["links"].append(cable(1, -1))
        snapshot["grid_capacity_mw"] = 0.75
        with_export = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(with_export["delivered_mw"], 0.75, delta=EPS)
        self.assertAlmostEqual(with_export["curtailed_mw"], 2.25, delta=EPS)

    def test_battery_never_discharges_for_export(self):
        snapshot = basic_snapshot()
        snapshot["devices"].append(device(3, "battery", energy=5.0))
        snapshot["links"].extend([cable(3, 1), cable(1, -1)])
        snapshot["steps"] = [interval(0.0, 0.0)]
        step = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(step["delivered_mw"], 0.0, delta=EPS)
        self.assertAlmostEqual(step["discharge_mw"], 0.0, delta=EPS)
        self.assertAlmostEqual(step["energy_mwh"], 5.0, delta=EPS)

    def test_full_battery_cannot_cycle_to_hide_curtailment(self):
        # Without binary exclusivity, simultaneous charge/discharge could use
        # storage conversion losses to reduce apparent renewable curtailment.
        snapshot = basic_snapshot()
        snapshot["devices"].append(device(3, "battery", {"capacity_mwh": 2.0}, energy=2.0))
        snapshot["links"].append(cable(1, 3))
        snapshot["steps"] = [interval(3.0, 1.0)]
        step = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(step["served_mw"], 1.0, delta=EPS)
        self.assertAlmostEqual(step["curtailed_mw"], 2.0, delta=EPS)
        self.assertAlmostEqual(step["charge_mw"] + step["discharge_mw"], 0.0, delta=EPS)
        self.assertAlmostEqual(step["energy_mwh"], 2.0, delta=EPS)

    def test_default_storage_state_and_capacity_weighted_soc(self):
        snapshot = basic_snapshot()
        snapshot["devices"].extend([device(3, "battery"), device(4, "battery", {
            "capacity_mwh": 30.0, "self_discharge_per_h": 0.2}, energy=24.0)])
        snapshot["links"] = []
        snapshot["steps"] = [interval(0.0, 0.0, duration=0.5)]
        step = self.solve(snapshot)["steps"][0]
        expected = 5.0 + 24.0 * math.exp(-0.1)
        self.assertAlmostEqual(step["energy_mwh"], expected, delta=EPS)
        self.assertAlmostEqual(step["soc"], expected / 40.0, delta=EPS)

    def test_terminal_soc_and_strict_supply_cannot_be_silently_relaxed(self):
        snapshot = basic_snapshot()
        snapshot["devices"].append(device(3, "battery", {"capacity_mwh": 2.0}, energy=0.0))
        snapshot["links"].append(cable(3, 1))
        snapshot["steps"] = [interval(0.0, 0.0)]
        snapshot["options"].update(strict_supply=True, terminal_soc_fraction=0.5)
        self.assert_failed(self.backend.solve(snapshot, glpsol=GLPSOL), "infeasible")
        snapshot = basic_snapshot()
        snapshot["options"]["strict_supply"] = True
        self.assert_failed(self.backend.solve(snapshot, glpsol=GLPSOL), "infeasible")

    def test_cli_json_round_trip(self):
        with tempfile.TemporaryDirectory(prefix="basin-dispatch-cli-") as directory:
            source = Path(directory) / "snapshot.json"
            target = Path(directory) / "result.json"
            snapshot = basic_snapshot()
            snapshot["metadata"] = {"request_id": "test-request", "scene_revision": 17,
                                    "simulation_time": 123.5}
            source.write_text(json.dumps(snapshot), encoding="utf-8")
            completed = subprocess.run([sys.executable, str(BACKEND_PATH), "--input", str(source),
                                        "--output", str(target), "--glpsol", GLPSOL],
                                       capture_output=True, text=True, timeout=30, check=False)
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertTrue(target.is_file())
            result = json.loads(target.read_text(encoding="utf-8"))
            self.assert_dispatch_invariants(snapshot, result)
            self.assertEqual(result["metadata"], snapshot["metadata"])


class FailureContractTests(BackendTestCase):
    def test_missing_glpsol_is_a_structured_error(self):
        with tempfile.TemporaryDirectory(prefix="basin-dispatch-missing-") as directory:
            missing = str(Path(directory) / "missing-glpsol")
            result = self.backend.solve(basic_snapshot(), glpsol=missing)
        self.assert_failed(result, "error")

    def test_subprocess_timeout_is_a_structured_timeout(self):
        with tempfile.TemporaryDirectory(prefix="basin-dispatch-timeout-") as directory:
            executable = Path(directory) / "fake-glpsol"
            executable.write_text(f"#!{sys.executable}\nimport time\ntime.sleep(20)\n", encoding="utf-8")
            executable.chmod(0o700)
            snapshot = basic_snapshot()
            snapshot["options"]["timeout_s"] = 0.05
            result = self.backend.solve(snapshot, glpsol=str(executable))
        self.assert_failed(result, "timeout")

    def test_cancellation_stops_a_running_solver(self):
        with tempfile.TemporaryDirectory(prefix="basin-dispatch-cancel-") as directory:
            executable = Path(directory) / "fake-glpsol"
            executable.write_text(f"#!{sys.executable}\nimport time\ntime.sleep(20)\n", encoding="utf-8")
            executable.chmod(0o700)
            cancel_file = Path(directory) / "cancel"
            snapshot = basic_snapshot()
            snapshot["options"]["timeout_s"] = 5.0
            timer = threading.Timer(0.1, cancel_file.touch)
            timer.start()
            try:
                result = self.backend.solve(snapshot, glpsol=str(executable), cancel_file=cancel_file)
            finally:
                timer.cancel()
                timer.join()
        self.assert_failed(result, "cancelled")
        self.assertIs(result["solver_invoked"], True)

    def test_cli_preexisting_cancellation_file(self):
        with tempfile.TemporaryDirectory(prefix="basin-dispatch-cancel-cli-") as directory:
            source = Path(directory) / "snapshot.json"
            target = Path(directory) / "result.json"
            cancel_file = Path(directory) / "cancel"
            snapshot = basic_snapshot()
            snapshot["metadata"] = {"request_id": "cancelled-request"}
            source.write_text(json.dumps(snapshot), encoding="utf-8")
            cancel_file.touch()
            completed = subprocess.run([sys.executable, str(BACKEND_PATH), "--input", str(source),
                                        "--output", str(target), "--glpsol", sys.executable,
                                        "--cancel-file", str(cancel_file)],
                                       capture_output=True, text=True, timeout=10, check=False)
            self.assertNotEqual(completed.returncode, 0)
            result = json.loads(target.read_text(encoding="utf-8"))
        self.assert_failed(result, "cancelled")
        self.assertIs(result["solver_invoked"], False)
        self.assertEqual(result["metadata"], snapshot["metadata"])

    def test_untrusted_solver_output_is_rejected(self):
        with mock.patch.object(self.backend, "run_glpk", return_value={
                "status": "optimal", "values": {}, "log": "Deliberately incomplete test solution"}):
            result = self.backend.solve(basic_snapshot(), glpsol=sys.executable)
        self.assert_failed(result, "error")
        self.assertFalse(result["validation"]["valid"])

    def test_invalid_input_is_rejected_before_running_solver(self):
        cases = []

        def case(name, mutation):
            snapshot = basic_snapshot()
            mutation(snapshot)
            cases.append((name, snapshot))

        case("zero duration", lambda s: s["steps"][0].update(dt_h=0))
        case("negative duration", lambda s: s["steps"][0].update(dt_h=-1))
        case("nonfinite duration", lambda s: s["steps"][0].update(dt_h=float("nan")))
        case("negative generation", lambda s: s["steps"][0]["available_mw"].update({"0": -1}))
        case("nonfinite generation", lambda s: s["steps"][0]["available_mw"].update({"0": float("inf")}))
        case("negative demand", lambda s: s["steps"][0]["demand_mw"].update({"2": -1}))
        case("duplicate device id", lambda s: s["devices"].append(copy.deepcopy(s["devices"][0])))
        case("unsupported device", lambda s: s["devices"][0].update(kind="steam"))
        case("missing endpoint", lambda s: s["links"][0].update(to=999))
        case("illegal direct route", lambda s: s["links"].append(cable(0, 2)))
        case("duplicate cable", lambda s: s["links"].append(copy.deepcopy(s["links"][0])))
        case("negative line capacity", lambda s: s["links"][0].update(capacity_mw=-1))
        case("unit line loss", lambda s: s["links"][0].update(loss_fraction=1))
        case("empty horizon", lambda s: s.update(steps=[]))
        case("terminal fraction out of range", lambda s: s["options"].update(terminal_soc_fraction=1.01))
        case("invalid battery energy", lambda s: s["devices"].append(device(3, "battery", energy=11)))
        case("invalid battery efficiency", lambda s: s["devices"].append(device(3, "battery", {
            "charge_efficiency": 0.0})))
        case("negative grid limit", lambda s: s.update(grid_capacity_mw=-1))
        for name, snapshot in cases:
            with self.subTest(name=name), mock.patch.object(self.backend.subprocess, "Popen") as run:
                self.assert_failed(self.backend.solve(snapshot, glpsol=sys.executable), "error")
                run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
