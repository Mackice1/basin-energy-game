extends RefCounted
## Pure CSV import and sampling. No filesystem or simulation mutation.
## Use parse(), then explicitly commit the returned series in the scene/controller.

const SCHEMA_VERSION := 1
const MAX_BYTES := 8 * 1024 * 1024
const MAX_ROWS := 100000
const MAX_TIME_S := 315576000.0 # Ten Julian years; a simulation-domain bound.
# Sky conditions are explicit global observations. Neither field is synthesized
# from irradiance, and device-specific bindings would be ambiguous for the sky.
const GLOBAL_ONLY_FIELDS := ["cloud_cover", "precipitation_mm_h", "dni_wm2"]
const FIELD_UNITS := {
	"power": ["kW", "MW"],
	"wind_ms": ["m/s", "km/h"],
	"irradiance_wm2": ["W/m2", "kW/m2"],
	"dni_wm2": ["W/m2", "kW/m2"],
	"temp_c": ["C", "K"],
	"cloud_cover": ["0..1", "%"],
	"precipitation_mm_h": ["mm/h"],
}
const BOUNDS := {
	"power": [0.0, 1000000000.0],
	"wind_ms": [0.0, 100.0],
	"irradiance_wm2": [0.0, 2000.0],
	"dni_wm2": [0.0, 2000.0],
	"temp_c": [-90.0, 70.0],
	"cloud_cover": [0.0, 1.0],
	"precipitation_mm_h": [0.0, 1000.0],
}

