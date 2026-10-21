"""Original V20 Rankine assets and V20.1 concentric-ring tower preview.
Run: blender -b -t 4 --python tools/build_rankine_assets.py [-- --tower-only --render]
Every export is exactly 0.1 world/m. --tower-only preserves the four process GLBs.
Teaching equipment envelopes/layout are original, not vendor CAD or engineered CSP.
"""
import importlib.util, json, math, struct, sys
from pathlib import Path
import bpy
from mathutils import Vector
PROJECT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('thermal_helpers', PROJECT/'tools/build_thermal_assets.py')
t = importlib.util.module_from_spec(spec); spec.loader.exec_module(t)
OUT = PROJECT/'assets/models'; SRC = PROJECT/'art_source/blender'
MAN = {}
TOWER_RING_RADII_M = (18.0, 30.0, 42.0, 54.0)
TOWER_RING_SLOTS = (16, 24, 32, 40)
TOWER_SUN_DIRECTION = Vector((-.4, .8, -.3)).normalized()
TOWER_RECEIVER_M = Vector((0, 24, 0))

def tower_mirror_layout():
    """Fixed teaching snapshot: stagger rings, reserve a 4 m east-west road."""
    for ring, (radius, slots) in enumerate(zip(TOWER_RING_RADII_M, TOWER_RING_SLOTS)):
        for slot in range(slots):
            angle = math.tau * (slot + .5 * (ring % 2)) / slots
            x, z = radius * math.cos(angle), radius * math.sin(angle)
            if abs(z) < 5.0:
                continue
            yield ring, Vector((x, 3, z))


def attach(ob, parent):
    bpy.context.view_layer.update()
    matrix = ob.matrix_world.copy(); ob.parent = parent; ob.matrix_world = matrix
    return ob

