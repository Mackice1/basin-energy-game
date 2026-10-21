extends SceneTree
var game
func _initialize():call_deferred("run")
func shot(name:String,focus:Vector3,span:float,angle:float):
 game.target=focus;game.distance=span;game.yaw=angle;game.pitch=0.68;game.update_camera()
 for i in 12:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://evidence/world_infrastructure_1002/"+name+".png")
func run():
 root.size=Vector2i(1440,900);root.gui_embed_subwindows=true
 game=load("res://main.tscn").instantiate();root.add_child(game)
 await process_frame
 game.example();game.paused=true
 var state=var_to_bytes(game.state())
 await shot("detail_crossarms_1440",Vector3(80,2.8,3),22.0,0.65)
 await shot("detail_terrain_1440",Vector3(39,0,33),58.0,-0.22)
 for layer in [1,6,5,7,0]:
  game.change_layer(layer)
  for i in 3:await process_frame
 assert(state==var_to_bytes(game.state()))
 print("WORLD_REVIEW_PASS overlays_and_state=true")
 quit()
