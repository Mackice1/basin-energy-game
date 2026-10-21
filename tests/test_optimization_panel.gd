extends SceneTree
## Real-control headless regressions. Fixture series test presentation only;
## they are not production forecasts or a substitute for visual acceptance.

const OptimizationPanel = preload("res://scripts/optimization_panel.gd")
var failures: Array[String] = []
var checks := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var panel = OptimizationPanel.new()
	root.add_child(panel)
	panel.open()
	await process_frame
	await process_frame
	check(panel.visible, "open shows the panel")
	check(panel._detail.get_theme_color("default_color") == Color("edf3f6"), "detail text has high-contrast foreground on dark surface")
	check(panel._step.min_value == 5 and panel._step.max_value == 360 and panel._timeout.max_value == 120, "input ranges match controller contract")
	check(panel.get_options() == {"horizon_hours": 24.0, "step_minutes": 60.0, "load_multiplier": 1.0, "strict_supply": false, "terminal_soc_fraction": null, "timeout_s": 30}, "defaults match task contract")
	panel.configure({"horizon_hours": 6.0, "step_minutes": 30.0, "load_multiplier": 1.5, "strict_supply": true, "terminal_soc_fraction": 0.75, "timeout_s": 12})
	check(panel.get_options().terminal_soc_fraction == 0.75 and panel.get_options().strict_supply, "configuration updates target/strict options")
	panel._load.get_line_edit().text = "1.75"
	check(panel.get_options().load_multiplier == 1.75, "unsubmitted numeric text commits before solve")
	var signal_count := [0, 0]
	panel.solve_requested.connect(func(_options): signal_count[0] += 1)
	panel.cancel_requested.connect(func(): signal_count[1] += 1)
	panel._request_solve()
	check(panel._busy and panel._run.disabled and not panel._cancel.disabled, "solve transitions into busy state")
	check(not panel._horizon.editable and panel._strict.disabled, "busy disables inputs")
	panel._request_solve()
	check(signal_count[0] == 1, "repeated solve cannot emit duplicate request")
	panel._request_cancel()
	check(not panel._busy and signal_count[1] == 1 and panel._steps.is_empty(), "cancel clears results and signals once")
	panel._request_cancel()
	check(signal_count[1] == 1, "repeated cancel does not emit twice")
	var steps := [
		{"time_s": 7200.0, "dt_h": 0.5, "wind_mw": 3.0, "pv_mw": 1.0, "available_mw": 4.0, "demand_mw": 2.0, "served_mw": 2.0, "unserved_mw": 0.0, "charge_mw": 1.0, "discharge_mw": 0.0, "energy_mwh": 5.5, "soc": 0.55, "export_mw": 0.5, "curtailed_mw": 0.25, "loss_mw": 0.25, "devices": {"battery-1": {"name": "电池 1", "charge_mw": 1.0, "discharge_mw": 0.0, "energy_mwh": 5.5, "soc": 0.55}}},
		{"time_s": 9000.0, "dt_h": 0.25, "wind_mw": 1.0, "pv_mw": 0.0, "available_mw": 1.0, "demand_mw": 2.0, "served_mw": 2.0, "unserved_mw": 0.0, "charge_mw": 0.0, "discharge_mw": 1.0, "energy_mwh": 5.25, "soc": 0.525, "export_mw": 0.0, "curtailed_mw": 0.0, "loss_mw": 0.0}
	]
	var result := {"status": "optimal", "steps": steps}
	var baseline := result.duplicate(true)
	baseline.steps[0].charge_mw = 0.5
	panel.show_result(result, baseline)
	await process_frame
	await process_frame
	check(panel._steps.size() == 2 and panel._power_chart._steps.size() == 2 and panel._soc_chart._steps.size() == 2, "result populates both charts")
	check(panel._status.text.contains("已证明最优"), "optimal status is explicit")
	check(panel._detail.text.contains("电池 1") and panel._detail.text.contains("0.500 MWh"), "per-device details include integrated energy")
	check(is_equal_approx(panel._integral(steps, "served_mw"), 1.5), "irregular durations integrate correctly")
	check(panel._comparison.get_child_count() == 36, "comparison contains header and eight rows")
	check(panel._comparison_note.text.contains("固定优先级基线"), "matching baseline accepted")
	panel._select_step(1)
	check(panel._power_chart._selected == 1 and panel._soc_chart._selected == 1 and panel._next.disabled, "selection synchronizes plots and navigation")
	check(panel._selection.text.contains("2.500–2.750 h") and panel._detail.text.contains("0.250 MWh"), "absolute timestep and MWh remain explicit")
	check(panel._power_chart._start_s == 7200.0 and panel._power_chart._end_s == 9900.0, "chart uses actual initial and final timestamps")
	panel._power_chart._choose(0)
	check(panel._selected == 0, "chart clicks update selected timestep")
	panel._soc_chart._choose(1)
	check(panel._selected == 1, "SOC chart clicks update selected timestep")
	panel.mark_stale()
	check(panel._steps.is_empty() and panel._power_chart._steps.is_empty() and panel._soc_chart._steps.is_empty(), "stale clears plots")
	check(result.steps.size() == 2 and result.steps[0].charge_mw == 1.0, "clearing never mutates caller data")
	panel.show_result(result, {})
	check(panel._comparison_note.text.contains("不显示虚构比较"), "absent baseline is explicitly disclosed")
	check(panel._comparison.get_child(5).text == "—", "missing baseline never becomes zero")
	var misaligned := baseline.duplicate(true)
	misaligned.steps[0].time_s = 7000.0
	panel.show_result(result, misaligned)
	check(panel._comparison_note.text.contains("不显示虚构比较"), "misaligned baseline is not compared")
	var incomplete := result.duplicate(true)
	incomplete.steps[0].erase("unserved_mw")
	panel.show_result(incomplete, baseline)
	check(panel._comparison.get_child(10).text == "—", "missing result field never becomes zero")
	panel.show_result({"steps": []})
	check(panel._steps.is_empty() and panel._error.visible, "empty result clears and reports error")
	panel.show_result({"steps": [{"time_s": 0.0, "dt_h": 0.0}]})
	check(panel._error.text.contains("时长"), "zero duration rejected")
	panel.show_result({"steps": [{"time_s": 0.0, "dt_h": 1.0}, {"time_s": 1800.0, "dt_h": 1.0}]})
	check(panel._error.text.contains("重叠"), "overlapping intervals rejected")
	panel.show_result(result, baseline)
	panel._load.value = 2.0
	check(panel._steps.is_empty() and panel._status.text.contains("失效"), "changing options invalidates previous result")
	panel.set_busy(true)
	panel._close()
	check(not panel.visible and signal_count[1] == 2 and not panel._busy, "close cancels active solve and hides")
	panel._close()
	check(signal_count[1] == 2, "closing again does not cancel twice")
	panel.open()
	panel.show_result(result, baseline)
	panel.size = Vector2i(700, 580)
	await process_frame
	await process_frame
	check(panel._run.get_global_rect().end.x < panel.size.x and panel._run.get_global_rect().end.y < panel.size.y, "solve remains reachable at minimum size")
	check(panel._tabs.size.y > 100.0 and panel._power_chart.size.x >= 300.0, "tab body retains useful area at minimum size")
	for i in range(panel._tabs.get_tab_count()):
		panel._tabs.current_tab = i
		await process_frame
		var scroll: ScrollContainer = panel._tabs.get_child(i)
		check(not scroll.get_h_scroll_bar().visible, "tab %d requires no horizontal scroll" % i)
	panel.configure({"horizon_hours": 168, "step_minutes": 5})
	panel._request_solve()
	check(not panel._busy and panel._error.text.contains("336"), "oversized step count rejected before solver signal")
	panel.size = Vector2i(1000, 740)
	await process_frame
	panel.free()
	await process_frame
	print("OPTIMIZATION_UI_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
