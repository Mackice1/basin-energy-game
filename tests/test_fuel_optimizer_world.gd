extends SceneTree
const CurrentWorldVersion = preload("res://scripts/world_game.gd")
## Actual world schema8 read-save -> isolated real-GLPK regression.
const ControllerTest = preload("res://tests/test_station_controller.gd")
const Optimization = preload("res://scripts/optimization_controller.gd")
class Host:
	extends ControllerTest.Fixture
	func _process(_delta: float) -> void: pass
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game := Host.new()
	game.cfg = {"max_build_slope_degrees": 8.0}
	game.dimension_profile = "metric_v1"
	game.booted = true
	for kind in game.KINDS: game.templates[kind] = game.model.defaults(kind)
	root.add_child(game)
	game.fuel_example()
	check(game.devices.size() == 9 and game.devices.filter(func(d): return d.kind == "fuel_boiler").size() == 1, "actual example builds exactly one fuel boiler")
	check(game.result.get("valid", false), "actual fuel example dispatch is valid")
	check(game.validate_state(game.state()).is_empty(), "actual fuel example passes complete save validation: " + game.validate_state(game.state()))
	check(game.advance(60.0), "actual world advances fuel ledger before save")
	check(float(game.fuel_energy.input_mwh) > 0, "preexisting fuel history is nonzero")
	var save_path := ProjectSettings.globalize_path("user://fuel_world_before_optimization.json")
	check(game.write_save(save_path), "actual world writes schema8 slot")
	var saved := FileAccess.get_file_as_bytes(save_path)
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	check(parsed.schema == CurrentWorldVersion.CURRENT_SAVE_SCHEMA and parsed.model_version == CurrentWorldVersion.CURRENT_MODEL_VERSION, "actual saved schema and model versions")
	check(game.read_save(save_path), "actual world reads its saved fuel state")
	check(game.paused and game.speed == 1.0, "read-save starts paused at speed one")
	var frozen := var_to_bytes(game.state())
	var revision := game.scene_revision
	var undo := var_to_bytes(game.undo_states)
	var service := Optimization.new()
	root.add_child(service); service.setup(game)
	service.solver_executable = (OS.get_environment("BASIN_GLPK") if not OS.get_environment("BASIN_GLPK").is_empty() else "glpsol")
	var options := {"horizon_hours": 1.0, "step_minutes": 30.0, "load_multiplier": 1.0, "timeout_s": 20, "strict_supply": false}
	var snapshot: Dictionary = service.snapshot(options)
	check(not snapshot.has("error"), "read-save fuel snapshot validates: " + str(snapshot.get("error", "")))
	if not snapshot.has("error"):
		check(snapshot.schema_version == 3 and snapshot.devices.size() == 9 and snapshot.links.size() == game.links.size(), "new catalog3 snapshot includes each physical device/link once")
		check(snapshot.devices.all(func(d): return d.kind != "thermal_station"), "station facade adds no physical capacity")
		check(snapshot.fuel_supply == game.fuel_supply, "read-save resource config reaches optimizer unchanged")
		service.start(options)
		check(service.pid > 0, "actual read-save scene launches real GLPK")
		var deadline := Time.get_ticks_msec() + 25000
		while service.pid > 0 and Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout
		check(service.pid < 0, "real world solver terminates")
		check(service.last_result.get("status") == "optimal", "actual read-save fuel scene optimizes successfully: " + service.panel._error.text)
		check(service.last_result.get("validation", {}).get("valid", false), "actual read-save result passes independent audit")
		if not service.last_result.is_empty():
			check(service.last_result.schema_version == 3 and service.last_result.totals.fuel.input_mwh > 0, "actual fuel result uses resource and schema3")
	check(var_to_bytes(game.state()) == frozen, "optimization leaves every serialized world field byte-identical after read-save")
	check(game.scene_revision == revision and var_to_bytes(game.undo_states) == undo, "optimization leaves revision and undo history unchanged")
	check(FileAccess.get_file_as_bytes(save_path) == saved, "optimization leaves real save-slot bytes untouched")
	service.free()
	for key in ["camera", "lod_camera", "terrain", "labels", "infrastructure", "selection", "overlay", "equipment", "cables", "confirmation", "param_dialog", "param_errors", "param_target", "data_dialog", "data_list", "line_dialog", "line_capacity", "line_loss", "line_choice", "station_interior"]:
		var node = game.get(key)
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	game.free()
	print("FUEL_OPTIMIZER_WORLD checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
