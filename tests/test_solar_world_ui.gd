extends SceneTree
const CurrentWorldVersion = preload("res://scripts/world_game.gd")
const SiteSupport = preload("res://scripts/site_layout_support.gd")
var game
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,caption:String):
 checks+=1
 if not ok:failures.append(caption);push_error(caption)
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1440,900)
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
 game.solar_example()
 check(game.device(3).kind=="solar_thermal","collector in example")
 check(game.result.get("valid",false),"example dispatch valid")
 check(game.state().schema == CurrentWorldVersion.CURRENT_SAVE_SCHEMA and game.state().model_version == CurrentWorldVersion.CURRENT_MODEL_VERSION,"new version")
 check(game.state().solar_energy.size()==7,"separate solar energy")
 check(game.connection_candidate(2,3).to==3,"aux input topology")
 check(game.connection_candidate(3,4).from_port=="heat_out","storage topology")
 check(game.connection_candidate(3,5).to_port=="hot_in","HX topology")
 check(game.can_place_internal(int(game.stations[0].id),"solar_thermal",Vector2(-.7,-.8),3)=="","example collector footprint")
 game.open_station(int(game.stations[0].id));await process_frame
 check(game.station_interior.tools.has("solar_thermal"),"build button")
 game.station_interior.selected_id=3;game.station_interior.refresh()
 check(game.station_interior.selected_label.text.contains("辅机"),"collector runtime detail")
 var form=load("res://scripts/parameter_form.gd").new();root.add_child(form)
 form.set_parameters("solar_thermal",game.device(3).params,true)
 check(form.get_validation_errors().is_empty(),"solar form valid")
 check(not form._fields.supply_temp_c.editable and not form._fields.return_temp_c.editable,"fixed temperatures read-only")
 for pair in [["optical_efficiency","0 < 值 ≤ 1"],["heat_loss_w_m2k","0 ≤ 值 ≤ 20"],["heat_loss_quadratic_w_m2k2","0 ≤ 值 ≤ 0.2"],["auxiliary_electric_ratio","0.001 ≤ 值 ≤ 0.2"]]:
  check(form._fields[pair[0]].get_meta("parameter_range")==pair[1],"solar UI range "+pair[0])
 var area_bound:Dictionary=SiteSupport.parameter_limits("solar_thermal").absorber_area_m2
 var area_range:String="%s %s 值 ≤ %s" % [String.num(float(area_bound.min),6),"<" if area_bound.min_exclusive else "≤",String.num(float(area_bound.max),6)]
 check(form._fields.absorber_area_m2.get_meta("parameter_range")==area_range,"solar collector range matches the shared installed envelope")
 var original_area:String=form._fields.absorber_area_m2.text
 form._fields.absorber_area_m2.text=str(float(area_bound.max)+1.0)
 check(not form.get_validation_errors().is_empty(),"solar installed-area limit rejects excessive draft")
 form._fields.absorber_area_m2.text=original_area
 check(form.get_validation_errors().is_empty(),"original solar parameters remain valid")
 form.queue_free()
 check(game.advance(60),"advance")
 var state:Dictionary=game.state()
 check(game.write_save("res://evidence/tower_stage/solar_world_roundtrip.json"),"save")
 game.solar_energy.incident_mwh=999
 check(game.read_save("res://evidence/tower_stage/solar_world_roundtrip.json"),"load")
 for key in state.solar_energy:check(is_equal_approx(float(game.solar_energy[key]),float(state.solar_energy[key])),"solar ledger restored "+key)
 var snap:Dictionary=game.optimization_controller.snapshot({"horizon_hours":1,"step_minutes":60})
 check(not snap.has("error"),"forecast snapshot valid")
 check(snap.steps[0].has("weather"),"weather frozen for solar")
 var baseline:Dictionary=game.optimization_controller.make_baseline(snap)
 check(not baseline.has("error") and baseline.steps[0].has("solar"),"baseline solar ledger")
 root.size=Vector2i(960,640);await process_frame
 game.station_interior._fit_to_parent_window();await process_frame
 check(game.station_interior.size.x<=root.get_visible_rect().size.x and game.station_interior.size.y<=root.get_visible_rect().size.y,"small window fits")
 game.dimension_profile="legacy_illustrative"
 var legacy_before:=var_to_bytes(game.state())
 var legacy_reason:String=game.can_place_internal(int(game.stations[0].id),"solar_thermal",Vector2.ZERO)
 check(legacy_reason.begins_with("旧比例兼容场景") and legacy_reason.contains("先迁移尺寸"),"legacy solar placement rejected specifically for explicit geometry migration")
 game.solar_example()
 check(var_to_bytes(game.state())==legacy_before,"legacy solar example refuses without mutations")
 print("SOLAR_WORLD_UI checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
