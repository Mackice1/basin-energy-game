extends SceneTree
## Independent analytic chemistry/phase ledger tests; no dispatch/solver/UI.
const L = preload("res://scripts/material_ledger_v3.gd")
const V2 = preload("res://scripts/material_ledger_v2.gd")
const WATER := 18.015 / 2.016
const OXYGEN := 15.999 / 2.016
const HHV := 285830.0 / 2.016 / 3600000.0
const LHV := 241826.0 / 2.016 / 3600000.0
const WATER_H := -285830.0 / 18.015 / 3600000.0
const MASS_RATES := ["water_withdrawn_kg_s", "hydrogen_produced_kg_s", "hydrogen_consumed_kg_s", "hydrogen_charged_kg_s", "hydrogen_discharged_kg_s", "oxygen_vented_kg_s", "oxygen_from_air_kg_s", "water_released_kg_s", "ammonia_produced_kg_s", "methanol_produced_kg_s", "nitrogen_withdrawn_kg_s", "co2_withdrawn_kg_s", "chemical_hydrogen_consumed_kg_s", "chemical_water_released_kg_s"]
const POWERS := ["electrolyzer_electric_mw", "compression_electric_mw", "fuel_cell_output_mw", "heat_rejected_mwth", "phase_store_electric_mw", "environment_heat_in_mwth", "chemical_electric_mw"]
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("LEDGER_V3_FAIL: " + label)

func near(a: float, b: float, label: String, tolerance: float = 1.0e-9) -> void:
	check(is_finite(a) and absf(a - b) <= tolerance, label + " (%s != %s)" % [a, b])

func device(id: int, kind: String, mass: float = 0.0, host: float = 1000.0) -> Dictionary:
	var species: String = {"water_supply_boundary":"H2O", "nitrogen_supply_boundary":"N2", "co2_supply_boundary":"CO2", "ammonia_synthesis_station":"NH3", "methanol_synthesis_station":"CH3OH"}.get(kind,"H2")
	var state: Dictionary = {"material_inventory_kg":{species:mass}}
	var params: Dictionary = {"capacity_kg":1000.0 if kind == "hydrogen_liquid_store" else 1.0e9}
	if kind in ["nitrogen_supply_boundary", "co2_supply_boundary", "ammonia_synthesis_station", "methanol_synthesis_station"]: params = {}
	if kind == "hydrogen_metal_hydride_store":
		params = {"dry_host_mass_kg":host}
		state.host_dry_mass_kg = host
	return {"id":id, "kind":kind, "params":params, "state":state}

func reference(kind: String) -> String:
	match kind:
		"water_supply_boundary": return "H2O_liquid_25c"
		"hydrogen_gas_store": return "H2_gas_25c"
		"hydrogen_liquid_store": return "H2_liquid_20k"
		"hydrogen_metal_hydride_store": return "H2_bound_lani5"
		"nitrogen_supply_boundary": return "N2_gas_25c"
		"co2_supply_boundary": return "CO2_gas_25c"
		"ammonia_synthesis_station": return "NH3_gas_25c"
		"methanol_synthesis_station": return "CH3OH_liquid_25c"
	return ""

func report(devices: Array, dt: float) -> Dictionary:
	var m: Dictionary = {"hydrogen_leaked_kg":0.0, "hydrogen_leak_lhv_mwh":0.0, "inventory_by_reference_kg":L.empty_inventory(), "dry_host_by_device_kg":{}}
	for key in MASS_RATES + POWERS: m[key] = 0.0
	var result: Dictionary = {"valid":true, "dt_s":dt, "material":m, "devices":{}, "next_states":{}}
	for d in devices:
		var id: String = str(int(d.id))
		result.devices[id] = {"kind":d.kind, "valid":true}
		result.next_states[id] = d.state.duplicate(true)
		m.inventory_by_reference_kg[reference(d.kind)] += float(d.state.material_inventory_kg.values()[0])
		if d.kind == "hydrogen_metal_hydride_store": m.dry_host_by_device_kg[id] = d.state.host_dry_mass_kg
	return result

func add_charge(r: Dictionary, kg: float, store_kwh: float, phase_delta: float) -> void:
	var seconds: float = r.dt_s
	var m: Dictionary = r.material
	m.water_withdrawn_kg_s = kg * WATER / seconds
	m.hydrogen_produced_kg_s = kg / seconds
	m.hydrogen_charged_kg_s = kg / seconds
	m.oxygen_vented_kg_s = kg * OXYGEN / seconds
	m.electrolyzer_electric_mw = 0.050 * kg * 3600.0 / seconds
	if phase_delta == 0.0: m.compression_electric_mw = store_kwh * kg * 3.6 / seconds
	else: m.phase_store_electric_mw = store_kwh * kg * 3.6 / seconds
	m.heat_rejected_mwth = (0.050 + store_kwh / 1000.0 - HHV - phase_delta / 1000.0) * kg * 3600.0 / seconds

func add_discharge(r: Dictionary, kg: float, store_kwh: float, phase_delta: float, ambient: bool) -> void:
	var m: Dictionary = r.material
	var seconds: float = r.dt_s
	m.hydrogen_consumed_kg_s = kg / seconds
	m.hydrogen_discharged_kg_s = kg / seconds
	m.water_released_kg_s = kg * WATER / seconds
	m.oxygen_from_air_kg_s = kg * OXYGEN / seconds
	m.fuel_cell_output_mw = kg * LHV * 0.5 * 3600.0 / seconds
	m.phase_store_electric_mw = kg * store_kwh * 3.6 / seconds
	m.environment_heat_in_mwth = -phase_delta * kg * 3.6 / seconds if ambient else 0.0
	var store_heat: float = store_kwh + (0.0 if ambient else phase_delta)
	m.heat_rejected_mwth = (HHV - LHV * 0.5 + store_heat / 1000.0) * kg * 3600.0 / seconds

