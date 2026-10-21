"""Schema-8 finite-water/hydrogen acceptance and independent-audit tests.

Only the standard library and the real GLPK executable are used. Run with:
    python3 -m unittest discover -s tests -p test_material_solver.py -v

The reusable material_case(), material_device(), electric_line(), material_line()
and material_step() helpers deliberately contain no solver-generated decisions.
Chemistry expectations are independently derived from the shared static profile.
"""
from __future__ import annotations

import copy
import importlib.util
import json
import math
import os
from pathlib import Path
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("material_backend_under_test", ROOT / "tools/dispatch_solver.py")
backend = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backend)
GLPK = str(ROOT.parents[1] / "v22_final_acceptance_20261020/tools/glpsol")
PROFILE = json.loads((ROOT / "data/material_process_profiles_v1.json").read_text())
MATERIAL_KINDS = tuple(PROFILE["defaults"])
PROFILE_ID = PROFILE["profile_id"]
H2_MOLAR_MASS = 2 * PROFILE["atomic_mass_kg_per_kmol"]["H"]
O_MOLAR_MASS = PROFILE["atomic_mass_kg_per_kmol"]["O"]
WATER_PER_H2 = (H2_MOLAR_MASS + O_MOLAR_MASS) / H2_MOLAR_MASS
OXYGEN_PER_H2 = O_MOLAR_MASS / H2_MOLAR_MASS
LHV_KWH_KG = -PROFILE["species"]["H2O"]["vapor_formation_enthalpy_kj_per_kmol"] / H2_MOLAR_MASS / 3600
HHV_KWH_KG = -PROFILE["species"]["H2O"]["formation_enthalpy_kj_per_kmol"] / H2_MOLAR_MASS / 3600
EPS = 3e-6
MATERIAL_FIELDS = (
    "water_withdrawn_kg_s", "hydrogen_produced_kg_s", "hydrogen_consumed_kg_s",
    "hydrogen_charged_kg_s", "hydrogen_discharged_kg_s", "hydrogen_leaked_kg",
    "oxygen_vented_kg_s", "oxygen_from_air_kg_s", "water_released_kg_s",
    "electrolyzer_electric_mw", "compression_electric_mw", "fuel_cell_output_mw",
    "heat_rejected_mwth", "hydrogen_inventory_kg", "water_inventory_kg",
    "hydrogen_lhv_mwh", "hydrogen_leak_lhv_mwh", "mass_balance_error_kg",
    "hydrogen_element_error_kg", "oxygen_element_error_kg", "enthalpy_balance_error_mw",
)
DETAIL_FIELDS = (
    "water_in_kg_s", "water_out_kg_s", "hydrogen_in_kg_s", "hydrogen_out_kg_s",
    "electric_input_mw", "electric_output_mw", "oxygen_vented_kg_s",
    "oxygen_from_air_kg_s", "water_released_kg_s", "heat_rejected_mwth",
    "inventory_before_kg", "inventory_after_leak_kg", "next_inventory_kg", "leaked_kg",
)
RATE_LEDGER = {
    "water_withdrawn_kg": "water_withdrawn_kg_s",
    "hydrogen_produced_kg": "hydrogen_produced_kg_s",
    "hydrogen_consumed_kg": "hydrogen_consumed_kg_s",
    "hydrogen_charged_kg": "hydrogen_charged_kg_s",
    "hydrogen_discharged_kg": "hydrogen_discharged_kg_s",
    "oxygen_vented_kg": "oxygen_vented_kg_s",
    "oxygen_from_air_kg": "oxygen_from_air_kg_s",
    "water_released_kg": "water_released_kg_s",
}
POWER_LEDGER = {
    "electrolyzer_electric_mwh": "electrolyzer_electric_mw",
    "compression_electric_mwh": "compression_electric_mw",
    "fuel_cell_output_mwh": "fuel_cell_output_mw",
    "heat_rejected_mwhth": "heat_rejected_mwth",
}
TOTAL_FIELDS = set(RATE_LEDGER) | set(POWER_LEDGER) | {
    "hydrogen_leaked_kg", "hydrogen_leak_lhv_mwh", "initial_hydrogen_kg",
    "final_hydrogen_kg", "initial_water_kg", "final_water_kg",
}


def material_device(ident, kind, params=None, inventory=None):
    """Create explicit material states, leaving ordinary electric devices intact."""
    result = {"id": ident, "kind": kind, "params": dict(params or {})}
    if kind in MATERIAL_KINDS:
        result.update(model_profile=PROFILE_ID, model_profile_version=1)
        if kind in ("water_supply_boundary", "hydrogen_gas_store"):
            species = "H2O" if kind == "water_supply_boundary" else "H2"
            initial = result["params"].get("initial_inventory_kg", PROFILE["defaults"][kind]["initial_inventory_kg"])
            result["state"] = {"material_inventory_kg": {species: initial if inventory is None else inventory}}
        else:
            result["state"] = {}
    return result


def electric_line(source, target, source_kind="station", target_kind="load", capacity=10., loss=0.):
    return {"from": source, "to": target,
            "from_port": "ac_out" if source_kind in ("fuel_cell_station", "steam_turbine") else "ac" if source_kind == "battery" else "out",
            "to_port": "ac_in" if target_kind in ("electrolyzer_station", "hydrogen_gas_store", "electric_boiler") else "ac" if target_kind == "battery" else "in",
            "carrier": "electricity_ac", "unit": "MW", "voltage_level": "AC_BUS",
            "capacity_mw": capacity, "loss_fraction": loss}


def material_line(source, target, source_kind, capacity=1.):
    routes = {
        "water_supply_boundary": ("water_out", "water_in", "material_water", "H2O", "liquid", "water_liquid_25c"),
        "electrolyzer_station": ("h2_out", "h2_in", "material_h2_gas", "H2", "gas", "h2_gas_supply"),
        "hydrogen_gas_store": ("h2_out", "h2_in", "material_h2_gas", "H2", "gas", "h2_gas_delivery"),
    }
    fp, tp, carrier, species, phase, grade = routes[source_kind]
    return {"from": source, "to": target, "from_port": fp, "to_port": tp,
            "carrier": carrier, "unit": "kg/s", "species_id": species,
            "phase_id": phase, "grade_id": grade, "mass_flow_capacity_kg_s": capacity,
            "loss_fraction": 0.}


