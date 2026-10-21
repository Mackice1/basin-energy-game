#!/usr/bin/env python3
"""Isolated headless regression; never touches active GUI or user save directories."""
import argparse,concurrent.futures,json,os,pathlib,subprocess,time,shutil
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--glpsol',required=True);p.add_argument('--jobs',type=int,default=2);p.add_argument('--out',default='evidence/material_phase2/regression');p.add_argument('--match',default='test_*.gd');args=p.parse_args()
solver=pathlib.Path(args.glpsol).resolve()
if not solver.is_file():p.error('actual GLPK binary is required; no skipped solver tests')
out=ROOT/args.out;out.mkdir(parents=True,exist_ok=True)
def run(test):
 home=pathlib.Path('/tmp/basin-phase2-regression')/test.stem
 env=os.environ.copy();env.update(HOME=str(home),XDG_DATA_HOME=str(home/'data'),XDG_CONFIG_HOME=str(home/'config'),XDG_CACHE_HOME=str(home/'cache'),BASIN_GLPK=str(solver),BASIN_PYTHON='python3',PATH=str(solver.parent)+os.pathsep+os.environ.get('PATH',''))
 for key in ['HOME','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:pathlib.Path(env[key]).mkdir(parents=True,exist_ok=True)
 start=time.monotonic()
 with (out/(test.stem+'.log')).open('w') as log:
  proc=subprocess.Popen(['godot','--headless','--path',str(ROOT),'--script','tests/'+test.name],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
  deadline=start+(600 if test.stem=='test_tower_day_night_world' else 120)
  code=None
  while proc.poll() is None:
   time.sleep(.1)
   current=(out/(test.stem+'.log')).read_text()
   reason='script_error' if ('SCRIPT ERROR' in current or 'Parse Error' in current) else 'timeout' if time.monotonic()>deadline else None
   if reason:
    proc.terminate()
    try:proc.wait(timeout=5)
    except subprocess.TimeoutExpired:proc.kill();proc.wait()
    code=reason;break
  if code is None:code=proc.returncode
 text=(out/(test.stem+'.log')).read_text();failed=code!=0 or 'SCRIPT ERROR' in text or 'Parse Error' in text
 record=dict(test=test.name,exit=code,failed=failed,elapsed_s=round(time.monotonic()-start,3),tail=text[-1800:]);print(test.name,'FAIL' if failed else 'PASS',record['elapsed_s'],flush=True);return record
with concurrent.futures.ThreadPoolExecutor(max_workers=max(1,min(args.jobs,4))) as pool:results=list(pool.map(run,sorted(p for p in (ROOT/'tests').glob(args.match) if p.suffix=='.gd')))
(out/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2));print('FAILED',[r['test'] for r in results if r['failed']],flush=True)
raise SystemExit(any(r['failed'] for r in results))
