"""Real GLPK boundary transactions, exact finite stocks and original Godot audit.
No mocked solver, relaxed stock audit, state clipping or replacement energy.
"""
import copy
import json
import math
import os
from pathlib import Path
import random
import subprocess
import tempfile
import unittest
from unittest import mock
from test_site_layout_solver import backend, GLPK, GODOT, ROOT


def fixture(name="laes_default"):
    return json.loads((ROOT/"evidence/phase2_air_capacity"/(name+"_request.json")).read_text())


def add_step(request, duration, available=0., demand=0.):
    steps = request["steps"]
    start = steps[-1]["time_s"]+steps[-1]["dt_h"]*3600 if steps else 0.
    steps.append({"time_s":start,"dt_h":duration,"available_mw":{"0":available},"demand_mw":{"2":demand}})


def independent_godot(test,pairs):
    with tempfile.TemporaryDirectory(prefix="storage-realization-godot-") as directory:
        root=Path(directory); env=os.environ.copy()
        for key in ["HOME","XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME"]:
            path=root/key;path.mkdir();env[key]=str(path)
        source=root/"pairs.json";source.write_text(json.dumps(pairs,allow_nan=False))
        script=root/"audit.gd"
        script.write_text('''extends SceneTree
const M=preload("res://scripts/energy_model.gd")
func _initialize():
 var pairs=JSON.parse_string(FileAccess.get_file_as_string(%s))
 var errors=[]
 for i in pairs.size():
  var pair=pairs[i]
  var audit=M.Dispatch.audit_optimization_result(pair.request,pair.result)
  if not audit.is_empty():errors.append({"case":i,"audit":audit})
  var forged=pair.result.duplicate(true)
  forged.steps[-1].next_states["3"].energy_mwh=-1e-16
  if M.Dispatch.audit_optimization_result(pair.request,forged).is_empty():errors.append({"case":i,"audit":"forged negative state accepted"})
 print("STORAGE_REALIZATION_GODOT cases=",pairs.size()," errors=",JSON.stringify(errors))
 quit(0 if errors.is_empty() else 1)
''' % json.dumps(str(source)))
        run=subprocess.run([GODOT,"--headless","--path",str(ROOT),"--script",str(script)],env=env,text=True,capture_output=True,timeout=90)
    test.assertEqual(run.returncode,0,run.stdout+run.stderr)
    test.assertNotIn("SCRIPT ERROR",run.stderr)


