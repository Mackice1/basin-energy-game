extends SceneTree
const CurrentWorldVersion = preload("res://scripts/world_game.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func run():
	var world=load("res://main.tscn").instantiate();root.add_child(world);await process_frame
	world.dimension_profile="metric_v1";world.devices=[];world.links=[];world.stations=[];world.next_id=0;world.elapsed_s=0.0;world.rebuild_equipment();world.refresh()
	var kind:="co2_liquid_cycle_store"
	check(world.can_place(kind,Vector2(0,-11)).is_empty(),"large CO2 facility has genuinely legal terrain site")
	check(world.add_equipment(kind,Vector2(0,-11),false),"CO2 real build creates complete station")
	var item:Dictionary=world.device(world.selected_id)
	check(item.model_profile=="co2_liquid_cycle_store_v1" and item.model_profile_version==1,"explicit technology profile")
	check(item.state.energy_mwh==0.0,"new CO2 energy empty not free generation")
	var node=world.nodes[str(world.selected_id)]
	check(node.has_named_port("ac"),"real bidirectional AC terminal")
	check(world.Catalog.ports(kind).size()==1,"no accidental heat or material terminal")
	check(world.BUILD_CATEGORIES.storage.kinds.has(kind),"independent storage build entry")
	check(world.device_inspector.open_device(world.selected_id),"CO2 secondary page opens")
	await process_frame
	check(world.device_inspector.texts["边界"].text.contains("非同循环实测"),"secondary page honest performance boundary")
	check(world.device_inspector.texts["参数"].text.contains("794.24"),"internal equivalent inventory displayed")
	world.device_inspector.close_device()
	var s:Dictionary=world.state()
	check(world.validate_state(s).is_empty(),"CO2 full world save valid: "+world.validate_state(s))
	check(s.schema==CurrentWorldVersion.CURRENT_SAVE_SCHEMA and s.model_version==CurrentWorldVersion.CURRENT_MODEL_VERSION,"CO2 save15 model24")
	var prior:=s.duplicate(true);prior.schema=14;prior.model_version=23;prior.templates.erase(kind)
	check(not world.validate_state(prior).is_empty(),"old schema cannot misread CO2 device")
	var bytes:=JSON.stringify(s);world.restore(JSON.parse_string(bytes))
	check(world.devices==JSON.parse_string(bytes).devices,"CO2 restore preserves independent state profile position")
	world.queue_free();await process_frame;await process_frame
	print("CO2_BUILD_DETAILS_PHASE2 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
