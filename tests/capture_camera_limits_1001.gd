extends SceneTree
var game
class Recorder:
 extends Node
 var inspector
 var elapsed:=0.0
 var captures:=0
 func _input(event):
  if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F10:
   captures+=1
   get_viewport().get_texture().get_image().save_png("res://evidence/camera_limits_1001/native_%02d.png"%captures)
 func _process(delta):
  elapsed+=delta
  if elapsed<0.3:return
  elapsed=0
  var i=inspector
  var p=i.camera.unproject_position(i.model_center)
  var data={"distance":i.camera_distance,"max_distance":i.max_zoom_out_distance,"fit_distance":i.fit_distance,"model_center_screen":str(p),"viewport_size":str(i.viewport.size),"target":str(i.camera_target),"yaw":i.camera_yaw,"version":ProjectSettings.get_setting("application/config/version")}
  var f=FileAccess.open("res://evidence/camera_limits_1001/live_telemetry.json",FileAccess.WRITE);f.store_string(JSON.stringify(data,"  "))
func _initialize():call_deferred("run")
func shot(name:String):
 for j in 8:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://evidence/camera_limits_1001/"+name+".png")
func run():
 root.size=Vector2i(1280,900);root.gui_embed_subwindows=true
 game=load("res://main.tscn").instantiate();root.add_child(game)
 await process_frame
 game.example();game.paused=true;game.open_device_details(0)
 var i=game.device_inspector
 var state=var_to_bytes(game.state())
 await shot("01_fit")
 i.camera_distance=1.0e20;i._update_camera()
 await shot("02_max_zoom_out")
 i.camera_target+=Vector3(1e10,1e10,1e10);i._update_camera()
 await shot("03_pan_edge")
 root.size=Vector2i(1024,768)
 await shot("04_resize_edge")
 assert(state==var_to_bytes(game.state()))
 root.size=Vector2i(1280,900);i.reset_camera()
 var recorder=Recorder.new();recorder.inspector=i;root.add_child(recorder);i.window_input.connect(recorder._input)
 print("CAMERA_LIMITS_1001_GUI_READY unchanged_state=true")
