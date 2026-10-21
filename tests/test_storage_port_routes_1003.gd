extends SceneTree
const World=preload("res://scripts/world_game.gd")
const Catalog=preload("res://scripts/device_catalog.gd")
class BoundaryProbe:
	extends Node3D
	func get_port_position(name:String)->Vector3:
		return {"ac_in":Vector3(1,0,0),"ac_out":Vector3(2,0,0),"heat_in":Vector3(0,0,1),"heat_out":Vector3(0,0,2),"heat_primary_in":Vector3(0,0,3),"heat_primary_out":Vector3(0,0,4)}.get(name,Vector3.ZERO)
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func device(id:int,kind:String,parent:int=-1)->Dictionary:
	var p:=Catalog.defaults(kind)
	var result:Dictionary={"id":id,"kind":kind,"params":p,"state":Catalog.initial_state(kind,p),"x":0.0,"z":0.0}
	if parent>=0:result.parent_station_id=parent
	return result
func _initialize():call_deferred("run")
func run():
	var world:=World.new()
	for kind in Catalog.NEW_STORAGE_KINDS+["molten_salt_store"]:
		check(world.can_place(kind,Vector2.ZERO).contains("米制"),kind+" blocked before placing in legacy save")
		check(not world.add_equipment(kind,Vector2.ZERO),kind+" legacy add rejects")
		check(world.devices.is_empty() and world.undo_states.is_empty() and world.next_id==0,kind+" legacy reject is before mutation")
	for kind in Catalog.ELECTRIC_STORAGE_KINDS:
		world.devices=[device(0,kind),device(1,"station")]
		var forward:Dictionary=world.connection_candidate(0,1)
		var backward:Dictionary=world.connection_candidate(1,0)
		check(forward==backward,kind+" click order canonical")
		check(forward.get("from_port","")=="ac" and forward.get("to_port","")=="in",kind+" catalog AC bidirectional ports")
		check(Catalog.validate_link(world.devices,[],forward)=="",kind+" route legal")
	for pair in [["electric_boiler","solid_thermal_store",100,-1],["fuel_boiler","solid_thermal_store",100,-1],["solar_thermal","solid_thermal_store",100,-1],["solid_thermal_store","heat_exchanger",-1,100],["solar_tower_receiver","molten_salt_store",100,-1],["molten_salt_store","salt_steam_generator",-1,100]]:
		world.devices=[device(0,pair[0],pair[2]),device(1,pair[1],pair[3])]
		var forward:Dictionary=world.connection_candidate(0,1)
		check(not forward.is_empty(),"standalone storage boundary "+str(pair))
		check(forward==world.connection_candidate(1,0),"thermal click order "+str(pair))
		check(Catalog.validate_link(world.devices,[],forward)=="","Catalog permits selected thermal ports")
	for pair in [["electric_boiler","thermal_store",100,101],["solar_tower_receiver","molten_salt_store",100,101],["molten_salt_store","salt_steam_generator",100,101],["solid_thermal_store","salt_steam_generator",-1,100],["molten_salt_store","heat_exchanger",-1,100]]:
		world.devices=[device(0,pair[0],pair[2]),device(1,pair[1],pair[3])]
		check(world.connection_candidate(0,1).is_empty(),"reject arbitrary crossing or wrong carrier "+str(pair))
	world.devices=[device(0,"station"),device(1,"molten_salt_store"),device(2,"solar_tower_receiver",100),device(3,"salt_steam_generator",100)]
	world.links=[world.connection_candidate(0,1)]
	var status:String=world.thermal_connection_status(1)
	check(status.contains("充热口未接") and status.contains("放热口未接") and not status.contains("均已连接"),"AC-only salt store does not claim heat connection")
	world.links.append(world.connection_candidate(2,1));status=world.thermal_connection_status(1)
	check(not status.contains("充热口未接") and status.contains("放热口未接"),"salt input without output explicitly reported")
	world.links.append(world.connection_candidate(1,3));status=world.thermal_connection_status(1)
	check(status.contains("均已连接"),"full salt and AC topology reports connected")
	world.links.remove_at(0);status=world.thermal_connection_status(1)
	check(status.contains("未接AC电源") and not status.contains("充热口未接"),"salt-only wiring still requires auxiliary AC")
	world.stations=[{"id":100,"name":"测试塔站","kind":"tower_station"},{"id":101,"name":"测试热站","kind":"thermal_station"},{"id":102,"name":"预览","kind":"tower_station_preview"}]
	world.devices.append(device(4,"heat_exchanger",101))
	check(world.endpoint_description(100).contains("565/290") and not world.endpoint_description(100).contains("70/40"),"tower boundary lists actual salt grade")
	check(world.endpoint_description(101).contains("70/40"),"thermal boundary includes mapped secondary output")
	check(world.endpoint_description(102).contains("无能量端口"),"preview never advertises working ports")
	check(world.thermal_grade_label("salt_565_290").contains("565/290"),"salt line grade label")
	check(world.thermal_grade_label("oil_300_200").contains("300/200"),"oil line grade label")
	var probe:=BoundaryProbe.new();world.station_nodes["100"]=probe
	world.devices.append(device(5,"molten_salt_store",100))
	check(world.endpoint(2,"heat_out")==probe.get_port_position("heat_out"),"internal receiver salt output drawn at thermal output anchor")
	check(world.endpoint(5,"heat_in")==probe.get_port_position("heat_in"),"internal molten salt input drawn at thermal input anchor")
	check(world.endpoint(3,"salt_in")==probe.get_port_position("heat_in"),"steam generator salt input not AC anchor")
	check(world.endpoint(5,"ac_in")==probe.get_port_position("ac_in"),"salt pump retains separate AC anchor")
	world.station_nodes["101"]=probe
	check(world.endpoint(4,"hot_in")==probe.get_port_position("heat_primary_in"),"primary HX input uses90/60 anchor")
	check(world.endpoint(4,"warm_out")==probe.get_port_position("heat_out"),"secondary HX output preserves70/40 anchor")
	check(world.visual_station(world.stations[1]).has_primary_storage_boundary,"thermal station advertises actual primary hook-up")
	world.links=[];world.pending_link=2
	check(world.connection_caption(1).contains("565/290") and not world.connection_caption(1).contains("70/40"),"connection preview reports correct salt grade")
	world.station_nodes.clear();probe.free()
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables","confirmation","param_dialog","param_errors","param_target","data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice"]:
		var node=world.get(key)
		if is_instance_valid(node) and node.get_parent()==null:node.free()
	world.free()
	print("STORAGE_PORT_ROUTES_1003 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
