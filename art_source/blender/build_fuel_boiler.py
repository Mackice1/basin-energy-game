"""Original natural-gas HOT-WATER boiler, in metres; no factory-CAD claim.

blender -b -t 4 --python art_source/blender/build_fuel_boiler.py -- --render
Uses the installed, existing thermal asset helpers. Does not rebuild old assets.
The one and only export scale is 0.1 world units per metre. No envelope fitting.
See docs/FUEL_BOILER_SOURCES.md for references and teaching assumptions.
"""
import argparse
import importlib.util
import json
import math
from pathlib import Path
import sys

import bpy

PROJECT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("thermal_helpers", PROJECT / "tools/build_thermal_assets.py")
t = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t)


def build():
    r = t.start("fuel_boiler", math.hypot(9, 7) / 2, "natural_gas_hot_water_skid")
    r["geometry_assumption"] = "Reference-size boiler body with original teaching burner, gas train, stack and skid; no OEM CAD claim"
    r["fixed_temperature_profile"] = "90/60 C"
    r["fuel_type"] = "natural_gas"
    r["fuel_energy_basis"] = "LHV"
    r["rated_fuel_mw_per_module"] = 2.0
    r["thermal_boundary"] = "Filled hot-water loop; fuel input and auxiliary electricity separate; no steam generation"
    r["recognition_features"] = "combustion door; forced-draft burner; gas train; flue stack; paired hot-water pipes"
    t.skid("Fuel boiler", (5.0, 3.0))
    # Reference casing: 3.480 x 1.510 x 1.730 m (L/W/H), from Bosch brochure.
    t.box("Reference-size insulated hot-water shell", (.05, 1.165, .10), (3.48, 1.73, 1.51), "shell", .14)
    for x in [-1.15, 1.15]:
        t.box("Boiler bearing rail", (x, .30, .10), (.25, .24, 1.40), "dark", .025)
    for x in [-.87, .40, 1.45]:
        t.box("Casing panel seam", (x, 1.17, -.66), (.025, 1.35, .018), "steel")
    # Circular combustion access door and a separate forced-draft burner face.
    t.cylinder("Combustion chamber front gasket", (-1.70, 1.18, .10), (-1.77, 1.18, .10), .68, "dark", 32)
    t.cylinder("Burner access door", (-1.78, 1.18, .10), (-1.81, 1.18, .10), .60, "cold", 32)
    for a in range(0, 360, 60):
        angle = math.radians(a)
        y, z = 1.18 + .55 * math.cos(angle), .10 + .55 * math.sin(angle)
        t.cylinder("Access door bolt", (-1.81, y, z), (-1.85, y, z), .038, "steel", 6)
    t.cylinder("Burner blast tube", (-1.80, 1.13, .10), (-2.04, 1.13, .10), .20, "steel", 20)
    t.box("Forced-draft burner housing", (-2.12, 1.13, -.05), (.51, .73, .69), "cold", .12)
    t.cylinder("Burner fan inlet shroud", (-2.375, 1.13, -.05), (-2.43, 1.13, -.05), .285, "dark", 24)
    for offset in [-.16, -.08, 0, .08, .16]:
        t.box("Fan intake grille", (-2.445, 1.13 + offset, -.05), (.020, .025, .42), "steel")
    t.box("Burner flame supervision", (-2.05, 1.57, -.03), (.25, .18, .23), "dark", .035)
    # Warm ochre is the existing palette's pipe-train colour, not a new fuel port.
    t.pipe("Natural gas supply train", [(-2.26, .62, -.94), (-.60, .62, -.94)], .075, "warm", .1)
    t.pipe("Burner gas feed", [(-2.26, .62, -.94), (-2.26, .62, -.35), (-2.12, .96, -.35)], .065, "warm", .1)
    for x in [-1.82, -1.27]:
        t.box("Gas safety valve body", (x, .62, -.94), (.23, .24, .24), "steel", .035)
        t.box("Gas valve actuator", (x, .84, -.94), (.18, .20, .18), "dark", .025)
    t.cylinder("Gas regulator", (-.88, .62, -.94), (-.88, .88, -.94), .15, "steel", 16)
    t.rod("Gas pressure gauge stem", (-.88, .89, -.94), (-.88, 1.03, -.94), .025)
    t.cylinder("Gas pressure gauge face", (-.88, 1.08, -.96), (-.88, 1.08, -1.015), .095, "shell", 16)
    # Distinct high flue and round cap. Total height is authored to 4.5 m.
    t.pipe("Rear combustion flue", [(1.79, 1.12, .58), (2.10, 1.12, .58), (2.10, 4.31, .58)], .20, "steel", .16, 20)
    for y in [1.64, 2.62, 3.63]:
        t.torus("Stack band", (2.10, y, .58), .205, .024, "dark", segments=20)
    t.cylinder("Flue rain cap", (2.10, 4.40, .58), (2.10, 4.50, .58), .29, "steel", 24, .055)
    for z in [.42, .74]:
        t.rod("Rain cap support", (2.10, 4.20, z), (2.10, 4.43, z), .018)
    t.rod("Stack bracket", (1.70, 1.80, .58), (2.10, 1.80, .58), .045)
    # Paired supply/return makes this visibly a hot-water circuit, not steam.
    t.pipe("Hot-water supply", [(.90, 2.00, .10), (.90, 2.26, .10), (1.84, 2.26, .10), (1.84, .63, .10), (1.84, .63, -1.42)], .10, "hot", .15)
    t.pipe("Water return", [(.10, 2.00, .10), (.10, 2.22, .10), (1.54, 2.22, .10), (1.54, .43, .10), (1.54, .43, -1.26), (1.84, .43, -1.26)], .075, "cold", .12)
    t.flange("Heat service outlet", (1.84, .63, -1.39), radius=.16, bolts=False)
    t.cabinet("Auxiliary control cabinet", (.61, .90, -1.02), .63, 1.30, .48)
    t.pipe("Auxiliary AC conduit", [(.61, .43, -1.02), (-.15, .35, -1.02), (-.15, .56, -1.43)], .045, "dark", .08, 8)
    t.box("Auxiliary AC socket", (-.15, .56, -1.43), (.22, .22, .13), "cold", .015)
    t.box("Boiler data plate", (.30, 1.58, -.675), (.55, .22, .026), "steel", .012)
    for y in [1.53, 1.58, 1.63]:
        t.box("Data plate rule", (.30, y, -.694), (.36, .013, .01), "dark")
    t.port("ac_in", (-.15, .56, -1.49), "electricity_ac", "input")
    t.port("heat_out", (1.84, .63, -1.44), "heat_water", "output", "hw_primary_90_60")
    t.empty("ProfileLabelAnchor", (0, 2.62, -.25), r)
    return r


