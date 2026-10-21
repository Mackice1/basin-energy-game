"""Build original, editable thermal equipment and self-contained Godot GLBs.

Run from any directory: blender -b -t 6 --python tools/build_thermal_assets.py
Optional: add -- --render to write four studio previews to /tmp/basin_thermal_previews.

All helper coordinates use the game's X/Y-up/Z convention. Standard glTF Y-up
conversion is the ONLY axis conversion. Equipment is visual-only: dimensions,
fixed colour zones, pipe pairs and instruments make no new simulation claims.
Sources are saved as four scenes in art_source/blender/thermal_assets.blend.
The editable source retains separate named parts; exports combine all static
parts into ONE mesh with a small shared opaque PBR material palette per asset.
"""
import argparse
import json
import math
import os
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Vector, Matrix

PROJECT = Path(__file__).resolve().parents[1]
MODEL_DIR = PROJECT / "assets/models"
SOURCE_DIR = PROJECT / "art_source/blender"
PREVIEW_DIR = Path("/tmp/basin_thermal_previews")
TAU = math.tau
WORLD_UNITS_PER_METER = .1
SCENES = []
MANIFEST = {}
ROOT = None
M = {}


def vec(p):
    return Vector((p[0], -p[2], p[1]))


def godot(p):
    return Vector((p[0], p[2], -p[1]))


def material(name, colour, metallic=0.0, roughness=0.5):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*colour, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*colour, 1)
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Roughness"].default_value = roughness
    return m


def palette():
    # Same seven materials are shared by every scene. No texture dependency.
    return {
        "shell": material("Silver grey insulation cladding", (.66, .69, .70), .55, .36),
        "steel": material("Brushed stainless steel", (.38, .42, .44), .78, .30),
        "dark": material("Charcoal gasket and cable", (.040, .047, .054), .20, .53),
        "hot": material("Supply identification red", (.52, .095, .050), .05, .48),
        "cold": material("Industrial blue coating", (.055, .18, .29), .10, .42),
        "warm": material("Safety ochre and secondary ID", (.84, .51, .10), .08, .46),
        "concrete": material("Warm aggregate concrete", (.31, .35, .32), .0, .88),
    }


def empty(name, position=(0, 0, 0), parent=None):
    ob = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(ob)
    ob.location = vec(position)
    ob.parent = parent
    ob.empty_display_type = "PLAIN_AXES"
    ob.empty_display_size = .22
    ob["asset_node_name"] = name
    return ob


def start(name, radius, representation):
    global ROOT
    scene = bpy.data.scenes.new(name)
    bpy.context.window.scene = scene
    ROOT = empty("".join(word.title() for word in name.split("_")))
    ROOT["visual_only"] = True
    ROOT["capacity_added"] = 0.0
    ROOT["footprint_radius"] = radius
    ROOT["representation"] = representation
    ROOT["geometry_assumption"] = "Original fixed-size teaching visual; not a capacity-scaled engineering model"
    ROOT["temperature_is_dynamic"] = False
    ROOT["thermal_boundary"] = "Fixed working point; logical heat links represent paired supply/return service"
    ROOT["authoring_axes"] = "Blender Z-up, glTF/Godot Y-up"
    SCENES.append(scene)
    return ROOT


def finish(ob, name, mat):
    ob.name = name
    ob.data.materials.append(M[mat] if isinstance(mat, str) else mat)
    ob.parent = ROOT
    return ob


def bevel(ob, amount=.025, segments=1):
    if not amount:
        return ob
    mod = ob.modifiers.new("Fabricated edge radius", "BEVEL")
    mod.width = amount
    mod.segments = segments
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return ob


def box(name, pos, size, mat="steel", edge=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=vec(pos))
    ob = bpy.context.object
    ob.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel(ob, edge)
    return finish(ob, name, mat)


def cylinder(name, a, b, radius, mat="steel", vertices=16, r2=None):
    a, b = vec(a), vec(b)
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius,
                                   radius2=radius if r2 is None else r2,
                                   depth=(b-a).length, location=(a+b)*.5)
    ob = bpy.context.object
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = (b-a).to_track_quat("Z", "Y")
    for face in ob.data.polygons:
        face.use_smooth = len(face.vertices) == 4
    return finish(ob, name, mat)


def rod(name, a, b, radius=.035, mat="steel", vertices=8):
    return cylinder(name, a, b, radius, mat, vertices)


def rounded_path(points, bend=.18, steps=4):
    points = [Vector(p) for p in points]
    rounded = [points[0]]
    for a, p, b in zip(points[:-2], points[1:-1], points[2:]):
        da, db = a-p, b-p
        length = min(bend, da.length*.4, db.length*.4)
        q, r = p+da.normalized()*length, p+db.normalized()*length
        rounded.append(q)
        for k in range(1, steps+1):
            t = k/steps
            rounded.append(q*(1-t)**2 + p*2*t*(1-t) + r*t*t)
    rounded.append(points[-1])
    return rounded


def pipe(name, points, radius=.105, mat="hot", bend=.22, sides=10):
    points = [vec(p) for p in rounded_path(points, bend)]
    verts, faces = [], []
    previous_u = None
    for i, p in enumerate(points):
        direction = (points[min(i+1, len(points)-1)]-points[max(i-1, 0)]).normalized()
        # Parallel-transport the cross-section to avoid twisting at elbows.
        if previous_u is None:
            reference = Vector((1,0,0)) if abs(direction.x) < .9 else Vector((0,1,0))
            u = direction.cross(reference).normalized()
        else:
            u = (previous_u-direction*previous_u.dot(direction)).normalized()
            if u.length < .1:
                u = direction.cross(Vector((0,0,1))).normalized()
        v = direction.cross(u).normalized()
        previous_u = u
        for j in range(sides):
            angle = TAU*j/sides
            verts.append(p + radius*(math.cos(angle)*u+math.sin(angle)*v))
        if i:
            for j in range(sides):
                faces.append(((i-1)*sides+j, (i-1)*sides+(j+1)%sides,
                              i*sides+(j+1)%sides, i*sides+j))
    faces += [tuple(reversed(range(sides))), tuple(range((len(points)-1)*sides,len(points)*sides))]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    for f in mesh.polygons:
        f.use_smooth = len(f.vertices) == 4
    return finish(ob, name, mat)


