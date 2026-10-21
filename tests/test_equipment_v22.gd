extends SceneTree
const Visual = preload("res://scripts/equipment_visual.gd")
const Interior = preload("res://scripts/station_interior.gd")
const TestHost = preload("res://tests/test_station_interior.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func _initialize():call_deferred("run")
func run():
	for kind in ["electric_boiler","thermal_store","heat_exchanger"]:
		var item=Visual.create(kind,{"visual_dimension_profile":"metric_v1"},true)
		root.add_child(item)
		check(item.named_ports.size()==2,kind+" retains two logical ports")
		check(item.physical_return_locals.size()==(1 if kind=="electric_boiler" else 2),kind+" has independent physical return nozzles")
		for port_id in item.physical_return_locals:
			var ret: Vector3=item.physical_return_locals[port_id]
			check(ret.distance_to(item.named_port_locals[port_id])>.015,kind+" physical return is separate from supply")
		check(item.get_meta("capacity_added")==0.0,kind+" adds no energy capacity")
		item.free()
	var host=TestHost.Host.new();host.dimension_profile="metric_v1";root.add_child(host)
	for spec in [["electric_boiler",Vector2(-1.35,0)],["thermal_store",Vector2(0,.2)],["heat_exchanger",Vector2(1.35,0)]]:
		host.add_internal_device(0,spec[0],spec[1])
	host.connect_internal_devices(0,1);host.connect_internal_devices(1,2)
	var before=var_to_bytes(host.devices);var links_before=var_to_bytes(host.links)
	var inside=Interior.new();host.add_child(inside);inside.setup(host);inside.open_station(0)
	await process_frame
	for route in inside.connections_root.get_children():
		if not route.name.begins_with("HeatPipe"):continue
		check(route.get_meta("route_style")=="physical_low_service_corridor","low corridor uses real nozzle exits")
		var points:PackedVector3Array=route.get_meta("route_points")
		check(points[0].is_equal_approx(route.get_meta("source_position")),"supply starts at catalog port")
		check(points[-1].is_equal_approx(route.get_meta("target_position")),"supply ends at catalog port")
		check(route.has_node("PhysicalReturnService"),"water pair includes physical return without extra edge")
		var ret=route.get_node("PhysicalReturnService")
		var rpoints:PackedVector3Array=ret.get_meta("route_points")
		check(rpoints[0].is_equal_approx(inside._physical_return(route.get_meta("from"),route.get_meta("from_port"))),"return begins at authored nozzle")
		check(rpoints[-1].is_equal_approx(inside._physical_return(route.get_meta("to"),route.get_meta("to_port"))),"return ends at authored nozzle")
		check(ret.get_meta("visual_only") and ret.get_meta("capacity_added")==0.0,"return geometry adds no simulated capacity")
		check(route.find_children("PipeSupportColumn*","MeshInstance3D",true,false).size()>0,"route is mechanically supported")
		for point in points:check(point.y<.25,"short water service does not jump over tank roof")
	check(var_to_bytes(host.devices)==before and var_to_bytes(host.links)==links_before,"geometry refresh preserves device and edge data")
	print("EQUIPMENT_V22_TEST checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
