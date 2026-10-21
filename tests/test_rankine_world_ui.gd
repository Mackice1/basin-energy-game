extends SceneTree
const CurrentWorldVersion = preload("res://scripts/world_game.gd")
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
 game.rankine_example()
 check(game.result.get("valid",false),"example dispatch valid "+str(game.result.get("errors",[])))
 check(game.state().schema==CurrentWorldVersion.CURRENT_SAVE_SCHEMA and game.state().model_version==CurrentWorldVersion.CURRENT_MODEL_VERSION,"new version")
 check(game.validate_state(game.state())=="","new example valid save: "+game.validate_state(game.state()))
 check(game.devices.filter(func(d):return d.kind in game.RANKINE_KINDS).size()==4,"four independent cycle devices")
 var ids:Dictionary={}
 for item in game.devices:
  ids[item.kind]=int(item.id)
  if item.has("parent_station_id"):check(game.can_place_internal(int(item.parent_station_id),item.kind,Vector2(item.interior_x,item.interior_z),int(item.id),item.params)=="","example footprint "+item.kind)
 for pair in [["steam_generator","steam_turbine"],["steam_turbine","steam_condenser"],["steam_condenser","feedwater_pump"],["feedwater_pump","steam_generator"]]:
  var link:Dictionary=game.connection_candidate(ids[pair[0]],ids[pair[1]])
  check(link.get("carrier")=="water_steam" and link.get("unit")=="kg/s","cycle path "+str(pair))
 check(game.connection_candidate(ids.steam_turbine,2).from_port=="ac_out","turbine independently exportsAC")
 check(game.connection_candidate(3,ids.steam_generator).to_port=="oil_in","existing oil source supplies steam generator")
 check(game.station_nodes[str(int(game.stations[0].id))].has_named_port("ac_out"),"active facade exposes actual turbine boundary output")
 var form=load("res://scripts/parameter_form.gd").new();root.add_child(form)
 for kind in game.Catalog.RANKINE_KINDS:
  form.set_parameters(kind,game.device(ids[kind]).params,true)
  check(form.get_validation_errors().is_empty(),"valid parameter form "+kind)
  for key in form._fields:
   var fixed:bool=str(form._fields[key].get_meta("parameter_range")).begins_with("固定")
   check(form._fields[key].editable!=fixed,"fixed thermodynamic field readonly "+kind+"/"+key)
 form.queue_free()
 game.open_station(int(game.stations[0].id));await process_frame
 var view=game.station_interior
 for kind in game.Catalog.RANKINE_KINDS:
  check(view.tools.has(kind),"internal build action "+kind)
  view.selected_id=ids[kind];view.refresh()
  check(view.selected_label.text.contains("kg/s"),"runtime mass flow detail "+kind)
 check(view.connections_root.get_child_count()==game.links.size()-4,"visible connections rendered "+str(view.connections_root.get_child_count()))
 game.select_device(ids.steam_generator);game.open_line_settings()
 var mass_index:int=game.links.find_custom(func(l):return l.get("carrier","")=="water_steam")
 game.select_editing_line(mass_index)
 check(game.line_capacity_title.text.contains("kg/s") and not game.line_loss.editable,"mass line editor units/loss")
 game.line_dialog.hide()
 check(game.advance(60),"advance cycle")
 check(float(game.rankine_energy.gross_electric_mwh)>0,"nonzero cumulative gross electricity")
 check(game.validate_state(game.state())=="","nonzero cumulative save conservation: "+game.validate_state(game.state()))
 var before:Dictionary=game.state()
 check(game.write_save("res://evidence/tower_stage/rankine_world_roundtrip.json"),"save")
 game.rankine_energy.gross_electric_mwh=999
 check(game.read_save("res://evidence/tower_stage/rankine_world_roundtrip.json"),"load")
 for key in before.rankine_energy:check(is_equal_approx(game.rankine_energy[key],before.rankine_energy[key]),"cumulative cycle restore "+key)
 var frozen:=var_to_bytes(game.state())
 var snap:Dictionary=game.optimization_controller.snapshot({"horizon_hours":1,"step_minutes":60})
 check(not snap.has("error") and snap.get("schema_version")==5,"rankine forecast schema5")
 var baseline:Dictionary=game.optimization_controller.make_baseline(snap)
 check(not baseline.has("error") and baseline.steps[0].has("rankine"),"baseline independent cycle ledger")
 check(var_to_bytes(game.state())==frozen,"forecast does not mutate live state")
 game.open_station(int(game.stations[0].id));root.size=Vector2i(960,640);await process_frame;view._fit_to_parent_window();await process_frame
 check(view.size.x<=root.get_visible_rect().size.x and view.size.y<=root.get_visible_rect().size.y,"small window fits")
 print("RANKINE_WORLD_UI checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
