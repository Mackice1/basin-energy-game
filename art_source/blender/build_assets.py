import bpy, math, os, json, sys
from mathutils import Vector
D=os.path.dirname(os.path.abspath(__file__))
def vec(p):return Vector((p[0],-p[2],p[1]))
def reset():
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 for x in list(bpy.data.materials):bpy.data.materials.remove(x)
def mat(n,c,metal=0,rough=.5):
 m=bpy.data.materials.new(n);m.diffuse_color=(*c,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough;return m
def empty(n,p=(0,0,0),parent=None):
 o=bpy.data.objects.new(n,None);bpy.context.collection.objects.link(o);o.location=vec(p);o.parent=parent;return o
def finish(o,n,m,parent=None):
 o.name=n;o.data.materials.append(m)
 if parent:
  world=o.matrix_world.copy();o.parent=parent;o.matrix_world=world
 return o
def box(n,p,s,m,bevel=0,parent=None):
 bpy.ops.mesh.primitive_cube_add(size=1,location=vec(p));o=bpy.context.object;o.dimensions=(s[0],s[2],s[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  b=o.modifiers.new('Machined edges','BEVEL');b.width=bevel;b.segments=2;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=b.name)
 return finish(o,n,m,parent)
def cyl(n,p,r1,r2,h,m,parent=None):
 bpy.ops.mesh.primitive_cone_add(vertices=32,radius1=r1,radius2=r2,depth=h,location=vec(p));o=bpy.context.object
 for f in o.data.polygons:f.use_smooth=len(f.vertices)==4
 return finish(o,n,m,parent)
def beam(n,a,b,width,m):
 mid=(Vector(a)+Vector(b))/2;o=box(n,mid,(width,(Vector(b)-Vector(a)).length,width),m);o.rotation_mode='QUATERNION';o.rotation_quaternion=(vec(b)-vec(a)).to_track_quat('Z','Y');return o
def join_meshes(n,objects,parent):
 bpy.ops.object.select_all(action='DESELECT')
 for o in objects:o.select_set(True)
 bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();o=bpy.context.object;o.name=n
 world=o.matrix_world.copy();o.parent=parent;o.matrix_world=world
 return o
def scene_export(name,root,target,ortho):
 bpy.context.view_layer.update()
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
 coords=[o.matrix_world@Vector(c) for o in meshes for c in o.bound_box]
 tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes)
 stats={'triangles':tris,'mesh_objects':len(meshes),'materials':len(set(m.name for o in meshes for m in o.data.materials)),'bounds_blender':[[min(v[i] for v in coords) for i in range(3)],[max(v[i] for v in coords) for i in range(3)]],'nodes':[o.name for o in bpy.context.scene.objects]}
 bpy.ops.object.select_all(action='SELECT')
 bpy.ops.export_scene.gltf(filepath=f'{D}/../../assets/models/{name}.glb',export_format='GLB',use_selection=True,export_yup=True,export_extras=True)
 # Studio is preview-only and deliberately not exported.
 ground=mat('PreviewGround',(.12,.16,.18),0,.85);box('Preview floor',(0,-.08,0),(200,.1,200),ground)
 world=bpy.context.scene.world or bpy.data.worlds.new('World');bpy.context.scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.45,.52,.62,1);world.node_tree.nodes['Background'].inputs[1].default_value=.5
 for pos,power,size in [((12,-10,22),2400,12),((-10,-2,14),1600,10),((2,10,18),2000,8)]:
  bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(vec(target)-o.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.object.camera_add(location=vec((ortho*.85,ortho*.60+target[1],-ortho*1.05)));cam=bpy.context.object;cam.location=vec((ortho*.85,ortho*.95+target[1],ortho*1.05)) if name=='solar_array' else cam.location;cam.rotation_euler=(vec(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=ortho;bpy.context.scene.camera=cam
 sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=32;sc.cycles.use_denoising=False;sc.render.resolution_x=1100;sc.render.resolution_y=1100;sc.render.resolution_percentage=100;sc.render.image_settings.file_format='PNG';sc.render.filepath=f'{D}/{name}_preview.png';sc.view_settings.view_transform='AgX'
 bpy.context.preferences.filepaths.save_version=0; bpy.ops.wm.save_as_mainfile(filepath=f'{D}/{name}.blend')
 if '--render' in sys.argv:bpy.ops.render.render(write_still=True)
 return stats
reset()
ivory=mat('Ceramic white',(.76,.78,.77),.08,.40);metal=mat('Brushed galvanized steel',(.29,.36,.39),.72,.4);blue=mat('Deep marine blue',(.15,.23,.28),.15,.45);concrete=mat('Warm concrete',(.34,.36,.33),0,.85);dark=mat('Vent charcoal',(.025,.038,.043),.15,.7);gravel=mat('Fine aggregate',(.20,.24,.22),0,.95)
root=empty('WindTurbine');root['hub_height_m']=90.;root['rotor_diameter_m']=126.;root['world_units_per_meter']=.1
box('Service apron',(.35,.035,-.15),(3.5,.07,2.7),gravel,.07)
cyl('Foundation',(0,.12,0),.93,.93,.24,concrete);cyl('Anchor flange',(0,.29,0),.30,.30,.10,metal)
cyl('Tapered tower',(0,4.56,0),.25,.15,8.5,ivory)
for h,r in [(3.1,.218),(5.9,.185)]:cyl('Tower segment seam',(0,h,0),r,r,.022,metal)
for k in range(16):
 angle=k*math.tau/16;cyl('Tower anchor nut',(.277*math.cos(angle),.355,.277*math.sin(angle)),.016,.016,.055,metal)
box('Door gasket',(0,.49,-.251),(.155,.38,.018),dark,.018);box('Service door',(0,.49,-.264),(.139,.35,.018),ivory,.016);box('Door handle',(.045,.48,-.279),(.012,.06,.015),metal,.004)
for k in range(3):box('Access stair',(0,.11+k*.055,-.57+k*.10),(.33,.055,.15),metal,.008)
for side in [-1,1]:
 beam('Stair rail post',(side*.18,.12,-.64),(side*.18,.46,-.64),.014,metal)
 beam('Stair rail',(side*.18,.46,-.64),(side*.18,.62,-.30),.014,metal)
box('Nacelle',(0,9,-.04),(.49,.43,1.30),ivory,.11)
box('Rear service fairing',(0,8.98,.57),(.44,.32,.16),ivory,.06)
box('Nacelle rear cooling intake',(0,8.98,.656),(.34,.19,.016),dark,.015)
for i in range(5):box('Cooling louver',(0,8.91+i*.034,.669),(.32,.012,.018),metal)
cyl('Yaw collar',(0,8.73,0),.17,.17,.16,metal)
box('Roof maintenance hatch',(0,9.225,.17),(.29,.026,.40),metal,.018)
beam('Sensor mast',(0,9.24,.40),(0,9.53,.40),.016,metal);box('Wind vane',(0,9.54,.40),(.20,.018,.04),metal,.006)
# The cable leaves the tower at grade and follows a covered service duct to
# the ground cabinet. It is never a wire drawn to arbitrary nacelle cladding.
duct=mat('Cable duct galvanized lid',(.36,.40,.41),.7,.45)
box('Tower cable gland',(.21,.20,0),(.10,.11,.14),metal,.014)
box('Covered cable duct',(.65,.10,0),(.89,.08,.19),duct,.012)
box('Converter base',(1.15,.10,0),(.70,.14,.50),metal,.018)
box('Converter',(1.15,.44,0),(.60,.60,.40),ivory,.035)
box('Converter service door',(1.15,.44,-.207),(.51,.51,.018),metal,.012)
box('Converter vents',(1.15,.27,-.222),(.38,.10,.012),dark,.006)
box('Converter door handle',(1.35,.47,-.226),(.012,.12,.015),dark,.004)
box('Converter cable termination',(1.15,.65,-.31),(.15,.14,.14),metal,.014)
rotor=empty('Rotor',(0,9,-.89),root);rotor['rotation_axis_godot']='Z';rotor['radius_world']=6.3
bpy.context.view_layer.update()
# Three swept and tapered closed airfoil blades. Radial span is exactly 6.3.
for k in range(3):
 stations=[(.20,.11,0,.07),(.65,.23,.01,.10),(1.2,.30,.035,.09),(2.5,.225,-.045,.065),(4.4,.135,-.12,.035),(5.8,.065,-.17,.016),(6.3,.012,-.19,.007)]
 verts=[];faces=[];angle=k*math.tau/3
 for r,w,s,t in stations:
  for x,d in [(-w+s,0),(-w*.2+s,-t),(w+s,0),(-w*.2+s,t)]:
   gx=x*math.cos(angle)-r*math.sin(angle);gy=x*math.sin(angle)+r*math.cos(angle);verts.append(tuple(vec((gx,gy,d))))
 for j in range(len(stations)-1):
  for q in range(4):faces.append((j*4+q,j*4+(q+1)%4,(j+1)*4+(q+1)%4,(j+1)*4+q))
 faces.extend([(3,2,1,0),tuple(range((len(stations)-1)*4,len(stations)*4))]);me=bpy.data.meshes.new('Airfoil');me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new('Blade_%d'%(k+1),me);bpy.context.collection.objects.link(o);o.parent=rotor;o.data.materials.append(ivory);o.data.materials.append(blue)
 for p in me.polygons:p.use_smooth=True;p.material_index=0
bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,location=vec((0,9,-1.02)));o=bpy.context.object;o.scale=(.25,.34,.25);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);finish(o,'Spinner',ivory,rotor)
for p in o.data.polygons:p.use_smooth=True
static=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.parent!=rotor];join_meshes('Structure',static,root)
port=empty('ElectricityPort',(1.15,.65,-.37),root);port['port_type']='electricity'
wind=scene_export('wind_turbine',root,(0,7.5,0),19)
if '--wind-only' in sys.argv:
 with open(f'{D}/wind_asset_stats.json','w') as f:json.dump(wind,f,indent=2)
 print('WIND_REFINEMENT_COMPLETE',wind['triangles'])
 raise SystemExit(0)
