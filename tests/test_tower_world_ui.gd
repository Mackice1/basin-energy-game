extends SceneTree
var game
var failures:Array[String]=[]
var checks:=0
func check(ok:bool,caption:String):
 checks+=1
 if not ok:failures.append(caption);push_error(caption)
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1440,900)
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
 game.tower_example()
 check(game.validate_state(game.state())=="","full state valid: "+game.validate_state(game.state()))
 check(game.stations.size()==1 and game.stations[0].get("kind","")=="tower_station","tower example station")
 check(game.devices.size()==10,"10 tower example devices")
 check(game.result.get("valid",false),"valid dispatch "+str(game.result.get("error","")))
 check(game.state().schema==13 and game.state().model_version==22,"schema13/model22")
 for d in game.devices:
  if d.has("parent_station_id"):check(game.can_place_internal(int(d.parent_station_id),d.kind,Vector2(d.interior_x,d.interior_z),int(d.id),d.params)=="","valid placement "+d.kind)
 var receiver:int=-1
 for d in game.devices:
  if d.kind=="solar_tower_receiver":receiver=int(d.id)
 check(receiver>=0,"receiver exists")
 check(game.can_place_internal(int(game.stations[0].id),"solar_tower_receiver",Vector2.ZERO)!="","duplicate rejected")
 check(not game.move_internal_device(receiver,Vector2(.2,0)),"receiver fixed center")
 check(game.sampled(0).weather.get("dni_wm2",0)>0,"automatic noon DNI")
 check(game.sampled(43200).weather.get("dni_wm2",-1)==0,"automatic midnight zero DNI")
 game.open_station(int(game.stations[0].id));await process_frame
 check(not game.station_interior.preview_only and game.station_interior.tower_site,"operational interior")
 game.station_interior.selected_id=receiver;game.station_interior.refresh()
 check(game.station_interior.selected_label.text.contains("1600"),"receiver detail")
 check(game.advance(60),"advance")
 var before:Dictionary=game.state()
 check(game.write_save("res://evidence/tower_stage/world_roundtrip.json"),"write save")
 game.tower_energy.useful_mwhth=999
 check(game.read_save("res://evidence/tower_stage/world_roundtrip.json"),"read save")
 for key in before.tower_energy:check(is_equal_approx(game.tower_energy[key],before.tower_energy[key]),"tower energy restored "+key)
 for i in game.devices.size():
  for key in before.devices[i].state:check(is_equal_approx(game.devices[i].state[key],before.devices[i].state[key]),"inventory restored")
 game.open_station(int(game.stations[0].id));await process_frame
 root.size=Vector2i(960,640);await process_frame
 game.station_interior._fit_to_parent_window();await process_frame
 var area:=Rect2(Vector2.ZERO,Vector2(game.station_interior.size))
 for child in game.station_interior.build_toolbar.get_children():
  if child is Button:check(child.is_visible_in_tree() and area.encloses(child.get_global_rect()),"tower small-window command "+str(child.name))
 check(game.station_interior.view_container.size.y>=320,"tower small-window usable viewport")
 print("TOWER_WORLD_UI checks=",checks," failures=",failures)
 quit(0 if failures.is_empty() else 1)
