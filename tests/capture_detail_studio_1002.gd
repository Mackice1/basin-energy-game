extends SceneTree
var game
var performance_samples: Array = []
var perf_elapsed := 0.0
func _process(delta):
 perf_elapsed += delta
 if perf_elapsed > 1.0:
  perf_elapsed = 0.0
  performance_samples.append({"at_ms":Time.get_ticks_msec(),"fps":Engine.get_frames_per_second(),"frame_time_ms":Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,"root_size":str(root.size)})
  var f = FileAccess.open("res://evidence/detail_1002/desktop_performance.json",FileAccess.WRITE)
  f.store_string(JSON.stringify(performance_samples,"  "))
 return false
class Recorder:
 extends Node
 var game
 var captures := 0
 var elapsed := 0.0
 var baseline: PackedByteArray
 var events: Array = []
 func _input(event):
  if event is InputEventMouseButton or event is InputEventKey: events.append(event.as_text())
  if event is InputEventKey and event.pressed and not event.echo:
   if event.keycode == KEY_F10:
    captures += 1
    get_viewport().get_texture().get_image().save_png("res://evidence/detail_1002/native_%02d.png" % captures)
   if event.keycode == KEY_F6:
    game.device_inspector.close_device()
    get_window().size = Vector2i(1024, 768)
    await get_tree().process_frame
    await get_tree().process_frame
    game.open_device_details(1)
   if event.keycode == KEY_F7:
    game.open_device_details(1)
   if event.keycode == KEY_F8:
    game.open_device_details(2)
 func _process(delta):
  elapsed += delta
  if elapsed < 0.3: return
  elapsed = 0
  var i = game.device_inspector
  var data = {"distance":i.camera_distance,"max_distance":i.max_zoom_out_distance,"fit_distance":i.fit_distance,"center_screen":str(i.camera.unproject_position(i.model_center)),"viewport_size":str(i.viewport.size),"target":str(i.camera_target),"yaw":i.camera_yaw,"visible":i.visible,"unchanged_state":var_to_bytes(game.state()) == baseline,"events":events,"version":ProjectSettings.get_setting("application/config/version")}
  var f = FileAccess.open("res://evidence/detail_1002/native_telemetry.json",FileAccess.WRITE)
  f.store_string(JSON.stringify(data,"  "))
func _initialize(): call_deferred("run")
func shot(name: String):
 for j in 12: await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://evidence/detail_1002/" + name + ".png")
func run():
 root.size = Vector2i(1440, 900)
 root.gui_embed_subwindows = true
 game = load("res://main.tscn").instantiate()
 root.add_child(game)
 await process_frame
 game.thermal_example(); game.paused = true; game.advance(300); game.refresh()
 var before = var_to_bytes(game.state())
 for resolution in [Vector2i(1440,900), Vector2i(1024,768)]:
  root.size = resolution
  for entry in [[1,"pv"],[0,"wind"],[2,"substation"],[4,"thermal_store"]]:
   game.open_device_details(entry[0])
   await shot(entry[1] + "_" + str(resolution.x))
   game.device_inspector.close_device()
  game.open_station(int(game.stations[0].id))
  await shot("station_interior_" + str(resolution.x))
  game.open_device_details(3)
  await shot("boiler_" + str(resolution.x))
  game.device_inspector.close_device()
  game.station_interior.close_station()
 assert(before == var_to_bytes(game.state()))
 var saved = game.state()
 game.tower_example(); game.paused = true
 var tower_before = var_to_bytes(game.state())
 for resolution in [Vector2i(1440,900), Vector2i(1024,768)]:
  root.size = resolution
  game.open_station(int(game.stations[0].id))
  await shot("tower_station_" + str(resolution.x))
  for item in game.devices:
   if item.kind == "solar_tower_receiver":
    game.open_device_details(int(item.id))
    await shot("tower_detail_" + str(resolution.x))
    game.device_inspector.close_device()
    break
  game.station_interior.close_station()
 assert(tower_before == var_to_bytes(game.state()))
 game.restore(saved); game.paused = true
 root.size = Vector2i(1440,900)
 game.open_device_details(1)
 var recorder = Recorder.new();recorder.game = game;recorder.baseline = before;root.add_child(recorder)
 game.device_inspector.window_input.connect(recorder._input)
 print("STUDIO_1002_GUI_READY state_preserved=true F6=1024 F7=PV F8=station F10=capture")