def material_step(generation=.53, demand=0., time=0., dt=1.):
    return {"time_s": time, "dt_h": dt, "available_mw": {"0": generation},
            "demand_mw": {"2": demand}, "heat_demand_mwth": {}}


def material_case(*, water=1000., hydrogen=0., capacity=100., leak=0., generation=.53,
                  demand=1., source_kind="wind", dt=1.):
    """A lossless two-period chain: 0 source, 1 bus, 2 load, 3/4/5/6 water/EL/store/FC.

    At .53 MW for one hour, the 50+3 kWh/kg process can store 10 kg H2.
    Every state is kg, never inferred from the legacy integrated H2 energy store.
    """
    return {
        "schema_version": 8,
        "devices": [material_device(0, source_kind),
                    material_device(1, "station", {"capacity_mw": 10., "loss_fraction": 0.}),
                    material_device(2, "load"),
                    material_device(3, "water_supply_boundary", {"capacity_kg": max(1000., water), "initial_inventory_kg": 0.}, water),
                    material_device(4, "electrolyzer_station"),
                    material_device(5, "hydrogen_gas_store", {"capacity_kg": capacity, "initial_inventory_kg": 0., "leak_per_h": leak}, hydrogen),
                    material_device(6, "fuel_cell_station")],
        "links": [electric_line(0, 1, source_kind, "station"), electric_line(1, 2),
                  electric_line(1, 4, target_kind="electrolyzer_station"),
                  electric_line(1, 5, target_kind="hydrogen_gas_store"),
                  electric_line(6, 1, "fuel_cell_station", "station"),
                  material_line(3, 4, "water_supply_boundary"),
                  material_line(4, 5, "electrolyzer_station"),
                  material_line(5, 6, "hydrogen_gas_store")],
        "steps": [material_step(generation, 0., dt=dt), material_step(0., demand, time=dt*3600, dt=dt)],
        "options": {"timeout_s": 30.},
    }


def one_step(snapshot, *, generation=0., demand=0., dt=1.):
    snapshot["steps"] = [material_step(generation, demand, dt=dt)]
    return snapshot


