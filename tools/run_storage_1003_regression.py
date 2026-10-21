#!/usr/bin/env python3
"""Headless-only full Godot regression, isolated test homes, no active user saves."""
import concurrent.futures,json,os,pathlib,subprocess,time
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'evidence/storage_1003/regression_final';OUT.mkdir(parents=True,exist_ok=True)
def run(p):
 home=pathlib.Path('/tmp/basin-storage1003-regression')/p.stem
 env=os.environ.copy();env.update(HOME=str(home),XDG_DATA_HOME=str(home/'data'),XDG_CONFIG_HOME=str(home/'config'),XDG_CACHE_HOME=str(home/'cache'),BASIN_PYTHON='python3')
 for k in ['HOME','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:pathlib.Path(env[k]).mkdir(parents=True,exist_ok=True)
 start=time.monotonic()
 with (OUT/(p.stem+'.log')).open('w') as log:
  try:
   result=subprocess.run(['godot','--headless','--path',str(ROOT),'--script','tests/'+p.name],cwd=ROOT,env=env,text=True,stdout=log,stderr=subprocess.STDOUT,timeout=600 if p.stem=='test_tower_day_night_world' else 90)
   code=result.returncode
  except subprocess.TimeoutExpired:code='timeout'
 text=(OUT/(p.stem+'.log')).read_text()
 bad=code!=0 or 'SCRIPT ERROR' in text or 'Parse Error' in text
 record=dict(test=p.name,exit=code,failed=bad,elapsed_s=round(time.monotonic()-start,3),tail=text[-1500:])
 print(p.name,'FAIL' if bad else 'PASS',record['elapsed_s'],flush=True)
 return record
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(run,sorted((ROOT/'tests').glob('test_*.gd'))))
(OUT/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
print('FAILED',[r['test'] for r in results if r['failed']],flush=True)
raise SystemExit(any(r['failed'] for r in results))
