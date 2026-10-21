"""Independent schema-11 whole-facility mass/enthalpy and real-GLPK tests.

No result is repaired before audit. Expected kWh/kg values here are independently
computed from the reviewed thermodynamic contract, not solver helper functions.
"""
from __future__ import annotations
import copy
import importlib.util
import json
import math
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("phase_backend_under_test", ROOT / "tools/dispatch_solver.py")
backend = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backend)
GLPK = os.environ.get("BASIN_GLPK", str(ROOT.parents[1]/"v22_final_acceptance_20261020/tools/glpsol"))
KINDS = ("hydrogen_liquid_store", "hydrogen_metal_hydride_store")
PROFILE = "material_hydrogen_2b_v2"
REFS = ("H2O_liquid_25c", "H2_gas_25c", "H2_liquid_20k", "H2_bound_lani5", "O2_gas_25c", "N2_gas_25c", "CO2_gas_25c", "NH3_gas_25c", "CH3OH_liquid_25c")
LAMBDA = -math.log(.999)/24
LHV = 241826/(2*1.008)/3600
HHV = 285830/(2*1.008)/3600
WATER = (2*1.008+15.999)/(2*1.008)
METAL_DISCHARGE = .15+(4.275+.2)/.95


def device(ident, kind, params=None, inventory=None):
    d = {"id": ident, "kind": kind, "params": params or {}}
    if kind in KINDS:
        d.update(model_profile=PROFILE, model_profile_version=2)
        if inventory is not None:
            d["state"] = {"material_inventory_kg": {"H2": inventory}}
            if kind == KINDS[1]: d["state"]["host_dry_mass_kg"] = d["params"].get("dry_host_mass_kg",10000.)
    return d


def ac(source, target, source_kind="station", target_kind="load", cap=10.):
    return {"from":source,"to":target,"from_port":"ac_out" if source_kind=="fuel_cell_station" else "ac" if source_kind in ("battery", "co2_liquid_cycle_store") else "out",
            "to_port":"ac_in" if target_kind in KINDS+("electrolyzer_station","hydrogen_gas_store") else "ac" if target_kind in ("battery", "co2_liquid_cycle_store") else "in",
            "carrier":"electricity_ac","unit":"MW","capacity_mw":cap,"loss_fraction":0.}


def pipe(source, target, water=False, supply=False, cap=1.):
    return {"from":source,"to":target,"from_port":"water_out" if water else "h2_out","to_port":"water_in" if water else "h2_in",
            "carrier":"material_water" if water else "material_h2_gas","unit":"kg/s","species_id":"H2O" if water else "H2",
            "phase_id":"liquid" if water else "gas","grade_id":"water_liquid_25c" if water else "h2_gas_supply" if supply else "h2_gas_delivery",
            "mass_flow_capacity_kg_s":cap,"loss_fraction":0.}


def phase_case(kind=KINDS[0], inventory=0., *, generation=1., demand=0., dt=1., params=None, target=None):
    # Separate auxiliary and FC buses make exact independent single-kg tests
    # possible: renewable electricity cannot bypass hydrogen to this load.
    s={"schema_version":11,"material_profile":PROFILE,"material_profile_version":2,"devices":[device(0,"wind"),device(1,"station",{"capacity_mw":10.,"loss_fraction":0.}),
       device(2,"load"),device(3,"water_supply_boundary"),device(4,"electrolyzer_station"),
       device(5,kind,params,inventory),device(6,"fuel_cell_station"),device(7,"station",{"capacity_mw":10.,"loss_fraction":0.})],
       "links":[ac(0,1,"wind","station"),ac(1,4,target_kind="electrolyzer_station"),ac(1,5,target_kind=kind),
                 ac(6,7,"fuel_cell_station","station"),ac(7,2),pipe(3,4,water=True),pipe(4,5,supply=True),pipe(5,6)],
       "steps":[{"time_s":0.,"dt_h":dt,"available_mw":{"0":generation},"demand_mw":{"2":demand},"heat_demand_mwth":{}}],
       "options":{"timeout_s":30.}}
    if target is not None:s["options"]["terminal_hydrogen_kg"]={"5":target}
    return s


