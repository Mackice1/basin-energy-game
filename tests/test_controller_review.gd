extends SceneTree
## Integration regressions for load validation, source priority, time and footprint.
## Does not boot the expensive terrain/UI or mutate user save slots.
class ReviewController:
	extends "res://scripts/world_game.gd"
	var last_notice := ""
	func _ready(): pass
	func tell(message: String): last_notice = message
	func exclusion(_x: float, _z: float) -> String: return ""
	func slope_at(_x: float, _z: float) -> float: return 0.0
	func height_at(_x: float, _z: float) -> float: return 0.0
	func rebuild_equipment(): pass
	func update_status(): pass

var checks := 0
var failures: Array[String] = []
var game: ReviewController

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("REVIEW_FAIL: ", label)

func _initialize(): call_deferred("_run")

func series(field: String, target: String, first: float, last: float, value: float) -> Dictionary:
	var unit: String = {"power":"kW", "wind_ms":"m/s", "temp_c":"C", "irradiance_wm2":"W/m2"}[field]
	return game.Series.parse("time,value\n%s,%s\n%s,%s" % [first, value, last, value], {"time_column":"time", "value_column":"value", "time_unit":"s", "value_unit":unit,"field":field,"target_device":target}).series

func base_state() -> Dictionary:
	return {"schema":3,"model_version":11,"devices":[{"id":0,"kind":"wind","x":0.0,"z":0.0,"params":game.model.defaults("wind")}],"links":[],"templates":{"wind":game.templates.wind.duplicate(true),"pv":game.templates.pv.duplicate(true),"station":game.templates.station.duplicate(true)},"imports":[],"next_id":1,"elapsed_s":0.0,"energy":{"generated":0.0,"delivered":0.0,"curtailed":0.0,"loss":0.0},"physical_lines":true}

func _run():
	game = ReviewController.new()
	game.cfg = {"max_build_slope_degrees":8.0}
	for kind in ["wind","pv","station"]: game.templates[kind] = game.model.defaults(kind)
	game.devices = base_state().devices
	game.next_id = 1
	game.imports = [series("wind_ms","",0,100,0), series("wind_ms","0",0,100,20), series("power","0",0,100,3000)]
	var solved: Dictionary = game.solve_at(0)
	check(is_equal_approx(solved.generated_mw,3.0), "direct power overrides device and global weather without addition")
	game.imports.pop_back()
	solved = game.solve_at(0)
	check(is_equal_approx(solved.generated_mw,5.0), "device weather overrides global weather")
	game.imports.pop_back()
	solved = game.solve_at(0)
	check(is_zero_approx(solved.generated_mw), "global weather overrides built-in weather")
	game.devices.append({"id":1,"kind":"pv","x":20.0,"z":0.0,"params":game.model.defaults("pv")})
	game.imports = [series("irradiance_wm2","",0,100,500)]
	solved = game.solve_at(0)
	check(game.sources["0"] == "内置模型" and game.sources["1"] == "CSV 气象 → 物理模型", "irrelevant irradiance does not relabel wind source")
	game.devices.pop_back()
	game.imports = [series("power","0",0,0.5,1000)]
	game.elapsed_s = 0
	game.energy = {"generated":0.0,"delivered":0.0,"curtailed":0.0,"loss":0.0}
	check(not game.advance(1.0) and is_equal_approx(game.elapsed_s,0.5), "fractional endpoint tail integrated before pause")
	check(is_equal_approx(game.energy.generated,0.5/3600.0), "fractional endpoint energy accounted exactly")
	game.apply_import(series("power","0",10,20,1000))
	check(game.solve_at(game.elapsed_s).error == "", "positive-start imported dataset leaves simulation at a usable time")

	var fixture := base_state()
	check(game.validate_state(fixture) == "", "valid controller save accepted")
	fixture.next_id = 0
	check(game.validate_state(fixture) != "", "next id cannot collide with restored equipment")
	fixture = base_state(); fixture.devices[0].id = 0.5
	check(game.validate_state(fixture) != "", "fractional device id rejected")
	fixture = base_state(); fixture.links = [{"from":0,"to":-1,"capacity_mw":4.0,"loss_fraction":0.02}]
	check(game.validate_state(fixture) != "", "generator-to-grid shortcut rejected on load")
	fixture = base_state(); fixture.imports = [{"samples":[{"t":0.0,"value":3.0},{"t":1.0,"value":4.0}]}]
	check(game.validate_state(fixture) != "", "series missing metadata rejected before restore")
	fixture = base_state(); fixture.imports = [series("power","0",0,10,1000)]; fixture.imports[0].field = "bogus"
	check(game.validate_state(fixture) != "", "unsupported imported field rejected")
	fixture = base_state(); fixture.imports = [series("power","999",0,10,1000)]
	check(game.validate_state(fixture) != "", "orphan imported target rejected")
	fixture = base_state(); fixture.imports = [series("power","0",0,10,1000)]; fixture.imports[0].samples.insert(1,{"t":11.0,"value":1000.0})
	check(game.validate_state(fixture) != "", "interior sample ordering validated")
	fixture = base_state(); fixture.imports = [series("power","0",0,10,1000)]; fixture.imports[0].samples[0].value = -1
	check(game.validate_state(fixture) != "", "saved series bounds revalidated")
	fixture = base_state(); fixture.imports = [series("power","0",0,10,1000)]; fixture.imports[0].end_s = 20.0
	check(game.validate_state(fixture) != "", "declared imported range must match actual samples")

	game.devices = base_state().devices
	game.devices[0].params.rotor_diameter_m = 300.0
	game.devices[0].params.hub_height_m = 200.0
	check(game.can_place("wind", Vector2(20,0)) != "", "existing enlarged rotor included in collision screening")
	game.devices = []
	game.templates.wind.rotor_diameter_m = 300.0
	game.templates.wind.hub_height_m = 200.0
	check(game.can_place("wind", Vector2(80,0)) != "", "enlarged template rotor included in boundary screening")
	print("CONTROLLER_REVIEW checks=", checks, " failures=", failures.size())
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables","confirmation","param_dialog","param_editor","param_errors","param_target","data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice"]:
		var node = game.get(key)
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	game.free()
	quit(0 if failures.is_empty() else 1)
