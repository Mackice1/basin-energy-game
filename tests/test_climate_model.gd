extends SceneTree
## godot --headless --path . --script tests/test_climate_model.gd
## Pure model checks: no scene, network, randomness or host clock dependencies.
const Climate = preload("res://scripts/climate_model.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("CLIMATE_MODEL_FAIL: " + label)

func near(actual: float, expected: float, label: String, tolerance: float = 1.0e-8) -> void:
	check(is_finite(actual) and absf(actual - expected) <= tolerance, "%s (actual %.9f, expected %.9f)" % [label, actual, expected])

func config_with(patch: Dictionary) -> Dictionary:
	var config: Dictionary = Climate.defaults()
	config.merge(patch, true)
	return config

func invalid(config: Variant, label: String) -> void:
	check(not Climate.validate(config).is_empty(), label + " rejected by validate")
	var result: Dictionary = Climate.sample(config, 0.0)
	check(not result.valid and not result.error.is_empty() and not result.has("irradiance_wm2"), label + " returns error without plausible weather")

func _initialize() -> void:
	_test_validation()
	_test_defaults_and_semantics()
	_test_reference_sun()
	_test_calendar_and_utc()
	_test_polar_and_day_night()
	_test_scenarios_and_determinism()
	print("CLIMATE_MODEL_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_validation() -> void:
	check(Climate.validate(Climate.defaults()).is_empty(), "defaults valid")
	for bad in [null, [], "", true, 12, 1.0]:
		invalid(bad, "non-object config " + str(bad))
	invalid({}, "missing configuration")
	for field in Climate.defaults():
		var missing: Dictionary = Climate.defaults()
		missing.erase(field)
		invalid(missing, "missing " + field)
	invalid(config_with({"timezone": 8}), "unknown field")
	for field in ["latitude_deg", "longitude_deg", "utc_offset_hours"]:
		for bad in [null, "8", true, false, [], {}, INF, -INF, NAN]:
			invalid(config_with({field: bad}), "non-number " + field + " " + str(bad))
	for bad in [-90.0001, 90.0001]:
		invalid(config_with({"latitude_deg": bad}), "latitude bound")
	for bad in [-180.0001, 180.0001]:
		invalid(config_with({"longitude_deg": bad}), "longitude bound")
	for bad in [-12.01, 14.01, 5.555, 0.001]:
		invalid(config_with({"utc_offset_hours": bad}), "offset bound/minute precision")
	for good in [-12, 14, -9.5, 5.5, 5.75, 12.75, 1.0 / 60.0]:
		check(Climate.validate(config_with({"utc_offset_hours": good})).is_empty(), "valid fixed offset " + str(good))
	for bad in [null, true, 20260621, "", "2026-6-21T12:00:00", "2026-06-21 12:00:00", "2026-06-21T12:00", "2026-06-21T12:00:00Z", "2026-06-21T12:00:00+08:00", "2026-06-21T12:00:00.0", "2026-02-29T12:00:00", "2024-02-30T12:00:00", "2026-04-31T12:00:00", "1900-02-29T12:00:00", "2100-02-29T12:00:00", "1899-12-31T00:00:00", "2100-01-01T00:00:00", "2026-00-01T00:00:00", "2026-13-01T00:00:00", "2026-01-00T00:00:00", "2026-01-32T00:00:00", "2026-01-01T24:00:00", "2026-01-01T12:60:00", "2026-01-01T12:00:60", "2026-01-01T-1:00:00", "２０２６-06-21T12:00:00"]:
		invalid(config_with({"start_local": bad}), "invalid calendar " + str(bad))
	for good in ["1901-01-01T00:00:00", "2000-02-29T23:59:59", "2024-02-29T00:00:00", "2099-12-31T23:59:59"]:
		check(Climate.validate(config_with({"start_local": good})).is_empty(), "valid Gregorian date " + good)
	for bad in [null, true, 1, "rain", "CLEAR", "clear "]:
		invalid(config_with({"scenario": bad}), "unknown/non-string scenario")
	for bad_time in [INF, -INF, NAN, 1.0e100, -1.0e100]:
		check(not Climate.sample(Climate.defaults(), bad_time).valid, "unsafe simulation time rejected " + str(bad_time))
	check(not Climate.sample(config_with({"start_local": "1901-01-01T00:00:00"}), -0.001).valid, "sample before supported local dates rejected")
	check(not Climate.sample(config_with({"start_local": "2099-12-31T23:59:59"}), 1.0).valid, "sample beyond supported local dates rejected")
	check(Climate.sample(config_with({"start_local": "1901-01-01T00:00:00", "utc_offset_hours": 14}), 0.0).valid, "boundary local date permits preceding UTC date")
	check(Climate.sample(config_with({"start_local": "2099-12-31T23:59:59", "utc_offset_hours": -12}), 0.0).valid, "boundary local date permits following UTC date")

func _test_defaults_and_semantics() -> void:
	var sample: Dictionary = Climate.sample(Climate.defaults(), 0.0)
	check(sample.valid and sample.is_day, "default noon is valid daylight")
	near(sample.irradiance_wm2, 850.0, "default clear irradiance remains near prior baseline", 2.0)
	near(sample.wind_speed_mps, 8.0, "default wind remains prior baseline")
	check(sample.local_datetime == "2026-06-21T12:00:00", "default civil display")
	check(sample.utc_datetime == "2026-06-21T04:00:00Z", "default UTC conversion")
	check(sample.utc_timestamp_s == Climate.SCENARIO_EPOCH_UTC, "documented absolute phase anchor")
	check(sample.irradiance_kind == "teaching_equivalent_poa", "POA semantic marker")
	check(sample.source.contains("教学") and sample.source.contains("非当地实测/预报") and sample.source.contains("降雨假设为 0"), "synthetic source and zero-rain assumption disclosed")
	check(sample.solar_method.contains("NOAA") and sample.solar_method.contains("no refraction"), "solar approximation disclosed")
	near(sample.precipitation_mm_h, 0.0, "teaching no-rain scenario")
	near(sample.air_density_kgm3, 101325.0 / (287.05 * (sample.air_temp_c + 273.15)), "dry ideal-gas density and declared standard pressure")
	var overcast: Dictionary = Climate.sample(config_with({"scenario": "overcast"}), 0.0)
	check(overcast.is_day and overcast.irradiance_wm2 < 120.0 and overcast.irradiance_wm2 > 0.0, "dim overcast noon never misclassified as night")
	near(overcast.solar_altitude_deg, sample.solar_altitude_deg, "weather choice cannot move the Sun")
	near(overcast.solar_azimuth_deg, sample.solar_azimuth_deg, "weather choice cannot change azimuth")
	check(overcast.cloud_cover > 0.9 and overcast.weather_state == "overcast", "explicit scenario sets cloud state")
	var modified: Dictionary = Climate.defaults()
	modified.latitude_deg = 0
	check(Climate.defaults().latitude_deg == 35.0, "defaults returned independently")

func _test_reference_sun() -> void:
	# Independent published NREL SPA example (not a copy of this implementation).
	# https://midcdmz.nlr.gov/spa/spa_tester.c
	# https://docs.nlr.gov/docs/fy08osti/34302.pdf Appendix A.5, Table A5.1.
	# Published apparent altitude=90-50.111622; azimuth=194.340241.
	# Our short NOAA Fourier approximation omits SPA/refraction/topocentric
	# corrections. 0.5/1.0 degree tolerances test educational plausibility only;
	# they are NOT a general accuracy guarantee or SPA precision claim.
	var golden: Dictionary = config_with({"latitude_deg": 39.742476, "longitude_deg": -105.1786, "start_local": "2003-10-17T12:30:30", "utc_offset_hours": -7.0})
	var actual: Dictionary = Climate.sample(golden, 0.0)
	check(actual.valid, "NREL published reference input accepted")
	near(actual.solar_altitude_deg, 39.888378, "NREL SPA altitude reference within teaching tolerance", 0.5)
	near(actual.solar_azimuth_deg, 194.340241, "NREL SPA azimuth reference within teaching tolerance", 1.0)
	check(actual.utc_datetime == "2003-10-17T19:30:30Z", "NREL negative offset converted correctly")
	print("CLIMATE_REFERENCE: NREL sample altitude=", actual.solar_altitude_deg, " azimuth=", actual.solar_azimuth_deg)
	var equator: Dictionary = config_with({"latitude_deg": 0.0, "longitude_deg": 0.0, "start_local": "2026-03-20T12:00:00", "utc_offset_hours": 0.0})
	var noon: Dictionary = Climate.sample(equator, 0.0)
	check(noon.solar_altitude_deg > 87.0 and noon.is_day, "equinox equatorial noon nearly overhead")
	var morning: Dictionary = Climate.sample(equator, -3.0 * 3600.0)
	var afternoon: Dictionary = Climate.sample(equator, 3.0 * 3600.0)
	check(morning.solar_azimuth_deg > 80 and morning.solar_azimuth_deg < 100, "morning Sun east; azimuth convention")
	check(afternoon.solar_azimuth_deg > 260 and afternoon.solar_azimuth_deg < 280, "afternoon Sun west; azimuth convention")
	check(not Climate.sample(equator, 12.0 * 3600.0).is_day, "equatorial midnight below horizon")
	# Exercise the explicitly documented azimuth singularity at zenith. At the
	# north pole the altitude equals declination; longitude can set hour angle 0.
	var pole: Dictionary = Climate._solar_position(90.0, 0.0, Climate.SCENARIO_EPOCH_UTC)
	var meridian: Dictionary = Climate._solar_position(0.0, 0.0, Climate.SCENARIO_EPOCH_UTC)
	var zenith: Dictionary = Climate._solar_position(pole.altitude_deg, -meridian.hour_angle_deg, Climate.SCENARIO_EPOCH_UTC)
	near(zenith.altitude_deg, 90.0, "exact zenith remains finite", 1.0e-6)
	check(not zenith.azimuth_defined and zenith.azimuth_deg == 0.0, "undefined zenith azimuth has explicit marker and stable convention")

func _test_calendar_and_utc() -> void:
	for fixture in [
		["2026-06-21T23:59:59", 1.0, "2026-06-22T00:00:00"],
		["2026-12-31T23:59:59", 1.0, "2027-01-01T00:00:00"],
		["2024-02-28T23:59:59", 1.0, "2024-02-29T00:00:00"],
		["2024-02-29T23:59:59", 1.0, "2024-03-01T00:00:00"],
		["2000-02-28T23:59:59", 1.0, "2000-02-29T00:00:00"],
		["2026-02-28T23:59:59", 1.0, "2026-03-01T00:00:00"],
		["2026-01-01T00:00:00", -1.0, "2025-12-31T23:59:59"],
	]:
		check(Climate.sample(config_with({"start_local": fixture[0]}), fixture[1]).local_datetime == fixture[2], "calendar rollover " + fixture[0])
	var before_1970: Dictionary = Climate.sample(config_with({"start_local": "1969-12-31T23:59:59", "utc_offset_hours": 0}), 0.5)
	check(before_1970.local_datetime == "1969-12-31T23:59:59", "negative epoch floors displayed fractional seconds correctly")
	near(before_1970.utc_timestamp_s, -0.5, "negative fractional epoch retained")
	var east: Dictionary = Climate.sample(config_with({"start_local": "2026-01-01T00:00:00", "utc_offset_hours": 14}), 0.0)
	check(east.utc_datetime == "2025-12-31T10:00:00Z", "east zone crosses UTC year backward")
	var west: Dictionary = Climate.sample(config_with({"start_local": "2026-12-31T23:00:00", "utc_offset_hours": -12}), 0.0)
	check(west.utc_datetime == "2027-01-01T11:00:00Z", "west zone crosses UTC year forward")
	var base: Dictionary = Climate.sample(Climate.defaults(), 123.25)
	for equivalent in [
		{"start_local": "2026-06-21T04:00:00", "utc_offset_hours": 0},
		{"start_local": "2026-06-21T00:00:00", "utc_offset_hours": -4},
		{"start_local": "2026-06-20T23:00:00", "utc_offset_hours": -5},
		{"start_local": "2026-06-21T09:30:00", "utc_offset_hours": 5.5},
		{"start_local": "2026-06-21T09:45:00", "utc_offset_hours": 5.75},
	]:
		var other: Dictionary = Climate.sample(config_with(equivalent), 123.25)
		for field in ["utc_timestamp_s", "solar_altitude_deg", "solar_azimuth_deg", "wind_speed_mps", "irradiance_wm2", "air_temp_c", "air_density_kgm3", "cloud_cover"]:
			near(other[field], base[field], "same UTC produces same " + field)
	var one_second_later: Dictionary = Climate.sample(Climate.defaults(), 1.0)
	var shifted_start: Dictionary = Climate.sample(config_with({"start_local": "2026-06-21T12:00:01"}), 0.0)
	for field in ["solar_altitude_deg", "wind_speed_mps", "cloud_cover", "air_temp_c", "irradiance_wm2"]:
		near(one_second_later[field], shifted_start[field], "origin shift preserves absolute sample " + field)
	var fractional: Dictionary = Climate.sample(Climate.defaults(), 0.25)
	check(fractional.solar_altitude_deg != Climate.sample(Climate.defaults(), 0.0).solar_altitude_deg, "subsecond solar motion preserved despite whole-second datetime label")
	near(fractional.utc_timestamp_s, base.utc_timestamp_s - 123.0, "subsecond UTC retained")
	# Same absolute instant across a UTC year/leap-day boundary, not only noon.
	for fixture in [
		[{"start_local": "2024-03-01T00:15:00", "utc_offset_hours": 5.75}, {"start_local": "2024-02-29T18:30:00", "utc_offset_hours": 0}],
		[{"start_local": "2026-01-01T00:30:00", "utc_offset_hours": 14}, {"start_local": "2025-12-31T10:30:00", "utc_offset_hours": 0}],
	]:
		var a: Dictionary = Climate.sample(config_with(fixture[0]), 0.0)
		var b: Dictionary = Climate.sample(config_with(fixture[1]), 0.0)
		near(a.solar_altitude_deg, b.solar_altitude_deg, "different calendar dates at same UTC retain altitude")
		near(a.solar_azimuth_deg, b.solar_azimuth_deg, "different calendar dates at same UTC retain azimuth")
		near(a.wind_speed_mps, b.wind_speed_mps, "different calendar dates at same UTC retain weather")

func _test_polar_and_day_night() -> void:
	for latitude in [78.0, 90.0, -78.0, -90.0]:
		for month in [6, 12]:
			var polar: Dictionary = config_with({"latitude_deg": latitude, "longitude_deg": 0.0, "utc_offset_hours": 0.0, "start_local": "2026-%02d-21T00:00:00" % month})
			var expected_day: bool = (latitude > 0 and month == 6) or (latitude < 0 and month == 12)
			for hour in 24:
				var s: Dictionary = Climate.sample(polar, hour * 3600.0)
				check(s.valid and s.is_day == expected_day, "polar season all-day state lat=%s month=%s hour=%s" % [latitude, month, hour])
				check(is_finite(s.solar_altitude_deg) and is_finite(s.solar_azimuth_deg) and s.solar_azimuth_deg >= 0 and s.solar_azimuth_deg < 360, "polar azimuth finite and normalized")
				check(s.irradiance_wm2 > 0.0 if expected_day else s.irradiance_wm2 == 0.0, "polar irradiance follows geometric horizon")
	var east_edge: Dictionary = Climate.sample(config_with({"longitude_deg": 180}), 0.0)
	var west_edge: Dictionary = Climate.sample(config_with({"longitude_deg": -180}), 0.0)
	near(east_edge.solar_altitude_deg, west_edge.solar_altitude_deg, "date-line longitude endpoints same altitude")
	near(east_edge.solar_azimuth_deg, west_edge.solar_azimuth_deg, "date-line longitude endpoints same azimuth")
	for hour in 48:
		var s: Dictionary = Climate.sample(Climate.defaults(), hour * 3600.0)
		check(s.is_day == (s.solar_altitude_deg > 0.0), "all day/night classifications use altitude")
		if not s.is_day:
			near(s.irradiance_wm2, 0.0, "night irradiance always zero")

func _test_scenarios_and_determinism() -> void:
	for scenario in Climate.SCENARIOS:
		var config: Dictionary = config_with({"scenario": scenario})
		var unchanged: String = JSON.stringify(config)
		var saved: Dictionary = Climate.sample(config, 1234.5)
		Climate.sample(config, 500000.0)
		Climate.sample(config, -8000.25)
		check(Climate.sample(config, 1234.5) == saved, "rewind/reorder deterministic " + scenario)
		check(JSON.stringify(config) == unchanged, "sample never mutates caller config " + scenario)
		var restored_config: Variant = JSON.parse_string(JSON.stringify(config))
		check(Climate.validate(restored_config).is_empty(), "JSON config restores valid " + scenario)
		check(Climate.sample(restored_config, 1234.5) == saved, "JSON config restores identical sample " + scenario)
		var restored_sample: Variant = JSON.parse_string(JSON.stringify(saved, "", true, true))
		check(restored_sample == saved, "JSON sample round trip " + scenario)
		for step in range(0, 96):
			var s: Dictionary = Climate.sample(config, float(step) * 900.0)
			check(s.valid and s.weather_state == scenario, "scenario provenance retained")
			check(s.wind_speed_mps >= 0 and s.wind_speed_mps < 30 and s.irradiance_wm2 >= 0 and s.irradiance_wm2 <= Climate.POA_SCALE_WM2, "bounded teaching wind/POA")
			check(s.cloud_cover >= 0 and s.cloud_cover <= 1 and s.precipitation_mm_h == 0, "cloud fraction and explicit no-rain scenario")
			check(is_finite(s.air_temp_c) and s.air_density_kgm3 > 0.5 and s.air_density_kgm3 < 2.0, "finite teaching air state")
	var clear: Dictionary = Climate.sample(Climate.defaults(), 0.0)
	var partly: Dictionary = Climate.sample(config_with({"scenario": "partly_cloudy"}), 0.0)
	var overcast: Dictionary = Climate.sample(config_with({"scenario": "overcast"}), 0.0)
	var windy: Dictionary = Climate.sample(config_with({"scenario": "windy"}), 0.0)
	check(clear.irradiance_wm2 > partly.irradiance_wm2 and partly.irradiance_wm2 > overcast.irradiance_wm2, "cloud scenarios attenuate same solar baseline")
	check(windy.wind_speed_mps > clear.wind_speed_mps, "windy scenario actually changes wind")
	var elsewhere: Dictionary = Climate.sample(config_with({"latitude_deg": -33.9, "longitude_deg": 151.2}), 0.0)
	near(elsewhere.wind_speed_mps, clear.wind_speed_mps, "coordinates do not fabricate location-specific wind")
	near(elsewhere.cloud_cover, clear.cloud_cover, "coordinates do not fabricate location-specific clouds")
	print("CLIMATE_DEFAULT: ", JSON.stringify(clear))