def flange(name, p, axis=(0,0,1), radius=.22, mat="steel", bolts=True):
    p, axis = Vector(p), Vector(axis).normalized()
    cylinder(name, p-axis*.045, p+axis*.045, radius, mat, 16)
    if bolts:
        ref = Vector((0,1,0)) if abs(axis.y)<.9 else Vector((1,0,0))
        u, v = axis.cross(ref).normalized(), None
        v = axis.cross(u).normalized()
        for i in range(6):
            angle = TAU*i/6
            c = p+radius*.78*(math.cos(angle)*u+math.sin(angle)*v)
            cylinder(name+" bolt",c-axis*.07,c+axis*.07,.025,"dark",6)


def torus(name, pos, radius, thickness, mat="steel", axis=(0,1,0), segments=24):
    bpy.ops.mesh.primitive_torus_add(major_segments=segments, minor_segments=6,
                                   location=vec(pos), major_radius=radius, minor_radius=thickness)
    ob = bpy.context.object
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = vec(axis).to_track_quat("Z", "Y")
    for face in ob.data.polygons:
        face.use_smooth = True
    return finish(ob,name,mat)


def lathe(name, center, profile, mat="shell", horizontal=False, sides=28):
    # Profile values are (axial position, radius). This gives real rounded heads
    # with far fewer triangles than nested full spheres hidden inside a vessel.
    verts, faces = [], []
    c = Vector(center)
    for axial,radius in profile:
        for j in range(sides):
            t = TAU*j/sides
            p = Vector((axial,radius*math.cos(t),radius*math.sin(t))) if horizontal else Vector((radius*math.cos(t),axial,radius*math.sin(t)))
            verts.append(vec(c+p))
    for i in range(len(profile)-1):
        for j in range(sides):
            # Godot Y-up → Blender transform preserves handedness.
            face=(i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j)
            faces.append(tuple(reversed(face)) if horizontal else face)
    faces += [tuple(reversed(range(sides))), tuple(range((len(profile)-1)*sides,len(profile)*sides))]
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(verts,[],faces);mesh.update()
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob)
    # Recalculate normals consistently rather than relying on axis orientation.
    bpy.ops.object.select_all(action="DESELECT");ob.select_set(True);bpy.context.view_layer.objects.active=ob
    bpy.ops.object.mode_set(mode="EDIT");bpy.ops.mesh.select_all(action="SELECT");bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode="OBJECT")
    for f in mesh.polygons:f.use_smooth=len(f.vertices)==4
    return finish(ob,name,mat)


def port(name, position, carrier, direction, grade=None):
    ob=empty("Port_"+name,position,ROOT)
    ob["port_id"]=name;ob["carrier"]=carrier;ob["direction"]=direction
    if grade:ob["grade_id"]=grade
    return ob


def cabinet(name, pos, width=.78, height=1.9, depth=.75):
    x,y,z=pos
    box(name+" body",pos,(width,height,depth),"shell",.045)
    box(name+" door gasket",(x,y,z-depth*.5-.008),(width*.87,height*.88,.045),"dark",.015)
    box(name+" service door",(x,y,z-depth*.5-.035),(width*.81,height*.83,.035),"shell",.012)
    box(name+" display surround",(x,y+height*.18,z-depth*.5-.065),(width*.60,.32,.025),"dark",.014)
    box(name+" display",(x,y+height*.19,z-depth*.5-.081),(width*.45,.17,.012),"cold")
    for dx in [-.15,0,.15]:
        cylinder(name+" selector",(x+dx,y-.05,z-depth*.5-.076),(x+dx,y-.05,z-depth*.5-.11),.038,"warm" if dx==0 else "dark",8)
    box(name+" latch",(x+width*.29,y-.17,z-depth*.5-.09),(.035,.22,.06),"steel",.01)
    for i in range(4):
        box(name+" louver",(x,y-height*.28+i*.065,z-depth*.5-.067),(width*.55,.023,.018),"dark")


def skid(name, size):
    box(name+" concrete pad",(0,.075,0),(size[0],.15,size[1]),"concrete",.045)
    for z in [-size[1]*.32,size[1]*.32]:
        box(name+" longitudinal steel",(0,.23,z),(size[0]-.3,.16,.15),"dark",.018)
    for x in [-size[0]*.36,size[0]*.36]:
        box(name+" cross member",(x,.23,0),(.14,.16,size[1]-.35),"steel",.018)


