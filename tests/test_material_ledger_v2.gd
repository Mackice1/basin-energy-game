extends SceneTree
## Independent analytic chemistry/phase ledger tests; no dispatch/solver/UI.
const L = preload("res://scripts/material_ledger_v2.gd")
const WATER := 18.015 / 2.016
const OXYGEN := 15.999 / 2.016
const HHV := 285830.0 / 2.016 / 3600000.0
const LHV := 241826.0 / 2.016 / 3600000.0
const WATER_H := -285830.0 / 18.015 / 3600000.0
const MASS_RATES := ["water_withdrawn_kg_s", "hydrogen_produced_kg_s", "hydrogen_consumed_kg_s", "hydrogen_charged_kg_s", "hydrogen_discharged_kg_s", "oxygen_vented_kg_s", "oxygen_from_air_kg_s", "water_released_kg_s"]
const POWERS := ["electrolyzer_electric_mw", "compression_electric_mw", "fuel_cell_output_mw", "heat_rejected_mwth", "phase_store_electric_mw", "environment_heat_in_mwth"]
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("LEDGER_V2_FAIL: " + label)

func near(a: float, b: float, label: String, tolerance: float = 1.0e-9) -> void:
	check(is_finite(a) and absf(a - b) <= tolerance, label + " (%s != %s)" % [a, b])

func device(id: int, kind: String, mass: float = 0.0, host: float = 1000.0) -> Dictionary:
	var species: String = "H2O" if kind == "water_supply_boundary" else "H2"
	var state: Dictionary = {"material_inventory_kg":{species:mass}}
	var params: Dictionary = {"capacity_kg":1000.0 if kind == "hydrogen_liquid_store" else 1.0e9}
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
	return ""

func report(devices: Array, dt: float) -> Dictionary:
	var m: Dictionary = {"hydrogen_leaked_kg":0.0, "hydrogen_leak_lhv_mwh":0.0, "inventory_by_reference_kg":L.empty_inventory(), "dry_host_by_device_kg":{}}
	for key in MASS_RATES + POWERS: m[key] = 0.0
	var result: Dictionary = {"valid":true, "dt_s":dt, "material":m, "devices":{}, "next_states":{}}
	for d in devices:
		var id: String = str(d.id)
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
	print("MATERIAL_LEDGER_V2: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_initial_and_coefficients() -> void:
	var ds: Array = [device(1,"water_supply_boundary",100), device(2,"hydrogen_gas_store",10), device(3,"hydrogen_liquid_store",5), device(4,"hydrogen_metal_hydride_store",3)]
	var saved: Array = ds.duplicate(true)
	var ledger: Dictionary = L.initial_energy(ds)
	check(not ledger.is_empty(), "initial ledger opens actual inventory")
	check(ds == saved, "initialization pure")
	check(ledger.size() == 36, "exact versioned ledger shape")
	check(ledger.ledger_version == 2 and ledger.ledger_profile == "material_reference_ledger_v2", "version/profile explicit")
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
