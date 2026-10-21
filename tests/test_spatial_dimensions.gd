extends SceneTree
## Metric geometry and versioned persistence must agree without rescaling saves.
const Spatial = preload("res://scripts/spatial_dimensions.gd")
const Validator = preload("res://scripts/save_validator.gd")
const Model = preload("res://scripts/energy_model.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func near(actual: float, expected: float, label: String, tolerance: float = 0.0001) -> void:
	check(absf(actual - expected) <= tolerance, "%s: %.8f / %.8f" % [label, actual, expected])

# JSON legitimately changes integer numeric variants to floating-point variants.
# Ignore only representation-level precision; preserve IDs, coordinates and stock.
func same_values(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return absf(float(a)-float(b)) <= 1.0e-12 * maxf(1.0,maxf(absf(float(a)),absf(float(b))))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not same_values(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not same_values(a[index],b[index]): return false
		return true
	return a == b

func fixture(dimension_profile: String = "metric_v1") -> Dictionary:
	var templates: Dictionary = {}
	for kind in Validator.PRE_FUEL_KINDS:
		templates[kind] = Model.defaults(kind)
	var electric: Dictionary = {}
	for key in Validator.CURRENT_ENERGY_KEYS:
		electric[key] = 0.0
	var thermal: Dictionary = {}
	for key in Validator.THERMAL_ENERGY_KEYS:
		thermal[key] = 0.0
	var devices: Array = []
	var positions: Array[Vector2] = [Vector2(-1.0,-0.7), Vector2(0.9,-0.6), Vector2(0.0,1.0)]
	# This is intentionally a schema-7 fixture, with its original three internal kinds.
	var legacy_internal := ["electric_boiler", "thermal_store", "heat_exchanger"]
	for index in legacy_internal.size():
		var kind: String = legacy_internal[index]
		devices.append({"id":index, "kind":kind, "params":Model.defaults(kind),
			"state":{"energy_mwhth":1.23456789} if kind == "thermal_store" else {},
			"model_profile":"thermal_stage1_v1", "parent_station_id":1000000,
			"x":23.75 + index, "z":-18.125, "interior_x":positions[index].x, "interior_z":positions[index].y})
	return {"schema":7,"model_version":16,"dimension_profile":dimension_profile,"rebuild":true,
		"devices":devices,"links":[],"imports":[],"templates":templates,"next_id":3,
		"stations":[{"id":1000000,"name":"Metric reference station","x":0.0,"z":0.0}],
		"next_station_id":1000001,"elapsed_s":3612.5,"energy":electric,"thermal_energy":thermal,"physical_lines":true}

func accepted(state: Dictionary, label: String) -> void:
	var original: PackedByteArray = var_to_bytes(state)
	var error: String = Validator.validate(state)
	check(error.is_empty(), label + ": " + error)
	check(original == var_to_bytes(state), label + " is non-mutating")

func rejected(state: Dictionary, label: String, contains: String = "") -> void:
	var original: PackedByteArray = var_to_bytes(state)
	var error: String = Validator.validate(state)
	check(not error.is_empty(), label)
	if not contains.is_empty():
		check(error.contains(contains), label + " reason: " + error)
	check(original == var_to_bytes(state), label + " preserves original")

func _initialize() -> void:
	var pv: Dictionary = Spatial.profile("pv")
	check(pv.valid and pv.panel_count == 2182 and pv.module_count == 2182, "1.2 MWdc requires exactly2182 full-size panels")
	check(pv.columns == 96 and pv.rows == 23, "PV grid uses square-aware5m row/1.2m column pitch")
	near(pv.panel_width_m,1.134,"PV width")
	near(pv.panel_length_m,2.278,"PV length")
	near(pv.tilt_deg,25.0,"PV tilt")
	near(pv.module_area_m2,5636.655864,"PV panel area independent of land")
	near(pv.installed_dc_mwp,1.2001,"PV full module installed nameplate")
	check(pv.land_area_m2 > pv.module_area_m2 and pv.land_envelope_area_m2 > pv.land_area_m2, "PV panel/land/collision-circle areas distinguished")
	check(pv.module_origins_m.size() == 2182 and pv.origins_complete, "defaultPV everypanel represented")
	check(pv.module_origins_m[0] == Spatial.panel_origin_m(pv,0) and pv.module_origins_m[-1] == Spatial.panel_origin_m(pv,2181), "analytical panel centers match explicit origins")
	near(pv.module_origins_m[96].z - pv.module_origins_m[0].z,5.0,"nextpanelrow exactly5m")
	near(pv.module_origins_m[1].x - pv.module_origins_m[0].x,1.2,"nextpanelcolumn exactly1.2m")
	check(pv.module_origins_world[100].is_equal_approx(pv.module_origins_m[100]*0.1), "origins convert metersto world exactlyonce")
	var bounds_only: Dictionary = Spatial.profile("pv",{},false)
	check(bounds_only.module_origins_m.is_empty() and not bounds_only.origins_complete,"bounds-only query skips instance-origin allocation")
	check(bounds_only.module_count == pv.module_count and bounds_only.body_dimensions_m == pv.body_dimensions_m and bounds_only.clearance_radius_world == pv.clearance_radius_world,"bounds-only queries preserve exact full-layout geometry")
	check(Spatial.panel_origin_m(bounds_only,2181) == Spatial.panel_origin_m(pv,2181),"bounds-only query still addresses every panel procedurally")
	var larger_pv: Dictionary = Spatial.profile("pv",{"dc_capacity_mw":2.4})
	check(larger_pv.panel_count == 4364 and larger_pv.unit_dimensions_m == pv.unit_dimensions_m, "doublePVcapacity doublespanels withoutscaling")
	check(larger_pv.land_area_m2 > pv.land_area_m2 and larger_pv.clearance_radius_world > pv.clearance_radius_world, "PVcapacity growsland andcollision")
	var large_pv: Dictionary = Spatial.profile("pv",{"dc_capacity_mw":10000.0})
	check(large_pv.panel_count == 18181819 and not large_pv.origins_complete, "hugePV analytical count retainedwithoutallocation blowup")
	check(large_pv.module_origins_m.size() == Spatial.MAX_EXPLICIT_ORIGINS, "hugePVorigin cache explicitlybounded")
	check(Spatial.panel_origin_m(large_pv,18181818).is_finite(), "hugePVlastpanel still addressable")

	var specs: Dictionary = {"battery":Vector3(6.058,2.896,2.438), "station":Vector3(6.813,2.941,5.538), "electric_boiler":Vector3(4,2.5,2.5), "thermal_store":Vector3(8.5,7.635,5), "heat_exchanger":Vector3(3,1.8,2)}
	for kind in specs:
		var p: Dictionary = Spatial.profile(kind)
		check(p.valid and p.unit_dimensions_m == specs[kind] and p.module_dimensions_m == p.unit_dimensions_m, kind + " exactreference dimensions andalias")
		check(p.module_origins_m.size() == p.module_count and p.module_origins_world.size() == p.module_count, kind + " fullmodulegeometry")
		near(p.body_area_m2,p.module_count*specs[kind].x*specs[kind].z,kind + " bodyarea sumsmodules")
		near(p.land_area_m2,p.land_dimensions_m.x*p.land_dimensions_m.z,kind + " landrectanglearea",0.001)
		near(p.clearance_radius_m,Vector2(p.land_dimensions_m.x,p.land_dimensions_m.z).length()/2.0,kind + " circlecoversrectanglecorners")
		near(p.land_envelope_area_m2,PI*pow(p.clearance_radius_m,2),kind + " circlearea separatelynamed")
		near(p.clearance_radius_world,p.clearance_radius_m*0.1,kind + " singlemetricconversion")
		near(Validator.radius(kind,{},"metric_v1"),p.clearance_radius_world,kind + " validationusesauthoritativeprofile")
		var corner: Vector2 = Vector2(p.land_dimensions_m.x,p.land_dimensions_m.z)*0.5
		for angle in [0.0,PI*0.5]:
			check(corner.rotated(angle).length() <= p.clearance_radius_m + 0.00001,kind + " conservative envelope contains 0/90-degree corners")
	var input_params: Dictionary = Model.defaults("battery")
	var input_snapshot: PackedByteArray = var_to_bytes(input_params)
	Spatial.profile("battery",input_params)
	check(var_to_bytes(input_params) == input_snapshot,"spatial profile never changes capacity or operating parameters")
	var battery: Dictionary = Spatial.profile("battery")
	check(battery.module_count == 2,"10MWh/3MW battery uses2fullcontainers")
	check(Spatial.profile("battery",{"capacity_mwh":5.015,"charge_mw":2.5,"discharge_mw":2.5}).module_count == 1,"exactbatteryreference boundary")
	check(Spatial.profile("battery",{"capacity_mwh":5.016,"charge_mw":2.5,"discharge_mw":2.5}).module_count == 2,"energy boundary addsbattery")
	check(Spatial.profile("battery",{"capacity_mwh":1.0,"charge_mw":7.51,"discharge_mw":0.0}).module_count == 4,"chargingpower independentlycontrols batterycount")
	check(Spatial.profile("battery",{"capacity_mwh":1.0,"charge_mw":0.0,"discharge_mw":5.01}).module_count == 3,"dischargingpower independentlycontrols batterycount")
	check(Spatial.profile("battery",{"capacity_mwh":0.1,"charge_mw":0.0,"discharge_mw":0.0}).unit_dimensions_m == battery.unit_dimensions_m,"deratedbattery doesnotshrink")
	for entry in [{"kind":"station","field":"capacity_mw","rating":2.0}, {"kind":"electric_boiler","field":"rated_electric_mw","rating":2.0}, {"kind":"thermal_store","field":"capacity_mwhth","rating":4.0}, {"kind":"heat_exchanger","field":"capacity_mwth","rating":2.0}]:
		var one: Dictionary = Spatial.profile(entry.kind,{entry.field:entry.rating})
		var three: Dictionary = Spatial.profile(entry.kind,{entry.field:entry.rating*2.01})
		check(one.module_count == 1 and three.module_count == 3,entry.kind + " capacityusesceiling fullmodules")
		check(one.unit_dimensions_m == three.unit_dimensions_m,entry.kind + " capacitypreserves unitgeometry")
		check(three.land_area_m2 > one.land_area_m2,entry.kind + " increasedcapacity reserveslargersite")
		check(Spatial.profile(entry.kind,{entry.field:entry.rating*0.01}).unit_dimensions_m == one.unit_dimensions_m,entry.kind + " deratingdoesnotshrink")

	var wind: Dictionary = Spatial.profile("wind")
	near(wind.body_area_m2,324.0,"windfoundation area")
	near(wind.rotor_radius_m,63.0,"windrotor radius")
	near(wind.clearance_radius_m,70.0,"windrotor plus7mavoidance")
	check(wind.rotor_swept_area_m2 != wind.body_area_m2 and wind.land_envelope_area_m2 != wind.body_area_m2,"windmotionenvelope neverfoundation area")
	var small_wind: Dictionary = Spatial.profile("wind", {"rotor_diameter_m":1.0})
	near(small_wind.clearance_radius_m,Vector2(32.0,32.0).length()*0.5,"small rotor still reserves all maintenance-area corners")
	near(wind.land_area_m2,1024.0,"wind maintenance area excludes swept-motion envelope")
	var site: Dictionary = Spatial.profile("thermal_station")
	check(site.body_dimensions_m == Vector3(80,9.1,60) and site.interior_dimensions_m == Vector3(48,0,48),"siteactual dimensions")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/thermal_asset_manifest.json"))
	for kind in ["electric_boiler", "thermal_store", "heat_exchanger", "thermal_station"]:
		var bounds: Array = manifest.assets[kind].bounds_m
		var actual := Vector3(float(bounds[1][0])-float(bounds[0][0]),float(bounds[1][1])-float(bounds[0][1]),float(bounds[1][2])-float(bounds[0][2]))
		var profile: Dictionary = Spatial.profile(kind)
		check(profile.unit_dimensions_m.is_equal_approx(actual),kind + " profile dimensions match authored GLB manifest in Y-up metres")
		near(profile.body_dimensions_m.y,actual.y,kind + " complete body height includes top fittings")
	near(site.land_area_m2,4800.0,"sitearea includesinterior")
	near(site.interior_area_m2,2304.0,"interiorarea statedseparately")
	near(site.body_area_m2,0.0,"open-airsite isnotonebuilding")
	near(site.clearance_radius_world,5.0,"sitecircle covers80x60 corners")
	for kind in ["load","heat_demand"]:
		var p: Dictionary = Spatial.profile(kind)
		check(p.is_service_marker and p.body_area_m2 == 0.0 and p.land_area_m2 == 0.0,kind + " externalmarkerclaims nophysicalarea")
		near(p.clearance_radius_world,0.25,kind + " markerinteractionradius")
	for entry in [{"kind":"pv","field":"dc_capacity_mw"}, {"kind":"wind","field":"rotor_diameter_m"}, {"kind":"battery","field":"charge_mw"}, {"kind":"thermal_store","field":"capacity_mwhth"}]:
		for value in [INF,NAN,-1.0,"2",true,null,1.0e100]:
			var p: Dictionary = Spatial.profile(entry.kind,{entry.field:value})
			check(not p.valid and not p.errors.is_empty(),entry.kind + " rejectsnonfinite/mistyped/outofrange geometry")
	check(not Spatial.profile("unknown").valid,"unknownkind rejected")

	var state: Dictionary = fixture()
	accepted(state,"schema7metricfixture")
	var original: Dictionary = state.duplicate(true)
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(state))
	accepted(roundtrip,"schema7metricJSONroundtrip")
	check(same_values(roundtrip.devices,original.devices) and same_values(roundtrip.energy,original.energy) and same_values(roundtrip.thermal_energy,original.thermal_energy),"metricroundtrip preservescoordinatesparamsstatesandledgers")
	for iteration in 3:
		roundtrip = JSON.parse_string(JSON.stringify(roundtrip))
		accepted(roundtrip,"repeatedmetricroundtrip%d" % iteration)
	check(same_values(roundtrip.devices,original.devices),"loadsavecycles neverrescalecoordinates")
	for bad in [null,true,0,"metric","METRIC_V1",{},[]]:
		state = fixture(); state.dimension_profile = bad
		rejected(state,"schema7requiresrecognizedprofile","dimension_profile")
	state = fixture(); state.erase("dimension_profile"); rejected(state,"schema7profilecannotbeomitted","dimension_profile")
	state = fixture(); state.model_version = 15; rejected(state,"schema7requiresmodel16","version 16")
	state = fixture(); state.schema = 6; state.model_version = 15; rejected(state,"schema6cannotclaimmetricprofile","schema 7")
	state = fixture(); state.devices[0].interior_x = 2.4; rejected(state,"metricinteriorchecksfullclearance","outside its station interior")
	state = fixture(); state.devices[1].interior_x = -1.0; state.devices[1].interior_z = -0.7; rejected(state,"metricinternalcollision","overlaps")
	state = fixture(); state.devices[1].params.capacity_mwhth = 100.0; rejected(state,"capacitygrowthcannotoutgrowinterior","outside its station interior")
	state = fixture(); state.stations[0].x = 90.0; state.stations[0].z = 60.0; accepted(state,"metricstationtouchesfieldcornerusingradius5")
	state.stations[0].x += 0.01; rejected(state,"metricstationoutsidefield","outside the buildable field")
	state = fixture(); state.stations.append({"id":1000001,"name":"B","x":9.99,"z":0.0}); state.next_station_id = 1000002; rejected(state,"metricstationcollision","overlaps")
	state.stations[1].x = 10.0; accepted(state,"metricstationcirclestouch")
	for value in [INF,NAN,"1",true,null]:
		state = fixture(); state.devices[0].interior_x = value; rejected(state,"nonfiniteinteriorrejected")
		state = fixture(); state.devices[1].params.capacity_mwhth = value; rejected(state,"nonfinitecapacityrejected")
		state = fixture(); state.stations[0].x = value; rejected(state,"nonfinitestationpositionrejected")

	# The exact same legacy coordinates remain readable, never compressed to fit.
	state = fixture("legacy_illustrative")
	state.devices[0].interior_x = -12.0; state.devices[0].interior_z = -8.0
	state.devices[1].interior_x = 12.0; state.devices[1].interior_z = -8.0
	state.devices[2].interior_x = 0.0; state.devices[2].interior_z = 10.0
	accepted(state,"schema7explicitlegacy retainsoldfootprints")
	var saved_legacy: Dictionary = JSON.parse_string(JSON.stringify(state))
	accepted(saved_legacy,"schema7legacyroundtrip")
	check(same_values(saved_legacy.devices,state.devices),"legacyroundtrip retainsalloriginalcoordsandenergy")
	var candidate: Dictionary = state.duplicate(true)
	candidate.dimension_profile = "metric_v1"
	rejected(candidate,"same-coordinate metricmigration rejectsoversizedoldinterior","outside its station interior")
	check(candidate.devices == state.devices,"rejectedmigration mustnotshrinkorrearrange")
	state.schema = 6; state.model_version = 15; state.erase("dimension_profile")
	accepted(state,"schema6originalunchanged")
	near(Validator.radius("thermal_store"),5.0,"legacythermalradius unchanged")
	near(Validator.radius("station"),4.0,"legacyelectricalstationradius unchanged")
	check(Validator.STATION_RADIUS == 8.0 and Validator.INTERIOR_HALF_WIDTH == 24.0,"legacycontainerdimensions retained")

	print("SPATIAL_DIMENSIONS_TEST checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