def build_boiler():
    root=start("electric_boiler",4.0,"electric_hot_water_skid")
    root["fixed_temperature_profile"]="90/60 C"
    skid("Boiler",(5.50,3.40))
    for x in [-1.12,1.12]:
        box("Saddle foot",(x,.39,.25),(.46,.20,1.64),"steel",.025)
        box("Saddle web",(x,.77,.25),(.21,.64,1.32),"dark",.03)
        for z in [-.36,.86]:
            rod("Saddle anchor",(x,.27,z),(x,.46,z),.045,"steel",8)
    lathe("Horizontal insulated electric hot-water vessel",(0,1.62,.25),
          [(-1.92,.10),(-1.85,.50),(-1.69,.77),(-1.50,.89),(1.50,.89),(1.69,.77),(1.85,.50),(1.92,.10)],horizontal=True)
    for x in [-1.25,1.25]:
        cylinder("Insulation retaining band",(x-.045,1.62,.25),(x+.045,1.62,.25),.907,"steel",28)
    for x in [-.65,.65]:
        cylinder("Top service neck",(x,2.45,.25),(x,2.62,.25),.13,"steel",16)
        flange("Bolted service cap",(x,2.64,.25),(0,1,0),.205,bolts=False)
    cylinder("Element bank collar",(-1.91,1.62,.25),(-2.05,1.62,.25),.42,"dark",20)
    flange("Electric element access flange",(-2.06,1.62,.25),(1,0,0),.47,bolts=True)
    cabinet("Electrical control cabinet",(-2.22,1.20,-.62),.73,1.91,.68)
    # The supply/return service is paired visually; only named logical ports
    # become connection endpoints in the game adapter.
    pipe("Hot-water supply",[(1.15,2.42,.25),(1.15,2.70,.25),(2.20,2.70,.25),(2.20,.65,.25),(2.20,.65,-1.85)],.13,"shell")
    flange("Supply top nozzle",(1.15,2.57,.25),(0,1,0),.21)
    cylinder("Supply ID band",(2.20,1.00,.25),(2.20,1.22,.25),.134,"hot",16)
    cylinder("Pressure gauge stem",(.15,2.49,.25),(.15,2.75,.25),.025,"steel",8)
    cylinder("Pressure gauge rim",(.15,2.77,.25),(.15,2.77,.12),.11,"steel",16)
    cylinder("Pressure gauge dial",(.15,2.77,.115),(.15,2.77,.10),.087,"shell",16)
    rod("Pressure gauge pointer",(.15,2.77,.089),(.12,2.82,.089),.012,"dark",6)
    pipe("Water return",[(1.62,1.18,.28),(1.83,1.18,.28),(1.83,.40,.28),(1.83,.40,-1.85)],.085,"shell")
    flange("Supply service flange",(2.20,.65,-1.65),radius=.22)
    flange("Return vessel nozzle",(1.76,1.18,.28),(1,0,0),.17)
    cylinder("Return ID band",(1.83,.40,-1.30),(1.83,.40,-1.50),.09,"cold",12)
    flange("Return service flange",(1.83,.40,-1.78),radius=.16,bolts=False)
    for x,y in [(2.20,.65),(1.83,.40)]:
        box("Pipe shoe",(x,.27,-1.18),(.27,.16,.30),"steel",.015)
        rod("Pipe shoe riser",(x,.34,-1.18),(x,y-.12,-1.18),.038,"steel",8)
    pipe("Electrical conduit",[(-2.22,.46,-.9),(-2.22,.36,-1.34),(-2.10,.36,-1.34),(-2.10,.65,-1.80)],.07,"dark",.1,8)
    # A bolted terminal head and cable tray identify resistance heating, not combustion.
    box("Element terminal weather hood",(-2.08,1.63,.25),(.30,1.08,1.11),"cold",.08)
    box("Element head cover",(-2.25,1.63,.25),(.035,.87,.91),"shell",.035)
    pipe("Element power trunk",[(-2.18,1.13,.25),(-2.18,.72,.25),(-2.18,.72,-.62)],.09,"dark",.13,8)
    box("Small electrical warning plate",(-2.28,1.63,.25),(.015,.22,.24),"warm",.01)
    box("Vessel specification plate",(.63,1.20,-.587),(.48,.19,.035),"steel",.012)
    for i in range(3):box("Specification rule",(.63,1.15+i*.043,-.608),(.32,.012,.01),"dark")
    port("ac_in",(-2.10,.65,-1.85),"electricity_ac","input")
    port("heat_out",(2.20,.65,-1.85),"heat_water","output","hw_primary_90_60")
    empty("Return_heat_out",(1.83,.40,-1.85),ROOT)
    empty("ProfileLabelAnchor",(0,2.95,.1),ROOT)
    return root


