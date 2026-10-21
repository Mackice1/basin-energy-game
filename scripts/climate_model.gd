extends RefCounted
## Deterministic teaching climate. No wall clock, randomness or external service.
## Geographic coordinates and civil time locate the Sun; they DO NOT infer weather.
## Solar geometry: NOAA's fractional-year Fourier approximation (not full SPA/Meeus):
## https://gml.noaa.gov/grad/solcalc/solareqns.PDF
## Geometric solar-center altitude, no refraction, terrain horizon or solar disk.
## Azimuth is clockwise from north: north=0, east=90, south=180, west=270.
## This is suitable for educational day/night motion, not precision ephemerides.
## Fixed UTC offsets are explicit; no automatic daylight-saving/time-zone lookup.
## Irradiance is a TEACHING EQUIVALENT POA input for the existing PV model, not
## measured GHI/DNI, array transposition or a complete radiative-transfer model.
## Wind, clouds and temperature below are deliberately synthetic scenarios.

const SCENARIOS: Array[String] = ["clear", "partly_cloudy", "overcast", "windy"]
const MIN_YEAR: int = 1901
const MAX_YEAR: int = 2099
const SECONDS_PER_DAY: float = 86400.0
const SOLAR_REFERENCE_URL: String = "https://gml.noaa.gov/grad/solcalc/solareqns.PDF"
const IRRADIANCE_KIND: String = "teaching_equivalent_poa"
# Scenario calibration only: default clear noon remains about 850 W/m2.
const POA_SCALE_WM2: float = 956.0
# 2026-06-21T04:00:00Z. Absolute anchor preserves identical weather for the
# same instant described by different start dates or fixed UTC offsets.
const SCENARIO_EPOCH_UTC: float = 1782014400.0

static func defaults() -> Dictionary:
	return {
		"latitude_deg": 35.0,
		"longitude_deg": 105.0,
		"start_local": "2026-06-21T12:00:00",
		"utc_offset_hours": 8.0,
		"scenario": "clear",
	}

static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

static func _leap_year(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)

static func _month_days(year: int, month: int) -> int:
	if month == 2:
		return 29 if _leap_year(year) else 28
	return 30 if month in [4, 6, 9, 11] else 31

static func _parse_local(value: Variant) -> Dictionary:
	# Do not let Time silently normalize impossible dates or accept suffixes.
	if not value is String or value.length() != 19:
		return {}
	for i in 19:
		if i in [4, 7]:
			if value[i] != "-":
				return {}
		elif i == 10:
			if value[i] != "T":
				return {}
		elif i in [13, 16]:
			if value[i] != ":":
				return {}
		elif value.unicode_at(i) < 48 or value.unicode_at(i) > 57:
			return {}
	var year: int = value.substr(0, 4).to_int()
	var month: int = value.substr(5, 2).to_int()
	var day: int = value.substr(8, 2).to_int()
	var hour: int = value.substr(11, 2).to_int()
	var minute: int = value.substr(14, 2).to_int()
	var second: int = value.substr(17, 2).to_int()
	if year < MIN_YEAR or year > MAX_YEAR or month < 1 or month > 12:
		return {}
	if day < 1 or day > _month_days(year, month) or hour > 23 or minute > 59 or second > 59:
		return {}
	return {"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": second}

## Full configuration is required: malformed/missing fields cannot silently
## become another geography, time or weather scenario. JSON numeric types work.
static func validate(config: Variant) -> String:
	if not config is Dictionary:
		return "气候配置必须是对象。"
	var required: Dictionary = defaults()
	for key in config:
		if not required.has(key):
			return "气候配置含未知字段：%s" % str(key)
	for key in required:
		if not config.has(key):
			return "气候配置缺少字段：%s" % key
	if not _number(config.latitude_deg) or absf(float(config.latitude_deg)) > 90.0:
		return "纬度 latitude_deg 必须是 -90 至 90 的有限数值（北纬为正）。"
	if not _number(config.longitude_deg) or absf(float(config.longitude_deg)) > 180.0:
		return "经度 longitude_deg 必须是 -180 至 180 的有限数值（东经为正）。"
	if not _number(config.utc_offset_hours) or float(config.utc_offset_hours) < -12.0 or float(config.utc_offset_hours) > 14.0:
		return "UTC 偏移 utc_offset_hours 必须是 -12 至 +14 小时的有限数值。"
	var offset_minutes: float = float(config.utc_offset_hours) * 60.0
	if absf(offset_minutes - roundf(offset_minutes)) > 1.0e-7:
		return "UTC 偏移必须精确到整分钟（例如 5.5、5.75 小时）。"
	if _parse_local(config.start_local).is_empty():
		return "起始本地时间 start_local 须为 1901–2099 年有效日期 YYYY-MM-DDTHH:MM:SS；不附时区，不接受闰秒。"
	if not config.scenario is String or not config.scenario in SCENARIOS:
		return "教学情景 scenario 仅支持 clear、partly_cloudy、overcast、windy。"
	return ""

