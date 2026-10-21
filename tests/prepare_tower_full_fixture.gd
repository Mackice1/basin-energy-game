extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
 assert(game.read_save("res://evidence/tower_stage/day_integrated.json"))
 assert(game.advance(3600));game.refresh()
 assert(is_equal_approx(game.result.tower.energy_mwhth,.5))
 assert(game.write_save("res://evidence/tower_stage/full_integrated.json"))
 print("TOWER_FULL_INTEGRATED")
 quit()
