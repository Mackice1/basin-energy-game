extends SceneTree
const Series = preload("res://scripts/series_import.gd")
const Solar = preload("res://scripts/solar_thermal.gd")
var checks := 0
var failures: Array[String] = []
var game
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize() -> void:call_deferred("run")
func parse(field: String, unit: String, csv: String) -> Dictionary:
	return Series.parse(csv,{"time_column":"t","value_column":"value","time_unit":"s","value_unit":unit,"field":field,"target_device":""}).series
func run() -> void:
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.solar_example()
	var original:PackedByteArray=var_to_bytes(game.state())
	game.apply_import(parse("irradiance_wm2","W/m2","t,value\n0,800\n60,0\n120,1000\n3600,1000"))
	game.apply_import(parse("temp_c","C","t,value\n0,20\n60,20\n120,20\n3600,20"))
	check(game.validate_state(game.state()).is_empty(),"global CSV world validates")
	var r:Dictionary=game.solve_at(0)
	check(r.valid and absf(r.solar.available_mwth-.0162036825)<1e-10,"global POA/temp feed exact reference physics")
	check(game.solve_at(60).solar.available_mwth==0,"zero irradiance boundary stops collection")
	check(absf(game.solve_at(120).solar.available_mwth-.0209607825)<1e-10,"next boundary correct physical output")
	check(game.sampled(3601).error!="","no CSV extrapolation")
	var snapshot:Dictionary=game.optimization_controller.snapshot({"horizon_hours":1,"step_minutes":60})
	check(not snapshot.has("error") and snapshot.steps.size()==3,"forecast splits exactly at POA boundaries")
	check(snapshot.steps[0].weather.irradiance_wm2==800 and snapshot.steps[1].weather.irradiance_wm2==0,"frozen original POA")
	var baseline:Dictionary=game.optimization_controller.make_baseline(snapshot)
	check(not baseline.has("error") and absf(baseline.steps[0].solar.available_mwth-.0162036825)<1e-10,"baseline matches original CSV physics")
	game.advance(60)
	check(game.solar_energy.useful_mwhth>0 and game.solar_energy.auxiliary_mwh>0,"finite step records independent useful heat and pump")
	check(game.validate_state(game.state()).is_empty(),"CSV integral passes saved ledger balances")
	var original_csv:String=game.imports[0].source.original_csv
	var path="res://evidence/solar_stage/solar_csv_roundtrip.json"
	check(game.write_save(path),"CSV solar world saved")
	# Restore the checkpoint preceding temperature import, then before POA import.
	game.undo();game.undo()
	check(var_to_bytes(game.state())==original,"two import undos restore exact pre-import state")
	check(game.read_save(path),"CSV solar world loaded")
	check(game.imports[0].source.original_csv==original_csv,"CSV source preserved without source file")
	print("SOLAR_CSV_WORLD: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
