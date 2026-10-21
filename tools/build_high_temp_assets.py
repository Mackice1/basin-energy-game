"""Original V19 metre-authored oil-system assets. blender -b -t 4 --python tools/build_high_temp_assets.py
Only new V19 files are written. Export root scale is exactly 0.1 world/m.
Editable parts and tracking hierarchy retained; no manufacturer CAD or textures.
"""
import importlib.util, json, math, sys
from pathlib import Path
import bpy
from mathutils import Vector
PROJECT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('helpers',PROJECT/'tools/build_thermal_assets.py')
t=importlib.util.module_from_spec(spec);spec.loader.exec_module(t)
OUT=PROJECT/'assets/models'; SRC=PROJECT/'art_source/blender'
MAN={}

def attach(ob,parent):
    bpy.context.view_layer.update()
    matrix=ob.matrix_world.copy();ob.parent=parent;ob.matrix_world=matrix
    return ob

def trough():
    r=t.start('parabolic_trough',10,'single_axis_parabolic_trough')
    pivot=t.empty('TrackingPivot',(0,3.5,0),r)
    bpy.context.view_layer.update()
    for z in [-5.7,5.7]:
        t.box('Concrete foundation',(0,.1,z),(1.4,.2,.8),'concrete')
        t.box('Stationary tracking pedestal',(0,1.85,z),(.25,3.3,.25),'steel')
        t.cylinder('Axis bearing',(0,3.5,z-.15),(0,3.5,z+.15),.18,'dark')
    verts=[];faces=[]
    for k in range(49):
        x=-2.885+5.77*k/48;y=x*x/(4*1.71)+3.5
        verts += [t.vec((x,y,-6)),t.vec((x,y,6))]
    for k in range(48):faces.append((2*k,2*k+1,2*k+3,2*k+2))
    mesh=bpy.data.meshes.new('True parabolic optical surface');mesh.from_pydata(verts,[],faces);mesh.update()
    ob=bpy.data.objects.new('ParabolicReflector',mesh);bpy.context.collection.objects.link(ob)
    ob.data.materials.append(t.M['mirror']);attach(ob,pivot)
    for z in [-5.5,-2.75,0,2.75,5.5]:
        for k in range(16):
            x=-2.885+5.77*k/16;xx=-2.885+5.77*(k+1)/16
            attach(t.rod('Curved rib',(x,3.46+x*x/6.84,z),(xx,3.46+xx*xx/6.84,z),.035,'steel'),pivot)
        attach(t.rod('Receiver support',(0,3.5,z),(0,5.21,z),.025,'steel'),pivot)
    attach(t.cylinder('ReceiverAtFocus',(0,5.21,-6),(0,5.21,6),.035,'dark',24),pivot)
    attach(t.rod('Torque tube',(0,3.38,-6),(0,3.38,6),.09,'steel',16),pivot)
    for z in [-6,6]:
        attach(t.pipe('Receiver rotary end',[(0,5.21,z),(0,3.5,z),(0,3.5,z+(.2 if z>0 else -.2))],.045,'hot'),pivot)
    t.pipe('Stationary oil supply',[(0,3.5,-6.2),(1,3.5,-6.2),(1,.5,-6.2),(1,.5,6.3)],.06,'hot')
    t.pipe('Stationary oil return',[(.7,.3,-6.3),(.7,.3,6.3)],.05,'cold')
    t.box('AC circulation controller',(-1,.5,-6.1),(.4,.6,.3),'cold')
    return r,{'ac_in':[-1,.5,-6.3],'heat_out':[1,.5,-6.3]}

def store():
    d=(4*(.2*3600000/238/809/.8)/math.pi)**(1/3)
    r=t.start('high_temp_store',8,'direct_Therminol66_two_tank')
    for i in range(2):
        x=(-.5 if i==0 else .5)*(d+2);tag='HOT 300C' if i==0 else 'COLD 200C';mat='hot' if i==0 else 'cold'
        t.box(tag+' foundation',(x,.1,0),(d,.2,d),'concrete')
        t.cylinder(tag+' full inventory vessel',(x,.2,0),(x,d+.2,0),d/2,'shell',48)
        t.cylinder(tag+' identification band',(x,d*.70+.2,0),(x,d*.70+.45,0),d/2+.002,mat,48)
        t.cylinder(tag+' insulated roof',(x,d+.2,0),(x,d+.45,0),d/2,'steel',48,r2=d*.45)
        t.pipe(tag+' service',[(x,.35,0),(x,.35,-d/2-.35),(x/2,.35,-d/2-.35)],.05,mat)
        t.box(tag+' level gauge',(x-d*.35,d*.5+.2,-d*.37),(.07,d*.6,.05),'dark')
        for y in [.4,d*.4,d*.7,d]:t.box(tag+' ladder rung',(x+d*.40,y,-d*.33),(.30,.035,.04),'steel')
    return r,{'heat_in':[-d*.5,.35,-d*.5-.3],'heat_out':[d*.5,.35,-d*.5-.3]}

