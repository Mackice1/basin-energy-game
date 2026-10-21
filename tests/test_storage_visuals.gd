extends SceneTree
## Demand-marker/battery geometry, authored-material, footprint, and icon checks.
const Visual = preload("res://scripts/equipment_visual.gd")
var checks := 0
var failures: Array[String] = []

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var icons: Dictionary = {}
	for kind in ["load", "battery"]:
		var params := {"demand_mw": 2.0, "priority": 10} if kind == "load" else {"capacity_mwh": 10.0, "initial_soc": 0.5}
		var original := params.duplicate(true)
		var item = Visual.create(kind, params)
		root.add_child(item)
		check(item.device_kind == kind, kind + ": canonical type is retained")
		check(not item.has_node("Placeholder"), kind + ": uses an independent authored model")
		check(item.has_node("ElectricityPort"), kind + ": has a single accessible electrical terminal")
		check(item.port.get_meta("port_type") == "electricity", kind + ": terminal is typed")
		check(item.rotor == null, kind + ": no reused generator rotor")
		check(item.get_meta("visual_only") and item.get_meta("capacity_added") == 0.0, kind + ": display adds no power or energy")
		check(params == original, kind + ": visual creation never changes parameters")
		var min_surfaces := 12 if kind == "load" else 30
		var max_surfaces := 30 if kind == "load" else 100
		check(item.surfaces.size() > min_surfaces and item.surfaces.size() < max_surfaces, kind + ": readable bounded-complexity silhouette")
		check(item.surfaces.size() == item.base_materials.size(), kind + ": all surfaces have restorable materials")
		check(not str(item.get_meta("geometry_assumption")).is_empty(), kind + ": fixed scale is explicitly documented")
		if kind == "load":
			for part in ["DemandBasePlate", "DemandBaseRing", "DemandPole", "DemandArrowStem", "DemandArrowHead", "DemandMeterPanel", "DemandTerminalBollard"]:
				check(item.has_node(part), "demand marker includes " + part)
			for part in ["FactoryHall", "FactoryBase", "SawtoothRoof0", "VentilationStack", "LoadingBay", "OfficeAnnex"]:
				check(not item.has_node(part), "demand marker has no industrial building part: " + part)
			check(item.get_meta("representation") == "demand_connection_marker", "load identifies a demand connection, not a factory")
			check(not item.get_meta("is_factory") and item.get_meta("demand_added") == 0.0, "marker explicitly adds no factory or new demand")
			check(Visual.footprint(kind) == 5.5 and item.get_meta("footprint_radius") == 5.5, "load retains legacy footprint for saved scenes")
			check(item.port_local.is_equal_approx(Vector3(0.95, 0.52, -2.39)), "load retains legacy cable endpoint")
			var arrow: CylinderMesh = item.get_node("DemandArrowHead").mesh
			check(arrow.bottom_radius == 0.0 and arrow.top_radius > 0.0, "demand arrow points down into the node")
			var terminal_body: MeshInstance3D = item.get_node("DemandTerminalBollard")
			var front_z: float = terminal_body.position.z + terminal_body.mesh.get_aabb().position.z
			check(item.port_local.z + 0.13 < front_z, "legacy terminal remains exposed in front of bollard")
			var materials: Array[Material] = []
			for material in item.base_materials:
				if not materials.has(material):
					materials.append(material)
			check(materials.size() >= 5, "demand marker retains distinct authored materials")
		else:
			for part in ["BatteryContainer", "BatteryEmblem", "ServiceDoor0", "ServiceDoor1", "CoolingUnit", "CoolingLouver7", "BatteryController"]:
				check(item.has_node(part), "battery includes " + part)
			check(item.get_meta("representation") == "container_battery", "battery has its own role metadata")
			check(item.get_meta("soc_emblem_is_static"), "battery symbol does not claim to display live SOC")
		for mesh in item.surfaces:
			if mesh == item.selection_ring:
				continue
			var bounds: AABB = mesh.mesh.get_aabb()
			for corner in 8:
				var point: Vector3 = mesh.global_transform * bounds.get_endpoint(corner)
				check(point.y >= -0.00001, kind + ": geometry stays above ground")
				check(Vector2(point.x, point.z).length() <= Visual.footprint(kind), kind + ": geometry fits declared footprint")
				if kind == "load":
					check(Vector2(point.x, point.z).length() <= 2.9 and point.y <= 3.0, "demand marker stays compact despite legacy footprint")
		item.set_highlight(true)
		check(item.selection_ring.visible, kind + ": selection is visible")
		for valid in [true, false]:
			item.set_preview(valid)
			for mesh in item.surfaces:
				check(mesh.material_override == (item.preview_good if valid else item.preview_bad), kind + ": preview covers every surface")
			check(not item.selection_ring.visible, kind + ": preview suppresses selection ring")
		item.clear_preview()
		for index in item.surfaces.size():
			check(item.surfaces[index].material_override == item.base_materials[index], kind + ": original material restored")
		check(item.selection_ring.visible, kind + ": selection restored after preview")
		item.set_operating(2.0)
		item._process(0.5)
		item.position = Vector3(2.0, 5.0, -3.0)
		item.rotation.y = 0.5
		check(item.port_global().is_equal_approx(item.to_global(item.port_local)), kind + ": terminal follows placement and rotation")
		item.free()
		var icon := Image.new()
		var svg := FileAccess.get_file_as_string("res://assets/icon_%s.svg" % kind)
		check(icon.load_svg_from_string(svg) == OK, kind + ": SVG parses")
		check(icon.get_width() == 64 and icon.get_height() == 64, kind + ": icon matches toolbar canvas")
		check(svg.contains("#386155") and svg.contains('stroke-width="2"'), kind + ": existing toolbar stroke style retained")
		var opaque_pixels := 0
		for x in icon.get_width():
			for y in icon.get_height():
				if icon.get_pixel(x, y).a > 0.1:
					opaque_pixels += 1
		check(opaque_pixels > 250 and opaque_pixels < 2500, kind + ": icon contains visible transparent-background line art")
		icons[kind] = icon.get_data()
	check(icons.load != icons.battery, "load and battery use distinct toolbar silhouettes")
	for alias in ["consumer", "industrial_load", "storage", "battery_storage"]:
		var item = Visual.create(alias)
		check(item.device_kind == ("load" if alias in ["consumer", "industrial_load"] else "battery"), "visual alias resolves: " + alias)
		item.free()
	print("STORAGE_VISUALS_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
