extends SceneTree
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
 var position:=Vector2(INF,INF)
 for x in range(-65,66,5):
  for z in range(-40,41,5):
   if game.can_place("tower_station_preview",Vector2(x,z))=="":position=Vector2(x,z);break
  if is_finite(position.x):break
 check(is_finite(position.x),"full160m metric preview has buildable terrain")
 check(game.add_equipment("tower_station_preview",position),"facility preview placement")
 var id:int=game.selected_id
 check(game.devices.is_empty() and game.links.is_empty(),"preview adds no energy device or link")
 check(game.stations.size()==1 and game.station(id).kind=="tower_station_preview","preview saved only as facility kind")
 check(game.station_nodes[str(id)].named_ports.is_empty(),"facade has zero terminals")
 check(not game.station_nodes[str(id)].has_named_port("ac_in") and not game.station_nodes[str(id)].has_named_port("heat_out"),"no implied heat or AC ports")
 check(is_equal_approx(game.footprint("tower_station_preview"),sqrt(128.0)),"full160m conservative placement radius")
 check(game.endpoint_description(id).contains("未投运"),"selected preview explicit label")
 game.set_mode("link");game.link_to(id)
 check(not game.station_port_dialog.visible and game.pending_link==-2,"network port picker forbidden")
 check(game.can_place_internal(id,"parabolic_trough",Vector2.ZERO).contains("未投运"),"running oil equipment placement forbidden")
 check(not game.add_internal_device(id,"steam_generator",Vector2.ZERO),"running Rankine equipment placement forbidden")
 game.open_station(id);await process_frame
 var view=game.station_interior
 check(view.preview_only and view.visible,"preview enter opens scene")
 check(view.selected_label.text.contains("100面") and view.selected_label.text.contains("1600 m²") and view.selected_label.text.contains("4圈径向错列"),"ring count and area UI accurate")
 check(view.selected_label.text.contains("固定教学太阳姿态，非实时天气追踪"),"fixed teaching sun disclaimer")
 check(view.title_label.text.contains("120 × 120"),"matching120m interior title")
 check(not view.build_toolbar.visible and not view.edit_toolbar.visible,"preview build/edit actions absent")
 check(view.equipment_nodes.is_empty() and view.connections_root.get_child_count()==0,"preview interior zero energy objects")
 check(view.scene_root.get_node("TowerPreviewGeometry").get_meta("preview_only",false),"preview visual marked")
 check(view.summary_label.text.contains("0 MW") and view.summary_label.text.contains("不参与调度"),"zero output boundary readable")
 view.start_build("steam_generator")
 check(view.interaction_mode=="select","programmatic preview construction blocked")
 var before:Dictionary=game.state()
 check(game.advance(30),"empty preview simulation valid")
 check(game.energy.generated==0 and game.rankine_energy.gross_electric_mwh==0,"preview cannot accrue electricity")
 check(game.devices.size()==before.devices.size(),"preview navigation no hidden devices")
 var path:="res://evidence/tower_rings_stage/tower_roundtrip.json"
 check(game.write_save(path),"preview save valid")
 game.stations.clear()
 check(game.read_save(path) and game.station(id).kind=="tower_station_preview","preview restore retains kind")
 game.open_station(id);root.size=Vector2i(960,640);await process_frame
 view._fit_to_parent_window();await process_frame
 check(view.size.x<=root.get_visible_rect().size.x and view.size.y<=root.get_visible_rect().size.y,"preview small window fits")
 view.close_station()
 check(not view.visible,"return closes preview")
 # Existing thermal station geometry must remain unchanged after switching.
 game.thermal_example();var old_id:int=game.stations[0].id;game.open_station(old_id);await process_frame
 check(not view.preview_only and view.title_label.text.contains("48 × 48"),"legacy active interior stays48m")
 check(view.build_toolbar.visible and view.device_picker.disabled==false,"active station controls restored")
 check(game.validate_state(game.state())=="","active save valid after leaving preview")
 print("TOWER_PREVIEW_UI checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