def hx():
    r=t.start('oil_water_exchanger',4,'isolated_oil_water_shell_and_tube')
    t.box('Heat transfer skid',(0,.075,0),(3,.15,2),'concrete')
    t.cylinder('Isolated shell and tube',(-.95,.95,.2),(.95,.95,.2),.4,'shell',32)
    for x in [-1,1]:
        t.box('Vessel saddle',(x,.45,.2),(.15,.6,.8),'steel')
        t.cylinder('Bolted exchanger end',(x-.04,.95,.2),(x+.04,.95,.2),.44,'steel',32)
    for x,mat in [(-1.25,'hot'),(1.25,'warm')]:
        t.pipe('Separate '+mat+' fluid manifold',[(x,.45,-.9),(x,1.3,-.4),(x*.6,1.3,.2)],.075,mat)
        t.cylinder(mat+' isolation valve',(x,1.2,-.4),(x,1.5,-.4),.10,'dark')
    t.box('AC pump controller',(0,.5,-.65),(.5,.65,.4),'cold')
    t.cylinder('AC circulation pump',(-.5,.4,-.6),(-.5,.4,-.85),.16,'cold')
    return r,{'hot_in':[-1.25,.45,-.9],'warm_out':[1.25,.45,-.9],'ac_in':[0,.4,-.9]}

def export(root,ports):
    scene=bpy.context.scene
    for name,pos in ports.items():t.empty('Port_'+name,pos,root)
    bpy.context.view_layer.update()
    points=[t.godot(o.matrix_world@v.co) for o in scene.objects if o.type=='MESH' for v in o.data.vertices]
    bounds=[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]
    # Exact metres-to-world root scale, with hierarchy intact for tracking.
    root.scale=(.1,)*3
    bpy.ops.object.select_all(action='SELECT')
    path=OUT/(scene.name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_extras=True,export_animations=False,export_cameras=False,export_lights=False)
    root.scale=(1,)*3
    MAN[scene.name]={'glb':str(path.relative_to(PROJECT)),'source':'art_source/blender/high_temp_assets.blend','world_units_per_meter':.1,'bounds_m':bounds,'ports':{k:[v*.1 for v in p] for k,p in ports.items()},'bytes':path.stat().st_size,'profile_anchor':[0,(bounds[1][1]+.3)*.1,0]}

def render(scene):
    bpy.context.window.scene=scene;scene.world=bpy.data.worlds.new(scene.name+' studio');scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.23,.28,.34,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
    for pos,power in [((8,-10,14),2500),((-8,-2,10),1800),((2,10,10),1800)]:
        bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.data.energy=power;o.data.size=8;o.rotation_euler=(Vector((0,0,2))-o.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add(location=(12,16,13));o=bpy.context.object;o.rotation_euler=(Vector((0,0,2))-o.location).to_track_quat('-Z','Y').to_euler();o.data.type='ORTHO';o.data.ortho_scale=16 if scene.name=='parabolic_trough' else 10;scene.camera=o
    scene.render.engine='CYCLES';scene.cycles.samples=16;scene.cycles.use_denoising=False
    scene.render.resolution_x=1000;scene.render.resolution_y=800;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.filepath=str(SRC/(scene.name+'_studio.png'));bpy.ops.render.render(write_still=True)

def main():
    OUT.mkdir(parents=True,exist_ok=True);SRC.mkdir(parents=True,exist_ok=True)
    t.M=t.palette();t.M['mirror']=t.material('Polished silver reflector',(.65,.75,.79),.72,.24)
    for fn in [trough,store,hx]:root,ports=fn();export(root,ports)
    bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'high_temp_assets.blend'))
    (OUT/'high_temp_asset_manifest.json').write_text(json.dumps({'generator':'tools/build_high_temp_assets.py','assets':MAN,'aperture_m2':69.24,'focal_length_m':1.71,'axis_height_m':3.5,'sweep_radius_m':3.25,'tank_reference_capacity_mwhth':.2,'enthalpy_difference_kj_kg':238,'hot_density_kg_m3':809,'freeboard_fraction':.2},indent=2)+'\n')
    if '--render' in sys.argv:
        for scene in t.SCENES:render(scene)
    print('HIGH_TEMP_ASSETS_COMPLETE')
if __name__=='__main__':main()
