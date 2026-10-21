"""Schema-12 chemical material network, independent physics and actual GLPK.

Expected constants are derived separately from the reviewed H/C/O/N contract.
The <=11 profile/default catalogs and behavior are covered by the legacy suite.
"""
from __future__ import annotations
import copy
import importlib.util
import json
import math
import os
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("chemical_backend_under_test", ROOT / "tools/dispatch_solver.py")
backend = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backend)
GLPK = os.environ.get("BASIN_GLPK", str(ROOT.parents[1]/"v22_final_acceptance_20261020/tools/glpsol"))
PROFILE = "material_chemical_2c_v3"
SYNTHESIS = ("ammonia_synthesis_station", "methanol_synthesis_station")
SOURCES = ("nitrogen_supply_boundary", "co2_supply_boundary")
H2_STORES = ("hydrogen_gas_store", "hydrogen_liquid_store", "hydrogen_metal_hydride_store")
H2_RATIO = {SYNTHESIS[0]: 6.048/34.062, SYNTHESIS[1]: 6.048/32.042}
FEED_RATIO = {SYNTHESIS[0]: 28.014/34.062, SYNTHESIS[1]: 44.009/32.042}
WATER_RATIO = {SYNTHESIS[0]: 0., SYNTHESIS[1]: 18.015/32.042}
REACTION = {SYNTHESIS[0]: -45940/17.031/3600, SYNTHESIS[1]: -130720/32.042/3600}
AC = {SYNTHESIS[0]: .25+.5/.95, SYNTHESIS[1]: .15+.6/.95}
LHV = 241826/2.016/3600


def device(ident, kind, params=None, inventory=None):
    d = {"id": ident, "kind": kind, "params": params or {}}
    if kind in SYNTHESIS+SOURCES:
        d.update(model_profile=PROFILE, model_profile_version=3)
    if inventory is not None:
        species = {SOURCES[0]: "N2", SOURCES[1]: "CO2", SYNTHESIS[0]: "NH3", SYNTHESIS[1]: "CH3OH"}.get(kind,"H2")
        d["state"] = {"material_inventory_kg": {species: inventory}}
        if kind == H2_STORES[2]: d["state"]["host_dry_mass_kg"] = d["params"].get("dry_host_mass_kg",10000.)
    return d


def ac(source, target, sk="station", tk="load", cap=10., loss=0.):
    storage = ("battery", "co2_liquid_cycle_store")
    return {"from": source, "to": target, "from_port": "ac_out" if sk == "fuel_cell_station" else "ac" if sk in storage else "out",
            "to_port": "ac_in" if tk in H2_STORES+SYNTHESIS+("electrolyzer_station",) else "ac" if tk in storage else "in",
            "carrier": "electricity_ac", "unit": "MW", "capacity_mw": cap, "loss_fraction": loss}


def pipe(source, target, species="H2", cap=1., supply=False):
    tag, phase, grade = {"H2": ("h2", "gas", "h2_gas_supply" if supply else "h2_gas_delivery"),
                         "N2": ("n2", "gas", "n2_gas_25c"), "CO2": ("co2", "gas", "co2_gas_25c"),
                         "H2O": ("water", "liquid", "water_liquid_25c")}[species]
    return {"from": source, "to": target, "from_port": tag+"_out", "to_port": tag+"_in",
            "carrier": "material_"+tag+("_gas" if phase == "gas" else ""), "unit": "kg/s", "species_id": species,
            "phase_id": phase, "grade_id": grade, "mass_flow_capacity_kg_s": cap, "loss_fraction": 0.}


