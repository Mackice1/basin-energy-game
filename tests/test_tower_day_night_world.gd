extends SceneTree
var game
func _initialize():call_deferred("run")
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
 game.tower_example()
 assert(game.validate_state(game.state())=="")
 var t:=Time.get_ticks_msec()
 assert(game.advance(600))
 game.refresh()
 assert(game.result.tower.charge_mwth>0)
 assert(game.result.rankine.gross_electric_mw>0)
 assert(game.write_save("res://evidence/tower_stage/day_integrated.json"))
 print("TOWER_DAY ",JSON.stringify({"time":game.elapsed_s,"tower":game.result.tower,"rankine":game.result.rankine,"runtime_ms":Time.get_ticks_msec()-t}))
 for hour in range(9):
  assert(game.advance(3600));game.refresh()
  if hour==0:assert(game.write_save("res://evidence/tower_stage/full_integrated.json"))
  print("TOWER_HOUR ",hour+1," time=",game.elapsed_s," salt=",game.result.tower.energy_mwhth," dni=",game.sampled(game.elapsed_s).weather.dni_wm2," gross=",game.result.rankine.gross_electric_mw," runtime_ms=",Time.get_ticks_msec()-t)
 assert(game.sampled(game.elapsed_s).weather.dni_wm2==0)
 assert(game.result.tower.discharge_mwth>0)
 assert(game.result.rankine.gross_electric_mw>0)
 assert(game.write_save("res://evidence/tower_stage/night_integrated.json"))
 print("TOWER_NIGHT ",JSON.stringify({"time":game.elapsed_s,"tower":game.result.tower,"rankine":game.result.rankine,"runtime_ms":Time.get_ticks_msec()-t}))
 quit()
