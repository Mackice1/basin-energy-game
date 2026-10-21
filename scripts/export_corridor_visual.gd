extends RefCounted
## Map-scale transmission-corridor illustration. Geometry only: no voltage, AC/DC,
## capacity, dispatch, collision or electrical-port changes. Not an engineering design.
## Existing route: three supports (68,3), (80,3), (94,3), continuing to map edge x=100.

const TOWER_X := [68.0, 80.0, 94.0]
const ROUTE_X := [68.0, 80.0, 94.0, 100.0]
const ROUTE_Z := 3.0
const CONDUCTOR_HEIGHT := 6.45
const CROSSARM_HEIGHT := 7.60
const SHIELD_HEIGHT := 8.75
const BUNDLE_Z := [-3.05, 0.0, 3.05]
const CLOSE_ORTHOGRAPHIC_SIZE := 65.0

class Batch:
	extends RefCounted
	var surfaces: Dictionary = {}
	var materials: Dictionary = {}
	var pieces := 0
	func _init(shared_materials: Dictionary) -> void:
		materials = shared_materials
		for key in materials:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			surfaces[key] = st
	func mesh(primitive: Mesh, transform: Transform3D, material: String) -> void:
		surfaces[material].append_from(primitive, 0, transform)
		pieces += 1
	func box(size: Vector3, at: Vector3, material: String) -> void:
		var primitive := BoxMesh.new()
		primitive.size = size
		mesh(primitive, Transform3D(Basis.IDENTITY, at), material)
	func beam(a: Vector3, b: Vector3, width: float, material: String) -> void:
		var primitive := BoxMesh.new()
		primitive.size = Vector3(width, a.distance_to(b), width)
		mesh(primitive, Transform3D(Basis(Quaternion(Vector3.UP, (b-a).normalized())), (a+b)*0.5), material)
	func tube(a: Vector3, b: Vector3, radius: float, material: String, segments := 6) -> void:
		var primitive := CylinderMesh.new()
		primitive.top_radius = radius
		primitive.bottom_radius = radius
		primitive.height = a.distance_to(b)
		primitive.radial_segments = segments
		primitive.rings = 0
		mesh(primitive, Transform3D(Basis(Quaternion(Vector3.UP, (b-a).normalized())), (a+b)*0.5), material)
	func bake(parent: Node3D) -> void:
		var triangles := 0
		for key in surfaces:
			var st: SurfaceTool = surfaces[key]
			st.set_material(materials[key])
			var result := st.commit()
			var node := MeshInstance3D.new()
			node.name = "ExportBatch_"+key
			node.mesh = result
			node.material_override = materials[key]
			# Fine wires should not cost individual shadow draws or produce far-view noise.
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(node)
			triangles += result.surface_get_array_index_len(0) / 3
		parent.set_meta("triangle_count", triangles)
		parent.set_meta("material_count", materials.size())
		parent.set_meta("component_count", pieces)
		surfaces.clear()

static func build(map: Node3D, parent: Node3D) -> Node3D:
	assert(map.has_method("height_at"), "Export corridor needs the existing map height field")
	var root := Node3D.new()
	root.name = "ExportCorridorVisual"
	root.set_meta("visual_only", true)
	root.set_meta("voltage_is_simulated", false)
	root.set_meta("representation", "schematic_lattice_export_corridor")
	root.set_meta("topology", "68,3 -> 80,3 -> 94,3 -> 100,3")
	root.set_meta("tower_count", TOWER_X.size())
	root.set_meta("geometry_assumption", "Map-scale lattice-tower illustration inspired by transmission engineering; no voltage rating, circuit type or additional network is asserted.")
	parent.add_child(root)
	var materials := _materials()
	for close in [false, true]:
		var level := Node3D.new()
		level.name = "Near" if close else "Far"
		root.add_child(level)
		var batch := Batch.new(materials)
		for x in TOWER_X:
			_tower(batch, map, x, close)
		_conductors(batch, map, close)
		batch.bake(level)
	set_detail(root, false)
	return root

static func set_detail(root: Node3D, close: bool) -> void:
	if not is_instance_valid(root):
		return
	root.get_node("Near").visible = close
	root.get_node("Far").visible = not close
	root.set_meta("close_detail", close)

static func conductor_path(map: Node3D, start_x: float, end_x: float, lateral: float, segments := 12, shield := false) -> PackedVector3Array:
	var height := SHIELD_HEIGHT if shield else CONDUCTOR_HEIGHT
	var a := Vector3(start_x, float(map.height_at(start_x, ROUTE_Z))+height, ROUTE_Z+lateral)
	var b := Vector3(end_x, float(map.height_at(end_x, ROUTE_Z))+height, ROUTE_Z+lateral)
	var sag := (end_x-start_x)*(0.032 if shield else 0.052)
	var points := PackedVector3Array()
	for i in range(segments+1):
		var t := float(i)/float(segments)
		var p := a.lerp(b, t)
		p.y -= 4.0*sag*t*(1.0-t)
		points.append(p)
	return points

