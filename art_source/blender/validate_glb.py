import struct,json,os
D=os.path.dirname(__file__)
for file in ['wind_turbine.glb','solar_array.glb']:
 data=open(os.path.join(D,file),'rb').read();magic,version,total=struct.unpack_from('<4sII',data);assert magic==b'glTF' and version==2 and total==len(data)
 size,kind=struct.unpack_from('<II',data,12);doc=json.loads(data[20:20+size]);nodes=doc['nodes'];print(file,'bytes',total,'meshes',len(doc['meshes']),'materials',len(doc['materials']),'nodes',[(n.get('name'),n.get('translation')) for n in nodes]);assert all(b.get('uri') is None for b in doc['buffers'])
 for m in doc['meshes']:
  for p in m['primitives']:
   assert p.get('mode',4)==4
   a=doc['accessors'][p['attributes']['POSITION']];assert a['count']>0
 if file.startswith('wind'):
  rotor=next(n for n in nodes if n.get('name')=='Rotor');assert all(abs(a-b)<1e-4 for a,b in zip(rotor['translation'],[0,9,-.89]));assert len(rotor['children'])==4
 print('PASS: GLB header, packed buffer, mesh accessors, materials and rotor hierarchy' if file.startswith('wind') else 'PASS: GLB header, packed buffer, mesh accessors and materials')
 json.dump(doc,open(os.path.join(D,file+'.json'),'w'),indent=2)
