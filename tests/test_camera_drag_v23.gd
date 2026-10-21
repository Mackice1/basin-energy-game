extends SceneTree

class WorldFixture:
 extends "res://scripts/world_game.gd"
 var clicks := 0
 var enters := 0
 var builds := 0
 var moves := 0
 var blocked := false
 var hit := 1
 func _ready():
  add_child(camera);add_child(lod_camera)
  camera.current=true
  camera.projection=Camera3D.PROJECTION_ORTHOGONAL
  distance=80.0;update_camera()
  set_process(false)
 func height_at(_x:float,_z:float)->float:return 0.0
 func modal_visible()->bool:return blocked
 func pointer_over_ui(pos:Vector2,_padding:Vector2=Vector2.ZERO)->bool:return pos.x<100
 func nearest(_pos:Vector2)->int:return hit
 func select_device(id:int):selected_id=id;clicks+=1
 func select_site(_point:Vector2):pass
 func pick_ground(_point:Vector2)->Vector2:return Vector2(4,5)
 func open_device_details(_id:int):enters+=1
 func add_equipment(_kind:String,_pos:Vector2,_record:bool=true)->bool:builds+=1;return false
 func move_selected(_pos:Vector2)->bool:moves+=1;return true
 func update_status():pass
 func clear_ghost():pass

var failures:Array[String]=[]
var checks:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func button(game,pos:Vector2,pressed:bool,double_click:bool=false,index:int=MOUSE_BUTTON_LEFT):
 var e:=InputEventMouseButton.new();e.position=pos;e.pressed=pressed;e.button_index=index;e.double_click=double_click
 game._input(e)
 if pressed:game._unhandled_input(e)
func motion(game,pos:Vector2,delta:Vector2,mask:int=MOUSE_BUTTON_MASK_LEFT):
 var e:=InputEventMouseMotion.new();e.position=pos;e.relative=delta;e.button_mask=mask
 game._input(e);game._unhandled_input(e)
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1440,900)
 var game:=WorldFixture.new();root.add_child(game)
 var start:=Vector2(500,300)
 var initial:Vector3=game.target
 button(game,start,true)
 check(game.clicks==0,"press defers selection")
 motion(game,start+Vector2(3,0),Vector2(3,0))
 check(game.target==initial and not game.left_pan_active,"small jitter stays a click")
 button(game,start+Vector2(3,0),false)
 check(game.clicks==1 and game.target==initial,"ordinary click selects once")
 button(game,start,true);motion(game,start+Vector2(30,20),Vector2(30,20))
 check(game.left_pan_active and game.target!=initial,"left drag pans over equipment")
 button(game,start+Vector2(30,20),false)
 check(game.clicks==1 and game.builds==0 and game.moves==0,"pan release neither selects nor edits")
 check(not game.left_pan_pending and not game.left_pan_active,"release clears gesture")
 button(game,start,true,true);button(game,start,false)
 check(game.enters==1,"station/device double click dispatches on release")
 button(game,start,true,true);motion(game,start+Vector2(40,0),Vector2(40,0));button(game,start+Vector2(40,0),false)
 check(game.enters==1,"double-click drag never opens a page")
 initial=game.target
 button(game,Vector2(20,300),true);motion(game,start,Vector2(480,0));button(game,start,false)
 check(game.target==initial and game.clicks==2,"UI-origin drag never leaks into map")
 button(game,start,true);button(game,Vector2(20,300),false)
 check(game.clicks==2 and not game.left_pan_pending,"release over UI cancels click")
 button(game,start,true);game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT);motion(game,start+Vector2(30,0),Vector2(30,0));button(game,start,false)
 check(game.target==initial and game.clicks==2,"focus loss cancels stale gesture")
 button(game,start,true);game.set_mode("build");button(game,start,false)
 check(game.builds==0 and not game.left_pan_pending,"mode switch release cannot build")
 button(game,start,true)
 check(game.builds==1 and not game.left_pan_pending,"build press preserves placement and cannot pan")
 game.set_mode("move");game.mode="move";game.hit=-2;button(game,start,true)
 check(game.moves==1,"explicit move tool still places selected equipment")
 game.mode="select";button(game,start,true);motion(game,start+Vector2(40,0),Vector2(40,0),0)
 check(not game.left_pan_pending,"missing button mask clears stale press")
 button(game,start,true);game.blocked=true;motion(game,start+Vector2(40,0),Vector2(40,0));game.blocked=false
 check(not game.left_pan_pending,"modal opening cancels gesture")
 button(game,start,true);button(game,Vector2(20,300),true);initial=game.target;motion(game,start+Vector2(40,0),Vector2(40,0));button(game,start,false)
 check(game.target==initial and not game.left_pan_pending,"new UI press invalidates an older stale map press")
 initial=game.target;button(game,start,true,false,MOUSE_BUTTON_MIDDLE);motion(game,start+Vector2(15,0),Vector2(15,0),MOUSE_BUTTON_MASK_MIDDLE);button(game,start,false,false,MOUSE_BUTTON_MIDDLE)
 check(game.target!=initial,"middle pan preserved")
 initial=game.target;button(game,Vector2(20,300),true,false,MOUSE_BUTTON_MIDDLE);motion(game,start,Vector2(50,0),MOUSE_BUTTON_MASK_MIDDLE);button(game,start,false,false,MOUSE_BUTTON_MIDDLE)
 check(game.target==initial,"middle UI-origin guard preserved")
 game.camera.projection=Camera3D.PROJECTION_PERSPECTIVE;game.update_camera();initial=game.target
 game.pan_camera(Vector2(20,10))
 check(game.target!=initial and game.target.is_finite(),"perspective pan finite and effective")
 game.pan_camera(Vector2(100000,100000))
 check(absf(game.target.x)<=100 and absf(game.target.z)<=70,"pan bounded to terrain")
 for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables","confirmation","param_dialog","param_errors","param_target","data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice"]:
  var node=game.get(key)
  if is_instance_valid(node) and node.get_parent()==null:node.free()
 game.free()
 print("CAMERA_DRAG_V23 checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
