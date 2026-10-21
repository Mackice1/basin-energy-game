extends SceneTree
## Focused import/UI/save regressions for explicit global cloud and rain data.
const Parser = preload("res://scripts/series_import.gd")
const ImportDialog = preload("res://scripts/import_dialog.gd")
const Validator = preload("res://scripts/save_validator.gd")
const Model = preload("res://scripts/energy_model.gd")

var checks := 0
var failures: Array[String] = []
var committed: Array = []

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func mapping(field: String, unit: String, target := "") -> Dictionary:
	return {"field": field, "value_unit": unit, "target_device": target,
		"time_column": "time", "value_column": "value", "time_unit": "s"}

func reject(csv: String, field_mapping: Dictionary, label: String, config: Dictionary = {}) -> void:
	var result: Dictionary = Parser.parse(csv, field_mapping, config)
	check(not result.ok and result.series.is_empty() and not result.errors.is_empty(), label)

func fixture(schema: int) -> Dictionary:
	var legacy := schema == 3
	var templates := {}
	for kind in (["wind", "pv", "station"] if legacy else ["wind", "pv", "station", "load", "battery"]):
		templates[kind] = Model.defaults(kind)
	var energy := {"generated": 0.0, "delivered": 0.0, "curtailed": 0.0, "loss": 0.0}
	if not legacy:
		for key in ["served", "unserved", "charge", "discharge", "storage_loss"]:
			energy[key] = 0.0
	return {"schema": schema, "model_version": 11 if legacy else 12,
		"rebuild": true, "devices": [], "links": [], "imports": [],
		"templates": templates, "next_id": 0, "elapsed_s": 0.0,
		"energy": energy, "physical_lines": true}

