extends SceneTree
const Existing=preload("res://tests/test_interaction_polish.gd")
const Workflow=preload("res://scripts/example_base_workflow.gd")
const WorkflowPanel=preload("res://scripts/base_workflow_panel.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,msg:String)->void:
 checks+=1
 if not ok:failures.append(msg);printerr("FAIL ",msg)
func _initialize():call_deferred("run")
func run()->void:
 var g=Existing.Fixture.new();root.add_child(g)
 g.climate_config=g.Climate.defaults()
 check(g.add_equipment("wind",Vector2(0,0),false),"original scene device")
 var original:=var_to_bytes(g.state());var undo_size:int=g.undo_states.size()
 check(g.beginner_base_example(),"complete example commits")
 check(g.devices.size()==8 and g.links.size()==9,"8 nodes 9 links")
 check(g.paused and g.elapsed_s==237570.0,"starts paused at historical June3 local17:59:30 before large actual boundary")
 check(g.validate_state(g.state()).is_empty(),"full scene passes save/geometry/ledger validation")
 check(g.imports.size()==3 and g.energy.delivered==0,"historical imports with zero accumulated run")
 check(g.device(4).state.energy_mwh==0 and g.device(7).state.material_inventory_kg.H2==0,"battery/hydrogen start empty")
 check(g.result.get("material",{}).get("hydrogen_produced_kg_s",0)>0 and absf(g.result.get("balance_error_mw",1))<1e-6,"historical initial dispatch balances; export not forced")
 check(g.capacity_comparison_layout_error().is_empty(),"all capacity variants pass placement bounds")
 check(g.advance(10.0),"real1s world advance10s")
 check(g.material_energy.get("hydrogen_produced_kg",0)>0 and g.device(5).state.material_inventory_kg.H2O<10000,"real finite water use and hydrogen accumulation")
 check(g.validate_state(g.state()).is_empty(),"advanced scene valid")
 check(g.undo_states.size()==undo_size+1,"one undo checkpoint")
 g.undo();check(var_to_bytes(g.state())==original,"one undo restores original scene exactly")
 # UI panel can construct without starting a comparison or replacing state.
 var panel:=WorkflowPanel.new();g.add_child(panel);panel.setup(g);panel._refresh()
 check(panel.current.text.contains("当前场景") and panel.results.text.contains("尚未计算"),"panel opens truthful initial state")
 check(not panel.running and var_to_bytes(g.state())==original,"inspection doesn't mutate live state")
 check(g.beginner_base_example(237570.0),"explicit large-change new example loads")
 check(g.elapsed_s==237570.0 and g.energy.generated==0 and g.device(4).state.energy_mwh==0 and g.device(7).state.material_inventory_kg.H2==0,"selected period starts fresh empty inventories and zero ledger")
 var before_sent:float=g.result.devices["0"].sent_mw
 check(g.advance(61.0),"real integration crosses selected historical boundary")
 check(float(g.result.devices["0"].sent_mw)>before_sent+1.0,"actual sent wind visibly changes, not just potential")
 var selected_state:Dictionary=g.state()
 check(not g.beginner_base_example(INF) and g.state()==selected_state,"invalid custom start no mutation")
 for key in ["terrain","infrastructure","overlay","confirmation","param_dialog","param_errors","param_target","data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice"]:
  var node=g.get(key)
  if is_instance_valid(node) and node.get_parent()==null:node.free()
 g.free();await process_frame
 print("BASE_WORKFLOW_INTEGRATION checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
