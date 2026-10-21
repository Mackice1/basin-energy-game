extends SceneTree
## Fuel boiler: physically authored module, real GLB, exact two-port contract.
## This intentionally does not test or change dispatch policy.
const Visual = preload("res://scripts/equipment_visual.gd")
const Spatial = preload("res://scripts/spatial_dimensions.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
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
	_test_dimensions()
	_test_import_contract()
	_test_visuals()
	_test_legacy_dimensions()
	print("FUEL_VISUAL_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _params(rated: float = 2.0) -> Dictionary:
	var params: Dictionary = Catalog.defaults("fuel_boiler")
	params.rated_fuel_mw = rated
	params.visual_dimension_profile = "metric_v1"
	return params

func _test_dimensions() -> void:
	var p := _params()
	var original := p.duplicate(true)
	var dimensions: Dictionary = Spatial.profile("fuel_boiler", p)
	check(dimensions.valid, "default fuel dimensions are supported")
	check(p == original, "spatial query never mutates fuel parameters")
	check(dimensions.module_count == 1, "2 MW_LHV uses one visual module")
	check(dimensions.unit_dimensions_m == Vector3(5, 4.5, 3), "fixed module metre dimensions are x/height/z")
	check(dimensions.reference_boiler_body_dimensions_m == Vector3(3.48, 1.73, 1.51), "source boiler casing is separate from entire skid")
	check(dimensions.fuel_energy_basis == "LHV", "geometry module rating keeps fuel input basis")
	check(dimensions.body_area_m2 == 15.0, "physical footprint is 15 square metres")
	check(dimensions.land_dimensions_m == Vector3(9, 0, 7) and dimensions.land_area_m2 == 63, "2 m teaching margin gives 9 by 7 m installation rectangle")
	check(is_equal_approx(dimensions.clearance_radius_world, sqrt(130.0) * 0.05), "conservative collision circle uses unchanged .1 world per metre")
	check(dimensions.clearance_radius_world < Spatial.STATION_INTERIOR_HALF_WORLD, "default unit fits existing 48 m station without shrinking")
	check(dimensions.source_note.contains("Bosch") and dimensions.source_note.contains("教学"), "source and assumption are surfaced")
	for value in [0.01, 1.99, 2.0, 2.01, 4.0, 4.01, 20.0]:
		# Above-default expansion is the preserved historical teaching layout.
		# The default/derated cases keep explicit new-reference coverage.
		var site_profile := "" if value > 2.0 else "reference_size_v1"
		var d: Dictionary = Spatial.profile("fuel_boiler", _params(value), true, "flow_process_v2", site_profile)
		if value > 2.0:
			check(not Spatial.profile("fuel_boiler", _params(value), false, "flow_process_v2", "reference_size_v1").valid, "new reference rejects unsupported fuel expansion %.2f" % value)
		check(d.valid and d.module_count == int(ceil(value / 2.0)), "fuel input determines integer module count %.2f" % value)
		check(d.unit_dimensions_m == dimensions.unit_dimensions_m, "unit never shrinks or stretches %.2f" % value)
		check(d.module_origins_m.size() == d.module_count, "all default-sized origins are explicit")
		for index in int(d.module_count):
			check(d.module_origins_world[index].is_equal_approx(Spatial.module_origin_m(d, index) * 0.1), "module origin is converted exactly once")
		var cheap: Dictionary = Spatial.profile("fuel_boiler", _params(value), false, "flow_process_v2", site_profile)
		check(cheap.module_count == d.module_count and cheap.land_dimensions_m == d.land_dimensions_m and cheap.clearance_radius_world == d.clearance_radius_world, "cheap placement query retains actual full envelope")
		check(cheap.module_origins_world.is_empty(), "cheap query omits allocation only")
	for invalid in [0.0, -1.0, INF, NAN, "2"]:
		check(not Spatial.profile("fuel_boiler", {"rated_fuel_mw": invalid}).valid, "invalid fuel rating rejected before geometry")
	p.thermal_efficiency = 0.8
	p.auxiliary_electric_ratio = 0.02
	check(Spatial.profile("fuel_boiler", p).unit_dimensions_m == dimensions.unit_dimensions_m, "efficiency and aux settings do not scale equipment")
	var huge: Dictionary = Spatial.profile("fuel_boiler", _params(100), false, "flow_process_v2", "")
	check(huge.clearance_radius_world > Spatial.STATION_INTERIOR_HALF_WORLD, "large capacity exceeds site instead of silently shrinking")

func _test_import_contract() -> void:
	var path: String = Visual.BLENDER_ASSETS.fuel_boiler
	check(FileAccess.file_exists(path), "fuel GLB exists")
	check(ResourceLoader.exists(path, "PackedScene"), "fuel GLB has a usable Godot import")
	var file := FileAccess.open(path, FileAccess.READ)
	check(file.get_buffer(4).get_string_from_ascii() == "glTF", "asset is a genuine binary glTF")
	var definition: Dictionary = Visual.thermal_asset_definition("fuel_boiler")
	check(definition.get("source") == "art_source/blender/fuel_boiler.blend", "fuel editable source stays independent of old assets")
	check(definition.get("triangles", 99999) <= 8000 and definition.get("material_surfaces", 99) <= 7, "recorded per-module mesh budget is bounded")
	check(definition.get("recognition_features", []).size() == 5, "original burner/gas/flue/water features documented")
	check(definition.ports.size() == 2 and definition.ports.has("ac_in") and definition.ports.has("heat_out"), "only auxiliary AC and primary hot-water endpoints")
	check(definition.dimensions_m == [5.0, 3.0, 4.5], "manifest physical dimensions agree with direct authored bounds")
	var packed: PackedScene = load(path)
	var asset := packed.instantiate() as Node3D
	check(asset.transform.is_equal_approx(Transform3D.IDENTITY), "GLB root is unit-scale Y-up")
	check(asset.find_children("*", "CollisionObject3D", true, false).is_empty(), "GLB has no hidden physics simulation")
	check(asset.find_children("*", "Label3D", true, false).is_empty(), "GLB has no baked UI state")
	asset.free()

func _bounds(item: Node3D) -> AABB:
	var result := AABB()
	var seen := false
	for instance: MeshInstance3D in item.surfaces:
		if instance == item.selection_ring:
			continue
		var local: Transform3D = Visual._relative_transform(instance, item)
		var bounds: AABB = local * instance.mesh.get_aabb()
		result = result.merge(bounds) if seen else bounds
		seen = true
	return result

func _test_visuals() -> void:
	var p := _params()
	var original := p.duplicate(true)
	var definition: Dictionary = Visual.thermal_asset_definition("fuel_boiler")
	var item = Visual.create("fuel_boiler", p, true)
	root.add_child(item)
	check(item.get_meta("visual_backend") == "blender_glb", "fuel uses actual imported Blender mesh")
	check(item.get_meta("module_count") == 1 and item.surfaces.size() == 2, "single static assembly plus selection ring")
	check(item.get_meta("capacity_added") == 0.0 and item.get_meta("visual_only"), "visual adds no fuel or heat capacity")
	check(item.get_meta("fuel_type") == "natural_gas" and item.get_meta("fuel_energy_basis") == "LHV", "visual metadata never implies generalized fuels")
	check(item.get_meta("thermal_boundary").contains("分别计量") and item.get_meta("thermal_boundary").contains("不产蒸汽"), "auxiliary electric and hot-water-only boundary is explicit")
	check(item.rotor == null, "boiler creates no turbine rotor")
	check(item.named_ports.size() == 2 and not item.has_named_port("fuel_in") and not item.has_named_port("steam_out") and not item.has_named_port("ac_out"), "no invented gas-network or steam/electric output ports")
	for port_id in ["ac_in", "heat_out"]:
		var port: Node3D = item.named_ports[port_id]
		check(port.global_position.is_equal_approx(Visual._vector3(definition.ports[port_id])), "authored endpoint survives axis conversion " + port_id)
		check(item.get_named_port_position(port_id).is_equal_approx(port.global_position), "picking matches rendered marker " + port_id)
		var contract: Dictionary = Catalog.port("fuel_boiler", port_id)
		for key in ["direction", "carrier", "unit"]:
			check(port.get_meta(key) == contract[key], "port metadata matches catalog " + port_id + "/" + key)
	check(item.named_ports.heat_out.get_meta("grade_id") == "hw_primary_90_60", "hot water joins only primary fixed grade")
	check(item.named_ports.ac_in.get_meta("voltage_level") == "AC_BUS", "auxiliary electricity uses existing AC bus")
	var bounds := _bounds(item)
	check(bounds.position.is_equal_approx(Vector3(-.25, 0, -.15)) and bounds.size.is_equal_approx(Vector3(.5, .45, .3)), "actual GLB has exact metre-derived footprint and stack height")
	var mesh := item.surfaces[0] as MeshInstance3D
	check(mesh.mesh.get_surface_count() == 7 and mesh.material_override == null, "authored seven-material look survives import")
	var saved_mesh: Mesh = mesh.mesh
	var transforms: Transform3D = mesh.transform
	var sibling = Visual.create("fuel_boiler", p, true)
	root.add_child(sibling)
	for valid in [true, false, true]:
		item.set_preview(valid)
		check(mesh.material_override == (item.preview_good if valid else item.preview_bad), "preview tints all material surfaces")
		check(sibling.surfaces[0].material_override == null, "preview never leaks into sibling mesh materials")
	item.clear_preview()
	check(mesh.mesh == saved_mesh and mesh.transform == transforms and mesh.material_override == null, "preview restores materials without changing geometry")
	item.set_highlight(true)
	check(item.selection_ring.visible, "selection ring is available")
	item.set_highlight(false)
	check(not item.selection_ring.visible, "selection clears correctly")
	item.set_annotation_visibility(true, true)
	check(item.named_ports.ac_in.get_node("PortLabel").visible, "auxiliary port label is discoverable")
	item.set_annotation_visibility(false)
	check(not item.named_ports.ac_in.get_node("PortLabel").visible, "labels support station decluttering")
	var fallback = Visual.create("fuel_boiler", p, false)
	root.add_child(fallback)
	check(fallback.get_meta("visual_backend") == "metric_procedural_fallback", "procedural fallback stays supported")
	check(_bounds(fallback).size.is_equal_approx(Vector3(.5, .45, .3)), "fallback also uses direct .1 metre conversion without envelope fitting")
	check(fallback.find_child("ForcedDraftBurner", true, false) != null and fallback.find_child("FlueStack", true, false) != null, "fallback retains independent burner and flue silhouette")
	check(fallback.get_meta("thermal_boundary") == item.get_meta("thermal_boundary") and fallback.get_meta("fuel_energy_basis") == "LHV", "fallback preserves fuel/aux semantics")
	for port_id in ["ac_in", "heat_out"]:
		check(fallback.get_named_port_position(port_id).is_equal_approx(fallback.named_ports[port_id].global_position), "fallback scaling preserves picking endpoint")
	var legacy_expanded := _params(2.01)
	legacy_expanded.visual_site_geometry_profile = ""
	var doubled = Visual.create("fuel_boiler", legacy_expanded, true)
	root.add_child(doubled)
	check(doubled.get_meta("module_count") == 2 and doubled.get_node("BlenderAsset").get_child_count() == 2, "capacity threshold adds full identical module")
	check(doubled.named_ports.size() == 2 and doubled.get_meta("modules_share_simulation_limits"), "two visual modules share one endpoint pair and simulation limits")
	for module: Node3D in doubled.get_node("BlenderAsset").get_children():
		check(module.scale == Vector3.ONE, "added modules retain exact authored world scale")
	check(_bounds(doubled).size.is_equal_approx(Vector3(1.2, .45, .3)), "second module expands footprint rather than squeezing")
	check(p == original, "asset creation, preview, labels and replication do not mutate model inputs")
	doubled.free(); fallback.free(); sibling.free(); item.free()

func _test_legacy_dimensions() -> void:
	check(Spatial.profile("electric_boiler",{},true,"flow_process_v2","").unit_dimensions_m == Vector3(4, 2.5, 2.5), "existing electric boiler stays unchanged")
	check(Spatial.profile("thermal_store",{},true,"flow_process_v2","").unit_dimensions_m == Vector3(8.5, 7.635, 5), "existing heat store stays unchanged")
	check(Spatial.profile("heat_exchanger",{},true,"flow_process_v2","").unit_dimensions_m == Vector3(3, 1.8, 2), "existing exchanger stays unchanged")
	check(Spatial.profile("thermal_station",{},true,"flow_process_v2","").interior_dimensions_m == Vector3(48, 0, 48), "station interior remains 48 m")
	check(Visual.footprint("electric_boiler",{"visual_site_geometry_profile":""}) == 4 and Visual.footprint("thermal_store",{"visual_site_geometry_profile":""}) == 5, "legacy saved thermal collision radii unchanged")