def tower_preview():
    root = t.start('tower_station_preview', math.sqrt(2)*8, 'uncommissioned_teaching_tower_preview')
    root['commissioned'] = False; root['preview_only'] = True
    layout = list(tower_mirror_layout())
    root['heliostat_count'] = len(layout); root['mirror_aperture_area_m2'] = len(layout)*16.0
    root['layout_version'] = 'V20.1'; root['ring_radii_m'] = list(TOWER_RING_RADII_M)
    root['sun_direction'] = list(TOWER_SUN_DIRECTION); root['receiver_target_m'] = list(TOWER_RECEIVER_M)
    root['tracking_mode'] = 'fixed_teaching_snapshot_not_realtime'
    exterior = t.empty('ExteriorSite', (0,0,0), root)
    working = t.empty('WorkingPreview', (0,0,0), root)
    attach(t.box('Site160m',(0,.035,0),(160,.07,160),'preview_site'), exterior)
    # Site boundary stays at +-80 m; net layout is independently delineated +-60 m.
    for z in [-79.8,79.8]:
        attach(t.box('ExteriorFence', (0,1,z),(159.6,.055,.055),'preview_steel'),exterior)
        for x in range(-78,79,6):
            attach(t.box('ExteriorFencePost',(x,.7,z),(.10,1.4,.10),'preview_steel'),exterior)
    for x in [-79.8,79.8]:
        attach(t.box('ExteriorFence',(x,1,0),(.055,.055,159.6),'preview_steel'),exterior)
        for z in range(-78,79,6):
            attach(t.box('ExteriorFencePost',(x,.7,z),(.10,1.4,.10),'preview_steel'),exterior)
    attach(t.box('Usable120m',(0,.085,0),(120,.03,120),'gravel'),working)
    for z in [-59.8,59.8]:attach(t.box('NetBoundary',(0,.106,z),(119.6,.012,.10),'warm'),working)
    for x in [-59.8,59.8]:attach(t.box('NetBoundary',(x,.106,0),(.10,.012,119.6),'warm'),working)
    attach(t.box('RadialServiceRoad',(0,.108,0),(120,.012,4),'preview_site'),working)
    for i, (ring, position) in enumerate(layout):
        x, y, z = position
        h = t.empty(f'Heliostat{i+1:03d}',(0,0,0),working)
        h['mirror_dimensions_m'] = [4.0,4.0]; h['aperture_area_m2'] = 16.0
        h['ring_index'] = ring; h['mirror_center_m'] = list(position)
        attach(t.box('MirrorFooting',(x,.20,z),(1.2,.2,1.2),'concrete'),h)
        attach(t.cylinder('AzimuthPedestal',(x,.30,z),(x,y,z),.10,'preview_steel'),h)
        target_direction = (TOWER_RECEIVER_M-position).normalized()
        n = (TOWER_SUN_DIRECTION+target_direction).normalized()
        rotation=t.vec((0,1,0)).rotation_difference(t.vec(n))
        panel=t.box(f'MirrorSurface{i+1:03d}',position,(4,.04,4),'mirror')
        panel.rotation_mode='QUATERNION';panel.rotation_quaternion=rotation;attach(panel,h)
        panel['mirror_normal'] = list(n)
        frame=t.box('MirrorBacking',position,(4,.08,4),'dark');frame.rotation_mode='QUATERNION';frame.rotation_quaternion=rotation
        frame.location-=t.vec(n)*.06;attach(frame,h)
    tower=t.empty('ReceiverTower25m',(0,0,0),working)
    attach(t.box('TowerFooting',(0,.25,0),(8,.30,8),'concrete'),tower)
    for x in [-1,1]:
        for z in [-1,1]:
            attach(t.rod('TaperedTowerLeg',(x*2.8,.40,z*2.8),(x*1,22.5,z*1),.17,'preview_steel'),tower)
    for level in range(5):
        y0=.40+level*4.4;y1=.40+(level+1)*4.4
        width0=2.8-(y0-.4)*1.8/22.1;width1=2.8-(y1-.4)*1.8/22.1
        for side in [-1,1]:
            for swap in [-1,1]:
                attach(t.rod('TowerCrossBrace',(side*width0,y0,swap*width0),(side*width1,y1,-swap*width1),.055,'preview_steel'),tower)
                attach(t.rod('TowerCrossBrace',(swap*width0,y0,side*width0),(-swap*width1,y1,side*width1),.055,'preview_steel'),tower)
    attach(t.cylinder('DarkReceiver',(0,22.5,0),(0,25,0),1.3,'dark',32),tower)
    attach(t.cylinder('ReceiverCasing',(0,22.4,0),(0,22.5,0),1.5,'hot',32),tower)
    attach(t.box('FutureServiceBuilding',(48,2.35,48),(14,4.5,8),'shell'),working)
    attach(t.box('FutureServiceRoof',(48,4.65,48),(14.2,.10,8.2),'preview_steel'),working)
    attach(t.box('UncommissionedPreviewPlaque',(48,2.4,43.96),(8,1.2,.04),'warm'),working)
    attach(t.box('FutureServiceDoor',(48,1.45,43.94),(2.2,2.7,.05),'dark'),working)
    return root, {}

def steam_generator():
    root=t.start('steam_generator',math.hypot(8,6.5)*.05,'oil_heated_steam_generator_skid')
    t.box('SteamGeneratorSkid',(0,.075,0),(4,.15,2.5),'concrete')
    for x in [-1.05,1.05]:t.box('PressureVesselSaddle',(x,.5,.15),(.22,.70,1.05),'steel')
    t.cylinder('OilWaterIsolatedShell',(-1.35,1.30,.15),(1.35,1.30,.15),.55,'shell',32)
    for x in [-1.38,1.38]:t.cylinder('BoltedTubeSheet',(x-.05,1.30,.15),(x+.05,1.30,.15),.60,'steel',32)
    t.cylinder('SteamDome',(.50,1.65,.15),(.50,2.65,.15),.28,'shell',24)
    t.cylinder('SafetyValveStem',(.50,2.65,.15),(.50,2.95,.15),.055,'hot',16)
    t.box('SafetyValveHandwheel',(.50,2.98,.15),(.30,.04,.08),'warm')
    t.pipe('OilSupplyAndReturn',[(-1.75,.55,-1.10),(-1.75,1.6,-.3),(-1.2,1.6,.15)],.075,'hot')
    t.pipe('FeedwaterLine',[(.50,.5,-1.10),(.50,.5,-.60),(.5,.95,-.60)],.045,'cold')
    t.pipe('LiveSteamRiser',[(.5,2.5,.15),(1.75,2.5,.15),(1.75,2.65,-1.10)],.065,'warm')
    t.box('AuxiliaryControlPanel',(-.75,.65,-.85),(.55,.90,.45),'cold')
    t.box('PressureReadout',(-.75,.86,-1.08),(.30,.20,.02),'dark')
    return root,{'oil_in':[-1.75,.55,-1.10],'ac_in':[-.75,.50,-1.10],'feed_in':[.50,.50,-1.10],'steam_out':[1.75,2.65,-1.10]}

