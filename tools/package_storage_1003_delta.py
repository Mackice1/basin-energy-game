#!/usr/bin/env python3
"""Generate a local text delta only; never pushes or modifies the baseline."""
import argparse,difflib,hashlib,json,pathlib
p=argparse.ArgumentParser();p.add_argument('--baseline',type=pathlib.Path,required=True);args=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];out=root/'evidence/storage_1003';out.mkdir(parents=True,exist_ok=True)
skip={'.git','.godot','evidence','generated','__pycache__'};rows=[];patch=[]
for f in sorted(root.rglob('*')):
 r=f.relative_to(root)
 if not f.is_file() or any(x in skip for x in r.parts) or f.suffix=='.pyc':continue
 b=args.baseline/r;data=f.read_bytes();old=b.read_bytes() if b.exists() else b''
 if b.exists() and old==data:continue
 rows.append(dict(path=str(r),status='modified' if b.exists() else 'new',bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))
 try:a=old.decode().splitlines(keepends=True);z=data.decode().splitlines(keepends=True)
 except UnicodeDecodeError:raise SystemExit('Binary delta requires explicit packaging: '+str(r))
 patch.extend(difflib.unified_diff(a,z,fromfile='a/'+str(r) if b.exists() else '/dev/null',tofile='b/'+str(r)))
(out/'source_delta_manifest.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
(out/'storage_1003_source.patch').write_text(''.join(patch))
print(len(rows),'source files;',sum(x['bytes'] for x in rows),'bytes full changed files;', (out/'storage_1003_source.patch').stat().st_size,'patch bytes')
