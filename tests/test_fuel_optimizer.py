"""Real-GLPK fuel/AC/heat coupling, finite resources and independent audit."""
import copy
from pathlib import Path
import tempfile
import time
import unittest
from unittest import mock

from test_thermal_dispatch_solver import backend, GLPK, EPS, device, cable, heat_line


def fuel_case(cap=2, generation=2, heat=2, dt=1):
    return {"schema_version": 3,
        "devices": [device(0, "wind"), device(1, "station", {"capacity_mw": 10, "loss_fraction": 0}),
                    device(2, "fuel_boiler"), device(3, "heat_exchanger"), device(4, "heat_demand")],
        "links": [cable(0, 1), cable(1, 2, boiler=True), heat_line(2, 3, "fuel_boiler"),
                  heat_line(3, 4, "heat_exchanger", "heat_demand")],
        "steps": [{"time_s": 0, "dt_h": dt, "available_mw": {"0": generation},
                   "demand_mw": {}, "heat_demand_mwth": {"4": heat}}],
        "fuel_supply": dict(backend.FUEL_SUPPLY_DEFAULTS, enabled=True, max_input_mw=cap),
        "options": {"timeout_s": 30}}


@unittest.skipUnless(GLPK, "Fuel integration requires real glpsol")
class FuelOptimizerTests(unittest.TestCase):
    def solve(self, snapshot):
        before = copy.deepcopy(snapshot)
        result = backend.solve(snapshot, glpsol=GLPK)
        self.assertTrue(result["success"], result)
        self.assertTrue(result["solver_invoked"])
        self.assertEqual(result["objective"]["completed_stages"], 5)
        self.assertTrue(result["validation"]["valid"])
        self.assertEqual(snapshot, before, "Optimization must not mutate the live snapshot")
        self.assertTrue(backend.validate_schedule(backend.normalize(snapshot), result["steps"])["valid"])
        for row in result["steps"]:
            fuel, heat = row["fuel"], row["thermal"]
            self.assertAlmostEqual(fuel["input_mw"], fuel["heat_output_mwth"]+fuel["conversion_loss_mw"], delta=EPS)
            self.assertAlmostEqual(fuel["auxiliary_electric_mw"], fuel["auxiliary_electric_loss_mw"], delta=EPS)
            self.assertAlmostEqual(row["balance_error_mw"], 0, delta=EPS)
            self.assertAlmostEqual(row["energy_balance_error_mwh"], 0, delta=EPS)
            self.assertAlmostEqual(heat["balance_error_mwth"], 0, delta=EPS)
            self.assertAlmostEqual(heat["energy_balance_error_mwhth"], 0, delta=EPS)
        return result

    def test_catalog3_and_legacy2_fuel_requests_are_both_supported(self):
        for schema in (2, 3):
            snapshot = fuel_case()
            snapshot["schema_version"] = schema
            result = self.solve(snapshot)
            self.assertEqual(result["schema_version"], schema)

    def test_fuel_cap_conversion_auxiliary_and_teaching_cost(self):
        result = self.solve(fuel_case(.5, dt=.25))
        row = result["steps"][0]
        for key, expected in (("input_mw", .5), ("heat_output_mwth", .45), ("conversion_loss_mw", .05),
                              ("auxiliary_electric_mw", .005), ("auxiliary_electric_loss_mw", .005),
                              ("volume_nm3_per_h", 50), ("cost_per_h", 150)):
            self.assertAlmostEqual(row["fuel"][key], expected, delta=EPS)
        self.assertAlmostEqual(row["thermal"]["served_mwth"], .441, delta=EPS)
        self.assertEqual(row["thermal"]["boiler_heat_mwth"], 0)
        self.assertEqual(row["boiler_electric_mw"], 0)
        self.assertAlmostEqual(result["totals"]["fuel"]["input_mwh"], .125, delta=EPS)
        self.assertAlmostEqual(result["totals"]["fuel"]["volume_nm3"], 12.5, delta=EPS)
        self.assertAlmostEqual(result["totals"]["fuel"]["cost"], 37.5, delta=EPS)
        self.assertFalse(result["objective"]["economic_optimality_claimed"])
        self.assertFalse(result["fuel_assumptions"]["emissions_model"])

    def test_missing_disabled_and_zero_supply_cannot_create_heat(self):
        for mode in ("missing", "disabled", "zero"):
            snapshot = fuel_case()
            if mode == "missing": snapshot.pop("fuel_supply")
            elif mode == "disabled": snapshot["fuel_supply"]["enabled"] = False
            else: snapshot["fuel_supply"]["max_input_mw"] = 0
            with self.subTest(mode=mode):
                row = self.solve(snapshot)["steps"][0]
                self.assertAlmostEqual(row["fuel"]["input_mw"], 0, delta=EPS)
                self.assertAlmostEqual(row["thermal"]["served_mwth"], 0, delta=EPS)

    def test_ac_shortage_and_line_rating_cannot_be_bypassed(self):
        for mode in ("source", "line", "losses"):
            snapshot = fuel_case(generation=.005 if mode == "source" else 2)
            if mode == "line": snapshot["links"][1]["capacity_mw"] = .005
            if mode == "losses":
                snapshot["steps"][0]["available_mw"]["0"] = .04
                snapshot["links"][0]["loss_fraction"] = .5
                snapshot["devices"][1]["params"]["loss_fraction"] = .5
                snapshot["links"][1]["loss_fraction"] = .5
            with self.subTest(mode=mode):
                row = self.solve(snapshot)["steps"][0]
                self.assertAlmostEqual(row["fuel"]["input_mw"], .5, delta=EPS)
                self.assertAlmostEqual(row["devices"]["2"]["input_mw"], .005, delta=EPS)

    def test_missing_ac_or_zero_generation_prevents_burning(self):
        for disconnected in (True, False):
            snapshot = fuel_case(generation=2 if disconnected else 0)
            if disconnected: snapshot["links"].pop(1)
            row = self.solve(snapshot)["steps"][0]
            self.assertAlmostEqual(row["fuel"]["input_mw"], 0, delta=EPS)

    def test_no_heat_sink_or_full_storage_prevents_burning(self):
        for mode in ("disconnected", "zero_demand", "full_storage"):
            snapshot = fuel_case(heat=0 if mode != "disconnected" else 2)
            if mode == "disconnected": snapshot["links"].pop(2)
            if mode == "full_storage":
                snapshot["devices"].append(device(6, "thermal_store", {"self_discharge_per_h": 0}, 4))
                snapshot["links"].append(heat_line(2, 6, "fuel_boiler", "thermal_store"))
            with self.subTest(mode=mode):
                self.assertAlmostEqual(self.solve(snapshot)["steps"][0]["fuel"]["input_mw"], 0, delta=EPS)

    def test_resource_is_shared_across_boilers_each_step(self):
        snapshot = fuel_case(.75)
        snapshot["devices"].append(device(5, "fuel_boiler"))
        snapshot["links"] += [cable(1, 5, boiler=True), heat_line(5, 3, "fuel_boiler")]
        snapshot["steps"].append(dict(snapshot["steps"][0], time_s=3600))
        result = self.solve(snapshot)
        for row in result["steps"]:
            self.assertAlmostEqual(row["fuel"]["input_mw"], .75, delta=EPS)
            self.assertAlmostEqual(sum(row["devices"][k]["fuel_input_mw"] for k in ("2", "5")), .75, delta=EPS)
            self.assertAlmostEqual(row["thermal"]["served_mwth"], .6615, delta=EPS)

    def test_stored_fuel_heat_can_serve_later_without_ac(self):
        snapshot = fuel_case(heat=0)
        snapshot["devices"].append(device(6, "thermal_store", {"self_discharge_per_h": 0}, 0))
        snapshot["links"] += [heat_line(2, 6, "fuel_boiler", "thermal_store"),
                               heat_line(6, 3, "thermal_store", "heat_exchanger")]
        snapshot["steps"].append(dict(snapshot["steps"][0], time_s=3600, available_mw={"0": 0}, heat_demand_mwth={"4": 1}))
        result = self.solve(snapshot)
        self.assertGreater(result["steps"][0]["fuel"]["input_mw"], 1)
        self.assertAlmostEqual(result["steps"][1]["fuel"]["input_mw"], 0, delta=EPS)
        self.assertAlmostEqual(result["steps"][1]["thermal"]["served_mwth"], 1, delta=EPS)
        for row in result["steps"]:
            store = row["devices"]["6"]
            self.assertLessEqual(min(store["charge_mwth"], store["discharge_mwth"]), EPS)
            self.assertEqual(set(row["next_states"]["6"]), {"energy_mwhth"})

    def test_battery_can_supply_auxiliary_and_remains_dimensioned(self):
        snapshot = fuel_case(generation=0)
        snapshot["devices"].append(device(5, "battery", {}, 1))
        snapshot["links"].append(cable(1, 5))
        row = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(row["fuel"]["input_mw"], 2, delta=EPS)
        self.assertAlmostEqual(row["discharge_mw"], .02, delta=EPS)
        self.assertEqual(set(row["next_states"]["5"]), {"energy_mwh"})

    def test_electric_and_fuel_boilers_share_heat_sink_and_ac(self):
        snapshot = fuel_case(heat=3)
        snapshot["devices"][3]["params"]["capacity_mwth"] = 4
        snapshot["devices"].append(device(5, "electric_boiler"))
        snapshot["links"] += [cable(1, 5, boiler=True), heat_line(5, 3)]
        row = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(row["thermal"]["served_mwth"], 3, delta=EPS)
        self.assertGreater(row["thermal"]["boiler_heat_mwth"], 0)
        self.assertAlmostEqual(row["fuel"]["input_mw"], 2, delta=EPS)
        self.assertAlmostEqual(row["produced_mw"], row["boiler_electric_mw"]+row["fuel"]["auxiliary_electric_mw"], delta=EPS)

    def test_strict_supply_rejects_fuel_or_auxiliary_shortage(self):
        for snapshot in (fuel_case(cap=.1), fuel_case(generation=0)):
            snapshot["options"]["strict_supply"] = True
            result = backend.solve(snapshot, glpsol=GLPK)
            self.assertEqual(result["status"], "infeasible", result)
            self.assertFalse(result["success"])
            self.assertEqual(result["steps"], [])

    def test_integer_float_ids_preserved_and_pause_has_no_fuel(self):
        snapshot = fuel_case(dt=0)
        for node in snapshot["devices"]: node["id"] = float(node["id"])
        for line in snapshot["links"]: line["from"], line["to"] = float(line["from"]), float(line["to"])
        row = self.solve(snapshot)["steps"][0]
        self.assertEqual(row["fuel"]["input_mw"], 0)

    def test_schedule_audit_rejects_forged_fuel_auxiliary_cost_and_nan(self):
        snapshot = fuel_case()
        result = self.solve(snapshot)
        problem = backend.normalize(snapshot)
        for field in backend.FUEL_FIELDS:
            bad = copy.deepcopy(result["steps"])
            bad[0]["fuel"][field] += .1
            with self.subTest(aggregate=field):
                self.assertFalse(backend.validate_schedule(problem, bad)["valid"])
        for field in ("fuel_input_mw", "fuel_volume_nm3_per_h", "fuel_cost_per_h", "heat_output_mwth",
                      "conversion_loss_mw", "auxiliary_electric_mw", "auxiliary_electric_loss_mw"):
            for forged in (.123, float("nan"), float("inf")):
                bad = copy.deepcopy(result["steps"])
                bad[0]["devices"]["2"][field] = forged
                with self.subTest(device_field=field, forged=forged):
                    self.assertFalse(backend.validate_schedule(problem, bad)["valid"])
        disabled = copy.deepcopy(problem)
        disabled["fuel_supply"]["enabled"] = False
        self.assertFalse(backend.validate_schedule(disabled, result["steps"])["valid"])
        capped = copy.deepcopy(problem)
        capped["fuel_supply"]["max_input_mw"] = .1
        self.assertFalse(backend.validate_schedule(capped, result["steps"])["valid"])

    def test_raw_audit_rejects_faulty_lp_auxiliary_coefficients(self):
        problem = backend.normalize(fuel_case(generation=.01))
        broken = copy.deepcopy(problem)
        broken["paths"][0]["received"] *= 2
        model = backend.build_model(broken)
        with tempfile.TemporaryDirectory() as temp:
            run = backend.run_glpk(GLPK, model, 0, [], Path(temp), time.monotonic()+10)
        self.assertEqual(run["status"], "optimal")
        self.assertFalse(backend.validate_decisions(model, run["values"]))
        self.assertTrue(backend.validate_physical_decisions(broken, run["values"]), "A feasible but physically wrong LP must fail the independent audit")

    def test_legacy_objectives_preserved_and_fuel_cost_is_final_tiebreak(self):
        result = self.solve(fuel_case())
        self.assertEqual(len(result["objective"]["stages"]), 5)
        self.assertIn("fuel input cost", result["objective"]["stages"][-1])
        snapshot = fuel_case()
        snapshot["fuel_supply"]["price_per_mwh"] = 0
        self.assertEqual(self.solve(snapshot)["totals"]["fuel"]["cost"], 0)


