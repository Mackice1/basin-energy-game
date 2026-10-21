extends SceneTree
## Thermal forecast presentation and immutable controller snapshot regressions.
## The real solver run verifies the controller/UI boundary; numerical physics
## and adversarial audit coverage live in their dedicated dispatch suites.
const OptimizationPanel = preload("res://scripts/optimization_panel.gd")
const Controller = preload("res://scripts/optimization_controller.gd")
const Catalog = preload("res://scripts/device_catalog.gd")

class Fixture:
	extends Node
	var devices: Array = []
	var links: Array = []
	var imports: Array = []
	var elapsed_s := 0.0
	var scene_revision := 1
	var climate_config: Dictionary = {}
	var paused := false
	func update_status() -> void: pass
	func common_interval(_imports: Array) -> Dictionary: return {"start": 0.0, "end": 1000000.0}
	func active_series() -> Array: return []
	func sampled(_time: float) -> Dictionary:
		return {"error": "", "weather": {}, "device_weather": {}, "sources": [], "direct": {"0": {"mw": 2.0}}}

var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func thermal_row(time_s: float, dt_h: float, served: float, inventory: float) -> Dictionary:
	return {"time_s": time_s, "dt_h": dt_h, "wind_mw": 2.0, "pv_mw": 0.0,
		"available_mw": 2.0, "demand_mw": 0.0, "served_mw": 0.0, "unserved_mw": 0.0,
		"charge_mw": 0.0, "discharge_mw": 0.0, "energy_mwh": 5.0, "soc": 0.5,
		"curtailed_mw": 0.0, "export_mw": 0.0, "loss_mw": 0.0,
		"boiler_electric_mw": 2.0, "boiler_conversion_loss_mw": 0.04,
		"thermal": {"demand_mwth": 2.0, "served_mwth": served, "unserved_mwth": 2.0 - served,
			"boiler_heat_mwth": 1.96, "charge_mwth": 0.0, "discharge_mwth": 0.0,
			"energy_mwhth": inventory, "soc": inventory / 4.0, "network_loss_mwth": 0.0,
			"exchanger_loss_mwth": 0.0392, "storage_conversion_loss_mwth": 0.0,
			"self_discharge_mwhth": 0.001, "balance_error_mwth": 0.0, "energy_balance_error_mwhth": 0.0},
		"devices": {"4": {"kind": "electric_boiler", "electric_input_mw": 2.0, "heat_output_mwth": 1.96, "conversion_loss_mw": 0.04},
			"5": {"kind": "thermal_store", "energy_before_mwhth": inventory + 0.001, "energy_mwhth": inventory, "charge_mwth": 0.0, "discharge_mwth": 0.0, "self_discharge_mwhth": 0.001, "soc": inventory / 4.0, "mode": "idle"},
			"6": {"kind": "heat_exchanger", "input_mwth": 1.96, "output_mwth": 1.9208, "loss_mwth": 0.0392},
			"7": {"kind": "heat_demand", "demand_mwth": 2.0, "served_mwth": served, "unserved_mwth": 2.0 - served}}}

