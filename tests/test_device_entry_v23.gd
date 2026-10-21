extends SceneTree
const Fixture=preload("res://tests/test_visual_ui.gd")
const Catalog=preload("res://scripts/device_catalog.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1440,900)
 root.gui_embed_subwindows=true
 var game=Fixture.UIController.new();root.add_child(game)
 await process_frame
 for kind in Catalog.implemented_kinds():
  var item={"id":0,"kind":kind,"x":0.0,"z":0.0,"params":Catalog.defaults(kind)}
  var initial=Catalog.initial_state(kind,item.params)
  if not initial.is_empty():item.state=initial
  game.devices=[item];game.links=[];game.selected_id=0;game.result={}
  game.update_station_display()
  check(game.station_enter_button.visible,"entry visible: "+kind)
  var snapshot=var_to_bytes(game.state())
  game.station_enter_button.pressed.emit()
  check(game.device_inspector.visible and game.device_inspector.device_id==0,"actual entry routes: "+kind)
  check(game.modal_visible(),"details blocks main canvas: "+kind)
  game.device_inspector.close_device()
  check(not game.modal_visible(),"exit unblocks map: "+kind)
  check(var_to_bytes(game.state())==snapshot,"entry/exit preserves full state: "+kind)
 game.devices=[];game.selected_id=-2;game.update_station_display()
 check(not game.station_enter_button.visible,"no phantom detail entrance without selection")
 game.open_device_details(-2)
 check(not game.device_inspector.visible,"invalid entry stays closed")
 for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables"]:
  var node=game.get(key)
  if is_instance_valid(node) and node.get_parent()==null:node.free()
 game.free();await process_frame
 print("DEVICE_ENTRY_V23 checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
