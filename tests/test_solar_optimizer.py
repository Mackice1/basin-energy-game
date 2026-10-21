"""V18 real-GLPK nonconcentrating solar thermal source and adversarial audit."""
import copy
import unittest
from unittest import mock
from test_thermal_dispatch_solver import backend, GLPK, EPS, device, cable, heat_line


def solar_case(irradiance=1000, generation=1, heat=1, dt=1):
    return {"schema_version": 3,
            "devices": [device(0, "wind"), device(1, "station", {"capacity_mw": 10, "loss_fraction": 0}),
                        device(2, "solar_thermal"), device(3, "heat_exchanger"), device(4, "heat_demand")],
            "links": [cable(0, 1), cable(1, 2, boiler=True), heat_line(2, 3, "solar_thermal"),
                      heat_line(3, 4, "heat_exchanger", "heat_demand")],
            "steps": [{"time_s": 0, "dt_h": dt, "available_mw": {"0": generation}, "demand_mw": {},
                       "heat_demand_mwth": {"4": heat}, "weather": {"irradiance_wm2": irradiance, "air_temp_c": 20}}],
            "options": {"timeout_s": 30}}


class SolarInputTests(unittest.TestCase):
    def test_poa_physics_and_nonnegative_loss_ledger(self):
        p = backend.DEFAULTS["solar_thermal"]
        for g in (0, 20, 1000):
            result = backend.solar_physics(p, {"irradiance_wm2": g, "air_temp_c": 20})
            expected = 30.3*max(0, .785*g-1.42*55-.005*55**2)/1e6
            self.assertAlmostEqual(result["available_mwth"], expected)
            self.assertAlmostEqual(result["incident_mw"], result["optical_rejection_mw"]+result["thermal_loss_mw"]+expected)

    def test_invalid_weather_cache_and_parameters_rejected(self):
        for field, value in (("irradiance_wm2", float("nan")), ("air_temp_c", -101), ("irradiance_wm2", -1)):
            s = solar_case(); s["steps"][0]["weather"][field] = value
            with self.assertRaises(backend.InputError): backend.normalize(s)
        for field, value in (("absorber_area_m2", 0), ("auxiliary_electric_ratio", 0), ("supply_temp_c", 80), ("absorber_area_m2", 3031), ("optical_efficiency", 0), ("heat_loss_w_m2k", 21), ("heat_loss_quadratic_w_m2k2", .21)):
            s = solar_case(); s["devices"][2]["params"][field] = value
            with self.assertRaises(backend.InputError): backend.normalize(s)
        for key, value in (("irradiance_kind", "dni"), ("irradiance_kind", "ghi"), ("is_day", 0)):
            s = solar_case(); s["steps"][0]["weather"][key] = value
            with self.assertRaises(backend.InputError): backend.normalize(s)
        s = solar_case(); del s["steps"][0]["weather"]
        with self.assertRaises(backend.InputError): backend.normalize(s)
        s = solar_case(); s["steps"][0]["solar_available_mwth"] = {"2": 100}
        with self.assertRaises(backend.InputError): backend.normalize(s)


