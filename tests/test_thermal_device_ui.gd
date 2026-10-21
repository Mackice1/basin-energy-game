extends SceneTree
## Focused thermal geometry and parameter-form contract; no simulated energy is
## created by the display. Run with -- --capture-thermal-ui for rendered sheets.
const Visual = preload("res://scripts/equipment_visual.gd")
const Form = preload("res://scripts/parameter_form.gd")
const Model = preload("res://scripts/energy_model.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const KINDS := ["electric_boiler", "thermal_store", "heat_exchanger", "heat_demand"]
const PORTS := {
	"electric_boiler": ["ac_in", "heat_out"],
	"thermal_store": ["heat_in", "heat_out"],
	"heat_exchanger": ["hot_in", "warm_out"],
	"heat_demand": ["heat_in"]
}
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
	_test_geometry()
	_test_legacy_endpoints()
	await _test_forms()
	if failures.is_empty() and "--capture-thermal-ui" in OS.get_cmdline_user_args():
		await _capture_review()
	print("THERMAL_DEVICE_UI_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_geometry() -> void:
	var representations: Array[String] = []
	for kind in KINDS:
		var params: Dictionary = Model.defaults(kind)
		var original := params.duplicate(true)
		var item = Visual.create(kind, params, false)
		root.add_child(item)
		check(not item.has_node("Placeholder"), kind + ": independently authored geometry")
		check(item.device_kind == kind, kind + ": stable kind")
		check(item.get_meta("visual_only") and item.get_meta("capacity_added") == 0.0, kind + ": visual adds no capacity")
		check(params == original, kind + ": does not mutate model parameters")
		check(item.rotor == null, kind + ": does not reuse wind geometry")
		check(item.surfaces.size() > 15 and item.surfaces.size() < 100, kind + ": bounded lightweight mesh count")
		check(item.surfaces.size() == item.base_materials.size(), kind + ": authored materials are restorable")
		check(not item.get_meta("temperature_is_dynamic"), kind + ": no invented temperature state")
		check("已充水" in item.get_meta("thermal_boundary") and "循环辅机" in item.get_meta("thermal_boundary"), kind + ": equivalent boundary is explicit")
		representations.append(item.get_meta("representation"))
		check(item.named_port_locals.size() == PORTS[kind].size(), kind + ": exact port count")
		for port_id in PORTS[kind]:
			check(item.has_named_port(port_id), kind + ": named port exists " + port_id)
			var terminal: Node3D = item.named_ports[port_id]
			var contract: Dictionary = Catalog.port(kind, port_id)
			for key in ["direction", "carrier", "unit"]:
				check(terminal.get_meta(key) == contract[key], kind + ": port matches catalog " + port_id + "/" + key)
			check(terminal.get_meta("port_id") == port_id, kind + ": port id metadata")
			var label: Label3D = terminal.get_node("PortLabel")
			if contract.carrier == "electricity_ac":
				check(terminal.get_meta("voltage_level") == "AC_BUS" and not terminal.has_meta("grade_id"), kind + ": AC port has no thermal grade")
				check(label.text.contains("电AC") and terminal.has_node("ACSquare"), kind + ": AC text plus square glyph")
			else:
				check(terminal.get_meta("grade_id") == contract.grade_id, kind + ": heat grade matches catalog")
				var primary: bool = contract.grade_id == "hw_primary_90_60"
				check(label.text.contains("热90" if primary else "热70"), kind + ": thermal grade has readable text")
				check(terminal.has_node("PrimaryHexFlange" if primary else "SecondaryInnerFlange"), kind + ": heat grade is shape-coded")
			check(label.text.contains("入" if contract.direction == "input" else "出"), kind + ": direction visible in text")
			check(item.get_named_port_position(port_id).is_equal_approx(terminal.global_position), kind + ": named port position is rendered endpoint")
		if PORTS[kind].size() == 2:
			check(item.get_named_port_position(PORTS[kind][0]).distance_to(item.get_named_port_position(PORTS[kind][1])) > 3.0, kind + ": independently selectable separated endpoints")
		for surface in item.surfaces:
			if surface == item.selection_ring:
				continue
			for corner in 8:
				var point: Vector3 = surface.global_transform * surface.mesh.get_aabb().get_endpoint(corner)
				check(point.y >= -0.00001, kind + ": geometry above ground")
				check(Vector2(point.x, point.z).length() <= Visual.footprint(kind), kind + ": geometry within advertised footprint")
		item.set_highlight(true)
		check(item.selection_ring.visible, kind + ": selection ring visible")
		for valid in [true, false]:
			item.set_preview(valid)
			for surface in item.surfaces:
				check(surface.material_override == (item.preview_good if valid else item.preview_bad), kind + ": preview applies to each mesh")
			check(not item.selection_ring.visible, kind + ": preview hides selection")
		item.clear_preview()
		for index in item.surfaces.size():
			check(item.surfaces[index].material_override == item.base_materials[index], kind + ": restores original material")
		item.position = Vector3(5, 2, -4)
		item.rotation.y = 0.7
		for port_id in PORTS[kind]:
			check(item.get_named_port_position(port_id).is_equal_approx(item.to_global(item.named_port_locals[port_id])), kind + ": named endpoint follows transform")
		check(item.get_port_position().is_equal_approx(item.to_global(item.port_local)), kind + ": old endpoint API compatible")
		if kind == "thermal_store":
			check(item.get_meta("storage_approximation").contains("双区") and not item.get_meta("soc_changes_temperature"), "storage: fixed-quality two-zone model")
			var zone: MeshInstance3D = item.get_node("FixedSupplyZone0")
			var shape: Transform3D = zone.transform
			var material: Material = zone.material_override
			for soc in [0.0, 0.25, 1.0]:
				item.set_thermal_soc(soc)
				check(item.thermal_soc_label.text == "库存 SOC %.1f%%" % (soc * 100.0) and item.thermal_soc_label.no_depth_test, "storage: separate inventory gauge remains readable over its physical plaque")
				check(zone.transform == shape and zone.material_override == material, "storage: SOC never changes temperature geometry/color")
			item.set_thermal_soc(NAN)
			check(item.thermal_soc_label.text == "库存 SOC —", "storage: unknown SOC does not invent temperature")
		if kind == "heat_demand":
			check(not item.get_meta("is_factory") and item.get_meta("demand_added") == 0.0, "heat demand is abstract and adds no extra demand")
			check(item.has_node("HeatDemandHexBase") and item.has_node("HeatWave0_0"), "heat demand has a distinct abstract marker")
		item.free()
	check(representations.size() == 4 and not representations.has("container_battery") and not representations.has("demand_connection_marker"), "thermal device silhouettes have distinct roles")
	for i in representations.size():
		for j in range(i + 1, representations.size()):
			check(representations[i] != representations[j], "thermal silhouettes are distinct")

func _test_legacy_endpoints() -> void:
	var expected := {
		"wind": [Vector3(1.15, 0.65, -0.37), 7.0, ["out"]],
		"pv": [Vector3(3.75, 0.38, -0.30), 5.0, ["out"]],
		"station": [Vector3(0, 0.45, -2.45), 4.0, ["in", "out"]],
		"load": [Vector3(0.95, 0.52, -2.39), 5.5, ["in"]],
		"battery": [Vector3(-2.55, 0.57, -1.56), 4.0, ["ac"]]
	}
	for kind in expected:
		var item = Visual.create(kind)
		check(item.port_local.is_equal_approx(expected[kind][0]), kind + ": unchanged legacy endpoint")
		check(Visual.footprint(kind) == expected[kind][1], kind + ": unchanged legacy footprint")
		check(item.has_node("ElectricityPort"), kind + ": unchanged legacy terminal")
		for port_id in expected[kind][2]:
			check(item.get_named_port_position(port_id).is_equal_approx(item.get_port_position()), kind + ": named AC alias shares original endpoint")
		item.free()

func _all_text(node: Node) -> String:
	var result := ""
	if node is Label or node is Button or node is Label3D:
		result += node.text + "\n"
	for child in node.get_children():
		result += _all_text(child)
	return result

func _test_forms() -> void:
	var form = Form.new()
	var theme := Theme.new()
	theme.default_font = load("res://assets/InterfaceCJK.ttc")
	form.theme = theme
	root.add_child(form)
	form.size = Vector2(760, 480)
	for kind in KINDS:
		var defaults: Dictionary = Model.defaults(kind)
		form.set_parameters(kind, defaults)
		check(not defaults.is_empty(), kind + ": authoritative model defaults exist")
		check(form.get_parameters() == defaults, kind + ": lossless parameter round-trip")
		check(form._fields.size() == defaults.size(), kind + ": every model parameter has an editor")
		check(form.get_validation_errors().is_empty(), kind + ": defaults validate")
		check(not is_instance_valid(form._curve_editor), kind + ": no wind/electrical CSV editor")
		for key in defaults:
			check(form._fields.has(key), kind + ": editor for " + key)
			var editor: LineEdit = form._fields[key]
			check(editor.get_meta("parameter_default") == defaults[key], kind + ": model default metadata")
			check(not editor.get_meta("parameter_note").is_empty(), kind + ": Chinese explanation")
			check(editor.editable, kind + ": construction parameter editable")
			check(editor.get_meta("construction_only") == (key == "initial_soc"), kind + ": construction-only scope")
			check(not key.contains("temperature") and not key.contains("supply_c") and not key.contains("return_c"), kind + ": no freely editable temperature")
			if key.ends_with("mwth"):
				check(editor.get_meta("parameter_unit") == "MWth", kind + ": heat power unit")
			if key.ends_with("mwhth"):
				check(editor.get_meta("parameter_unit") == "MWhth", kind + ": heat energy unit")
			form._fields[key].text = "invalid"
			check(not form.get_validation_errors().is_empty(), kind + ": invalid text is rejected " + key)
			check(not form.get_validation_errors()[0].contains("must"), kind + ": invalid numeric text is localized")
			form._fields[key].text = str(defaults[key])
		var visible: String = _all_text(form)
		check(visible.contains("教学假设") and visible.contains("温区"), kind + ": teaching profile is visible")
		check(visible.contains("已充水") and visible.contains("循环辅机"), kind + ": boundary is visible")
		for character in visible + "电AC 入 热90 出 热70 入 库存 SOC —":
			if character.unicode_at(0) >= 0x3400 and character.unicode_at(0) <= 0x9fff:
				check(theme.default_font.has_char(character.unicode_at(0)), "Chinese font covers " + character)
		await process_frame
		await process_frame
		check(not form._scroll.get_h_scroll_bar().visible, kind + ": no horizontal scrolling")
		check(form._groups.size.x <= form._scroll.size.x, kind + ": form fits readable panel width")
		check(form._status.position.y + form._status.size.y <= form.size.y + 0.01, kind + ": validation status remains visible")
	form.set_parameters("thermal_store", Model.defaults("thermal_store"), false)
	check(not form._fields.initial_soc.editable, "existing thermal store initial SOC is read-only")
	check(form._summary.text.contains("当前热库存独立保存") and form._summary.text.contains("只读"), "runtime thermal state separation is visible")
	form._fields.initial_soc.text = "1"
	check(form.get_parameters().initial_soc == 0.0, "programmatic edit cannot refill an existing thermal store")
	form._fields.capacity_mwhth.text = "8"
	check(form.get_parameters().capacity_mwhth == 8.0, "other storage parameters stay editable")
	check(not form.get_parameters().has("energy_mwhth") and not form.get_parameters().has("energy_mwh"), "form does not add runtime inventory")
	check(form._fields.charge_efficiency.tooltip_text.contains("热库存") and not form._fields.charge_efficiency.tooltip_text.contains("电量"), "thermal efficiency does not reuse electrical explanation")
	form.set_parameters("thermal_store", {"energy_mwhth": 1.0})
	check(not form.get_validation_errors().is_empty() and form.get_parameters().has("energy_mwhth"), "unknown inventory parameter is retained and rejected")
	form.set_parameters("heat_exchanger", Model.defaults("heat_exchanger"))
	check(_all_text(form).contains("90/60°C → 冷侧 70/40°C"), "both exchanger temperature profiles are visible")
	check(form._fields.min_approach_k.tooltip_text.contains("90−70=20") and form._fields.min_approach_k.tooltip_text.contains("60−40=20"), "both terminal approach constraints are explained")
	form._fields.min_approach_k.text = "21"
	check(not form.get_validation_errors().is_empty(), "excessive approach temperature is rejected")
	form._fields.transfer_efficiency.text = "98"
	check(form.get_parameters().transfer_efficiency == 98.0 and not form.get_validation_errors().is_empty(), "invalid percentage is not silently clamped")
	form.set_parameters("heat_demand", Model.defaults("heat_demand"))
	check(_all_text(form).contains("不支持热需求时序导入"), "constant-only heat demand limit is explicit")
	check(form._fields.priority.tooltip_text.contains("不能称为严格"), "heat priority does not overclaim strict ordering")
	form._fields.priority.text = "1.5"
	check(not form.get_validation_errors().is_empty() and not form.get_validation_errors()[0].contains("must"), "fractional heat priority is rejected in Chinese")
	form.set_parameters("battery", Model.defaults("battery"))
	check(form._fields.charge_efficiency.tooltip_text.contains("电量") and not form._fields.charge_efficiency.tooltip_text.contains("热库存"), "switching to battery restores electrical explanations")
	check(not form.get_parameters().has("capacity_mwhth"), "thermal fields cannot leak into electrical draft")
	form.free()
	await process_frame

func _capture_review() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Screenshot review requires a rendering display; headless checks are not screenshot acceptance.")
		failures.append("No rendering display for capture")
		return
	root.size = Vector2i(1440, 900)
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("dbe4e0")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -25, 0)
	sun.light_energy = 1.2
	scene.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 23.0
	camera.position = Vector3(3, 17, -22)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 1, 0))
	camera.current = true
	for index in KINDS.size():
		var item = Visual.create(KINDS[index])
		item.position = Vector3((index % 2) * 10.0 - 5.0, 0, floori(index / 2.0) * 9.0 - 4.5)
		scene.add_child(item)
		if KINDS[index] == "thermal_store":
			item.set_thermal_soc(0.42)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://thermal_device_visuals.png")
	scene.queue_free()
	await process_frame
	var form = Form.new()
	var theme := Theme.new()
	theme.default_font = load("res://assets/InterfaceCJK.ttc")
	form.theme = theme
	form.position = Vector2(240, 70)
	form.size = Vector2(960, 760)
	root.add_child(form)
	for kind in KINDS:
		form.set_parameters(kind, Model.defaults(kind), kind != "thermal_store")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://thermal_parameters_%s.png" % kind)
	form.free()
	print("THERMAL_DEVICE_UI_CAPTURE ", OS.get_user_data_dir())
