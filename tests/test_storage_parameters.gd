extends SceneTree
## New device editors preserve the model contract and never own runtime SOC.
const Form = preload("res://scripts/parameter_form.gd")
const EnergyModel = preload("res://scripts/energy_model.gd")
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
	var form = Form.new()
	var theme := Theme.new()
	theme.default_font = load("res://assets/InterfaceCJK.ttc")
	form.theme = theme
	root.add_child(form)
	form.size = Vector2(760, 420)
	for kind in ["load", "battery"]:
		var defaults: Dictionary = EnergyModel.defaults(kind)
		check(not defaults.is_empty(), kind + ": model supplies a supported schema")
		form.set_parameters(kind, defaults)
		check(form.get_parameters() == defaults, kind + ": default values round-trip unchanged")
		check(form._fields.size() == defaults.size(), kind + ": every accepted parameter has an editor")
		check(form.get_validation_errors().is_empty(), kind + ": default parameters validate")
		check(not is_instance_valid(form._curve_editor), kind + ": no irrelevant wind-curve editor")
		for key in defaults:
			check(form._fields.has(key), kind + ": field exists: " + key)
			var editor: LineEdit = form._fields[key]
			check(editor.get_meta("parameter_key") == key, key + ": stable parameter key metadata")
			check(editor.get_meta("parameter_label") == form._labels[key], key + ": Chinese label metadata")
			check(not str(editor.get_meta("parameter_unit")).is_empty(), key + ": unit metadata")
			check(not str(editor.get_meta("parameter_range")).is_empty(), key + ": range metadata")
			check(editor.get_meta("parameter_default") == defaults[key], key + ": model default metadata")
			check(not str(editor.get_meta("parameter_note")).is_empty(), key + ": explanation metadata")
			check(editor.editable, key + ": construction editor is editable")
			check(editor.get_theme_font_size("font_size") >= 18, key + ": values remain legible")
			check(editor.get_meta("construction_only") == (key == "initial_soc"), key + ": construction-only metadata is explicit")
		form.get_parameters()[defaults.keys()[0]] = -99.0
		check(form.get_parameters() == defaults, kind + ": returned dictionary cannot mutate the editor")
		for panel in form._groups.get_children():
			var body: VBoxContainer = panel.get_child(0)
			var source: Label = body.get_child(1).get_child(0)
			check(source.text.contains("教学假设"), kind + ": every group identifies teaching assumptions")
		await process_frame
		await process_frame
		check(not form._scroll.get_h_scroll_bar().visible, kind + ": no horizontal scrolling needed")
		check(form._groups.size.x <= form._scroll.size.x, kind + ": fields fit readable-width panel")
	form.set_parameters("load", {"demand_mw": 2.123456789123, "priority": 10})
	check(form.get_parameters().demand_mw == 2.123456789123, "untouched demand retains full precision")
	check(typeof(form.get_parameters().priority) == TYPE_INT, "untouched priority retains its integer type")
	check(form._fields.priority.tooltip_text.contains("较小"), "load priority direction is visible")
	form._fields.priority.text = "1.5"
	check(not form.get_validation_errors().is_empty(), "fractional priority is rejected")
	check(not form.get_validation_errors()[0].contains("must"), "priority error is described in Chinese")
	form._fields.priority.text = "0"
	form._fields.demand_mw.text = "0"
	check(form.get_validation_errors().is_empty(), "zero demand and highest priority are supported")
	form._fields.demand_mw.text = "-1"
	check(not form.get_validation_errors().is_empty(), "negative demand rejected")
	form.set_parameters("battery", EnergyModel.defaults("battery"), true)
	form._fields.initial_soc.text = "0.25"
	check(form.get_parameters().initial_soc == 0.25, "new-construction SOC can be configured")
	check(form._summary.text.contains("只用于新建"), "construction-only SOC scope is visible")
	var battery_defaults: Dictionary = EnergyModel.defaults("battery")
	form.set_parameters("battery", battery_defaults, false)
	check(not form._fields.initial_soc.editable, "existing-device initial SOC is read-only")
	check(form._summary.text.contains("当前电量独立保存") and form._summary.text.contains("只读"), "existing-device state separation is visible")
	form._fields.initial_soc.text = "1"
	check(form.get_parameters().initial_soc == battery_defaults.initial_soc, "programmatic edits cannot change locked initial SOC")
	form._fields.capacity_mwh.text = "15"
	check(form.get_parameters().capacity_mwh == 15.0, "other battery parameters remain editable")
	check(battery_defaults.capacity_mwh == 10.0, "editing does not mutate caller parameters")
	check(not form.get_parameters().has("energy_mwh") and not form.get_parameters().has("state"), "form does not invent or reset runtime energy state")
	form.set_parameters("battery", EnergyModel.defaults("battery"))
	for key in ["charge_efficiency", "discharge_efficiency"]:
		form._fields[key].text = "90"
		check(not form.get_validation_errors().is_empty(), key + ": percentages entered without conversion are rejected")
		check(form.get_parameters()[key] == 90.0, key + ": invalid value is not silently clamped")
		form._fields[key].text = "0.9"
	for key in ["charge_mw", "discharge_mw", "self_discharge_per_h", "initial_soc"]:
		form._fields[key].text = "0"
	check(form.get_validation_errors().is_empty(), "zero charging, discharging, self-discharge and initial SOC are supported")
	form._fields.capacity_mwh.text = "0"
	check(not form.get_validation_errors().is_empty(), "zero energy capacity rejected")
	form.set_parameters("battery", {"energy_mwh": 5.0})
	check(not form.get_validation_errors().is_empty(), "runtime energy cannot be smuggled into parameter schema")
	check(form.get_parameters().has("energy_mwh"), "unknown state fields remain visible for validation rejection")
	form.set_parameters("load", EnergyModel.defaults("load"))
	check(form._fields.size() == 2 and not form.get_parameters().has("initial_soc"), "switching device kind discards stale battery editors")
	form.free()
	await process_frame
	print("STORAGE_PARAMETERS_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