def build_store():
    root=start("thermal_store",5.5,"fixed_grade_two_zone_heat_store")
    root["fixed_temperature_profile"]="90/60 C"
    root["storage_approximation"]="Fixed two-zone / ideal-stratification equivalent inventory; twin silhouettes are one modeled store"
    root["soc_changes_temperature"]=False
    root["source_dimensions_m"]="Two diameter 3.5 m vessels; 6.5 m cylindrical height; 8.5 x 5 m pad"
    root["geometry_basis"]="Teaching estimate: 2 x pi x 1.75^2 x 6.5 = 125.07 m3 gross cylindrical volume"
    box("Store concrete foundation",(0,.09,0),(8.5,.18,5.0),"concrete",.045)
    for x in [-2.02,2.02]:
        cylinder("Tank anchor plinth",(x,.18,0),(x,.28,0),1.80,"dark",32)
        cylinder("Lower silver insulated jacket",(x,.28,0),(x,3.53,0),1.75,"shell",32)
        cylinder("Upper silver insulated jacket",(x,3.53,0),(x,6.78,0),1.75,"shell",32)
        cylinder("90 C supply identification band",(x,5.98,0),(x,6.10,0),1.767,"hot",32)
        cylinder("60 C return identification band",(x,.80,0),(x,.92,0),1.767,"cold",32)
        cylinder("Front inspection nozzle",(x,1.67,-1.65),(x,1.67,-1.86),.32,"steel",20)
        flange("Bolted tank manway",(x,1.67,-1.89),(0,0,1),.37)
        box("Tank specification plate",(x,2.40,-1.766),(.48,.26,.025),"steel",.01)
        lathe("Insulated dished tank head",(x,6.78,0),[(0,1.75),(.08,1.68),(.15,1.35),(.20,.75),(.21,.12)],"shell",sides=32)
        for y in [.55,2.05,3.53,5.02,6.55]:
            cylinder("Jacket retaining band",(x,y-.035,0),(x,y+.035,0),1.775,"steel",32)
        for angle in [-.85,-.30,.30,.85]:
            xx=x+1.755*math.sin(angle);zz=-1.755*math.cos(angle)
            rod("Jacket sheet vertical seam",(xx,.38,zz),(xx,6.73,zz),.013,"steel",6)
        cylinder("Inspection lid",(x,6.99,0),(x,7.08,0),.25,"steel",16)
        for z in [-1.18,1.18]:
            for sign in [-1,1]:
                cylinder("Anchor bolt",(x+sign*1.20,.22,z),(x+sign*1.20,.37,z),.04,"steel",6)
    box("Service platform",(0,6.80,2.10),(7.96,.10,.61),"steel",.015)
    for x in [-3.93,-2.02,0,2.02,3.93]:
        rod("Platform guard post",(x,6.85,2.36),(x,7.60,2.36),.035,"steel",8)
    for y in [7.19,7.60]:
        rod("Rear guardrail",(-3.93,y,2.36),(3.93,y,2.36),.035,"steel",8)
        rod("Left platform guardrail",(-3.93,y,2.36),(-3.93,y,1.83),.035,"steel",8)
    for x in [-3.88,3.88]:
        rod("Platform leg",(x,.18,2.10),(x,6.80,2.10),.055,"dark",8)
    for z in [1.83,2.36]:
        rod("Ladder side rail",(4.10,.23,z),(4.10,7.50,z),.040,"steel",8)
        for y in [.55,3.20,6.35]:
            rod("Ladder stand-off",(3.88,y,z),(4.10,y,z),.033,"steel",8)
    for i in range(23):
        y=.42+i*.285
        rod("Ladder rung",(4.10,y,1.83),(4.10,y,2.36),.030,"steel",8)
    for x in [-2.02,2.02]:
        pipe("Upper tank service branch",[(x,6.15,-1.65),(x,6.15,-1.93),(x,5.84,-1.93)],.115,"shell",.13)
        pipe("Lower return branch",[(x,.94,-1.66),(x,.94,-2.0),(x,.48,-2.0)],.09,"shell",.13)
    pipe("Fixed hot manifold",[(-3.70,.75,-2.50),(-3.70,.75,-1.93),(-3.70,5.84,-1.93),(3.70,5.84,-1.93),(3.70,.75,-1.93),(3.70,.75,-2.50)],.14,"shell")
    pipe("Fixed return manifold",[(-3.70,.47,-2.50),(-3.70,.47,-2.0),(3.70,.47,-2.0),(3.70,.47,-2.50)],.09,"shell")
    for x in [-3.70,3.70]:
        flange("Store service coupling",(x,.75,-2.28),radius=.235)
        box("Manifold pipe shoe",(x,.29,-2.04),(.40,.18,.42),"steel",.02)
        cylinder("Supply header identification",(x,1.0,-1.93),(x,1.25,-1.93),.145,"hot",12)
        rod("Riser bracket",(x,3.3,-1.93),(x,3.3,-1.55),.045,"steel",8)
        rod("Upper manifold support arm",(x,5.65,-1.93),(x,5.65,-1.55),.045,"steel",8)
        rod("Riser independent support",(x,.18,-1.55),(x,5.65,-1.55),.055,"steel",8)
    for x in [-2.02,2.02]:
        flange("Upper nozzle flange",(x,6.15,-1.82),radius=.21)
        flange("Lower nozzle flange",(x,.94,-1.84),radius=.17,bolts=False)
    for x in [-.9,.9]:
        rod("Inventory display stand",(x,.18,-2.10),(x,1.60,-2.10),.035,"steel",8)
    box("Separate inventory display plaque",(0,1.60,-2.13),(2.45,.58,.10),"dark",.035)
    box("Inventory display upper trim",(0,1.90,-2.13),(2.43,.035,.105),"steel")
    port("heat_in",(-3.70,.75,-2.50),"heat_water","input","hw_primary_90_60")
    port("heat_out",(3.70,.75,-2.50),"heat_water","output","hw_primary_90_60")
    empty("Return_heat_in",(-3.70,.47,-2.50),ROOT)
    empty("Return_heat_out",(3.70,.47,-2.50),ROOT)
    empty("ThermalSOCAnchor",(0,1.60,-2.23),ROOT)
    empty("ProfileLabelAnchor",(0,8.05,0),ROOT)
    return root


def build_exchanger():
    root=start("heat_exchanger",4.0,"isolated_plate_heat_exchanger")
    root["fixed_temperature_profile"]="90/60 -> 70/40 C"
    root["circuits_isolated"]=True
    root["nozzle_layout"]="Four connections on fixed frame plate; separate primary and secondary channels"
    skid("Heat exchanger",(5.5,3.7))
    # Real plate-and-frame topology: fixed front frame, compressed thin plate
    # pack behind, movable rear pressure plate, carrying rail and support post.
    for z in [-.55,1.05]:
        box("Frame spread foot",(0,.36,z),(2.40,.17,.42),"steel",.025)
        box("Blue end frame",(0,1.56,z),(1.95,2.36,.18),"cold",.045)
    for i in range(23):
        z=-.40+i*.059
        box("Pressed stainless plate %02d"%i,(0,1.56,z),(1.72,2.07,.029),"shell",.008)
        box("Plate gasket edge %02d"%i,(0,1.56,z+.024),(1.66,2.01,.014),"dark",.004)
    for x in [-1.08,1.08]:
        for y in [.71,2.37]:
            rod("Frame tightening bolt",(x,y,-.79),(x,y,1.28),.046,"steel",10)
            for z in [-.74,1.20]:cylinder("Bolt hex nut",(x,y,z-.04),(x,y,z+.04),.084,"dark",6)
    box("Upper carrying rail",(0,2.85,.42),(.13,.13,2.61),"steel",.015)
    box("Lower guide rail",(0,.40,.42),(.11,.11,2.61),"steel",.012)
    box("Rear support column",(0,1.56,1.61),(.14,2.45,.14),"cold",.018)
    box("Rear support foot",(0,.36,1.61),(.67,.17,.38),"steel",.015)
    for side,mat in [(-1,"hot"),(1,"warm")]:
        # Front four corner nozzles are all normal to the fixed plate.
        x=side*.61; service=side*2.15
        for y,r in [(2.17,.125),(.98,.09)]:
            cylinder("Fixed plate port collar",(x,y,-.63),(x,y,-.82),r*1.55,"steel",16)
            flange("Fixed plate bolted connection",(x,y,-.85),radius=r*1.95)
        pipe("Isolated supply "+mat,[(x,2.17,-.84),(x,2.17,-1.13),(service,2.17,-1.13),(service,.65,-1.13),(service,.65,-1.95)],.125,"shell")
        pipe("Isolated return "+mat,[(x,.98,-.84),(x,.98,-1.48),(side*1.78,.98,-1.48),(side*1.78,.40,-1.48),(side*1.78,.40,-1.95)],.09,"shell",.16)
        cylinder("Supply circuit identification band",(service,1.35,-1.13),(service,1.58,-1.13),.131,mat,12)
        cylinder("Return circuit identification band",(side*1.78,.40,-1.65),(side*1.78,.40,-1.83),.095,"cold",12)
        flange("Supply service flange",(service,.65,-1.86),radius=.22)
        flange("Return service flange",(side*1.78,.40,-1.87),radius=.16,bolts=False)
        cylinder("Isolation valve body",(service,.96,-1.13),(service,1.13,-1.13),.18,"steel",12)
        rod("Isolation valve stem",(service,1.05,-1.13),(service,1.05,-1.40),.035,"steel",8)
        torus("Isolation handwheel",(service,1.05,-1.44),.16,.025,"cold",axis=(0,0,1),segments=12)
        box("Pipe support foot",(service,.25,-1.53),(.35,.20,.44),"steel",.015)
        rod("Pipe support post",(service,.34,-1.53),(service,.51,-1.53),.04,"steel",8)
    box("Exchanger maker plate",(0,1.55,-.655),(.55,.35,.025),"steel",.012)
    for i in range(3):box("Exchanger specification rule",(0,1.47+i*.065,-.674),(.40,.018,.01),"dark")
    port("hot_in",(-2.15,.65,-1.95),"heat_water","input","hw_primary_90_60")
    port("warm_out",(2.15,.65,-1.95),"heat_water","output","hw_secondary_70_40")
    empty("Return_hot_in",(-1.78,.40,-1.95),ROOT)
    empty("Return_warm_out",(1.78,.40,-1.95),ROOT)
    empty("ProfileLabelAnchor",(0,3.20,0),ROOT)
    return root


