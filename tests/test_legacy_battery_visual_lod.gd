extends SceneTree
const V=preload("res://scripts/equipment_visual.gd")
const S=preload("res://scripts/spatial_dimensions.gd")
const C=preload("res://scripts/device_catalog.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var old:=C.defaults("battery")
	old.capacity_mwh=99999.0
	old.visual_dimension_profile="metric_v1"
	old.visual_site_geometry_profile=""
	var before:=var_to_bytes(old)
	var d:=S.profile("battery",old,true,"flow_process_v2","")
	check(d.valid and d.module_count>10000,"extreme historical capacity remains valid legacy geometry")
	var v=V.create("battery",old)
	root.add_child(v)
	check(v.get_meta("visual_valid",false),"extreme historical visual remains readable")
	check(v.get_meta("module_count")==d.module_count,"full analytical historical module count retained")
	check(v.get_meta("display_module_count")==48 and v.get_meta("representative_lod"),"bounded representative LOD explicitly marked")
	check(v.get_meta("body_dimensions_m")==d.body_dimensions_m and v.get_meta("land_dimensions_m")==d.land_dimensions_m,"LOD does not shrink site or occupy less land")
	check(is_equal_approx(v.get_meta("footprint_radius"),d.clearance_radius_world),"full collision envelope retained")
	var modules:=v.find_children("PhysicalModule*","Node3D",false,false)
	check(modules.size()==48,"only 48 whole historical containers actually allocated")
	for i in modules.size():
		var index:=int(round(float(i)*(d.module_count-1)/47.0))
		check(modules[i].position.is_equal_approx(S.module_origin_m(d,index)*.1),"LOD samples complete original layout index "+str(index))
	check(modules[0].position.is_equal_approx(S.module_origin_m(d,0)*.1),"first full-site index included")
	check(modules[-1].position.is_equal_approx(S.module_origin_m(d,d.module_count-1)*.1),"last full-site index included")
	check(v.named_ports.size()==1 and v.has_named_port("ac"),"LOD creates no duplicate simulation ports")
	check(var_to_bytes(old)==before and old.capacity_mwh==99999.0,"legacy capacity and params are never clamped")
	check(v.get_meta("capacity_added")==0.0,"LOD creates no extra capacity")
	v.free()
	var modern:=C.defaults("battery")
	modern.capacity_mwh=20.06;modern.charge_mw=10.0;modern.discharge_mw=10.0
	modern.visual_dimension_profile="metric_v1"
	var complete=V.create("battery",modern)
	root.add_child(complete)
	check(complete.get_meta("visual_valid",false),"maximum supported new installation valid")
	check(complete.get_meta("module_count")==4 and complete.get_meta("display_module_count")==4,"all four new reference containers rendered")
	check(not complete.get_meta("representative_lod"),"new installation never representative LOD")
	check(complete.find_children("PhysicalModule*","Node3D",false,false).size()==4,"new hardware actually contains all four visible boxes")
	complete.free()
	print("LEGACY_BATTERY_VISUAL_LOD checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
