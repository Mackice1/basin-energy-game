extends SceneTree
const Validator = preload("res://scripts/save_validator.gd")
const Model = preload("res://scripts/energy_model.gd")
const Series = preload("res://scripts/series_import.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label); push_error(label)

func fixture() -> Dictionary:
	return {"schema":3,"model_version":11,"rebuild":true,"devices":[
		{"id":0,"kind":"wind","x":-15.0,"z":0.0,"params":Model.defaults("wind")},
		{"id":1,"kind":"pv","x":7.0,"z":14.0,"params":Model.defaults("pv")},
		{"id":2,"kind":"station","x":24.0,"z":14.0,"params":Model.defaults("station")}],
		"links":[{"from":0,"to":2,"capacity_mw":6.0,"loss_fraction":0.02},{"from":1,"to":2,"capacity_mw":2.0,"loss_fraction":0.02},{"from":2,"to":-1,"capacity_mw":4.0,"loss_fraction":0.02}],
		"templates":{"wind":Model.defaults("wind"),"pv":Model.defaults("pv"),"station":Model.defaults("station")},
		"imports":[],"next_id":3,"elapsed_s":0.0,"energy":{"generated":1.0,"delivered":0.8,"curtailed":0.1,"loss":0.1},"physical_lines":true}

func power(target := "0") -> Dictionary:
	return Series.parse("time,power\n0,2000\n60,1000",{"field":"power","target_device":target,"time_column":"time","value_column":"power","time_unit":"s","value_unit":"kW"}).series

func invalid(state: Variant, label: String): check(Validator.validate(state) != "", label)

func _initialize():
	var good := fixture()
	check(Validator.validate(good) == "", "valid scene accepted")
	var encoded := JSON.stringify(good)
	check(Validator.validate(JSON.parse_string(encoded)) == "", "JSON numeric round trip accepted")
	check(JSON.stringify(good) == encoded, "validation does not mutate source state")
	for value in [null, [], "bad", 1]: invalid(value, "non-object rejected")
	for key in ["devices","links","imports","templates","elapsed_s","energy","next_id","physical_lines","model_version"]:
		var s := fixture(); s.erase(key); invalid(s, "required field %s" % key)
	for value in [-1, 0.5, "0", INF, NAN, 2147483648.0]:
		var s := fixture(); s.devices[0].id = value; invalid(s, "invalid ID %s" % value)
	for value in [0, 2, 2.5, "3", INF]:
		var s := fixture(); s.next_id = value; invalid(s, "invalid next ID %s" % value)
	for value in ["0", null, INF, NAN, 200.0]:
		var s := fixture(); s.devices[0].x = value; invalid(s, "invalid coordinate %s" % value)
	var s := fixture(); s.devices[1].id = 0; invalid(s, "duplicate ID rejected")
	s = fixture(); s.devices[0].kind = "coal"; invalid(s, "unsupported device kind")
	s = fixture(); s.devices[0].params.rated_mw = "5"; invalid(s, "mistyped parameter")
	s = fixture(); s.templates.wind.rotor_diameter_m = -1; invalid(s, "invalid template")
	s = fixture(); s.templates.coal = {}; invalid(s, "unknown template kind")
	s = fixture(); s.templates.wind = {}; check(Validator.validate(s) == "", "partial templates retain model defaults semantics")
	s = fixture(); s.devices[1].x = -15.0; s.devices[1].z = 0.0; invalid(s, "overlapping sites")
	s = fixture(); s.devices[0].params.rotor_diameter_m = 600.0; s.devices[0].params.hub_height_m = 400.0; invalid(s, "dynamic rotor radius detects overlap")
	s = fixture(); s.devices[0].params.rotor_diameter_m = 300.0; s.devices[0].params.hub_height_m = 200.0; s.devices[0].x = -80; invalid(s, "dynamic rotor radius detects boundary")
	for value in [0.5, "0", -2, INF]:
		s = fixture(); s.links[0].from = value; invalid(s, "invalid line endpoint")
	s = fixture(); s.links[0].to = -1; invalid(s, "generator-to-grid shortcut")
	s = fixture(); s.links[2].to = 1; invalid(s, "station-to-generator reversal")
	s = fixture(); s.links[1].from = 0; invalid(s, "duplicate outgoing connection")
	s = fixture(); s.links[0].to = 999; invalid(s, "missing endpoint")
	for value in [-1, 0, INF, NAN, "4"]:
		s = fixture(); s.links[0].capacity_mw = value; invalid(s, "invalid line capacity")
	for value in [-0.1, 1.0, INF, NAN, "0"]:
		s = fixture(); s.links[0].loss_fraction = value; invalid(s, "invalid line loss")
	s = fixture(); s.energy.generated = 2; invalid(s, "energy mismatch")
	s = fixture(); s.energy.loss = -0.1; invalid(s, "negative energy")
	s = fixture(); s.energy.extra = "bad"; invalid(s, "unknown energy integration field")
	s = fixture(); s.physical_lines = "false"; invalid(s, "mistyped boolean")
	s = fixture(); s.imports = [power()]; check(Validator.validate(s) == "", "canonical direct import accepted")
	check(Validator.validate(JSON.parse_string(JSON.stringify(s))) == "", "import and original CSV survive JSON round trip")
	s.devices[0].params.rated_mw = 1.0; check(Validator.validate(s) == "", "lowered rating preserves measured series for model clipping")
	s = fixture(); s.imports = [power("999")]; invalid(s, "orphan binding")
	s = fixture(); s.imports = [power("2")]; invalid(s, "station binding")
	s = fixture(); s.imports = [power("00")]; invalid(s, "noncanonical ID binding")
	s = fixture(); s.imports = [power(), power()]; invalid(s, "duplicate field binding")
	s = fixture(); s.imports = [{"samples":[{"t":0,"value":1}]}]; invalid(s, "missing series metadata")
	s = fixture(); s.imports = [power()]; s.imports[0].samples.insert(1,{"t":70,"value":1000}); invalid(s, "unordered sample")
	s = fixture(); s.imports = [power()]; s.imports[0].samples[0].value = -1; invalid(s, "out-of-bounds saved value")
	s = fixture(); s.imports = [power()]; s.imports[0].end_s = 70; invalid(s, "range disagreement")
	s = fixture(); s.imports = [power()]; s.imports[0].source.original_csv += "\n"; invalid(s, "source hash disagreement")
	s = fixture(); s.imports = [power()]; s.imports[0].field = "bogus"; invalid(s, "unsupported imported field")
	print("SAVE_VALIDATOR_TEST checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
