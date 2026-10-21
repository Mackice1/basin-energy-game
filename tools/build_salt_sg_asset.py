"""Derive a separately typed teaching salt SG from the original process-skid mesh.
Geometry envelope is reused, not claimed as engineered 565C material selection.
No existing GLB is modified. Original editable source: rankine_assets.blend.
"""
import json,struct
from pathlib import Path
root=Path(__file__).resolve().parents[1];path=root/'assets/models/steam_generator.glb';raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n])
for node in doc.get('nodes',[]):
 if node.get('name')=='Port_oil_in':node['name']='Port_salt_in'
 if 'extras' in node:
  e=node['extras']
  if e.get('asset_node_name')=='Port_oil_in':e['asset_node_name']='Port_salt_in'
  if e.get('carrier')=='heat_oil':e['carrier']='heat_salt'
  if e.get('grade_id')=='oil_300_200':e['grade_id']='salt_565_290'
encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4);rest=raw[20+n:]
out=root/'assets/models/salt_steam_generator.glb';out.write_bytes(struct.pack('<4sII',b'glTF',2,20+len(encoded)+len(rest))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+rest)
old=json.loads((root/'assets/models/rankine_asset_manifest.json').read_text())['assets']['steam_generator'];old['ports']['salt_in']=old['ports'].pop('oil_in');old.update(glb='assets/models/salt_steam_generator.glb',generator='tools/build_salt_sg_asset.py',bytes=out.stat().st_size,geometry_assumption='Original teaching skid envelope shared with oil SG; separately typed molten salt/water ports; no vendor sizing or alloy qualification claim.')
(root/'assets/models/tower_asset_manifest.json').write_text(json.dumps({'assets':{'salt_steam_generator':old}},indent=2)+'\n')
