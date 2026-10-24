extends SceneTree
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,msg:String)->void:
 checks+=1
 if not ok:failures.append(msg);printerr("FAIL ",msg)
func _initialize():call_deferred("run")
func run()->void:
 root.size=Vector2i(1180,812)
 var w=load("res://main.tscn").instantiate();root.add_child(w);await process_frame
 check(w.beginner_base_example(),"real terrain transaction example")
 check(w.devices.size()==8 and w.links.size()==9,"complete real terrain scene")
 check(w.validate_state(w.state()).is_empty(),"actual terrain/save validation")
 check(w.capacity_comparison_layout_error().is_empty(),"all capacity footprints fit real terrain")
 check(w.result.get("material",{}).get("hydrogen_produced_kg_s",0)>0 and absf(w.result.get("balance_error_mw",1))<1e-6,"actual historical weather dispatch balances without forced export")
 check(w.advance(5.0),"live world5s")
 var before:=var_to_bytes(w.state());var revision:int=w.scene_revision
 w.open_base_workflow();await process_frame
 var panel=w.base_workflow_panel
 check(panel.visible and w.modal_visible(),"panel registered modal")
 panel._compare();await process_frame
 check(panel.running,"batch comparison running")
 w.handle_escape();await process_frame
 check(not panel.visible and not panel.running,"Escape cancels job and closes")
 check(panel.results.text.contains("已取消计算") and not panel.results.text.contains("正在计算"),"cancel replaces stale progress label")
 panel.open();check(panel.results.text.contains("已取消计算"),"reopen keeps explicit cancelled status")
 panel._close()
 check(var_to_bytes(w.state())==before and w.scene_revision==revision,"cancel preserves live state exactly")
 panel.open();panel._compare();panel._close();panel.open();panel._compare()
 await process_frame;await process_frame
 check(panel.running and panel.compare_button.disabled,"stale cancelled coroutine cannot unlock new job")
 panel._close();await process_frame
 panel.open();await panel._compare()
 check(panel.results.text.contains("MWh 电池") and panel.results.text.contains("成本：未建模"),"UI renders actual completed comparisons")
 check(var_to_bytes(w.state())==before and w.scene_revision==revision,"complete comparison preserves live state")
 var completed_text:String=panel.results.text
 panel._close();panel.open()
 check(panel.results.text==completed_text,"closing completed result does not mark it cancelled")
 for size in [Vector2i(1180,812),Vector2i(640,480)]:
  root.size=size;w._layout_workspace();panel.open();await process_frame
  check(panel.size.x<=size.x and panel.size.y<=size.y,"window fits "+str(size))
 panel._close();w.start_build("wind");w._layout_workspace();await process_frame
 check(w.repeat_build_button.visible and w.repeat_build_button.button_pressed,"actual continuous toggle visible")
 w.repeat_build_button.pressed.emit();check(not w.repeat_build,"actual button toggles single mode")
 w.queue_free();await process_frame;await process_frame
 print("BASE_WORKFLOW_NATIVE_SCENE checks=",checks," failures=",failures.size()," headless real-scene controls, not OS clicks")
 quit(0 if failures.is_empty() else 1)