static func _materials() -> Dictionary:
	var result: Dictionary = {}
	for key in {"steel":"9aa9ac", "brace":"687c80", "insulator":"a5c8c1", "concrete":"b4b0a5", "wire":"b3bfba"}:
		var material := StandardMaterial3D.new()
		material.resource_name = "ExportCorridor_"+key
		material.albedo_color = Color({"steel":"9aa9ac", "brace":"687c80", "insulator":"a5c8c1", "concrete":"b4b0a5", "wire":"b3bfba"}[key])
		material.roughness = 0.80 if key == "concrete" else 0.55
		material.metallic = 0.15 if key == "wire" else 0.45 if key in ["steel", "brace"] else 0.0
		result[key] = material
	return result

static func _tower(batch: Batch, map: Node3D, x: float, close: bool) -> void:
	var origin := Vector3(x, float(map.height_at(x, ROUTE_Z)), ROUTE_Z)
	var levels := [Vector3(0.90, 0.40, 0.98), Vector3(0.69, 1.85, 0.75), Vector3(0.48, 3.50, 0.55), Vector3(0.35, 5.15, 0.45)]
	if not close:
		# Overview needs fewer, heavier silhouette members, not subpixel peppering.
		levels = [levels[0], Vector3(0.57,2.75,0.64), levels[-1]]
	var main_width := 0.085 if close else 0.20
	var brace_width := 0.045 if close else 0.15
	# Four small individual foundations follow the existing terrain, not a new site pad.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var foot := origin+Vector3(sx*levels[0].x, 0, sz*levels[0].z)
			foot.y = float(map.height_at(foot.x, foot.z))
			batch.box(Vector3(0.48,0.25,0.48), foot+Vector3(0,0.105,0), "concrete")
			batch.box(Vector3(0.23,0.065,0.23), foot+Vector3(0,0.25,0), "steel")
			batch.beam(foot+Vector3(0,0.25,0), origin+Vector3(sx*levels[0].x,levels[0].y,sz*levels[0].z), main_width, "steel")
	# Tapered four-leg trunk with open triangular bays, not a solid pole.
	for index in range(levels.size()-1):
		var low: Vector3 = levels[index]
		var high: Vector3 = levels[index+1]
		for sx in [-1.0,1.0]:
			for sz in [-1.0,1.0]:
				batch.beam(origin+Vector3(sx*low.x,low.y,sz*low.z),origin+Vector3(sx*high.x,high.y,sz*high.z),main_width,"steel")
		for side in [-1.0,1.0]:
			var face_a := origin+Vector3(-low.x,low.y,side*low.z)
			var face_b := origin+Vector3(high.x,high.y,side*high.z)
			var face_c := origin+Vector3(low.x,low.y,side*low.z)
			var face_d := origin+Vector3(-high.x,high.y,side*high.z)
			batch.beam(face_a,face_b,brace_width,"brace")
			if close: batch.beam(face_c,face_d,brace_width,"brace")
			batch.beam(face_b,face_d,brace_width,"steel")
			face_a = origin+Vector3(side*low.x,low.y,-low.z)
			face_b = origin+Vector3(side*high.x,high.y,high.z)
			face_c = origin+Vector3(side*low.x,low.y,low.z)
			face_d = origin+Vector3(side*high.x,high.y,-high.z)
			batch.beam(face_a,face_b,brace_width,"brace")
			if close: batch.beam(face_c,face_d,brace_width,"brace")
			batch.beam(face_b,face_d,brace_width,"steel")
	# Open cat-head frame leaves room for the middle conductor; crossarm is across
	# the route (Z), not pointing along the route (X). No wire passes through steel.
	for sx in [-1.0,1.0]:
		for sz in [-1.0,1.0]:
			var waist := origin+Vector3(sx*0.35,5.15,sz*0.45)
			var shoulder := origin+Vector3(sx*0.30,CROSSARM_HEIGHT,sz*1.14)
			var tip := origin+Vector3(sx*0.22,CROSSARM_HEIGHT,sz*3.25)
			batch.beam(waist,shoulder,main_width,"steel")
			batch.beam(waist,tip,brace_width,"brace")
			batch.beam(shoulder,origin+Vector3(0,SHIELD_HEIGHT,sz*1.14),main_width,"steel")
			if close:
				batch.beam(origin+Vector3(sx*0.30,6.85,sz*0.95),tip,brace_width,"brace")
		batch.beam(origin+Vector3(sx*0.22,CROSSARM_HEIGHT,-3.25),origin+Vector3(sx*0.22,CROSSARM_HEIGHT,3.25),main_width,"steel")
		batch.beam(origin+Vector3(sx*0.22,CROSSARM_HEIGHT+0.34,-3.0),origin+Vector3(sx*0.22,CROSSARM_HEIGHT+0.34,3.0),brace_width,"steel")
		var cells := 8 if close else 4
		var step := 6.0/float(cells)
		for cell in cells:
			var z0 := -3.0+cell*step
			batch.beam(origin+Vector3(sx*0.22,CROSSARM_HEIGHT,z0),origin+Vector3(sx*0.22,CROSSARM_HEIGHT+0.34,z0+step),brace_width,"brace")
	for z in [-3.05,-1.14,0.0,1.14,3.05]:
		batch.beam(origin+Vector3(-0.22,CROSSARM_HEIGHT,z),origin+Vector3(0.22,CROSSARM_HEIGHT,z),main_width,"steel")
	for z in BUNDLE_Z:
		_insulator(batch,origin+Vector3(0,CROSSARM_HEIGHT,z),close)
	if close:
		# A restrained access ladder and marker plate read only at close map zoom.
		for sx in [-0.12,0.12]:
			batch.beam(origin+Vector3(sx,0.65,-0.88),origin+Vector3(sx,4.85,-0.51),0.025,"brace")
		for rung in 16:
			var t := rung/15.0
			batch.beam(origin+Vector3(-0.12,lerpf(0.65,4.85,t),lerpf(-0.88,-0.51,t)),origin+Vector3(0.12,lerpf(0.65,4.85,t),lerpf(-0.88,-0.51,t)),0.024,"steel")
		batch.box(Vector3(0.23,0.27,0.025),origin+Vector3(0,2.05,-0.75),"steel")