def build_station():
    root=start("thermal_station",50.0,"compact_electric_hot_water_station_facade")
    root["station_shell_only"]=True
    root["no_internal_devices_added"]=True
    root["source_dimensions_m"]="80 x 60 m station parcel; equipment silhouettes are display-only"
    box("80 by 60 metre station boundary slab",(0,.08,0),(80,.16,60),"concrete",.10)
    # A compact service hall plus realistically scaled twin tank silhouettes;
    # the unoccupied paved yard is intentionally not filled with imaginary plant.
    box("Service hall plinth",(-12,.25,2),(26,.18,21),"dark",.055)
    box("Service hall shell",(-12,4.15,2),(25.6,7.6,20.6),"shell",.075)
    box("Insulated roof fascia",(-12,8.05,2),(26.3,.22,21.3),"cold",.045)
    box("Roof cap",(-12,8.20,2),(26.18,.09,21.18),"steel",.025)
    for x in [-23.5,-19.5,-15.5,-11.5,-7.5,-3.5]:
        box("Facade structural seam",(x,4.14,-8.33),(.065,7.36,.045),"steel")
    box("Service door recess",(-19,1.75,-8.36),(3.0,2.8,.10),"dark",.025)
    for x in [-19.73,-18.27]:
        box("Double service door",(x,1.75,-8.43),(1.40,2.70,.05),"cold",.02)
        box("Door vision panel",(x,2.30,-8.468),(.82,.49,.026),"dark",.012)
        box("Door handle",(x+(.48 if x<-19 else -.48),1.45,-8.50),(.045,.34,.07),"steel",.01)
    box("Entry canopy",(-19,3.36,-9.00),(4.1,.13,1.58),"steel",.02)
    for x in [-20.72,-17.28]:
        rod("Canopy brace",(x,2.80,-8.37),(x,3.32,-9.70),.045,"dark",8)
    box("Door landing",(-19,.25,-9.15),(4.4,.18,1.60),"dark",.04)
    box("Roll-up maintenance door frame",(-7,2.93,-8.36),(6.30,5.4,.12),"dark",.025)
    box("Roll-up maintenance door",(-7,2.93,-8.44),(6.05,5.2,.06),"cold",.02)
    for i in range(15):
        box("Maintenance door roll seam",(-7,.54+i*.34,-8.485),(5.98,.025,.025),"steel")
    box("Station sign backing",(-12,6.82,-8.38),(7.80,.84,.10),"cold",.035)
    for x in [-14,-12,-10]:
        pipe("Station heat emblem",[(x,6.55,-8.47),(x-.18,6.78,-8.47),(x+.15,7.08,-8.47)],.045,"warm",.06,6)
    cabinet("External hall controls",(-2.27,1.25,-8.57),.85,1.85,.42)
    for groupz in [-4.0,4.0]:
        for i in range(12):
            box("Hall side ventilation louver",(-24.835,1.2+i*.24,groupz),(.05,.07,2.45),"dark")
    for x in [-19,-6]:
        box("Low roof ventilation housing",(x,8.65,5),(2.4,.70,2.1),"shell",.06)
        box("Ventilation cap",(x,9.05,5),(2.60,.10,2.3),"steel",.02)
        for i in range(5):
            box("Ventilation housing louver",(x,8.40+i*.11,3.93),(2.1,.035,.035),"dark")
    for x in [6.0,10.1]:
        cylinder("Station tank foundation",(x,.16,3),(x,.28,3),1.8,"dark",32)
        cylinder("Station lower return jacket",(x,.28,3),(x,3.53,3),1.75,"shell",32)
        cylinder("Station upper supply jacket",(x,3.53,3),(x,6.78,3),1.75,"shell",32)
        lathe("Station insulated tank head",(x,6.78,3),[(0,1.75),(.08,1.68),(.15,1.35),(.20,.75),(.21,.12)],"shell",sides=32)
        for y in [.55,2.05,3.53,5.02,6.55]:
            cylinder("Station tank band",(x,y-.035,3),(x,y+.035,3),1.775,"steel",32)
        cylinder("Station tank inspection lid",(x,6.99,3),(x,7.08,3),.25,"steel",16)
    box("Tank service gantry",(8.05,6.8,5.1),(7.97,.11,.62),"steel",.02)
    for x in [4.12,6.75,9.35,11.98]:
        rod("Tank gantry guard post",(x,6.85,5.36),(x,7.60,5.36),.035,"steel",8)
    for y in [7.19,7.60]:
        rod("Tank gantry railing",(4.12,y,5.36),(11.98,y,5.36),.035,"steel",8)
    for z in [4.83,5.36]:
        rod("Station tank access ladder",(12.15,.24,z),(12.15,7.50,z),.040,"steel",8)
    for i in range(23):
        rod("Station ladder rung",(12.15,.42+i*.285,4.83),(12.15,.42+i*.285,5.36),.030,"steel",8)
    for x in [4.18,11.90]:
        rod("Gantry support",(x,.16,5.10),(x,6.8,5.10),.055,"dark",8)
    pipe("Primary tank-side hot header",[(.95,1.30,1.07),(2.3,1.30,1.07),(2.3,5.84,1.07),(13.2,5.84,1.07)],.16,"hot",.25,12)
    for x in [6.0,10.1]:
        pipe("Station hot branch",[(x,5.84,1.07),(x,5.84,1.35)],.13,"hot",.15,10)
    pipe("Primary tank-side return header",[(.95,.66,.71),(13,.66,.71)],.11,"cold",.20,10)
    for x in [6.0,10.1]:
        pipe("Station return branch",[(x,.66,.71),(x,.66,1.35)],.10,"cold",.1,10)
    # The secondary service emerges independently from the hall's exchanger.
    # Its yellow supply and blue return never join the orange tank-side loop.
    pipe("Isolated secondary export supply",[(.95,1.05,-2.2),(15,1.05,-2.2),(15,1.05,8),(38.95,1.05,8)],.16,"warm",.25,12)
    pipe("Isolated secondary export return",[(.95,.66,-2.6),(14.6,.66,-2.6),(14.6,.63,7.6),(38.85,.63,7.6)],.11,"cold",.20,10)
    rod("Primary header support",(12.9,.16,1.07),(12.9,5.68,1.07),.055,"steel",8)
    flange("Station heat boundary flange",(38.75,1.05,8),(1,0,0),.30,bolts=True)
    for x in [19,25,31,37]:
        box("Heat service pipe support",(x,.31,7.8),(.5,.3,1.05),"dark",.02)
    cabinet("Electrical entry cubicle",(-37.7,1.25,8),.95,2.08,.80)
    pipe("Electrical boundary conduit",[(-37.7,.52,8),(-38.5,.52,8),(-38.5,1.05,8),(-38.95,1.05,8)],.115,"dark",.18,10)
    box("Electrical boundary socket",(-38.91,1.05,8),(.19,.39,.39),"cold",.025)
    # Defined 80 x 60 m boundary, with a front access opening and low kerb.
    for x in [-39.60,39.60]:
        box("Side boundary kerb",(x,.26,0),(.25,.20,59.1),"shell",.02)
        for z in range(-27,28,6):
            rod("Side boundary fence post",(x,.16,z),(x,1.45,z),.045,"steel",8)
        for y in [.62,1.25]:
            rod("Side boundary fence rail",(x,y,-29.2),(x,y,29.2),.035,"steel",8)
    box("Rear boundary kerb",(0,.26,29.6),(79.2,.20,.25),"shell",.02)
    for x in range(-36,37,6):
        rod("Rear fence post",(x,.16,29.6),(x,1.45,29.6),.045,"steel",8)
    for y in [.62,1.25]:
        rod("Rear fence rail",(-39.6,y,29.6),(39.6,y,29.6),.035,"steel",8)
    for x,width in [(-24,31.2),(24,31.2)]:
        box("Front boundary kerb",(x,.26,-29.6),(width,.2,.25),"shell",.02)
        for y in [.62,1.25]:
            rod("Front fence rail",(x-width/2,y,-29.6),(x+width/2,y,-29.6),.035,"steel",8)
    for x in [-39,-32,-25,-18,-11,11,18,25,32,39]:
        rod("Front fence post",(x,.16,-29.6),(x,1.45,-29.6),.045,"steel",8)
    # Ground marks identify the service approach without decorative machinery.
    for x in [-7.7,7.7]:
        box("Entry lane marking",(x,.169,-21),(.12,.018,16.0),"warm")
    for x,z in [(-32,-20),(30,-20),(-32,21),(30,21)]:
        cylinder("Yard luminaire pole",(x,.16,z),(x,5.2,z),.055,"steel",10)
        box("Yard luminaire head",(x,5.23,z),(.55,.12,.22),"shell",.025)
    port("ac_in",(-39,1.05,8),"electricity_ac","input")
    port("heat_out",(39,1.05,8),"heat_water","output","hw_secondary_70_40")
    empty("ProfileLabelAnchor",(0,10.0,0),ROOT)
    return root