func run() -> void:
	var panel = OptimizationPanel.new()
	root.add_child(panel)
	panel.open()
	panel.set_thermal_context(true)
	await process_frame
	check(panel._thermal_settings.visible, "thermal scene exposes independent heat controls")
	check(panel.get_options().heat_service_weight == 1.0 and panel.get_options().terminal_heat_soc_fraction == null, "heat options have documented defaults")
	panel.configure({"terminal_soc_fraction": 0.2, "terminal_heat_soc_fraction": 0.75, "heat_service_weight": 1.5})
	check(panel.get_options().terminal_soc_fraction == 0.2 and panel.get_options().terminal_heat_soc_fraction == 0.75, "electric and thermal terminal constraints stay independent")
	check(panel.get_options().heat_service_weight == 1.5, "teaching heat service weight can be configured")
	check(panel._heat_weight.tooltip_text.contains("非价格") and panel._strict.text.contains("电热"), "weight is not price and strict supply covers both carriers")
	panel.set_busy(true)
	check(not panel._terminal_heat.editable and not panel._heat_weight.editable and panel._terminal_heat_enabled.disabled, "busy freezes heat controls")
	panel.set_busy(false)
	check(panel._terminal_heat.editable and panel._heat_weight.editable, "heat controls restore after solve")
	var rows := [thermal_row(7200, 0.5, 1.9208, 1.0), thermal_row(9000, 0.25, 1.0, 0.5)]
	var result := {"status": "optimal", "steps": rows}
	var baseline := result.duplicate(true)
	baseline.steps[0].thermal.served_mwth = 1.0
	baseline.steps[0].thermal.energy_mwhth = 0.25
	panel.show_result(result, baseline)
	await process_frame
	check(panel._thermal_chart._unit == "MWth" and panel._power_chart._unit == "MW", "heat and electricity use separate power axes")
	check(panel._thermal_energy_chart._unit == "MWhth", "thermal inventory has its own energy unit")
	check(panel._thermal_soc_chart._fixed_max == 100.0 and panel._soc_chart._fixed_max == 100.0, "thermal and electric SOC have independent percentage charts")
	check(panel._thermal_chart._series_value(panel._thermal_chart._steps[0], "thermal.served_mwth") == 1.9208, "nested heat ledger draws directly")
	check(panel._thermal_chart._series_value(panel._thermal_chart._steps[0], "baseline_thermal.served_mwth") == 1.0, "matching baseline overlays supply curve")
	check(panel._thermal_energy_chart._series_value(panel._thermal_energy_chart._steps[0], "baseline_thermal.energy_mwhth") == 0.25, "matching baseline overlays thermal inventory")
	check(panel._thermal_chart._series_value(rows[0], "thermal.missing") == null, "missing thermal values never become zero")
	check(is_equal_approx(panel._thermal_total(rows, "served_mwth"), 1.2104), "heat integral uses true irregular timestep durations")
	check(is_equal_approx(panel._thermal_total(rows, "self_discharge_mwhth", false), 0.002), "self-discharge energy is summed without multiplying dt again")
	check(panel._detail.text.contains("1.960 MWth") and panel._detail.text.contains("0.980 MWhth"), "thermal timestep details show power and integrated heat")
	check(panel._detail.text.contains("锅炉电输入") and panel._detail.text.contains("0.040 MW"), "boiler electricity and conversion loss remain explicit")
	check(panel._detail.text.contains("90/60 → 70/40°C") and panel._detail.text.contains("热库存"), "device details include grades and thermal inventory")
	check(panel._detail.text.contains("同一时段基线") and panel._detail.text.contains("0.250 MWhth"), "details compare actual baseline heat inventory")
	check(panel._comparison_note.text.contains("非价格") and panel._comparison_note.text.contains("不强制"), "comparison discloses weight and baseline terminal differences")
	check(panel._comparison.get_child_count() > 36, "thermal comparison adds separate ledger rows")
	check(panel._selection.text.contains("电池 5.000 MWh") and panel._selection.text.contains("热储 1.000 MWhth"), "selection does not merge electricity and heat inventories")
	panel._thermal_soc_chart._choose(1)
	check(panel._selected == 1 and panel._power_chart._selected == 1 and panel._thermal_energy_chart._selected == 1, "all chart selections synchronize")
	var malformed := baseline.duplicate(true)
	malformed.steps[0].time_s = 7000.0
	panel.show_result(result, malformed)
	check(not panel._thermal_chart._steps[0].has("baseline_thermal"), "misaligned heat baseline is never plotted")
	panel.show_result(result, {})
	check(not panel._thermal_energy_chart._steps[0].has("baseline_thermal"), "absent heat baseline does not create zero inventory curve")
	var incomplete := rows.duplicate(true)
	incomplete[0].thermal.erase("served_mwth")
	check(panel._thermal_total(incomplete, "served_mwth") == null, "incomplete heat total remains missing")
	panel.show_result(result, baseline)
	panel._heat_weight.value = 2.0
	check(panel._steps.is_empty() and panel._thermal_chart._steps.is_empty() and panel._thermal_soc_chart._steps.is_empty(), "changing heat weight invalidates all result curves")
	check(result.steps[0].thermal.energy_mwhth == 1.0 and not result.steps[0].has("baseline_thermal"), "plotting and stale clearing do not mutate original result")
	panel.show_result(result, baseline)
	panel.size = Vector2i(700, 580)
	await process_frame
	await process_frame
	check(panel._run.get_global_rect().end.x <= panel.size.x and panel._run.get_global_rect().end.y <= panel.size.y, "thermal controls retain reachable run button at minimum size")
	check(panel._tabs.size.y > 100.0, "thermal settings retain useful tab area at minimum size")
	panel._tabs.current_tab = panel._thermal_tab_index
	await process_frame
	check(not panel._tabs.get_child(panel._thermal_tab_index).get_h_scroll_bar().visible, "thermal chart tab requires no horizontal scrolling")
	panel.set_busy(true)
	panel._close()
	check(not panel.visible and panel._thermal_energy_chart._steps.is_empty(), "close during solve clears thermal chart too")
	panel.free()
	await test_controller()
	print("THERMAL_OPTIMIZATION_UI checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func test_controller() -> void:
	var game := Fixture.new()
	for entry in [[0, "wind"], [1, "station"], [2, "load"], [3, "battery"], [4, "electric_boiler"], [5, "thermal_store"], [6, "heat_exchanger"], [7, "heat_demand"], [8, "heat_demand"]]:
		var d := {"id": entry[0], "kind": entry[1], "params": Catalog.defaults(entry[1])}
		if entry[1] in ["battery", "thermal_store"]: d.state = Catalog.initial_state(entry[1], d.params)
		if Catalog.is_thermal(entry[1]): d.model_profile = Catalog.model_profile(entry[1])
		game.devices.append(d)
	game.devices[1].params.loss_fraction = 0.0
	game.devices[2].params.demand_mw = 0.1
	game.devices[5].state.energy_mwhth = 1.0
	game.devices[5].params.initial_soc = 0.9
	game.devices[7].params.demand_mwth = 2.0
	game.devices[8].params.demand_mwth = 0.0
	game.links = [{"from": 0, "to": 1, "capacity_mw": 4.0, "loss_fraction": 0.0},
		{"from": 1, "to": 2, "capacity_mw": 4.0, "loss_fraction": 0.0},
		{"from": 1, "to": 4, "from_port": "out", "to_port": "ac_in", "carrier": "electricity_ac", "unit": "MW", "capacity_mw": 4.0, "loss_fraction": 0.0},
		heat_line(4, 6, "heat_out", "hot_in", Catalog.PRIMARY_GRADE),
		heat_line(4, 5, "heat_out", "heat_in", Catalog.PRIMARY_GRADE),
		heat_line(5, 6, "heat_out", "hot_in", Catalog.PRIMARY_GRADE),
		heat_line(6, 7, "warm_out", "heat_in", Catalog.SECONDARY_GRADE)]
	root.add_child(game)
	var service = Controller.new()
	root.add_child(service)
	service.setup(game)
	service.open()
	check(service.panel._thermal_enabled, "opening thermal scene reveals thermal forecast controls")
	var options := {"horizon_hours": 1.0, "step_minutes": 30.0, "load_multiplier": 2.0, "timeout_s": 20, "strict_supply": false}
	var original := JSON.stringify({"devices": game.devices, "links": game.links})
	var snapshot: Dictionary = service.snapshot(options)
	check(not snapshot.has("error"), "thermal snapshot validates connected topology")
	if snapshot.has("error"):
		push_error(str(snapshot.error))
		service.free(); game.free(); return
	check(snapshot.schema_version == 2 and snapshot.steps.size() == 2, "thermal snapshot uses schema2 and correct timesteps")
	check(snapshot.options.terminal_heat_soc_fraction == null and snapshot.options.heat_service_weight == 1.0, "controller fills schema2 heat defaults even for legacy option callers")
	check(snapshot.steps[0].heat_demand_mwth == {"7": 2.0, "8": 0.0}, "heat demand map includes exact complete ID set")
	check(snapshot.steps[0].demand_mw == {"2": 0.2}, "boiler is not exogenous electric demand; multiplier affects electric load only")
	check(snapshot.steps[1].heat_demand_mwth == snapshot.steps[0].heat_demand_mwth, "stage1 heat demand remains constant")
	check(snapshot.devices[5].state == {"energy_mwhth": 1.0}, "snapshot preserves actual heat inventory rather than initial_soc")
	snapshot.devices[5].state.energy_mwhth = 0.5
	check(game.devices[5].state.energy_mwhth == 1.0, "frozen thermal state is a deep copy")
	snapshot.devices[5].state.energy_mwhth = 1.0
	check(snapshot.devices[3].state.has("energy_mwh") and not snapshot.devices[3].state.has("energy_mwhth"), "battery state remains separate")
	check(snapshot.devices[4].model_profile == "thermal_stage1_v1", "snapshot carries thermal model profile")
	check(snapshot.forecast.heat_demand.contains("not supported"), "snapshot declares heat demand CSV unsupported")
	var base: Dictionary = service.make_baseline(snapshot)
	if base.has("error"): print("THERMAL_BASELINE_ERROR ", base.error)
	check(not base.has("error") and base.steps.size() == 2, "live strategy generates same-forecast heat baseline")
	if not base.has("error"):
		check(base.steps[0].thermal.has("energy_mwhth") and base.steps[0].has("boiler_electric_mw"), "baseline preserves independent heat ledger and boiler electric input")
		check(base.steps[0].energy_mwh == 5.0 and base.steps[0].thermal.energy_mwhth <= 1.0, "baseline does not mix thermal and battery inventory")
	check(JSON.stringify({"devices": game.devices, "links": game.links}) == original, "snapshot and baseline leave live scene unchanged")
	game.devices[5].state.energy_mwh = 1.0
	check(service.snapshot(options).has("error"), "heat inventory cannot silently carry an electric state field")
	game.devices[5].state.erase("energy_mwh")
	game.devices[4].state = {"energy_mwhth": 1.0}
	check(service.snapshot(options).has("error"), "stateless thermal device cannot smuggle runtime inventory")
	game.devices[4].erase("state")
	var invalid := options.duplicate(true)
	for target in [-0.01, 1.01, NAN, true]:
		invalid.terminal_heat_soc_fraction = target
		check(service.snapshot(invalid).has("error"), "invalid thermal terminal target rejected")
	invalid = options.duplicate(true)
	for weight in [0.0, -1.0, INF, true]:
		invalid.heat_service_weight = weight
		check(service.snapshot(invalid).has("error"), "invalid thermal service weight rejected")
	service.solver_executable = "/workspace/shared/glpk/bin/glpsol"
	service.panel.configure(options)
	service.start(options)
	check(service.pid > 0, "thermal solve starts asynchronously")
	var deadline := Time.get_ticks_msec() + 30000
	while service.pid > 0 and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	check(service.pid < 0 and service.last_result.get("status") == "optimal", "real GLPK thermal result reaches optimal")
	check(service.last_result.get("validation", {}).get("valid", false), "real thermal result passes independent audit")
	if not service.last_result.is_empty():
		check(service.panel._thermal_chart._steps.size() == 2 and service.panel._detail.text.contains("MWhth"), "real thermal result reaches graph and detail")
		check(service.last_result.steps[0].thermal.demand_mwth == 2.0, "real solver reports constant heat demand")
		await capture_panel(service.panel)
	check(JSON.stringify({"devices": game.devices, "links": game.links}) == original, "real optimization never writes live thermal state")
	game.scene_revision += 1
	await create_timer(0.05).timeout
	check(service.last_result.is_empty() and service.panel._thermal_chart._steps.is_empty(), "scene revision invalidates heat forecast")
	var strict_options := options.duplicate(true)
	strict_options.strict_supply = true
	service.start(strict_options)
	await finish_solver(service)
	check(service.last_result.is_empty() and service.panel._error.text.contains("无可行解"), "strict heat supply infeasibility is shown without stale plots")
	var terminal_options := options.duplicate(true)
	terminal_options.terminal_heat_soc_fraction = 1.0
	service.start(terminal_options)
	await finish_solver(service)
	check(service.last_result.is_empty() and service.panel._error.text.contains("无可行解"), "unreachable thermal terminal inventory is not silently ignored")
	service.start(options)
	service.cancel()
	await finish_solver(service)
	check(service.last_result.is_empty() and service.panel._thermal_energy_chart._steps.is_empty(), "cancelling thermal solve never exposes old heat inventory")
	check(JSON.stringify({"devices": game.devices, "links": game.links}) == original, "infeasible and cancelled heat tasks leave live state intact")
	service.free()
	game.free()

func finish_solver(service: Node) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while service.pid > 0 and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	check(service.pid < 0, "thermal solver process terminates")

func capture_panel(panel: Window) -> void:
	var directory := OS.get_environment("BASIN_CAPTURE_THERMAL_UI_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(directory)
	panel.size = Vector2i(1000, 740)
	for item in [[0, "electric"], [panel._thermal_tab_index, "heat"], [1, "comparison"], [2, "detail"]]:
		panel._tabs.current_tab = item[0]
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		check(panel.get_texture().get_image().save_png(directory.path_join("thermal_glpk_" + item[1] + ".png")) == OK, "real thermal GLPK panel screenshot saved")
	for item in [[1, "comparison_heat", 10000], [2, "detail_heat", 350], [2, "detail_devices", 10000]]:
		panel._tabs.current_tab = item[0]
		panel._tabs.get_child(item[0]).scroll_vertical = item[2]
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		panel.get_texture().get_image().save_png(directory.path_join("thermal_glpk_" + item[1] + ".png"))
	panel._tabs.current_tab = panel._thermal_tab_index
	panel._tabs.get_child(panel._thermal_tab_index).scroll_vertical = 10000
	await process_frame
	await RenderingServer.frame_post_draw
	panel.get_texture().get_image().save_png(directory.path_join("thermal_glpk_inventory.png"))
	panel.size = Vector2i(700, 580)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	panel.get_texture().get_image().save_png(directory.path_join("thermal_glpk_minimum.png"))

func heat_line(a: int, b: int, out_port: String, in_port: String, grade: String) -> Dictionary:
	return {"from": a, "to": b, "from_port": out_port, "to_port": in_port, "carrier": "heat_water", "unit": "MWth", "grade_id": grade, "capacity_mwth": 4.0, "loss_fraction": 0.0}