def add_battery(snapshot, energy=.05, cap=.1):
    snapshot["devices"].append({"id":8,"kind":"battery","params":{"capacity_mwh":cap,"charge_efficiency":1.,"discharge_efficiency":1.,"initial_soc":0.},"state":{"energy_mwh":energy}})
    snapshot["links"].append(ac(8,1,"battery","station"))
    return snapshot


def cycle_case(kind=KINDS[0]):
    s=add_battery(phase_case(kind,generation=1.,demand=0.))
    s["steps"].append(dict(s["steps"][0],time_s=3600.,available_mw={"0":0.},demand_mw={"2":LHV*.5/1000}))
    return s


def mixed_case():
    s=cycle_case(KINDS[0])
    s["devices"][1]=device(1,"collector_substation",{"capacity_mw":10.,"loss_fraction":.01})
    s["devices"][-1]={"id":8,"kind":"co2_liquid_cycle_store","params":{"initial_soc":0.},"state":{"energy_mwh":.05}}
    s["devices"].append({"id":9,"kind":"hydrogen_gas_store","params":{"leak_per_h":.0001},"state":{"material_inventory_kg":{"H2":3.}}})
    s["devices"].append(device(10,KINDS[1],inventory=2.))
    return s


def write_fixtures(directory):
    """Persist independently audited, actual GLPK results for Godot re-audit."""
    cases={"lh2_charge_1kg":phase_case(KINDS[0],target=1.),
           "metal_charge_1kg":phase_case(KINDS[1],target=1.),
           "lh2_discharge_1kg":phase_case(KINDS[0],math.exp(LAMBDA),generation=.01,demand=LHV*.5/1000),
           "metal_discharge_1kg":phase_case(KINDS[1],1.,generation=.01,demand=LHV*.5/1000),
           "lh2_cycle_battery":cycle_case(KINDS[0]),"metal_cycle_battery":cycle_case(KINDS[1]),
           "lh2_passive_24h":phase_case(KINDS[0],100.,generation=0.,dt=24.),
           "metal_heater_limited":phase_case(KINDS[1],100.,generation=1.,demand=1.,params={"discharge_heater_electric_mw":.001}),
           "lh2_environment_limited":phase_case(KINDS[0],100.,generation=1.,demand=1.,params={"ambient_vaporizer_mwth":.001}),
           "lh2_no_auxiliary":phase_case(KINDS[0],100.,generation=0.,demand=1.),
           "mixed_phase_gas_co2_collector":mixed_case(),
           "paused_phase":phase_case(KINDS[0],100.,generation=1.,demand=1.,dt=0.)}
    output=Path(directory);output.mkdir(parents=True,exist_ok=True)
    fixtures=[];summary=[]
    for name,snapshot in cases.items():
        result=backend.solve(snapshot,GLPK)
        if not result["success"] or not result["solver_invoked"]:raise AssertionError((name,result.get("errors")))
        audit=backend.validate_schedule(backend.normalize(snapshot),result["steps"])
        if not audit["valid"]:raise AssertionError((name,audit))
        fixture={"name":name,"request":snapshot,"result":result}
        fixtures.append(fixture)
        (output/(name+".json")).write_text(json.dumps(fixture,indent=2,allow_nan=False)+"\n")
        summary.append({"name":name,"status":result["status"],"raw_decisions_validated":result["validation"]["raw_decisions_validated"],
                        "max_residual":audit["max_residual"],"material_total_fields":len(result["totals"]["material"])})
    (output/"solver_fixtures.json").write_text(json.dumps(fixtures,indent=2,allow_nan=False)+"\n")
    (output/"fixture_summary.json").write_text(json.dumps(summary,indent=2,allow_nan=False)+"\n")
    return summary


