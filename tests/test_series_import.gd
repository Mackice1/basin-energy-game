extends SceneTree

const Parser = preload("res://scripts/series_import.gd")
const ImportDialog = preload("res://scripts/import_dialog.gd")
var checks := 0
var failures: Array[String] = []
var committed: Array = []

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _mapping(field := "power", unit := "kW", time_unit := "s") -> Dictionary:
	return {"time_column": "time", "value_column": "value", "field": field,
		"value_unit": unit, "time_unit": time_unit,
		"target_device": "wind_001" if field == "power" else ""}

func _reject(text: String, mapping: Dictionary, reason: String, config: Dictionary = {}) -> void:
	var result: Dictionary = Parser.parse(text, mapping, config)
	_expect(not result.ok and result.series.is_empty() and not result.errors.is_empty(), reason)

func _run() -> void:
	var mapping := _mapping()
	var csv := "time,value\n0,1\n10,4\n20,9\n"
	var result: Dictionary = Parser.parse(csv, mapping, {"source_name": "unit-test.csv", "max_power_kw": 10.0})
	_expect(result.ok, "Basic CSV accepted")
	if not result.ok:
		print(result)
		_finish()
		return
	var series: Dictionary = result.series
	_expect(series.count == 3 and series.field == "power" and series.target_device == "wind_001", "Field/device metadata")
	_expect(series.source.original_csv == csv and series.source.sha256 == csv.sha256_text(), "Original CSV and hash preserved")
	_expect(series.mapping.time_column == "time" and series.mapping.value_unit == "kW", "Mapping preserved")
	_expect(series.interpolation == "zero_order_hold" and series.outside_range == "no_data", "Sampling policy persisted")
	_expect(Parser.sample(series, 0).value == 1.0, "First timestamp included")
	_expect(Parser.sample(series, 9.99).value == 1.0, "Zero-order hold, no linear interpolation")
	_expect(Parser.sample(series, 10).value == 4.0, "Next sample starts exactly at its timestamp")
	_expect(Parser.sample(series, 20).value == 9.0, "Final timestamp included")
	_expect(Parser.sample(series, -0.01).status == "no_data", "Before first is no data")
	_expect(Parser.sample(series, 20.001).status == "no_data", "After last is no data, no extrapolation")
	_expect(not Parser.sample(series, 21).has("value"), "No data has no fake numeric value")
	_expect(Parser.sample(series, NAN).status == "invalid", "NaN sampling time rejected")
	_expect(Parser.sample({}, 1).status == "invalid", "Empty series rejected")
	_expect(Parser.sample({"samples": [{"t": "0", "value": 1}]}, 1).status == "invalid", "Non-numeric saved sample rejected")
	var decoded: Variant = JSON.parse_string(JSON.stringify(series))
	_expect(decoded is Dictionary and Parser.sample(decoded, 15).value == 4.0, "JSON save/load preserves sample values")
	_expect(decoded.source.original_csv == csv and decoded.mapping == series.mapping, "JSON preserves original source and mapping")
	mapping.target_device = "changed_later"
	_expect(series.target_device == "wind_001", "Mapping input is copied, not retained")
	mapping = _mapping()
	_reject("", mapping, "Empty CSV rejected")
	_reject("  \n", mapping, "Whitespace CSV rejected")
	_reject("time,value\n", mapping, "Header-only rejected")
	_reject("time,value\n0,\n10,2", mapping, "Missing numeric value rejected")
	_reject("time,value\n,2", mapping, "Missing timestamp rejected")
	_reject("time,value\n0,1\n\n10,2", mapping, "Blank interior row rejected")
	_reject("time,value\n0,1\n10,2,3", mapping, "Extra row column rejected")
	_reject("time,value\n0,1\n10", mapping, "Short row rejected")
	_reject("time,value\n0,1\n0,2", mapping, "Duplicate timestamp rejected")
	_reject("time,value\n10,1\n0,2", mapping, "Out-of-order timestamp rejected, never silently sorted")
	_reject("time,value\n-1,2", mapping, "Negative elapsed timestamp rejected")
	_reject("time,value\n315576001,2", mapping, "Excessive elapsed timestamp rejected")
	_reject("time,value\n0,nan", mapping, "NaN value rejected")
	_reject("time,value\n0,inf", mapping, "Infinite value rejected")
	_reject("time,value\n0,1e999", mapping, "Numeric overflow rejected")
	_reject("time,value\n0,1e-999", mapping, "Numeric underflow rejected, not silently set to zero")
	_reject("time,value\nwat,2", mapping, "Text time rejected")
	_reject("time,value\n0,-2", mapping, "Negative direct generation rejected")
	_reject("time,value\n0,11", mapping, "Device rating enforced", {"max_power_kw": 10.0})
	_reject("time,value\n0,2", mapping, "Invalid config rejected", {"max_value": INF})
	_reject("time,value\n0,2", mapping, "Contradictory bounds rejected", {"min_value": 3.0, "max_value": 1.0})
	var no_device := _mapping()
	no_device.target_device = ""
	_reject(csv, no_device, "Direct power requires binding")
	var bad_column := _mapping()
	bad_column.value_column = "absent"
	_reject(csv, bad_column, "Absent named value column rejected")
	bad_column.value_column = "time"
	_reject(csv, bad_column, "Identical mapped columns rejected")
	bad_column.value_column = 1.2
	_reject(csv, bad_column, "Fractional column index rejected")
	var indexed := _mapping()
	indexed.time_column = 0
	indexed.value_column = 1
	_expect(Parser.parse(csv, indexed).ok, "Index-based mapping accepted")
	_reject("time,time\n0,1", mapping, "Duplicate header rejected")
	_reject("time,\n0,1", mapping, "Blank header rejected")
	_reject('time,value\n0,"2', mapping, "Unclosed quote rejected")
	_reject('time,value\n0,2"', mapping, "Unexpected quote rejected")
	_reject('time,value\n0,"2"x', mapping, "Text after closing quote rejected")
	var quoted: Dictionary = Parser.parse('\ufeff"time","value","note"\r\n"0","2","a, b"\r\n"10","3","quoted ""text"""\r\n', mapping)
	_expect(quoted.ok and quoted.series.count == 2, "BOM, CRLF, quotes, escaped quote, ignored text supported")
	var multiline: Dictionary = Parser.parse('time,value,note\n0,2,"line1\nline2"\n10,3,ok', mapping)
	_expect(multiline.ok, "Quoted multiline unused fields supported")
	var semi := _mapping()
	semi.delimiter = ";"
	_expect(Parser.parse("time;value\n0;2\n10;3", semi).ok, "Semicolon delimiter supported")
	semi.delimiter = "\t"
	_expect(Parser.parse("time\tvalue\n0\t2", semi).ok, "Tab delimiter supported")
	semi.delimiter = "|"
	_reject(csv, semi, "Unsupported delimiter rejected")
	var mw: Dictionary = Parser.parse("time,value\n0,1.5\n1,2", _mapping("power", "MW", "min"))
	_expect(mw.ok and mw.series.samples[0].value == 1500.0 and mw.series.end_s == 60.0, "MW and minute conversion")
	var hours: Dictionary = Parser.parse("time,value\n2,36\n3,72", _mapping("wind_ms", "km/h", "h"))
	_expect(hours.ok and hours.series.start_s == 7200.0 and hours.series.samples[1].value == 20.0, "Hours retain elapsed offset and km/h converts to m/s")
	_expect(Parser.sample(hours.series, 0).status == "no_data", "Elapsed series is not silently shifted to zero")
	var irradiance: Dictionary = Parser.parse("time,value\n0,1.2", _mapping("irradiance_wm2", "kW/m²"))
	_expect(irradiance.ok and irradiance.series.samples[0].value == 1200.0, "Irradiance conversion and Unicode unit")
	var temperature: Dictionary = Parser.parse("time,value\n0,273.15\n10,293.15", _mapping("temp_c", "K"))
	_expect(temperature.ok and is_equal_approx(temperature.series.samples[1].value, 20.0), "Kelvin conversion")
	var single: Dictionary = Parser.parse("time,value\n5,1", mapping)
	_expect(single.ok and Parser.sample(single.series, 5).status == "ok" and Parser.sample(single.series, 5.1).status == "no_data", "Single sample valid only at exact time")
	_reject(csv, _mapping("power", "m/s"), "Unit/field mismatch rejected")
	_reject("time,value\n0,101", _mapping("wind_ms", "m/s"), "Wind model bound enforced")
	_reject("time,value\n0,2001", _mapping("irradiance_wm2", "W/m2"), "Irradiance model bound enforced")
	_reject("time,value\n0,-91", _mapping("temp_c", "C"), "Low temperature bound enforced")
	_reject("time,value\n0,71", _mapping("temp_c", "C"), "High temperature bound enforced")
	var iso_mapping := _mapping("wind_ms", "m/s", "iso_utc")
	var iso: Dictionary = Parser.parse("time,value\n2024-02-29T23:59:59Z,2\n2024-03-01T00:00:00+00:00,3", iso_mapping)
	_expect(iso.ok and iso.series.start_s == 0.0 and iso.series.end_s == 1.0, "ISO UTC and leap day normalize to origin")
	_expect(iso.series.time_origin_utc == "2024-02-29T23:59:59Z", "ISO origin preserved")
	var fractional: Dictionary = Parser.parse("time,value\n2026-01-01T00:00:00.250Z,2\n2026-01-01T00:00:01.750Z,3", iso_mapping)
	_expect(fractional.ok and is_equal_approx(fractional.series.end_s, 1.5), "Fractional ISO seconds supported")
	_reject("time,value\n2025-02-29T00:00:00Z,2", iso_mapping, "Invalid leap day rejected")
	_reject("time,value\n2026-04-31T00:00:00Z,2", iso_mapping, "Invalid month day rejected")
	_reject("time,value\n2026-01-01T25:00:00Z,2", iso_mapping, "Invalid ISO hour rejected")
	_reject("time,value\n2026-01-01T00:00:60Z,2", iso_mapping, "Unsupported leap second rejected")
	_reject("time,value\n2026-01-01T00:00:00,2", iso_mapping, "ISO timezone missing rejected")
	_reject("time,value\n2026-01-01T00:00:00+08:00,2", iso_mapping, "Non-UTC timezone rejected explicitly")
	_reject("time,value\n2026-01-01T00:00:00Z,2\n2026-01-01T00:00:00+00:00,3", iso_mapping, "Equivalent ISO duplicate timestamp rejected")
	var weather: Dictionary = Parser.parse("time,value\n0,2\n10,3", _mapping("wind_ms", "m/s"))
	_expect(weather.ok and weather.series.kind == "weather" and weather.series.target_device == "", "Global weather is valid")
	_expect(Parser.parse("time,value\n0,0", _mapping("irradiance_wm2", "W/m2")).ok, "Zero irradiance preserved, never treated as missing")
	_expect(Parser.validate_series(series).is_empty(), "Original series passes stored validation")
	_expect(Parser.validate_series(decoded).is_empty(), "JSON roundtrip passes stored validation")
	_expect(not Parser.validate_series({}).is_empty(), "Empty saved series rejected")
	var broken: Dictionary = series.duplicate(true)
	broken.samples[1].t = broken.samples[0].t
	_expect(not Parser.validate_series(broken).is_empty(), "Saved duplicate timestamp rejected")
	broken = series.duplicate(true)
	broken.samples[1].value = NAN
	_expect(not Parser.validate_series(broken).is_empty(), "Saved NaN rejected")
	broken = series.duplicate(true)
	broken.field = "unknown"
	_expect(not Parser.validate_series(broken).is_empty(), "Saved invalid field rejected")
	broken = series.duplicate(true)
	broken.unit = "MW"
	_expect(not Parser.validate_series(broken).is_empty(), "Saved wrong canonical unit rejected")
	broken = series.duplicate(true)
	broken.source.original_csv += " \n"
	_expect(not Parser.validate_series(broken).is_empty(), "Saved source hash mismatch rejected")
	broken = series.duplicate(true)
	broken.samples[1].value = 4.5
	_expect(not Parser.validate_series(broken).is_empty(), "Saved source/sample disagreement rejected")
	broken = series.duplicate(true)
	broken.target_device = "different_target"
	_expect(not Parser.validate_series(broken).is_empty(), "Saved binding/mapping disagreement rejected")
	broken = series.duplicate(true)
	broken.start_s = -1
	_expect(not Parser.validate_series(broken).is_empty(), "Saved range mismatch rejected")
	broken = series.duplicate(true)
	broken.outside_range = "hold"
	_expect(not Parser.validate_series(broken).is_empty(), "Saved extrapolation cannot bypass policy")
	broken = series.duplicate(true)
	broken.bounds.max = INF
	_expect(not Parser.validate_series(broken).is_empty(), "Saved nonfinite bound rejected")
	_reject("x".repeat(Parser.MAX_BYTES + 1), mapping, "Oversized input rejected")
	var dialog := ImportDialog.new()
	root.add_child(dialog)
	dialog.setup([{"id": "wind_001", "name": "Test wind", "kind": "wind", "rated_kw": 10.0}])
	dialog.applied.connect(func(value: Dictionary): committed.append(value))
	dialog.stage_import(csv, _mapping(), {"source_name": "cancel.csv"})
	_expect(committed.is_empty(), "Preview emits no mutation signal")
	dialog.cancel_import()
	dialog.apply_import()
	_expect(committed.is_empty(), "Cancel discards staged data and blocks stale apply")
	dialog.stage_import(csv, _mapping())
	dialog.apply_import()
	_expect(committed.size() == 1 and committed[0].count == 3, "Explicit apply emits complete staged series once")
	dialog.apply_import()
	_expect(committed.size() == 1, "Double apply cannot emit twice")
	dialog.stage_import(csv, _mapping())
	dialog._invalidate()
	dialog.apply_import()
	_expect(committed.size() == 1, "Mapping change invalidates preview")
	dialog.stage_import(csv, _mapping())
	dialog.stage_import("time,value\n0,", _mapping())
	dialog.apply_import()
	_expect(committed.size() == 1, "Failed preview cannot apply previous valid result")
	dialog.stage_import(csv, _mapping())
	dialog._load_file("res://does-not-exist.csv")
	dialog.apply_import()
	_expect(committed.size() == 1 and dialog._raw_text.is_empty(), "Failed file selection invalidates old source and staged apply")
	dialog.queue_free()
	_finish()

func _finish() -> void:
	print("CSV_IMPORT_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
