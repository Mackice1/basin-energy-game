"""Visual-only Dunhuang-inspired tower. No changes to field/physics/ports.
blender -b -t 4 --python tools/build_csp_tower_visual.py -- --render
"""
import importlib.util, json, math, sys
from pathlib import Path
import bpy
from mathutils import Vector
P=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('rankine',P/'tools/build_rankine_assets.py')
r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r);t=r.t
E=P/'evidence/tower_redesign';E.mkdir(parents=True,exist_ok=True)
PARTS=[]
def box(name,pos,size,mat):PARTS.append(dict(type='box',name=name,pos=pos,size=size,material=mat))
def cyl(name,a,b,rad,mat='steel',r2=None,n=24):PARTS.append(dict(type='cylinder',name=name,a=a,b=b,radius=rad,top_radius=rad if r2 is None else r2,segments=n,material=mat))
def geometry():
 box('TowerFooting',(0,.25,0),(8,.30,8),'concrete')
 cyl('TaperedConcreteShaft',(0,.4,0),(0,21.9,0),1.72,'concrete',.98,48)
 cyl('ReceiverSupportShoulder',(0,21.9,0),(0,22.4,0),.98,'concrete',1.22,32)
 box('ServiceDoor',(0,1.15,-1.69),(.8,1.5,.07),'dark')
 box('DoorLintel',(0,1.94,-1.72),(1,.09,.13),'steel')
 for y in (3.2,6.3,9.4,12.5,15.6,18.7):
  radius=1.72-(y-.4)*.74/21.5
  cyl('ConcreteLiftJoint',(0,y,0),(0,y+.025,0),radius+.003,'joint',radius+.002,48)
 # Receiver remains exactly the old 22.5-25m envelope and centered at the 24m aiming height.
 cyl('DarkReceiver',(0,22.5,0),(0,24.94,0),1.3,'dark',n=48)
 for i in range(48):
  a=math.tau*i/48; x,z=1.302*math.cos(a),1.302*math.sin(a)
  cyl('AbsorberPanelSeam',(x,22.57,z),(x,24.88,z),.012,'receiver_seam',n=6)
 cyl('ReceiverTopCap',(0,24.94,0),(0,25,0),1.36,'steel',n=48)
 cyl('ReceiverCasing',(0,22.4,0),(0,22.5,0),1.44,'steel',n=48)
 cyl('MaintenanceDeck',(0,21.97,0),(0,22.08,0),1.88,'steel',n=48)
 for i in range(24):
  a=math.tau*i/24; b=math.tau*(i+1)/24
  x,z=1.82*math.cos(a),1.82*math.sin(a)
  cyl('MaintenanceRailPost',(x,22.08,z),(x,22.47,z),.022,'steel',n=6)
  for y in (22.25,22.47):cyl('MaintenanceRail',(x,y,z),(1.82*math.cos(b),y,1.82*math.sin(b)),.018,'steel',n=6)
  if i%3==0:cyl('DeckBracket',(.99*math.cos(a),21.30,.99*math.sin(a)),(x,21.98,z),.04,'steel',n=6)
 # Enclosed risers, base service box and short datum stripes are artistic service cues.
 for x in (-.24,.24):
  cyl('InsulatedSaltRiser',(x,.5,1.69),(x,21.8,1.1),.075,'steel',n=10)
 for y in (2,5,8,11,14,17,20):
  z=1.69-(y-.5)*.59/21.3
  box('PipeBracket',(0,y,z),(.72,.08,.16),'steel')
 box('TowerServiceCabinet',(2.25,.8,1.7),(.8,.8,.6),'steel')
 for x in (-.24,.24):cyl('BaseSaltService',(x,.5,1.69),(x,.5,2.65),.075,'steel',n=10)
 for z in (-2.5,2.5):box('FootingSafetyStripe',(0,.405,z),(4.4,.014,.12),'ochre')

def setup_palette():
 t.M=t.palette();t.M['mirror']=t.material('Blue gray heliostat reflector',(.10,.27,.37),.55,.30)
 t.M['gravel']=t.material('Muted sand preview layout',(.08,.065,.045),0,.95)
 t.M['preview_steel']=t.material('Dark preview tower steel',(.05,.10,.12),.45,.5)
 t.M['preview_site']=t.material('Muted sand site boundary',(.10,.08,.06),0,.95)
 # Tower-specific palette does not recolor the existing site/mirrors.
 for k,c,m,rough in [('tower_concrete',(.56,.55,.49),0,.92),('tower_steel',(.36,.42,.44),.7,.38),('tower_dark',(.026,.032,.036),.2,.72),('tower_joint',(.43,.43,.39),0,.95),('tower_receiver_seam',(.085,.093,.10),.35,.6),('tower_ochre',(.64,.40,.10),.1,.7)]:t.M[k]=t.material(k,c,m,rough)