def studio():
    scene = bpy.context.scene
    t.ROOT = None
    t.box("Preview ground", (0, -.06, 0), (200, .10, 200), "concrete")
    world = bpy.data.worlds.new("Fuel boiler studio")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (.33, .40, .48, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = .45
    target = t.vec((0, 2.15, 0))
    for pos, power, size in [((6, 11, -8), 1600, 8), ((-6, 7, -4), 1400, 7), ((2, 9, 8), 1700, 6)]:
        bpy.ops.object.light_add(type="AREA", location=t.vec(pos))
        ob = bpy.context.object
        ob.data.energy = power
        ob.data.shape = "DISK"
        ob.data.size = size
        ob.rotation_euler = (target - ob.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.object.camera_add(location=t.vec((-6.8, 5.4, -8.2)))
    camera = bpy.context.object
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 8.3
    scene.camera = camera
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PROJECT / "evidence/fuel_boiler/fuel_boiler_studio.png")
    scene.view_settings.view_transform = "AgX"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    t.M = t.palette()
    original_scene = bpy.context.scene
    r = build()
    # Exact envelope is achieved by authored coordinates, never fitted to a box.
    t.export_asset(r)
    entry = t.MANIFEST["fuel_boiler"]
    assert entry["dimensions_m"] == [5.0, 3.0, 4.5], entry["dimensions_m"]
    entry["source"] = "art_source/blender/fuel_boiler.blend"
    entry["generator"] = "art_source/blender/build_fuel_boiler.py"
    entry["source_reference"] = "docs/FUEL_BOILER_SOURCES.md"
    entry["reference_boiler_casing_m"] = [3.48, 1.51, 1.73]
    entry["recognition_features"] = ["combustion_door", "forced_draft_burner", "gas_train", "flue_stack", "hot_water_supply_return"]
    bpy.data.scenes.remove(original_scene)
    studio()
    source = PROJECT / entry["source"]
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(source))
    manifest = {"generator": entry["generator"], "blender": bpy.app.version_string,
                "world_units_per_meter": .1, "visual_dimension_profile": "metric_v1",
                "assets": {"fuel_boiler": entry}, "source_bytes": source.stat().st_size}
    (PROJECT / "assets/models/fuel_boiler_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if args.render:
        Path(bpy.context.scene.render.filepath).parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.render.render(write_still=True)
    print("FUEL_BOILER_ASSET_COMPLETE", json.dumps(entry))

if __name__ == "__main__":
    main()
