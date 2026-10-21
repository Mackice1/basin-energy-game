extends SceneTree
var checks:=0
var failures:Array[String]=[]
func check(value:bool,message:String):
 checks+=1
 if not value:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func run():
 var w=load("res://main.tscn").instantiate();root.add_child(w);await process_frame
 w.save_root="user://ux_isolated_slots_"+str(Time.get_ticks_usec())
 w.new_reference_scene();w.update_scene_identity(true)
 check(w.scene_name=="空白基地" and w.scene_is_dirty,"new unsaved scene has truthful name and dirty state")
 var before:Dictionary=w.state().duplicate(true)
 w.slot.select(0);w.request_save_slot()
 check(w.confirmation.visible and not FileAccess.file_exists(w.save_root+"/slot0.json"),"save opens confirmation without write")
 w.handle_escape()
 check(not w.confirmation.visible and w.state()==before and w.scene_is_dirty,"Esc cancel leaves scene and saved baseline unchanged")
 check(w.save_scene_to_slot(0),"explicit save succeeds")
 check(not w.scene_is_dirty and w.scene_identity_label.text.contains("已保存"),"successful save marks clean")
 check(w.hud_brand_subtitle.text.contains("空白基地"),"current scene identity also visible in wide-screen header")
 var bytes:String=FileAccess.get_file_as_string(w.save_root+"/slot0.json")
 w.yaw+=.1;w.selected_id=-2;w.update_scene_identity(true)
 check(not w.scene_is_dirty,"camera/selection do not make document dirty")
 w.weather_effects_enabled=not w.weather_effects_enabled;w.scene_status_checked_ms=-1000;w._process(0.0)
 check(w.scene_is_dirty,"saved presentation preference change is tracked")
 w.weather_effects_enabled=not w.weather_effects_enabled;w.update_scene_identity(true)
 check(not w.scene_is_dirty,"reverting saved preference restores clean state")
 check(w.add_equipment("battery",Vector2(170,170)),"reference fixture places")
 w.update_scene_identity(true);check(w.scene_is_dirty,"construction makes unsaved change")
 w.undo();w.update_scene_identity(true);check(not w.scene_is_dirty,"undo back to exact saved state becomes clean")
 w.slot.select(2);before=w.state().duplicate(true);w.request_load_slot()
 check(not w.confirmation.visible and w.state()==before and w.scene_save_feedback.text.contains("为空"),"empty slot reports failure without modal or mutation")
 w.add_equipment("battery",Vector2(170,170));w.slot.select(0);w.request_load_slot()
 check(w.confirmation.dialog_text.contains("未保存"),"load warns about unsaved changes")
 before=w.state().duplicate(true);w.handle_escape();check(w.state()==before,"load cancel has no side effects")
 check(w.load_scene_from_slot(0) and not w.scene_is_dirty and w.devices.is_empty(),"load restores saved scene and clean baseline")
 check(w.scene_name=="空白基地","scene name persisted in optional backwards-compatible metadata")
 w.undo();w.update_scene_identity(true);check(w.devices.size()==1 and w.scene_is_dirty,"undo load restores unsaved previous scene")
 w.slot.select(0);w.request_save_slot();w.slot.select(1);w.confirm_action.call();w.confirmation.hide()
 check(FileAccess.file_exists(w.save_root+"/slot0.json") and not FileAccess.file_exists(w.save_root+"/slot1.json"),"confirmation captures target slot, not later dropdown change")
 var legacy:Dictionary=w.state().duplicate(true);legacy.erase("scene_name")
 check(w.validate_state(legacy)=="","old saves without scene name remain accepted")
 w.restore(legacy);check(w.scene_name=="旧存档场景","legacy scene receives honest fallback name")
 var invalid:Dictionary=legacy.duplicate(true);invalid.scene_name=[]
 check(w.validate_state(invalid).contains("场景名称"),"invalid metadata rejected before mutation")
 var f:=FileAccess.open(w.save_root+"/slot2.json",FileAccess.WRITE);f.store_string("{broken");f.close()
 before=w.state().duplicate(true);check(not w.load_scene_from_slot(2) and w.state()==before,"corrupt load leaves all state unchanged")
 var root_before:String=w.save_root;w.save_root="res://project.godot/not_a_directory";w.update_scene_identity(true);var dirty_before:bool=w.scene_is_dirty
 check(not w.save_scene_to_slot(0) and w.scene_is_dirty==dirty_before,"write failure cannot mark current content saved")
 w.save_root=root_before
 check(FileAccess.get_file_as_string(root_before+"/slot0.json")!="" and bytes!="","existing original save remains readable after failed target")
 # Actual layout containers, not fabricated screenshots.
 for extent in [Vector2i(1180,812),Vector2i(640,480)]:
  root.size=extent;w.hud_dock.close_panels();w.hud_dock.toggle_panel("templates");await process_frame;await process_frame
  var card:Control=w.sidebar_groups.scene_saves
  check(card.is_visible_in_tree(),"save card visible before example expansion at "+str(extent))
  check(card.get_global_rect().size.x<=extent.x,"save card fits viewport width "+str(extent))
  check(w.slot.is_visible_in_tree(),"slot selector reachable without expanding example library")
  var viewport_rect:=Rect2(Vector2.ZERO,Vector2(extent))
  for item in w.slot.get_parent().get_children():
   check(viewport_rect.encloses(item.get_global_rect()),"all save controls fully inside viewport "+str(extent))
   var clip_parent:Node=item.get_parent()
   while clip_parent!=null:
    if clip_parent is Control and clip_parent.clip_contents:check(clip_parent.get_global_rect().encloses(item.get_global_rect()),"save controls not hidden by scroll clipping "+str(extent))
    clip_parent=clip_parent.get_parent()
   item.grab_focus();check(item.has_focus(),"save controls reachable by native keyboard focus")
 w.queue_free();await process_frame;await process_frame
 print("SCENE_SAVE_UX checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
