extends SceneTree
const C = preload("res://scripts/device_catalog.gd")
const V = preload("res://scripts/save_validator.gd")
const R = preload("res://scripts/rankine_cycle.gd")
const T = preload("res://scripts/solar_tower_thermal.gd")
const Old = preload("res://tests/test_high_temp_catalog.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func device(id: int, kind: String, position: Vector2 = Vector2.ZERO) -> Dictionary:
	return {"id":id,"kind":kind,"params":C.defaults(kind),"state":C.initial_state(kind),"model_profile":C.model_profile(kind),"model_profile_version":1,"x":0.0,"z":0.0,"parent_station_id":1000000,"interior_x":position.x,"interior_z":position.y}
func edge(a: int,b: int,ap: String,bp: String,carrier: String,grade: String) -> Dictionary:
	return {"from":a,"to":b,"from_port":ap,"to_port":bp,"carrier":carrier,"grade_id":grade,"unit":"MWth","capacity_mwth":1.0,"loss_fraction":0.0}
func blank() -> Dictionary:
	var old = Old.new()
	var s: Dictionary = old.blank()
	old.free()
	s.schema = 12; s.model_version = 21; s.rankine_energy = R.initial_energy(); s.tower_energy = T.initial_energy()
	for kind in V.SCHEMA12_KINDS:
		s.templates[kind] = C.defaults(kind)
	s.stations = [{"id":1000000,"name":"塔式热链","kind":"tower_station","x":0.0,"z":0.0}]
	s.next_station_id = 1000001
	return s
func _initialize() -> void:
	for kind in C.TOWER_KINDS:
		check(C.implemented_kinds().count(kind) == 1,"implemented once " + kind)
		check(C.is_thermal(kind) and C.is_tower(kind),"tower thermal classification " + kind)
		check(C.model_profile(kind) == "tower_stage1_v1","tower profile " + kind)
		check(C.validate_thermal(kind,{}).is_empty(),"valid default " + kind)
		for key in C.defaults(kind):
			for value in [NAN,INF,true,"1",null]:
				check(not C.validate_thermal(kind,{key:value}).is_empty(),"reject invalid " + kind + "/" + key)
	check(not C.validate_thermal("solar_tower_receiver",{"mirror_area_m2":1601}).is_empty(),"fixed physical mirror area")
	check(not C.validate_thermal("solar_tower_receiver",{"supply_temp_c":564}).is_empty(),"fixed hot salt grade")
	check(C.temperature_grade(C.SALT_GRADE).supply_c == 565,"salt hot grade")
	check(C.temperature_grade(C.SALT_GRADE).return_c == 290,"salt cold grade")
	check(C.initial_state("molten_salt_store").energy_mwhth == 0,"initial preheated zero usable inventory")
	check(C.validate_state("molten_salt_store",{}, {"energy_mwhth":0.5}).is_empty(),"full salt inventory")
	check(not C.validate_state("molten_salt_store",{}, {"energy_mwhth":0.5001}).is_empty(),"reject overfull salt inventory")
	var ds: Array = [device(0,"solar_tower_receiver"),device(1,"molten_salt_store"),device(2,"salt_steam_generator"),device(3,"steam_generator"),device(4,"parabolic_trough"),device(5,"station")]
	var salt: Array = [edge(0,1,"heat_out","heat_in",C.SALT_CARRIER,C.SALT_GRADE),edge(0,2,"heat_out","salt_in",C.SALT_CARRIER,C.SALT_GRADE),edge(1,2,"heat_out","salt_in",C.SALT_CARRIER,C.SALT_GRADE)]
	check(C.validate_topology(ds,salt).is_empty(),"salt direct and stored routes")
	for line in [edge(0,3,"heat_out","oil_in",C.SALT_CARRIER,C.SALT_GRADE),edge(4,2,"heat_out","salt_in",C.OIL_CARRIER,C.OIL_GRADE)]:
		check(not C.validate_link(ds,[],line).is_empty(),"salt and oil never cross")
	for id in [0,1,2]:
		check(C.validate_link(ds,[],{"from":5,"to":id,"from_port":"out","to_port":"ac_in","carrier":C.CARRIER,"unit":"MW","capacity_mw":1.0,"loss_fraction":0.0}).is_empty(),"explicit aux AC " + str(id))
	var s := blank()
	check(V.validate(s).is_empty(),"empty tower site valid: " + V.validate(s))
	var expanded_legacy := s.duplicate(true)
	expanded_legacy.templates.battery_sodium = C.defaults("battery_sodium")
	check(not V.validate(expanded_legacy).is_empty(),"schema12 rejects expanded storage templates; requires schema13")
	s.devices = [device(0,"solar_tower_receiver")]; s.next_id = 1
	check(V.validate(s).is_empty(),"centered receiver valid: " + V.validate(s))
	var cycle: Array = [device(10,"salt_steam_generator"),device(11,"steam_turbine"),device(12,"steam_condenser"),device(13,"feedwater_pump")]
	var cycle_links: Array = []
	for spec in [[10,11,"steam_out","steam_in","rankine_live_v1"],[11,12,"exhaust_out","exhaust_in","rankine_exhaust_v1"],[12,13,"condensate_out","condensate_in","rankine_condensate_v1"],[13,10,"feed_out","feed_in","rankine_feedwater_v1"]]:
		cycle_links.append({"from":spec[0],"to":spec[1],"from_port":spec[2],"to_port":spec[3],"carrier":C.MASS_CARRIER,"unit":"kg/s","grade_id":spec[4],"mass_flow_capacity_kg_s":0.05,"loss_fraction":0.0})
	check(C.validate_topology(cycle,cycle_links).is_empty(),"salt SG reuses complete existing fixed-state mass cycle")
	check(not C.validate_link(cycle,cycle_links,cycle_links[0]).is_empty(),"duplicate steam port rejected")
	var encoded: String = JSON.stringify(s)
	check(V.validate(JSON.parse_string(encoded)).is_empty(),"schema12 JSON roundtrip")
	var save_path: String = "res://evidence/tower_stage/tower_schema12_roundtrip.json"
	var file := FileAccess.open(save_path,FileAccess.WRITE); file.store_string(encoded); file.close()
	check(V.validate(JSON.parse_string(FileAccess.get_file_as_string(save_path))).is_empty(),"schema12 persisted file validates after reload")
	check(JSON.stringify(s) == encoded,"save validation is nonmutating")
	var bad := s.duplicate(true); bad.devices[0].erase("parent_station_id");bad.devices[0].erase("interior_x");bad.devices[0].erase("interior_z")
	check(not V.validate(bad).is_empty(),"receiver cannot be freestanding")
	bad=s.duplicate(true);bad.devices[0].interior_x=0.1
	check(not V.validate(bad).is_empty(),"receiver cannot move off tower center")
	bad=s.duplicate(true);bad.devices.append(device(1,"solar_tower_receiver"));bad.next_id=2
	check(not V.validate(bad).is_empty(),"one receiver per site")
	bad=s.duplicate(true);bad.stations[0].kind="thermal_station"
	check(not V.validate(bad).is_empty(),"receiver requires tower facility")
	bad=s.duplicate(true);bad.stations[0].kind="tower_station_preview"
	check(not V.validate(bad).is_empty(),"preview never auto commissions")
	bad=s.duplicate(true);bad.devices=[device(0,"molten_salt_store",Vector2(6,0))]
	check(not V.validate(bad).is_empty(),"salt vessel footprint inside 120m interior")
	bad=s.duplicate(true);bad.erase("tower_energy")
	check(not V.validate(bad).is_empty(),"schema12 requires explicit tower ledger")
	bad=s.duplicate(true);bad.tower_energy.rankine_salt_input_mwhth=1
	check(not V.validate(bad).is_empty(),"reject unbacked salt history")
	bad=s.duplicate(true);bad.rankine_energy.salt_input_mwhth=1
	check(not V.validate(bad).is_empty(),"rankine salt cross-ledger bound")
	var old = Old.new(); var legacy: Dictionary = old.blank(); old.free()
	legacy.schema=11;legacy.model_version=20;legacy.rankine_energy=R.initial_energy()
	for kind in C.RANKINE_KINDS:legacy.templates[kind]=C.defaults(kind)
	legacy.stations=[{"id":1000000,"name":"旧预览","kind":"tower_station_preview","x":0.0,"z":0.0}];legacy.next_station_id=1000001
	var before: String=JSON.stringify(legacy)
	check(V.validate(legacy).is_empty(),"schema11 original templates still validate: " + V.validate(legacy))
	check(JSON.stringify(legacy)==before and not legacy.has("tower_energy") and not legacy.rankine_energy.has("salt_input_mwhth"),"legacy validation adds no tower or salt fields")
	bad=legacy.duplicate(true);bad.stations[0].kind="tower_station"
	check(not V.validate(bad).is_empty(),"schema11 cannot hold commissioned tower")
	bad=legacy.duplicate(true);bad.templates.solar_tower_receiver=C.defaults("solar_tower_receiver")
	check(not V.validate(bad).is_empty(),"schema11 rejects tower template")
	print("TOWER_CATALOG_SAVE: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
