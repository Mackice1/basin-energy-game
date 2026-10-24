extends SceneTree
const Existing=preload("res://tests/test_interaction_polish.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize():call_deferred("run")
func dispose(g):
 for key in ["terrain","infrastructure","overlay","confirmation","param_dialog","param_errors","param_target","data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice"]:
  var node=g.get(key)
  if is_instance_valid(node) and node.get_parent()==null:node.free()
 g.free()
func run():
 var a=Existing.Fixture.new();root.add_child(a);a.climate_config=a.Climate.defaults()
 var loaded:bool=a.beginner_base_example()
 check(loaded,"historical example commits: "+a.last_notice)
 if not loaded:dispose(a);quit(1);return
 var seed:Dictionary=a.state();seed.elapsed_s=3590.0;a.restore(seed)
 var b=Existing.Fixture.new();root.add_child(b);b.restore(seed)
 check(a.start_weather_replay(),"replay restricted-source activation")
 b.paused=false
 var total:=0
 while a.elapsed_s<3620.0:
  var began:=Time.get_ticks_usec()
  a.advance_frame(1.0/60.0)
  check(a.replay_last_steps>0 and a.replay_last_steps<=30,"bounded frame steps")
  print("REPLAY_FRAME_US ",Time.get_ticks_usec()-began," steps=",a.replay_last_steps)
  for i in a.replay_last_steps:check(b.advance(1.0),"reference1s commit")
  total+=a.replay_last_steps
  if a.replay_last_steps==0:break
 check(a.elapsed_s==b.elapsed_s and a.devices==b.devices and a.energy==b.energy and a.material_energy==b.material_energy,"replay equals sequential1s across hourly boundary")
 check(a.sampled(3599).weather.wind_speed_mps!=a.sampled(3600).weather.wind_speed_mps,"real source hour transition no synthetic jitter")
 check(a.sampled(3600).weather.wind_speed_mps==a.sampled(3650).weather.wind_speed_mps,"hourly zero-order hold")
 a.paused=true;var frozen:Dictionary=a.state();a.advance_frame(10)
 check(a.state()==frozen,"pause halts replay")
 check(a.set_simulation_speed(2) and not a.weather_replay,"ordinary speed exits replay")
 a.imports=[]
 check(not a.start_weather_replay(),"unrelated scene cannot replay real-source mode")
 a.restore(seed);a.elapsed_s=604799.0;a.start_weather_replay();a.advance_frame(1)
 check(a.elapsed_s==604800.0 and a.paused,"real endpoint pauses without extrapolation")
 dispose(a);dispose(b);await process_frame
 print("REAL_WEATHER_REPLAY checks=",checks," failures=",failures," actual_steps=",total)
 quit(0 if failures==0 else 1)
