extends SceneTree
const Source=preload("res://scripts/real_weather_source.gd")
const Model=preload("res://scripts/energy_model.gd")
const Climate=preload("res://scripts/climate_model.gd")
const Series=preload("res://scripts/series_import.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():
	var data:=Source.dataset()
	check(data.valid,"verified source available")
	if not data.valid:quit(1);return
	check(data.count==169 and data.duration_s==604800,"seven days plus real endpoint")
	check(Climate.validate(Source.climate_config()).is_empty(),"civil date location valid")
	var imports:=Source.imports()
	check(imports.size()==3 and Source.matches_imports(imports),"recognize exact built-in imports")
	for s in imports:check(Series.validate_series(s).is_empty(),"saved CSV provenance valid")
	check(Source.matches_imports(JSON.parse_string(JSON.stringify(imports))),"saved JSON roundtrip retains exact recognized source")
	var altered:=imports.duplicate(true);altered[0].samples[80].value+=0.1
	check(not Source.matches_imports(altered),"edited middle sample not overwritten by adapter")
	altered=imports.duplicate(true);altered[0].target_device="0"
	check(not Source.matches_imports(altered),"device-specific override not mistaken for builtin")
	check(not Source.matches_imports(imports+[imports[0]]),"additional sources not silently replaced")
	var winds:Dictionary={};var radiation:Dictionary={}
	for i in data.count:
		var w:=Source.sample(i*3600.0)
		var r:Dictionary=data.rows[i]
		check(w.valid,"hour valid")
		check(w.wind_speed_mps==r.wind_100m_ms and w.pv_wind_speed_mps==r.wind_10m_ms,"actual wind heights")
		check(w.irradiance_wm2==r.gti30_south_instant_wm2,"GTI instantaneous no mean/plane substitution")
		check(absf(w.air_density_kgm3-r.surface_pressure_hpa*100/(287.05*(r.temperature_2m_c+273.15)))<1e-12,"actual local pressure density")
		winds[w.wind_speed_mps]=true;radiation[w.irradiance_wm2]=true
		if i<168:check(Source.sample(i*3600.0+3599.0)==w,"hour holds no invented noise")
	check(winds.size()>100 and radiation.size()>50,"actual variable historical input")
	check(not Source.sample(-1).valid and not Source.sample(604801).valid,"no extrapolation or loop")
	check(Source.sample(604800).valid,"real final point allowed")
	data.rows[0].wind_100m_ms=999
	check(Source.sample(0).wind_speed_mps!=999,"returned data cannot mutate source cache")
	var started:=Time.get_ticks_usec()
	for i in 1000:Source.matches_imports(imports)
	print("MATCH_1000_US ",Time.get_ticks_usec()-started)
	started=Time.get_ticks_usec()
	for i in 1000:Source.sample(float(i))
	print("SAMPLE_1000_US ",Time.get_ticks_usec()-started)
	print("REAL_WEATHER checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