def chemical_case(kind=SYNTHESIS[0], h2_kind=H2_STORES[0], *, generation=1., target=1., feed=1000., hydrogen=10., product=0., dt=1., params=None, steps=1):
    source, species = (SOURCES[0], "N2") if kind == SYNTHESIS[0] else (SOURCES[1], "CO2")
    s = {"schema_version": 12, "material_profile": PROFILE, "material_profile_version": 3,
         "devices": [device(0,"wind"), device(1,"station",{"capacity_mw":10.,"loss_fraction":0.}),
                     device(2,source,inventory=feed), device(3,h2_kind,{"leak_per_h":0.} if h2_kind == H2_STORES[0] else {}, hydrogen), device(4,kind,params,product)],
         "links": [ac(0,1,"wind","station"), ac(1,4,tk=kind), ac(1,3,tk=h2_kind), pipe(2,4,species), pipe(3,4)],
         "steps": [{"time_s": i*dt*3600, "dt_h":dt, "available_mw":{"0":generation}, "demand_mw":{}} for i in range(steps)],
         "options": {"timeout_s":30.}}
    if target is not None: s["options"]["terminal_product_kg"]={"4":target}
    return s


def add_battery(s, energy=.1, kind="battery"):
    s["devices"].append({"id":8,"kind":kind,"params":{"initial_soc":0.},"state":{"energy_mwh":energy}})
    s["links"].append(ac(8,1,kind,"station"))
    return s


def add_fc(s, demand=.01):
    s["devices"] += [device(5,"fuel_cell_station"), device(6,"station",{"capacity_mw":10.,"loss_fraction":0.}),device(7,"load")]
    s["links"] += [pipe(3,5), ac(5,6,"fuel_cell_station","station"),ac(6,7)]
    for step in s["steps"]: step["demand_mw"]={"7":demand}
    return s


def write_fixtures(directory):
    cases = {}
    for kind, name in zip(SYNTHESIS,("ammonia", "methanol")):
        cases[name+"_1kg"] = chemical_case(kind)
        for hk, short in zip(H2_STORES,("gas", "liquid", "metal")):
            cases[name+"_shared_fc_"+short] = add_fc(chemical_case(kind,hk))
        cases[name+"_finite_battery"] = add_battery(chemical_case(kind,generation=0.))
        cases[name+"_empty_feed"] = chemical_case(kind,feed=0.,target=None)
        cases[name+"_full_buffer"] = chemical_case(kind,product=200. if kind==SYNTHESIS[0] else 1000.,target=None)
        cases[name+"_no_ac"] = chemical_case(kind,generation=0.,target=None)
        cases[name+"_no_cooler"] = chemical_case(kind,params={"heat_rejection_mwth":0.},target=None)
        cases[name+"_no_heater"] = chemical_case(kind,params={"heater_electric_mw":0.},target=None)
        cases[name+"_infeasible_goal"] = chemical_case(kind,feed=0.)
    mixed=add_battery(chemical_case(SYNTHESIS[1],H2_STORES[1]),kind="co2_liquid_cycle_store")
    mixed["devices"][1]=device(1,"collector_substation",{"capacity_mw":10.,"loss_fraction":.01})
    cases["mixed_chemical_phase_co2_collector"] = mixed
    out=Path(directory);out.mkdir(parents=True,exist_ok=True)
    fixtures=[];summary=[]
    for name,snapshot in cases.items():
        result=backend.solve(snapshot,GLPK)
        infeasible=name.endswith("infeasible_goal")
        if infeasible:
            if result["success"] or result["status"] != "infeasible" or result["steps"]: raise AssertionError((name,result))
        elif not result["success"] or not result["solver_invoked"]: raise AssertionError((name,result.get("errors"),result.get("validation")))
        fixture={"name":name,"request":snapshot,"result":result}
        fixtures.append(fixture)
        (out/(name+".json")).write_text(json.dumps(fixture,indent=2,allow_nan=False)+"\n")
        summary.append({"name":name,"status":result["status"],"success":result["success"],"solver_invoked":result["solver_invoked"],"material_total_fields":len(result["totals"].get("material",{}))})
    (out/"solver_fixtures.json").write_text(json.dumps(fixtures,indent=2,allow_nan=False)+"\n")
    (out/"fixture_summary.json").write_text(json.dumps(summary,indent=2,allow_nan=False)+"\n")
    return summary