def steam_turbine():
    root=t.start('steam_turbine',math.hypot(8,6.5)*.05,'small_steam_turbine_generator_skid')
    t.box('TurbineGeneratorSkid',(0,.075,0),(4,.15,2.5),'concrete')
    for x in [-1.1,.65,1.4]:t.box('BearingPedestal',(x,.45,.15),(.25,.6,.65),'steel')
    t.cylinder('SteamTurbineCasing',(-1.45,1.05,.15),(-.25,1.05,.15),.52,'shell',32,r2=.36)
    for x in [-1.43,-.30]:t.cylinder('SplitCasingFlange',(x-.035,1.05,.15),(x+.035,1.05,.15),.55,'steel',32)
    t.cylinder('ShaftCoupling',(-.25,1.05,.15),(.35,1.05,.15),.16,'dark',16)
    t.cylinder('ACGenerator',(.35,1.05,.15),(1.55,1.05,.15),.48,'cold',32)
    for x in [.45,.62,.79,.96,1.13,1.3]:t.cylinder('GeneratorCoolingFin',(x,1.05,.15),(x+.035,1.05,.15),.51,'steel',24)
    t.pipe('LiveSteamInlet',[(-1.75,1.6,-1.10),(-1.75,2.1,-.45),(-.95,2.1,-.45),(-.95,1.55,.15)],.065,'warm')
    t.pipe('TurbineExhaust',[(-.6,1.05,.15),(-.6,.5,-.65),(-.6,.5,-1.10)],.15,'cold')
    t.box('GeneratorTerminalBox',(1.65,.65,-.85),(.50,.90,.45),'dark')
    t.box('LubeOilSystem',(-1.25,.40,-.85),(.6,.5,.45),'steel')
    return root,{'steam_in':[-1.75,1.6,-1.10],'exhaust_out':[-.6,.5,-1.10],'ac_out':[1.75,.5,-1.10]}

def steam_condenser():
    root=t.start('steam_condenser',math.hypot(10,8)*.05,'dry_air_cooled_surface_condenser')
    t.box('DryCondenserSkid',(0,.075,0),(6,.15,4),'concrete')
    for x in [-2.45,2.45]:
        for z in [-1.4,1.4]:t.box('DryCoolerSupport',(x,1.6,z),(.18,2.9,.18),'steel')
    t.cylinder('SurfaceCondenserShell',(-1.95,.85,0),(1.95,.85,0),.45,'shell',32)
    t.box('DryRadiatorCore',(0,2.95,0),(5.2,.45,3),'steel')
    for x in [-2.4+i*.15 for i in range(33)]:t.box('AirSideFin',(x,2.95,0),(.025,.55,2.9),'shell')
    t.box('FanPlenum',(0,3.30,0),(5.2,.20,3.0),'dark')
    for x in [-1.45,1.45]:
        t.cylinder('DryFanHousing',(x,3.40,0),(x,4.10,0),.78,'steel',32)
        t.cylinder('DryFanInlet',(x,4.105,0),(x,4.115,0),.70,'dark',32)
        t.cylinder('FanHub',(x,4.12,0),(x,4.20,0),.13,'shell',16)
        for angle in [0,math.pi/2,math.pi,3*math.pi/2]:
            ob=t.box('VisibleDryFanBlade',(x+.34*math.cos(angle),4.135,.34*math.sin(angle)),(.59,.025,.16),'shell');ob.rotation_euler.z=-angle
    t.pipe('LowPressureSteamHeader',[(-2.7,1,-1.8),(-2.7,1,0),(-1.95,.85,0)],.15,'warm')
    t.pipe('CondensateHotwellOutlet',[(1.95,.55,0),(2.7,.4,0),(2.7,.4,-1.8)],.06,'cold')
    t.box('DryFanACControl',(0,.65,-1.55),(.80,1.0,.45),'cold')
    return root,{'exhaust_in':[-2.7,1.0,-1.8],'condensate_out':[2.7,.4,-1.8],'ac_in':[0,.5,-1.8]}

