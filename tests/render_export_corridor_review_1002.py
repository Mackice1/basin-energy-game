"""Offline review of the exported Godot mesh, not a game screenshot or UI test.

Run test_export_corridor_visual_1002.gd with --export-mesh first, then:
blender -b -t 4 --python tests/render_export_corridor_review_1002.py
"""
import json
import os
import struct
import tempfile

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "evidence", "export_corridor_1002")
bpy.ops.wm.read_factory_settings(use_empty=True)
source = open(os.path.join(OUT, "near.glb"), "rb").read()
length = struct.unpack_from("<I", source, 12)[0]
document = json.loads(source[20 : 20 + length])
# Blender 4.3 does not implement Godot 4.6's optional node visibility extension.
# Only a temporary review copy changes; the original generated meshes are intact.
for key in ["extensionsRequired", "extensionsUsed"]:
    document[key] = [v for v in document.get(key, []) if v != "KHR_node_visibility"]
for node in document.get("nodes", []):
    node.get("extensions", {}).pop("KHR_node_visibility", None)
payload = json.dumps(document).encode()
payload += b" " * (-len(payload) % 4)
tail = source[20 + length :]
copy = os.path.join(tempfile.gettempdir(), "export_corridor_review_1002.glb")
with open(copy, "wb") as handle:
    handle.write(struct.pack("<III", 0x46546C67, 2, 20 + len(payload) + len(tail)))
    handle.write(struct.pack("<II", len(payload), 0x4E4F534A) + payload + tail)
bpy.ops.import_scene.gltf(filepath=copy)
# Ground is an explicitly artificial review floor, not game terrain.
bpy.ops.mesh.primitive_plane_add(size=200, location=(82, -3, 0.025))
floor = bpy.context.object
material = bpy.data.materials.new("Offline review floor only")
material.diffuse_color = (0.54, 0.48, 0.37, 1)
floor.data.materials.append(material)
world = bpy.data.worlds.new("Offline review environment")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.72, 0.79, 0.82, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.65
bpy.ops.object.light_add(type="SUN", location=(60, -15, 30))
sun = bpy.context.object
sun.data.energy = 2.3
sun.rotation_euler = (0.40, -0.65, -0.5)
bpy.ops.object.camera_add(location=(65, 29, 22))
camera = bpy.context.object
camera.data.type = "ORTHO"
scene = bpy.context.scene
scene.camera = camera
scene.render.engine = "CYCLES"
scene.cycles.samples = 32
scene.cycles.use_denoising = False
scene.render.resolution_x = 1440
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "AgX"
scene.render.image_settings.file_format = "PNG"
for name, position, target, size in [
    ("corridor_offline_review", (65, 29, 22), (83, -3, 3.8), 40),
    ("tower_offline_review", (59, 14, 12), (68, -3, 4.3), 16.5),
]:
    camera.location = position
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = size
    scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
