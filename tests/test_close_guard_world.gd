extends SceneTree
var checks:=0
var failures:Array[String]=[]
var quit_count:=0
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func run():
 var w=load("res://main.tscn").instantiate();root.add_child(w);await process_frame
 w.scene_close_guard.quit_confirmed.disconnect(w._confirm_application_quit)
 w.scene_close_guard.quit_confirmed.connect(func():quit_count+=1)
 check(not auto_accept_quit,"OS automatic close disabled by actual world")
 w.save_root="user://close_guard_world_"+str(Time.get_ticks_usec());w.new_reference_scene()
 check(w.save_scene_to_slot(0),"isolated fixture saved")
 w.add_equipment("battery",Vector2(170,170),false)
 var before:=JSON.stringify(w.state())
 w.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
 check(w.scene_close_guard.visible and quit_count==0,"actual close notification protects built unsaved scene")
 check(w.modal_visible(),"close decision blocks map interactions")
 check(w.handle_escape() and not w.scene_close_guard.visible and JSON.stringify(w.state())==before,"cancel leaves all parameters inventory and geometry")
 w.add_equipment("collector_substation",Vector2.ZERO,false);w.connect_selected_to_grid();before=JSON.stringify(w.state())
 w.request_application_close();w.scene_close_guard.get_ok_button().pressed.emit()
 check(quit_count==0 and JSON.stringify(w.state())==before,"default cancel preserves newly connected route")
 w.advance(0.25);before=JSON.stringify(w.state());w.request_application_close();w.handle_escape()
 check(quit_count==0 and JSON.stringify(w.state())==before,"runtime inventory and elapsed preserved on close cancellation")
 w.select_device(0);w.open_parameters(false);await process_frame
 check(w.param_dialog.visible,"existing parameter editor fixture open")
 w.request_application_close();await process_frame
 check(w.scene_close_guard.visible and w.scene_close_guard.get_parent()==w.param_dialog,"close protection nests over existing exclusive parameter window")
 w.handle_escape();check(w.param_dialog.visible and not w.scene_close_guard.visible,"cancel preserves existing editor")
 w.request_application_close();w.scene_close_guard.save_button.pressed.emit();await process_frame
 check(w.hud_dock.active_key=="templates" and not w.param_dialog.visible and quit_count==0,"go to save only reveals existing card and dismisses unapplied editor")
 check(JSON.stringify(w.state())==before,"go to save does not apply drafts or mutate scene")
 var good_root:String=w.save_root;w.save_root="res://project.godot/no_directory"
 check(not w.save_scene_to_slot(0) and quit_count==0 and w.scene_is_dirty,"save failure cannot exit or clear dirty state")
 w.save_root=good_root
 w.request_application_close();check(w.scene_close_guard.visible,"failed save remains protected on another close")
 w.handle_escape();check(w.save_scene_to_slot(0),"explicit isolated save succeeds")
 w.request_application_close();check(quit_count==1 and not w.scene_close_guard.visible,"clean scene may exit with actual host signal")
 w.request_application_close();check(quit_count==1,"repeat close after decision emits only once")
 w.queue_free();await process_frame;await process_frame
 print("CLOSE_GUARD_WORLD checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