def write_forged_fixtures(directory):
    """Keep negative re-audit evidence separate from real solver fixtures."""
    out=Path(directory);out.mkdir(parents=True,exist_ok=True)
    fixtures=[];controls=[]
    for kind,prefix in zip(SYNTHESIS,("ammonia","methanol")):
        request=chemical_case(kind);result=backend.solve(request,GLPK)
        if not result["success"]:raise AssertionError(result)
        product="NH3" if kind==SYNTHESIS[0] else "CH3OH"
        reference="NH3_gas_25c" if kind==SYNTHESIS[0] else "CH3OH_liquid_25c"
        mutations={
            "profile":lambda x:x["devices"]["4"].update(model_profile=backend.MATERIAL_PROFILE,model_profile_version=1),
            "reference_stock":lambda x:x["material"]["inventory_by_reference_kg"].update({reference:2.}),
            "reference_enthalpy":lambda x:(x["devices"]["4"].update(heat_rejected_mwth=0.),x["material"].update(heat_rejected_mwth=0.,enthalpy_balance_error_mw=0.)),
            "feed_omission":lambda x:(x["lines"][3].update(sent_kg_s=0.,received_kg_s=0.,signed_kg_s=0.,active=False,direction=0),x["material_flows"][0].update(sent_kg_s=0.)),
            "product_without_atoms":lambda x:(x["next_states"]["4"]["material_inventory_kg"].update({product:2.}),x["devices"]["4"].update(next_inventory_kg=2.),x["material"]["inventory_by_reference_kg"].update({reference:2.})),
            "water_boundary":lambda x:(x["devices"]["4"].update(water_released_kg_s=.1),x["material"].update(water_released_kg_s=.1,chemical_water_released_kg_s=.1,mass_balance_error_kg=0.,hydrogen_element_error_kg=0.,oxygen_element_error_kg=0.))}
        for suffix,mutate in mutations.items():
            forged=copy.deepcopy(result);mutate(forged["steps"][0])
            audit=backend.validate_schedule(backend.normalize(request),forged["steps"])
            if audit["valid"]:raise AssertionError((prefix,suffix))
            fixtures.append({"name":"forged_"+prefix+"_"+suffix,"request":request,"result":forged,"expected_validation":False,"python_audit_errors":audit["errors"]})
    for kind,species in ((SOURCES[0],"N2"),(SOURCES[1],"CO2"),(SYNTHESIS[0],"NH3"),(SYNTHESIS[1],"CH3OH")):
        request=chemical_case(target=None,steps=100)
        request["devices"]=[device(2,kind,inventory=100.),device(4,kind,inventory=100.)];request["links"]=[]
        for step in request["steps"]:step["available_mw"]={}
        forged=backend.solve(request,GLPK)
        if not forged["success"]:raise AssertionError(forged)
        controls.append({"name":"clean_cumulative_"+species,"request":request,"result":copy.deepcopy(forged),"expected_validation":True})
        for i,step in enumerate(forged["steps"]):
            for ident,sign in (("2",1.),("4",-1.)):
                d=step["devices"][ident]
                d.update(inventory_before_kg=100.+sign*i*1e-6,inventory_after_leak_kg=100.+sign*i*1e-6,next_inventory_kg=100.+sign*(i+1)*1e-6)
                step["next_states"][ident]["material_inventory_kg"][species]=d["next_inventory_kg"]
        audit=backend.validate_schedule(backend.normalize(request),forged["steps"])
        if audit["valid"]:raise AssertionError(kind)
        fixtures.append({"name":"forged_cumulative_balanced_"+species,"request":request,"result":forged,"expected_validation":False,"python_audit_errors":audit["errors"]})
    (out/"clean_cumulative_controls.json").write_text(json.dumps(controls,indent=2,allow_nan=False)+"\n")
    (out/"forged_solver_fixtures.json").write_text(json.dumps(fixtures,indent=2,allow_nan=False)+"\n")
    (out/"forged_fixture_summary.json").write_text(json.dumps([{"name":x["name"],"expected_validation":False,"python_rejected":bool(x["python_audit_errors"])} for x in fixtures],indent=2)+"\n")
    return len(fixtures)


