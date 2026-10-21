extends SceneTree
var game
class Recorder:
 extends Node
 var game
 var elapsed:=0.0
 var events:Array=[]
 func _input(event):
  if event is InputEventMouseButton or event is InputEventKey:events.append({"at_ms":Time.get_ticks_msec(),"event":event.as_text()})
  if event is InputEventKey and event.pressed:
   if event.keycode==KEY_F6:
    game.tower_example();game.open_station(int(game.stations[0].id))
   if event.keycode==KEY_F5:
    assert(game.read_save("res://evidence/tower_stage/full_integrated.json"));game.open_station(int(game.stations[0].id))
   if event.keycode==KEY_F10:game.write_save("res://evidence/tower_stage/native_mouse_state.json")
   if event.keycode==KEY_F11:
    assert(game.read_save("res://evidence/tower_stage/native_mouse_state.json"));game.open_station(int(game.stations[0].id))
   if event.keycode==KEY_F8:
    assert(game.read_save("res://evidence/tower_stage/night_integrated.json"));game.open_station(int(game.stations[0].id))
   if event.keycode==KEY_F7:
    assert(game.read_save("res://evidence/tower_stage/day_integrated.json"));game.open_station(int(game.stations[0].id))
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
  var controls:Dictionary={};gather_controls(game,controls)
  var data:={"paused":game.paused,"speed":game.speed,"time":game.elapsed_s,"notice":game.notice.text,"interior_visible":game.station_interior.visible,"summary":game.station_interior.summary_label.text,"tower":game.result.get("tower",{}),"rankine":game.result.get("rankine",{}),"state":game.state(),"controls":controls,"events":events}
  var file=FileAccess.open("res://evidence/tower_stage/native_mouse_telemetry.json",FileAccess.WRITE)
  file.store_string(JSON.stringify(data,"  "));file.close()
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1600,1000)
 root.position=Vector2i.ZERO
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
 assert(game.read_save("res://evidence/tower_stage/day_integrated.json"))
 game.open_station(int(game.stations[0].id));game.station_interior.refresh()
 var recorder:=Recorder.new();recorder.game=game;root.add_child(recorder);game.station_interior.window_input.connect(recorder._input)
 print("TOWER_NATIVE_READY")
