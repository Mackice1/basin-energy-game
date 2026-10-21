extends SceneTree
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
	var save_path := ProjectSettings.globalize_path("res://evidence/solar_stage/native_mouse_state.json")
	var saved := FileAccess.get_file_as_bytes(save_path)
	check(game.read_save(save_path),"new process reads native F10 save")
	check(game.solar_energy.useful_mwhth>0,"saved native runtime solar history nonzero")
	check(game.result.get("valid",false),"restored solar dispatch valid")
	var frozen := var_to_bytes(game.state())
	var revision := game.scene_revision
	var undo := var_to_bytes(game.undo_states)
	var service := Optimization.new()
	root.add_child(service); service.setup(game)
	service.solver_executable = "/workspace/shared/glpk/bin/glpsol"
	var options := {"horizon_hours": 1.0, "step_minutes": 30.0, "load_multiplier": 1.0, "timeout_s": 20, "strict_supply": false}
	var snapshot: Dictionary = service.snapshot(options)
	check(not snapshot.has("error"), "read-save solar snapshot validates: " + str(snapshot.get("error", "")))
	if not snapshot.has("error"):
		check(snapshot.schema_version == 3 and snapshot.devices.size() == 8 and snapshot.links.size() == game.links.size(), "new catalog3 snapshot includes each physical device/link once")
		check(snapshot.devices.all(func(d): return d.kind != "thermal_station"), "station facade adds no physical capacity")
		check(snapshot.fuel_supply == game.fuel_supply, "read-save resource config reaches optimizer unchanged")
		service.start(options)
		check(service.pid > 0, "actual read-save scene launches real GLPK")
		var deadline := Time.get_ticks_msec() + 25000
		while service.pid > 0 and Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout
		check(service.pid < 0, "real world solver terminates")
		check(service.last_result.get("status") == "optimal", "actual read-save solar scene optimizes successfully: " + service.panel._error.text)
		check(service.last_result.get("validation", {}).get("valid", false), "actual read-save result passes independent audit")
		if not service.last_result.is_empty():
			check(service.last_result.schema_version == 3 and service.last_result.totals.solar.useful_mwhth > 0, "actual solar result uses POA and schema3")
	check(var_to_bytes(game.state()) == frozen, "optimization leaves every serialized world field byte-identical after read-save")
	check(game.scene_revision == revision and var_to_bytes(game.undo_states) == undo, "optimization leaves revision and undo history unchanged")
	check(FileAccess.get_file_as_bytes(save_path) == saved, "optimization leaves real save-slot bytes untouched")
	var evidence:=FileAccess.open("res://evidence/solar_stage/native_restart_optimization.json",FileAccess.WRITE)
	evidence.store_string(JSON.stringify({"request":service.request,"result":service.last_result,"baseline":service.baseline,"checks":checks,"failures":failures},"  "));evidence.close()
	service.free()
	for key in ["camera", "lod_camera", "terrain", "labels", "infrastructure", "selection", "overlay", "equipment", "cables", "confirmation", "param_dialog", "param_errors", "param_target", "data_dialog", "data_list", "line_dialog", "line_capacity", "line_loss", "line_choice", "station_interior"]:
		var node = game.get(key)
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	game.free()
	print("SOLAR_OPTIMIZER_NATIVE_RESTART checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