def inspect_glb(path, expected_ports, budget, expected_bounds, radius_world):
    data=path.read_bytes()
    magic,version,total=struct.unpack_from("<4sII",data)
    assert magic==b"glTF" and version==2 and total==len(data)
    size,kind=struct.unpack_from("<II",data,12)
    assert kind==0x4e4f534a
    doc=json.loads(data[20:20+size])
    assert all("uri" not in b for b in doc["buffers"]), "All data must be embedded"
    assert not doc.get("images"), "Thermal assets must not require textures"
    assert len(doc["meshes"])==1, "One merged static mesh per asset"
    assert len(doc["materials"])<=7
    triangles=0
    positions=[]
    binary_offset=20+size
    binary_size,binary_type=struct.unpack_from("<II",data,binary_offset)
    assert binary_type==0x004e4942
    binary=data[binary_offset+8:binary_offset+8+binary_size]
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            assert primitive.get("mode",4)==4
            triangles+=doc["accessors"][primitive["indices"]]["count"]//3
            accessor=doc["accessors"][primitive["attributes"]["POSITION"]]
            assert accessor["componentType"]==5126 and accessor["type"]=="VEC3"
            view=doc["bufferViews"][accessor["bufferView"]]
            offset=view.get("byteOffset",0)+accessor.get("byteOffset",0)
            stride=view.get("byteStride",12)
            positions.extend(struct.unpack_from("<3f",binary,offset+i*stride) for i in range(accessor["count"]))
    assert triangles<=budget, (path.name,triangles,budget)
    assert all(math.isfinite(v) for p in positions for v in p)
    assert min(p[1] for p in positions)>=-1e-6
    assert max(math.hypot(p[0],p[2]) for p in positions)<=radius_world+1e-6
    actual_bounds=[[min(p[i] for p in positions) for i in range(3)],
                   [max(p[i] for p in positions) for i in range(3)]]
    assert all(abs(actual_bounds[a][i]-expected_bounds[a][i])<2e-5 for a in range(2) for i in range(3))
    for node in doc["nodes"]:
        if "mesh" in node:
            assert not any(k in node for k in ["translation","rotation","scale","matrix"]), "World scale must be baked into geometry"
    node_map={n.get("name"):n for n in doc["nodes"]}
    for name,position in expected_ports.items():
        node=node_map[name]
        assert max(abs(a-b) for a,b in zip(node.get("translation",[0,0,0]),position))<1e-5,(name,node)
    return doc,triangles


