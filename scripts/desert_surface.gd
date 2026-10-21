extends RefCounted
# Decorative meshes only. No collision, terrain deformation, or gameplay state.
# Low-poly, embedded silhouettes replace the uniformly round gravel and shrubs.

static func matte_vertex_material() -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.vertex_color_use_as_albedo = true
	result.roughness = 1.0
	result.metallic_specular = 0.15
	return result

static func triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color):
	for point in [a, c, b]:
		# A restrained darker base grounds small objects without dynamic shadows.
		surface.set_color(tint.darkened(clampf((0.16 - point.y) * 0.45, 0.0, 0.15)))
		surface.add_vertex(point)

static func rock_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lower: Array[Vector3] = []
	var shoulder: Array[Vector3] = []
	var radii := [0.53, 0.45, 0.56, 0.49, 0.57, 0.43, 0.50]
	var heights := [0.23, 0.28, 0.20, 0.30, 0.26, 0.19, 0.25]
	for i in range(7):
		var angle := float(i) * TAU / 7.0
		var radius: float = radii[i]
		lower.append(Vector3(cos(angle) * radius, -0.14, sin(angle) * radius))
		shoulder.append(Vector3(cos(angle) * radius * 0.83 + 0.04, heights[i], sin(angle) * radius * 0.82))
	var crest := Vector3(-0.09, 0.46, 0.06)
	for i in range(7):
		var j := (i + 1) % 7
		var side := Color.WHITE.darkened(0.05 + float(i % 3) * 0.025)
		triangle(surface, lower[i], shoulder[i], lower[j], side)
		triangle(surface, lower[j], shoulder[i], shoulder[j], side)
		triangle(surface, shoulder[i], crest, shoulder[j], Color.WHITE)
	surface.generate_normals()
	var mesh := surface.commit()
	mesh.surface_set_material(0, matte_vertex_material())
	return mesh

static func shrub_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Three unequal, low crowns read as a wind-shaped shrub rather than a topiary ball.
	var centers := [Vector3(-0.19, 0.0, -0.04), Vector3(0.18, 0.0, -0.08), Vector3(0.01, 0.0, 0.19)]
	var radii := [0.29, 0.25, 0.24]
	var heights := [0.36, 0.28, 0.23]
	for lobe in range(3):
		var center: Vector3 = centers[lobe]
		var radius: float = radii[lobe]
		var height: float = heights[lobe]
		var lower: Array[Vector3] = []
		var shoulder: Array[Vector3] = []
		for i in range(6):
			var angle := float(i) * TAU / 6.0 + float(lobe) * 0.6
			var uneven := 0.84 + float((i + lobe) % 3) * 0.09
			var offset := Vector3(cos(angle) * radius * uneven, 0.0, sin(angle) * radius)
			lower.append(center + offset + Vector3(0.0, -0.06, 0.0))
			shoulder.append(center + offset * 0.74 + Vector3(0.0, height * 0.7, 0.0))
		var crest := center + Vector3(0.035, height, -0.025)
		for i in range(6):
			var j := (i + 1) % 6
			var side := Color.WHITE.darkened(0.05 + float((i + lobe) % 3) * 0.035)
			triangle(surface, lower[i], shoulder[i], lower[j], side)
			triangle(surface, lower[j], shoulder[i], shoulder[j], side)
			triangle(surface, shoulder[i], crest, shoulder[j], Color.WHITE.darkened(float(lobe) * 0.025))
	surface.generate_normals()
	var mesh := surface.commit()
	mesh.surface_set_material(0, matte_vertex_material())
	return mesh

static func macro_texture(seed_value: int) -> NoiseTexture2D:
	var field := FastNoiseLite.new()
	field.seed = seed_value + 197
	field.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	field.frequency = 0.027
	field.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.generate_mipmaps = true
	texture.noise = field
	return texture
