extends SceneTree

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
	for kind in ["wind", "pv", "station"]:
		var defaults: Dictionary = EnergyModel.defaults(kind)
		form.set_parameters(kind, defaults)
		check(form.get_parameters() == defaults, kind + ": every default round-trips")
		check(form._fields.size() + (1 if kind == "wind" else 0) == defaults.size(), kind + ": every accepted field has an editor")
		check(form.get_validation_errors().is_empty(), kind + ": valid defaults remain accepted")
		for key in defaults:
			if defaults[key] is Array:
				check(key == "power_curve_kw" and is_instance_valid(form._curve_editor), "curve has its dedicated multiline editor")
				continue
			check(form._fields.has(key), kind + ": editor for " + key)
			var editor: LineEdit = form._fields[key]
			check(not editor.tooltip_text.is_empty(), key + ": explanation available")
			check(editor.get_theme_font_size("font_size") >= 18, key + ": editable values use readable type")
			var style: StyleBoxFlat = editor.get_theme_stylebox("normal")
			check(style.bg_color.a == 1.0, key + ": input is opaque")
		check((form.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a == 1.0, "form is opaque")
		var copy: Dictionary = form.get_parameters()
		copy[defaults.keys()[0]] = -123.0
		check(form.get_parameters() == defaults, "returned dictionaries do not mutate form state")
	test_curves(form)
	form.set_parameters("wind", {"hub_height_m": 1000.123456789123})
	check(form.get_parameters().hub_height_m == 1000.123456789123, "untouched full-precision numeric values remain identical")
	form.set_parameters("wind", {"rated_mw": 5})
	check(typeof(form.get_parameters().rated_mw) == TYPE_INT, "untouched integers retain their type")
	form.set_parameters("wind", {"rated_mw": 5.0})
	check(form.get_parameters() == EnergyModel.defaults("wind"), "partial inputs inherit defaults")
	var original: Dictionary = EnergyModel.defaults("wind")
	form.set_parameters("wind", original)
	form._fields["rated_mw"].text = "4.25"
	check(form.get_parameters().rated_mw == 4.25, "numeric editing becomes numeric output")
	check(original.rated_mw == 5.0, "editing leaves caller data unchanged")
	for raw in ["", "abc", "1/0", "nan", "inf", "--1"]:
		form._fields["rated_mw"].text = raw
		check(not form.get_validation_errors().is_empty(), "invalid numeric text rejected: " + raw)
	form._fields["rated_mw"].text = " 5e0 "
	check(form.get_parameters().rated_mw == 5.0, "scientific notation and whitespace accepted")
	form._fields["rated_speed_mps"].text = "2"
	check(form.get_validation_errors().has("风速须满足：切入 < 额定 < 切出。"), "cross-field speed constraints remain enforced")
	form.set_parameters("wind", EnergyModel.defaults("wind"))
	form._fields["hub_height_m"].text = "50"
	check(not form.get_validation_errors().is_empty(), "hub/rotor geometry constraint remains enforced")
	form.set_parameters("wind", EnergyModel.defaults("wind"))
	form._fields["rated_mw"].text = "100"
	check(not form.get_validation_errors().is_empty(), "joint wind power constraint remains enforced")
	form.set_parameters("wind", EnergyModel.defaults("wind"))
	form._fields["cp_max"].text = str(16.0 / 27.0)
	check(form.get_validation_errors().is_empty(), "exact Betz upper bound retained without display rounding")
	form._fields["cp_max"].text = "0.6"
	check(not form.get_validation_errors().is_empty(), "above Betz bound rejected")
	form.set_parameters("pv", {"temp_coefficient_per_c": -0.004123456789})
	check(is_equal_approx(form.get_parameters().temp_coefficient_per_c, -0.004123456789), "small negative coefficient preserved")
	form._fields["inverter_efficiency"].text = "96"
	check(form.get_parameters().inverter_efficiency == 96.0, "out-of-range input never silently clamps")
	check(not form.get_validation_errors().is_empty(), "percentage mistakenly entered as fraction rejected")
	form.set_parameters("station", {"loss_fraction": 0.999999})
	check(form.get_parameters().loss_fraction == 0.999999, "station loss bound preserves six decimal places")
	check(form.get_validation_errors().is_empty(), "station loss inclusive bound accepted")
	form._fields["loss_fraction"].text = "1"
	check(not form.get_validation_errors().is_empty(), "station loss of one rejected")
	form.set_parameters("wind", {"obsolete_field": 7.0})
	check(form.get_parameters().has("obsolete_field"), "unknown data retained for rejection")
	check(not form.get_validation_errors().is_empty(), "unknown data cannot bypass model validation")
	form.set_parameters("station", EnergyModel.defaults("station"))
	check(not form.get_parameters().has("obsolete_field") and form._fields.size() == 2, "switching kind discards old draft and editors")
	check(not is_instance_valid(form._curve_editor), "switching away from wind discards the curve editor")
	form.set_parameters("bad_kind", {})
	check(not form.get_validation_errors().is_empty(), "unsupported kind produces explicit validation error")
	form.set_parameters("wind", EnergyModel.defaults("wind"))
	await process_frame
	await process_frame
	check(form._scroll.size.y < form._groups.size.y, "wind fields scroll within bounded dialog")
	check(form._scroll.get_h_scroll_bar().visible == false, "no horizontal scroll required")
	check(form._groups.size.x <= form._scroll.size.x, "CJK form fits available width without clipping")
	var notifications := [0, 0]
	form.parameters_changed.connect(func(): notifications[0] += 1)
	form.validation_changed.connect(func(_errors): notifications[1] += 1)
	form._fields["rated_mw"].text = "invalid"
	form._fields["rated_mw"].text_changed.emit("invalid")
	check(notifications == [1, 1], "editing emits change and validation signals once")
	check(form._status.text.begins_with("待修正："), "invalid edit immediately displays Chinese feedback")
	form.set_parameters("wind", EnergyModel.defaults("wind"))
	check(form._status.text.begins_with("参数检查通过"), "reset clears old validation errors")
	check(notifications[0] == 1, "loading parameters does not emit a user-edit signal")
	for editor in form._fields.values():
		check(editor.size.y >= 34 and editor.size.x >= 125, "numeric editors retain useful touch targets")
	var panel: PanelContainer = form._groups.get_child(0)
	var body: VBoxContainer = panel.get_child(0)
	var heading: Button = body.get_child(0)
	heading.button_pressed = false
	check(not body.get_child(1).visible, "group can collapse")
	heading.button_pressed = true
	check(body.get_child(1).visible, "group can reopen")
	await test_dialog_layout(form)
	form.free()
	await process_frame
	print("PARAMETER_FORM_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func edit_curve(form, text: String) -> void:
	form._curve_editor.text = text
	form._curve_editor.text_changed.emit()

func test_curves(form) -> void:
	form.set_parameters("wind", EnergyModel.defaults("wind"))
	check(form._fields.has("reference_air_density_kgm3"), "reference density has a numeric input")
	check(form._labels.reference_air_density_kgm3 == "参考空气密度", "reference density is labeled in Chinese")
	check(form._fields.reference_air_density_kgm3.text == "1.225", "reference density starts at 1.225")
	check(form._curve_editor.text.is_empty() and form.get_parameters().power_curve_kw == [], "default curve stays explicitly empty")
	check(form._curve_status.text.contains("默认三次式"), "empty-curve behavior is visible")
	check(form._curve_editor.get_theme_font_size("font_size") >= 18, "curve editing uses readable type")
	check((form._curve_editor.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.a == 1.0, "curve editor is opaque")
	edit_curve(form, "3, 0\n12, 100\n25, 0")
	check(form.get_validation_errors().is_empty(), "valid low-output electrical curve passes model validation")
	check(form.get_parameters().power_curve_kw == [{"wind_mps": 3.0, "power_kw": 0.0}, {"wind_mps": 12.0, "power_kw": 100.0}, {"wind_mps": 25.0, "power_kw": 0.0}], "CSV becomes exact array of named wind and electrical-power points")
	check(form._curve_status.text.contains("3 个点"), "curve status shows the draft point count")
	var notifications := [0, 0]
	form.parameters_changed.connect(func(): notifications[0] += 1)
	form.validation_changed.connect(func(_errors): notifications[1] += 1)
	edit_curve(form, "3, 0\n12, 120\n25, 0")
	check(notifications == [1, 1], "curve editing emits draft and validation signals once")
	form._fields.reference_air_density_kgm3.text = "0.4"
	check(not form.get_validation_errors().is_empty(), "reference density below its range is rejected")
	form._fields.reference_air_density_kgm3.text = "1.225"
	for raw in ["3, 0", "3, 0\n3, 1", "12, 100\n3, 0", "3, 0\n101, 100", "3, 0\n12, 5001", "3, 0\n12, -1", "3, 0\n12, nan", "3, 0\n12, inf", "3, 0\n12, 1e999", "3, 0\n12, text", "3, 0\n, 100", "3, 0\n12,", "3, 0\n12, 100, extra", "wind_mps, power_kw\n3, 0", "0, 0\n12, 100", "3, 200\n12, 200", "3, 0\n12, 5000"]:
		edit_curve(form, raw)
		check(not form.get_validation_errors().is_empty(), "malformed, unordered, nonfinite or physically invalid curve is rejected: " + raw)
		check(not form.get_validation_errors()[0].contains("power_curve_kw"), "curve errors are readable Chinese rather than raw schema errors: " + raw)
		check(form._curve_editor.text == raw, "invalid curve text is never silently corrected: " + raw)
	edit_curve(form, "3, 0\n12, 100")
	form._fields.rated_speed_mps.text = "2"
	check(form.get_validation_errors().is_empty(), "custom curve does not incorrectly use the default cubic rated-speed shape")
	form._fields.cut_in_mps.text = "26"
	check(form.get_validation_errors().has("自定义曲线的运行风速须满足：切入 < 切出。"), "custom cut-in/cut-out failure is described in Chinese")
	form._fields.cut_in_mps.text = "3"
	form._fields.rated_speed_mps.text = "11.4"
	edit_curve(form, "3, 0\n12, not-a-number")
	check(form.get_parameters().power_curve_kw[1].power_kw == "not-a-number", "invalid numeric cell remains validator-visible text")
	edit_curve(form, "3, 0\n12, 100, extra")
	check(form.get_parameters().power_curve_kw[1] == "12, 100, extra", "malformed row remains a validator-visible entry")
	edit_curve(form, " 3e0 , 0 \n\n 1.2e1，1e2 \n25,0 ")
	check(form.get_validation_errors().is_empty(), "CSV accepts whitespace, empty lines, scientific notation and Chinese comma")
	var many_lines := PackedStringArray()
	for index in range(256):
		many_lines.append("%s, 0" % (float(index) / 4.0))
	edit_curve(form, "\n".join(many_lines))
	check(form.get_parameters().power_curve_kw.size() == 256 and form.get_validation_errors().is_empty(), "exact 256-point limit is accepted")
	many_lines.append("100, 0")
	edit_curve(form, "\n".join(many_lines))
	check(not form.get_validation_errors().is_empty(), "257 points are rejected")
	edit_curve(form, " \n  \n")
	check(form.get_parameters().power_curve_kw == [] and form.get_validation_errors().is_empty(), "blank text selects the default cubic rather than a malformed point")
	var exact_curve := [{"wind_mps": 3, "power_kw": 0}, {"wind_mps": 12.1234567890123, "power_kw": 100.1234567890123}, {"wind_mps": 25, "power_kw": 0}]
	var original: Dictionary = EnergyModel.defaults("wind")
	original.power_curve_kw = exact_curve.duplicate(true)
	form.set_parameters("wind", original)
	check(form.get_parameters().power_curve_kw == exact_curve, "untouched curve retains full coordinate precision")
	check(typeof(form.get_parameters().power_curve_kw[0].wind_mps) == TYPE_INT, "untouched curve retains integer coordinates")
	var exact_lines: PackedStringArray = form._curve_editor.text.split("\n")
	exact_lines[2] = "26, 0"
	edit_curve(form, "\n".join(exact_lines))
	check(form.get_parameters().power_curve_kw[1] == exact_curve[1], "editing another point preserves every original high-precision coordinate")
	check(typeof(form.get_parameters().power_curve_kw[0].wind_mps) == TYPE_INT, "editing another point preserves untouched integer types")
	check(original.power_curve_kw == exact_curve, "editing curve never mutates caller-owned nested arrays")
	var detached: Dictionary = form.get_parameters()
	detached.power_curve_kw[1].power_kw = 999.0
	check(form.get_parameters().power_curve_kw[1].power_kw == exact_curve[1].power_kw, "returned nested curve points are deep copies")
	# Reset is draft-only, and removed curves cannot leak into another device kind.
	(form.find_child("ClearPowerCurve", true, false) as Button).pressed.emit()
	check(form.get_parameters().power_curve_kw == [], "clear-curve button selects default cubic for the draft")
	check(original.power_curve_kw == exact_curve, "clear-curve button leaves caller data unchanged")
	form.set_parameters("wind", {"power_curve_kw": "broken"})
	check(form.get_parameters().power_curve_kw == "broken" and not form.get_validation_errors().is_empty(), "malformed original curve remains rejectable")
	form.set_parameters("wind", {"power_curve_kw": [{"wind_mps": 3, "power_kw": 0, "unknown": 1}, {"wind_mps": 12, "power_kw": 100}]})
	var extra_text: String = form._curve_editor.text
	edit_curve(form, extra_text + "\n25, 0")
	check(form.get_parameters().power_curve_kw[0].has("unknown"), "editing another line does not silently discard original unknown point data")
	check(not form.get_validation_errors().is_empty(), "unknown point data is still rejected by the model")
	form.set_parameters("pv", EnergyModel.defaults("pv"))
	check(not form.get_parameters().has("power_curve_kw") and not is_instance_valid(form._curve_editor), "non-wind kind has no stale curve state")

func test_dialog_layout(form) -> void:
	# Model the real 940×790 modal structure with actions outside the scroll area.
	root.remove_child(form)
	var dialog := Control.new()
	dialog.size = Vector2(940, 790)
	root.add_child(dialog)
	var body := VBoxContainer.new()
	dialog.add_child(body)
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 20
	body.offset_right = -20
	body.offset_top = 18
	body.offset_bottom = -18
	body.add_theme_constant_override("separation", 10)
	for title_text in ["设备参数", "应用范围 · 仅当前设备 #0；不修改其他设备或未来模板。"]:
		var title := Label.new()
		title.text = title_text
		title.add_theme_font_size_override("font_size", 25 if title_text == "设备参数" else 16)
		body.add_child(title)
	body.add_child(form)
	var note := Label.new()
	note.text = "修改后校验并应用。取消或关闭不修改场景。"
	body.add_child(note)
	var actions := HBoxContainer.new()
	body.add_child(actions)
	for caption in ["恢复参考默认（待应用）", "取消", "校验并应用"]:
		var action := Button.new()
		action.text = caption
		action.custom_minimum_size.y = 36
		actions.add_child(action)
	form.set_parameters("wind", EnergyModel.defaults("wind"))
	await process_frame
	await process_frame
	check(actions.position.y + actions.size.y <= body.size.y, "bottom actions remain visible in the 940×790 modal")
	check(form._scroll.size.y < form._groups.size.y, "wind form scrolls rather than expanding the 940×790 modal")
	check(form._groups.size.x <= form._scroll.size.x, "larger Chinese typography still fits the modal width")
	check(form._status.position.y + form._status.size.y <= form.size.y, "validation summary stays outside the scroll and within the form")
	body.remove_child(form)
	root.add_child(form)
	dialog.queue_free()