func _run() -> void:
	var cloud_csv := "time,value\n5,0\n10,0.375\n20,1\n"
	var rain_csv := "time,value\n5,0\n10,2.5\n20,1000\n"
	var cloud: Dictionary = Parser.parse(cloud_csv, mapping("cloud_cover", "0..1"))
	var percent: Dictionary = Parser.parse("time,value\n5,0\n10,37.5\n20,100\n", mapping("cloud_cover", "%"))
	var rain: Dictionary = Parser.parse(rain_csv, mapping("precipitation_mm_h", "mm/h"))
	check(cloud.ok and percent.ok and rain.ok, "Explicit cloud fraction, percentage, and rain imports accepted")
	if not cloud.ok or not percent.ok or not rain.ok:
		_finish()
		return
	check(cloud.series.unit == "0..1" and cloud.series.samples[1].value == 0.375, "Cloud fraction uses canonical 0..1 values")
	check(percent.series.unit == "0..1" and percent.series.samples == cloud.series.samples, "Percentage normalizes to the identical canonical samples")
	check(percent.series.mapping.value_unit == "%", "Percentage source unit preserved for exact reparse")
	check(rain.series.unit == "mm/h" and rain.series.samples[1].value == 2.5, "Rain remains in millimeters per hour")
	check(rain.series.samples[0].value == 0.0 and cloud.series.samples[0].value == 0.0, "Explicit clear/dry zeros are valid measurements")
	for entry in [cloud, percent, rain]:
		var series: Dictionary = entry.series
		check(series.schema_version == 1 and series.kind == "weather" and series.target_device == "", "%s retains compatible global-weather schema" % series.field)
		check(Parser.validate_series(series).is_empty(), "%s validates against original CSV" % series.field)
		var decoded: Variant = JSON.parse_string(JSON.stringify(series))
		check(decoded is Dictionary and Parser.validate_series(decoded).is_empty(), "%s survives strict JSON save/load" % series.field)
		check(Parser.sample(series, 4.999).status == "no_data", "%s does not extrapolate before range" % series.field)
		check(Parser.sample(series, 20.001).status == "no_data", "%s does not extrapolate after range" % series.field)
		check(Parser.sample(series, 9.999).value == 0.0, "%s preserves zero-order hold of explicit zero" % series.field)
		check(Parser.sample(series, 10.0).value == series.samples[1].value, "%s changes exactly at timestamp" % series.field)
		check(Parser.sample(series, 20.0).value == series.samples[-1].value, "%s includes final timestamp" % series.field)
	for alias in ["fraction", "ratio", "1"]:
		var result: Dictionary = Parser.parse(cloud_csv, mapping("cloud_cover", alias))
		check(result.ok and result.series.mapping.value_unit == "0..1", "Explicit dimensionless alias %s normalizes" % alias)
	for data in [
		["cloud_cover", "0..1", "-0.001"], ["cloud_cover", "0..1", "1.001"],
		["cloud_cover", "%", "-0.001"], ["cloud_cover", "%", "100.001"],
		["precipitation_mm_h", "mm/h", "-0.001"], ["precipitation_mm_h", "mm/h", "1000.001"]]:
		reject("time,value\n0,%s\n" % data[2], mapping(data[0], data[1]), "%s/%s enforces bounds for %s" % data)
	for field in Parser.GLOBAL_ONLY_FIELDS:
		var unit: String = Parser.FIELD_UNITS[field][0]
		for bad_unit in ["", "C", "W/m2", "mm", "mm/s"]:
			if bad_unit in Parser.FIELD_UNITS[field]:
				continue
			reject("time,value\n0,0\n", mapping(field, bad_unit), "%s rejects unit '%s' instead of guessing" % [field, bad_unit])
		for target in ["0", "wind_001", "station", " nonexistent "]:
			reject("time,value\n0,0\n", mapping(field, unit, target), "%s rejects device binding '%s'" % [field, target])
		for csv in ["time,value\n0,\n", "time,value\n,0\n", "time,value\n0,nan\n", "time,value\n0,inf\n", "time,value\n0,1e999\n", "time,value\n0,1e-999\n", "time,value\n0,50%\n", "time,value\n0,0\n0,1\n", "time,value\n10,0\n5,1\n", "time,value\n-1,0\n", "time,value\n315576001,0\n"]:
			reject(csv, mapping(field, unit), "%s retains strict missing/numeric/time validation: %s" % [field, csv])
		var timed := mapping(field, unit)
		timed.time_unit = "h"
		var hours: Dictionary = Parser.parse("time,value\n1,0\n2,1", timed)
		check(hours.ok and hours.series.start_s == 3600.0 and hours.series.end_s == 7200.0, "%s retains explicit elapsed offsets and hour conversion" % field)
		timed.time_unit = "iso_utc"
		var utc: Dictionary = Parser.parse("time,value\n2026-10-15T01:00:00Z,0\n2026-10-15T01:00:01Z,1", timed)
		check(utc.ok and utc.series.end_s == 1.0 and utc.series.time_origin_utc == "2026-10-15T01:00:00Z", "%s retains ISO UTC origin semantics" % field)
		check(Parser.validate_series(utc.series).is_empty(), "%s ISO source metadata remains valid" % field)
		for invalid_origin in ["", "2026-10-15T01:00:00", "2026-10-15T01:00:00+08:00", "2026-02-30T01:00:00Z", 0, null]:
			var invalid_utc: Dictionary = utc.series.duplicate(true)
			invalid_utc.time_origin_utc = invalid_origin
			check(not Parser.validate_series(invalid_utc).is_empty(), "%s rejects invalid saved ISO origin %s" % [field, str(invalid_origin)])
		var original: Dictionary = Parser.parse("time,value\n5,0\n10,0.1\n20,0.2", mapping(field, unit)).series
		for invalid_target in [0, false, null]:
			var invalid_binding: Dictionary = original.duplicate(true)
			invalid_binding.target_device = invalid_target
			check(not Parser.validate_series(invalid_binding).is_empty(), "%s rejects non-string saved binding without runtime errors" % field)
		for invalid_mode in ["", "seconds", "iso_local", 0, null]:
			var invalid_time: Dictionary = original.duplicate(true)
			invalid_time.time_mode = invalid_mode
			check(not Parser.validate_series(invalid_time).is_empty(), "%s rejects invalid saved time mode %s" % [field, str(invalid_mode)])
		var tampered: Dictionary = original.duplicate(true)
		tampered.time_origin_utc = "2026-10-15T01:00:00Z"
		check(not Parser.validate_series(tampered).is_empty(), "%s elapsed-time series cannot claim an unrelated UTC origin" % field)
		tampered = original.duplicate(true)
		tampered.target_device = "0"
		tampered.mapping.target_device = "0"
		check(not Parser.validate_series(tampered).is_empty(), "%s saved device binding rejected even if mapping agrees" % field)
		tampered = original.duplicate(true)
		tampered.bounds.max = float(Parser.BOUNDS[field][1]) + 1.0
		check(not Parser.validate_series(tampered).is_empty(), "%s saved bounds cannot expand domain" % field)
		tampered = original.duplicate(true)
		tampered.samples[1].value = 0.5
		check(not Parser.validate_series(tampered).is_empty(), "%s saved sample cannot disagree with source" % field)
	reject("time,value\n0,20\n", mapping("cloud_cover", "%"), "Configured cloud bounds apply after percent conversion", {"max_value": 0.1})
	reject("time,value\n0,2\n", mapping("precipitation_mm_h", "mm/h"), "Configured rain bounds are still enforced", {"max_value": 1.0})
	for legacy_field in ["wind_ms", "irradiance_wm2", "temp_c"]:
		var old: Dictionary = Parser.parse("time,value\n0,0\n10,1", mapping(legacy_field, Parser.FIELD_UNITS[legacy_field][0], "wind_001"))
		check(old.ok and old.series.target_device == "wind_001", "%s keeps existing device binding behavior" % legacy_field)
		check(not old.series.has("cloud_cover") and not old.series.has("precipitation_mm_h"), "%s does not invent cloud/rain values" % legacy_field)
		check(Parser.validate_series(old.series).is_empty(), "%s keeps existing saved schema" % legacy_field)
	check(Validator.MAX_IMPORTS == Validator.MAX_DEVICES * 4 + 6, "Import count accommodates cloud, rain and explicit global DNI")
	for schema in [3, 4]:
		var state := fixture(schema)
		check(Validator.validate(state).is_empty(), "Schema %d without cloud/rain remains valid" % schema)
		state.imports = [cloud.series, rain.series]
		check(Validator.validate(state).is_empty(), "Schema %d accepts explicit global cloud/rain imports" % schema)
		check(Validator.validate(JSON.parse_string(JSON.stringify(state))).is_empty(), "Schema %d cloud/rain survives JSON roundtrip" % schema)
		state.imports.append(cloud.series.duplicate(true))
		check(not Validator.validate(state).is_empty(), "Schema %d still rejects duplicate global field imports" % schema)
		state = fixture(schema)
		var bound: Dictionary = rain.series.duplicate(true)
		bound.target_device = "0"
		bound.mapping.target_device = "0"
		state.imports = [bound]
		check(not Validator.validate(state).is_empty(), "Schema %d rejects device-bound global-only weather" % schema)
	_test_dialog(cloud_csv, rain_csv)
	_finish()