class FuelInputTests(unittest.TestCase):
    def test_invalid_supply_or_parameters_fail_before_solver(self):
        edits = [lambda s: s.update(fuel_supply=[]),
                 lambda s: s["fuel_supply"].update(enabled=1),
                 lambda s: s["fuel_supply"].update(max_input_mw=-1),
                 lambda s: s["fuel_supply"].update(max_input_mw=float("inf")),
                 lambda s: s["fuel_supply"].update(lower_heating_value_kwh_per_nm3=0),
                 lambda s: s["fuel_supply"].update(lower_heating_value_kwh_per_nm3=1e-310),
                 lambda s: (s["fuel_supply"].update(lower_heating_value_kwh_per_nm3=1e-303), s["steps"][0].update(dt_h=8760)),
                 lambda s: s["fuel_supply"].update(price_per_mwh=float("nan")),
                 lambda s: s["fuel_supply"].update(emissions=1),
                 lambda s: s["devices"][2]["params"].update(auxiliary_electric_ratio=0),
                 lambda s: s["devices"][2]["params"].update(thermal_efficiency=1.1)]
        for edit in edits:
            snapshot = fuel_case()
            edit(snapshot)
            with self.subTest(edit=edit), mock.patch.object(backend.subprocess, "Popen") as launch:
                result = backend.solve(snapshot)
                self.assertFalse(result["success"])
                self.assertFalse(result["solver_invoked"])
                launch.assert_not_called()


if __name__ == "__main__": unittest.main()