@unittest.skipUnless(GLPK, "Solar integration requires real glpsol")
class SolarOptimizerTests(unittest.TestCase):
    def solve(self, s):
        original = copy.deepcopy(s)
        r = backend.solve(s, glpsol=GLPK)
        self.assertTrue(r["success"], r)
        self.assertTrue(r["solver_invoked"])
        self.assertTrue(r["validation"]["valid"])
        self.assertEqual(original, s)
        return r

    def test_sunny_weather_bound_auxiliary_and_accounting(self):
        r = self.solve(solar_case(dt=.25)); row = r["steps"][0]; solar = row["solar"]
        q = 30.3*(785-1.42*55-.005*55**2)/1e6
        self.assertAlmostEqual(solar["useful_mwth"], q, delta=EPS)
        self.assertAlmostEqual(solar["auxiliary_electric_mw"], .02*q, delta=EPS)
        self.assertAlmostEqual(row["thermal"]["served_mwth"], .98*q, delta=EPS)
        self.assertAlmostEqual(r["totals"]["solar"]["useful_mwhth"], q*.25, delta=EPS)
        self.assertEqual(row["devices"]["2"]["output_mw"], 0)
        self.assertAlmostEqual(solar["incident_mw"], sum(solar[x] for x in ("optical_rejection_mw", "thermal_loss_mw", "curtailed_mwth", "useful_mwth")), delta=EPS)

    def test_night_low_irradiance_paused_no_sink_no_power(self):
        for mode in ("night", "low", "paused", "zero_demand", "disconnected_heat", "disconnected_ac", "zero_ac", "full_storage"):
            s = solar_case(irradiance=0 if mode == "night" else 20 if mode == "low" else 1000,
                           generation=0 if mode == "zero_ac" else 1,
                           heat=0 if mode in ("zero_demand", "full_storage") else 1,
                           dt=0 if mode == "paused" else 1)
            if mode == "disconnected_heat": s["links"].pop(2)
            if mode == "disconnected_ac": s["links"].pop(1)
            if mode == "full_storage":
                s["devices"].append(device(5, "thermal_store", {"self_discharge_per_h": 0}, 4))
                s["links"].append(heat_line(2, 5, "solar_thermal", "thermal_store"))
            with self.subTest(mode=mode):
                row = self.solve(s)["steps"][0]
                self.assertAlmostEqual(row["solar"]["useful_mwth"], 0, delta=EPS)
                self.assertAlmostEqual(row["solar"]["auxiliary_electric_mw"], 0, delta=EPS)

    def test_edge_ac_station_exchanger_demand_limits(self):
        for mode in ("heat_edge", "ac_edge", "source", "station", "exchanger", "demand"):
            s = solar_case()
            if mode == "heat_edge": s["links"][2]["capacity_mwth"] = .005
            if mode == "ac_edge": s["links"][1]["capacity_mw"] = .0001
            if mode == "source": s["steps"][0]["available_mw"]["0"] = .0001
            if mode == "station": s["devices"][1]["params"]["capacity_mw"] = .0001
            if mode == "exchanger": s["devices"][3]["params"]["capacity_mwth"] = .005
            if mode == "demand": s["steps"][0]["heat_demand_mwth"]["4"] = .0049
            with self.subTest(mode=mode):
                row = self.solve(s)["steps"][0]
                self.assertAlmostEqual(row["solar"]["useful_mwth"], .005, delta=EPS)

    def test_storage_moves_sun_heat_to_night(self):
        s = solar_case(heat=0)
        s["devices"].append(device(5, "thermal_store", {"self_discharge_per_h": 0}, 0))
        s["links"] += [heat_line(2, 5, "solar_thermal", "thermal_store"), heat_line(5, 3, "thermal_store")]
        second = copy.deepcopy(s["steps"][0]); second.update(time_s=3600, weather={"irradiance_wm2": 0, "air_temp_c": 20}, heat_demand_mwth={"4": 1})
        s["steps"].append(second)
        r = self.solve(s)
        q = r["steps"][0]["solar"]["available_mwth"]
        self.assertAlmostEqual(r["steps"][0]["thermal"]["charge_mwth"], q, delta=EPS)
        self.assertAlmostEqual(r["steps"][1]["thermal"]["served_mwth"], q*.98**3, delta=EPS)
        self.assertAlmostEqual(r["steps"][1]["solar"]["useful_mwth"], 0, delta=EPS)

    def test_reports_and_cached_bounds_cannot_forge_source(self):
        s = solar_case(); r = self.solve(s); p = backend.normalize(s)
        for field in backend.SOLAR_FIELDS:
            for aggregate in (True, False):
                reports = copy.deepcopy(r["steps"])
                target = reports[0]["solar"] if aggregate else reports[0]["devices"]["2"]
                target[field] += .01
                self.assertFalse(backend.validate_schedule(p, reports)["valid"], field)
        # A compromised model cache can satisfy its own bound; independent audit must reject it.
        original = backend.build_model
        def corrupted(problem):
            problem["steps"][0]["solar_available_mwth"]["2"] = 1
            return original(problem)
        with mock.patch.object(backend, "build_model", corrupted):
            result = backend.solve(s, glpsol=GLPK)
        self.assertFalse(result["success"])
        self.assertTrue(any("solar weather availability" in x for x in result["errors"]), result)

    def test_battery_can_supply_aux_but_solar_cannot_generate_electricity(self):
        s = solar_case(generation=0)
        s["devices"].append(device(5, "battery", {}, 1))
        s["links"].append(cable(5, 1))
        row = self.solve(s)["steps"][0]
        self.assertGreater(row["solar"]["useful_mwth"], .01)
        self.assertAlmostEqual(row["discharge_mw"], row["solar"]["auxiliary_electric_mw"], delta=EPS)
        self.assertEqual(row["produced_mw"], 0)

    def test_storage_headroom_rate_and_terminal_target(self):
        for mode in ("headroom", "rate", "terminal"):
            s = solar_case(heat=0)
            params = {"self_discharge_per_h": 0, "capacity_mwhth": 1}
            if mode == "rate": params["charge_mwth"] = .005
            s["devices"].append(device(5, "thermal_store", params, .9951 if mode == "headroom" else 0))
            s["links"].append(heat_line(2, 5, "solar_thermal", "thermal_store"))
            # With no future demand the throughput objective does not waste solar charging;
            # an explicit inventory target creates a legitimate useful sink.
            s["options"]["terminal_heat_soc_fraction"] = 1 if mode == "headroom" else .0049
            row = self.solve(s)["steps"][0]
            self.assertAlmostEqual(row["thermal"]["charge_mwth"], .005, delta=EPS)
            self.assertGreater(row["solar"]["curtailed_mwth"], 0)

    def test_solar_and_fuel_joint_service_preserves_fuel_ledger(self):
        s = solar_case(heat=.5)
        s["devices"].append(device(5, "fuel_boiler"))
        s["links"] += [cable(1, 5, boiler=True), heat_line(5, 3, "fuel_boiler")]
        s["fuel_supply"] = dict(backend.FUEL_SUPPLY_DEFAULTS, enabled=True, max_input_mw=1)
        row = self.solve(s)["steps"][0]
        self.assertAlmostEqual(row["thermal"]["served_mwth"], .5, delta=EPS)
        self.assertGreater(row["solar"]["useful_mwth"], 0)
        self.assertGreater(row["fuel"]["heat_output_mwth"], 0)
        self.assertAlmostEqual(row["balance_error_mw"], 0, delta=EPS)
        self.assertAlmostEqual(row["fuel"]["balance_error_mw"], 0, delta=EPS)

    def test_strict_night_service_is_infeasible(self):
        s = solar_case(irradiance=0)
        s["options"]["strict_supply"] = True
        result = backend.solve(s, glpsol=GLPK)
        self.assertFalse(result["success"])
        self.assertEqual(result["status"], "infeasible")


    def test_explicit_night_overrides_positive_irradiance(self):
        s = solar_case(irradiance=1000)
        s["steps"][0]["weather"]["is_day"] = False
        row = self.solve(s)["steps"][0]
        self.assertEqual(row["solar"]["incident_mw"], 0)
        self.assertEqual(row["solar"]["useful_mwth"], 0)
        for kind in ("poa", "plane_of_array", "teaching_equivalent_poa"):
            s["steps"][0]["weather"].update(is_day=True, irradiance_kind=kind)
            self.assertGreater(self.solve(s)["steps"][0]["solar"]["useful_mwth"], 0)