class ChemicalSolverTests(unittest.TestCase):
    def solve(self,s):
        r=backend.solve(s,GLPK)
        self.assertTrue(r["success"],r)
        self.assertTrue(r["solver_invoked"])
        self.assertTrue(r["validation"]["valid"],r["validation"])
        return r

    def reject(self,s):
        with self.assertRaises(backend.InputError): backend.normalize(s)

    def test_exact_1kg_stoichiometry_and_heat(self):
        for kind in SYNTHESIS:
            with self.subTest(kind=kind):
                r=self.solve(chemical_case(kind));m=r["totals"]["material"]
                prefix="ammonia" if kind==SYNTHESIS[0] else "methanol"
                self.assertAlmostEqual(m[prefix+"_produced_kg"],1.,places=8)
                self.assertAlmostEqual(m["chemical_hydrogen_consumed_kg"],H2_RATIO[kind],places=8)
                self.assertAlmostEqual(m["nitrogen_withdrawn_kg" if kind==SYNTHESIS[0] else "co2_withdrawn_kg"],FEED_RATIO[kind],places=8)
                self.assertAlmostEqual(m["chemical_water_released_kg"],WATER_RATIO[kind],places=8)
                self.assertAlmostEqual(m["chemical_electric_mwh"],AC[kind]/1000,places=10)
                self.assertAlmostEqual(m["heat_rejected_mwhth"],(AC[kind]-REACTION[kind])/1000,places=10)
                self.assertEqual(len(m),27)
                self.assertEqual(r["schema_version"],12)
                self.assertEqual((r["material_profile"],r["material_profile_version"]),(PROFILE,3))
                self.assertEqual(m["hydrogen_consumed_kg"],0.)
                for name,value in r["steps"][0]["material"].items():
                    if "error" in name:self.assertAlmostEqual(value,0.,places=8)

    def test_all_hydrogen_phases_share_fc_budget(self):
        for kind in SYNTHESIS:
            for hk in H2_STORES:
                with self.subTest(kind=kind,hk=hk):
                    r=self.solve(add_fc(chemical_case(kind,hk)));m=r["totals"]["material"]
                    self.assertAlmostEqual(m["hydrogen_discharged_kg"],m["hydrogen_consumed_kg"]+H2_RATIO[kind],places=7)
                    self.assertAlmostEqual(m["chemical_hydrogen_consumed_kg"],H2_RATIO[kind],places=7)
                    self.assertAlmostEqual(m["water_released_kg"],m["hydrogen_consumed_kg"]*18.015/2.016+WATER_RATIO[kind],places=7)

    def test_historical_catalogs_frozen(self):
        self.assertEqual((len(backend.DEFAULTS),len(backend.SCHEMA_10_DEFAULTS),len(backend.SCHEMA_11_DEFAULTS),len(backend.SCHEMA_12_DEFAULTS)),(32,33,35,39))
        for kind in SYNTHESIS+SOURCES:self.assertNotIn(kind,backend.SCHEMA_11_DEFAULTS)

    def test_schema12_required_and_reserved(self):
        for schema in range(1,12):
            s=chemical_case();s["schema_version"]=schema
            if schema==11:s.update(material_profile="material_hydrogen_2b_v2",material_profile_version=2)
            self.reject(s)
        s=chemical_case();s["devices"]=s["devices"][:2];s["links"]=s["links"][:1];s["options"].pop("terminal_product_kg")
        self.reject(s)

    def test_top_profile_exact(self):
        for key,value in (("material_profile",None),("material_profile","material_hydrogen_2b_v2"),("material_profile_version",2),("material_profile_version",True)):
            s=chemical_case()
            if value is None:s.pop(key)
            else:s[key]=value
            self.reject(s)

    def test_device_profile_exact(self):
        for index in (2,4):
            for key,value in (("model_profile","material_hydrogen_2b_v2"),("model_profile_version",2),("model_profile_version",True),("unknown",1)):
                s=chemical_case();s["devices"][index][key]=value;self.reject(s)

    def test_defaults_and_maxima_from_profile(self):
        data=json.loads((ROOT/"data/material_process_profiles_v3.json").read_text())
        for kind in SYNTHESIS:
            s=chemical_case(kind);s["devices"][2].pop("state");s["devices"][4].pop("state")
            p=backend.normalize(s)
            for index in (2,4):
                k=s["devices"][index]["kind"]
                self.assertEqual(p["nodes"][str(index)]["params"],data["defaults"][k])
                for key,value in data["maximums"][k].items():
                    for bad in (-.001,value+.001,float("nan"),float("inf"),True):
                        q=copy.deepcopy(s);q["devices"][index]["params"][key]=bad;self.reject(q)

    def test_source_defaults_cannot_exceed_reduced_capacity(self):
        s=chemical_case();s["devices"][2]["params"]["capacity_kg"]=1.;self.reject(s)
        s["devices"][2]["params"]["initial_inventory_kg"]=1.;s["devices"][2]["state"]["material_inventory_kg"]["N2"]=1.
        self.solve(s)

    def test_product_initial_param_only_zero_but_saved_state_allowed(self):
        s=chemical_case(product=1.);self.solve(s)
        s["devices"][4]["params"]["initial_inventory_kg"]=1.;self.reject(s)

    def test_inventory_state_species_and_units_exact(self):
        for index in (2,4):
            for bad in ({},{"energy_mwh":1.},{"material_inventory_kg":{"H2":1.}}, {"material_inventory_kg":{"N2":1.,"NH3":0.}}):
                s=chemical_case();s["devices"][index]["state"]=bad;self.reject(s)
        for value in (-1.,201.,float("nan"),True):
            s=chemical_case(product=value);self.reject(s)

    def test_source_alone_is_valid_finite_reference_inventory(self):
        for kind,species,reference in ((SOURCES[0],"N2","N2_gas_25c"),(SOURCES[1],"CO2","CO2_gas_25c")):
            s=chemical_case(target=None);s["devices"]=[device(2,kind)];s["links"]=[];s["steps"][0]["available_mw"]={}
            r=self.solve(s)
            self.assertEqual(r["steps"][0]["next_states"]["2"]["material_inventory_kg"][species],1000.)
            self.assertEqual(r["steps"][0]["material"]["inventory_by_reference_kg"][reference],1000.)
            self.assertEqual(r["steps"][0]["material"]["hydrogen_lhv_mwh"],0.)

    def test_terminal_product_target_validation(self):
        for goal in ({"04":1.},{4:1.},{"3":1.},{"2":1.},{"4":-1.},{"4":201.},{"4":float("nan")},{"4":True},[]):
            s=chemical_case();s["options"]["terminal_product_kg"]=goal;self.reject(s)
        s=chemical_case();s["options"]["terminal_hydrogen_kg"]={"4":1.};self.reject(s)

    def test_old_schema_rejects_even_empty_product_option(self):
        s={"schema_version":8,"devices":[device(0,"hydrogen_gas_store")],"links":[],"steps":[{"time_s":0.,"dt_h":1.,"available_mw":{},"demand_mw":{}}],"options":{"terminal_product_kg":{}}}
        self.reject(s)

    def test_material_routes_are_typed_zero_loss(self):
        for index in (3,4):
            for field,value in (("loss_fraction",.01),("phase_id","liquid"),("species_id","NH3"),("unit","MW"),("grade_id","free"),("capacity_mw",1.)):
                s=chemical_case();s["links"][index][field]=value;self.reject(s)
            s=chemical_case();s["links"].append(copy.deepcopy(s["links"][index]));self.reject(s)

    def test_wrong_feed_and_product_export_rejected(self):
        s=chemical_case();s["devices"][2]=device(2,SOURCES[1]);s["links"][3]=pipe(2,4,"CO2");self.reject(s)
        s=chemical_case();s["links"].append(pipe(4,2,"N2"));self.reject(s)
        s=chemical_case();s["links"].append(ac(4,1,sk="fuel_cell_station",tk="station"));self.reject(s)

    def test_default_goal_does_not_invent_market_or_production(self):
        for kind in SYNTHESIS:
            r=self.solve(chemical_case(kind,target=None))
            self.assertEqual(r["totals"]["material"]["chemical_electric_mwh"],0.)
            self.assertEqual(r["steps"][0]["devices"]["4"]["product_produced_kg_s"],0.)

    def test_explicit_infeasible_targets_have_no_fake_output(self):
        cases=[]
        for kind in SYNTHESIS:
            cases.extend([chemical_case(kind,feed=0.),chemical_case(kind,hydrogen=0.),chemical_case(kind,generation=0.),
                          chemical_case(kind,params={"heater_electric_mw":0.}),chemical_case(kind,params={"heat_rejection_mwth":0.}),
                          chemical_case(kind,params={"rated_electric_mw":0.}),chemical_case(kind,params={"max_product_kg_s":0.})])
        for s in cases:
            r=backend.solve(s,GLPK)
            self.assertTrue(r["solver_invoked"]);self.assertEqual(r["status"],"infeasible",r)
            self.assertFalse(r["success"]);self.assertEqual(r["steps"],[]);self.assertEqual(r["totals"],{})

    def test_exact_finite_feed_and_product_headroom(self):
        for kind in SYNTHESIS:
            capacity=200. if kind==SYNTHESIS[0] else 1000.
            r=self.solve(chemical_case(kind,feed=FEED_RATIO[kind],hydrogen=H2_RATIO[kind],product=capacity-1.,target=capacity))
            self.assertAlmostEqual(r["steps"][0]["devices"]["2"]["next_inventory_kg"],0.,places=8)
            self.assertAlmostEqual(r["steps"][0]["devices"]["3"]["next_inventory_kg"],0.,places=8)
            self.assertAlmostEqual(r["steps"][0]["devices"]["4"]["next_inventory_kg"],capacity,places=8)

    def test_pipeline_and_feed_rate_limits_are_shared(self):
        for field,where in (("mass_flow_capacity_kg_s","line"),("max_outflow_kg_s","source")):
            s=chemical_case(target=2.)
            if where=="line":s["links"][3][field]=FEED_RATIO[SYNTHESIS[0]]/3600
            else:s["devices"][2]["params"][field]=FEED_RATIO[SYNTHESIS[0]]/3600
            self.assertEqual(backend.solve(s,GLPK)["status"],"infeasible")
            s["options"]["terminal_product_kg"]["4"]=1.;self.solve(s)

    def test_heater_cooler_and_ac_are_separate_constraints(self):
        for kind in SYNTHESIS:
            heater=(.5 if kind==SYNTHESIS[0] else .6)/.95
            for field,cap in (("rated_electric_mw",AC[kind]/1000),("heater_electric_mw",heater/1000),("heat_rejection_mwth",(AC[kind]-REACTION[kind])/1000)):
                s=chemical_case(kind,params={field:cap});self.solve(s)
                s["options"]["terminal_product_kg"]["4"]=2.
                self.assertEqual(backend.solve(s,GLPK)["status"],"infeasible")

    def test_station_and_ac_cables_share_capacity_with_load(self):
        s=chemical_case(generation=.01)
        s["devices"] += [device(7,"load")];s["links"] += [ac(1,7)]
        s["steps"][0]["demand_mw"]={"7":.01};s["options"]["strict_supply"]=True
        self.assertEqual(backend.solve(s,GLPK)["status"],"infeasible")
        s["options"]["strict_supply"]=False;r=self.solve(s)
        self.assertAlmostEqual(r["steps"][0]["unserved_mw"],AC[SYNTHESIS[0]]/1000,places=8)
        s["devices"][1]["params"]["capacity_mw"]=AC[SYNTHESIS[0]]/2000
        self.assertEqual(backend.solve(s,GLPK)["status"],"infeasible")

    def test_explicit_goal_can_use_finite_battery_and_phase_aux(self):
        for kind in SYNTHESIS:
            for hk in H2_STORES:
                r=self.solve(add_battery(chemical_case(kind,hk,generation=0.)))
                self.assertGreater(r["totals"]["discharge_mwh"],0.)
                self.assertEqual(r["totals"]["material"]["hydrogen_charged_kg"],0.)
                s=add_battery(chemical_case(kind,hk,generation=0.),energy=0.)
                self.assertEqual(backend.solve(s,GLPK)["status"],"infeasible")

    def test_fc_cannot_bootstrap_synthesis_or_phase_aux(self):
        s=chemical_case(h2_kind=H2_STORES[2],generation=0.)
        s["devices"].append(device(5,"fuel_cell_station"));s["links"] += [pipe(3,5),ac(5,1,"fuel_cell_station","station")]
        p=backend.normalize(s)
        self.assertFalse(any(path["source"]=="5" for path in p["paths"]))
        self.assertEqual(backend.solve(s,GLPK)["status"],"infeasible")

    def test_old_charge_provenance_unchanged_with_chemistry(self):
        for hk in H2_STORES:
            s=add_battery(chemical_case(h2_kind=hk,generation=0.,target=None,hydrogen=0.))
            s["devices"] += [device(10,"water_supply_boundary"),device(11,"electrolyzer_station")]
            s["links"] += [pipe(10,11,"H2O"),pipe(11,3,supply=True),ac(1,11,tk="electrolyzer_station")]
            s["options"]["terminal_hydrogen_kg"]={"3":1.}
            self.assertEqual(backend.solve(s,GLPK)["status"],"infeasible")

    def test_same_step_new_hydrogen_cannot_feed_synthesis(self):
        for hk in H2_STORES:
            s=chemical_case(h2_kind=hk,hydrogen=0.)
            s["devices"] += [device(10,"water_supply_boundary"),device(11,"electrolyzer_station")]
            s["links"] += [pipe(10,11,"H2O"),pipe(11,3,supply=True),ac(1,11,tk="electrolyzer_station")]
            self.assertEqual(backend.solve(s,GLPK)["status"],"infeasible")
            s["steps"].append({**s["steps"][0],"time_s":3600.});r=self.solve(s)
            self.assertAlmostEqual(r["steps"][0]["devices"]["4"]["product_produced_kg_s"],0.,places=15)
            self.assertGreater(r["steps"][1]["devices"]["4"]["product_produced_kg_s"],0.)

    def test_two_products_share_hydrogen_without_double_spend(self):
        s=chemical_case(hydrogen=H2_RATIO[SYNTHESIS[0]]+H2_RATIO[SYNTHESIS[1]])
        s["devices"] += [device(10,SOURCES[1]),device(11,SYNTHESIS[1])]
        s["links"] += [pipe(10,11,"CO2"),pipe(3,11),ac(1,11,tk=SYNTHESIS[1])]
        s["options"]["terminal_product_kg"]["11"]=1.
        r=self.solve(s)
        self.assertAlmostEqual(r["totals"]["material"]["final_hydrogen_kg"],0.,places=7)
        s["devices"][3]["state"]["material_inventory_kg"]["H2"]-=.01
        self.assertEqual(backend.solve(s,GLPK)["status"],"infeasible")

    def test_two_stations_share_feed_without_double_spend(self):
        s=chemical_case(feed=2*FEED_RATIO[SYNTHESIS[0]])
        s["devices"].append(device(11,SYNTHESIS[0]));s["links"] += [pipe(2,11,"N2"),pipe(3,11),ac(1,11,tk=SYNTHESIS[0])]
        s["options"]["terminal_product_kg"]["11"]=1.
        self.solve(s)
        s["devices"][2]["state"]["material_inventory_kg"]["N2"]-=.01
        self.assertEqual(backend.solve(s,GLPK)["status"],"infeasible")

    def test_paused_and_reload_equivalence(self):
        s=chemical_case(product=1.,dt=0.);r=self.solve(s)
        self.assertEqual(r["steps"][0]["devices"]["4"]["product_produced_kg_s"],0.)
        self.assertEqual(r["totals"]["material"]["chemical_electric_mwh"],0.)
        s=chemical_case(SYNTHESIS[1],H2_STORES[1],steps=3,target=2.);r=self.solve(s)
        re=copy.deepcopy(s);re["steps"]=re["steps"][1:]
        for d in re["devices"]:
            if str(d["id"]) in r["steps"][0]["next_states"]:d["state"]=r["steps"][0]["next_states"][str(d["id"])]
        rr=self.solve(re)
        for k,state in rr["steps"][-1]["next_states"].items():
            for species,mass in state["material_inventory_kg"].items():self.assertAlmostEqual(mass,r["steps"][-1]["next_states"][k]["material_inventory_kg"][species],places=6)

    def test_reference_inventory_contains_products_not_product_lhv(self):
        r=self.solve(chemical_case(SYNTHESIS[1]));m=r["steps"][0]["material"]
        self.assertEqual(set(m["inventory_by_reference_kg"]),set(backend.MATERIAL_REFERENCE_IDS))
        self.assertAlmostEqual(m["inventory_by_reference_kg"]["CH3OH_liquid_25c"],1.,places=8)
        self.assertAlmostEqual(m["hydrogen_lhv_mwh"],m["hydrogen_inventory_kg"]*LHV/1000,places=10)

    def test_forged_profile_elements_enthalpy_and_fields_rejected(self):
        for kind in SYNTHESIS:
            s=chemical_case(kind);r=self.solve(s);p=backend.normalize(s)
            changes=[lambda x:x["devices"]["4"].update(model_profile_version=2),
                     lambda x:x["devices"]["4"].update(electric_input_mw=0.),
                     lambda x:x["devices"]["4"].update(product_produced_kg_s=.1),
                     lambda x:x["devices"]["4"].update(water_released_kg_s=.1),
                     lambda x:x["devices"]["4"].update(heat_rejected_mwth=0.),
                     lambda x:x["devices"]["4"].update(energy_mwh=1.),
                     lambda x:x["material"].update(carbon_element_error_kg=1.),
                     lambda x:x["material"].update(nitrogen_element_error_kg=1.),
                     lambda x:x["material"].update(hydrogen_element_error_kg=1.),
                     lambda x:x["material"].update(oxygen_element_error_kg=1.),
                     lambda x:x["material"].update(enthalpy_balance_error_mw=1.),
                     lambda x:x["material"]["inventory_by_reference_kg"].update(CO2_gas_25c=1.),
                     lambda x:x["next_states"]["4"]["material_inventory_kg"].update(H2=1.)]
            for change in changes:
                forged=copy.deepcopy(r["steps"]);change(forged[0]);self.assertFalse(backend.validate_schedule(p,forged)["valid"])

    def test_whole_schedule_small_balanced_stock_forgery_rejected(self):
        for kind in SOURCES+SYNTHESIS:
            species={SOURCES[0]:"N2",SOURCES[1]:"CO2",SYNTHESIS[0]:"NH3",SYNTHESIS[1]:"CH3OH"}[kind]
            s=chemical_case(target=None,steps=100)
            s["devices"]=[device(2,kind,inventory=100.),device(4,kind,inventory=100.)];s["links"]=[]
            for step in s["steps"]:step["available_mw"]={}
            r=self.solve(s);forged=copy.deepcopy(r["steps"])
            for i,step in enumerate(forged):
                for ident,sign in (("2",1.),("4",-1.)):
                    d=step["devices"][ident]
                    d.update(inventory_before_kg=100.+sign*i*1e-6,inventory_after_leak_kg=100.+sign*i*1e-6,next_inventory_kg=100.+sign*(i+1)*1e-6)
                    step["next_states"][ident]["material_inventory_kg"][species]=d["next_inventory_kg"]
            audit=backend.validate_schedule(backend.normalize(s),forged)
            self.assertFalse(audit["valid"])
            self.assertTrue(any("finite mass recurrence" in e or "inventory_before_kg" in e for e in audit["errors"]))

    def test_co2_energy_storage_and_collector_are_independent(self):
        s=add_battery(chemical_case(SYNTHESIS[1],H2_STORES[1],generation=0.),kind="co2_liquid_cycle_store")
        s["devices"][1]=device(1,"collector_substation",{"loss_fraction":.01})
        r=self.solve(s)
        self.assertEqual(r["steps"][0]["devices"]["8"]["model_profile"],"co2_liquid_cycle_store_v1")
        self.assertAlmostEqual(r["totals"]["material"]["co2_withdrawn_kg"],FEED_RATIO[SYNTHESIS[1]],places=8)
        self.assertEqual(r["steps"][0]["devices"]["1"]["model_profile"],"collector_substation_v1")


if __name__ == "__main__": unittest.main()
