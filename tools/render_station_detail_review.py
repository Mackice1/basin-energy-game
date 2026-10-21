"""Offline Blender review of the actual Godot-exported detail mesh, not app UI evidence.
Run after tests/test_station_detail_sample.gd with: blender -b -t 4 --python tools/render_station_detail_review.py
"""
import bpy, math, os, json, struct, tempfile
from mathutils import Vector
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'evidence', 'station_detail_1002')
for stage in ['before', 'after']:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Blender 4.3 lacks Godot 4.6's optional visibility extension. Strip only
    # that extension from a temporary review copy; source meshes stay unchanged.
    source = open(os.path.join(OUT, stage + '.glb'), 'rb').read()
    jlen = struct.unpack_from('<I', source, 12)[0]
    document = json.loads(source[20:20+jlen])
    for key in ['extensionsRequired', 'extensionsUsed']:
        document[key] = [e for e in document.get(key, []) if e != 'KHR_node_visibility']
    for node in document.get('nodes', []):
        node.get('extensions', {}).pop('KHR_node_visibility', None)
    payload = json.dumps(document).encode();payload += b' ' * ((-len(payload)) % 4)
    tail = source[20+jlen:]
    copy = os.path.join(tempfile.gettempdir(), 'station_review_' + stage + '.glb')
    open(copy,'wb').write(struct.pack('<III',0x46546C67,2,20+len(payload)+len(tail))+struct.pack('<II',len(payload),0x4E4F534A)+payload+tail)
    bpy.ops.import_scene.gltf(filepath=copy)
    # Godot Y-up export is transformed by the importer into Blender Z-up.
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for o in meshes:
        if 'Selection' in o.name or 'Port' in o.name: o.hide_render = True
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0,0,-.025))
    floor=bpy.context.object
    m=bpy.data.materials.new('Review floor only');m.diffuse_color=(.70,.74,.74,1);floor.data.materials.append(m)
    world=bpy.data.worlds.new('Studio');bpy.context.scene.world=world;world.use_nodes=True
    world.node_tree.nodes['Background'].inputs[0].default_value=(.70,.76,.80,1)
    world.node_tree.nodes['Background'].inputs[1].default_value=.45
    for pos,power,size in [((-3,-5,9),1500,7),((4,3,7),1100,5)]:
        bpy.ops.object.light_add(type='AREA',location=pos);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size
        light.rotation_euler=(Vector((0,0,1.2))-light.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add(location=(-8,12,8))
    cam=bpy.context.object;cam.rotation_euler=(Vector((-.1,0,1.2))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=8.8
    scene=bpy.context.scene;scene.camera=cam;scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=False
    scene.render.resolution_x=1200;scene.render.resolution_y=800;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG'
    scene.render.filepath=os.path.join(OUT,stage+'_offline_review.png')
    bpy.ops.render.render(write_still=True)