def feedwater_pump():
    root=t.start('feedwater_pump',math.hypot(6,5.2)*.05,'closed_cycle_feedwater_pump_skid')
    t.box('FeedPumpSkid',(0,.075,0),(2,.15,1.2),'concrete')
    t.box('PumpBearing',(-.35,.29,0),(.40,.30,.50),'steel')
    t.box('MotorBearing',(.4,.29,0),(.65,.30,.50),'steel')
    t.cylinder('PumpVolute',(-.55,.65,0),(-.15,.65,0),.28,'shell',24)
    t.cylinder('PumpCoupling',(-.15,.65,0),(.15,.65,0),.10,'dark',16)
    t.cylinder('FeedPumpACMotor',(.15,.65,0),(.75,.65,0),.24,'cold',24)
    for x in [.22,.35,.48,.61]:t.cylinder('MotorCoolingFin',(x,.65,0),(x+.03,.65,0),.26,'steel',20)
    t.pipe('CondensateSuction',[(-.8,.5,-.48),(-.8,.65,0),(-.55,.65,0)],.055,'cold')
    t.pipe('PressurizedFeedDischarge',[(-.35,.85,0),(-.35,1.15,0),(.8,1.15,0),(.8,.85,-.48)],.045,'warm')
    t.box('PumpACIsolator',(0,1.28,-.35),(.35,.44,.24),'cold')
    return root,{'condensate_in':[-.8,.5,-.48],'feed_out':[.8,.85,-.48],'ac_in':[0,1.25,-.48]}

def export(root, ports):
    scene=bpy.context.scene
    for name,pos in ports.items():t.empty('Port_'+name,pos,root)
    bpy.context.view_layer.update()
    points=[t.godot(o.matrix_world@v.co) for o in scene.objects if o.type=='MESH' for v in o.data.vertices]
    bounds=[[min(p[i] for p in points) for i in range(3)],[max(p[i] for p in points) for i in range(3)]]
    root.scale=(.1,)*3
    bpy.ops.object.select_all(action='SELECT')
    path=OUT/(scene.name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_extras=True,export_animations=False,export_cameras=False,export_lights=False)
    # Blender object names are global across scenes, but glTF names need only
    # be local to this isolated asset. Restore exact authored marker names from
    # extras, removing Blender's automatic .001 suffix on repeated AC anchors.
    raw=path.read_bytes();json_length=struct.unpack_from('<I',raw,12)[0]
    document=json.loads(raw[20:20+json_length])
    for node in document.get('nodes',[]):
        if node.get('extras',{}).get('asset_node_name'):
            node['name']=node['extras']['asset_node_name']
    encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    remainder=raw[20+json_length:]
    path.write_bytes(struct.pack('<4sII',b'glTF',2,20+len(encoded)+len(remainder))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+remainder)
    root.scale=(1,)*3
    MAN[scene.name]={'glb':str(path.relative_to(PROJECT)),'source':'art_source/blender/rankine_assets.blend','world_units_per_meter':.1,'bounds_m':bounds,'ports':{k:[v*.1 for v in p] for k,p in ports.items()},'bytes':path.stat().st_size,'profile_anchor':[0,(bounds[1][1]+.3)*.1,0]}
    if scene.name!='tower_station_preview':
        ratings={'steam_generator':('capacity_mwth',.1,[4,3,2.5]),'steam_turbine':('mass_flow_capacity_kg_s',.05,[4,2.2,2.5]),'steam_condenser':('capacity_mwth',.08,[6,4.2,4]),'feedwater_pump':('mass_flow_capacity_kg_s',.05,[2,1.5,1.2])}
        key,value,size=ratings[scene.name];MAN[scene.name].update({'rating_parameter':key,'reference_rating':value,'unit_dimensions_m':size,'geometry_assumption':'Original fixed-size teaching process skid; no vendor capacity or engineering sizing claim.'})
    if scene.name=='tower_station_preview':MAN[scene.name].update({'commissioned':False,'preview_only':True,'energy_ports':[],'site_dimensions_m':[160,0,160],'interior_dimensions_m':[120,0,120],'tower_height_m':25,'heliostat_count':len(list(tower_mirror_layout())),'mirror_dimensions_m':[4,.12,4],'mirror_aperture_area_m2':len(list(tower_mirror_layout()))*16,'layout_version':'V20.1','ring_radii_m':list(TOWER_RING_RADII_M),'ring_counts':[sum(r == ring for r, _ in tower_mirror_layout()) for ring in range(4)],'sun_direction':list(TOWER_SUN_DIRECTION),'receiver_target_m':list(TOWER_RECEIVER_M),'tracking_mode':'fixed_teaching_snapshot_not_realtime','geometry_assumption':'Original concentric-ring teaching layout, not an engineered or commissioned CSP plant; no performance claim.'})

