extends RefCounted
## Visual-only fallback shares the exact metre-scale parts with Blender.
## No ports, capacity, tracking, dimensions or engineering parameters are changed.
static func build(tower: Node3D) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/csp_tower_parts.json"))
	var materials: Dictionary = {}
	for key in data.materials:
		var spec: Dictionary = data.materials[key]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(spec.color[0], spec.color[1], spec.color[2])
		mat.metallic = spec.metallic
		mat.roughness = spec.roughness
		materials[key] = mat
	for part in data.parts:
		var instance := MeshInstance3D.new()
		instance.name = part.name
		if part.type == "box":
			var mesh := BoxMesh.new()
			mesh.size = _vector(part.size) * .1
			instance.mesh = mesh
			instance.position = _vector(part.pos) * .1
		else:
			var a := _vector(part.a)
			var b := _vector(part.b)
			var mesh := CylinderMesh.new()
			mesh.bottom_radius = float(part.radius) * .1
			mesh.top_radius = float(part.top_radius) * .1
			mesh.height = a.distance_to(b) * .1
			mesh.radial_segments = int(part.segments)
			mesh.rings = 1
			instance.mesh = mesh
			instance.position = (a + b) * .05
			instance.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
		instance.material_override = materials[part.material]
		tower.add_child(instance)
	tower.set_meta("reference_project", "Dunhuang 100MW visual reference; adapted 25m teaching envelope, not engineering replica")
static func _vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
