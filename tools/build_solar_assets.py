"""Build only the V18 fixed-tilt, nonconcentrating evacuated-tube collector.
Run: blender -b -t 4 --python tools/build_solar_assets.py
Source dimensions are metres; helper export bakes exactly 0.1 world units/m.
Uses existing opaque industrial palette and exporter without rebuilding old assets.
"""
import importlib.util
import json
import sys
import math
from pathlib import Path
import bpy

PROJECT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('thermal_helpers', PROJECT / 'tools/build_thermal_assets.py')
t = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t)
ANGLE = math.radians(30)
W, L, THICK = 2.061, 2.241, .15
HEIGHT = .35 + L * math.sin(ANGLE) + THICK * math.cos(ANGLE)
CENTER = .35 + (HEIGHT - .35) / 2

def point(x, thickness, along):
    return (x, CENTER + along * math.sin(ANGLE) + thickness * math.cos(ANGLE), along * math.cos(ANGLE) - thickness * math.sin(ANGLE))

def panel_box(name, x, v, z, size, mat):
    ob = t.box(name, point(x, v, z), size, mat)
    ob.rotation_euler.x = -ANGLE
    return ob

def main():
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    t.M = t.palette()
    # Keep the inherited seven-material palette; polished dark blue is opaque,
    # so tubes remain readable in the software renderer without glass sorting.
    t.M['cold'].node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = .20
    r = t.start('solar_thermal', 3.0, 'fixed_tilt_evacuated_tube_collector')
    r['tube_count'] = 24; r['tilt_deg'] = 30.0
    r['absorber_area_m2'] = 3.03; r['aperture_area_m2'] = 3.19; r['gross_area_m2'] = 4.62
    r['geometry_assumption'] = 'Historical Vitosol 200-T SP2A 24-tube envelope; original educational rack and service fittings, not manufacturer CAD'
    r['collector_type'] = 'nonconcentrating evacuated tube; fixed rack, no sun tracking'
    panel_box('Insulated upper copper manifold', 0, 0, 1.0, (W, THICK, .241), 'shell')
    panel_box('Lower tube retaining rail', 0, -.027, -1.083, (W, .075, .075), 'steel')
    for i in range(24):
        x = -.958 + i * (1.916 / 23)
        t.cylinder(f'Evacuated tube {i+1:02d}', point(x, 0, -1.045), point(x, 0, .8795), .029, 'cold', 12)
        t.cylinder(f'Tube manifold socket {i+1:02d}', point(x, 0, .83), point(x, 0, .905), .033, 'steel', 8)
        t.cylinder(f'Tube lower cap {i+1:02d}', point(x, 0, -1.08), point(x, 0, -1.025), .031, 'dark', 8)
    for x in [-.84, .84]:
        panel_box('Tilted rack longitudinal member', x, -.055, 0, (.055, .04, 2.12), 'steel')
        for z in [-.80, .80]:
            top = point(x, -.075, z)
            t.rod('Rack support leg', (x, .06, top[2]), top, .028, 'steel')
            t.box('Rack anchor foot', (x, .03, top[2]), (.24, .06, .22), 'dark')
        t.rod('Triangular rack brace', (x, .10, -.69), point(x, -.075, .80), .020, 'steel')
    # Small service fittings remain inside the collector/rack footprint.
    t.box('Circulation auxiliary controller', (-.70, .30, -.45), (.30, .35, .20), 'shell')
    t.box('Controller status window', (-.70, .35, -.556), (.16, .09, .015), 'dark')
    t.cylinder('Circulation pump', (.70, .28, -.43), (.70, .28, -.60), .10, 'cold', 12)
    t.pipe('Paired warm outlet', [point(.90, 0, .95), (.90, .22, .70), (.90, .22, -.70)], .028, 'hot', .06, 8)
    t.pipe('Paired return line', [point(.78, 0, .95), (.78, .15, .70), (.78, .15, -.70)], .023, 'cold', .05, 8)
    t.box('AC auxiliary socket', (-.70, .18, -.70), (.12, .12, .08), 'cold')
    t.empty('Port_ac_in', (-.70, .18, -.75), r)
    t.empty('Port_heat_out', (.90, .22, -.75), r)
    t.empty('ProfileLabelAnchor', (0, HEIGHT + .25, 0), r)
    t.MODEL_DIR.mkdir(parents=True, exist_ok=True); t.SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    t.export_asset(r)
    source = t.SOURCE_DIR / 'solar_thermal.blend'
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(source))
    asset = t.MANIFEST['solar_thermal']
    asset['source'] = 'art_source/blender/solar_thermal.blend'
    asset.update(collector_dimensions_m=[W, L, THICK], tilt_deg=30, tube_count=24,
                 absorber_area_m2=3.03, aperture_area_m2=3.19, gross_area_m2=4.62,
                 installation_assumptions='0.35 m bottom; 2.4 m column pitch; 3.6 m row pitch; 2 m perimeter access')
    manifest = dict(generator='tools/build_solar_assets.py', blender=bpy.app.version_string,
                    world_units_per_meter=.1, visual_dimension_profile='metric_v1', assets=t.MANIFEST,
                    source_bytes=source.stat().st_size)
    (t.MODEL_DIR / 'solar_thermal_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    if '--render' in sys.argv:
        # Render the retained metre-scale authored parts, never the merged
        # world-unit export. Camera/light objects are preview-only and unsaved.
        scene = bpy.context.scene
        scene.world = bpy.data.worlds.new('Solar studio')
        scene.world.use_nodes = True
        scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.32,.39,.46,1)
        scene.world.node_tree.nodes['Background'].inputs[1].default_value = .6
        from mathutils import Vector
        for position, power in [((3,-4,6),900),((-3,-1,3),500),((1,4,5),700)]:
            bpy.ops.object.light_add(type='AREA', location=position)
            light = bpy.context.object
            light.data.energy = power; light.data.shape = 'DISK'; light.data.size = 4
            light.rotation_euler = (Vector((0,0,.8)) - light.location).to_track_quat('-Z','Y').to_euler()
        bpy.ops.object.camera_add(location=(3.4,4.5,3.2))
        camera = bpy.context.object
        camera.rotation_euler = (Vector((0,0,.8)) - camera.location).to_track_quat('-Z','Y').to_euler()
        camera.data.type = 'ORTHO'; camera.data.ortho_scale = 3.5; scene.camera = camera
        scene.render.engine = 'CYCLES'; scene.cycles.samples = 32; scene.cycles.use_denoising = False
        scene.render.resolution_x = 1100; scene.render.resolution_y = 900; scene.render.resolution_percentage = 100
        scene.render.image_settings.file_format = 'PNG'
        scene.render.filepath = str(t.SOURCE_DIR / 'solar_thermal_studio.png')
        scene.view_settings.view_transform = 'AgX'
        bpy.ops.render.render(write_still=True)
    print('SOLAR_THERMAL_ASSET_COMPLETE', source)

if __name__ == '__main__': main()
