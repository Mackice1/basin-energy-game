extends SceneTree
## Source-sized electrochemical hardware, not a replacement physics model.
const Spatial = preload("res://scripts/spatial_dimensions.gd")
const Visual = preload("res://scripts/equipment_visual.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const Support = preload("res://scripts/site_layout_support.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func near(a: float,b: float,label: String) -> void:
	check(absf(a-b)<0.00001,label)
func _initialize() -> void: call_deferred("run")
func vertices(item: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	var batched := item.find_child("StorageFacilityGeometry",true,false) as MeshInstance3D
	for surface in batched.mesh.get_surface_count():
		var array: PackedVector3Array = batched.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for point in array: points.append(batched.transform*point)
	return points
func has_point(points: PackedVector3Array,target: Vector3) -> bool:
	for point in points:
		if point.distance_to(target)<0.00001: return true
	return false
func run() -> void:
	for kind in ["battery_sodium","battery_flow"]:
		var p: Dictionary = Catalog.defaults(kind)
		var saved := var_to_bytes(p)
		var state := var_to_bytes(Catalog.initial_state(kind,p))
		var d: Dictionary = Spatial.profile(kind,p)
		var hardware: Dictionary = Support.geometry(kind)
		check(d.valid,kind+" reference profile valid")
		check(d.module_count==hardware.hardware_module_count_cap,kind+" fixed shared hardware module count")
		var reduced := p.duplicate(true)
		reduced.capacity_mwh = 0.01
		reduced.charge_mw = 0.0
		reduced.discharge_mw = 0.0
		var low: Dictionary = Spatial.profile(kind,reduced)
		check(low.valid and low.module_count==d.module_count and low.body_dimensions_m==d.body_dimensions_m and low.land_dimensions_m==d.land_dimensions_m,kind+" derating retains all fixed hardware")
		var signatures: Array = []
		for input in [p,reduced]:
			var input_saved := var_to_bytes(input)
			var v = Visual.create(kind,input)
			root.add_child(v)
			check(v.get_meta("visual_valid",false),kind+" generated visual valid")
			check(v.get_meta("module_count")==d.module_count,kind+" actual visual fixed module count")
			check(v.get_meta("reference_capacity_basis")==d.reference_capacity_basis,kind+" explicit energy basis")
			check(v.named_ports.size()==1 and v.has_named_port("ac"),kind+" one aggregate AC port")
			near(v.get_meta("capacity_added"),0.0,kind+" no hidden simulation inventory")
			var g := v.find_child("StorageFacilityGeometry",true,false) as MeshInstance3D
			var box := g.mesh.get_aabb()
			check(box.position.y>=-0.00001 and box.end.y<=d.body_dimensions_m.y*.1+.00001,kind+" actual height fits")
			check(box.size.x<=d.body_dimensions_m.x*.1+.00001 and box.size.z<=d.body_dimensions_m.z*.1+.00001,kind+" actual footprint fits")
			var points := vertices(v)
			signatures.append(points)
			if kind=="battery_sodium":
				check(d.module_count==3,"sodium three whole cabinets")
				check(d.unit_dimensions_m==Vector3(9,3.5,4),"sodium auxiliary unit is not cabinet outer size")
				check(d.reference_container_dimensions_m==Vector3(7.12,2.896,2.8),"sodium conservative PDF cabinet axes")
				near(d.reference_capacity_per_module,2.5,"sodium source nominal energy per cabinet")
				near(d.reference_power_per_module,1.25,"sodium source rated power per cabinet")
				near(d.reference_hardware_energy_mwh,7.5,"sodium installed source energy")
				near(d.reference_hardware_power_mw,3.75,"sodium installed source power")
				near(d.reference_hardware_energy_mwh*hardware.usable_energy_allocation_fraction,6.0,"sodium explicitly allocated six MWh")
				var anchors := v.find_children("SourceSizedSodiumCabinet*","Node3D",true,false)
				check(anchors.size()==3,"sodium three source-sized visible enclosures")
				for anchor in anchors:
					check(anchor.get_meta("outer_dimensions_m")==d.reference_container_dimensions_m,"sodium anchor dimensions match shared contract")
					var half: Vector3 = d.reference_container_dimensions_m*.05
					var center: Vector3 = v.to_local(anchor.global_position)
					for x in [-1,1]:
						for y in [-1,1]:
							for z in [-1,1]:
								check(has_point(points,center+Vector3(x*half.x,y*half.y,z*half.z)),"sodium rendered shell corner exact, no inflated foundation shell")
			else:
				check(d.module_count==2,"flow two fixed complete process plants")
				check(d.reference_process_units_per_module==6 and d.reference_process_unit_count==12,"flow twelve source two-storey units")
				check(v.find_children("FlowProcessUnit*","Node3D",true,false).size()==12,"flow all twelve units actually drawn")
				near(d.reference_capacity_per_module,12.0,"flow source AC nameplate is not old ten MWh assumption")
				near(d.reference_hardware_energy_mwh_ac,24.0,"flow source hardware AC energy")
				near(d.reference_hardware_power_mw_ac,4.0,"flow plant-rated source hardware AC power")
				check(str(d.reference_capacity_basis).contains("AC_delivered") and str(d.reference_capacity_basis).contains("not_internal"),"flow separates AC and internal inventory")
			check(var_to_bytes(input)==input_saved,kind+" visual leaves input parameters untouched")
			v.free()
		check(signatures[0]==signatures[1],kind+" all rendered vertices unchanged by derating")
		check(var_to_bytes(p)==saved and var_to_bytes(Catalog.initial_state(kind,p))==state,kind+" original params and initial state unchanged")
		for key in ["capacity_mwh","charge_mw","discharge_mw"]:
			var over := p.duplicate(true); over[key]=float(p[key])+.001
			check(not Spatial.profile(kind,over).valid,kind+" game support bound unchanged "+key)
		var old: Dictionary = Spatial.profile(kind,p,true,"flow_process_v2","")
		check(old.valid and old.module_count==2,kind+" legacy default still two historical modules")
		near(old.reference_capacity_per_module,5.0 if kind=="battery_sodium" else 10.0,kind+" old replication threshold unchanged")
		check(not old.has("reference_hardware"),kind+" legacy not relabeled as source-proven hardware")
		var old_params := p.duplicate(true); old_params.visual_site_geometry_profile=""
		var old_visual = Visual.create(kind,old_params)
		root.add_child(old_visual)
		check(old_visual.get_meta("module_count")==2 and old_visual.get_meta("site_geometry_profile")=="",kind+" old marker keeps old visual")
		check(not old_visual.has_meta("reference_capacity_basis"),kind+" old teaching geometry has no new source claim")
		old_visual.free()
	check(not Spatial.profile("battery_flow",{},true,"flow_icon_v1").valid,"new flow reference cannot masquerade as old compact icon")
	check(Spatial.profile("battery_flow",{},true,"flow_icon_v1","").valid,"old compact flow icon remains readable")
	print("SODIUM_FLOW_REFERENCE_CAPACITY checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