def render(scene,path,close=False):
 scene.world=bpy.data.worlds.new('Tower neutral studio');scene.world.use_nodes=True
 scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.30,.37,.40,1)
 scene.world.node_tree.nodes['Background'].inputs[1].default_value=.7
 bpy.ops.object.light_add(type='SUN',location=(20,-30,50));sun=bpy.context.object;sun.rotation_euler=(.45,-.5,-.4);sun.data.energy=2.5;sun.data.angle=.15
 bpy.ops.object.camera_add(location=(33,-43,30) if close else (140,-180,150));cam=bpy.context.object
 target=Vector((0,0,12) if close else (0,0,5));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=31 if close else 190;scene.camera=cam
 scene.render.engine='CYCLES';scene.cycles.samples=20;scene.cycles.use_denoising=False
 scene.render.resolution_x=1100;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.render.filepath=str(path);scene.view_settings.view_transform='AgX';bpy.ops.render.render(write_still=True)
 bpy.data.objects.remove(cam,do_unlink=True);bpy.data.objects.remove(sun,do_unlink=True)

def main():
 geometry();setup_palette();root,_=r.tower_preview();scene=bpy.context.scene
 tower=next(o for o in scene.objects if o.get('asset_node_name')=='ReceiverTower25m')
 if '--render' in sys.argv:render(scene,E/'tower_before_close.png',True)
 for ob in list(tower.children):bpy.data.objects.remove(ob,do_unlink=True)
 for part in PARTS:
  mat='tower_'+part['material']
  if part['type']=='box':ob=t.box(part['name'],part['pos'],part['size'],mat)
  else:ob=t.cylinder(part['name'],part['a'],part['b'],part['radius'],mat,part['segments'],part['top_radius'])
  r.attach(ob,tower)
 # Merge static detail by material, but retain required DarkReceiver/TowerFooting markers.
 for mat in {p['material'] for p in PARTS}:
  obs=[o for o in tower.children if o.type=='MESH' and o.data.materials[0]==t.M['tower_'+mat] and o.name not in ('DarkReceiver','TowerFooting')]
  if len(obs)>1:
   bpy.ops.object.select_all(action='DESELECT')
   for o in obs:o.select_set(True)
   bpy.context.view_layer.objects.active=obs[0];bpy.ops.object.join();obs[0].name='TowerDetail_'+mat
 tower['reference_project']='Shouhang Dunhuang 100MW; silhouette only, adapted to original 25m teaching envelope'
 r.export(root,{})
 manifest_path=r.OUT/'rankine_asset_manifest.json';manifest=json.loads(manifest_path.read_text());manifest['assets']['tower_station_preview'].update(r.MAN['tower_station_preview']);manifest['assets']['tower_station_preview']['source']='art_source/blender/csp_tower_visual.blend';manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
 palette={k.replace('tower_',''):dict(color=list(m.diffuse_color)[:3],metallic=m.node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value,roughness=m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value) for k,m in t.M.items() if k.startswith('tower_')}
 (P/'assets/models/csp_tower_parts.json').write_text(json.dumps(dict(world_units_per_meter=.1,height_m=25,receiver_target_m=[0,24,0],parts=PARTS,materials=palette),indent=2)+'\n')
 bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(r.SRC/'csp_tower_visual.blend'))
 stats={'parts_authored':len(PARTS),'tower_meshes_exported':sum(o.type=='MESH' for o in tower.children),'tower_triangles':sum(len(p.vertices)-2 for o in tower.children if o.type=='MESH' for p in o.data.polygons),'tower_materials':len(palette),'glb_bytes':(r.OUT/'tower_station_preview.glb').stat().st_size,'height_m':25,'receiver_target_m':[0,24,0],'heliostats':100,'aperture_m2':1600}
 (E/'geometry_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
 if '--render' in sys.argv:render(scene,E/'tower_after_close.png',True);render(scene,E/'tower_after_site.png')
 print('CSP_TOWER_VISUAL_COMPLETE',stats)
if __name__=='__main__':main()
