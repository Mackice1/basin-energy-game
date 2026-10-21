from pathlib import Path
import zipfile, hashlib, json
root=Path(__file__).resolve().parents[1]
base=root.parent
files=[p for p in root.rglob('*') if p.is_file() and '.godot' not in p.parts and '__pycache__' not in p.parts and 'preview' not in p.relative_to(root).parts and not p.name.endswith('.log')]
manifest={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
from datetime import datetime, timezone
out=base/('Basin-Rebuild-V13-Source-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'.zip')
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in sorted(files):z.write(p,Path('Basin02')/p.relative_to(root))
 z.writestr('SOURCE_MANIFEST.json',json.dumps(manifest,indent=2))
with zipfile.ZipFile(out) as z:
 assert z.testzip() is None
 for n,h in manifest.items():assert hashlib.sha256(z.read('Basin02/'+n)).hexdigest()==h
print(json.dumps({'path':str(out),'bytes':out.stat().st_size,'files':len(files),'sha256':hashlib.sha256(out.read_bytes()).hexdigest()}))
