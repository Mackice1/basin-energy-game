extends SceneTree
## Real GLPK controller boundary, fuel presentation and immutable world/save data.
const Controller = preload("res://scripts/optimization_controller.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const FuelSupply = preload("res://scripts/fuel_supply.gd")

class Fixture:
	extends Node
	var devices: Array = []
	var links: Array = []
	var imports: Array = []
	var elapsed_s := 7200.0
	var scene_revision := 3
	var climate_config: Dictionary = {"seed": 17}
	var paused := true
	var fuel_supply: Dictionary = FuelSupply.defaults()
	var fuel_energy: Dictionary = FuelSupply.initial_energy()
	func update_status() -> void: pass
	func common_interval(_imports: Array) -> Dictionary: return {"start": 0.0, "end": 1000000.0}
	func active_series() -> Array: return []
	func sampled(_time: float) -> Dictionary:
		return {"error": "", "weather": {}, "device_weather": {}, "sources": [], "direct": {"0": {"mw": 2.0}}}
	func state() -> Dictionary:
		return {"devices": devices, "links": links, "imports": imports, "elapsed_s": elapsed_s,
			"scene_revision": scene_revision, "climate_config": climate_config,
			"fuel_supply": fuel_supply, "fuel_energy": fuel_energy, "paused": paused}

var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
func _initialize() -> void: call_deferred("run")

func heat_line(a: int, b: int, source_port: String, target_port: String, grade: String) -> Dictionary:
	return {"from": a, "to": b, "from_port": source_port, "to_port": target_port,
		"carrier": "heat_water", "unit": "MWth", "grade_id": grade, "capacity_mwth": 4.0, "loss_fraction": 0.0}

func run() -> void:
	var game := Fixture.new()
	for entry in [[0, "wind"], [1, "station"], [2, "fuel_boiler"], [3, "heat_exchanger"], [4, "heat_demand"], [5, "battery"], [6, "thermal_store"]]:
		var d := {"id": entry[0], "kind": entry[1], "params": Catalog.defaults(entry[1])}
		if entry[1] in ["battery", "thermal_store"]: d.state = Catalog.initial_state(entry[1], d.params)
		if Catalog.is_thermal(entry[1]):
			d.model_profile = Catalog.model_profile(entry[1]); d.model_profile_version = 1
		game.devices.append(d)
	game.devices[1].params.loss_fraction = 0.0
	game.devices[4].params.demand_mwth = 2.0
	game.devices[5].state.energy_mwh = 3.0
	game.devices[6].state.energy_mwhth = 1.0
	game.fuel_supply.enabled = true
	game.fuel_supply.max_input_mw = 0.5
	game.fuel_energy = {"input_mwh": 1.0, "volume_nm3": 100.0, "cost": 300.0, "heat_output_mwhth": 0.9, "conversion_loss_mwh": 0.1, "auxiliary_mwh": 0.01}
	game.links = [{"from": 0, "to": 1, "capacity_mw": 4.0, "loss_fraction": 0.0},
		{"from": 1, "to": 2, "from_port": "out", "to_port": "ac_in", "carrier": "electricity_ac", "unit": "MW", "capacity_mw": 4.0, "loss_fraction": 0.0},
		heat_line(2, 3, "heat_out", "hot_in", Catalog.PRIMARY_GRADE),
		heat_line(3, 4, "warm_out", "heat_in", Catalog.SECONDARY_GRADE)]
	root.add_child(game)
	var service = Controller.new()
	root.add_child(service)
	service.setup(game)
	service.solver_executable = "/workspace/shared/glpk/bin/glpsol"
	service.open()
	var options := {"horizon_hours": 1.0, "step_minutes": 30.0, "load_multiplier": 1.0, "timeout_s": 20, "strict_supply": false}
	var original := JSON.stringify(game.state())
	var saved_path := "user://fuel_forecast_untouched_save.json"
	var save := FileAccess.open(saved_path, FileAccess.WRITE)
	save.store_string(original); save.close()
	var original_bytes := FileAccess.get_file_as_bytes(saved_path)
	var snapshot: Dictionary = service.snapshot(options)
	check(not snapshot.has("error"), "fuel snapshot validates")
	if snapshot.has("error"):
		service.free(); game.free(); finish(); return
	check(snapshot.schema_version == 3 and snapshot.schema_version == Catalog.SCHEMA_VERSION, "new fuel forecast uses current catalog3 schema")
	check(snapshot.fuel_supply == game.fuel_supply, "forecast freezes explicit shared resource")
	check(snapshot.devices[2].model_profile == "thermal_stage1_v1", "fuel boiler carries established hot-water profile")
	check(snapshot.steps[0].demand_mw.is_empty(), "auxiliary remains endogenous, not external demand")
	snapshot.fuel_supply.max_input_mw = 0.25
	check(game.fuel_supply.max_input_mw == 0.5, "fuel supply snapshot is a deep copy")
	snapshot.fuel_supply.max_input_mw = 0.5
	var base: Dictionary = service.make_baseline(snapshot)
	check(not base.has("error"), "same-resource realtime baseline succeeds")
	if base.has("error"):
		push_error(str(base.error)); service.free(); game.free(); finish(); return
	check(base.steps[0].has("fuel") and is_equal_approx(float(base.steps[0].fuel.input_mw), 0.5), "baseline uses frozen shared fuel limit")
	check(JSON.stringify(game.state()) == original, "snapshot and baseline preserve entire fixture state")
	service.start(options)
	check(service.pid > 0, "fuel forecast launches real asynchronous GLPK")
	var deadline := Time.get_ticks_msec() + 25000
	while service.pid > 0 and Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout
	check(service.pid < 0, "fuel solver completes")
	check(service.last_result.get("status") == "optimal", "fuel GLPK result is proven optimal")
	check(service.last_result.get("validation", {}).get("valid", false), "fuel result passes independent audit")
	if not service.last_result.is_empty():
		check(service.last_result.schema_version == snapshot.schema_version, "real solver echoes new fuel schema3")
		check(service.last_result.objective.completed_stages == 5, "fuel cost is fifth lexicographic objective")
		var row: Dictionary = service.last_result.steps[0]
		check(is_equal_approx(float(row.fuel.input_mw), 0.5) and is_equal_approx(float(row.fuel.auxiliary_electric_mw), 0.005), "result preserves explicit fuel/auxiliary coupling")
		check(row.boiler_electric_mw == 0.0 and row.thermal.boiler_heat_mwth == 0.0, "electric boiler ledger remains separate")
		check(service.panel._detail.text.contains("MW LHV") and service.panel._detail.text.contains("Nm³") and service.panel._detail.text.contains("CNY"), "details expose fuel energy, volume and money units")
		check(service.panel._detail.text.contains("辅机散热") and service.panel._detail.text.contains("不加到有用热量"), "auxiliary dissipation cannot be mistaken for useful heat")
		check(service.panel._comparison_note.text.contains("教学假设") and service.panel._comparison_note.text.contains("非经济最优"), "comparison discloses teaching cost and objective limit")
		check(is_equal_approx(float(service.panel._fuel_total(service.last_result.steps, "cost_per_h")), 150.0), "fuel cost integrates timestep durations")
		check(service.panel._power_chart._series_value(row, "fuel.auxiliary_electric_mw") == row.fuel.auxiliary_electric_mw, "AC chart shows actual auxiliary load")
		check(service.panel._thermal_chart._series_value(row, "fuel.heat_output_mwth") == row.fuel.heat_output_mwth, "thermal chart shows separate fuel heat")
		check(service.panel._selection.text.contains("教学费用"), "selected interval discloses fuel cost")
		service.panel.size = Vector2i(700, 580)
		await process_frame; await process_frame
		check(service.panel._run.get_global_rect().end.x <= service.panel.size.x and service.panel._run.get_global_rect().end.y <= service.panel.size.y, "fuel context keeps solve button reachable at minimum size")
		check(service.panel._power_chart._plot.size.y > 50, "fuel legend leaves a usable chart plot")
	check(JSON.stringify(game.state()) == original, "optimization and presentation preserve all world data and accumulated fuel ledger")
	check(FileAccess.get_file_as_bytes(saved_path) == original_bytes, "forecast never rewrites saved bytes")
	service.panel.mark_stale()
	check(service.panel._steps.is_empty(), "stale fuel results clear normally")
	check(JSON.stringify(game.state()) == original, "stale clearing leaves live state untouched")
	service.free(); game.free()
	finish()

func finish() -> void:
	print("FUEL_OPTIMIZATION_UI checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