reset();ivory=mat('Enclosure ivory',(.69,.73,.73),.12,.4);metal=mat('Anodized aluminum',(.38,.46,.49),.8,.32);dark=mat('Panel backsheet',(.035,.05,.065),.1,.6);concrete=mat('Warm concrete',(.34,.36,.33),0,.85);gravel=mat('Fine aggregate',(.20,.24,.22),0,.95);glass=mat('Monocrystalline cells',(.025,.065,.12),.45,.26)
# Embedded 256px cell atlas with six columns, ten rows and thin silver busbars.
im=bpy.data.images.new('PV_cell_atlas_256',width=256,height=256);pixels=[]
for y in range(256):
 for x in range(256):
  cx=(x*6)%256;cy=(y*10)%256
  if cx<8 or cy<8:c=(.16,.22,.27)
  elif cx%85<3:c=(.22,.29,.34)
  else:
   v=.015*((x*6//256+y*10//256)%3);c=(.026+v,.07+v,.13+v)
  pixels.extend((*c,1))
im.pixels=pixels;im.pack();node=glass.node_tree.nodes.new('ShaderNodeTexImage');node.image=im;glass.node_tree.links.new(node.outputs['Color'],glass.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
root=empty('SolarArray');root['tilt_deg']=25.;root['field_representation']=True;root['module_area_m2']=16000.;root['module_surface_area_world']=1.55*1.7*12
box('Service field',(0,.025,0),(7,.05,6.6),gravel,.08)
tilt=math.radians(25);w=1.55;length=1.7
for row in range(3):
 for col in range(4):
  x=(col-1.5)*1.75;z=(row-1)*2.12;cy=.48+math.sin(tilt)*length/2
  frame=empty('Panel_%d_%d'%(row,col),(x,cy,z));frame.rotation_euler.x=tilt;bpy.context.view_layer.update()
  # Local Z-up Blender boxes then move under the tilted assembly.
  for label,sz,loc,m in [('Frame',(w+.06,.075,length+.06),(0,0,0),metal),('Backsheet',(w,.012,length),(0,-.045,0),dark),('Cells',(w-.035,.012,length-.035),(0,.045,0),glass)]:
   o=box(label,loc,sz,m,.008 if label!='Cells' else 0);o.parent=frame
   if label=='Cells':
    uv=o.data.uv_layers.active
    for poly in o.data.polygons:
     for li in poly.loop_indices:
      v=o.data.vertices[o.data.loops[li].vertex_index].co;uv.data[li].uv=(v.x/(w-.035)+.5,v.y/(length-.035)+.5)
  for side in [-1,1]:
   support_z=z+side*.56*math.cos(tilt);height=cy-side*.56*math.sin(tilt)-.05
   for sx in [-.52,.52]:
    box('Ground foot',(x+sx,.09,support_z),(.27,.12,.27),concrete,.018);box('Racking post',(x+sx,height/2,support_z),(.055,height,.055),metal)
   beam('Racking crossbar',(x-.66,height,support_z),(x+.66,height,support_z),.055,metal)
  beam('Diagonal brace',(x-.52,.16,z-.5),(x+.52,cy-math.tan(tilt)*.5-.10,z+.5),.035,metal)
box('Inverter plinth',(3.75,.055,0),(.95,.11,.70),concrete,.035);box('Inverter',(3.75,.43,0),(.7,.75,.45),ivory,.06);box('Inverter dark fascia',(3.75,.42,-.236),(.49,.54,.025),dark,.025)
for i in range(5):box('Heat sink',(4.11,.38,-.12+i*.06),(.04,.45,.025),metal)
box('Status display',(3.75,.58,-.257),(.26,.10,.015),glass,.012)
bpy.context.view_layer.update();join_meshes('ArrayAssembly',[o for o in bpy.context.scene.objects if o.type=='MESH'],root)
for o in list(bpy.context.scene.objects):
 if o.type=='EMPTY' and o!=root:bpy.data.objects.remove(o,do_unlink=True)
empty('ElectricityPort',(3.75,.38,-.30),root)
solar=scene_export('solar_array',root,(.2,.4,0),11)
with open(f'{D}/asset_stats.json','w') as f:json.dump({'wind':wind,'solar':solar},f,indent=2)
