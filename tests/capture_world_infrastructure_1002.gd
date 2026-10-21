extends SceneTree
var game
var phase := "before"
var report:Array=[]
func _initialize():call_deferred("run")
func capture_view(label:String, size:Vector2i, span:float, focus:Vector3):
 root.size=size
 game.distance=span;game.target=focus;game.yaw=-0.22;game.pitch=0.78;game.update_camera()
 for i in 15:await process_frame
 var samples:Array=[]
 var previous=Time.get_ticks_usec()
 for i in 60:
  await process_frame
  var now=Time.get_ticks_usec();samples.append((now-previous)/1000.0);previous=now
 samples.sort()
 var total=0.0
 for value in samples:total+=value
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://evidence/world_infrastructure_1002/"+phase+"_"+label+".png")
 var row={"label":label,"mean_ms":total/samples.size(),"median_ms":samples[30],"p95_ms":samples[57],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"static_memory":OS.get_static_memory_usage(),"adapter":RenderingServer.get_video_adapter_name(),"viewport":str(size)}
 report.append(row);print("WORLD_BENCH ",JSON.stringify(row))
func run():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("phase="):phase=arg.trim_prefix("phase=")
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/world_infrastructure_1002"))
 root.size=Vector2i(1440,900);root.gui_embed_subwindows=true
 game=load("res://main.tscn").instantiate();root.add_child(game)
 await process_frame
 game.example();game.paused=true
 var state=var_to_bytes(game.state())
 await capture_view("far_1440",Vector2i(1440,900),205.0,Vector3(0,0,0))
 await capture_view("near_1440",Vector2i(1440,900),39.0,Vector3(80,0,3))
 await capture_view("far_1024",Vector2i(1024,768),205.0,Vector3(0,0,0))
 await capture_view("near_1024",Vector2i(1024,768),39.0,Vector3(80,0,3))
 assert(state==var_to_bytes(game.state()))
 var f=FileAccess.open("res://evidence/world_infrastructure_1002/"+phase+"_benchmark.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
 print("WORLD_CAPTURE_PASS state_unchanged=true");quit()
