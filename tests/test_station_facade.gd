extends SceneTree
## Procedural fallback contract; imported backend is tested by test_thermal_glb_visuals.
## Run: godot --headless --path . --script tests/test_station_facade.gd

const Facade = preload("res://scripts/station_facade.gd")
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
	var station = Facade.new()
	var station_data := {"id": 100, "name": "北区电热储能站", "devices": [{"kind": "thermal_store", "stored_mwhth": 123.0}]}
	var original := station_data.duplicate(true)
	station.setup(station_data, false)
	root.add_child(station)
	check(station_data == original, "setup leaves authoritative station data untouched")
	check(station.title_label.text == "北区电热储能站", "station title uses supplied name")
	check(is_equal_approx(station.title_label.position.y, 6.5), "title floats above whole facility")
	check(station.title_label.font != null and not station.title_label.no_depth_test and station.title_label.fixed_size, "CJK title is screen-bounded and respects geometry occlusion")
	check(station.has_node("PlantBuilding") and station.has_node("Courtyard") and station.has_node("FenceBack"), "single whole-site building, courtyard and fence")
	check(station.has_node("TankSilhouette1") and station.has_node("TankSilhouette2"), "simplified tanks belong to facade silhouette")
	check(station.surfaces.size() > 30 and station.surfaces.size() < 100, "whole facility has bounded lightweight mesh count")
	check(station.base_materials.size() == station.surfaces.size(), "all authored surface materials can be restored")
	check(station.get_meta_list().is_empty(), "facade has no energy capacity or state metadata")
	check(not station.is_processing() and not station.is_physics_processing(), "facade does not run simulation")
	check(station.get("devices") == null and station.get("stored_mwhth") == null, "facade does not retain devices or storage inventory")
	check(is_equal_approx(Facade.FOOTPRINT_RADIUS, 8.0), "whole facility has the agreed radius-eight footprint")
	for surface in station.surfaces:
		check(surface is MeshInstance3D and surface.mesh != null, "picking surface is real geometry")
		if surface == station.selection_ring:
			continue
		for corner in 8:
			var point: Vector3 = surface.global_transform * surface.mesh.get_aabb().get_endpoint(corner)
			check(point.y >= -0.00001, "physical facade geometry stays above ground")
			check(Vector2(point.x, point.z).length() <= Facade.FOOTPRINT_RADIUS, "physical facade geometry fits siting radius")
	check(station.has_named_port("ac_in") and station.has_named_port("heat_out"), "exact external AC input and 70/40 output names exist")
	check(not station.has_named_port("hot_in") and not station.has_named_port("missing"), "internal or unknown ports are not advertised")
	check(station.named_ports.size() == 2, "facade exposes only its two external carriers")
	check(station.named_ports.ac_in.has_node("ACSquare"), "AC endpoint uses square glyph")
	check(station.named_ports.heat_out.has_node("HeatOuterFlange"), "heat endpoint uses round flange glyph")
	check(station.named_ports.ac_in.get_node("PortLabel").text == "AC 输入", "AC direction is labeled")
	check(station.named_ports.heat_out.get_node("PortLabel").text == "热70/40 输出", "secondary heat grade and direction are labeled")
	check(station.get_port_position("ac_in").distance_to(station.get_port_position("heat_out")) > 14.0, "carrier endpoints are clearly separated")
	check(station.port_global().is_equal_approx(station.get_port_position("ac_in")), "legacy default endpoint is AC")
	check(station.get_port_position().is_equal_approx(station.get_port_position("ac_in")), "optional named-port argument remains AC-compatible")
	var holder := Node3D.new()
	root.add_child(holder)
	station.reparent(holder)
	holder.position = Vector3(9, 2, -7)
	holder.rotation.y = -0.4
	station.position = Vector3(5, 3, -2)
	station.rotation.y = 0.7
	station.scale = Vector3(1.2, 1.2, 1.2)
	for port_id in ["ac_in", "heat_out"]:
		check(station.get_port_position(port_id).is_equal_approx(station.named_ports[port_id].global_position), "named endpoint includes full parent/placement transform")
		check(station.get_named_port_position(port_id).is_equal_approx(station.get_port_position(port_id)), "named-port compatibility alias")
	check(station.get_port_position("missing").is_equal_approx(station.global_position), "unknown endpoint cannot silently become AC endpoint")
	check(not station.selection_ring.visible, "selection starts hidden")
	station.set_selected(true)
	check(station.selected and station.selection_ring.visible, "selection controls whole-site ring")
	for valid in [true, false]:
		station.set_preview(valid)
		check(station.selected and not station.selection_ring.visible, "preview preserves selected state without showing selection ring")
		check(not station.status_label.visible, "placement ghost hides live-operation readout")
		for surface in station.surfaces:
			check(surface.material_override == (station.preview_good if valid else station.preview_bad), "preview tint covers all geometry")
		var material: StandardMaterial3D = station.preview_good if valid else station.preview_bad
		check(material.albedo_color.a < 1.0 and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "placement preview is translucent")
	station.clear_preview()
	check(station.selection_ring.visible and station.status_label.visible, "clear preview restores selection and status")
	for i in station.surfaces.size():
		check(station.surfaces[i].material_override == station.base_materials[i], "clear preview restores authored material")
	station.set_highlight(false)
	check(not station.selected and not station.selection_ring.visible, "highlight compatibility alias controls selection")
	var tank: MeshInstance3D = station.get_node("TankSilhouette1/TankShell")
	var tank_shape := tank.transform
	var tank_material := tank.material_override
	station.set_status(2.4, 2.35, 18.75)
	check(station.status_label.text == "电 2.4 MW · 热 2.4 MWth\n储热 18.8 MWhth", "status displays explicit electricity/heat/inventory units")
	station.set_status(0.0, 0.0, 0.0)
	check(station.status_label.text.contains("储热 0.0 MWhth"), "zero inventory is displayed")
	station.set_status(NAN, INF, -INF)
	check(station.status_label.text == "电 — MW · 热 — MWth\n储热 — MWhth", "missing status does not invent operation values")
	check(tank.transform == tank_shape and tank.material_override == tank_material, "readout never changes tank volume or temperature color")
	check(station_data == original, "status and preview never mutate model data")
	var surface_count: int = station.surfaces.size()
	var child_count: int = station.get_child_count()
	station.set_selected(true)
	station.set_preview(false)
	station.setup({"title": "南区热站"}, false)
	check(station.title_label.text == "南区热站", "title field is accepted when name is absent")
	check(station.surfaces.size() == surface_count and station.get_child_count() == child_count, "repeated setup does not duplicate facility geometry")
	check(station.named_ports.size() == 2 and is_instance_valid(station.named_ports.ac_in), "repeated setup rebuilds valid carrier markers")
	check(station.selected and station.preview_enabled and not station.selection_ring.visible, "repeated setup preserves ghost and selection state")
	station.set_preview_disabled()
	check(station.selection_ring.visible and not station.preview_enabled, "legacy preview-disable restores selection after rebuild")
	station.setup({"name": "  "}, false)
	check(station.title_label.text == "电热储能站", "empty title uses readable generic facility name")
	holder.free()
	var detached = Facade.new()
	detached.position = Vector3(3, 2, 1)
	detached.rotation.y = 0.5
	check(detached.port_global().is_equal_approx(detached.transform * Facade.PORT_LOCALS.ac_in), "AC coordinate works before entering scene tree")
	detached.set_selected(true)
	detached.setup({}, false)
	check(detached.selection_ring.visible, "selection can be set before setup")
	detached.free()
	print("STATION_FACADE_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
