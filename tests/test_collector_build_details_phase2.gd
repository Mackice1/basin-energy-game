extends SceneTree
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func run():
	var world=load("res://main.tscn").instantiate();root.add_child(world);await process_frame
	world.dimension_profile="metric_v1";world.devices=[];world.links=[];world.stations=[];world.next_id=0;world.elapsed_s=0.0;world.rebuild_equipment();world.refresh()
	var kind:="collector_substation"
	check(world.can_place(kind,Vector2.ZERO).is_empty(),"collector real terrain placement")
	check(world.add_equipment(kind,Vector2.ZERO,false),"collector build entry produces independent station")
	var item:Dictionary=world.device(world.selected_id)
	check(item.kind==kind and item.model_profile=="collector_substation_v1" and item.model_profile_version==1,"independent kind and explicit profile")
	check(item.params.capacity_mw==200.0 and item.state.is_empty(),"bounded throughput no energy inventory")
	check(world.Catalog.defaults("station").capacity_mw==4.0,"old compact unit unchanged")
	check(world.BUILD_CATEGORIES.grid.kinds.has(kind) and world.BUILD_CATEGORIES.grid.kinds.has("station"),"both grid build entries retained")
	var node=world.nodes[str(world.selected_id)]
	for port in ["in","out"]:check(node.has_named_port(port),"actual named AC terminal "+port)
	check(world.device_inspector.open_device(world.selected_id),"actual collector secondary page")
	await process_frame
	check(world.device_inspector.texts["边界"].text.contains("不支持变电站级联"),"explicit star-network limitation")
	check(world.device_inspector.texts["参数"].text.contains("200"),"real capacity parameter display")
	world.device_inspector.close_device()
	var s:Dictionary=world.state()
	check(s.schema==world.CURRENT_SAVE_SCHEMA and s.model_version==world.CURRENT_MODEL_VERSION,"collector schema16 model25")
	check(world.validate_state(s).is_empty(),"new full save valid: "+world.validate_state(s))
	var prior:=s.duplicate(true);prior.schema=15;prior.model_version=24;prior.templates.erase(kind)
	check(not world.validate_state(prior).is_empty(),"schema15 rejects independent collector kind")
	prior.devices=[];prior.material_energy=world.Materials.initial_energy_v1();prior.templates={}
	for old_kind in world.Catalog.co2_stage_implemented_kinds():prior.templates[old_kind]=world.Catalog.defaults(old_kind)
	check(world.validate_state(prior).is_empty(),"frozen schema15 without collector remains readable")
	for val in [0,-1,200.1,INF,NAN,"200",true]:
		var bad:=s.duplicate(true);bad.devices[0].params.capacity_mw=val
		check(not world.validate_state(bad).is_empty(),"invalid collector throughput rejected")
	var encoded:=JSON.stringify(s);world.restore(JSON.parse_string(encoded))
	check(world.devices==JSON.parse_string(encoded).devices,"actual restore preserves station identity geometry params")
	world.queue_free();await process_frame;await process_frame
	print("COLLECTOR_BUILD_DETAILS_PHASE2 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