class PhaseInputTests(unittest.TestCase):
    def reject(self,s):
        with self.assertRaises(backend.InputError):backend.normalize(s)

    def test_frozen_old_catalog_cardinalities(self):
        self.assertEqual(len(backend.DEFAULTS),32)
        self.assertEqual(len(backend.SCHEMA_10_DEFAULTS),33)
        self.assertEqual(len(backend.SCHEMA_11_DEFAULTS),35)
        self.assertTrue(all(k not in backend.DEFAULTS for k in KINDS))
        self.assertTrue(all(k not in backend.SCHEMA_10_DEFAULTS for k in KINDS))

    def test_schema11_requires_new_kind_and_new_kinds_require11(self):
        for kind in KINDS:
            for schema in range(1,11):
                s=phase_case(kind);s["schema_version"]=schema
                with self.subTest(kind=kind,schema=schema):self.reject(s)
        s=phase_case();s["devices"][5]=device(5,"hydrogen_gas_store")
        self.reject(s)

    def test_schema11_requires_explicit_top_profile_identity(self):
        for key,value in (("material_profile",None),("material_profile","material_hydrogen_2a_v1"),
                          ("material_profile_version",None),("material_profile_version",1),("material_profile_version",True)):
            s=phase_case()
            if value is None:s.pop(key)
            else:s[key]=value
            self.reject(s)

    def test_defaults_and_profile_are_separate(self):
        data=json.loads((ROOT/"data/material_process_profiles_v2.json").read_text())
        for kind in KINDS:
            s=phase_case(kind);s["devices"][5].pop("state")
            p=backend.normalize(s)
            self.assertEqual(p["nodes"]["5"]["params"],data["defaults"][kind])
            self.assertEqual(p["nodes"]["5"]["inventory_kg"],0)
            for field,val in (("model_profile","material_hydrogen_2a_v1"),("model_profile_version",1),("model_profile_version",True)):
                q=copy.deepcopy(s);q["devices"][5][field]=val;self.reject(q)

    def test_capacity_and_every_rating_are_bounded(self):
        data=json.loads((ROOT/"data/material_process_profiles_v2.json").read_text())
        for kind in KINDS:
            for key,maximum in data["maximums"][kind].items():
                with self.subTest(kind=kind,key=key):
                    s=phase_case(kind);s["devices"][5]["params"][key]=maximum+1e-4;self.reject(s)
                    s=phase_case(kind);s["devices"][5]["params"][key]=-1e-4;self.reject(s)
        s=phase_case(KINDS[1],1.,params={"dry_host_mass_kg":10.});self.reject(s)
        s=phase_case(KINDS[1],params={"capacity_kg":100.});self.reject(s)

    def test_host_is_exact_immutable_and_inventory_is_explicit(self):
        for change in (lambda d:d["state"].update(host_dry_mass_kg=9999.),
                       lambda d:d["state"].pop("host_dry_mass_kg"),
                       lambda d:d["state"].update(energy_mwh=1.),
                       lambda d:d["state"]["material_inventory_kg"].update(O2=1.)):
            s=phase_case(KINDS[1]);change(s["devices"][5]);self.reject(s)
        s=phase_case();s["devices"][5]["state"]["host_dry_mass_kg"]=10000;self.reject(s)

    def test_no_storage_to_storage_or_non_gas_interface(self):
        for source_kind in KINDS+("hydrogen_gas_store",):
            for sink_kind in KINDS:
                s=phase_case(sink_kind);s["devices"].append(device(9,source_kind))
                s["links"].append(pipe(9,5));self.reject(s)
        for field,value in (("phase_id","liquid"),("grade_id","H2_liquid_20k"),("unit","kg"),("carrier","heat_water")):
            s=phase_case();s["links"][-1][field]=value;self.reject(s)

    def test_no_coefficient_overrides(self):
        for kind in KINDS:
            for key in ("liquefaction_kwh_per_kg","heater_efficiency","leak_per_h","phase_enthalpy_kwh_per_kg"):
                s=phase_case(kind);s["devices"][5]["params"][key]=0.;self.reject(s)


