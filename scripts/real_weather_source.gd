extends RefCounted
## Historical hourly ERA5 reanalysis + provider-derived tilted radiation.
## No synthetic fallback, added noise, endpoint extension or loop.
const Series=preload("res://scripts/series_import.gd")
const DATA_PATH="res://data/weather/dunhuang_era5_20250601_7days.json"
const META_PATH="res://data/weather/dunhuang_era5_metadata.json"
const EXPECTED_SHA="8eeab2165cb9e7348f5c46aeff09e5f3a1f956cd91a401ba2c6efa4acdf1fe7e"
const LABEL="敦煌附近 ERA5 · 2025-06-01—07 · UTC+8 · 逐小时再分析/零阶保持，非站点实测"
static var _cache:Dictionary={}
static var _imports:Array=[]
static var _saved_imports:Array=[]

static func _load()->Dictionary:
	if not _cache.is_empty():return _cache
	if not FileAccess.file_exists(DATA_PATH):return {"valid":false,"error":"历史气象源缺失；没有合成天气替代。"}
	var text:=FileAccess.get_file_as_string(DATA_PATH)
	if text.sha256_text()!=EXPECTED_SHA:return {"valid":false,"error":"历史气象文件摘要不匹配，拒绝悄悄换源。"}
	var rows:Variant=JSON.parse_string(text)
	if not rows is Array or rows.size()!=169:return {"valid":false,"error":"历史气象格式/端点不完整。"}
	for i in rows.size():
		var r:Dictionary=rows[i]
		if r.get("time_s")!=i*3600:return {"valid":false,"error":"历史气象小时不连续，拒绝填值。"}
		for key in ["wind_10m_ms","wind_100m_ms","temperature_2m_c","surface_pressure_hpa","gti30_south_instant_wm2"]:
			var value:Variant=r.get(key)
			if not (value is float or value is int) or not is_finite(float(value)):return {"valid":false,"error":"历史气象缺测/非有限值。"}
		if r.surface_pressure_hpa<=0 or r.temperature_2m_c<=-273.15 or r.wind_10m_ms<0 or r.wind_100m_ms<0 or r.gti30_south_instant_wm2<0:return {"valid":false,"error":"历史气象含非法值。"}
	_cache={"valid":true,"rows":rows,"count":169,"duration_s":604800.0,"sha256":EXPECTED_SHA,"start_local":"2025-06-01T00:00:00+08:00","end_local":"2025-06-08T00:00:00+08:00","timezone":"Asia/Shanghai","latitude":40.25,"longitude":94.75}
	return _cache

static func dataset()->Dictionary:return _load().duplicate(true)
static func duration_s()->float:return float(_load().get("duration_s",0.0))
static func source_label()->String:return LABEL
static func demo_start_s()->float:return 237570.0 # June3 17:59:30; thirty seconds before the largest actual adjacent-hour modeled wind change.
static func climate_config()->Dictionary:
	return {"latitude_deg":40.25,"longitude_deg":94.75,"start_local":"2025-06-01T00:00:00","utc_offset_hours":8.0,"scenario":"clear"} # clear only locates sky fallback; real meteorological fields override it.

static func metadata()->Dictionary:
	var data:=dataset()
	if not data.valid:return data
	data.erase("rows");data["label"]=LABEL
	data["wind_note"]="100m再分析风速按既有0.14幂律折算90m轮毂，这是模型假设非90m观测；PV冷却采用10m风速。其他轮毂高度由当前设备幂律参数换算。"
	data["irradiance_note"]="Open-Meteo由再分析辐射推算30°朝南平面瞬时GTI（各向同性天空、反照率0.2），不是实测POA。"
	data["sampling_note"]="逐小时样本；小时内零阶保持，不添加秒级波动；第7天结束有真实端点，之后停止。"
	return data

static func sample(time_s:float)->Dictionary:
	var data:=_load()
	if not data.valid:return data
	if not is_finite(time_s) or time_s<0 or time_s>float(data.duration_s):return {"valid":false,"error":"超出历史气象时段；不外推、不循环。"}
	var i:=mini(int(floor(time_s/3600.0)),168)
	var r:Dictionary=data.rows[i]
	return {"valid":true,"wind_speed_mps":float(r.wind_100m_ms),"wind_height_m":100.0,"pv_wind_speed_mps":float(r.wind_10m_ms),"irradiance_wm2":float(r.gti30_south_instant_wm2),"air_temp_c":float(r.temperature_2m_c),"air_density_kgm3":float(r.surface_pressure_hpa)*100.0/(287.05*(float(r.temperature_2m_c)+273.15)),"surface_pressure_hpa":float(r.surface_pressure_hpa),"source":LABEL,"source_time_local":r.timestamp_local,"source_timezone":"Asia/Shanghai","source_sample_index":i,"data_sha256":EXPECTED_SHA,"irradiance_kind":"provider_derived_poa_30deg_south"}

static func _ensure_imports()->void:
	if not _imports.is_empty():return
	var data:=_load()
	if not data.valid:return
	var csv:="time_s,wind_ms,poa_wm2,temp_c\n"
	for r in data.rows:csv+="%d,%.9f,%.9f,%.9f\n"%[int(r.time_s),float(r.wind_100m_ms),float(r.gti30_south_instant_wm2),float(r.temperature_2m_c)]
	for spec in [["wind_ms","wind_ms","m/s"],["irradiance_wm2","poa_wm2","W/m2"],["temp_c","temp_c","C"]]:
		var parsed:Dictionary=Series.parse(csv,{"time_column":"time_s","value_column":spec[1],"time_unit":"s","value_unit":spec[2],"field":spec[0],"target_device":""},{"source_name":LABEL+" · "+EXPECTED_SHA})
		if not parsed.ok:_imports=[];return
		_imports.append(parsed.series)
	_saved_imports=JSON.parse_string(JSON.stringify(_imports))

static func imports()->Array:
	_ensure_imports();return _imports.duplicate(true)

## One-time CSV parse only. Exact in-memory equality detects edited middle
## samples, metadata and bindings too; no per-call JSON, hashing or disk reads.
static func matches_imports(candidate:Array)->bool:
	if candidate.size()!=3:return false
	_ensure_imports()
	if _imports.size()!=3:return false
	for i in _imports.size():
		var reference:Dictionary=_imports[i]
		var found:=false
		for series in candidate:
			if series.get("field")==reference.field and (series==reference or series==_saved_imports[i]):found=true;break
		if not found:return false
	return true
