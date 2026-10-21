extends SceneTree
const Fixture=preload("res://tests/test_visual_ui.gd")
var checks:=0
var failures:Array[String]=[]
var game
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures.append(message);push_error("WORKSPACE_V22_FAIL "+message)
func _initialize():call_deferred("run")
func settle():
 for i in 5:await process_frame
func run():
 root.content_scale_size=Vector2i.ZERO
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
 game=Fixture.UIController.new();root.add_child(game)
 await settle()
 for resolution in [Vector2i(1024,768),Vector2i(1440,900)]:
  root.size=resolution;await settle();game._layout_workspace();await settle()
  var canvas:=Rect2(Vector2.ZERO,Vector2(resolution))
  for control in [game.hud_header,game.hud_views,game.hud_context,game.hud_build,game.hud_footer]:
   check(canvas.encloses(control.get_global_rect()),str(resolution)+": contained "+control.name)
  for control in [game.hud_header,game.hud_views,game.hud_context,game.hud_build,game.hud_footer]:
   for other in [game.hud_header,game.hud_views,game.hud_context,game.hud_build,game.hud_footer]:
    if control!=other:check(not control.get_global_rect().intersects(other.get_global_rect()),"no overlap "+control.name+" / "+other.name)
  check(not game.hud_layers.visible,"map layers start closed")
  game.hud_layer_button.pressed.emit();await settle()
  check(game.hud_layers.visible and canvas.encloses(game.hud_layers.get_global_rect()),"layers open within canvas")
  game.hud_layer_button.pressed.emit()
  for key in game.hud_actions:
   var command:Button=game.hud_actions[key]
   check(command.size.x>=52 and command.size.y>=34,"labelled edit control retains usable hit box "+key)
  for key in game.tool_buttons:
   check(canvas.encloses(game.tool_buttons[key].get_global_rect()),"all construction cards visible "+key)
  for key in game.hud_dock.panels:
   game.hud_dock.toggle_panel(key);await settle()
   check(canvas.encloses(game.hud_dock.panels[key].get_global_rect()),"sidebar contained "+key)
   check(not game.hud_dock.panels[key].get_global_rect().intersects(game.hud_context.get_global_rect()),"sidebar clear of context commands "+key)
   game.hud_dock.toggle_panel(key)
  check(not game.pointer_over_ui(Vector2(500,300)),"central map is directly clickable with panels closed")
  game.start_build("wind");game.cancel_interaction();game.cancel_interaction()
  check(game.mode=="select" and not is_instance_valid(game.ghost),"repeated cancel clears construction ghost")
 for key in ["camera", "lod_camera", "terrain", "labels", "infrastructure", "selection", "overlay", "equipment", "cables"]:
  var node=game.get(key)
  if is_instance_valid(node) and node.get_parent()==null:node.free()
 game.free()
 await process_frame
 print("WORKSPACE_UI_V22 checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