class PhaseGLPKTests(unittest.TestCase):
    def solve(self,s):
        with tempfile.TemporaryDirectory(prefix="phase_h2_solver_") as home:
            old={k:os.environ.get(k) for k in ("HOME","XDG_DATA_HOME","XDG_CONFIG_HOME")}
            try:
                os.environ.update(HOME=home,XDG_DATA_HOME=home+"/data",XDG_CONFIG_HOME=home+"/config")
                result=backend.solve(s,GLPK)
            finally:
                for key,value in old.items():
                    if value is None:os.environ.pop(key,None)
                    else:os.environ[key]=value
        self.assertTrue(result["solver_invoked"],result)
        self.assertTrue(result["success"],result.get("errors"))
        self.assertTrue(result["validation"]["valid"],result)
        self.assertTrue(backend.validate_schedule(backend.normalize(s),result["steps"])["valid"])
        return result

    def test_one_kg_charge_exact_ac_rejection_and_signed_phase(self):
        for kind,ac_kwh,heat,delta in ((KINDS[0],12.,13.24,1.24),(KINDS[1],.15,4.425,4.275)):
            with self.subTest(kind=kind):
                s=phase_case(kind,target=1.);r=self.solve(s);d=r["steps"][0]["devices"]["5"]
                self.assertAlmostEqual(d["next_inventory_kg"],1.,places=7)
                self.assertAlmostEqual(d["hydrogen_in_kg_s"]*3600,1.,places=7)
                self.assertAlmostEqual(d["electric_input_mw"]*1000,ac_kwh,places=7)
                self.assertAlmostEqual(d["heat_rejected_mwth"]*1000,heat,places=7)
                self.assertAlmostEqual(d["phase_enthalpy_change_mwh"]*1000,-delta,places=7)
                self.assertEqual(d["environment_heat_in_mwth"],0.)
                self.assertEqual(d["model_profile"],PROFILE)
                self.assertEqual(r["steps"][0]["devices"]["4"]["model_profile_version"],1)

    def test_one_kg_discharge_exact_actual_ac_and_environment(self):
        for kind,ac_kwh,heat,delta,env in ((KINDS[0],.02,.02,1.24,1.24),(KINDS[1],METAL_DISCHARGE,METAL_DISCHARGE-4.275,4.275,0.)):
            inventory=math.exp(LAMBDA) if kind==KINDS[0] else 1.
            s=phase_case(kind,inventory,generation=.01,demand=LHV*.5/1000)
            r=self.solve(s);d=r["steps"][0]["devices"]["5"]
            self.assertAlmostEqual(d["hydrogen_out_kg_s"]*3600,1.,places=6)
            self.assertAlmostEqual(d["electric_input_mw"]*1000,ac_kwh,places=7)
            self.assertAlmostEqual(d["heat_rejected_mwth"]*1000,heat,places=7)
            self.assertAlmostEqual(d["phase_enthalpy_change_mwh"]*1000,delta*inventory,places=7)
            self.assertAlmostEqual(d["environment_heat_in_mwth"]*1000,env+(inventory-1.)*delta,places=7)
            self.assertAlmostEqual(d["next_inventory_kg"],0.,places=6)

    def test_dark_loaded_store_requires_aux_not_self_bootstrap(self):
        for kind in KINDS:
            r=self.solve(phase_case(kind,100.,generation=0.,demand=.1))
            self.assertAlmostEqual(r["steps"][0]["material"]["fuel_cell_output_mw"],0.,places=10)
            self.assertEqual(r["steps"][0]["devices"]["5"]["hydrogen_out_kg_s"],0.)

    def test_same_bus_fuel_cell_cannot_bootstrap_aux_or_export(self):
        for kind in KINDS:
            s=phase_case(kind,100.,generation=0.,demand=1.)
            for line in s["links"]:
                if line["from"]==6:line["to"]=1
                if line["from"]==7:line["from"]=1
            s["links"].append(ac(1,-1))
            p=backend.normalize(s)
            self.assertTrue(all(path["sink"]=="2" for path in p["paths"] if path["source"]=="6"))
            r=self.solve(s)
            self.assertAlmostEqual(r["steps"][0]["material"]["fuel_cell_output_mw"],0.,places=10)
            self.assertAlmostEqual(r["steps"][0]["export_mw"],0.,places=10)

    def test_turbine_is_never_an_eligible_phase_auxiliary_source(self):
        s=phase_case(KINDS[0],100.,generation=0.,demand=1.)
        s["devices"].append(device(9,"steam_turbine"))
        edge=ac(9,1,"fuel_cell_station","station")
        s["links"].append(edge);s["steps"][0]["weather"]={"air_temp_c":25.}
        p=backend.normalize(s)
        self.assertFalse(any(path["source"]=="9" and path["sink"]=="5" for path in p["paths"]))

    def test_finite_battery_can_supply_discharge_aux(self):
        for kind in KINDS:
            s=add_battery(phase_case(kind,10.,generation=0.,demand=LHV*.5/1000))
            r=self.solve(s);d=r["steps"][0]["devices"]["5"]
            self.assertAlmostEqual(d["hydrogen_out_kg_s"]*3600,1.,places=6)
            self.assertAlmostEqual(.05-r["final_states"]["8"]["energy_mwh"],d["electric_input_mw"],places=8)

    def test_finite_battery_cannot_supply_charging_or_electrolysis(self):
        for kind in KINDS:
            s=add_battery(phase_case(kind,generation=0.,target=1.))
            r=backend.solve(s,GLPK)
            self.assertTrue(r["solver_invoked"]);self.assertFalse(r["success"])
            self.assertEqual(r["status"],"infeasible")
        # Wind can run the electrolyzer, but removing the phase store's renewable
        # path still cannot make its charge auxiliary use battery energy.
        s=add_battery(phase_case(KINDS[0],generation=.05,target=1.))
        r=backend.solve(s,GLPK);self.assertFalse(r["success"])

    def test_disconnected_ac_forbids_partial_active_transaction(self):
        for kind in KINDS:
            for inventory,target in ((0.,1.),(1.,None)):
                s=phase_case(kind,inventory,generation=1.,demand=.1,target=target)
                s["links"]=[x for x in s["links"] if not(x["from"]==1 and x["to"]==5)]
                if target is not None:self.assertFalse(backend.solve(s,GLPK)["success"])
                else:
                    r=self.solve(s);self.assertEqual(r["steps"][0]["devices"]["5"]["hydrogen_out_kg_s"],0.)

    def test_liquid_passive_boiloff_without_cable_and_pause(self):
        s=phase_case(KINDS[0],100.,generation=0.,dt=24.)
        s["links"]=[];r=self.solve(s);d=r["steps"][0]["devices"]["5"]
        self.assertAlmostEqual(d["leaked_kg"],.1,places=10)
        self.assertAlmostEqual(d["next_inventory_kg"],99.9,places=10)
        self.assertAlmostEqual(d["environment_heat_in_mwth"]*24*1000,.124,places=10)
        self.assertEqual(d["electric_input_mw"],0.)
        s["steps"][0]["dt_h"]=0.;r=self.solve(s)
        self.assertEqual(r["final_states"]["5"]["material_inventory_kg"]["H2"],100.)
        self.assertEqual(r["steps"][0]["material"]["environment_heat_in_mwth"],0.)

    def test_metal_no_ambient_or_passive_leak_host_retained(self):
        s=phase_case(KINDS[1],100.,generation=0.,dt=8760.)
        r=self.solve(s);d=r["steps"][0]["devices"]["5"]
        self.assertEqual(d["leaked_kg"],0.)
        self.assertEqual(d["environment_heat_in_mwth"],0.)
        self.assertEqual(r["initial_states"]["5"]["host_dry_mass_kg"],10000.)
        self.assertEqual(r["final_states"]["5"]["host_dry_mass_kg"],10000.)

    def test_finite_charge_cooler_and_liquefier_limits(self):
        for kind,parameter,rating,coefficient in ((KINDS[0],"heat_rejection_mwth",.001,13.24),(KINDS[0],"liquefier_electric_mw",.001,12.),(KINDS[1],"heat_rejection_mwth",.001,4.425),(KINDS[1],"charge_aux_electric_mw",.00001,.15)):
            s=phase_case(kind,params={parameter:rating},target=1.)
            r=backend.solve(s,GLPK);self.assertFalse(r["success"],(kind,parameter))
            s["options"]["terminal_hydrogen_kg"]["5"]=rating*1000/coefficient*.9
            self.solve(s)

    def test_finite_discharge_heater_aux_environment_cooler(self):
        for kind,parameter,rating,coefficient in ((KINDS[0],"ambient_vaporizer_mwth",.000124,1.24),(KINDS[0],"discharge_aux_electric_mw",.000002,.02),(KINDS[0],"heat_rejection_mwth",.000002,.02),(KINDS[1],"discharge_heater_electric_mw",.0001,METAL_DISCHARGE),(KINDS[1],"heat_rejection_mwth",.0001,METAL_DISCHARGE-4.275)):
            s=phase_case(kind,100.,generation=1.,demand=1.,params={parameter:rating})
            r=self.solve(s);d=r["steps"][0]["devices"]["5"]
            self.assertAlmostEqual(d["hydrogen_out_kg_s"]*3600,rating*1000/coefficient,places=6)

    def test_full_empty_and_host_derived_capacity(self):
        for kind,capacity in ((KINDS[0],1000.),(KINDS[1],120.)):
            s=phase_case(kind,capacity,target=capacity);r=self.solve(s)
            self.assertLessEqual(r["final_states"]["5"]["material_inventory_kg"]["H2"],capacity+1e-7)
            s=phase_case(kind,0.,generation=0.,demand=1.);r=self.solve(s)
            self.assertAlmostEqual(r["steps"][0]["material"]["fuel_cell_output_mw"],0.,places=10)
        s=phase_case(KINDS[1],params={"dry_host_mass_kg":100.},target=1.2);r=self.solve(s)
        self.assertAlmostEqual(r["final_states"]["5"]["material_inventory_kg"]["H2"],1.2,places=7)

    def test_shared_station_cap_includes_all_auxiliary_flows(self):
        for kind,phase_ac in ((KINDS[0],12.),(KINDS[1],.15)):
            s=phase_case(kind,target=1.);s["devices"][1]["params"]["capacity_mw"]=(50.+phase_ac)/1000*.999
            self.assertFalse(backend.solve(s,GLPK)["success"])
            s["devices"][1]["params"]["capacity_mw"]=(50.+phase_ac)/1000
            r=self.solve(s);self.assertAlmostEqual(r["steps"][0]["devices"]["1"]["input_mw"],(50.+phase_ac)/1000,places=8)

    def test_reference_map_and_legacy_chemical_lhv_are_not_double_counted(self):
        for kind,ref,delta in ((KINDS[0],"H2_liquid_20k",1.24),(KINDS[1],"H2_bound_lani5",4.275)):
            s=phase_case(kind,target=1.);r=self.solve(s);m=r["steps"][0]["material"]
            self.assertEqual(set(m["inventory_by_reference_kg"]),set(REFS))
            self.assertAlmostEqual(m["inventory_by_reference_kg"][ref],1.,places=7)
            self.assertAlmostEqual(m["hydrogen_lhv_mwh"],LHV/1000,places=9)
            self.assertAlmostEqual(m["phase_enthalpy_mwh"],-delta/1000,places=9)
            self.assertAlmostEqual(m["enthalpy_balance_error_mw"],0.,places=8)

    def test_tampering_enthalpy_heat_stock_map_profile_host_and_aux_rejected(self):
        for kind in KINDS:
            s=phase_case(kind,target=1.);r=self.solve(s);problem=backend.normalize(s)
            changes=[lambda step:step["devices"]["5"].update(phase_enthalpy_mwh=1.),
                     lambda step:step["devices"]["5"].update(heat_rejected_mwth=0.),
                     lambda step:step["devices"]["5"].update(electric_input_mw=0.),
                     lambda step:step["devices"]["5"].update(environment_heat_in_mwth=1.),
                     lambda step:step["devices"]["5"].update(model_profile_version=1),
                     lambda step:step["material"]["inventory_by_reference_kg"].update(CO2_gas_25c=1.),
                     lambda step:step["material"]["dry_host_by_device_kg"].update(fake=1.),
                     lambda step:step["next_states"]["5"]["material_inventory_kg"].update(H2=2.)]
            if kind==KINDS[1]:changes.append(lambda step:step["next_states"]["5"].update(host_dry_mass_kg=9999.))
            for change in changes:
                forged=copy.deepcopy(r["steps"]);change(forged[0])
                self.assertFalse(backend.validate_schedule(problem,forged)["valid"])

    def test_legacy_billion_kg_one_kg_and_cumulative_forgery_rejected(self):
        s={"schema_version":8,"devices":[{"id":0,"kind":"hydrogen_gas_store","params":{"capacity_kg":1e9,"initial_inventory_kg":1e9,"leak_per_h":0.}}],"links":[],
           "steps":[{"time_s":i*3600.,"dt_h":1.,"available_mw":{},"demand_mw":{},"heat_demand_mwth":{}} for i in range(1000)],"options":{"timeout_s":30.}}
        r=self.solve(s);p=backend.normalize(s)
        for cumulative in (False,True):
            forged=copy.deepcopy(r["steps"])
            for i,step in enumerate(forged):
                delta=(i+1)/1000 if cumulative else 1.
                step["next_states"]["0"]["material_inventory_kg"]["H2"]-=delta
                step["devices"]["0"]["next_inventory_kg"]-=delta
                step["material"]["hydrogen_inventory_kg"]-=delta
            self.assertFalse(backend.validate_schedule(p,forged)["valid"])

    def test_cumulative_balanced_stock_transfer_below_local_tolerance_rejected(self):
        # Both stores keep aggregate mass/elements/LHV unchanged. Each invented
        # 0.001 kg transfer is within rel2e-12 at 5e8 kg, but 1000 transfers must
        # not create a permitted 1 kg relocation without any physical pipe.
        s={"schema_version":8,"devices":[{"id":i,"kind":"hydrogen_gas_store","params":{"capacity_kg":1e9,"initial_inventory_kg":5e8,"leak_per_h":0.}} for i in range(2)],
           "links":[],"steps":[{"time_s":i*3600.,"dt_h":1.,"available_mw":{},"demand_mw":{},"heat_demand_mwth":{}} for i in range(1000)],"options":{"timeout_s":30.}}
        r=self.solve(s);forged=copy.deepcopy(r["steps"])
        for i,step in enumerate(forged):
            for ident,sign in (("0",1.),("1",-1.)):
                d=step["devices"][ident]
                d["inventory_before_kg"]=5e8+sign*i*.001
                d["inventory_after_leak_kg"]=d["inventory_before_kg"]
                d["next_inventory_kg"]=5e8+sign*(i+1)*.001
                step["next_states"][ident]["material_inventory_kg"]["H2"]=d["next_inventory_kg"]
        audit=backend.validate_schedule(backend.normalize(s),forged)
        self.assertFalse(audit["valid"])
        self.assertTrue(any("finite mass recurrence" in item or "inventory_before_kg" in item for item in audit["errors"]))

    def test_both_phase_stores_coexist_with_gas_co2_and_collector(self):
        s=mixed_case();r=self.solve(s)
        self.assertEqual(len(r["totals"]["material"]),20)
        self.assertEqual(r["material_assumptions"]["model_profile"],PROFILE)
        for step in r["steps"]:
            self.assertEqual(step["devices"]["9"]["model_profile_version"],1)
            self.assertEqual(step["devices"]["10"]["model_profile_version"],2)
            self.assertEqual(step["material"]["dry_host_by_device_kg"],{"10":10000.})
            self.assertGreater(step["material"]["inventory_by_reference_kg"]["H2_gas_25c"],0.)
        self.assertGreater(r["steps"][0]["devices"]["5"]["hydrogen_in_kg_s"],0.)
        self.assertGreater(r["steps"][1]["devices"]["5"]["hydrogen_out_kg_s"],0.)

    def test_multi_store_shared_electrolyzer_and_station_capacity(self):
        s=phase_case(KINDS[0],target=1.,generation=1.)
        s["devices"].append(device(9,KINDS[1],inventory=0.))
        s["links"] += [ac(1,9,target_kind=KINDS[1]),pipe(4,9,supply=True)]
        s["options"]["terminal_hydrogen_kg"]["9"]=1.
        r=self.solve(s);step=r["steps"][0]
        self.assertAlmostEqual(step["devices"]["4"]["hydrogen_out_kg_s"]*3600,2.,places=6)
        self.assertAlmostEqual(step["devices"]["1"]["input_mw"],.11215,places=8)
        s["devices"][1]["params"]["capacity_mw"]=.11214
        self.assertFalse(backend.solve(s,GLPK)["success"])

    def test_charge_discharge_mutual_exclusion_even_with_same_step_feed(self):
        for kind in KINDS:
            s=phase_case(kind,0.,generation=1.,demand=1.)
            r=self.solve(s)
            self.assertAlmostEqual(r["steps"][0]["devices"]["5"]["hydrogen_out_kg_s"],0.,places=10)
            self.assertAlmostEqual(r["steps"][0]["served_mw"],0.,places=10)

    def test_independent_physics_rejects_feasible_lp_with_missing_charge_ac(self):
        original=backend.build_model
        def wrong_model(problem):
            model=original(problem)
            for terms,relation,rhs in model.rows:
                if terms.get("hydrogen_charge_0_5")==-43.2 and any(k.startswith("x_0_") for k in terms):
                    del terms["hydrogen_charge_0_5"]
            return model
        with mock.patch.object(backend,"build_model",side_effect=wrong_model):
            result=backend.solve(phase_case(KINDS[0],target=1.),GLPK)
        self.assertTrue(result["solver_invoked"])
        self.assertFalse(result["success"])
        self.assertEqual(result["steps"],[])
        self.assertTrue(any("atomic phase hydrogen and actual AC" in error for error in result["errors"]),result)
        retries=sum("same_model_dual_retry" in stage for stage in result.get("solver_stages",[]))
        self.assertLessEqual(retries,1)

    def test_phase_report_cannot_invent_spendable_energy_or_useful_heat(self):
        for kind in KINDS:
            s=phase_case(kind,target=1.);r=self.solve(s);p=backend.normalize(s)
            for field in ("energy_mwh","energy_mwhth","soc","charge_mw","discharge_mw","capacity_mwh","useful_heat_output_mwth","heat_output_mwth","cold_output_mwth"):
                forged=copy.deepcopy(r["steps"]);forged[0]["devices"]["5"][field]=0.
                self.assertFalse(backend.validate_schedule(p,forged)["valid"],field)

    def test_raw_provenance_and_binary_tampering_rejected(self):
        s=cycle_case(KINDS[1]);r=self.solve(s);p=backend.normalize(s)
        forged=copy.deepcopy(r["steps"])
        for flow in forged[1]["path_flows"]:
            if flow["source_id"]==8 and flow["sink_id"]==5:
                flow["source_id"]=6;break
        self.assertFalse(backend.validate_schedule(p,forged)["valid"])
        forged=copy.deepcopy(r["steps"]);forged[0]["devices"]["5"]["mode_binary"]=0.
        self.assertFalse(backend.validate_schedule(p,forged)["valid"])

    def test_fixture_writer_returns_real_audited_twenty_field_results(self):
        with tempfile.TemporaryDirectory(prefix="phase_fixtures_") as folder:
            summary=write_fixtures(folder)
            self.assertEqual(len(summary),12)
            self.assertTrue(all(x["raw_decisions_validated"] and x["material_total_fields"]==20 for x in summary))

    def test_long_multistep_boiloff_replay_and_reload_equivalence(self):
        s=phase_case(KINDS[0],100.,generation=0.,dt=.25)
        s["steps"]=[dict(s["steps"][0],time_s=i*900.) for i in range(96)]
        r=self.solve(s)
        self.assertAlmostEqual(r["final_states"]["5"]["material_inventory_kg"]["H2"],99.9,places=8)
        self.assertAlmostEqual(sum(x["material"]["hydrogen_leaked_kg"] for x in r["steps"]),.1,places=8)
        reload=phase_case(KINDS[0],99.9,generation=0.,dt=24.);r2=self.solve(reload)
        self.assertAlmostEqual(r2["final_states"]["5"]["material_inventory_kg"]["H2"],100*.999**2,places=8)


if __name__=="__main__":unittest.main()
