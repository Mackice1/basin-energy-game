extends SceneTree
const Hint=preload("res://scripts/topology_hint.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures.append(message);push_error(message)
func find_button(node:Node,text:String)->Button:
 if node is Button and node.text==text:return node
 for child in node.get_children():
  var found:=find_button(child,text)
  if found!=null:return found
 return null
func _initialize():call_deferred("run")
func run():
 var w=load("res://main.tscn").instantiate();root.add_child(w);await process_frame
 var shortcut:=find_button(w,"连接外部电网")
 check(shortcut!=null,"actual constructed shortcut button")
 for kind in ["station","collector_substation"]:
  w.new_reference_scene()
  check(w.add_equipment(kind,Vector2.ZERO,false),"actual build "+kind)
  var id:int=w.selected_id
  check(not shortcut.disabled,"station shortcut enabled and outside technical fold")
  check(w.topology_hint_label.text.contains("尚无交流线路"),"fresh station visible topology hint")
  var before:Dictionary=w.state().duplicate(true)
  shortcut.pressed.emit()
  check(w.links.size()==1 and int(w.links[0].from)==id and int(w.links[0].to)==-1,"button connects actual station to grid "+kind)
  check(w.Catalog.validate_link(w.devices,[],w.links[0]).is_empty(),"controller connection has valid actual ports")
  check(w.links[0].capacity_mw==4.0,"external boundary unchanged")
  check(w.topology_hint_label.text.contains("缺少交流输入"),"empty-input fact remains distinct from grid link")
  var count:int=w.undo_states.size();shortcut.pressed.emit()
  check(w.links.size()==1 and w.undo_states.size()==count,"repeat shortcut cannot duplicate or add undo")
  w.undo();check(w.state()==before,"one undo fully restores before shortcut")
  shortcut.pressed.emit();var saved:Dictionary=w.state().duplicate(true)
  check(w.validate_state(saved).is_empty(),"new grid route remains save compatible")
  w.restore(saved);check(w.links==saved.links,"restore retains real connection")
 w.new_reference_scene();w.add_equipment("wind",Vector2.ZERO,false)
 var wind_id:int=w.selected_id;var unchanged:=JSON.stringify(w.state());shortcut.pressed.emit()
 check(w.links.is_empty() and JSON.stringify(w.state())==unchanged,"nonstation shortcut refused without state mutation")
 check(w.topology_hint_label.text.contains("尚未接入汇集站"),"isolated generation gives actionable structural hint")
 var ds:Array=[{"id":0,"kind":"wind"},{"id":1,"kind":"collector_substation"},{"id":2,"kind":"battery"},{"id":3,"kind":"load"}]
 var ls:Array=[{"from":0,"to":1}]
 check(Hint.for_device(0,ds,ls).contains("尚无供电/外送"),"generator detects missing downstream route")
 ls.append({"from":2,"to":1})
 check(Hint.for_device(0,ds,ls).is_empty() and Hint.for_device(1,ds,ls).is_empty(),"bidirectional battery is valid sink even canonical cable points into station")
 check(Hint.for_device(3,ds,ls).contains("尚无交流供电"),"isolated load diagnosed")
 ls.append({"from":1,"to":3})
 check(Hint.for_device(3,ds,ls).is_empty(),"local supply without external grid is not called broken")
 check(Hint.for_device(3,ds,[{"from":1,"to":3}]).contains("上游尚未连接"),"load detects upstream missing source without guessing weather")
 check(Hint.for_device(-2,ds,ls).is_empty(),"no selection no hint")
 check(JSON.stringify(w.state())==unchanged,"diagnostic calls read-only")
 w.queue_free();await process_frame;await process_frame
 print("FIRST_USE_CONNECTIONS checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
