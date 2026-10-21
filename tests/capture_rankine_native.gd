extends SceneTree
# Native X11 mouse/keyboard evidence. Initial example is a fixture; all recorded
# clicks are delivered by the OS, not synthesized as Godot InputEvents.
var game
var recorder
class Recorder:
 extends Node
 var game
 var elapsed:=0.0
 var events:Array=[]
 var tower_id:=-1
 func _input(event):
  if event is InputEventMouseButton or event is InputEventKey:events.append({"at_ms":Time.get_ticks_msec(),"event":event.as_text()})
  if event is InputEventKey and event.pressed:
   if event.keycode==KEY_F10:game.write_save("res://evidence/rankine_stage/native_mouse_state.json")
   if event.keycode==KEY_F9:
    game.station_interior.close_station();game.select_device(tower_id);game.focus_selected()
   if event.keycode==KEY_F11:
    game.open_station(int(game.stations[0].id));game.station_interior.selected_id=10;game.station_interior.refresh()
 func control_rect(node:Control)->Array:
  var window:Window=node.get_window()
  var origin:Vector2=node.get_global_rect().position
  if window!=get_tree().root:origin+=Vector2(window.position)
  var scale:=Vector2(get_tree().root.size)/get_tree().root.get_visible_rect().size
  var center:Vector2=(origin+node.size*.5)*scale
  return [center.x,center.y]
 func gather_controls(node:Node,out:Dictionary):
  if node is Control and node.is_visible_in_tree():
   if node is Button:out[str(node.name)+"|"+node.text]=control_rect(node)
   if node is LineEdit:out["field|"+str(node.name)]=control_rect(node)
  for child in node.get_children():gather_controls(child,out)
 func _process(delta):
  elapsed+=delta
  if elapsed<.5:return
  elapsed=0
  var station=game.station_interior
  var controls:Dictionary={};gather_controls(game,controls)
  var data:={"window_size":str(game.get_tree().root.size),"interior_size":str(station.size),"selected":game.selected_id,"mode":game.mode,"undo_count":game.undo_states.size(),"paused":game.paused,"time":game.elapsed_s,"notice":game.notice.text,"caption":game.interaction_caption.text,"interior_visible":station.visible,"preview_only":station.preview_only,"interior_selected":station.selected_id,"interior_mode":station.interaction_mode,"rankine_result":game.result.get("rankine",{}),"rankine_energy":game.rankine_energy,"state":game.state(),"controls":controls,"events":events,"tower_id":tower_id}
  var file=FileAccess.open("res://evidence/rankine_stage/native_mouse_telemetry.json",FileAccess.WRITE)
  file.store_string(JSON.stringify(data,"  "));file.close()
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1440,900)
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
 if OS.has_environment("RANKINE_RESTART"):
  assert(game.read_save("res://evidence/rankine_stage/native_mouse_state.json"))
 else:
  game.rankine_example()
  var found:=false
  for x in range(-60,66,5):
   for z in range(-40,41,5):
    if game.can_place("tower_station_preview",Vector2(x,z))=="":
     assert(game.add_equipment("tower_station_preview",Vector2(x,z)));found=true;break
   if found:break
  assert(found,"tower160m site must find terrain without overlap")
 game.paused=true
 game.open_station(int(game.stations[0].id));game.station_interior.selected_id=10;game.station_interior.refresh()
 recorder=Recorder.new();recorder.game=game
 for facility in game.stations:
  if facility.get("kind","")=="tower_station_preview":recorder.tower_id=int(facility.id)
 root.add_child(recorder);game.station_interior.window_input.connect(recorder._input)
 print("RANKINE_NATIVE_MOUSE_READY")
