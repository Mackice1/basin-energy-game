extends SceneTree
const Catalog = preload("res://scripts/device_catalog.gd")
const Model = preload("res://scripts/energy_model.gd")
const Validator = preload("res://scripts/save_validator.gd")
const Fuel = preload("res://scripts/fuel_supply.gd")
const Series = preload("res://scripts/series_import.gd")
const Solar = preload("res://scripts/solar_thermal.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func blank() -> Dictionary:
	var s := {"schema":9,"model_version":18,"rebuild":true,"devices":[],"links":[],"imports":[],"templates":{},"next_id":0,"elapsed_s":0.0,"physical_lines":true,"energy":{},"thermal_energy":{},"solar_energy":Solar.initial_energy(),"fuel_energy":Fuel.initial_energy(),"fuel_supply":Fuel.defaults(),"stations":[],"next_station_id":1000000,"dimension_profile":"metric_v1"}
	for kind in Validator.SOLAR_KINDS: s.templates[kind] = Catalog.defaults(kind)
	for key in Validator.CURRENT_ENERGY_KEYS: s.energy[key] = 0.0
	for key in Validator.THERMAL_ENERGY_KEYS: s.thermal_energy[key] = 0.0
	return s
func _initialize() -> void:
	check(Catalog.implemented_kinds().count("solar_thermal") == 1,"collector is implemented exactly once")
	check(Model.validate("solar_thermal",{}).is_empty(),"default physical params accepted")
	var p := Catalog.defaults("solar_thermal")
	check(p.absorber_area_m2 == 30.3 and p.optical_efficiency == .785,"absorber area basis and official coefficient")
	for key in p:
		for bad in [NAN,INF,"1",null,true]:
			check(not Model.validate("solar_thermal",{key:bad}).is_empty(),"reject nonnumeric/nonfinite "+key)
	for bad in [{"absorber_area_m2":0},{"absorber_area_m2":3030.1},{"optical_efficiency":1.01},{"heat_loss_w_m2k":-1},{"heat_loss_quadratic_w_m2k2":-1},{"auxiliary_electric_ratio":0},{"supply_temp_c":91},{"return_temp_c":59},{"dni_wm2":800},{"rated_mw":1}]:
		check(not Model.validate("solar_thermal",bad).is_empty(),"reject invalid/unsupported "+str(bad))
	check(Catalog.port("solar_thermal","ac_in").carrier == "electricity_ac","pump AC port")
	check(Catalog.port("solar_thermal","heat_out").grade_id == Catalog.PRIMARY_GRADE,"90/60 hot water")
	check(Catalog.port("solar_thermal","out").is_empty(),"no invented electricity generator")
	check(Catalog.validate_state("solar_thermal",p,{"energy_mwhth":1}).size()>0,"collector cannot hide heat inventory")
	for header in ["GHI", "DNI_W_m2", "DHI", "水平辐照", "直接法向辐照", "global_horizontal", "direct_normal"]:
		var parsed := Series.parse("time,"+header+"\n0,800\n60,700", {"time_column":"time","value_column":header,"time_unit":"s","value_unit":"W/m2","field":"irradiance_wm2","target_device":""})
		check(not parsed.ok,"reject mislabeled non-POA source "+header)
	var poa := Series.parse("time,POA\n0,800\n60,700", {"time_column":"time","value_column":"POA","time_unit":"s","value_unit":"W/m2","field":"irradiance_wm2","target_device":""})
	check(poa.ok,"global POA CSV accepted")
	var s := blank()
	check(Validator.validate(s).is_empty(),"schema9 blank accepted: "+Validator.validate(s))
	var original := var_to_bytes(s)
	Validator.validate(s)
	check(var_to_bytes(s)==original,"validator read only")
	for key in s.solar_energy:
		var bad := s.duplicate(true); bad.solar_energy[key] = -1
		check(not Validator.validate(bad).is_empty(),"negative solar history "+key)
	var bad := s.duplicate(true); bad.solar_energy.useful_mwhth = 1
	check(not Validator.validate(bad).is_empty(),"cannot invent historical heat")
	bad = s.duplicate(true); bad.solar_energy.auxiliary_mwh = 1
	check(not Validator.validate(bad).is_empty(),"cannot invent historical pump consumption")
	bad = s.duplicate(true); bad.erase("solar_energy")
	check(not Validator.validate(bad).is_empty(),"schema9 requires ledger")
	# 1 MWh incident = .215 rejected + .1 thermal loss + .685 available.
	s.solar_energy={"incident_mwh":1.0,"optical_rejection_mwh":.215,"thermal_loss_mwh":.1,"available_mwhth":.685,"useful_mwhth":.5,"curtailed_mwhth":.185,"auxiliary_mwh":.01}
	s.energy.generated=.01; s.thermal_energy.served=.49; s.thermal_energy.demand=.49; s.thermal_energy.exchanger_loss=.01
	check(Validator.validate(s).is_empty(),"independent historical solar/electric/heat balances accepted: "+Validator.validate(s))
	bad=s.duplicate(true); bad.energy.generated=0
	check(not Validator.validate(bad).is_empty(),"solar auxiliary participates electric history")
	bad=s.duplicate(true); bad.thermal_energy.served=.48; bad.thermal_energy.demand=.48
	check(not Validator.validate(bad).is_empty(),"solar output participates heat history")
	bad=blank(); bad.dimension_profile="legacy_illustrative"; bad.devices=[{"id":0,"kind":"solar_thermal","params":p,"state":{},"model_profile":"thermal_stage1_v1","x":0,"z":0}];bad.next_id=1
	check(Validator.validate(bad).contains("metric_v1"),"legacy illustrative cannot host real-meter collector")
	var old := blank(); old.schema=8; old.model_version=17; old.templates.erase("solar_thermal"); old.erase("solar_energy")
	check(Validator.validate(old).is_empty(),"V17 remains readable: "+Validator.validate(old))
	old.templates.solar_thermal=p
	check(not Validator.validate(old).is_empty(),"solar does not masquerade as V17")
	print("SOLAR_CATALOG_SAVE_TESTS: ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