static func _invalid(error: String) -> Dictionary:
	return {"valid": false, "error": error}

## A single sample drives generation and presentation together. Negative t_s
## supports deterministic rewind; resulting LOCAL date must remain 1901–2099.
## JSON round-trips preserve configuration and samples; no scene objects leak.
static func sample(config: Variant, t_s: float) -> Dictionary:
	var error: String = validate(config)
	if not error.is_empty():
		return _invalid(error)
	if not is_finite(t_s):
		return _invalid("模拟时间 t_s 必须是有限秒数。")
	var start_local_epoch: float = float(Time.get_unix_time_from_datetime_dict(_parse_local(config.start_local)))
	var local_epoch: float = start_local_epoch + t_s
	# Check bounds BEFORE converting a float to an integer (including huge t_s).
	var lower: float = float(Time.get_unix_time_from_datetime_dict({"year": MIN_YEAR, "month": 1, "day": 1}))
	var upper: float = float(Time.get_unix_time_from_datetime_dict({"year": MAX_YEAR + 1, "month": 1, "day": 1}))
	if not is_finite(local_epoch) or local_epoch < lower or local_epoch >= upper:
		return _invalid("模拟后的本地日期超出 1901–2099 年支持范围。")
	var offset_seconds: float = roundf(float(config.utc_offset_hours) * 60.0) * 60.0
	var utc_epoch: float = local_epoch - offset_seconds
	var solar: Dictionary = _solar_position(float(config.latitude_deg), float(config.longitude_deg), utc_epoch)
	var scenario: String = config.scenario
	# All phases use supplied simulation time after UTC conversion, never OS time.
	var phase_s: float = utc_epoch - SCENARIO_EPOCH_UTC
	var cloud: float = 0.08 + 0.04 * sin(TAU * fposmod(phase_s, 5400.0) / 5400.0)
	var wind_base: float = 8.0
	var temp_offset: float = 0.0
	match scenario:
		"partly_cloudy":
			cloud = 0.48 + 0.22 * sin(TAU * fposmod(phase_s, 3600.0) / 3600.0)
			wind_base = 7.0
			temp_offset = -1.0
		"overcast":
			cloud = 0.96 + 0.025 * sin(TAU * fposmod(phase_s, 7200.0) / 7200.0)
			wind_base = 5.0
			temp_offset = -3.0
		"windy":
			cloud = 0.22 + 0.12 * sin(TAU * fposmod(phase_s, 4200.0) / 4200.0)
			wind_base = 13.0
			temp_offset = -1.5
	var wind: float = maxf(0.0, wind_base + 1.1 * sin(TAU * fposmod(phase_s, 2100.0) / 2100.0) + 0.4 * sin(TAU * fposmod(phase_s, 370.0) / 370.0))
	var solar_factor: float = pow(maxf(0.0, sin(deg_to_rad(solar.altitude_deg))), 0.8)
	var irradiance: float = POA_SCALE_WM2 * solar_factor * (1.0 - 0.95 * cloud) if solar.is_day else 0.0
	# Generic teaching daily temperature curve, with a two-solar-hour lag.
	# It is not a climate/location/season forecast and has no weather API source.
	var temperature: float = 20.5 + 6.0 * cos(deg_to_rad(solar.hour_angle_deg - 30.0)) - 2.0 * cloud + temp_offset
	# Dry ideal-gas density at assumed standard sea-level pressure, not site pressure.
	var density: float = 101325.0 / (287.05 * (temperature + 273.15))
	return {
		"valid": true, "error": "",
		"wind_speed_mps": wind,
		"irradiance_wm2": irradiance,
		"air_temp_c": temperature,
		"air_density_kgm3": density,
		"cloud_cover": cloud,
		"precipitation_mm_h": 0.0,
		"solar_altitude_deg": solar.altitude_deg,
		"solar_azimuth_deg": solar.azimuth_deg,
		"solar_azimuth_defined": solar.azimuth_defined,
		"is_day": solar.is_day,
		"local_datetime": Time.get_datetime_string_from_unix_time(int(floor(local_epoch))),
		"utc_datetime": Time.get_datetime_string_from_unix_time(int(floor(utc_epoch))) + "Z",
		"utc_timestamp_s": utc_epoch,
		"time_s": t_s,
		"utc_offset_hours": float(config.utc_offset_hours),
		"scenario": scenario,
		"weather_state": scenario,
		"irradiance_kind": IRRADIANCE_KIND,
		"source": "教学情景 %s；太阳位置 NOAA 近似；非当地实测/预报；辐照为 POA 教学等效值；降雨假设为 0" % scenario,
		"solar_method": "NOAA fractional-year approximation; geometric center; no refraction",
		"solar_reference_url": SOLAR_REFERENCE_URL,
		"pressure_assumption_pa": 101325.0,
	}

