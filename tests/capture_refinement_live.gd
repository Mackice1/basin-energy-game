extends SceneTree
# Native X11 mouse/keyboard QA harness. Does not synthesize Godot input.
var game
var recorder
class Recorder:
 extends Node
 var game
 var elapsed:=0.0
 var events:Array=[]
 func _input(event):
  if event is InputEventMouseButton or event is InputEventKey:
   events.append({"at_ms":Time.get_ticks_msec(),"event":event.as_text()})
  if event is InputEventKey and event.pressed and event.keycode==KEY_F10:
   game.write_save("res://evidence/refinement/native_mouse_state.json")
 func _process(delta):
  elapsed+=delta
  if elapsed<1:return
  elapsed=0
  var station=game.station_interior
  var data:={"window_size":str(game.get_tree().root.size),"interior_size":str(station.size),"selected":game.selected_id,"hovered":game.hovered_id,"mode":game.mode,"drag_active":game.drag_active,"pending_link":game.pending_link,"undo_count":game.undo_states.size(),"paused":game.paused,"time":game.elapsed_s,"notice":game.notice.text,"caption":game.interaction_caption.text,"camera":{"position":str(game.camera.position),"target":str(game.target),"distance":game.distance},"interior_visible":station.visible,"interior_selected":station.selected_id,"interior_mode":station.interaction_mode,"state":game.state(),"events":events}
  var file=FileAccess.open("res://evidence/refinement/native_mouse_telemetry.json",FileAccess.WRITE)
  file.store_string(JSON.stringify(data,"  "));file.close()
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1440,900)
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
 game.thermal_example();game.paused=true;game.distance=100;game.target=Vector3(game.stations[0].x-8,0,game.stations[0].z);game.update_camera()
 recorder=Recorder.new();recorder.game=game;root.add_child(recorder)
 print("REFINEMENT_NATIVE_MOUSE_READY")
