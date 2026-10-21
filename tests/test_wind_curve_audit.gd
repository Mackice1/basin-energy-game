extends SceneTree
## Independent numerical + persistence audit. Does not drive or start the GUI.
const Model = preload("res://scripts/energy_model.gd")
const Validator = preload("res://scripts/save_validator.gd")
const Form = preload("res://scripts/parameter_form.gd")

class AuditController:
	extends "res://scripts/world_game.gd"
	var last_notice := ""
	func _ready(): pass
	func tell(message: String): last_notice = message
	func exclusion(_x: float, _z: float) -> String: return ""
	func slope_at(_x: float, _z: float) -> float: return 0.0
	func height_at(_x: float, _z: float) -> float: return 0.0
	func rebuild_equipment(): pass
	func update_status(): pass


	# Explicit historical data setup, NOT a replacement for the production build
	# API. Legacy UI construction is now rejected; these fixtures retain their
	# old ratings/coordinates and no site_geometry_profile for ledger/save tests.
	func append_legacy_device(kind:String, at:Vector2, record:bool=true, parent_id:int=-1)->bool:
		if record: checkpoint()
		var id:int=next_id
		while not station(id).is_empty() or not device(id).is_empty(): id+=1
		var values:Dictionary=templates[kind].duplicate(true)
		var item:Dictionary={"id":id,"kind":kind,"x":at.x,"z":at.y,"params":values,"state":Catalog.initial_state(kind,values)}
		if kind in THERMAL_KINDS:item.model_profile=Catalog.model_profile(kind)
		if parent_id>=0:
			var parent:Dictionary=station(parent_id)
			item.x=parent.x;item.z=parent.z;item.parent_station_id=parent_id
			item.interior_x=at.x;item.interior_z=at.y
		devices.append(item);selected_id=id;next_id=id+1;normalize_id_cursors();refresh()
		return true

var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("WIND_CURVE_AUDIT_FAIL: " + label)
func near(actual: float, expected: float, label: String, relative := 1.0e-10, absolute := 1.0e-12) -> void:
	check(is_finite(actual) and absf(actual - expected) <= maxf(absolute, absf(expected) * relative), label + " (actual " + str(actual) + ", expected " + str(expected) + ")")
func point(speed: float, power: float) -> Dictionary:
	return {"wind_mps": speed, "power_kw": power}
func params(curve: Array) -> Dictionary:
	var p: Dictionary = Model.defaults("wind")
	p.power_curve_kw = curve.duplicate(true)
	return p
func cp(speed: float, power_kw: float, p: Dictionary) -> float:
	return power_kw * 1000.0 / (0.5 * p.reference_air_density_kgm3 * PI * pow(p.rotor_diameter_m / 2.0, 2.0) * pow(speed, 3.0) * p.drivetrain_efficiency)
func output(p: Dictionary, speed: float, density := 1.225) -> Dictionary:
	return Model.generation("wind", p, {"wind_speed_mps": speed, "air_density_kgm3": density})