@unittest.skipUnless(GLPK and GODOT,"Real GLPK and Godot required")
class StorageTransactionRealizationTests(unittest.TestCase):
    def solve(self,request):
        before=copy.deepcopy(request)
        result=backend.solve(request,glpsol=GLPK)
        self.assertTrue(result["success"],result)
        self.assertTrue(result["validation"]["valid"],result)
        self.assertEqual(request,before)
        problem=backend.normalize(request)
        prior=problem["nodes"]["3"]["energy"]
        params=problem["nodes"]["3"]["params"]
        for report in result["steps"]:
            detail=report["devices"]["3"]
            energy=report["next_states"]["3"]["energy_mwh"]
            self.assertGreaterEqual(energy,0.)
            self.assertLessEqual(energy,params["capacity_mwh"])
            actual=prior*math.exp(-params["self_discharge_per_h"]*report["dt_h"])+(params["charge_efficiency"]*detail["charge_mw"]-detail["discharge_mw"]/params["discharge_efficiency"])*report["dt_h"]
            self.assertEqual(energy,actual,"inventory is the actual recurrence, never clipped")
            self.assertEqual(detail["energy_before_mwh"],prior)
            self.assertEqual(detail["energy_mwh"],energy)
            prior=energy
        self.assertTrue(backend.validate_schedule(problem,result["steps"])["valid"])
        return result

    def test_original_fixtures_third_step_continuation_and_determinism(self):
        pairs=[]
        for name in ["laes_default","laes_small_eta1"]:
            for marked in [True,False]:
                request=fixture(name)
                if not marked:
                    for item in request["devices"]:item.pop("site_geometry_profile",None)
                for continuation in [False,True]:
                    candidate=copy.deepcopy(request)
                    if continuation:add_step(candidate,.37)
                    result=self.solve(candidate)
                    again=self.solve(candidate)
                    for key in ["steps","totals","initial_states","final_states","storage_transaction_normalization"]:
                        self.assertEqual(result.get(key),again.get(key),"same input deterministic "+key)
                    info=result["storage_transaction_normalization"]
                    self.assertFalse(info["inventory_clipped"])
                    self.assertFalse(info["replacement_energy_added"])
                    self.assertLess(info["max_path_adjustment_mw"],1e-11)
                    if not continuation:
                        self.assertGreater(info["path_decision_count"],0)
                        self.assertGreater(info["max_path_adjustment_mw"],0)
                    pairs.append({"request":candidate,"result":result})
        independent_godot(self,pairs)

    def test_full_charge_fractional_steps_and_multistep_emptying(self):
        rng=random.Random(20261021)
        pairs=[]
        for index in range(36):
            request=fixture()
            for item in request["devices"]:item.pop("site_geometry_profile",None)
            params=request["devices"][3]["params"]
            params.update(capacity_mwh=rng.choice([.13,.37,.93,1.73]),charge_efficiency=rng.uniform(.51,.99),discharge_efficiency=rng.uniform(.55,1.),self_discharge_per_h=rng.uniform(0,.006))
            # Enough first-step generation and time to reach full inventory,
            # followed by an adequate demand horizon to consume it all.
            request["grid_capacity_mw"]=0.
            request["steps"]=[]
            add_step(request,2.137+rng.random(),available=2.)
            for _ in range(5):add_step(request,rng.uniform(.17,1.19),demand=1.)
            add_step(request,.317)
            if index%2:
                request["devices"][1]["params"]["loss_fraction"]=.017
                for cable in request["links"]:cable["loss_fraction"]=.013
            result=self.solve(request)
            self.assertAlmostEqual(result["steps"][0]["next_states"]["3"]["energy_mwh"],params["capacity_mwh"],delta=1e-10)
            pairs.append({"request":request,"result":result})
        independent_godot(self,pairs)

    def test_original_paths_only_decrease_and_large_infeasibility_is_not_repaired(self):
        request=fixture();problem=backend.normalize(request)
        captured=[];real_run=backend.run_glpk
        def recording(*args,**kwargs):
            run=real_run(*args,**kwargs)
            if run.get("values"):captured.append(copy.deepcopy(run["values"]))
            return run
        with mock.patch.object(backend,"run_glpk",side_effect=recording):
            result=self.solve(request)
        raw=captured[-1];saved=copy.deepcopy(raw)
        actual,info=backend.realize_electric_storage_transactions(problem,raw)
        self.assertEqual(raw,saved)
        for name in raw:
            if name.startswith("x_"):self.assertLessEqual(actual[name],raw[name])
        self.assertGreater(actual["unmet_1_2"],raw["unmet_1_2"],"less energy is actually served")
        model=backend.build_model(problem)
        objective=[sum(actual[name]*coefficient for name,coefficient in terms.items()) for terms in model.objectives]
        self.assertEqual(objective,result["objective"]["published_schedule_values"],"objective rebuilt from actual changed transactions")
        coupled=copy.deepcopy(problem)
        for path in coupled["paths"]:
            if path["source"]=="3":path["sink"]="coupled_auxiliary"
        with self.assertRaisesRegex(backend.InputError,"cannot close without changing coupled activity"):
            backend.realize_electric_storage_transactions(coupled,raw)
        forged=copy.deepcopy(raw);forged["energy_1_3"]=-.001
        with self.assertRaises(backend.InputError):backend.realize_electric_storage_transactions(problem,forged)
        forged=copy.deepcopy(raw)
        # Actual path overdraw, not just a dishonest reported state.
        for j,path in enumerate(problem["paths"]):
            if path["source"]=="3" and path["sink"]=="2":forged[f"x_1_{j}"]+=.001
        with self.assertRaises(backend.InputError):backend.realize_electric_storage_transactions(problem,forged)

if __name__=="__main__":unittest.main()