def fit_reference_envelope(root, dimensions_m, clearance_radius_m):
    """Fit a stylised reference skid into the documented physical envelope.

    These are dimensional reference visuals, not manufacturer CAD replicas.
    Tank diameters/heights are authored directly and do not use this helper.
    """
    bpy.context.view_layer.update()
    meshes=[o for o in bpy.context.scene.objects if o.type=="MESH"]
    points=[godot(ob.matrix_world@v.co) for ob in meshes for v in ob.data.vertices]
    low=Vector([min(p[i] for p in points) for i in range(3)])
    high=Vector([max(p[i] for p in points) for i in range(3)])
    span=high-low
    sx,sy,sz=dimensions_m[0]/span.x,dimensions_m[2]/span.y,dimensions_m[1]/span.z
    center=(low+high)*.5;center.y=low.y
    transform=Matrix.Diagonal((sx,sz,sy,1.0)) @ Matrix.Translation(-vec(center))
    for ob in list(bpy.context.scene.objects):
        if ob!=root:
            ob.matrix_world=transform@ob.matrix_world
    root["footprint_radius"]=clearance_radius_m
    root["reference_envelope_m"]=dimensions_m
    root["dimension_profile"]="metric_v1"
    bpy.context.view_layer.update()


def export_asset(root):
    scene=bpy.context.scene
    bpy.context.view_layer.update()
    authored=[o for o in scene.objects if o.type=="MESH"]
    points=[godot(ob.matrix_world@v.co) for ob in authored for v in ob.data.vertices]
    bounds=[[round(min(p[i] for p in points),5) for i in range(3)],
            [round(max(p[i] for p in points),5) for i in range(3)]]
    radius=max(math.hypot(p.x,p.z) for p in points)
    source_radius=root["footprint_radius"]
    assert bounds[0][1]>=-.00001,(scene.name,"below ground",bounds)
    assert radius<=root["footprint_radius"],(scene.name,"outside footprint",radius)
    # Export combined duplicates, leaving the editable source parts untouched.
    bpy.ops.object.select_all(action="DESELECT")
    duplicates=[]
    for ob in authored:
        dupe=ob.copy();dupe.data=ob.data.copy();scene.collection.objects.link(dupe)
        dupe.select_set(True);duplicates.append(dupe)
    bpy.context.view_layer.objects.active=duplicates[0]
    bpy.ops.object.join()
    merged=bpy.context.object
    merged.name="ThermalAssembly"
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    merged.scale=(WORLD_UNITS_PER_METER,)*3
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    merged.parent=root
    # A joined mesh otherwise keeps duplicate slots for reused materials.
    used=[]
    old=list(merged.data.materials)
    indices=[]
    for poly in merged.data.polygons:
        mat=old[poly.material_index]
        if mat not in used:used.append(mat)
        indices.append(used.index(mat))
    merged.data.materials.clear()
    for mat in used:merged.data.materials.append(mat)
    for poly,index in zip(merged.data.polygons,indices):poly.material_index=index
    bpy.ops.object.select_all(action="DESELECT")
    merged.select_set(True);root.select_set(True)
    markers=[o for o in scene.objects if o.type=="EMPTY" and o!=root]
    marker_source_positions={o:o.location.copy() for o in markers}
    saved_names={}
    # Blender names are global across scenes, while each separate GLB needs the
    # same exact port/anchor names. Rename only for export, then restore.
    for marker in markers:
        desired=marker["asset_node_name"]
        existing=bpy.data.objects.get(desired)
        if existing is not None and existing!=marker:
            saved_names[existing]=existing.name
            existing.name="TEMP_EXPORT_CONFLICT_"+existing.name
        saved_names[marker]=marker.name
        marker.name=desired
        marker.location*=WORLD_UNITS_PER_METER
        marker.select_set(True)
    root["world_units_per_meter"]=WORLD_UNITS_PER_METER
    root["visual_dimension_profile"]="metric_v1"
    root["footprint_radius_m"]=source_radius
    root["footprint_radius"]=source_radius*WORLD_UNITS_PER_METER
    path=MODEL_DIR/(scene.name+".glb")
    bpy.ops.export_scene.gltf(filepath=str(path),export_format="GLB",use_selection=True,
                              export_yup=True,export_extras=True,export_animations=False,
                              export_cameras=False,export_lights=False)
    expected_ports={o.name:[round(v,5) for v in godot(o.location)] for o in markers if o.name.startswith("Port_")}
    world_bounds=[[round(v*WORLD_UNITS_PER_METER,7) for v in p] for p in bounds]
    doc,triangles=inspect_glb(path,expected_ports,12000 if scene.name=="thermal_station" else 8000,
                             world_bounds,root["footprint_radius"])
    dimensions=[round(bounds[1][i]-bounds[0][i],5) for i in [0,2,1]]
    anchors={o.name:[round(v,7) for v in godot(o.location)] for o in markers if not o.name.startswith("Port_")}
    MANIFEST[scene.name]={
        "glb":str(path.relative_to(PROJECT)),"source":"art_source/blender/thermal_assets.blend",
        "source_scene":scene.name,"triangles":triangles,"mesh_objects":1,
        "materials":len(doc["materials"]),"material_surfaces":len(doc["meshes"][0]["primitives"]),
        "bytes":path.stat().st_size,"bounds_godot":world_bounds,
        "bounds_m":bounds,"horizontal_radius":round(radius*WORLD_UNITS_PER_METER,7),
        "footprint_radius":root["footprint_radius"],"ports_godot":expected_ports,
        "ports":{name.removeprefix("Port_"):p for name,p in expected_ports.items()},
        "anchors_godot":anchors,"profile_anchor":anchors.get("ProfileLabelAnchor"),
        "dimensions_m":dimensions,"body_dimensions_m":dimensions,
        "world_units_per_meter":WORLD_UNITS_PER_METER,"visual_dimension_profile":"metric_v1",
        "root":root.name,"root_transform":"identity","coordinate_system":"Godot Y-up",
        "textures":0,"visual_only":True,"capacity_added":0.0,
    }
    if "ThermalSOCAnchor" in anchors:MANIFEST[scene.name]["soc_anchor"]=anchors["ThermalSOCAnchor"]
    for marker,position in marker_source_positions.items():marker.location=position
    for ob in saved_names:ob.name="RESTORE_"+ob.name
    for ob,name in saved_names.items():ob.name=name
    bpy.data.objects.remove(merged,do_unlink=True)
    print("THERMAL_ASSET",scene.name,json.dumps(MANIFEST[scene.name]))