static func _insulator(batch: Batch, top: Vector3, close: bool) -> void:
	var end := top-Vector3(0,CROSSARM_HEIGHT-CONDUCTOR_HEIGHT,0)
	batch.tube(top,end,0.037 if close else 0.07,"brace",6)
	if close:
		for shed in 10:
			var p := top-Vector3(0,0.16+shed*0.083,0)
			batch.tube(p-Vector3(0,0.025,0),p+Vector3(0,0.025,0),0.115,"insulator",8)
		batch.box(Vector3(0.27,0.06,0.25),end,"steel")
		# A small low-poly grading-ring cue, not an asserted voltage-specific fitting.
		for side in 8:
			var a := TAU*side/8.0
			var b := TAU*(side+1)/8.0
			batch.beam(end+Vector3(cos(a)*0.18,0.08,sin(a)*0.18),end+Vector3(cos(b)*0.18,0.08,sin(b)*0.18),0.024,"steel")
	else:
		batch.tube(top-Vector3(0,0.12,0),end+Vector3(0,0.12,0),0.10,"insulator",6)

static func _conductors(batch: Batch, map: Node3D, close: bool) -> void:
	var segments := 12 if close else 7
	for span in range(ROUTE_X.size()-1):
		for lateral in BUNDLE_Z:
			var path := conductor_path(map,ROUTE_X[span],ROUTE_X[span+1],lateral,segments)
			if close:
				# Four close strands and periodic square spacers suggest a conductor bundle.
				for dy in [-0.075,0.075]:
					for dz in [-0.075,0.075]:
						# Map-scale minimum readable thickness, not a real conductor diameter.
						_path(batch,path,Vector3(0,dy,dz),0.040,4)
				for fraction in [0.25,0.5,0.75]:
					var p: Vector3 = path[int(fraction*segments)]
					batch.beam(p+Vector3(0,-0.075,-0.075),p+Vector3(0,0.075,-0.075),0.022,"steel")
					batch.beam(p+Vector3(0,-0.075,0.075),p+Vector3(0,0.075,0.075),0.022,"steel")
					batch.beam(p+Vector3(0,-0.075,-0.075),p+Vector3(0,-0.075,0.075),0.022,"steel")
					batch.beam(p+Vector3(0,0.075,-0.075),p+Vector3(0,0.075,0.075),0.022,"steel")
			else:
				_path(batch,path,Vector3.ZERO,0.140,4)
		for lateral in [-1.14,1.14]:
			_path(batch,conductor_path(map,ROUTE_X[span],ROUTE_X[span+1],lateral,segments,true),Vector3.ZERO,0.040 if close else 0.100,4)

static func _path(batch: Batch, points: PackedVector3Array, offset: Vector3, radius: float, segments: int) -> void:
	for index in range(points.size()-1):
		batch.tube(points[index]+offset,points[index+1]+offset,radius,"wire",segments)