static func _solar_position(latitude_deg: float, longitude_deg: float, utc_epoch: float) -> Dictionary:
	var utc: Dictionary = Time.get_datetime_dict_from_unix_time(int(floor(utc_epoch)))
	var day_of_year: int = int(utc.day)
	for month in range(1, int(utc.month)):
		day_of_year += _month_days(int(utc.year), month)
	var utc_seconds: float = fposmod(utc_epoch, SECONDS_PER_DAY)
	var days_in_year: float = 366.0 if _leap_year(int(utc.year)) else 365.0
	# Evaluate the NOAA fractional year in UTC so equivalent instants always
	# produce the same declination/equation of time regardless of civil offset.
	var gamma: float = TAU / days_in_year * (float(day_of_year - 1) + (utc_seconds / 3600.0 - 12.0) / 24.0)
	var equation_minutes: float = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma) - 0.014615 * cos(2.0 * gamma) - 0.040849 * sin(2.0 * gamma))
	var declination: float = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) - 0.006758 * cos(2.0 * gamma) + 0.000907 * sin(2.0 * gamma) - 0.002697 * cos(3.0 * gamma) + 0.00148 * sin(3.0 * gamma)
	var solar_minutes: float = fposmod(utc_seconds / 60.0 + equation_minutes + 4.0 * longitude_deg, 1440.0)
	var hour_angle_deg: float = solar_minutes / 4.0 - 180.0
	var hour_angle: float = deg_to_rad(hour_angle_deg)
	var latitude: float = deg_to_rad(latitude_deg)
	# Local east/north/up solar vector avoids tan(latitude) and divisions by
	# cos(latitude), so +/-90 degree poles and exact zenith remain finite.
	var east: float = -cos(declination) * sin(hour_angle)
	var north: float = cos(latitude) * sin(declination) - sin(latitude) * cos(declination) * cos(hour_angle)
	var up: float = sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hour_angle)
	var altitude: float = rad_to_deg(asin(clampf(up, -1.0, 1.0)))
	# At exact zenith/nadir azimuth is undefined; deterministic 0 is a display
	# convention and the boolean explicitly exposes that singularity.
	var azimuth_defined: bool = east * east + north * north > 1.0e-20
	var azimuth: float = fposmod(rad_to_deg(atan2(east, north)), 360.0) if azimuth_defined else 0.0
	return {"altitude_deg": altitude, "azimuth_deg": azimuth, "azimuth_defined": azimuth_defined, "hour_angle_deg": hour_angle_deg, "is_day": altitude > 0.0}

## Independent synthetic direct-normal irradiance, NOT a conversion from POA.
## Only new high-temperature callers opt in, preserving existing weather records.
## 950 W/m2 ceiling, altitude attenuation and cloud factor are teaching assumptions.
static func teaching_dni(weather: Dictionary) -> float:
	var altitude: float = float(weather.get("solar_altitude_deg", -90.0))
	if altitude <= 0.0 or weather.get("is_day", false) == false: return 0.0
	var cloud: float = clampf(float(weather.get("cloud_cover", 0.0)),0.0,1.0)
	return 950.0 * (0.35 + 0.65 * sqrt(maxf(0.0,sin(deg_to_rad(altitude))))) * (1.0 - 0.95 * cloud)