def studio(scene):
    # These objects are source-only. Export has already completed.
    global ROOT
    root=ROOT
    ROOT=None
    collection=bpy.data.collections.new(scene.name+" studio preview only")
    scene.collection.children.link(collection)
    def studio_object(ob):
        for old in list(ob.users_collection):old.objects.unlink(ob)
        collection.objects.link(ob)
        ob["preview_only"]=True
    floor_extent=600 if scene.name=="thermal_station" else 200
    floor=box("Preview studio ground",(0,-.06,0),(floor_extent,.1,floor_extent),"concrete")
    studio_object(floor)
    specs={"electric_boiler":((0,1.25,0),6.2),"heat_exchanger":((0,.9,0),4.8),
           "thermal_store":((0,3.75,0),15.0),"thermal_station":((0,2.0,0),106.0)}
    target,scale=specs[scene.name]
    world=bpy.data.worlds.new(scene.name+" studio world");scene.world=world;world.use_nodes=True
    world.node_tree.nodes["Background"].inputs[0].default_value=(.33,.40,.48,1)
    world.node_tree.nodes["Background"].inputs[1].default_value=.45
    lighting_scale=6.5 if scene.name=="thermal_station" else (1.3 if scene.name=="thermal_store" else 1.0)
    for pos,power,size in [((7,11,-8),1600,8),((-6,6,-3),1000,7),((2,9,8),1700,6)]:
        bpy.ops.object.light_add(type="AREA",location=vec(pos)*lighting_scale)
        ob=bpy.context.object;ob.data.energy=power*lighting_scale**2
        ob.data.shape="DISK";ob.data.size=size*lighting_scale
        ob.rotation_euler=(vec(target)-ob.location).to_track_quat("-Z","Y").to_euler()
        studio_object(ob)
    bpy.ops.object.camera_add(location=vec((scale*.78,scale*.53+target[1],-scale*.98)))
    camera=bpy.context.object;camera.rotation_euler=(vec(target)-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO";camera.data.ortho_scale=scale
    studio_object(camera);scene.camera=camera
    scene.render.engine="CYCLES";scene.cycles.samples=24;scene.cycles.use_denoising=False
    scene.render.resolution_x=1000;scene.render.resolution_y=800;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format="PNG";scene.render.filepath=str(PREVIEW_DIR/(scene.name+".png"))
    scene.view_settings.view_transform="AgX"
    ROOT=root


def main():
    global M
    parser=argparse.ArgumentParser()
    parser.add_argument("--render",action="store_true")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    MODEL_DIR.mkdir(parents=True,exist_ok=True);SOURCE_DIR.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action="SELECT");bpy.ops.object.delete(use_global=False)
    for mat in list(bpy.data.materials):bpy.data.materials.remove(mat)
    M=palette()
    original_scene=bpy.context.scene
    for build in [build_boiler,build_store,build_exchanger,build_station]:
        root=build()
        if bpy.context.scene.name=="electric_boiler":
            fit_reference_envelope(root,[4.0,2.5,2.5],2.75)
        elif bpy.context.scene.name=="heat_exchanger":
            fit_reference_envelope(root,[3.0,2.0,1.8],2.25)
        export_asset(root);studio(bpy.context.scene)
    bpy.data.scenes.remove(original_scene)
    bpy.context.window.scene=SCENES[0]
    bpy.ops.object.select_all(action="DESELECT")
    source=SOURCE_DIR/"thermal_assets.blend"
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(source))
    manifest={"generator":"tools/build_thermal_assets.py","blender":bpy.app.version_string,
              "world_units_per_meter":WORLD_UNITS_PER_METER,"visual_dimension_profile":"metric_v1",
              "assets":MANIFEST,"source_bytes":source.stat().st_size}
    (MODEL_DIR/"thermal_asset_manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    if args.render:
        PREVIEW_DIR.mkdir(parents=True,exist_ok=True)
        for scene in SCENES:
            bpy.context.window.scene=scene
            bpy.ops.render.render(write_still=True)
    print("THERMAL_ASSETS_COMPLETE",source)


if __name__=="__main__":
    main()