func _initialize() -> void:
	test_initial_and_coefficients()
	test_shape_and_adversarial_inputs()
	test_inventory_boundaries()
	test_one_kg_cycles()
	test_boiloff_and_time_units()
	test_legacy_bootstrap()
	test_long_history()
	test_nested_types_and_cancellation()
	test_json_device_identifiers()
	test_chemical_reactions()
	test_chemical_phase_supply()
	test_chemical_boundaries_and_forgery()
	test_v2_upgrade_preserves_every_anchor()
	test_chemical_long_history_and_roundtrip()
	print("MATERIAL_LEDGER_V3: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_initial_and_coefficients() -> void:
	var ds: Array = [device(1,"water_supply_boundary",100), device(2,"hydrogen_gas_store",10), device(3,"hydrogen_liquid_store",5), device(4,"hydrogen_metal_hydride_store",3)]
	var saved: Array = ds.duplicate(true)
	var ledger: Dictionary = L.initial_energy(ds)
	check(not ledger.is_empty(), "initial ledger opens actual inventory")
	check(ds == saved, "initialization pure")
	check(ledger.size() == 43, "exact versioned ledger shape")
	check(ledger.ledger_version == 3 and ledger.ledger_profile == "material_reference_ledger_v3", "version/profile explicit")
	check(L.validate_energy(ledger,ds).is_empty(), "initial world matches ledger")
	near(ledger.current_reference_enthalpy_mwh,100 * WATER_H - 5 * 0.00124 - 3 * 0.004275,"formation + phase/binding enthalpy")
	near(ledger.current_atoms_kg.H,100 * 2.016 / 18.015 + 18,"hydrogen atom mass")
	near(ledger.current_atoms_kg.O,100 * 15.999 / 18.015,"oxygen atom mass")
	for prefix in ["opening","current","imported","exported"]:
		check(ledger[prefix+"_inventory_kg"].size()==9,"nine fixed references "+prefix)
		check(ledger[prefix+"_atoms_kg"].size()==4,"four fixed elements "+prefix)
	near(ledger.imported_reference_enthalpy_mwh,0,"opening not fake import")
	var material: Dictionary=L.empty_inventory()
	material.CO2_gas_25c=44.009;material.NH3_gas_25c=17.031;material.CH3OH_liquid_25c=32.042;material.N2_gas_25c=28.014
	var atoms: Dictionary=L.atoms_for_inventory(material)
	near(atoms.H,7*1.008,"future chemical H atoms")
	near(atoms.C,2*12.011,"future chemical C atoms")
	near(atoms.N,3*14.007,"future chemical N atoms")
	near(atoms.O,3*15.999,"future chemical O atoms")
	near(L.enthalpy_for_inventory(material),(-393510.0-45940.0-238400.0)/3600000.0,"future formation enthalpies")
	var changed: Array=ds.duplicate(true);changed[2].kind="hydrogen_gas_store"
	check(not L.validate_energy(ledger,changed).is_empty(),"phase relabel rejected")
	changed=ds.duplicate(true);changed[3].state.host_dry_mass_kg+=1
	check(not L.validate_energy(ledger,changed).is_empty(),"world dry host state tamper rejected")
	changed=ds.duplicate(true);changed[3].params.dry_host_mass_kg+=1;changed[3].state.host_dry_mass_kg+=1
	check(not L.validate_energy(ledger,changed).is_empty(),"coherent world host reconfiguration rejected")
	changed=ds.duplicate(true);changed[2].id=99
	check(not L.validate_energy(ledger,changed).is_empty(),"same aggregate with substituted device rejected")
	changed=ds.duplicate(true);changed.append(device(99,"hydrogen_gas_store",0))
	check(not L.validate_energy(ledger,changed).is_empty(),"extra zero-inventory device rejected")
	var large: Array=[device(1,"hydrogen_gas_store",1.0e9)]
	var big: Dictionary=L.initial_energy(large);large[0].state.material_inventory_kg.H2-=1
	check(not L.validate_energy(big,large).is_empty(),"one kg tamper on 1e9 kg stock rejected")
	big.current_inventory_kg.H2_gas_25c-=1;big.current_inventory_by_device["1"].mass_kg-=1;big.current_atoms_kg.H-=1
	check(not L.validate_energy(big).is_empty(),"coherent one kg atom theft at 1e9 rejected")

func test_shape_and_adversarial_inputs() -> void:
	var base: Dictionary=L.initial_energy()
	for invalid in [null,[],0,"ledger",true]:
		check(not L.validate_energy(invalid).is_empty(),"invalid top-level ledger "+str(invalid))
		check(L.accumulate_energy(invalid,{},1).is_empty(),"invalid accumulation ledger")
		check(not L.bootstrap_from_legacy(invalid,[]).valid,"invalid bootstrap ledger")
	for key in base:
		var bad: Dictionary=base.duplicate(true);bad.erase(key)
		check(not L.validate_energy(bad).is_empty(),"missing field "+key)
		for invalid in [null,[],"bad",NAN,INF,true]:
			bad=base.duplicate(true);bad[key]=invalid
			check(not L.validate_energy(bad).is_empty(),"bad field "+key+" "+str(invalid))
	var bad: Dictionary=base.duplicate(true);bad.surprise=0
	check(not L.validate_energy(bad).is_empty(),"extra field rejected")
	for map_key in ["current_inventory_kg","current_atoms_kg"]:
		bad=base.duplicate(true);bad[map_key].extra=0
		check(not L.validate_energy(bad).is_empty(),"extra map key "+map_key)
		for key in base[map_key]:
			for invalid in [-1.0,NAN,INF,null,"0",true]:
				bad=base.duplicate(true);bad[map_key][key]=invalid
				check(not L.validate_energy(bad).is_empty(),"invalid nested amount "+key)
	var d: Dictionary=device(1,"hydrogen_metal_hydride_store",13,1000)
	check(L.initial_energy([d]).is_empty(),"fixed dry-host capacity cannot be exceeded")
	check(L.initial_energy(null).is_empty(),"null devices rejected without exception")
	check(not L.import_inventory_event(base,null).valid,"null import rejected without exception")
	check(not L.remove_inventory_event(base,null).valid,"null removal rejected without exception")
	check(L.atoms_for_inventory(null).is_empty() and is_nan(L.enthalpy_for_inventory(null)),"invalid calculator input rejected")
	check(is_nan(L.cumulative_electric_input_mwh(null)),"invalid electric history returns NAN")

func test_inventory_boundaries() -> void:
	var base: Dictionary=L.initial_energy()
	var d: Dictionary=device(5,"hydrogen_liquid_store",2)
	var encoded: String=JSON.stringify(base)
	var imported: Dictionary=L.import_inventory_event(base,d)
	check(imported.valid,"phase stock import boundary accepted")
	check(JSON.stringify(base)==encoded,"successful import does not mutate source")
	near(imported.ledger.imported_inventory_kg.H2_liquid_20k,2,"import retains phase mass")
	near(imported.ledger.imported_reference_enthalpy_mwh,-0.00248,"import signed phase enthalpy")
	check(not L.import_inventory_event(imported.ledger,d).valid,"duplicate import ID rejected")
	check(not L.remove_inventory_event(imported.ledger,d).valid,"nonempty facility removal rejected")
	var metal: Dictionary=device(6,"hydrogen_metal_hydride_store",0,1000)
	var added: Dictionary=L.import_inventory_event(imported.ledger,metal)
	check(added.valid,"empty LaNi5 facility imports real dry host")
	near(added.ledger.imported_dry_host_by_device_kg["6"],1000,"host import explicit")
	var removed: Dictionary=L.remove_inventory_event(added.ledger,metal)
	check(removed.valid,"empty LaNi5 removal accepted")
	near(removed.ledger.exported_dry_host_by_device_kg["6"],1000,"host export explicit")
	check(not removed.ledger.current_dry_host_by_device_kg.has("6"),"removed host not current")
	check(not removed.ledger.current_inventory_by_device.has("6"),"removed zero-stock device unregistered")
	check(not L.remove_inventory_event(removed.ledger,metal).valid,"duplicate removal rejected")
	check(L.validate_energy(removed.ledger,[d]).is_empty(),"post-removal full world matches")
	var before: String=JSON.stringify(added.ledger)
	metal.state.host_dry_mass_kg=999
	check(not L.remove_inventory_event(added.ledger,metal).valid,"wrong host removal rejected")
	check(JSON.stringify(added.ledger)==before,"failed removal atomic")

func test_one_kg_cycles() -> void:
	for spec in [["hydrogen_gas_store",3.0,0.0,0.0,false],["hydrogen_liquid_store",12.0,-1.24,0.02,true],["hydrogen_metal_hydride_store",0.15,-4.275,0.15+4.475/0.95,false]]:
		var ds: Array=[device(1,"water_supply_boundary",100),device(2,spec[0],0)]
		var ledger: Dictionary=L.initial_energy(ds)
		var original: String=JSON.stringify(ledger)
		ds[0].state.material_inventory_kg.H2O-=WATER;ds[1].state.material_inventory_kg.H2=1.0
		var charge: Dictionary=report(ds,7200.0);add_charge(charge,1.0,spec[1],spec[2])
		var charged: Dictionary=L.accumulate_energy(ledger,charge,7200.0)
		check(not charged.is_empty(),"one kg charge "+spec[0])
		check(JSON.stringify(ledger)==original,"accumulation never mutates input "+spec[0])
		if charged.is_empty():continue
		check(L.validate_energy(charged,ds).is_empty(),"charged world audit "+spec[0])
		near(charged.water_withdrawn_kg,WATER,"rate times seconds exactly once")
		near(charged.electrolyzer_electric_mwh,0.05,"power times hours exactly once")
		near(charged.exported_inventory_kg.O2_gas_25c,OXYGEN,"electrolysis O2 export")
		near(charged.current_reference_enthalpy_mwh-charged.opening_reference_enthalpy_mwh,HHV+float(spec[2])/1000.0,"reaction plus phase storage")
		ds[1].state.material_inventory_kg.H2=0.0
		var discharge: Dictionary=report(ds,1800.0);add_discharge(discharge,1.0,spec[3],spec[2],spec[4])
		var final: Dictionary=L.accumulate_energy(charged,discharge,1800.0)
		check(not final.is_empty(),"one kg discharge "+spec[0])
		if final.is_empty():continue
		check(L.validate_energy(final,ds).is_empty(),"closed cycle world audit "+spec[0])
		near(final.imported_inventory_kg.O2_gas_25c,OXYGEN,"fuel cell air boundary")
		near(final.exported_inventory_kg.H2O_liquid_25c,WATER,"fuel cell water boundary")
		near(final.exported_reference_enthalpy_mwh,-HHV,"released water negative formation enthalpy")
		near(final.fuel_cell_output_mwh,LHV*0.5,"LHV electric statistic separate")
		near(L.cumulative_electric_input_mwh(final),(50.0+float(spec[1])+float(spec[3]))/1000.0,"total real electrical consumption")
		var bad: Dictionary=charge.duplicate(true);bad.material.heat_rejected_mwth=0.0;bad.material.enthalpy_balance_error_mw=0.0
		check(L.accumulate_energy(ledger,bad,7200.0).is_empty(),"forged zero residual cannot conceal missing heat")
		bad=charge.duplicate(true);bad.material.oxygen_vented_kg_s=0.0
		check(L.accumulate_energy(ledger,bad,7200.0).is_empty(),"missing oxygen exit rejected")
		bad=charge.duplicate(true);bad.next_states["2"].material_inventory_kg.H2=2.0
		check(L.accumulate_energy(ledger,bad,7200.0).is_empty(),"next-state vs material snapshot forgery rejected")
		bad=charge.duplicate(true);bad.devices["2"].kind="hydrogen_gas_store" if spec[0]!="hydrogen_gas_store" else "hydrogen_liquid_store"
		check(L.accumulate_energy(ledger,bad,7200.0).is_empty(),"report cannot relabel phase")

func test_boiloff_and_time_units() -> void:
	var ds: Array=[device(1,"hydrogen_liquid_store",10)]
	var ledger: Dictionary=L.initial_energy(ds)
	ds[0].state.material_inventory_kg.H2=9.0
	var r: Dictionary=report(ds,60.0)
	r.material.hydrogen_leaked_kg=1.0;r.material.hydrogen_leak_lhv_mwh=LHV;r.material.environment_heat_in_mwth=0.00124*60.0
	var next: Dictionary=L.accumulate_energy(ledger,r,60.0)
	check(not next.is_empty(),"passive liquid boiloff with ambient heat")
	if not next.is_empty():
		near(next.hydrogen_leaked_kg,1,"leak is kg per step, never kg/s")
		near(next.environment_heat_in_mwhth,0.00124,"full endpoint ambient heat")
		near(next.exported_inventory_kg.H2_gas_25c,1,"vent exits warm reference gas")
		near(next.exported_reference_enthalpy_mwh,0,"leak LHV not double counted as enthalpy")
	var bad: Dictionary=r.duplicate(true);bad.material.environment_heat_in_mwth=0
	check(L.accumulate_energy(ledger,bad,60.0).is_empty(),"boiloff without ambient heat rejected")
	bad=r.duplicate(true);bad.material.hydrogen_leaked_kg=1.0/60.0;bad.material.hydrogen_leak_lhv_mwh=LHV/60.0
	check(L.accumulate_energy(ledger,bad,60.0).is_empty(),"kg leak misrepresented as rate rejected")
	for dt in [-1.0,NAN,INF,null,"60",true,61.0]:
		check(L.accumulate_energy(ledger,r,dt).is_empty(),"invalid/mismatched step duration")
	for key in MASS_RATES+POWERS+["hydrogen_leaked_kg","hydrogen_leak_lhv_mwh"]:
		for value in [-1.0,null,"0",NAN,INF,true]:
			bad=r.duplicate(true);bad.material[key]=value
			check(L.accumulate_energy(ledger,bad,60.0).is_empty(),"invalid report scalar "+key)
	var paused: Dictionary=report([device(1,"hydrogen_liquid_store",10)],0.0)
	check(L.accumulate_energy(ledger,paused,0.0)==ledger,"paused exact inventory no operation")
	paused.material.phase_store_electric_mw=1.0
	check(L.accumulate_energy(ledger,paused,0.0).is_empty(),"pause cannot hide a nonzero power")
	paused=report(ds,0.0)
	check(L.accumulate_energy(ledger,paused,0.0).is_empty(),"pause cannot change inventory")
	var missing: Dictionary=r.duplicate(true);missing.next_states.erase("1")
	check(L.accumulate_energy(ledger,missing,60.0).is_empty(),"missing next state rejected")
	var metal: Array=[device(1,"hydrogen_metal_hydride_store",0)]
	var ml: Dictionary=L.initial_energy(metal);var mr: Dictionary=report(metal,60.0)
	mr.next_states["1"].host_dry_mass_kg+=1;mr.material.dry_host_by_device_kg["1"]+=1
	check(L.accumulate_energy(ml,mr,60.0).is_empty(),"report cannot import dry host silently")

func test_legacy_bootstrap() -> void:
	var old: Dictionary=L.initial_energy_v1()
	old.water_withdrawn_kg=2*WATER;old.hydrogen_produced_kg=2;old.hydrogen_charged_kg=2;old.oxygen_vented_kg=2*OXYGEN
	old.electrolyzer_electric_mwh=0.1;old.compression_electric_mwh=0.006;old.heat_rejected_mwhth=0.106-2*HHV
	old.hydrogen_leaked_kg=0.25;old.hydrogen_leak_lhv_mwh=0.25*LHV
	check(L.validate_energy_v1(old).is_empty(),"independent exact v1 chemistry validation")
	var ds: Array=[device(1,"water_supply_boundary",500),device(2,"hydrogen_gas_store",1.75)]
	var encoded: String=JSON.stringify(old)
	var migrated: Dictionary=L.bootstrap_from_legacy(old,ds)
	check(migrated.valid,"bootstrap actual stock plus old history")
	check(JSON.stringify(old)==encoded,"bootstrap leaves old historical counters untouched")
	if not migrated.valid:return
	var ledger: Dictionary=migrated.ledger
	check(ledger.legacy_v1_history==old,"history copied exactly")
	near(ledger.current_inventory_kg.H2_gas_25c,1.75,"no invented reconstruction from cumulative production")
	near(ledger.opening_inventory_kg.H2O_liquid_25c,500,"opening actual water stock")
	near(ledger.hydrogen_produced_kg,0,"v2 period starts with zero process totals")
	near(ledger.imported_inventory_kg.H2_gas_25c,0,"legacy not reimported")
	near(L.cumulative_electric_input_mwh(ledger),0.106,"historical electric use still counted")
	var serialized: Variant=JSON.parse_string(JSON.stringify(ledger))
	check(L.validate_energy(serialized,ds).is_empty(),"v2 JSON reload remains anchored")
	var next: Dictionary=L.accumulate_energy(ledger,report(ds,1),1)
	check(not next.is_empty() and next.legacy_v1_history==old,"old history read-only during new steps")
	for field in old:
		var bad: Dictionary=old.duplicate(true);bad.erase(field)
		check(not L.bootstrap_from_legacy(bad,ds).valid,"legacy missing field "+field)
	var bad: Dictionary=old.duplicate(true);bad.heat_rejected_mwhth+=0.001
	check(not L.bootstrap_from_legacy(bad,ds).valid,"legacy bad enthalpy cannot be laundered into v2")
	bad=old.duplicate(true);bad.water_withdrawn_kg+=1
	check(not L.bootstrap_from_legacy(bad,ds).valid,"legacy bad reaction rejected")
	check(not L.bootstrap_from_legacy(ledger,ds).valid,"v2 cannot be bootstrapped again")

func test_long_history() -> void:
	var ds: Array=[device(1,"water_supply_boundary",1.0e6),device(2,"hydrogen_metal_hydride_store",0)]
	var ledger: Dictionary=L.initial_energy(ds)
	for i in 2000:
		var quantity: float=0.001+(i%7)*0.0001
		ds[0].state.material_inventory_kg.H2O-=quantity*WATER
		ds[1].state.material_inventory_kg.H2=quantity
		var charge: Dictionary=report(ds,17.0);add_charge(charge,quantity,0.15,-4.275)
		ledger=L.accumulate_energy(ledger,charge,17.0)
		if ledger.is_empty():check(false,"long history charge "+str(i));return
		ds[1].state.material_inventory_kg.H2=0.0
		var discharge: Dictionary=report(ds,19.0);add_discharge(discharge,quantity,0.15+4.475/0.95,-4.275,false)
		ledger=L.accumulate_energy(ledger,discharge,19.0)
		if ledger.is_empty():check(false,"long history discharge "+str(i));return
		if i%100==0:ledger=JSON.parse_string(JSON.stringify(ledger))
	check(L.validate_energy(ledger,ds).is_empty(),"4000 steps with repeated JSON reload closes atoms and enthalpy")
	near(ledger.hydrogen_produced_kg,ledger.hydrogen_consumed_kg,"long history equal hydrogen cycle",1e-10)
	near(ledger.current_dry_host_by_device_kg["2"],1000,"host immutable over long history")
	var forged: Dictionary=ledger.duplicate(true)
	forged.current_inventory_kg.H2O_liquid_25c-=1.0
	forged.current_inventory_by_device["1"].mass_kg-=1.0
	forged.current_atoms_kg=L.atoms_for_inventory(forged.current_inventory_kg)
	forged.current_reference_enthalpy_mwh=L.enthalpy_for_inventory(forged.current_inventory_kg)
	check(not L.validate_energy(forged).is_empty(),"one kg theft not concealed by long history")


func test_nested_types_and_cancellation() -> void:
	var ds: Array=[device(1,"hydrogen_liquid_store",1)]
	var ledger: Dictionary=L.initial_energy(ds)
	for field in ["kind","reference_id","mass_kg","host_dry_mass_kg"]:
		for invalid in [null,[],{},true,NAN,INF,"bad"]:
			var bad: Dictionary=ledger.duplicate(true);bad.current_inventory_by_device["1"][field]=invalid
			check(not L.validate_energy(bad).is_empty(),"nested per-device malformed "+field)
	var r: Dictionary=report(ds,1)
	for invalid in [null,[],{},1,"true"]:
		var bad: Dictionary=r.duplicate(true);bad.valid=invalid
		check(L.accumulate_energy(ledger,bad,1).is_empty(),"report validity must be explicit boolean")
		bad=r.duplicate(true);bad.devices["1"].valid=invalid
		check(L.accumulate_energy(ledger,bad,1).is_empty(),"device validity must be explicit boolean")
	for invalid in [null,[],true,0,"1"]:
		var changed: Array=ds.duplicate(true);changed[0].params=invalid
		check(L.initial_energy(changed).is_empty(),"invalid device parameters rejected safely")
	var forged: Dictionary=L.initial_energy()
	forged.imported_inventory_kg.CO2_gas_25c=44.009;forged.exported_inventory_kg.CO2_gas_25c=44.009
	for prefix in ["imported","exported"]:
		forged[prefix+"_atoms_kg"]=L.atoms_for_inventory(forged[prefix+"_inventory_kg"])
		forged[prefix+"_reference_enthalpy_mwh"]=L.enthalpy_for_inventory(forged[prefix+"_inventory_kg"])
	check(not L.validate_energy(forged).is_empty(),"future coefficients do not silently enable unsupported boundaries")
	forged=L.initial_energy()
	forged.imported_inventory_kg.O2_gas_25c=1;forged.exported_inventory_kg.O2_gas_25c=1
	for prefix in ["imported","exported"]:forged[prefix+"_atoms_kg"]=L.atoms_for_inventory(forged[prefix+"_inventory_kg"])
	check(not L.validate_energy(forged).is_empty(),"balanced but fabricated oxygen history rejected")
	# A closed huge-throughput gas cycle: global energy cancellation should get
	# ULP-scale slack, not a 2e-7 fraction of the gross historical electricity.
	var history: Dictionary=L.initial_energy([device(1,"water_supply_boundary",1.0e9)])
	var quantity: float=1.0e10
	history.water_withdrawn_kg=quantity*WATER;history.hydrogen_produced_kg=quantity;history.hydrogen_charged_kg=quantity
	history.hydrogen_consumed_kg=quantity;history.hydrogen_discharged_kg=quantity;history.water_released_kg=quantity*WATER
	history.oxygen_vented_kg=quantity*OXYGEN;history.oxygen_from_air_kg=quantity*OXYGEN
	history.electrolyzer_electric_mwh=quantity*0.05;history.compression_electric_mwh=quantity*0.003
	history.fuel_cell_output_mwh=quantity*LHV*0.5
	history.heat_rejected_mwhth=quantity*0.053-history.fuel_cell_output_mwh
	history.imported_inventory_kg.H2O_liquid_25c=quantity*WATER;history.exported_inventory_kg.H2O_liquid_25c=quantity*WATER
	history.imported_inventory_kg.O2_gas_25c=quantity*OXYGEN;history.exported_inventory_kg.O2_gas_25c=quantity*OXYGEN
	for prefix in ["imported","exported"]:
		history[prefix+"_atoms_kg"]=L.atoms_for_inventory(history[prefix+"_inventory_kg"])
		history[prefix+"_reference_enthalpy_mwh"]=L.enthalpy_for_inventory(history[prefix+"_inventory_kg"])
	check(L.validate_energy(history).is_empty(),"large cancelling reference/atomic history remains valid")
	history.heat_rejected_mwhth+=0.001
	check(not L.validate_energy(history).is_empty(),"one kWh forged heat rejected amid 530 million MWh throughput")


func test_json_device_identifiers() -> void:
	var ds: Array=[device(0,"water_supply_boundary",123.456),device(3,"hydrogen_liquid_store",1.234),device(2147483646,"hydrogen_metal_hydride_store",2.345)]
	var ledger: Dictionary=L.initial_energy(ds)
	var decoded_devices: Variant=JSON.parse_string(JSON.stringify(ds))
	var decoded_ledger: Variant=JSON.parse_string(JSON.stringify(ledger))
	check(L.validate_energy(ledger,decoded_devices).is_empty(),"JSON device numeric IDs canonicalize against original ledger")
	check(L.validate_energy(decoded_ledger,decoded_devices).is_empty(),"device and ledger JSON roundtrip preserves exact identity")
	decoded_devices=JSON.parse_string(JSON.stringify(decoded_devices))
	decoded_ledger=JSON.parse_string(JSON.stringify(decoded_ledger))
	check(L.validate_energy(decoded_ledger,decoded_devices).is_empty(),"double device and ledger JSON roundtrip remains anchored")
	var reopened: Dictionary=L.initial_energy(decoded_devices)
	check(not reopened.is_empty() and reopened.current_inventory_by_device==decoded_ledger.current_inventory_by_device and reopened.current_inventory_kg==decoded_ledger.current_inventory_kg,"opening ledger retains exact stock/identity from JSON float IDs")
	var r: Dictionary=report(ds,0)
	check(not L.accumulate_energy(decoded_ledger,r,0).is_empty(),"decoded ledger accepts canonical runtime report IDs")
	var empty: Dictionary=JSON.parse_string(JSON.stringify(device(8,"hydrogen_gas_store",0)))
	var added: Dictionary=L.import_inventory_event(decoded_ledger,empty)
	check(added.valid and added.ledger.current_inventory_by_device.has("8"),"JSON float device import uses canonical ID")
	if added.valid:check(L.remove_inventory_event(added.ledger,empty).valid,"JSON float device removal uses canonical ID")
	for invalid in [-1,-1.0,true,false,3.5,NAN,INF,2147483647,2147483647.0,"3.0","03","+3","-0","-1","2147483647","",[],null]:
		var bad: Dictionary=device(3,"hydrogen_gas_store",0);bad.id=invalid
		check(L.initial_energy([bad]).is_empty(),"invalid/aliased material device ID rejected "+str(invalid))
		check(not L.import_inventory_event(ledger,bad).valid,"invalid/aliased event ID rejected")
	var alias: Dictionary=ledger.duplicate(true)
	alias.current_inventory_by_device["3.0"]=alias.current_inventory_by_device["3"];alias.current_inventory_by_device.erase("3")
	check(not L.validate_energy(alias).is_empty(),"ledger map cannot contain noncanonical ID alias")
	var duplicates: Array=[device(3,"hydrogen_gas_store",0),device(3,"hydrogen_liquid_store",0)]
	duplicates[1].id=3.0
	check(L.initial_energy(duplicates).is_empty(),"integer and JSON float aliases cannot create two devices")

# These analytic fixtures derive masses and heats directly from the reaction
# equations and independently selected atomic/formation data, not dispatcher
# helpers, optimizer variables, or implementation stoichiometry constants.
func chemical_world() -> Array:
	return [device(10,"hydrogen_gas_store",200.0),device(11,"nitrogen_supply_boundary",1000.0),device(12,"co2_supply_boundary",1000.0),device(13,"ammonia_synthesis_station",0.0),device(14,"methanol_synthesis_station",0.0)]

func apply_chemistry(ds: Array, ammonia: float, methanol: float) -> void:
	ds[0].state.material_inventory_kg.H2 -= ammonia*6.048/34.062 + methanol*6.048/32.042
	ds[1].state.material_inventory_kg.N2 -= ammonia*28.014/34.062
	ds[2].state.material_inventory_kg.CO2 -= methanol*44.009/32.042
	ds[3].state.material_inventory_kg.NH3 += ammonia
	ds[4].state.material_inventory_kg.CH3OH += methanol

func add_chemistry(r: Dictionary, ammonia: float, methanol: float, electric: float = -1.0) -> void:
	var m: Dictionary = r.material
	var dt: float = r.dt_s
	var h2: float = ammonia*6.048/34.062 + methanol*6.048/32.042
	var water: float = methanol*18.015/32.042
	# Arbitrary, declared 0.8/1 kWh/kg whole-station AC assumptions. All AC
	# finishes as rejected heat, plus independent signed reaction enthalpy.
	if electric < 0.0: electric = ammonia*0.0008 + methanol*0.001
	m.ammonia_produced_kg_s = ammonia/dt
	m.methanol_produced_kg_s = methanol/dt
	m.nitrogen_withdrawn_kg_s = ammonia*28.014/34.062/dt
	m.co2_withdrawn_kg_s = methanol*44.009/32.042/dt
	m.chemical_hydrogen_consumed_kg_s = h2/dt
	m.chemical_water_released_kg_s = water/dt
	m.hydrogen_discharged_kg_s += h2/dt
	m.water_released_kg_s += water/dt
	m.chemical_electric_mw = electric*3600.0/dt
	m.heat_rejected_mwth += (electric+ammonia*45940.0/17.031/3600000.0+methanol*130720.0/32.042/3600000.0)*3600.0/dt

func refresh_for_test(ledger: Dictionary) -> void:
	for prefix in ["opening","current","imported","exported"]:
		ledger[prefix+"_atoms_kg"] = L.atoms_for_inventory(ledger[prefix+"_inventory_kg"])
		ledger[prefix+"_reference_enthalpy_mwh"] = L.enthalpy_for_inventory(ledger[prefix+"_inventory_kg"])

func test_chemical_reactions() -> void:
	for quantities in [[34.062,0.0],[0.0,32.042],[34.062,32.042],[0.001,0.002]]:
		for dt in [1.0,7.0,3600.0]:
			var ds: Array = chemical_world()
			var ledger: Dictionary = L.initial_energy(ds)
			check(not ledger.is_empty(),"chemical initial references accepted")
			if ledger.is_empty(): return
			var initial: Dictionary = ledger.duplicate(true)
			apply_chemistry(ds,quantities[0],quantities[1])
			var r: Dictionary = report(ds,dt)
			add_chemistry(r,quantities[0],quantities[1])
			var saved: Dictionary = r.duplicate(true)
			var result: Dictionary = L.accumulate_energy(ledger,r,dt)
			check(not result.is_empty(),"analytic ammonia/methanol reaction closes at dt "+str(dt))
			check(ledger==initial and r==saved,"chemical accumulation is pure")
			if result.is_empty(): return
			check(L.validate_energy(result,ds).is_empty(),"chemical result anchors to exact device world")
			near(result.ammonia_produced_kg,quantities[0],"ammonia product counter")
			near(result.methanol_produced_kg,quantities[1],"methanol product counter")
			near(result.current_inventory_kg.NH3_gas_25c,quantities[0],"NH3 gas stock retained")
			near(result.current_inventory_kg.CH3OH_liquid_25c,quantities[1],"methanol liquid stock retained")
			near(result.imported_inventory_kg.N2_gas_25c,0.0,"source withdrawal not nitrogen import")
			near(result.imported_inventory_kg.CO2_gas_25c,0.0,"source withdrawal not carbon import")
			near(result.hydrogen_consumed_kg,0.0,"chemical consumption never labeled fuel-cell H2")
			near(result.hydrogen_discharged_kg,result.chemical_hydrogen_consumed_kg,"all-store discharge includes chemistry")
			near(result.exported_inventory_kg.H2O_liquid_25c,quantities[1]*18.015/32.042,"liquid byproduct leaves explicit environmental boundary")
			near(L.cumulative_electric_input_mwh(result),quantities[0]*0.0008+quantities[1]*0.001,"chemical AC included in all-time input")
			for element in ["H","C","N","O"]:
				near(result.opening_atoms_kg[element]+result.imported_atoms_kg[element]-result.current_atoms_kg[element]-result.exported_atoms_kg[element],0.0,"independent atom closure "+element)
			check(L.accumulate_energy(result,r,dt).is_empty(),"replaying chemical delta cannot duplicate its material transaction")
			check(L.validate_energy(JSON.parse_string(JSON.stringify(result)),JSON.parse_string(JSON.stringify(ds))).is_empty(),"chemical JSON roundtrip preserves anchors")
			for key in ["ammonia_produced_kg","methanol_produced_kg","nitrogen_withdrawn_kg","co2_withdrawn_kg","chemical_hydrogen_consumed_kg","chemical_water_released_kg"]:
				var bad: Dictionary = result.duplicate(true); bad[key] += 1.0
				check(not L.validate_energy(bad).is_empty(),"chemical cumulative counter forgery rejected "+key)
			var bad: Dictionary = result.duplicate(true); bad.chemical_electric_mwh += 0.001
			check(not L.validate_energy(bad).is_empty(),"unaccounted chemical AC rejected")
	# Combined electrochemistry and fuel cell keeps FC-only oxygen distinct.
	var ds: Array = chemical_world()
	var ledger: Dictionary = L.initial_energy(ds)
	ds[0].state.material_inventory_kg.H2 -= 2.0
	apply_chemistry(ds,34.062,32.042)
	var combined: Dictionary = report(ds,60.0)
	add_discharge(combined,2.0,0.0,0.0,false)
	add_chemistry(combined,34.062,32.042)
	var result: Dictionary = L.accumulate_energy(ledger,combined,60.0)
	check(not result.is_empty(),"fuel cell plus two chemical stations balances in one atomic step")
	if not result.is_empty():
		near(result.hydrogen_consumed_kg,2.0,"combined FC-only hydrogen")
		near(result.chemical_hydrogen_consumed_kg,12.096,"combined chemistry-only hydrogen")
		near(result.hydrogen_discharged_kg,14.096,"combined aggregate store discharge")
		near(result.water_released_kg,2.0*WATER+18.015,"combined total released liquid water")
		near(result.imported_inventory_kg.O2_gas_25c,2.0*OXYGEN,"only fuel cell imports air oxygen")

func test_chemical_boundaries_and_forgery() -> void:
	var ds: Array = chemical_world()
	var ledger: Dictionary = L.initial_energy(ds)
	if ledger.is_empty(): check(false,"chemical boundary fixtures initialize"); return
	for index in [1,2]:
		check(not L.remove_inventory_event(ledger,ds[index]).valid,"nonempty prepared feedstock cannot be deleted")
	for index in [3,4]:
		check(L.remove_inventory_event(ledger,ds[index]).valid,"empty product station can be removed")
	apply_chemistry(ds,20.0,40.0)
	var r: Dictionary = report(ds,10.0); add_chemistry(r,20.0,40.0)
	var result: Dictionary = L.accumulate_energy(ledger,r,10.0)
	if result.is_empty(): check(false,"chemical boundary result initializes"); return
	for index in [3,4]:
		check(not L.remove_inventory_event(result,ds[index]).valid,"nonempty product buffer cannot be deleted")
	var omitted: Dictionary = result.duplicate(true)
	for key in ["ammonia_produced_kg","methanol_produced_kg","nitrogen_withdrawn_kg","co2_withdrawn_kg","chemical_hydrogen_consumed_kg","chemical_water_released_kg","hydrogen_discharged_kg"]: omitted[key]=0.0
	omitted.water_released_kg=0.0; omitted.exported_inventory_kg.H2O_liquid_25c=0.0
	refresh_for_test(omitted)
	check(not L.validate_energy(omitted).is_empty(),"material stocks cannot hide erased reaction histories")
	for reference_id in ["N2_gas_25c","CO2_gas_25c","NH3_gas_25c","CH3OH_liquid_25c"]:
		var bad: Dictionary=result.duplicate(true)
		bad.imported_inventory_kg[reference_id]+=1.0; bad.exported_inventory_kg[reference_id]+=1.0
		refresh_for_test(bad)
		check(not L.validate_energy(bad).is_empty(),"balanced fake export forbidden "+reference_id)
	for field in ["ammonia_produced_kg_s","methanol_produced_kg_s","nitrogen_withdrawn_kg_s","co2_withdrawn_kg_s","chemical_hydrogen_consumed_kg_s","chemical_water_released_kg_s","chemical_electric_mw"]:
		var bad: Dictionary=r.duplicate(true);bad.material.erase(field)
		check(L.accumulate_energy(ledger,bad,10.0).is_empty(),"report requires chemical aggregate "+field)
		for invalid in [-1.0,NAN,INF,null,true,"0",[],{}]:
			bad=r.duplicate(true);bad.material[field]=invalid
			check(L.accumulate_energy(ledger,bad,10.0).is_empty(),"bad chemical aggregate rejected "+field)
	for species_name in ["N2","CO2","NH3","CH3OH"]:
		var bad: Array=ds.duplicate(true)
		for d in bad:
			if d.state.material_inventory_kg.has(species_name): d.state.material_inventory_kg[species_name]+=1.0
		check(not L.validate_energy(result,bad).is_empty(),"actual chemical stock tampering rejected "+species_name)
	var forged: Dictionary=r.duplicate(true)
	forged.next_states["13"].material_inventory_kg={"NH3_liquid":20.0}
	check(L.accumulate_energy(ledger,forged,10.0).is_empty(),"unmodeled ammonia liquid cannot replace gas reference")
	forged=r.duplicate(true);forged.next_states["14"].host_dry_mass_kg=100.0
	check(L.accumulate_energy(ledger,forged,10.0).is_empty(),"chemical plants cannot acquire implicit dry host")
	forged=r.duplicate(true);forged.devices["13"].kind="methanol_synthesis_station"
	check(L.accumulate_energy(ledger,forged,10.0).is_empty(),"chemical device kind cannot be relabeled")
	var paused: Dictionary=report(ds,0.0)
	check(L.accumulate_energy(result,paused,0.0)==result,"chemical pause is exact no-op")
	paused.material.chemical_electric_mw=1.0
	check(L.accumulate_energy(result,paused,0.0).is_empty(),"chemical AC cannot hide during pause")
	# Explicit inventory events create an import exactly once. Existing product
	# stock may be anchored/restored, but construction parameters remain empty.
	for kind in ["nitrogen_supply_boundary","co2_supply_boundary","ammonia_synthesis_station","methanol_synthesis_station"]:
		var added: Dictionary=device(100,kind,10.0)
		var imported: Dictionary=L.import_inventory_event(L.initial_energy(),added)
		check(imported.valid,"explicit valid inventory import "+kind)
		if imported.valid:
			near(imported.ledger.imported_inventory_kg[reference(kind)],10.0,"event records actual stock once")
			check(not L.import_inventory_event(imported.ledger,added).valid,"duplicate inventory event cannot reimport stock")
			check(L.validate_energy(imported.ledger,[added]).is_empty(),"event anchors exact world stock")
		check(not L.initial_energy([added]).is_empty(),"resumed stock can be anchored without inventing production")
		added.params.initial_inventory_kg=1.0
		if kind in ["ammonia_synthesis_station","methanol_synthesis_station"]:
			check(L.initial_energy([added]).is_empty(),"new-build product preload forbidden")
	for pair in [["nitrogen_supply_boundary",1000.001],["co2_supply_boundary",1000.001],["ammonia_synthesis_station",200.001],["methanol_synthesis_station",1000.001]]:
		check(L.initial_energy([device(100,pair[0],pair[1])]).is_empty(),"chemical fixed capacity enforced "+pair[0])

func test_v2_upgrade_preserves_every_anchor() -> void:
	var ds: Array=[device(1,"water_supply_boundary",500.0),device(2,"hydrogen_gas_store",10.0)]
	var old: Dictionary=V2.initial_energy(ds)
	var imported_device: Dictionary=device(3,"hydrogen_metal_hydride_store",0.0)
	var imported: Dictionary=V2.import_inventory_event(old,imported_device)
	check(imported.valid,"migration fixture imports immutable dry host")
	if not imported.valid:return
	old=imported.ledger
	old=V2.remove_inventory_event(old,imported_device).ledger
	ds[0].state.material_inventory_kg.H2O-=WATER
	ds[1].state.material_inventory_kg.H2+=1.0
	var charge: Dictionary=report(ds,1.0);add_charge(charge,1.0,3.0,0.0)
	old=V2.accumulate_energy(old,charge,1.0)
	check(not old.is_empty(),"migration fixture has nonzero v2 history")
	if old.is_empty():return
	var legacy: Dictionary=V2.initial_energy_v1()
	legacy.hydrogen_produced_kg=2.0;legacy.hydrogen_charged_kg=2.0;legacy.water_withdrawn_kg=2.0*WATER;legacy.oxygen_vented_kg=2.0*OXYGEN
	legacy.electrolyzer_electric_mwh=0.1;legacy.compression_electric_mwh=0.006;legacy.heat_rejected_mwhth=0.106-2.0*HHV
	old.legacy_v1_history=legacy.duplicate(true)
	check(V2.validate_energy(old,ds).is_empty(),"migration fixture passes frozen v2 validator")
	for invalid in [null,{},true,0,"devices"]:
		check(not L.upgrade_ledger_v2_to_v3(old,invalid).valid,"migration requires actual world array")
	var saved: Dictionary=old.duplicate(true)
	var world: Array=ds.duplicate(true)
	var upgrade: Dictionary=L.upgrade_ledger_v2_to_v3(old,ds)
	check(upgrade.valid,"validated v2 upgrades without resetting its period")
	check(old==saved and ds==world,"upgrade is pure")
	if not upgrade.valid:return
	check(upgrade.ledger.size()==43,"upgrade strictly adds seven fields")
	for key in old:
		if key not in ["ledger_version","ledger_profile"]:
			check(upgrade.ledger[key]==old[key],"upgrade preserves exact v2 field "+key)
	for key in ["chemical_electric_mwh","ammonia_produced_kg","methanol_produced_kg","nitrogen_withdrawn_kg","co2_withdrawn_kg","chemical_hydrogen_consumed_kg","chemical_water_released_kg"]:
		check(upgrade.ledger[key]==0.0,"upgrade adds zero chemical counter "+key)
	near(L.cumulative_electric_input_mwh(upgrade.ledger),V2.cumulative_electric_input_mwh(old),"upgrade retains both current and legacy energy history")
	check(L.validate_energy(upgrade.ledger,ds).is_empty(),"upgraded period closes against actual world")
	check(not V2.validate_energy(upgrade.ledger,ds).is_empty(),"frozen v2 does not accept widened schema")
	check(not L.upgrade_ledger_v2_to_v3(upgrade.ledger,ds).valid,"cannot re-upgrade v3")
	for key in old:
		var bad: Dictionary=old.duplicate(true);bad.erase(key)
		check(not L.upgrade_ledger_v2_to_v3(bad,ds).valid,"migration rejects missing legacy field "+key)
	var bad: Dictionary=old.duplicate(true);bad.heat_rejected_mwhth+=0.001
	check(not L.upgrade_ledger_v2_to_v3(bad,ds).valid,"migration cannot launder invalid legacy energy")
	var bad_world: Array=ds.duplicate(true);bad_world[1].state.material_inventory_kg.H2+=1.0
	check(not L.upgrade_ledger_v2_to_v3(old,bad_world).valid,"migration cannot reset inventory discrepancy")
	bad_world=ds.duplicate(true);bad_world.append(device(99,"nitrogen_supply_boundary",1000.0))
	check(not L.upgrade_ledger_v2_to_v3(old,bad_world).valid,"migration cannot silently import new preexisting source")
	var decoded: Variant=JSON.parse_string(JSON.stringify(old))
	var decoded_world: Variant=JSON.parse_string(JSON.stringify(ds))
	check(L.upgrade_ledger_v2_to_v3(decoded,decoded_world).valid,"JSON-decoded v2 IDs migrate canonically")
	var addition: Dictionary=L.import_inventory_event(upgrade.ledger,device(99,"nitrogen_supply_boundary",1000.0))
	check(addition.valid,"real post-upgrade source construction imports stock")
	if addition.valid:
		near(addition.ledger.imported_inventory_kg.N2_gas_25c,1000.0,"post-upgrade source imports exactly once")
		near(addition.ledger.opening_inventory_kg.N2_gas_25c,0.0,"post-upgrade construction never rewrites original anchor")

func test_chemical_long_history_and_roundtrip() -> void:
	var ds: Array=chemical_world()
	var ledger: Dictionary=L.initial_energy(ds)
	if ledger.is_empty():check(false,"long chemistry history initializes");return
	for i in 1000:
		var ammonia: float=0.001+float(i%7)*0.0001
		var methanol: float=0.002+float(i%5)*0.0001
		apply_chemistry(ds,ammonia,methanol)
		var r: Dictionary=report(ds,13.0)
		add_chemistry(r,ammonia,methanol)
		ledger=L.accumulate_energy(ledger,r,13.0)
		if ledger.is_empty():check(false,"long chemical step "+str(i));return
		if i%50==0:
			ds=JSON.parse_string(JSON.stringify(ds))
			ledger=JSON.parse_string(JSON.stringify(ledger))
	check(L.validate_energy(ledger,ds).is_empty(),"1000 chemical steps and repeated JSON reloads retain four-element/energy closure")
	var forged: Dictionary=ledger.duplicate(true)
	forged.current_inventory_kg.NH3_gas_25c+=1.0;forged.current_inventory_by_device["13"].mass_kg+=1.0
	refresh_for_test(forged)
	check(not L.validate_energy(forged).is_empty(),"coherent one kg product creation rejected after long history")
	# Huge valid throughput history from the inherited gas-cycle fixture already
	# tests the unchanged ULP budget. Chemical AC is included in that same budget.
	var huge: Dictionary=L.initial_energy([device(1,"water_supply_boundary",1.0e9)])
	var q: float=1.0e10
	huge.water_withdrawn_kg=q*WATER;huge.hydrogen_produced_kg=q;huge.hydrogen_charged_kg=q
	huge.hydrogen_consumed_kg=q;huge.hydrogen_discharged_kg=q;huge.water_released_kg=q*WATER
	huge.oxygen_vented_kg=q*OXYGEN;huge.oxygen_from_air_kg=q*OXYGEN
	huge.electrolyzer_electric_mwh=q*0.05;huge.compression_electric_mwh=q*0.003
	huge.fuel_cell_output_mwh=q*LHV*0.5;huge.heat_rejected_mwhth=q*0.053-huge.fuel_cell_output_mwh
	huge.imported_inventory_kg.H2O_liquid_25c=q*WATER;huge.exported_inventory_kg.H2O_liquid_25c=q*WATER
	huge.imported_inventory_kg.O2_gas_25c=q*OXYGEN;huge.exported_inventory_kg.O2_gas_25c=q*OXYGEN
	refresh_for_test(huge)
	check(L.validate_energy(huge).is_empty(),"huge v3 cumulative energy remains cancellation-safe")
	huge.chemical_electric_mwh+=0.001
	check(not L.validate_energy(huge).is_empty(),"one kWh chemical AC forgery rejected at 530 million MWh history")


func test_chemical_phase_supply() -> void:
	for kind in ["hydrogen_liquid_store","hydrogen_metal_hydride_store"]:
		var ds: Array=chemical_world()
		ds[0]=device(10,kind,10.0)
		var ledger: Dictionary=L.initial_energy(ds)
		if ledger.is_empty():check(false,"phase-fed chemical fixture initializes "+kind);return
		var ammonia: float=1.0
		var methanol: float=2.0
		var h2: float=ammonia*6.048/34.062+methanol*6.048/32.042
		apply_chemistry(ds,ammonia,methanol)
		var r: Dictionary=report(ds,17.0)
		add_chemistry(r,ammonia,methanol)
		var phase: float=-0.00124 if kind=="hydrogen_liquid_store" else -0.004275
		var electricity: float=0.00015 if kind=="hydrogen_liquid_store" else (0.15+4.475/0.95)/1000.0
		var ambient: float=-phase if kind=="hydrogen_liquid_store" else 0.0
		r.material.phase_store_electric_mw=h2*electricity*3600.0/17.0
		r.material.environment_heat_in_mwth=h2*ambient*3600.0/17.0
		r.material.heat_rejected_mwth+=h2*(electricity+ambient+phase)*3600.0/17.0
		var result: Dictionary=L.accumulate_energy(ledger,r,17.0)
		check(not result.is_empty(),"phase supply plus chemical reactions share exact reference enthalpy "+kind)
		if result.is_empty():continue
		check(L.validate_energy(result,ds).is_empty(),"phase-fed chemistry matches exact world "+kind)
		near(result.hydrogen_consumed_kg,0.0,"phase-fed chemistry still not fuel-cell consumption")
		near(result.hydrogen_discharged_kg,h2,"phase-fed stores count all chemical H2 discharge")
		near(L.cumulative_electric_input_mwh(result),0.0008+0.002+h2*electricity,"chemical and phase AC count once")
		var forged: Dictionary=r.duplicate(true)
		forged.material.phase_store_electric_mw=0.0
		check(L.accumulate_energy(ledger,forged,17.0).is_empty(),"phase discharge electric cannot disappear into chemistry")
		forged=r.duplicate(true)
		forged.material.inventory_by_reference_kg.H2_gas_25c=forged.material.inventory_by_reference_kg[reference(kind)]
		forged.material.inventory_by_reference_kg[reference(kind)]=0.0
		check(L.accumulate_energy(ledger,forged,17.0).is_empty(),"chemical supply cannot relabel retained phase stock")
