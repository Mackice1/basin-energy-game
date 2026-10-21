extends SceneTree
## Real controls: integer dragging and input, decimal rejection/restore,
## repeated controller refreshes, and no signal loops during two-way sync.

const SpeedControl = preload("res://scripts/speed_control.gd")
var failures: Array[String] = []
var checks := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("SPEED_CONTROL_FAIL: " + description)

func _initialize() -> void:
	call_deferred("_run")

func _submit(control, text: String) -> void:
	control._input.text = text
	control._input.text_submitted.emit(text)

func _run() -> void:
	root.size = Vector2i(800, 600)
	var control = SpeedControl.new()
	var emitted: Array[float] = []
	control.speed_changed.connect(func(value: float):
		emitted.append(value)
		control.set_speed(value))
	control.set_speed(3.0)
	check(control.get_speed() == 3.0 and emitted.is_empty(), "pre-ready external value is exact and silent")
	root.add_child(control)
	control.size = Vector2(320, 1)
	await process_frame
	await process_frame
	check(control._slider is HSlider and control._input is LineEdit, "slider and directly validated numeric text editor exist")
	check(control._slider.min_value == 1.0 and control._slider.max_value == 60.0 and control._slider.step == 1.0, "slider is linear 1–60 with integer steps")
	check(not control._slider.exp_edit and control._slider.tick_count == 0, "no logarithmic spacing or separate reference ticks")
	check(control._input.text == "3" and control._slider.value == 3.0, "integer field and slider are synchronized")
	check(control.get_minimum_size().x <= 320.0 and control._input.get_global_rect().end.x <= 320.0, "editor fits 320px sidebar")
	check(control._input.position.x > control._slider.position.x and control._range_note.text.contains("每次 1 倍"), "numeric input is on right and integer behavior is visible")
	check(control.get_child_count() == 4, "ready after pre-ready setup does not duplicate controls")
	control._slider.value = 8.0
	check(control.get_speed() == 8.0 and control._input.text == "8" and emitted == [8.0], "integer slider change updates model and input exactly once")
	control._slider.value = 9.4
	check(control.get_speed() == 9.0 and emitted[-1] == 9.0, "drag/property updates use one-times integer steps")
	_submit(control, "12")
	check(control.get_speed() == 12.0 and control._input.text == "12" and control._slider.value == 12.0, "valid integer text updates slider")
	_submit(control, "25")
	check(control.get_speed() == 25.0 and control._input.text == "25" and control._slider.value == 25.0, "subsequent integer text updates both controls")
	var before := emitted.size()
	control._input.focus_exited.emit()
	_submit(control, "25")
	control.set_speed(25.0)
	check(emitted.size() == before and control.get_speed() == 25.0, "submit then blur, duplicate submit, and controller callback do not loop")
	control.set_speed(17.0)
	check(control.get_speed() == 17.0 and control._input.text == "17", "controller update changes the displayed integer")
	control._input.focus_exited.emit()
	check(control.get_speed() == 17.0 and emitted.size() == before, "unchanged field does not emit again on blur")
	control._input.text = "3"
	control.set_speed(control.get_speed())
	check(control._input.text == "3", "routine same-value refresh preserves unfinished input")
	control._input.focus_exited.emit()
	check(control.get_speed() == 3.0 and control._input.text == "3", "focus exit commits edited integer text")
	_submit(control, " 4 ")
	check(control.get_speed() == 4.0 and control._input.text == "4", "surrounding whitespace is accepted and normalized")
	_submit(control, "1.5e1")
	check(control.get_speed() == 15.0 and control._slider.value == 15.0, "numeric scientific notation with an integer value is accepted")
	_submit(control, "1")
	check(control.get_speed() == 1.0, "minimum is inclusive")
	_submit(control, "60")
	check(control.get_speed() == 60.0 and control._slider.value == 60.0, "maximum is inclusive")
	control.set_speed(3.0)
	before = emitted.size()
	for invalid in ["", " ", "NaN", "nan", "inf", "INF", "-inf", "1e309", "-1e309", "0", "0.1", "0.99999999", "1.25", "2.375", "59.9", "60.00000001", "61", "-1", "hello", "2,5", "2x", "1.2.3"]:
		_submit(control, invalid)
		check(control.get_speed() == 3.0 and control._input.text == "3" and control._slider.value == 3.0, "invalid '%s' restores exact previous speed" % invalid)
		check(emitted.size() == before and control._error.visible and control._input.tooltip_text.contains("已恢复原值"), "invalid '%s' shows an error without changing speed" % invalid)
		control.set_speed(3.0)
		control._input.focus_exited.emit()
		check(control._error.visible, "invalid '%s' feedback survives refresh and ensuing blur" % invalid)
	_submit(control, "45")
	check(control.get_speed() == 45.0 and not control._error.visible, "next valid edit clears the error")
	before = emitted.size()
	control.set_speed(10.0)
	check(control.get_speed() == 10.0 and control._input.text == "10" and control._slider.value == 10.0 and emitted.size() == before, "external update synchronizes both controls silently")
	control._input.text = "42"
	control.set_speed(1.0)
	check(control._input.text == "1" and control._slider.value == 1.0 and emitted.size() == before, "real external reset replaces an unfinished edit without emitting")
	control.set_speed(10.0)
	for invalid in [NAN, INF, -INF, 0.0, 0.1, 1.25, 2.375, 59.9, 60.00001]:
		control.set_speed(invalid)
		check(control.get_speed() == 10.0 and emitted.size() == before and control._error.visible, "invalid programmatic speed is rejected, not clamped")
	control._slider.value = 1.0
	check(control.get_speed() == 1.0 and not control._error.visible, "slider remains usable after validation failures")
	control._slider.value = 60.0
	check(control.get_speed() == 60.0 and control._input.text == "60", "slider reaches inclusive upper endpoint")
	control.free()
	await process_frame
	print("SPEED_CONTROL_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
