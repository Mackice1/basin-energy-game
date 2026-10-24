extends SceneTree
const Existing = preload("res://tests/test_interaction_polish.gd")
var checks:=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
 checks+=1
 if not value:failures.append(message);printerr("FAIL ",message)
func _initialize():call_deferred("run")
func right(pressed:bool)->InputEventMouseButton:
 var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_RIGHT;e.pressed=pressed;e.position=Vector2(400,400);return e
func run()->void:
 var g=Existing.Fixture.new();root.add_child(g)
 g.repeat_build=true;g.start_build("wind")
 check(g.workflow_caption().contains("连续建造"),"continuous preference visible")
 check(g.commit_build_at(Vector2(-50,0)),"first repeated device committed")
 check(g.devices.size()==1 and g.mode=="build" and g.build_kind=="wind" and is_instance_valid(g.ghost),"repeat keeps pending same-kind ghost")
 var before:=var_to_bytes(g.state());var rev:int=g.scene_revision
 check(not g.commit_build_at(Vector2(-50,0)),"occupied placement rejected")
 check(var_to_bytes(g.state())==before and g.scene_revision==rev and g.mode=="build","failed placement preserves state and tool")
 g.toggle_repeat_build()
 check(not g.repeat_build and g.workflow_caption().contains("单次建造"),"single mode visible")
 check(g.commit_build_at(Vector2(0,0)),"single device committed")
 check(g.devices.size()==2 and g.mode=="select" and g.build_kind=="" and g.ghost==null,"single mode exits and clears pending kind")
 g.start_build("pv");g.handle_escape()
 check(g.mode=="select" and g.build_kind=="" and g.ghost==null,"Escape and right-click share complete cancel")
 for tool in ["build","link","move"]:
  if tool=="build":g.start_build("pv")
  else:g.set_mode(tool)
  if tool=="link":g.pending_link=0
  before=var_to_bytes(g.state());rev=g.scene_revision
  g._input(right(true))
  check(g.mode=="select" and g.pending_link==-2 and g.build_kind=="" and g.ghost==null,tool+" right-click exits whole tool")
  check(var_to_bytes(g.state())==before and g.scene_revision==rev,tool+" cancel doesn't edit device/links/inventory")
  check(g.camera_drag_blocked,tool+" cancellation press cannot rotate")
  g._input(right(false));check(not g.camera_drag_blocked,tool+" release restores orbit")
 g.set_mode("link");g.pending_link=0;g.blocked_modal=true;g._input(right(true))
 check(g.mode=="link" and g.pending_link==0,"modal owns input; right-click doesn't cancel behind it")
 g.blocked_modal=false;g.cancel_interaction()
 g.set_mode("link")
 check(g.workflow_caption().contains("1/2") and g.connection_caption(-2).contains("右键"),"link start explains progress and cancel")
 g.pending_link=0
 check(g.workflow_caption().contains("2/2") and g.connection_caption(-2).contains("右键"),"link endpoint explains progress and cancel")
 before=var_to_bytes(g.state());rev=g.scene_revision
 g.toggle_repeat_build()
 check(var_to_bytes(g.state())==before and g.scene_revision==rev,"tool preference isn't dirty scene edit")
 for key in ["terrain","infrastructure","overlay","confirmation","param_dialog","param_errors","param_target","data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice"]:
  var node=g.get(key)
  if is_instance_valid(node) and node.get_parent()==null:node.free()
 g.free();await process_frame
 print("BUILD_WORKFLOW checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