def render(scene):
    bpy.context.window.scene=scene;scene.world=bpy.data.worlds.new(scene.name+' studio');scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.23,.28,.34,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.75
    tower=scene.name=='tower_station_preview';factor=10 if tower else 1
    for pos,power in [((8,-10,14),2400),((-8,-2,10),1400),((2,10,10),1600)]:
        bpy.ops.object.light_add(type='AREA',location=Vector(pos)*factor);o=bpy.context.object;o.data.energy=power*factor*factor;o.data.size=8*factor;o.rotation_euler=(Vector((0,0,2*factor))-o.location).to_track_quat('-Z','Y').to_euler()
    camera_position = Vector((16,-20,16))*factor if tower else Vector((12,16,13))
    target_height = {'steam_generator':1.5,'steam_turbine':1.1,'steam_condenser':2.1,'feedwater_pump':.75,'tower_station_preview':6.25}[scene.name]
    bpy.ops.object.camera_add(location=camera_position);o=bpy.context.object;o.rotation_euler=(Vector((0,0,target_height))-o.location).to_track_quat('-Z','Y').to_euler();o.data.type='ORTHO';o.data.ortho_scale=240 if tower else 3.5 if scene.name=='feedwater_pump' else 8;scene.camera=o
    scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=False
    scene.render.resolution_x=1200;scene.render.resolution_y=900;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.filepath=str(SRC/(scene.name+'_studio.png'));bpy.ops.render.render(write_still=True)

def main():
    OUT.mkdir(parents=True,exist_ok=True);SRC.mkdir(parents=True,exist_ok=True)
    t.M=t.palette();t.M['mirror']=t.material('Blue gray heliostat reflector',(.10,.27,.37),.55,.30);t.M['gravel']=t.material('Muted sand preview layout',(.08,.065,.045),0,.95)
    t.M['preview_steel']=t.material('Dark preview tower steel',(.05,.10,.12),.45,.5);t.M['preview_site']=t.material('Muted sand site boundary',(.10,.08,.06),0,.95)
    tower_only = '--tower-only' in sys.argv
    if tower_only:
        MAN.update(json.loads((OUT/'rankine_asset_manifest.json').read_text())['assets'])
        # Rebuild editable scenes, but never touch the four existing process GLBs.
    for fn in [steam_generator,steam_turbine,steam_condenser,feedwater_pump,tower_preview]:
        root,ports=fn()
        if not tower_only or fn == tower_preview:
            export(root,ports)
    bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'rankine_assets.blend'))
    (OUT/'rankine_asset_manifest.json').write_text(json.dumps({'generator':'tools/build_rankine_assets.py','assets':MAN,'geometry_basis':'Original teaching process equipment, no vendor CAD; full-size modules, never scaled to fit'},indent=2)+'\n')
    if '--render' in sys.argv:
        selected={arg.split('=',1)[1] for arg in sys.argv if arg.startswith('--render-kind=')}
        for scene in t.SCENES:
            if not selected or scene.name in selected:render(scene)
    print('RANKINE_ASSETS_COMPLETE')
if __name__=='__main__':main()
