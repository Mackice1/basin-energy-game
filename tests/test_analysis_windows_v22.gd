extends SceneTree
## Headless structural/interaction checks only, not a rendered GUI audit.
const PanelScript = preload("res://scripts/optimization_panel.gd")
const ChartScript = preload("res://scripts/optimization_chart.gd")
const FormScript = preload("res://scripts/parameter_form.gd")
const ImportScript = preload("res://scripts/import_dialog.gd")
const ClimateScript = preload("res://scripts/climate_panel.gd")
const SpeedScript = preload("res://scripts/speed_control.gd")
const Model = preload("res://scripts/energy_model.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures.append(what)
		push_error(what)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1024, 768)
	var panel = PanelScript.new()
	root.add_child(panel)
	panel.open()
	panel.set_thermal_context(true)
	panel.size = Vector2i(700, 580)
	await process_frame
	await process_frame
	check(panel._run.get_global_rect().end.y <= panel.size.y, "primary solver action remains reachable at minimum window size")
	check(panel._tabs.size.y > 100.0, "heat settings leave a useful tab viewport")
	check(panel._detail.get_theme_color("default_color") == Color("edf3f6"), "detail foreground matches dark theme")
	check(panel.theme.get_stylebox("tab_selected", "TabBar").border_color == Color("69d1bd"), "Godot 4 TabBar uses visible selected accent")
	panel.set_busy(true)
	check(panel._status.get_theme_color("font_color") == Color("efbc68"), "busy state has warning accent")
	panel.show_error("测试错误")
	check(panel._status.get_theme_color("font_color") == Color("ff9790"), "failure state has error accent")
	var chart = panel._thermal_chart
	var row := {"time_s": 0.0, "dt_h": 1.0}
	for serie in chart._series:
		var path: PackedStringArray = str(serie.key).split(".")
		if not row.has(path[0]):
			row[path[0]] = {}
		row[path[0]][path[1]] = 1.0
	chart.set_steps([row])
	for width in [300.0, 600.0, 920.0]:
		var hits: Array = chart._layout_legend(width)
		check(hits.size() == chart._series.size(), "all actual series retain a legend at width %s" % width)
		for i in hits.size():
			var rect: Rect2 = hits[i].rect
			check(rect.position.x >= 14 and rect.end.x <= width - 13, "legend chip stays within horizontal bounds")
			if i > 0:
				check(not rect.intersects(hits[i - 1].rect), "neighboring legend hit targets never overlap")
	chart.size.x = 300.0
	chart._refresh_layout()
	var narrow_hits: Array = chart._layout_legend(300.0)
	check(chart.custom_minimum_size.y >= float(narrow_hits[-1].rect.end.y) + 150.0, "wrapped legend reserves an independent readable plot")
	var sparse = ChartScript.new()
	root.add_child(sparse)
	sparse.configure("检查", "MW", [{"key":"zero", "label":"真实零值", "color":Color("69d1bd")}, {"key":"missing", "label":"未返回值", "color":Color("efbc68")}])
	sparse.set_steps([{"time_s": 0.0, "dt_h": 1.0, "zero": 0.0}])
	var sparse_hits: Array = sparse._layout_legend(300.0)
	check(sparse_hits.size() == 1 and sparse_hits[0].key == "zero", "valid zero is shown while absent field is omitted")
	sparse._legend_hits = sparse_hits
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = sparse_hits[0].rect.get_center()
	sparse._gui_input(click)
	check(sparse._hidden.zero and sparse._layout_legend(300.0).size() == 1, "hidden series retains a legend for restoring visibility")
	sparse._gui_input(click)
	check(not sparse._hidden.zero, "legend click restores the same series")
	check(sparse._steps[0].zero == 0.0, "legend operations never modify the result data")
	var form = FormScript.new()
	root.add_child(form)
	form.set_parameters("battery", Model.defaults("battery"), false)
	check(form._fields.initial_soc.get_theme_color("font_uneditable_color") == Color("a5b7c4"), "read-only fields have explicit readable foreground")
	check(form._fields.initial_soc.tooltip_text.contains("只读参数"), "read-only fields explain why they cannot be edited")
	form.set_parameters("wind", Model.defaults("wind"))
	form._fields.rated_mw.text = "invalid"
	form._fields.rated_mw.text_changed.emit("invalid")
	check(form._fields.rated_mw.get_theme_stylebox("normal").border_color == Color("ff9790"), "model-invalid field is marked without changing its text")
	check(form._fields.rated_mw.text == "invalid", "error presentation does not repair the draft")
	form.set_parameters("wind", Model.defaults("wind"))
	check(form._status.get_theme_color("font_color") == Color("69d1bd"), "valid draft gets a clear success state")
	var importer = ImportScript.new()
	root.add_child(importer)
	importer.setup([{"id":"1", "name":"示例风机", "kind":"wind", "rated_kw":5000.0}])
	panel.hide()
	importer.open()
	importer.size = Vector2i(660, 560)
	await process_frame
	await process_frame
	check(importer._apply.get_global_rect().end.y <= importer.size.y, "import footer stays reachable at minimum size")
	check(importer._target.get_global_rect().end.x <= importer.size.x, "mapping controls fit the narrow import window")
	check(importer._apply.get_theme_color("font_color") == Color("edf3f6"), "primary import action has light readable text")
	var mapping := {"field":"wind_ms", "time_column":"t", "value_column":"v", "time_unit":"s", "value_unit":"m/s", "target_device":""}
	var parsed: Dictionary = importer.stage_import("t,v\n0,4\n1,5\n", mapping)
	check(parsed.ok and not importer._apply.disabled, "valid preview can still be applied")
	check(importer._preview.get_theme_stylebox("normal").border_color == Color("69d1bd"), "valid preview has success border")
	importer.stage_import("t,v\n0,no\n1,5\n", mapping)
	check(importer._apply.disabled and importer._preview.get_theme_color("default_color") == Color("ff9790"), "failed preview blocks application and signals error")
	var climate = ClimateScript.new()
	root.add_child(climate)
	climate.size = Vector2(320, 1)
	var candidates: Array = []
	climate.apply_requested.connect(func(value: Dictionary): candidates.append(value))
	climate.start_local.text = "invalid"
	climate._submit()
	check(candidates.is_empty() and climate.feedback.get_theme_color("font_color") == Color("ff9790"), "invalid climate draft remains unapplied")
	climate.set_config(climate.Climate.defaults())
	climate._submit()
	check(candidates.size() == 1 and candidates[0] == climate.Climate.defaults(), "valid climate draft emits the unchanged controller contract")
	climate.set_snapshot({"valid":false,"error":"测试"})
	check(climate.live.visible and climate.live.get_theme_color("font_color") == Color("ff9790"), "unavailable weather remains explicit")
	climate.set_snapshot({"valid":true,"is_day":true})
	check(climate.live.get_theme_color("font_color") == Color("edf3f6"), "recovered weather clears the stale error color")
	var speed = SpeedScript.new()
	root.add_child(speed)
	speed.size = Vector2(320, 1)
	await process_frame
	await process_frame
	check(speed._input.get_global_rect().end.x <= 320, "larger speed value typography still fits the narrow sidebar")
	check(climate.longitude.get_global_rect().end.x <= 320, "location controls fit the narrow sidebar")
	for node in [speed, climate, importer, form, sparse, panel]:
		node.free()
	await process_frame
	print("ANALYSIS_WINDOWS_V22 checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
