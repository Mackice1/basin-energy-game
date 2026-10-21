extends SceneTree
var game
var checks:=0
var failures:Array[String]=[]
class Recorder:
 extends Node
 var game
 var elapsed:=0.0
 var events:Array=[]
 var captures:=0
 func _input(event):
  if event is InputEventMouseButton or event is InputEventKey:events.append({"at_ms":Time.get_ticks_msec(),"event":event.as_text()})
  if event is InputEventKey and event.pressed and not event.echo:
   if event.keycode==KEY_F10:
    captures+=1
    get_viewport().get_texture().get_image().save_png("res://evidence/ui_v22/native_%02d.png"%captures)
   if event.keycode==KEY_F8:game.write_save("res://evidence/ui_v22/native_saved.json")
   if event.keycode==KEY_F9:game.read_save("res://evidence/ui_v22/native_saved.json")
 func gather(node:Node,out:Dictionary):
  if node is Control and node.is_visible_in_tree() and node is BaseButton:
   var origin:Vector2=node.get_global_rect().position
   if node.get_window()!=get_tree().root:origin+=Vector2(node.get_window().position)
   out[str(node.name)+"|"+str(node.get("text"))]={"x":origin.x,"y":origin.y,"w":node.size.x,"h":node.size.y}
  for child in node.get_children():gather(child,out)
 func _process(delta):
  elapsed+=delta
  if elapsed<.5:return
  elapsed=0
  var controls:Dictionary={};gather(game,controls)
  var st=game.station_interior
  var data={"root_size":str(get_tree().root.size),"selected":game.selected_id,"mode":game.mode,"pending":game.pending_link,"undo":game.undo_states.size(),"paused":game.paused,"time":game.elapsed_s,"notice":game.notice.text,"interior_visible":st.visible,"interior_selected":st.selected_id,"interior_mode":st.interaction_mode,"interior_pending":st.pending_link,"controls":controls,"events":events,"state":game.state()}
  var file=FileAccess.open("res://evidence/ui_v22/native_telemetry.json",FileAccess.WRITE);file.store_string(JSON.stringify(data,"  "));file.close()
func _initialize():call_deferred("run")
func settle():
 for i in 8:await process_frame
 await RenderingServer.frame_post_draw
func capture(path:String):
 await settle()
 root.get_texture().get_image().save_png("res://evidence/ui_v22/"+path+".png")
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures.append(message);push_error("V22_GUI_FAIL "+message)
func run():
 root.size=Vector2i(1440,900)
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
 game=load("res://main.tscn").instantiate();root.add_child(game)
 await settle()
 game.thermal_example();game.paused=true
 game.target=Vector3(game.stations[0].x,0,game.stations[0].z);game.distance=70;game.update_camera()
 await capture("01_base_1440")
 var original:=var_to_bytes(game.state())
 game.hud_dock.toggle_panel("energy")
 await capture("02_energy_1440")
 game.hud_dock.close_panels()
 game.open_station(int(game.stations[0].id))
 await capture("03_station_1440")
 game.station_interior.close_station()
 root.size=Vector2i(1024,768)
 await capture("04_base_1024")
 game.open_station(int(game.stations[0].id))
 await capture("05_station_1024")
 game.station_interior.set_interaction_mode("connect")
 await capture("06_connection_1024")
 game.station_interior.close_station()
 check(var_to_bytes(game.state())==original,"resize, navigation, connection preview preserve authoritative state")
 game.hud_dock.toggle_panel("optimization")
 await capture("07_optimization_entry_1024")
 game.hud_dock.close_panels()
 var target_id:int=game.devices.filter(func(d):return d.kind=="electric_boiler")[0].id
 game.select_device(target_id);game.open_parameters(false)
 await capture("08_parameters_1024")
 game.param_dialog.hide()
 check(var_to_bytes(game.state())==original,"parameter open/cancel preserves state")
 check(game.write_save("res://evidence/ui_v22/gui_roundtrip.json"),"GUI process save")
 check(game.read_save("res://evidence/ui_v22/gui_roundtrip.json"),"GUI process reload")
 check(game.paused and game.speed==1,"reload remains paused at x1")
 var after_load:=var_to_bytes(game.state())
 game.optimization_controller.open()
 game.optimization_controller.start({"horizon_hours":2,"step_minutes":60,"terminal_soc_fraction":0.0,"enforce_terminal_soc":false})
 var started:=Time.get_ticks_msec()
 while game.optimization_controller.pid>0 and Time.get_ticks_msec()-started<60000:await process_frame
 check(game.optimization_controller.last_result.get("status","")=="optimal" and game.optimization_controller.last_result.get("validation",{}).get("valid",false),"real GLPK after reload")
 check(var_to_bytes(game.state())==after_load,"optimization after reload never applies schedule")
 await capture("09_optimization_after_reload_1024")
 game.optimization_controller.panel.hide()
 root.size=Vector2i(1024,768)
 var report={"checks":checks,"failures":failures,"solver":game.optimization_controller.last_result}
 var file=FileAccess.open("res://evidence/ui_v22/gui_checks.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 var recorder:=Recorder.new();recorder.game=game;root.add_child(recorder);game.station_interior.window_input.connect(recorder._input)
 print("V22_GUI_CAPTURE_DONE checks=",checks," failures=",failures.size())