func _test_dialog(cloud_csv: String, rain_csv: String) -> void:
	var dialog := ImportDialog.new()
	root.add_child(dialog)
	dialog.setup([{"id": "0", "name": "Test wind", "kind": "wind", "rated_kw": 10.0}])
	dialog.applied.connect(func(value: Dictionary): committed.append(value))
	for field in Parser.GLOBAL_ONLY_FIELDS:
		var index: int = ImportDialog.FIELDS.find(field)
		check(index >= 0, "%s is offered by import UI" % field)
		dialog._field.select(index)
		dialog._on_field_selected(index)
		check(dialog._target.item_count == 1 and dialog._target.disabled, "%s UI only offers disabled global target" % field)
		check(dialog._selected_device().get("id") == "", "%s UI clears stale device binding" % field)
		check(dialog._target.tooltip_text.contains("不可绑定设备") and dialog._range_hint.text.contains("仅全局"), "%s UI explains binding restriction" % field)
		check(dialog._value_unit.get_item_text(0) == Parser.FIELD_UNITS[field][0], "%s UI offers canonical unit" % field)
		var csv: String = cloud_csv if field == "cloud_cover" else rain_csv
		check(dialog.stage_import(csv, mapping(field, Parser.FIELD_UNITS[field][0])).ok, "%s previews without committing" % field)
		var before: int = committed.size()
		dialog.cancel_import()
		dialog.apply_import()
		check(committed.size() == before, "%s cancel blocks stale apply" % field)
		dialog.stage_import(csv, mapping(field, Parser.FIELD_UNITS[field][0]))
		dialog.apply_import()
		dialog.apply_import()
		check(committed.size() == before + 1 and committed[-1].field == field and committed[-1].target_device == "", "%s explicit apply commits exactly once" % field)
		dialog.stage_import(csv, mapping(field, Parser.FIELD_UNITS[field][0]))
		var invalid: Dictionary = dialog.stage_import(csv, mapping(field, Parser.FIELD_UNITS[field][0], "0"))
		dialog.apply_import()
		check(not invalid.ok and dialog._apply.disabled and committed.size() == before + 1, "%s invalid binding invalidates old preview" % field)
	var wind_index: int = ImportDialog.FIELDS.find("wind_ms")
	dialog._field.select(wind_index)
	dialog._on_field_selected(wind_index)
	check(not dialog._target.disabled and dialog._target.item_count == 2, "Returning to legacy weather restores global and device choices")
	dialog._field.select(0)
	dialog._on_field_selected(0)
	check(not dialog._target.disabled and dialog._target.item_count == 1 and dialog._selected_device().get("id") == "0", "Returning to power restores mandatory generating-device target")
	dialog.setup([])
	var cloud_index: int = ImportDialog.FIELDS.find("cloud_cover")
	dialog._field.select(cloud_index)
	dialog._on_field_selected(cloud_index)
	check(dialog._target.item_count == 1 and dialog._selected_device().get("id") == "", "Explicit global weather remains importable without devices")
	check(dialog._value_unit.item_count == 2 and dialog._value_unit.get_item_text(1) == "%", "Cloud UI explicitly offers percentage conversion")
	dialog.queue_free()

func _finish() -> void:
	print("WEATHER_CSV_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
