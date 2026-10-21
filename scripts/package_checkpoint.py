"""Package self-contained desktop checkpoint, excluding caches/mobile binaries/full TTC."""
from pathlib import Path
import zipfile
root=Path(__file__).resolve().parents[1]
out=root.parent/'Basin02-Terrain3D-Checkpoint.zip'
files=[]
for p in root.rglob('*'):
    if not p.is_file() or '.godot' in p.parts or p.name.endswith('.import') or p.name in ['runtime.log','Chinese.ttc']: continue
    if '/bin/' in str(p) and any(x in p.name for x in ['android','ios','web.']): continue
    if p.suffix=='.log' and p.name!='test.log': continue
    files.append(p)
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for p in sorted(files): z.write(p,Path('Basin02')/p.relative_to(root))
with zipfile.ZipFile(out) as z: assert z.testzip() is None
print(out, out.stat().st_size, 'bytes', len(files), 'files')