class MaterialInputTests(unittest.TestCase):
    def reject(self, snapshot):
        with self.assertRaises(backend.InputError):
            backend.normalize(snapshot)

    def test_schema_eight_supports_all_four_catalog_kinds_and_exact_defaults(self):
        snapshot = material_case()
        for node in snapshot["devices"]:
            if node["kind"] in MATERIAL_KINDS:
                node["params"] = {}
                node.pop("state", None)
        problem = backend.normalize(snapshot)
        self.assertEqual(problem["schema"], 8)
        for ident in ("3", "4", "5", "6"):
            node = problem["nodes"][ident]
            self.assertEqual(node["params"], PROFILE["defaults"][node["kind"]])
        self.assertEqual(set(MATERIAL_KINDS), {"water_supply_boundary", "electrolyzer_station", "hydrogen_gas_store", "fuel_cell_station"})

    def test_material_devices_require_schema_eight(self):
        for schema in range(1, 8):
            for kind in MATERIAL_KINDS:
                snapshot = {"schema_version": schema, "devices": [material_device(0, kind)], "links": [],
                            "steps": [{"time_s": 0., "dt_h": 1., "available_mw": {}, "demand_mw": {}, "heat_demand_mwth": {}}]}
                with self.subTest(schema=schema, kind=kind):
                    self.reject(snapshot)

    def test_material_parameter_names_finiteness_and_nonnegativity(self):
        for ident in (3, 4, 5, 6):
            kind = material_case()["devices"][ident]["kind"]
            for field in PROFILE["defaults"][kind]:
                for value in (-1., float("nan"), float("inf"), True, "1", None):
                    snapshot = material_case()
                    snapshot["devices"][ident]["params"][field] = value
                    with self.subTest(kind=kind, field=field, value=value):
                        self.reject(snapshot)
            snapshot = material_case()
            snapshot["devices"][ident]["params"]["free_hydrogen_kg"] = 10.
            self.reject(snapshot)

    def test_profile_and_device_fields_are_strict(self):
        for ident in (3, 4, 5, 6):
            for field, value in (("model_profile", "material_hydrogen_2b_v1"), ("model_profile_version", 2),
                                 ("model_profile_version", True), ("unmetered_inventory_kg", 1.)):
                snapshot = material_case()
                snapshot["devices"][ident][field] = value
                with self.subTest(ident=ident, field=field, value=value):
                    self.reject(snapshot)

    def test_physical_parameter_bounds_and_no_free_electrolysis_heat(self):
        bad = ((3, "capacity_kg", 0.), (3, "capacity_kg", 1e9+1), (3, "max_outflow_kg_s", 1001.),
               (3, "initial_inventory_kg", 1001.), (4, "rated_electric_mw", 0.),
               (4, "max_hydrogen_kg_s", 1001.), (4, "electricity_kwh_per_kg", HHV_KWH_KG-.001),
               (4, "electricity_kwh_per_kg", 1001.), (5, "capacity_kg", 0.),
               (5, "compressor_electric_mw", 0.), (5, "compression_kwh_per_kg", 0.),
               (5, "compression_kwh_per_kg", 1001.), (5, "charge_kg_s", 1001.),
               (5, "discharge_kg_s", 1001.), (5, "leak_per_h", 1.001),
               (6, "rated_electric_mw", 0.), (6, "net_efficiency_lhv", 0.),
               (6, "net_efficiency_lhv", 1.001), (6, "max_hydrogen_kg_s", 1001.))
        for ident, field, value in bad:
            snapshot = material_case()
            snapshot["devices"][ident]["params"][field] = value
            with self.subTest(ident=ident, field=field):
                self.reject(snapshot)
        snapshot = material_case()
        snapshot["devices"][4]["params"]["electricity_kwh_per_kg"] = HHV_KWH_KG
        backend.normalize(snapshot)

    def test_material_states_have_exact_species_and_units(self):
        for ident, species, wrong, cap in ((3, "H2O", "H2", 1000.), (5, "H2", "H2O", 100.)):
            states = ({}, None, [], {"energy_mwh": 1.}, {"material_inventory_kg": {}},
                      {"material_inventory_kg": {wrong: 1.}}, {"material_inventory_kg": {species: 1., wrong: 1.}},
                      {"material_inventory_kg": {species: 1.}, "energy_mwh": 1.})
            states += tuple({"material_inventory_kg": {species: value}} for value in
                            (-1., cap+1., float("nan"), float("inf"), True, "1", None))
            for state in states:
                snapshot = material_case()
                snapshot["devices"][ident]["state"] = state
                with self.subTest(ident=ident, state=state):
                    self.reject(snapshot)
        for ident in (4, 6):
            for state in (None, [], {"material_inventory_kg": {"H2": 1.}}, {"energy_mwh": 1.}):
                snapshot = material_case()
                snapshot["devices"][ident]["state"] = state
                with self.subTest(converter=ident, state=state):
                    self.reject(snapshot)

    def test_every_material_pipe_field_is_required_and_dimensioned(self):
        for index in (5, 6, 7):
            for field in ("from_port", "to_port", "carrier", "unit", "species_id", "phase_id", "grade_id",
                          "mass_flow_capacity_kg_s", "loss_fraction"):
                snapshot = material_case()
                del snapshot["links"][index][field]
                with self.subTest(index=index, missing=field):
                    self.reject(snapshot)
            edits = (("from_port", "ac"), ("to_port", "ac"), ("carrier", "water_steam"),
                     ("unit", "MW"), ("species_id", "CO2"), ("phase_id", "solid"),
                     ("grade_id", "h2_gas_unverified"), ("mass_flow_capacity_kg_s", -1.),
                     ("mass_flow_capacity_kg_s", 1001.), ("mass_flow_capacity_kg_s", True),
                     ("mass_flow_capacity_kg_s", float("nan")), ("loss_fraction", .01),
                     ("capacity_mw", 1.), ("capacity_mwth", 1.), ("voltage_level", "AC_BUS"))
            for field, value in edits:
                snapshot = material_case()
                snapshot["links"][index][field] = value
                with self.subTest(index=index, field=field, value=value):
                    self.reject(snapshot)

    def test_illegal_material_routes_reverse_pipes_and_duplicates_are_rejected(self):
        for index in (5, 6, 7):
            snapshot = material_case()
            line = snapshot["links"][index]
            line["from"], line["to"] = line["to"], line["from"]
            with self.subTest(reverse=index):
                self.reject(snapshot)
            snapshot = material_case()
            snapshot["links"].append(copy.deepcopy(snapshot["links"][index]))
            with self.subTest(duplicate=index):
                self.reject(snapshot)
        for source, target, source_kind in ((4, 6, "electrolyzer_station"), (5, 5, "hydrogen_gas_store"),
                                             (3, 5, "water_supply_boundary"), (5, 4, "hydrogen_gas_store")):
            snapshot = material_case()
            snapshot["links"].append(material_line(source, target, source_kind))
            with self.subTest(source=source, target=target):
                self.reject(snapshot)

    def test_terminal_hydrogen_targets_are_kg_for_existing_gas_stores_only(self):
        invalid = (None, 1., [], {5: 1.}, {"3": 1.}, {"4": 1.}, {"6": 1.}, {"missing": 1.},
                   {"5": -1.}, {"5": 101.}, {"5": True}, {"5": float("nan")}, {"5": float("inf")})
        for target in invalid:
            snapshot = material_case()
            snapshot["options"]["terminal_hydrogen_kg"] = target
            with self.subTest(target=target):
                self.reject(snapshot)
        for target in ({}, {"5": 0.}, {"5": 100.}):
            snapshot = material_case()
            snapshot["options"]["terminal_hydrogen_kg"] = target
            backend.normalize(snapshot)

    def test_material_devices_cannot_claim_exogenous_electric_generation(self):
        for ident in ("3", "4", "5", "6"):
            snapshot = material_case()
            snapshot["steps"][0]["available_mw"][ident] = 1.
            with self.subTest(ident=ident):
                self.reject(snapshot)

    def test_negative_or_nonfinite_duration_is_rejected(self):
        for duration in (-1., float("nan"), float("inf"), True):
            snapshot = one_step(material_case(), dt=duration)
            with self.subTest(duration=duration):
                self.reject(snapshot)

    def test_only_wind_pv_can_feed_electrolysis_compression_and_fc_only_loads(self):
        snapshot = material_case()
        snapshot["devices"] += [material_device(7, "battery"), material_device(8, "pv"),
                                material_device(9, "electric_boiler")]
        snapshot["links"] += [electric_line(1, 7, target_kind="battery"),
                              electric_line(8, 1, "pv", "station"), electric_line(1, -1),
                              electric_line(1, 9, target_kind="electric_boiler")]
        for step in snapshot["steps"]:
            step["available_mw"]["8"] = 0.
        problem = backend.normalize(snapshot)
        for sink in ("4", "5"):
            self.assertEqual({p["source"] for p in problem["paths"] if p["sink"] == sink}, {"0", "8"})
        self.assertEqual({p["sink"] for p in problem["paths"] if p["source"] == "6"}, {"2"})


class MaterialGLPKTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not Path(GLPK).is_file() or not os.access(GLPK, os.X_OK):
            raise RuntimeError("Material acceptance requires the real executable at " + GLPK)

    def solve(self, snapshot):
        before = copy.deepcopy(snapshot)
        result = backend.solve(snapshot, glpsol=GLPK)
        self.assertTrue(result["success"], result)
        self.assertEqual(result["status"], "optimal", result)
        self.assertTrue(result["solver_invoked"], result)
        self.assertEqual(result["schema_version"], 8)
        self.assertEqual(snapshot, before, "Optimization must not mutate the live material snapshot")
        self.assertTrue(result["validation"]["valid"], result["validation"])
        self.assertTrue(result["validation"]["raw_decisions_validated"], result["validation"])
        audit = backend.validate_schedule(backend.normalize(snapshot), result["steps"])
        self.assertTrue(audit["valid"], audit)
        for report in result["steps"]:
            material = report["material"]
            self.assertEqual(set(material), set(MATERIAL_FIELDS))
            for field in ("mass_balance_error_kg", "hydrogen_element_error_kg", "oxygen_element_error_kg", "enthalpy_balance_error_mw"):
                self.assertAlmostEqual(material[field], 0., delta=EPS)
            self.assertAlmostEqual(report["balance_error_mw"], 0., delta=EPS)
            self.assertAlmostEqual(report["energy_balance_error_mwh"], 0., delta=EPS)
            self.assertAlmostEqual(material["water_withdrawn_kg_s"], material["hydrogen_produced_kg_s"]*WATER_PER_H2, delta=EPS)
            self.assertAlmostEqual(material["oxygen_vented_kg_s"], material["hydrogen_produced_kg_s"]*OXYGEN_PER_H2, delta=EPS)
            self.assertAlmostEqual(material["water_released_kg_s"], material["hydrogen_consumed_kg_s"]*WATER_PER_H2, delta=EPS)
            self.assertAlmostEqual(material["oxygen_from_air_kg_s"], material["hydrogen_consumed_kg_s"]*OXYGEN_PER_H2, delta=EPS)
            self.assertAlmostEqual(material["hydrogen_lhv_mwh"], material["hydrogen_inventory_kg"]*LHV_KWH_KG/1000, delta=EPS)
            for node in snapshot["devices"]:
                if node["kind"] not in MATERIAL_KINDS:
                    continue
                detail = report["devices"][str(node["id"])]
                self.assertEqual(detail["model_profile"], PROFILE_ID)
                self.assertEqual(detail["model_profile_version"], 1)
                self.assertGreaterEqual(detail["heat_rejected_mwth"], -EPS)
                if node["kind"] == "hydrogen_gas_store":
                    self.assertLessEqual(min(detail["hydrogen_in_kg_s"], detail["hydrogen_out_kg_s"]), EPS)
        total = result["totals"]["material"]
        self.assertEqual(len(TOTAL_FIELDS), 18)
        self.assertEqual(set(total), TOTAL_FIELDS, "The cross-language cumulative ledger has an exact 18-field contract")
        for field in TOTAL_FIELDS:
            self.assertIsInstance(total[field], (int, float), field)
            self.assertNotIsInstance(total[field], bool, field)
            self.assertTrue(math.isfinite(total[field]), field)
            self.assertGreaterEqual(total[field], -EPS, field)
        for field, rate in RATE_LEDGER.items():
            self.assertAlmostEqual(total[field], sum(row["material"][rate]*row["dt_s"] for row in result["steps"]), delta=EPS, msg=field)
        for field, power in POWER_LEDGER.items():
            self.assertAlmostEqual(total[field], sum(row["material"][power]*row["dt_h"] for row in result["steps"]), delta=EPS, msg=field)
        for field in ("hydrogen_leaked_kg", "hydrogen_leak_lhv_mwh"):
            self.assertAlmostEqual(total[field], sum(row["material"][field] for row in result["steps"]), delta=EPS, msg=field)
        for label, kind, species in (("water", "water_supply_boundary", "H2O"), ("hydrogen", "hydrogen_gas_store", "H2")):
            initial = sum(node.get("state", {}).get("material_inventory_kg", {}).get(species,
                          node["params"].get("initial_inventory_kg", PROFILE["defaults"][kind]["initial_inventory_kg"]))
                          for node in snapshot["devices"] if node["kind"] == kind)
            self.assertAlmostEqual(total["initial_"+label+"_kg"], initial, delta=EPS)
            self.assertAlmostEqual(total["final_"+label+"_kg"], result["steps"][-1]["material"][label+"_inventory_kg"], delta=EPS)
        self.assertAlmostEqual(total["water_withdrawn_kg"], total["hydrogen_produced_kg"]*WATER_PER_H2, delta=EPS)
        self.assertAlmostEqual(total["oxygen_vented_kg"], total["hydrogen_produced_kg"]*OXYGEN_PER_H2, delta=EPS)
        self.assertAlmostEqual(total["water_released_kg"], total["hydrogen_consumed_kg"]*WATER_PER_H2, delta=EPS)
        self.assertAlmostEqual(total["oxygen_from_air_kg"], total["hydrogen_consumed_kg"]*OXYGEN_PER_H2, delta=EPS)
        self.assertAlmostEqual(total["hydrogen_charged_kg"], total["hydrogen_produced_kg"], delta=EPS)
        self.assertAlmostEqual(total["hydrogen_discharged_kg"], total["hydrogen_consumed_kg"], delta=EPS)
        self.assertAlmostEqual(total["hydrogen_leak_lhv_mwh"], total["hydrogen_leaked_kg"]*LHV_KWH_KG/1000., delta=EPS)
        self.assertAlmostEqual(total["initial_hydrogen_kg"]+total["hydrogen_produced_kg"]-total["hydrogen_consumed_kg"]-total["hydrogen_leaked_kg"], total["final_hydrogen_kg"], delta=EPS)
        self.assertAlmostEqual(total["initial_water_kg"]-total["water_withdrawn_kg"], total["final_water_kg"], delta=EPS)
        self.assertAlmostEqual(total["electrolyzer_electric_mwh"]+total["compression_electric_mwh"]-total["fuel_cell_output_mwh"]-total["heat_rejected_mwhth"],
                               (total["hydrogen_produced_kg"]-total["hydrogen_consumed_kg"])*HHV_KWH_KG/1000., delta=EPS)
        return result

    def infeasible(self, snapshot):
        result = backend.solve(snapshot, glpsol=GLPK)
        self.assertFalse(result["success"], result)
        self.assertEqual(result["status"], "infeasible", result)
        self.assertEqual(result["steps"], [])
        self.assertTrue(result["solver_invoked"], result)
        return result

    def test_real_glpk_two_step_charge_then_discharge_with_complete_chemistry(self):
        result = self.solve(material_case())
        first, second = result["steps"]
        self.assertAlmostEqual(first["material"]["hydrogen_inventory_kg"], 10., delta=EPS)
        self.assertAlmostEqual(first["material"]["water_inventory_kg"], 1000.-10.*WATER_PER_H2, delta=EPS)
        self.assertAlmostEqual(first["material"]["electrolyzer_electric_mw"], .5, delta=EPS)
        self.assertAlmostEqual(first["material"]["compression_electric_mw"], .03, delta=EPS)
        self.assertAlmostEqual(second["served_mw"], 10.*LHV_KWH_KG*.5/1000., delta=EPS)
        self.assertAlmostEqual(second["material"]["hydrogen_inventory_kg"], 0., delta=EPS)
        self.assertAlmostEqual(second["material"]["water_inventory_kg"], first["material"]["water_inventory_kg"], delta=EPS,
                               msg="Fuel-cell effluent must not silently replenish the finite water source")
        self.assertEqual(set(result["initial_states"]), {"3", "5"})
        self.assertEqual(set(result["final_states"]), {"3", "5"})
        for states in (result["initial_states"], result["final_states"]):
            self.assertEqual(set(states["3"]), {"material_inventory_kg"})
            self.assertEqual(set(states["3"]["material_inventory_kg"]), {"H2O"})
            self.assertEqual(set(states["5"]["material_inventory_kg"]), {"H2"})
        self.assertAlmostEqual(first["material"]["heat_rejected_mwth"], .53-10.*HHV_KWH_KG/1000, delta=EPS)
        self.assertAlmostEqual(second["material"]["heat_rejected_mwth"], 10.*HHV_KWH_KG/1000-second["served_mw"], delta=EPS)
        self.assertAlmostEqual(first["energy_mwh"], 0., delta=EPS, msg="kg inventories are not electric-storage MWh")

    def test_pv_is_an_authorized_process_power_source(self):
        result = self.solve(material_case(source_kind="pv"))
        self.assertAlmostEqual(result["steps"][0]["material"]["hydrogen_inventory_kg"], 10., delta=EPS)

    def test_finite_water_and_outflow_are_not_reset_between_steps(self):
        snapshot = material_case(water=2.*WATER_PER_H2)
        snapshot["steps"] = [material_step(), material_step(time=3600.), material_step(0., 1., time=7200.)]
        result = self.solve(snapshot)
        produced = sum(row["material"]["hydrogen_produced_kg_s"]*row["dt_s"] for row in result["steps"])
        self.assertAlmostEqual(produced, 2., delta=EPS)
        self.assertAlmostEqual(result["final_states"]["3"]["material_inventory_kg"]["H2O"], 0., delta=EPS)
        snapshot = material_case()
        snapshot["devices"][3]["params"]["max_outflow_kg_s"] = WATER_PER_H2/3600.
        self.assertAlmostEqual(self.solve(snapshot)["steps"][0]["material"]["hydrogen_inventory_kg"], 1., delta=EPS)

    def test_fractional_duration_converts_rate_to_mass_using_seconds(self):
        for duration in (.25, .5, 2.):
            with self.subTest(duration=duration):
                result = self.solve(material_case(dt=duration))
                first, second = result["steps"]
                self.assertAlmostEqual(first["material"]["hydrogen_inventory_kg"], 10.*duration, delta=EPS)
                self.assertAlmostEqual(first["material"]["water_inventory_kg"], 1000.-10.*duration*WATER_PER_H2, delta=EPS)
                self.assertAlmostEqual(second["served_mw"], 10.*LHV_KWH_KG*.5/1000., delta=EPS)

    def test_multiple_electrolyzers_share_one_finite_water_source_and_port_cap(self):
        for limiting in ("inventory", "outflow"):
            snapshot = material_case(water=WATER_PER_H2 if limiting == "inventory" else 1000.)
            if limiting == "outflow":
                snapshot["devices"][3]["params"]["max_outflow_kg_s"] = WATER_PER_H2/3600.
            snapshot["devices"] += [material_device(7, "electrolyzer_station"),
                                    material_device(8, "hydrogen_gas_store", {"initial_inventory_kg": 0., "leak_per_h": 0.}, 0.),
                                    material_device(9, "fuel_cell_station")]
            snapshot["links"] += [electric_line(1, 7, target_kind="electrolyzer_station"),
                                  electric_line(1, 8, target_kind="hydrogen_gas_store"),
                                  electric_line(9, 1, "fuel_cell_station", "station"),
                                  material_line(3, 7, "water_supply_boundary"),
                                  material_line(7, 8, "electrolyzer_station"),
                                  material_line(8, 9, "hydrogen_gas_store")]
            with self.subTest(limiting=limiting):
                first = self.solve(snapshot)["steps"][0]
                self.assertAlmostEqual(first["material"]["hydrogen_inventory_kg"], 1., delta=EPS)
                self.assertAlmostEqual(first["devices"]["4"]["hydrogen_out_kg_s"] + first["devices"]["7"]["hydrogen_out_kg_s"], 1./3600., delta=EPS)
                self.assertAlmostEqual(first["devices"]["3"]["water_out_kg_s"], WATER_PER_H2/3600., delta=EPS)

    def test_missing_water_electricity_or_each_pipe_stops_charge(self):
        for missing in ("water", "generation", "source_cable", "electrolysis_cable", "compression_cable", "water_pipe", "hydrogen_pipe"):
            snapshot = material_case(water=0. if missing == "water" else 1000., generation=0. if missing == "generation" else .53)
            index = {"source_cable": 0, "electrolysis_cable": 2, "compression_cable": 3, "water_pipe": 5, "hydrogen_pipe": 6}.get(missing)
            if index is not None:
                snapshot["links"].pop(index)
            with self.subTest(missing=missing):
                result = self.solve(snapshot)
                for row in result["steps"]:
                    self.assertAlmostEqual(row["material"]["hydrogen_produced_kg_s"], 0., delta=EPS)
                    self.assertAlmostEqual(row["material"]["electrolyzer_electric_mw"], 0., delta=EPS)
                    self.assertAlmostEqual(row["material"]["compression_electric_mw"], 0., delta=EPS)
                self.assertAlmostEqual(result["final_states"]["3"]["material_inventory_kg"]["H2O"], snapshot["devices"][3]["state"]["material_inventory_kg"]["H2O"], delta=EPS)

    def test_electrolyzer_compressor_and_pipe_caps_jointly_limit_production(self):
        edits = (("device", 4, "rated_electric_mw", .05, 1.),
                 ("device", 4, "max_hydrogen_kg_s", 1./3600., 1.),
                 ("device", 5, "compressor_electric_mw", .003, 1.),
                 ("device", 5, "charge_kg_s", 1./3600., 1.),
                 ("line", 2, "capacity_mw", .05, 1.),
                 ("line", 3, "capacity_mw", .003, 1.),
                 ("line", 5, "mass_flow_capacity_kg_s", WATER_PER_H2/3600., 1.),
                 ("line", 6, "mass_flow_capacity_kg_s", 1./3600., 1.))
        for kind, ident, field, value, expected in edits:
            snapshot = material_case()
            target = snapshot["devices"][ident]["params"] if kind == "device" else snapshot["links"][ident]
            target[field] = value
            with self.subTest(kind=kind, ident=ident, field=field):
                self.assertAlmostEqual(self.solve(snapshot)["steps"][0]["material"]["hydrogen_inventory_kg"], expected, delta=EPS)

    def test_shared_source_cable_and_station_count_both_process_draws(self):
        for limited in ("source_cable", "station"):
            snapshot = material_case()
            target = snapshot["links"][0] if limited == "source_cable" else snapshot["devices"][1]["params"]
            target["capacity_mw"] = .265
            with self.subTest(limited=limited):
                row = self.solve(snapshot)["steps"][0]
                self.assertAlmostEqual(row["material"]["hydrogen_inventory_kg"], 5., delta=EPS)
                self.assertAlmostEqual(row["devices"]["1"]["input_mw"], .265, delta=EPS)

    def test_electric_delivery_losses_are_paid_before_material_production(self):
        snapshot = material_case()
        snapshot["links"][0]["loss_fraction"] = .1
        snapshot["devices"][1]["params"]["loss_fraction"] = .1
        snapshot["links"][2]["loss_fraction"] = .1
        snapshot["links"][3]["loss_fraction"] = .1
        row = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(row["material"]["hydrogen_inventory_kg"], 10.*.9**3, delta=EPS)

    def test_empty_store_full_store_and_capacity_headroom(self):
        empty = self.solve(one_step(material_case(), demand=1.))["steps"][0]
        self.assertAlmostEqual(empty["served_mw"], 0., delta=EPS)
        for initial, capacity, expected_charge in ((10., 10., 0.), (9., 10., 1.)):
            with self.subTest(initial=initial):
                row = self.solve(material_case(hydrogen=initial, capacity=capacity))["steps"][0]
                self.assertAlmostEqual(row["material"]["hydrogen_produced_kg_s"]*3600., expected_charge, delta=EPS)
                self.assertAlmostEqual(row["material"]["hydrogen_inventory_kg"], 10., delta=EPS)

    def test_no_load_disconnected_load_or_disconnected_fc_preserves_hydrogen(self):
        for missing in ("zero_load", "load_cable", "fc_cable", "gas_pipe"):
            snapshot = one_step(material_case(hydrogen=10.), demand=0. if missing == "zero_load" else 1.)
            index = {"load_cable": 1, "fc_cable": 4, "gas_pipe": 7}.get(missing)
            if index is not None:
                snapshot["links"].pop(index)
            with self.subTest(missing=missing):
                row = self.solve(snapshot)["steps"][0]
                self.assertAlmostEqual(row["material"]["hydrogen_inventory_kg"], 10., delta=EPS)
                self.assertAlmostEqual(row["material"]["hydrogen_consumed_kg_s"], 0., delta=EPS)

    def test_fuel_cell_power_rate_inventory_and_delivery_pipe_caps(self):
        factor = 3.6*LHV_KWH_KG*.5
        edits = ((6, "rated_electric_mw", .01, .01),
                 (6, "max_hydrogen_kg_s", 1./3600., LHV_KWH_KG*.5/1000.),
                 (5, "discharge_kg_s", 1./3600., LHV_KWH_KG*.5/1000.))
        for ident, field, value, expected in edits:
            snapshot = one_step(material_case(hydrogen=10.), demand=1.)
            snapshot["devices"][ident]["params"][field] = value
            with self.subTest(ident=ident, field=field):
                row = self.solve(snapshot)["steps"][0]
                self.assertAlmostEqual(row["served_mw"], expected, delta=EPS)
                self.assertAlmostEqual(row["material"]["hydrogen_consumed_kg_s"], expected/factor, delta=EPS)
        snapshot = one_step(material_case(hydrogen=10.), demand=1.)
        snapshot["links"][7]["mass_flow_capacity_kg_s"] = 1./3600.
        self.assertAlmostEqual(self.solve(snapshot)["steps"][0]["served_mw"], LHV_KWH_KG*.5/1000., delta=EPS)

    def test_negative_zero_is_explicitly_normalized_only_after_raw_audit(self):
        real_run = backend.run_glpk
        snapshot = one_step(material_case())
        def negative_zero(*args, **kwargs):
            run = real_run(*args, **kwargs)
            if run["status"] in ("optimal", "feasible"):
                run["values"]["material_0_5"] = -1e-15
            return run
        with mock.patch.object(backend, "run_glpk", side_effect=negative_zero):
            result = self.solve(snapshot)
        note = result["negative_zero_normalization"]
        self.assertTrue(note["raw_decisions_audited_first"])
        self.assertTrue(note["report_rebuilt_and_reaudited"])
        self.assertGreaterEqual(note["decision_count"], 1)
        self.assertEqual(result["steps"][0]["material"]["water_withdrawn_kg_s"], 0.)
        self.assertEqual(result["totals"]["material"]["water_withdrawn_kg"], 0.)

    def test_invalid_raw_incumbent_retries_same_unfixed_model_once(self):
        real_run = backend.run_glpk
        calls = []
        def first_invalid(executable, model, stage, locks, *args, **kwargs):
            calls.append((stage, copy.deepcopy(locks), tuple(model.binaries), kwargs.get("simplex_dual", False)))
            run = real_run(executable, model, stage, locks, *args, **kwargs)
            if len(calls) == 1:
                run["values"]["material_0_5"] = -1e-4
            return run
        with mock.patch.object(backend, "run_glpk", side_effect=first_invalid):
            result = self.solve(material_case())
        self.assertEqual(calls[0][:3], calls[1][:3])
        self.assertFalse(calls[0][3])
        self.assertTrue(calls[1][3])
        self.assertTrue(result["solver_stages"][0]["rejected_initial_run"]["errors"])
        self.assertEqual(result["solver_stages"][0]["same_model_dual_retry"]["errors"], [])
        self.assertTrue(result["warnings"])

    def test_substantive_negative_decisions_remain_rejected_after_one_retry(self):
        real_run = backend.run_glpk
        calls = []
        def always_invalid(*args, **kwargs):
            calls.append(kwargs.get("simplex_dual", False))
            run = real_run(*args, **kwargs)
            run["values"]["material_0_5"] = -1e-4
            return run
        with mock.patch.object(backend, "run_glpk", side_effect=always_invalid):
            result = backend.solve(material_case(), GLPK)
        self.assertEqual(calls, [False, True])
        self.assertFalse(result["success"])
        self.assertEqual(result["status"], "error")
        self.assertEqual(result["steps"], [])
        self.assertNotIn("negative_zero_normalization", result)

    def test_small_material_flows_use_runtime_mode_threshold_not_energy_tolerance(self):
        snapshot = one_step(material_case(), generation=.000053)
        snapshot["options"]["terminal_hydrogen_kg"] = {"5": .001}
        row = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(row["material"]["hydrogen_inventory_kg"], .001, delta=1e-9)
        self.assertEqual(row["devices"]["4"]["mode"], "produce")
        self.assertEqual(row["devices"]["5"]["mode"], "charge")
        self.assertTrue(row["lines"][6]["active"])
        self.assertEqual(row["lines"][6]["direction"], 1)

    def test_zero_duration_has_no_material_flow_leak_or_inventory_change(self):
        snapshot = one_step(material_case(hydrogen=10., leak=.1), generation=.53, demand=1., dt=0.)
        row = self.solve(snapshot)["steps"][0]
        for field in MATERIAL_FIELDS:
            if field not in ("hydrogen_inventory_kg", "water_inventory_kg", "hydrogen_lhv_mwh"):
                self.assertEqual(row["material"][field], 0., field)
        self.assertEqual(row["next_states"]["3"]["material_inventory_kg"]["H2O"], 1000.)
        self.assertEqual(row["next_states"]["5"]["material_inventory_kg"]["H2"], 10.)

    def test_leak_is_from_beginning_inventory_with_matching_lhv_loss(self):
        for duration in (.25, 1., 2.):
            snapshot = one_step(material_case(hydrogen=10., leak=.1), dt=duration)
            row = self.solve(snapshot)["steps"][0]
            remaining = 10.*math.exp(-.1*duration)
            with self.subTest(duration=duration):
                self.assertAlmostEqual(row["material"]["hydrogen_inventory_kg"], remaining, delta=EPS)
                self.assertAlmostEqual(row["material"]["hydrogen_leaked_kg"], 10.-remaining, delta=EPS)
                self.assertAlmostEqual(row["material"]["hydrogen_leak_lhv_mwh"], (10.-remaining)*LHV_KWH_KG/1000., delta=EPS)
        snapshot = one_step(material_case(hydrogen=10., leak=.1), demand=1.)
        self.assertAlmostEqual(self.solve(snapshot)["steps"][0]["served_mw"], 10.*math.exp(-.1)*LHV_KWH_KG*.5/1000., delta=EPS)

    def test_no_same_step_hydrogen_passthrough_between_separate_ac_buses(self):
        snapshot = one_step(material_case(), generation=.53, demand=1.)
        snapshot["devices"].append(material_device(7, "station", {"capacity_mw": 10., "loss_fraction": 0.}))
        snapshot["links"][1]["from"] = 7
        snapshot["links"][4]["to"] = 7
        snapshot["options"]["terminal_hydrogen_kg"] = {"5": 10.}
        row = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(row["material"]["hydrogen_inventory_kg"], 10., delta=EPS)
        self.assertAlmostEqual(row["served_mw"], 0., delta=EPS)
        self.assertAlmostEqual(row["material"]["hydrogen_consumed_kg_s"], 0., delta=EPS)
        snapshot["options"]["strict_supply"] = True
        self.infeasible(snapshot)

    def test_terminal_kg_floor_is_enforced_and_unreachable_floor_is_infeasible(self):
        snapshot = one_step(material_case(), generation=.53)
        snapshot["options"]["terminal_hydrogen_kg"] = {"5": 10.}
        self.assertGreaterEqual(self.solve(snapshot)["final_states"]["5"]["material_inventory_kg"]["H2"], 10.-EPS)
        for obstruction in ("power", "water", "compression", "target"):
            bad = copy.deepcopy(snapshot)
            if obstruction == "power": bad["steps"][0]["available_mw"]["0"] = 0.
            elif obstruction == "water": bad["devices"][3]["state"]["material_inventory_kg"]["H2O"] = 0.
            elif obstruction == "compression": bad["links"].pop(3)
            else: bad["options"]["terminal_hydrogen_kg"]["5"] = 11.
            with self.subTest(obstruction=obstruction):
                self.infeasible(bad)

    def test_terminal_inventory_is_per_store_not_an_aggregate_hydrogen_target(self):
        snapshot = one_step(material_case())
        snapshot["devices"].append(material_device(7, "hydrogen_gas_store", {"leak_per_h": 0.}, 10.))
        snapshot["options"]["terminal_hydrogen_kg"] = {"5": 1.}
        self.infeasible(snapshot)
        snapshot["options"]["terminal_hydrogen_kg"] = {"5": 0., "7": 10.}
        result = self.solve(snapshot)
        self.assertAlmostEqual(result["final_states"]["5"]["material_inventory_kg"]["H2"], 0., delta=EPS)
        self.assertAlmostEqual(result["final_states"]["7"]["material_inventory_kg"]["H2"], 10., delta=EPS)

    def test_battery_cannot_power_process_and_fc_cannot_export_or_charge_battery(self):
        snapshot = one_step(material_case(hydrogen=10.))
        battery = material_device(7, "battery")
        battery["state"] = {"energy_mwh": 1.}
        snapshot["devices"].append(battery)
        snapshot["links"] += [electric_line(1, 7, target_kind="battery"), electric_line(1, -1)]
        row = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(row["export_mw"], 0., delta=EPS)
        self.assertAlmostEqual(row["material"]["hydrogen_inventory_kg"], 10., delta=EPS)
        self.assertAlmostEqual(row["material"]["hydrogen_produced_kg_s"], 0., delta=EPS)
        snapshot["options"]["terminal_hydrogen_kg"] = {"5": 11.}
        self.infeasible(snapshot)
        snapshot["options"] = {"timeout_s": 30., "terminal_soc_fraction": .2}
        snapshot["devices"][-1]["state"]["energy_mwh"] = 0.
        self.infeasible(snapshot)

    def test_existing_integrated_hydrogen_inventory_is_not_duplicated_into_kg(self):
        snapshot = one_step(material_case(), demand=1.)
        node = material_device(7, "hydrogen_storage_system", {"capacity_mwh": 1., "initial_soc": 0., "self_discharge_per_h": 0.})
        node["state"] = {"energy_mwh": 1.}
        snapshot["devices"].append(node)
        # Intentionally unconnected: mere presence cannot create gas-store H2.
        row = self.solve(snapshot)["steps"][0]
        self.assertAlmostEqual(row["material"]["hydrogen_inventory_kg"], 0., delta=EPS)
        self.assertAlmostEqual(row["served_mw"], 0., delta=EPS)
        self.assertEqual(row["next_states"]["7"], {"energy_mwh": 1.})

    def assert_tamper_rejected(self, snapshot, result, edit):
        reports = copy.deepcopy(result["steps"])
        edit(reports)
        audit = backend.validate_schedule(backend.normalize(snapshot), reports)
        self.assertFalse(audit["valid"], audit)
        self.assertTrue(audit["errors"], audit)

    def test_audit_rejects_every_forged_material_aggregate_and_nonfinite_field(self):
        snapshot = material_case()
        result = self.solve(snapshot)
        for field in MATERIAL_FIELDS:
            for value in (123., float("nan"), float("inf"), True):
                with self.subTest(field=field, value=value):
                    self.assert_tamper_rejected(snapshot, result, lambda rows, f=field, v=value: rows[0]["material"].__setitem__(f, v))
            with self.subTest(missing=field):
                self.assert_tamper_rejected(snapshot, result, lambda rows, f=field: rows[0]["material"].pop(f))

    def test_audit_rejects_every_forged_device_material_metric_and_profile(self):
        snapshot = material_case()
        result = self.solve(snapshot)
        for ident in ("3", "4", "5", "6"):
            for field in DETAIL_FIELDS:
                with self.subTest(ident=ident, field=field):
                    self.assert_tamper_rejected(snapshot, result,
                        lambda rows, k=ident, f=field: rows[0]["devices"][k].__setitem__(f, rows[0]["devices"][k][f]+.1))
            for field, value in (("model_profile", "free_hydrogen"), ("model_profile_version", 2)):
                with self.subTest(ident=ident, field=field):
                    self.assert_tamper_rejected(snapshot, result,
                        lambda rows, k=ident, f=field, v=value: rows[0]["devices"][k].__setitem__(f, v))

    def test_audit_rejects_forged_material_next_states_and_state_continuity(self):
        snapshot = material_case()
        result = self.solve(snapshot)
        for ident, species in (("3", "H2O"), ("5", "H2")):
            for state in ({"material_inventory_kg": {species: 123.}}, {"energy_mwh": 1.},
                          {"material_inventory_kg": {species: True}}, {"material_inventory_kg": {species: float("nan")}},
                          {"material_inventory_kg": {species: 1., "CO2": 1.}}, {}):
                with self.subTest(ident=ident, state=state):
                    self.assert_tamper_rejected(snapshot, result, lambda rows, k=ident, v=state: rows[0]["next_states"].__setitem__(k, v))
            self.assert_tamper_rejected(snapshot, result, lambda rows, k=ident: rows[0]["next_states"].pop(k))
            self.assert_tamper_rejected(snapshot, result,
                lambda rows, k=ident: rows[1]["devices"][k].__setitem__("inventory_before_kg", 999.))
        self.assert_tamper_rejected(snapshot, result,
            lambda rows: rows[0]["next_states"].__setitem__("4", {"material_inventory_kg": {"H2": 1.}}))

    def test_audit_rejects_forged_pipe_identity_units_flow_and_capacity(self):
        snapshot = material_case()
        result = self.solve(snapshot)
        edits = (("from", 6), ("to", 3), ("from_port", "ac"), ("to_port", "ac"),
                 ("species_id", "CO2"), ("phase_id", "liquid"), ("grade_id", "fake"),
                 ("carrier", "water_steam"), ("unit", "MW"), ("mass_flow_capacity_kg_s", 500.),
                 ("sent_kg_s", .5), ("received_kg_s", .5), ("signed_kg_s", -.5),
                 ("loss_kg_s", .1), ("loss_fraction", .1), ("flow_from", 5), ("flow_to", 4))
        for field, value in edits:
            with self.subTest(field=field):
                self.assert_tamper_rejected(snapshot, result,
                    lambda rows, f=field, v=value: rows[0]["lines"][6].__setitem__(f, v))

    def test_audit_rejects_forged_ac_path_provenance_and_forbidden_fc_destinations(self):
        snapshot = material_case()
        snapshot["links"].append(electric_line(1, -1))
        result = self.solve(snapshot)
        for field, value in (("source_id", 6), ("sink_id", 5), ("station_id", 0), ("sent_mw", 42.)):
            def edit(rows, f=field, v=value):
                path = next(p for p in rows[0]["path_flows"] if p["source_id"] == 0 and p["sink_id"] == 4)
                path[f] = v
            with self.subTest(field=field):
                self.assert_tamper_rejected(snapshot, result, edit)
        for sink in (-1, 4, 5):
            with self.subTest(forbidden_fc_sink=sink):
                self.assert_tamper_rejected(snapshot, result,
                    lambda rows, k=sink: rows[1]["path_flows"].append({"source_id": 6, "station_id": 1, "sink_id": k, "sent_mw": .01}))


if __name__ == "__main__":
    unittest.main()