func _initialize(): call_deferred("_run")
func _run() -> void:
	_test_cp_extrema()
	_test_output_boundaries()
	_test_numeric_validation()
	_test_legacy()
	_test_state_and_form()
	await process_frame
	print("WIND_CURVE_AUDIT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_cp_extrema() -> void:
	# Both endpoints satisfy Cp <= .49, but the exact interior maximum does not.
	var bad: Dictionary = params([point(3.0, 0.0), point(6.0, 720.0)])
	check(cp(6.0, 720.0, bad) < bad.cp_max, "interior trap endpoint itself is below Cp cap")
	check(cp(4.5, 360.0, bad) > bad.cp_max, "interior trap analytical maximum is above Cp cap")
	var snapshot := JSON.stringify(bad)
	var errors: Array[String] = Model.validate("wind", bad)
	check(not errors.is_empty(), "endpoint-only physical false positive is rejected")
	check("interior" in " ".join(errors), "rejection diagnoses interior Cp violation")
	check(JSON.stringify(bad) == snapshot, "Cp validation never edits rejected curve")
	check(not output(bad, 4.5).valid, "generation refuses invalid curve instead of silently clamping it")
	near(output(bad, 4.5).mw, 0.0, "rejected curve supplies no output")
	var good: Dictionary = params([point(3.0, 0.0), point(6.0, 600.0), point(10.0, 600.0), point(15.0, 0.0)])
	check(Model.validate("wind", good).is_empty(), "rising/flat/falling valid curve accepted")
	for i in range(300, 1501):
		var speed: float = float(i) / 100.0
		var g: Dictionary = output(good, speed)
		check(g.valid and g.mw >= 0.0 and g.cp_aero <= good.cp_max + 1.0e-9, "dense output scan respects full physical envelope %.2f" % speed)
	var zero_rise: Dictionary = params([point(0.0, 0.0), point(1.0, 0.001)])
	zero_rise.cut_in_mps = 0.0
	check(not Model.validate("wind", zero_rise).is_empty(), "positive linear rise immediately from zero rejected as unbounded Cp")
	var delayed_rise: Dictionary = params([point(0.0, 0.0), point(1.0, 0.0), point(2.0, 1.0)])
	delayed_rise.cut_in_mps = 0.0
	check(Model.validate("wind", delayed_rise).is_empty(), "zero-power interval before first positive curve segment accepted")
	near(output(delayed_rise, 0.0).mw, 0.0, "zero wind no power")
	var tiny: Dictionary = params([point(0.0001, 0.0), point(0.0002, 0.000000000001)])
	tiny.cut_in_mps = 0.0
	check(Model.validate("wind", tiny).is_empty(), "physically valid near-zero curve accepted")
	var tiny_g: Dictionary = output(tiny, 0.00015)
	near(tiny_g.mw, 5.0e-16, "near-zero curve is not silently zeroed", 1.0e-10, 1.0e-24)
	near(tiny_g.cp_aero, cp(0.00015, 0.5e-12, tiny), "near-zero Cp metadata remains physically accurate", 1.0e-10, 1.0e-12)
	# Test exact limiting curve at the analytically known interior maximum.
	var coefficient: float = cp(4.5, 0.5, good)
	var limit_power: float = good.cp_max / coefficient
	var on_limit: Dictionary = params([point(3.0, 0.0), point(6.0, limit_power)])
	check(Model.validate("wind", on_limit).is_empty(), "analytic Cp equality accepted within numerical tolerance")
	on_limit.power_curve_kw[1].power_kw *= 1.000001
	check(not Model.validate("wind", on_limit).is_empty(), "slightly over interior limit rejected")
	var close: Dictionary = params([point(8.0, 100.0), point(8.000000000001, 101.0)])
	check(Model.validate("wind", close).is_empty(), "narrowly spaced finite points remain supported")
	near(output(close, 8.0).mw, 0.1, "narrow segment left endpoint is exact")
	var underflow: Dictionary = params([point(3.0, 0.0), point(6.0, 0.0)])
	underflow.rotor_diameter_m = 1.0e-100
	underflow.drivetrain_efficiency = 1.0e-200
	check(Model.validate("wind", underflow).is_empty(), "all-zero curve remains valid with very small positive geometry/efficiency")
	var underflow_g: Dictionary = output(underflow, 4.0)
	near(underflow_g.cp_aero, 0.0, "underflowed zero-output Cp denominator never produces NaN")

func _test_output_boundaries() -> void:
	var p: Dictionary = params([point(4.0, 100.0), point(8.0, 500.0), point(20.0, 4000.0)])
	check(Model.validate("wind", p).is_empty(), "output fixture physically valid")
	for speed in [0.0, 2.999, 3.0, 3.999, 20.000001, 24.999, 25.0, 30.0]:
		near(output(p, speed).mw, 0.0, "operating/domain intersection boundary " + str(speed))
	near(output(p, 4.0).mw, 0.1, "domain first endpoint retained (possible onset discontinuity)")
	near(output(p, 6.0).mw, 0.3, "linear interpolated electrical power, no second efficiency factor")
	near(output(p, 8.0).mw, 0.5, "interior knot electrical power")
	near(output(p, 20.0).mw, 4.0, "domain final endpoint retained")
	near(output(p, 6.0, 0.9).mw, 0.3 * 0.9 / 1.225, "actual/reference air density scaling")
	var capped: Dictionary = output(p, 20.0, 2.0)
	near(capped.mw, 5.0, "actual density increase respects nameplate cap")
	near(capped.nameplate_clipped_mw, 4.0 * 2.0 / 1.225 - 5.0, "density clipping explicitly reported")
	var adjusted: Dictionary = p.duplicate(true)
	adjusted.reference_air_density_kgm3 = 1.0
	check(Model.validate("wind", adjusted).is_empty(), "alternate reference density accepted with feasible curve")
	near(output(adjusted, 6.0).mw, 0.3 * 1.225, "edited reference density is actually used")
	var altered_efficiency: Dictionary = p.duplicate(true)
	altered_efficiency.drivetrain_efficiency = 0.8
	check(Model.validate("wind", altered_efficiency).is_empty(), "alternate efficiency feasible fixture")
	near(output(altered_efficiency, 6.0).mw, 0.3, "efficiency affects validation but does not re-derate electrical curve")
	p.cut_in_mps = 6.0
	p.cut_out_mps = 15.0
	near(output(p, 5.999999).mw, 0.0, "below cut-in zero even within curve")
	near(output(p, 6.0).mw, 0.3, "cut-in inclusive even for positive curve onset")
	near(output(p, 15.0).mw, 0.0, "cut-out exclusive even within positive curve segment")
	check(output(p, 14.999999).mw > 0.0, "immediately before cut-out retains curve power")

func _test_numeric_validation() -> void:
	var valid: Dictionary = params([point(3.0, 0.0), point(6.0, 600.0)])
	for bad in [null, {}, "[]", true, [point(3.0, 0.0)]]:
		var p := valid.duplicate(true); p.power_curve_kw = bad
		check(not Model.validate("wind", p).is_empty(), "invalid curve container/count rejected: " + str(bad))
	for bad in [NAN, INF, -1.0, "6", true, null]:
		var p := valid.duplicate(true); p.power_curve_kw[1].wind_mps = bad
		check(not Model.validate("wind", p).is_empty(), "invalid wind knot rejected: " + str(bad))
		p = valid.duplicate(true); p.power_curve_kw[1].power_kw = bad
		check(not Model.validate("wind", p).is_empty(), "invalid electrical knot rejected: " + str(bad))
	for bad in [0.0, 0.49, 2.01, NAN, INF, "1.225", true, null]:
		var p := valid.duplicate(true); p.reference_air_density_kgm3 = bad
		check(not Model.validate("wind", p).is_empty(), "invalid reference density rejected: " + str(bad))
	for curve in [[point(3.0, 0.0), point(3.0, 1.0)], [point(6.0, 100.0), point(3.0, 0.0)], [point(3.0, 0.0), point(6.0, 5000.01)], [point(0.0, 1.0), point(6.0, 100.0)]]:
		check(not Model.validate("wind", params(curve)).is_empty(), "duplicate/reversed/above-rating/zero-wind power rejected")
	var unknown: Dictionary = valid.duplicate(true)
	unknown.power_curve_kw[1].power_mw = 0.6
	check(not Model.validate("wind", unknown).is_empty(), "unknown curve unit/key cannot silently pass")

func _test_legacy() -> void:
	var old: Dictionary = Model.defaults("wind")
	old.erase("reference_air_density_kgm3")
	old.erase("power_curve_kw")
	check(Model.validate("wind", old).is_empty(), "pre-restoration schema3 wind params still accepted")
	for density in [0.1, 0.9, 1.225, 2.0]:
		for speed in [0.0, 3.0, 3.1, 8.0, 11.4, 20.0, 25.0]:
			var a: Dictionary = output(old, speed, density)
			var b: Dictionary = output(Model.defaults("wind"), speed, density)
			near(a.mw, b.mw, "omitted fields exactly retain cubic behavior")
			check(a.curve_mode == "cubic", "omitted curve uses cubic mode")

func _test_state_and_form() -> void:
	var p: Dictionary = params([point(4.0, 100.0), point(8.0, 500.0), point(20.0, 4000.0)])
	var form = Form.new()
	form.set_parameters("wind", p)
	check(form.get_parameters() == p, "custom curve round-trips form unchanged")
	p.power_curve_kw[0].power_kw = 90.0
	near(form.get_parameters().power_curve_kw[0].power_kw, 100.0, "form owns deep copy of incoming curve")
	var returned: Dictionary = form.get_parameters()
	returned.power_curve_kw[0].power_kw = 80.0
	near(form.get_parameters().power_curve_kw[0].power_kw, 100.0, "get_parameters deep copy cannot mutate draft")
	var game = AuditController.new()
	game.cfg = {"max_build_slope_degrees": 8.0}
	for kind in ["wind", "pv", "station"]: game.templates[kind] = Model.defaults(kind)
	game.devices = [{"id": 0, "kind": "wind", "x": 0.0, "z": 0.0, "params": form.get_parameters()}]
	game.next_id = 1
	game.parameter_form = form
	game.param_scope = "device"
	game.parameter_id = 0
	game.selected_id = 0
	form._fields["reference_air_density_kgm3"].text = "1.0"
	near(game.devices[0].params.reference_air_density_kgm3, 1.225, "editing draft never alters live device")
	game.apply_parameters()
	near(game.devices[0].params.reference_air_density_kgm3, 1.0, "apply commits reference density")
	near(game.templates.wind.reference_air_density_kgm3, 1.225, "single device apply leaves template unchanged")
	check(game.devices[0].params.power_curve_kw.size() == 3, "apply retains custom curve")
	game.undo()
	near(game.devices[0].params.reference_air_density_kgm3, 1.225, "undo restores pre-apply density")
	near(game.devices[0].params.power_curve_kw[0].power_kw, 100.0, "undo restores deep curve snapshot")
	var s: Dictionary = game.state()
	s.devices[0].params.power_curve_kw[0].power_kw = 1.0
	near(game.devices[0].params.power_curve_kw[0].power_kw, 100.0, "state snapshot cannot mutate live nested curve")
	s = game.state()
	check(Validator.validate(s).is_empty(), "custom curve save validates")
	var wire: String = JSON.stringify(s)
	var decoded: Dictionary = JSON.parse_string(wire)
	check(Validator.validate(decoded).is_empty(), "custom curve JSON round trip validates")
	game.restore(decoded)
	decoded.devices[0].params.power_curve_kw[0].power_kw = 1.0
	near(game.devices[0].params.power_curve_kw[0].power_kw, 100.0, "restore separates live curve from input dictionary")
	var path := "user://wind_curve_audit/scene.json"
	check(game.write_save(path), "custom curve writes to isolated real save file")
	game.devices[0].params.power_curve_kw = []
	check(game.read_save(path), "custom curve reads from isolated real save file")
	check(game.devices[0].params.power_curve_kw.size() == 3, "file reload restores custom points")
	game.undo()
	check(game.devices[0].params.power_curve_kw.is_empty(), "read-save undo restores preceding empty curve")
	var old: Dictionary = game.state()
	old.devices[0].params.erase("reference_air_density_kgm3")
	old.devices[0].params.erase("power_curve_kw")
	old.templates.wind.erase("reference_air_density_kgm3")
	old.templates.wind.erase("power_curve_kw")
	check(Validator.validate(old).is_empty(), "old schema3 save missing both new fields validates")
	game.restore(old)
	check(game.solve_at(0.0).error == "", "old schema3 restored scene solves with defaults")
	game.devices[0].params = form.get_parameters()
	game.imports = [game.Series.parse("time,power\n0,700\n60,700", {"field": "power", "target_device": "0", "time_column": "time", "value_column": "power", "time_unit": "s", "value_unit": "kW"}).series]
	near(game.solve_at(0.0).generated_mw, 0.7, "CSV electrical output replaces custom curve and density model without addition")
	check(game.sources["0"] == "CSV 直接出力", "CSV overriding custom curve provenance is explicit")
	game.imports = [game.Series.parse("time,power\n0,0\n60,0", {"field": "power", "target_device": "0", "time_column": "time", "value_column": "power", "time_unit": "s", "value_unit": "kW"}).series]
	near(game.solve_at(0.0).generated_mw, 0.0, "explicit CSV zero suppresses positive custom curve")
	game.imports = []
	check(game.solve_at(0.0).generated_mw > 0.0, "removing direct CSV reveals custom model")
	# Bad saved curves are rejected atomically before replacing live state.
	var bad_save: Dictionary = game.state()
	bad_save.devices[0].params.power_curve_kw = [point(3.0, 0.0), point(6.0, 720.0)]
	bad_save.devices[0].params.reference_air_density_kgm3 = 1.225
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(bad_save)); f.close()
	var live_before: String = JSON.stringify(game.state())
	var undo_count: int = game.undo_states.size()
	check(not game.read_save(path), "Cp-invalid saved curve rejected before restore")
	check(JSON.stringify(game.state()) == live_before, "rejected read leaves all live scene state unchanged")
	check(game.undo_states.size() == undo_count, "rejected read does not add an undo snapshot")
	# Reopening a draft abandons edits; malformed pasted rows are not repaired.
	form.set_parameters("wind", game.devices[0].params)
	form._curve_editor.text = "3, 0\n6, 720"
	check(not form.get_validation_errors().is_empty(), "text editor reports analytic interior Cp failure")
	check(JSON.stringify(game.state()) == live_before, "bad curve draft does not alter scene")
	form.set_parameters("wind", game.devices[0].params)
	check(form.get_parameters() == game.devices[0].params, "reopened draft discards uncommitted curve changes")
	form._curve_editor.text = "4, 100, 7\n8, 500"
	check(not form.get_validation_errors().is_empty(), "extra CSV column in curve text is rejected")
	form.set_parameters("wind", game.devices[0].params)
	form._curve_editor.text = "4，100\n8，500\n20，4000"
	check(form.get_validation_errors().is_empty(), "Chinese comma point text is supported")
	form._curve_editor.text = ""
	check(form.get_parameters().power_curve_kw.is_empty(), "empty text deliberately selects legacy cubic")
	# Template application affects later instances and never aliases existing ones.
	form.set_parameters("wind", params([point(4.0, 80.0), point(8.0, 400.0), point(20.0, 3000.0)]))
	game.param_scope = "template"
	for kind in ["wind", "pv", "station"]: game.param_target.add_item(kind)
	game.param_target.select(0)
	game.apply_parameters()
	near(game.devices[0].params.power_curve_kw[0].power_kw, 100.0, "template application does not retroactively alter existing curve")
	check(not game.add_equipment("wind", Vector2(25.0, 0.0)), "legacy scene rejects new wind construction until migration")
	check(game.append_legacy_device("wind", Vector2(25.0, 0.0)), "historical fixture copies edited template curve")
	near(game.devices[1].params.power_curve_kw[0].power_kw, 80.0, "new instance inherits edited template curve")
	game.templates.wind.power_curve_kw[0].power_kw = 60.0
	near(game.devices[1].params.power_curve_kw[0].power_kw, 80.0, "new instance curve does not alias template")
	game.devices[1].params.power_curve_kw[0].power_kw = 50.0
	near(game.devices[0].params.power_curve_kw[0].power_kw, 100.0, "two devices never share nested curve points")
	game.undo()
	check(game.devices.size() == 1, "undo creation removes only added instance")
	near(game.templates.wind.power_curve_kw[0].power_kw, 80.0, "undo deep snapshot restores template before later mutation")
	form.free()
	for key in ["camera", "lod_camera", "terrain", "labels", "infrastructure", "selection", "overlay", "equipment", "cables", "confirmation", "param_dialog", "param_editor", "param_errors", "param_target", "data_dialog", "data_list", "line_dialog", "line_capacity", "line_loss", "line_choice"]:
		var node = game.get(key)
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	game.free()
