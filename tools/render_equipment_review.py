"""Actual GLB studio renders, not generated concept art; no desktop access."""
import bpy, sys, math
from pathlib import Path
from mathutils import Vector
args=sys.argv[sys.argv.index('--')+1:]
source=Path(args[0]);out=Path(args[1]);out.mkdir(parents=True,exist_ok=True)
def vec(p):return Vector((p[0],-p[2],p[1]))
shots=[('electric_boiler','electric_boiler',6.0,(0,1.15,0),10),('thermal_store','thermal_store',11.5,(0,3.6,0),10),('heat_exchanger','heat_exchanger',4.1,(0,.9,0),10),('wind_turbine','wind_turbine',18.5,(0,7.7,0),1),('wind_foundation','wind_turbine',3.6,(.25,.8,0),1),('wind_nacelle','wind_turbine',2.5,(0,9,.1),1)]
shots.append(('station_piping','station_piping',4.2,(0,.27,-.10),1))
if len(args)>2:shots=[s for s in shots if s[0] in args[2:]]
else:shots=[s for s in shots if s[0]!='station_piping']
for label,asset,scale,target,factor in shots:
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 bpy.ops.import_scene.gltf(filepath=str(source/('evidence/equipment_v22' if asset=='station_piping' else 'assets/models')/f'{asset}.glb'))
 for o in list(bpy.context.scene.objects):
  if o.parent is None:o.scale*=factor
 bpy.ops.mesh.primitive_plane_add(size=300,location=(0,0,-.006));floor=bpy.context.object
 m=bpy.data.materials.new('neutral studio');m.diffuse_color=(.17,.19,.21,1);m.use_nodes=True;m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.17,.19,.21,1);m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.85;floor.data.materials.append(m)
 world=bpy.data.worlds.new(label);bpy.context.scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.39,.46,.54,1);world.node_tree.nodes['Background'].inputs[1].default_value=.5
 ls=max(scale*.5,2)
 for p,power,size in [((1.1,1.8,-1.3),60,1.3),((-1.4,1,-.5),45,1.1),((.6,1.8,1.3),65,1.0)]:
  bpy.ops.object.light_add(type='AREA',location=vec(tuple(p[i]*ls+target[i] for i in range(3))));o=bpy.context.object;o.data.energy=power*ls**2;o.data.size=size*ls;o.rotation_euler=(vec(target)-o.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.object.camera_add(location=vec((scale*.76+target[0],scale*.5+target[1],-scale*.95+target[2])));cam=bpy.context.object;cam.rotation_euler=(vec(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=scale;bpy.context.scene.camera=cam
 s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.samples=32;s.cycles.use_denoising=False;s.render.resolution_x=1000;s.render.resolution_y=800;s.render.resolution_percentage=100;s.render.image_settings.file_format='PNG';s.render.filepath=str(out/f'{label}.png');s.view_settings.view_transform='AgX';bpy.ops.render.render(write_still=True)
 print('REVIEW_RENDER',label,flush=True)
