extends SceneTree
var game
class Recorder:
 extends Node
 var game
 var captures:=0
 var elapsed:=0.0
 var events:Array=[]
 func _input(event):
  if event is InputEventMouseButton or event is InputEventKey:events.append({"at_ms":Time.get_ticks_msec(),"event":event.as_text()})
  if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F10:
   captures+=1
   get_viewport().get_texture().get_image().save_png("res://evidence/v23/native_%02d.png"%captures)
 func _process(delta):
  elapsed+=delta
  if elapsed<0.3:return
  elapsed=0
  var data={"selected":game.selected_id,"mode":game.mode,"target":str(game.target),"state":game.state(),"inspector_visible":game.device_inspector.visible,"inspector_id":game.device_inspector.device_id,"station_visible":game.station_interior.visible,"station_selected":game.station_interior.selected_id,"events":events}
  var f=FileAccess.open("res://evidence/v23/native_telemetry.json",FileAccess.WRITE);f.store_string(JSON.stringify(data,"  "))
func _initialize():call_deferred("run")
func settle():
 for i in 8:await process_frame
 await RenderingServer.frame_post_draw
func capture(name:String):
 await settle()
 root.get_texture().get_image().save_png("res://evidence/v23/"+name+".png")
func run():
 root.size=Vector2i(1440,900)
 root.title="能源基地 V23 · 左键平移与设备详情验收"
 root.gui_embed_subwindows=true
 game=load("res://main.tscn").instantiate();root.add_child(game)
 await settle()
 game.thermal_example();game.paused=true;game.advance(300);game.refresh()
 await capture("01_base")
 var before=var_to_bytes(game.state())
 for entry in [[0,"02_wind"],[1,"03_pv"],[2,"04_substation"],[6,"05_heat_demand"]]:
  game.select_device(entry[0]);game.open_device_details(entry[0]);await capture(entry[1]);game.device_inspector.close_device()
 game.open_station(int(game.stations[0].id));await capture("06_station")
 game.station_interior._select(3);game.open_device_details(3);await capture("07_boiler_details")
 game.device_inspector.tabs.current_tab=2;await capture("08_boiler_connections")
 game.device_inspector.tabs.current_tab=3;await capture("09_boiler_boundaries")
 game.device_inspector.close_device();game.station_interior.close_station()
 assert(var_to_bytes(game.state())==before,"Navigation must not change authoritative simulation state")
 var saved:Dictionary=game.state()
 root.size=Vector2i(1024,768)
 game.open_device_details(0);await capture("10_wind_1024");game.device_inspector.close_device()
 root.size=Vector2i(1440,900)
 game.storage_example();game.paused=true
 for d in game.devices:
  if d.kind=="battery":game.open_device_details(int(d.id));await capture("11_battery");game.device_inspector.close_device();break
 game.tower_example();game.paused=true
 for d in game.devices:
  if d.kind=="steam_turbine":game.open_device_details(int(d.id));await capture("12_steam_turbine");game.device_inspector.close_device();break
 game.open_station(int(game.stations[0].id));await capture("13_tower_station");game.station_interior.close_station()
 game.restore(saved)
 game.select_device(0);game.hud_dock.close_panels()
 var recorder=Recorder.new();recorder.game=game;root.add_child(recorder)
 game.device_inspector.window_input.connect(recorder._input)
 game.station_interior.window_input.connect(recorder._input)
 print("V23_CAPTURE_READY state_preserved=true")
