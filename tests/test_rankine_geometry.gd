extends SceneTree
const Spatial = preload("res://scripts/spatial_dimensions.gd")
const Visual = preload("res://scripts/equipment_visual.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _init() -> void:
	for kind in Visual.RANKINE_KINDS:
		var d := Spatial.profile(kind)
		check(d.valid and d.module_count == 1, "single default module: " + kind)
		check(d.unit_dimensions_m.x >= 2 and d.unit_dimensions_m.z >= 1.2, "physical envelope never miniature")
		var enlarged: Dictionary = Catalog.defaults(kind)
		enlarged[d.rating_parameter] = float(d.reference_rating_per_module) * 2.05
		# Current finite hardware rejects oversized ratings. Historical scenes
		# still retain the original replicated-module geometry without migration.
		check(not Spatial.profile(kind,enlarged).valid, "current reference hardware rejects enlarged rating: " + kind)
		var big := Spatial.profile(kind,enlarged,true,"flow_process_v2","")
		check(big.module_count == 3 and big.unit_dimensions_m == d.unit_dimensions_m, "oversize rating adds full modules: " + kind)
		check(big.land_area_m2 > d.land_area_m2 and big.installed_reference_rating >= big.requested_rating, "expanded installation remains full size")
		check(not Spatial.profile(kind,{d.rating_parameter:-1}).valid, "negative rating rejected")
		check(not Spatial.profile(kind,{d.rating_parameter:NAN}).valid, "nonfinite rating rejected")
		var derated: Dictionary = Catalog.defaults(kind)
		derated[d.rating_parameter] = float(d.reference_rating_per_module) * .25
		var low := Spatial.profile(kind,derated)
		check(low.valid and low.module_count==d.module_count and low.unit_dimensions_m==d.unit_dimensions_m and low.body_dimensions_m==d.body_dimensions_m and low.land_dimensions_m==d.land_dimensions_m, "current derating retains complete hardware and installation: " + kind)
		var historical_enlarged := enlarged.duplicate(true)
		historical_enlarged.visual_site_geometry_profile = ""
		var definitions := Visual.rankine_port_definitions(kind)
		check(Catalog.ports(kind).size() == definitions.size(), "catalog exact port count")
		for port_id in definitions:
			var catalog_port := Catalog.port(kind,port_id)
			check(not catalog_port.is_empty() and catalog_port.get("carrier") == definitions[port_id][3] and catalog_port.get("direction") == definitions[port_id][1], "visual matches authoritative catalog carrier/direction")
			check(catalog_port.get("grade_id", "") == definitions[port_id][2], "visual matches authoritative catalog grade")
		var expected := Visual.thermal_asset_definition(kind)
		check(expected.get("ports",{}).size() == definitions.size(), "manifest exact number of ports")
		for imported in [false,true]:
			for params in [{},derated,historical_enlarged]:
				var before: PackedByteArray = var_to_bytes(params)
				var site_profile: String = str(params.get("visual_site_geometry_profile","reference_size_v1"))
				var profile := Spatial.profile(kind,params,true,"flow_process_v2",site_profile)
				var item = Visual.create(kind,params,imported)
				root.add_child(item)
				check(var_to_bytes(params)==before,"geometry never changes requested ratings: " + kind)
				check(item.get_meta("site_geometry_profile")==site_profile,"current versus historical geometry identity: " + kind)
				check(item.get_meta("visual_backend") == ("blender_glb" if imported else "metric_procedural_fallback"), "Rankine backend: " + kind)
				check(item.scale == Vector3.ONE and item.get_meta("world_units_per_meter") == .1, "one conversion only")
				check(item.get_meta("capacity_added") == 0 and item.get_meta("modules_share_simulation_limits"), "geometry does not add capacity")
				check(item.find_children("RankineModule*", "Node3D", true, false).size() == profile.module_count, "module quantity exact")
				check(item.named_ports.size() == definitions.size(), "one aggregate port set regardless module count")
				for port_id in definitions:
					var spec: Array = definitions[port_id]
					check(item.has_named_port(port_id), "explicit port exists: " + port_id)
					if not item.named_ports.has(port_id): continue # failed assertion, not an invalid-key test hang
					var port: Node3D = item.named_ports[port_id]
					check(port.get_meta("carrier") == spec[3] and port.get_meta("direction") == spec[1], "typed direction: " + port_id)
					check(port.get_meta("unit") == ("kg/s" if spec[3] == "water_steam" else "MWth" if spec[3] in ["heat_oil","heat_salt"] else "MW"), "mass/heat/electric units: " + port_id)
					if not str(spec[2]).is_empty(): check(port.get_meta("grade_id") == spec[2], "state grade: " + port_id)
					check(item.named_port_locals[port_id].is_equal_approx(profile.module_origins_world[0] + spec[0]*.1), "first module anchor: " + port_id)
					if imported:
						var anchor := item.get_node("RankineModule001").find_child("Port_"+port_id,true,false) as Node3D
						check(anchor != null and Visual._position_relative_to(anchor,item).is_equal_approx(item.named_port_locals[port_id]), "GLB anchor exact: " + port_id)
				for surface in item.surfaces:
					if surface == item.selection_ring: continue
					var a: AABB = Visual._relative_transform(surface,item) * surface.mesh.get_aabb()
					var half: Vector3 = profile.body_dimensions_m * .05
					check(a.position.x >= -half.x-.0001 and a.end.x <= half.x+.0001 and a.position.z >= -half.z-.0001 and a.end.z <= half.z+.0001, "physical module envelope " + kind + "/" + surface.name + " " + str(a))
					check(a.position.y >= -.0001 and a.end.y <= profile.body_dimensions_m.y*.1+.0001, "above ground and within height: " + kind + "/" + surface.name)
				item.set_preview(false)
				check(item.preview_enabled, "preview tint active")
				item.clear_preview()
				check(not item.preview_enabled, "preview tint cleared")
				item.free()
	print("RANKINE_GEOMETRY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