static func parse(text: String, mapping: Dictionary, config: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	var field := str(mapping.get("field", ""))
	var time_unit := str(mapping.get("time_unit", ""))
	var value_unit := _unit_alias(str(mapping.get("value_unit", "")))
	var target := str(mapping.get("target_device", "")).strip_edges()
	if not FIELD_UNITS.has(field):
		errors.append("Choose a target field: power, wind_ms, irradiance_wm2, temp_c, cloud_cover, precipitation_mm_h, or dni_wm2.")
	elif not value_unit in FIELD_UNITS[field]:
		errors.append("Unit '%s' is not valid for %s. Choose %s." % [value_unit, field, str(FIELD_UNITS[field])])
	if not time_unit in ["s", "min", "h", "iso_utc"]:
		errors.append("Choose a time unit: s, min, h, or iso_utc.")
	if field == "power" and target.is_empty():
		errors.append("Direct power must be bound to one device ID.")
	if field in GLOBAL_ONLY_FIELDS and not target.is_empty():
		errors.append("%s is global weather only; clear the target-device binding." % field)
	var delimiter := str(mapping.get("delimiter", ","))
	if not delimiter in [",", ";", "\t"]:
		errors.append("Delimiter must be comma, semicolon, or tab.")
	if not errors.is_empty():
		return _failure(errors)
	var csv := inspect_csv(text, delimiter)
	if not csv.ok:
		return csv
	var headers: Array = csv.headers
	var time_index := _column_index(mapping.get("time_column"), headers)
	var value_index := _column_index(mapping.get("value_column"), headers)
	if time_index < 0:
		errors.append("Time column is missing or does not match a CSV header.")
	if value_index < 0:
		errors.append("Value column is missing or does not match a CSV header.")
	# Explicitly selecting irradiance_wm2 declares collector-plane POA. Reject
	# recognizably incompatible headers rather than silently relabel GHI/DNI.
	if field == "irradiance_wm2" and value_index >= 0:
		var header: String = str(headers[value_index]).to_lower()
		if header.contains("ghi") or header.contains("dni") or header.contains("dhi") or header.contains("水平") or header.contains("法向") or header.contains("horizontal") or header.contains("direct_normal"):
			errors.append("辐照导入仅支持设备平面 POA；GHI/DNI/DHI 必须先按固定集热面方向转换，不能直接映射。")
	if field == "dni_wm2" and value_index >= 0:
		var header: String = str(headers[value_index]).to_lower()
		if header.contains("poa") or header.contains("ghi") or header.contains("dhi") or header.contains("horizontal") or header.contains("水平") or header.contains("倾斜"):
			errors.append("槽式集热仅支持直接法向 DNI；POA/GHI/DHI 不能改名或直接映射为DNI。")
	if time_index >= 0 and time_index == value_index:
		errors.append("Time and value must be mapped to different columns.")
	if not errors.is_empty():
		return _failure(errors)
	var lower: float = BOUNDS[field][0]
	var upper: float = BOUNDS[field][1]
	for key in ["min_value", "max_value", "max_power_kw"]:
		if config.has(key) and (not _is_number(config[key]) or not is_finite(float(config[key]))):
			errors.append("Configuration %s must be a finite number." % key)
	if not errors.is_empty():
		return _failure(errors)
	if config.has("min_value"):
		lower = maxf(lower, float(config.min_value))
	if config.has("max_value"):
		upper = minf(upper, float(config.max_value))
	if field == "power" and config.has("max_power_kw"):
		upper = minf(upper, float(config.max_power_kw))
	if upper < lower:
		return _failure(["Configured minimum exceeds the allowed maximum."])
	var samples: Array = []
	var previous := -INF
	var utc_origin := ""
	var utc_origin_unix := 0.0
	var minimum := INF
	var maximum := -INF
	for record in csv.records:
		var cells: Array = record.cells
		var row_no: int = record.line
		if cells.size() != headers.size():
			errors.append("Row %d: expected %d columns; found %d." % [row_no, headers.size(), cells.size()])
			continue
		var time_text := str(cells[time_index]).strip_edges()
		var value_text := str(cells[value_index]).strip_edges()
		if time_text.is_empty() or value_text.is_empty():
			errors.append("Row %d: mapped time/value is blank. No values are filled automatically." % row_no)
			continue
		var time_result := _parse_time(time_text, time_unit)
		if not time_result.ok:
			errors.append("Row %d: %s" % [row_no, time_result.error])
			continue
		var time_s: float = time_result.value
		if time_unit == "iso_utc":
			if utc_origin.is_empty():
				utc_origin = time_text
				utc_origin_unix = time_s
			time_s -= utc_origin_unix
		if time_s < 0.0 or time_s > MAX_TIME_S:
			errors.append("Row %d: elapsed time must be within 0 to %.0f seconds." % [row_no, MAX_TIME_S])
			continue
		if time_s == previous:
			errors.append("Row %d: duplicate timestamp %.6f s. Keep exactly one sample per timestamp." % [row_no, time_s])
			continue
		if time_s < previous:
			errors.append("Row %d: timestamps are out of order. Sort strictly ascending before importing." % row_no)
			continue
		previous = time_s
		if not value_text.is_valid_float():
			errors.append("Row %d: '%s' is not a finite numeric value." % [row_no, value_text])
			continue
		var number := _finite_text_number(value_text)
		if not number.ok:
			errors.append("Row %d: value is outside the finite numeric range." % row_no)
			continue
		var raw_value: float = number.value
		var value := _convert(raw_value, value_unit)
		if not is_finite(raw_value) or not is_finite(value):
			errors.append("Row %d: value must be finite." % row_no)
			continue
		if value < lower or value > upper:
			errors.append("Row %d: converted value %.6f %s is outside allowed [%.6f, %.6f]." % [row_no, value, FIELD_UNITS[field][0], lower, upper])
			continue
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
		samples.append({"t": time_s, "value": value})
	if not errors.is_empty():
		return _failure(errors)
	if samples.is_empty():
		return _failure(["The CSV contains no data rows."])
	var canonical_mapping := {
		"time_column": str(headers[time_index]), "value_column": str(headers[value_index]),
		"time_unit": time_unit, "value_unit": value_unit, "field": field,
		"target_device": target, "delimiter": delimiter,
	}
	var series := {
		"schema_version": SCHEMA_VERSION,
		"kind": "power" if field == "power" else "weather",
		"field": field, "target_device": target,
		"unit": FIELD_UNITS[field][0],
		"time_unit": "s", "time_mode": time_unit, "time_origin_utc": utc_origin,
		"interpolation": "zero_order_hold", "outside_range": "no_data",
		"start_s": float(samples[0].t), "end_s": float(samples[-1].t),
		"count": samples.size(), "min_value": minimum, "max_value": maximum,
		"bounds": {"min": lower, "max": upper}, "samples": samples,
		"mapping": canonical_mapping,
		"source": {
			"name": str(config.get("source_name", "CSV import")),
			"sha256": text.sha256_text(), "byte_count": text.to_utf8_buffer().size(),
			"original_csv": text, "row_count": samples.size(),
		},
	}
	return {"ok": true, "errors": [], "series": series}

static func sample(series: Dictionary, t_s: float) -> Dictionary:
	if not is_finite(t_s):
		return {"status": "invalid", "reason": "Sampling time must be finite."}
	var samples: Variant = series.get("samples", [])
	if not samples is Array or samples.is_empty():
		return {"status": "invalid", "reason": "Series has no samples."}
	if not _valid_sample(samples[0]) or not _valid_sample(samples[-1]):
		return {"status": "invalid", "reason": "Invalid series endpoint."}
	var first: float = samples[0].t
	var last: float = samples[-1].t
	if first > last:
		return {"status": "invalid", "reason": "Series timestamps are not ordered."}
	if t_s < first or t_s > last:
		return {"status": "no_data", "reason": "Outside imported range; pause simulation.", "start_s": first, "end_s": last}
	var low := 0
	var high: int = samples.size() - 1
	while low <= high:
		var mid: int = (low + high) / 2
		if not _valid_sample(samples[mid]):
			return {"status": "invalid", "reason": "Invalid series sample."}
		if float(samples[mid].t) <= t_s:
			low = mid + 1
		else:
			high = mid - 1
	return {"status": "ok", "value": float(samples[high].value), "sample_time_s": float(samples[high].t), "index": high}

## Preview headers without assigning anything. Full rows remain private to the caller.
static func inspect_csv(text: String, delimiter: String = ",") -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return _failure(["CSV exceeds the 8 MiB import limit."])
	if text.strip_edges().is_empty():
		return _failure(["CSV is empty."])
	if not delimiter in [",", ";", "\t"]:
		return _failure(["Delimiter must be comma, semicolon, or tab."])
	var decoded := _decode_csv(text, delimiter)
	if not decoded.ok:
		return decoded
	var records: Array = decoded.records
	if records.is_empty():
		return _failure(["CSV is empty."])
	var headers: Array = records[0].cells
	var used := {}
	for i in headers.size():
		headers[i] = str(headers[i]).strip_edges()
		if str(headers[i]).is_empty():
			return _failure(["Header column %d is blank." % (i + 1)])
		if used.has(headers[i]):
			return _failure(["Duplicate CSV header '%s'. Rename it before mapping." % headers[i]])
		used[headers[i]] = true
	records.remove_at(0)
	if records.size() > MAX_ROWS:
		return _failure(["CSV exceeds the 100,000 data-row import limit."])
	return {"ok": true, "errors": [], "series": {}, "headers": headers, "records": records}

static func _decode_csv(original: String, delimiter: String) -> Dictionary:
	var text := original.trim_prefix("\ufeff").replace("\r\n", "\n").replace("\r", "\n")
	var records: Array = []
	var cells: Array = []
	var cell := ""
	var quoted := false
	var closed_quote := false
	var record_start := 1
	var line := 1
	var i := 0
	while i < text.length():
		var character := text.substr(i, 1)
		if quoted:
			if character == "\"":
				if i + 1 < text.length() and text.substr(i + 1, 1) == "\"":
					cell += "\""
					i += 1
				else:
					quoted = false
					closed_quote = true
			else:
				cell += character
				if character == "\n":
					line += 1
		elif character == delimiter:
			cells.append(cell)
			cell = ""
			closed_quote = false
		elif character == "\n":
			cells.append(cell)
			records.append({"line": record_start, "cells": cells})
			if records.size() > MAX_ROWS + 1:
				return _failure(["CSV exceeds the 100,000 data-row import limit."])
			cells = []
			cell = ""
			closed_quote = false
			line += 1
			record_start = line
		elif character == "\"":
			if not cell.is_empty() or closed_quote:
				return _failure(["Row %d: unexpected quote in an unquoted CSV field." % line])
			quoted = true
		elif closed_quote:
			if character != " " and character != "\t":
				return _failure(["Row %d: unexpected text after a quoted CSV field." % line])
		else:
			cell += character
		i += 1
	if quoted:
		return _failure(["Row %d: quoted CSV field is not closed." % record_start])
	if not cells.is_empty() or not cell.is_empty() or closed_quote:
		cells.append(cell)
		records.append({"line": record_start, "cells": cells})
	return {"ok": true, "records": records}

static func _column_index(selector: Variant, headers: Array) -> int:
	if selector is int:
		return selector if selector >= 0 and selector < headers.size() else -1
	if selector is float and is_finite(selector) and selector == floor(selector):
		return int(selector) if selector >= 0 and selector < headers.size() else -1
	if selector is String:
		return headers.find(selector)
	return -1

static func _parse_time(value: String, unit: String) -> Dictionary:
	if unit == "iso_utc":
		return _parse_iso_utc(value)
	if not value.is_valid_float():
		return {"ok": false, "error": "Time '%s' is not numeric." % value}
	var parsed_number := _finite_text_number(value)
	if not parsed_number.ok:
		return {"ok": false, "error": "Time is outside the finite numeric range."}
	var result: float = parsed_number.value
	if unit == "min":
		result *= 60.0
	elif unit == "h":
		result *= 3600.0
	if not is_finite(result):
		return {"ok": false, "error": "Time must be finite."}
	return {"ok": true, "value": result}

static func _parse_iso_utc(value: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})(\\.\\d{1,6})?(Z|\\+00:00)$")
	var matched := regex.search(value)
	if matched == null:
		return {"ok": false, "error": "ISO time must be UTC: YYYY-MM-DDTHH:MM:SS[.ffffff]Z or +00:00."}
	var year := matched.get_string(1).to_int()
	var month := matched.get_string(2).to_int()
	var day := matched.get_string(3).to_int()
	var hour := matched.get_string(4).to_int()
	var minute := matched.get_string(5).to_int()
	var second := matched.get_string(6).to_int()
	if year < 1 or month < 1 or month > 12 or hour > 23 or minute > 59 or second > 59:
		return {"ok": false, "error": "ISO timestamp contains an invalid calendar date/time (leap seconds are unsupported)."}
	var days := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0):
		days[1] = 29
	if day < 1 or day > days[month - 1]:
		return {"ok": false, "error": "ISO timestamp contains an invalid calendar day."}
	var unix := float(Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": second}))
	var fraction := matched.get_string(7)
	if not fraction.is_empty():
		unix += fraction.to_float()
	return {"ok": true, "value": unix}

static func _convert(value: float, unit: String) -> float:
	match unit:
		"MW", "kW/m2": return value * 1000.0
		"km/h": return value / 3.6
		"K": return value - 273.15
		"%": return value / 100.0
	return value

static func _unit_alias(unit: String) -> String:
	match unit:
		"W/m²", "W/m^2": return "W/m2"
		"kW/m²", "kW/m^2": return "kW/m2"
		"°C", "degC": return "C"
		"kmh": return "km/h"
		"fraction", "ratio", "1": return "0..1"
	return unit

static func _is_number(value: Variant) -> bool:
	return value is int or value is float

static func _valid_sample(value: Variant) -> bool:
	return value is Dictionary and _is_number(value.get("t")) and _is_number(value.get("value")) and is_finite(float(value.t)) and is_finite(float(value.value))

static func _failure(errors: Array) -> Dictionary:
	return {"ok": false, "errors": errors, "series": {}}

## Strict validation for untrusted saved JSON. Call once on load/assignment,
## not every frame. Reparse the embedded source so metadata and sample arrays
## cannot silently disagree. The controller must ALSO validate the target exists
## and use its current rated power as a cap before committing a saved import.
static func validate_series(series: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var field: Variant = series.get("field")
	if not field is String or not FIELD_UNITS.has(field):
		return ["Saved series has an unknown field."]
	if not _is_number(series.get("schema_version")) or float(series.schema_version) != SCHEMA_VERSION:
		errors.append("Saved series has an unsupported schema version.")
	if series.get("kind") != ("power" if field == "power" else "weather"):
		errors.append("Saved series kind does not match its field.")
	if not series.get("target_device") is String or (field == "power" and str(series.get("target_device", "")).strip_edges().is_empty()):
		errors.append("Saved series has an invalid target-device binding.")
	if field in GLOBAL_ONLY_FIELDS and series.get("target_device") is String and series.target_device != "":
		errors.append("Saved %s series must be global weather without a device binding." % field)
	if series.get("unit") != FIELD_UNITS[field][0] or series.get("time_unit") != "s":
		errors.append("Saved series must use canonical value units and seconds.")
	var time_mode: Variant = series.get("time_mode")
	var time_origin: Variant = series.get("time_origin_utc")
	if not time_mode is String or not time_mode in ["s", "min", "h", "iso_utc"]:
		errors.append("Saved series has an unsupported source time mode.")
	if not time_origin is String:
		errors.append("Saved series UTC origin must be a string.")
	elif time_mode is String and time_mode == "iso_utc":
		if not _parse_iso_utc(time_origin).ok:
			errors.append("Saved ISO series requires a valid explicit UTC origin.")
	elif time_origin != "":
		errors.append("Saved elapsed-time series must not contain a UTC origin.")
	if series.get("interpolation") != "zero_order_hold" or series.get("outside_range") != "no_data":
		errors.append("Saved series has unsupported sampling/extrapolation behavior.")
	var bounds: Variant = series.get("bounds")
	if not bounds is Dictionary or not _is_number(bounds.get("min")) or not _is_number(bounds.get("max")):
		errors.append("Saved series bounds are missing or invalid.")
	elif not is_finite(float(bounds.min)) or not is_finite(float(bounds.max)) or float(bounds.min) > float(bounds.max) or float(bounds.min) < float(BOUNDS[field][0]) or float(bounds.max) > float(BOUNDS[field][1]):
		errors.append("Saved series bounds exceed the model domain.")
	var samples: Variant = series.get("samples")
	if not samples is Array or samples.is_empty() or samples.size() > MAX_ROWS:
		errors.append("Saved series sample array is empty, invalid, or too large.")
	if not errors.is_empty():
		return errors
	var last := -INF
	var minimum := INF
	var maximum := -INF
	for i in samples.size():
		if not _valid_sample(samples[i]):
			errors.append("Saved sample %d must contain finite numeric t and value." % (i + 1))
			continue
		var time: float = samples[i].t
		var value: float = samples[i].value
		if time < 0.0 or time > MAX_TIME_S or time <= last:
			errors.append("Saved sample %d timestamp is outside bounds, duplicated, or out of order." % (i + 1))
		if value < float(bounds.min) or value > float(bounds.max):
			errors.append("Saved sample %d value is outside allowed bounds." % (i + 1))
		last = time
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	if not errors.is_empty():
		return errors
	for key in ["start_s", "end_s", "count", "min_value", "max_value"]:
		if not _is_number(series.get(key)) or not is_finite(float(series[key])):
			errors.append("Saved series %s must be finite numeric metadata." % key)
	if not errors.is_empty():
		return errors
	if float(series.start_s) != float(samples[0].t) or float(series.end_s) != float(samples[-1].t) or float(series.count) != samples.size():
		errors.append("Saved series range/count does not match its samples.")
	if float(series.min_value) != minimum or float(series.max_value) != maximum:
		errors.append("Saved series value range does not match its samples.")
	var source: Variant = series.get("source")
	var mapping: Variant = series.get("mapping")
	if not source is Dictionary or not source.get("original_csv") is String or not source.get("name") is String or not source.get("sha256") is String:
		errors.append("Saved series original CSV/source metadata is missing or invalid.")
	if not mapping is Dictionary:
		errors.append("Saved series column mapping is missing or invalid.")
	if not errors.is_empty():
		return errors
	if str(source.original_csv).to_utf8_buffer().size() > MAX_BYTES:
		return ["Saved series source exceeds the 8 MiB limit."]
	if str(source.original_csv).sha256_text() != source.sha256:
		errors.append("Saved series source hash does not match original CSV.")
	if not _is_number(source.get("byte_count")) or float(source.byte_count) != str(source.original_csv).to_utf8_buffer().size():
		errors.append("Saved source byte count is inconsistent.")
	if not _is_number(source.get("row_count")) or float(source.row_count) != samples.size():
		errors.append("Saved source row count is inconsistent.")
	if not errors.is_empty():
		return errors
	var reparsed := parse(source.original_csv, mapping, {"source_name": source.name, "min_value": bounds.min, "max_value": bounds.max})
	if not reparsed.ok:
		errors.append("Saved source no longer parses: " + "; ".join(PackedStringArray(reparsed.errors)))
		return errors
	var original: Dictionary = reparsed.series
	for key in ["field", "kind", "target_device", "unit", "time_mode", "time_origin_utc", "mapping", "count"]:
		if series.get(key) != original.get(key):
			errors.append("Saved series %s disagrees with its original CSV mapping." % key)
	if original.samples.size() != samples.size():
		errors.append("Saved sample count differs from original CSV.")
	else:
		for i in samples.size():
			# Godot JSON may round doubles on serialization. Relative epsilon is
			# restricted to 1e-12 after independent strict bounds/order validation.
			if not _serialized_float_equal(float(samples[i].t), float(original.samples[i].t)) or not _serialized_float_equal(float(samples[i].value), float(original.samples[i].value)):
				errors.append("Saved sample %d differs from original CSV data." % (i + 1))
				break
	return errors

static func _serialized_float_equal(a: float, b: float) -> bool:
	return absf(a - b) <= 1e-12 * maxf(1.0, maxf(absf(a), absf(b)))

static func _finite_text_number(value: String) -> Dictionary:
	# Reject impossible exponents before Godot's converter logs overflow warnings.
	# Avoid silently converting underflow such as 1e-999 into measured zero.
	var parts := value.to_lower().split("e")
	if parts.size() > 1:
		var exponent := str(parts[1]).to_int()
		if exponent < -308 or exponent > 308:
			return {"ok": false}
	var result := value.to_float()
	if not is_finite(result):
		return {"ok": false}
	if result == 0.0:
		var mantissa := str(parts[0]).replace(".", "").replace("+", "").replace("-", "")
		if not mantissa.replace("0", "").is_empty():
			return {"ok": false}
	return {"ok": true, "value": result}
