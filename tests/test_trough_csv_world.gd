extends SceneTree
const Series=preload("res://scripts/series_import.gd")
const High=preload("res://scripts/high_temp_thermal.gd")
var game
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func parse(field:String,unit:String,values:String)->Dictionary:
 return Series.parse("t,value\n"+values,{"time_column":"t","value_column":"value","time_unit":"s","value_unit":unit,"field":field,"target_device":""}).series
func _initialize():call_deferred("run")
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
 game.trough_example()
 var w:Dictionary=game.sampled(0).weather
 check(w.dni_source.contains("教学"),"explicit teaching DNI source")
 check(w.has("cloud_cover") and w.has("precipitation_mm_h"),"no CSV retains actual teaching cloud/rain for visuals")
 check(not str(w.source).contains("CSV"),"no CSV cannot claim measured source")
 var dni:float=w.dni_wm2
 game.apply_import(parse("irradiance_wm2","W/m2","0,0\n60,1000\n3600,1000"))
 check(is_equal_approx(game.sampled(0).weather.dni_wm2,dni),"POA cannot replace or scale DNI")
 check(game.sampled(0).weather.dni_source.contains("教学"),"POA-only CSV clearly retains teaching DNI")
 game.apply_import(parse("dni_wm2","W/m2","0,800\n60,0\n120,1000\n3600,1000"))
 check(game.sampled(0).weather.dni_source=="CSV DNI","explicit DNI source visible")
 check(game.sampled(0).weather.dni_wm2==800,"DNI exact CSV value")
 check(game.solve_at(0).high_temp.available_mwth>0,"DNI collector useful availability")
 check(game.solve_at(60).high_temp.available_mwth==0,"zero DNI boundary")
 check(game.sampled(3601).error!="","DNI not extrapolated")
 var snap:Dictionary=game.optimization_controller.snapshot({"horizon_hours":1,"step_minutes":60})
 check(not snap.has("error") and snap.steps.size()==3,"forecast splits DNI and POA boundaries")
 check(snap.steps[0].weather.dni_wm2==800 and snap.steps[1].weather.dni_wm2==0,"forecast freezes exact independent DNI")
 check(game.validate_state(game.state()).is_empty(),"DNI CSV save validates")
 var path="res://evidence/trough_stage/dni_csv_roundtrip.json"
 check(game.write_save(path),"save DNI source")
 game.undo()
 check(game.sampled(0).weather.dni_source.contains("教学"),"undo DNI returns explicit teaching source")
 check(game.read_save(path) and game.sampled(0).weather.dni_wm2==800,"reload original CSV without external file")
 print("TROUGH_CSV_WORLD checks=",checks," failures=",failures)
 quit(0 if failures==0 else 1)
