#!/usr/bin/env python3
"""Run all Godot regressions; provide BASIN_GLPK/BASIN_GODOT where needed.
Writes regression evidence and fixture files inside this working copy.
Requires a Godot-imported project; this does not install dependencies.
"""
import pathlib,subprocess,os,json,concurrent.futures,time,shutil,tempfile,sys
root=pathlib.Path(__file__).resolve().parents[1];out=root/'evidence/tower_rings_stage/validation';out.mkdir(exist_ok=True,parents=True)
def run(p):
 env=os.environ.copy();home=str(pathlib.Path(tempfile.gettempdir())/'basin-v201-regression'/p.stem)
 for n in ['data','cache','config']:pathlib.Path(home,n).mkdir(parents=True,exist_ok=True)
 env.update(HOME=home,XDG_DATA_HOME=home+'/data',XDG_CACHE_HOME=home+'/cache',XDG_CONFIG_HOME=home+'/config',BASIN_GLPK=os.environ.get('BASIN_GLPK',shutil.which('glpsol') or ''),BASIN_PYTHON='python3')
 try:
  r=subprocess.run([os.environ.get('BASIN_GODOT','godot'),'--headless','--path',str(root),'--script','tests/'+p.name],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
  (out/(p.stem+'.log')).write_text(r.stdout)
  print(p.name,r.returncode,flush=True);return {'test':p.name,'exit':r.returncode,'tail':r.stdout[-1000:]}
 except subprocess.TimeoutExpired as e:
  (out/(p.stem+'.log')).write_bytes(e.stdout or b'');print(p.name,'TIMEOUT',flush=True);return {'test':p.name,'exit':'timeout'}
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:results=list(ex.map(run,sorted((root/'tests').glob('test_*.gd'))))
(out/'regression_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
print('FAILED',[(x['test'],x['exit']) for x in results if x['exit']!=0],flush=True)

sys.exit(1 if any(x["exit"]!=0 for x in results) else 0)
