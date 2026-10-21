extends Node
## Separate, read-only forecast. Never applies a schedule to live state or save slots.
const OptimizationPanel = preload("res://scripts/optimization_panel.gd")
const Model = preload("res://scripts/energy_model.gd")
const Series = preload("res://scripts/series_import.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const FuelSupply = preload("res://scripts/fuel_supply.gd")
var host: Node
var panel: Window
var pid: int = -1
var request_id := ""
var revision := -1
var request: Dictionary = {}
var baseline: Dictionary = {}
var last_result: Dictionary = {}
var output_path := ""
var cancel_path := ""
var started_ms := 0
var cancel_started_ms := 0
var cancel_reason := ""
var timeout_s := 30.0
var run_folder := ""
var python_executable := "python3"
var solver_executable := "glpsol"

func setup(game: Node) -> void:
	host = game
	panel = OptimizationPanel.new()
	add_child(panel)
	panel.solve_requested.connect(start)
	panel.cancel_requested.connect(cancel)
	if OS.has_environment("BASIN_GLPK"):
		solver_executable = OS.get_environment("BASIN_GLPK")
	if OS.has_environment("BASIN_PYTHON"):
		python_executable = OS.get_environment("BASIN_PYTHON")

func open() -> void:
	host.paused = true
	host.update_status()
	panel.set_thermal_context(_has_thermal_devices(host.devices))
	panel.open()

func _has_thermal_devices(devices: Array) -> bool:
	for device in devices:
		if device.get("kind", "") in ["electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "high_temp_store", "oil_water_exchanger", "thermal_store", "solid_thermal_store", "heat_exchanger", "heat_demand","steam_generator","steam_turbine","steam_condenser","feedwater_pump","solar_tower_receiver","molten_salt_store","salt_steam_generator"]:
			return true
	return false

func _has_fuel_devices(devices: Array) -> bool:
	for device in devices:
		if device.get("kind", "") == "fuel_boiler": return true
	return false

func snapshot(options: Dictionary) -> Dictionary:
	var fuel: Variant = host.get("fuel_supply")
	if fuel == null: fuel = FuelSupply.defaults()
	var fuel_error: String = FuelSupply.validate(fuel)
	if not fuel_error.is_empty(): return {"error": "燃料资源无效：" + fuel_error}
	var frozen_fuel: Dictionary = fuel.duplicate(true)
	var horizon := float(options.get("horizon_hours", 24.0))
	var step_minutes := float(options.get("step_minutes", 60.0))
	var multiplier := float(options.get("load_multiplier", 1.0))
	if not is_finite(horizon) or not is_finite(step_minutes) or not is_finite(multiplier) or horizon <= 0 or horizon > 168 or step_minutes < 5 or step_minutes > 360 or multiplier < 0 or multiplier > 10:
		return {"error": "时域须在0–168小时，步长5–360分钟，负荷倍数0–10。"}
	var frozen_options := options.duplicate(true)
	frozen_options["terminal_heat_soc_fraction"] = options.get("terminal_heat_soc_fraction")
	frozen_options["heat_service_weight"] = options.get("heat_service_weight", 1.0)
	var heat_target: Variant = frozen_options.terminal_heat_soc_fraction
	if heat_target != null and (not (heat_target is float or heat_target is int) or not is_finite(float(heat_target)) or float(heat_target) < 0 or float(heat_target) > 1):
		return {"error": "热储期末 SOC 下限须为0–1比例。"}
	var heat_weight: Variant = frozen_options.heat_service_weight
	if not (heat_weight is float or heat_weight is int) or not is_finite(float(heat_weight)) or float(heat_weight) <= 0 or float(heat_weight) > 10000:
		return {"error": "供热服务权重须大于0且不超过10000；这是教学服务权重，非价格。"}
	var count := int(ceil(horizon * 60.0 / step_minutes))
	if count > 336:
		return {"error": "最多336个时段，请缩短时域或加大步长。"}
	var finish := float(host.elapsed_s) + horizon * 3600.0
	var interval: Dictionary = host.common_interval(host.imports)
	if float(host.elapsed_s) < float(interval.start) or finish > float(interval.end) + 1e-7:
		return {"error": "预测时域超出当前有效CSV共同区间；不会外推。请缩短时域。"}
	var frozen: Array = []
	for d in host.devices:
		var params: Dictionary = Model.defaults(d.kind)
		params.merge(d.params, true)
		var validation: Array = Model.validate(d.kind, params)
		if not validation.is_empty():
			return {"error": "; ".join(validation)}
		var item := {"id": int(d.id), "kind": d.kind, "params": params}
		var state: Variant = d.get("state", Catalog.initial_state(d.kind, params))
		var state_errors := Catalog.validate_state(d.kind, params, state)
		if not state_errors.is_empty():
			return {"error": "设备库存状态无效：" + "; ".join(state_errors)}
		if d.has("state") or d.kind in ["battery", "battery_sodium", "battery_flow", "caes_aboveground", "liquid_air_store", "hydrogen_storage_system", "thermal_store", "solid_thermal_store", "high_temp_store", "molten_salt_store"]:
			item.state = state.duplicate(true)
		if d.kind in ["electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "high_temp_store", "oil_water_exchanger", "thermal_store", "solid_thermal_store", "heat_exchanger", "heat_demand","steam_generator","steam_turbine","steam_condenser","feedwater_pump","solar_tower_receiver","molten_salt_store","salt_steam_generator"]:
			item.model_profile = d.get("model_profile", Catalog.model_profile(d.kind))
			item.model_profile_version = d.get("model_profile_version", 1)
		frozen.append(item)
	if frozen.is_empty(): return {"error": "请先建造设备；优化不会新增设备。"}
	var valid_links: Array = []
	for line in host.links:
		var reason := Catalog.validate_link(frozen, valid_links, line)
		if reason != "": return {"error": "拓扑未通过校验：" + reason}
		var normalized:Dictionary=line.duplicate(true)
		# Older electric connections carried an empty thermal-grade placeholder.
		if normalized.get("carrier","electricity_ac")=="electricity_ac" and normalized.get("grade_id","__absent__")=="":normalized.erase("grade_id")
		valid_links.append(normalized)
	var steps: Array = []
	var source_labels: Dictionary = {}
	var t := float(host.elapsed_s)
	while t < finish - 1e-8:
		if steps.size()>=336:return {"error":"CSV边界细分后超过336时段；请缩短分析时域。"}
		var duration := minf(step_minutes * 60.0, finish - t)
		for series in host.active_series():
			var value:Dictionary=Series.sample(series,t)
			if value.status!="ok":return {"error":"预测采样超出CSV区间。"}
			var next_index:int=int(value.index)+1
			if next_index<series.samples.size():duration=minf(duration,float(series.samples[next_index].t)-t)
		if duration<=0:return {"error":"CSV时间边界无法推进。"}
		var dat: Dictionary = host.sampled(t)
		if dat.error != "": return {"error": dat.error}
		var available: Dictionary = {}
		var demands: Dictionary = {}
		var heat_demands: Dictionary = {}
		for d in frozen:
			var key := str(int(d.id))
			if d.kind == "load":
				demands[key] = float(d.params.demand_mw) * multiplier
			elif d.kind == "heat_demand":
				heat_demands[key] = float(d.params.demand_mwth)
			elif d.kind in ["wind", "pv"]:
				var rating := float(d.params.get("rated_mw", d.params.get("inverter_capacity_mw", 0.0)))
				if dat.direct.has(key):
					available[key] = minf(float(dat.direct[key].mw), rating)
					source_labels[key] = "CSV直接功率作为可用出力假设"
				else:
					var weather: Dictionary = dat.weather.duplicate(true)
					weather.merge(dat.device_weather.get(key, {}), true)
					var generation: Dictionary = Model.generation(d.kind, d.params, weather)
					if not generation.get("valid", false): return {"error": "设备出力模型未通过校验"}
					available[key] = minf(float(generation.mw), rating)
					source_labels[key] = "CSV气象/未绑定字段内置天气" if not dat.sources.is_empty() or dat.device_weather.has(key) else "内置教学天气"
		steps.append({"time_s": t, "dt_h": duration / 3600.0, "available_mw": available, "demand_mw": demands, "heat_demand_mwth": heat_demands, "weather": dat.weather.duplicate(true)})
		t += duration
	return {"schema_version": 7 if frozen.any(func(d):return d.kind in Catalog.NEW_STORAGE_KINDS) else 6 if frozen.any(func(d):return Catalog.is_tower(d.kind)) else 5 if frozen.any(func(d):return d.kind in ["steam_generator","steam_turbine","steam_condenser","feedwater_pump","solar_tower_receiver","molten_salt_store","salt_steam_generator"]) else 4 if frozen.any(func(d):return Catalog.is_high_temp(d.kind)) else Catalog.SCHEMA_VERSION if _has_fuel_devices(frozen) or frozen.any(func(d):return d.kind in ["solar_thermal","parabolic_trough","high_temp_store","oil_water_exchanger"]) else 2, "devices": frozen, "links": valid_links, "steps": steps, "grid_capacity_mw": Catalog.GRID_CAPACITY_MW,
		"fuel_supply": frozen_fuel, "options": frozen_options, "metadata": {"request_id": request_id, "scene_revision": host.scene_revision, "start_time_s": host.elapsed_s,"climate_config":host.climate_config.duplicate(true)},
		"forecast": {"sampling": "left endpoint; piecewise constant; split exactly at every active CSV boundary", "sources": source_labels, "climate": "same deterministic location/calendar and imported/teaching weather sampler as live world; isolated from live visual time", "load": "fixed electric demand multiplied by explicit forecast task factor", "heat_demand": "constant device demand; heat-demand CSV import is not supported", "heat_service_weight": "teaching service weight, not an electricity/heat price or economic equivalence", "capacity_expansion": false, "fuel": "shared bounded LHV input; explicit auxiliary AC consumption; configured CNY/MWh teaching cost, not a market tariff"}}

func make_baseline(data: Dictionary) -> Dictionary:
	var fleet: Array = data.devices.duplicate(true)
	var rows: Array = []
	for step in data.steps:
		var direct: Dictionary = {"_fuel_supply": data.get("fuel_supply", FuelSupply.defaults()).duplicate(true)}
		for key in step.available_mw: direct[key] = {"mw": step.available_mw[key], "source": "same forecast"}
		for d in fleet:
			if d.kind == "load": d.params.demand_mw = step.demand_mw[str(int(d.id))]
			elif d.kind == "heat_demand": d.params.demand_mwth = step.heat_demand_mwth[str(int(d.id))]
		var r: Dictionary = Model.dispatch(fleet, data.links, step.get("weather",{}), direct, float(step.dt_h) * 3600.0)
		if not r.get("valid", false): return {"error": "基准调度未通过校验：" + "; ".join(r.get("errors", [])), "steps": []}
		var row := {"time_s": step.time_s, "dt_h": step.dt_h, "wind_mw": 0.0, "pv_mw": 0.0, "export_mw": r.delivered_mw, "energy_mwh": 0.0, "soc": 0.0}
		for k in ["available_mw", "demand_mw", "served_mw", "unserved_mw", "charge_mw", "discharge_mw", "curtailed_mw", "loss_mw"]: row[k] = r.get(k, 0.0)
		if _has_thermal_devices(fleet):
			if not r.get("thermal") is Dictionary:
				return {"error": "基准调度缺少热账本，不能退回纯电比较。", "steps": []}
			row.thermal = r.thermal.duplicate(true)
			row.boiler_electric_mw = r.get("boiler_electric_mw")
			row.boiler_conversion_loss_mw = r.get("boiler_conversion_loss_mw")
		if _has_fuel_devices(fleet) and not r.get("fuel") is Dictionary:
			return {"error": "基准调度缺少燃料账本，不能将燃料视为免费热源。", "steps": []}
		if r.get("fuel") is Dictionary: row.fuel = r.fuel.duplicate(true)
		if r.get("solar") is Dictionary: row.solar = r.solar.duplicate(true)
		if r.get("high_temp") is Dictionary: row.high_temp = r.high_temp.duplicate(true)
		if r.get("tower") is Dictionary: row.tower = r.tower.duplicate(true)
		if r.get("rankine") is Dictionary: row.rankine = r.rankine.duplicate(true)
		row.devices = r.get("devices", {}).duplicate(true)
		var capacity := 0.0
		for d in fleet:
			var key := str(int(d.id))
			if d.kind in ["wind", "pv"]: row[d.kind + "_mw"] += float(r.devices[key].sent_mw)
			if Catalog.is_electric_storage(d.kind):
				d.state = r.next_states[key].duplicate(true)
				row.energy_mwh += float(d.state.energy_mwh)
				capacity += float(d.params.capacity_mwh)
			elif d.kind in ["thermal_store", "solid_thermal_store", "high_temp_store", "molten_salt_store"]:
				if not r.get("next_states", {}).has(key) or not r.next_states[key].has("energy_mwhth"):
					return {"error": "基准调度缺少热库存状态。", "steps": []}
				d.state = r.next_states[key].duplicate(true)
		row.soc = row.energy_mwh / capacity if capacity > 0 else 0.0
		rows.append(row)
	return {"steps": rows, "policy": "realtime priority_then_stable_id; same forecast and initial state; electric and thermal terminal SOC not enforced"}

func start(options: Dictionary) -> void:
	if pid > 0: return
	host.paused = true
	host.update_status()
	request_id = "%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	request = snapshot(options)
	if request.has("error"):
		panel.show_error(request.error)
		return
	var source_summary: Array = []
	for source in request.forecast.sources.values():
		if not source_summary.has(source): source_summary.append(source)
	panel.set_thermal_context(_has_thermal_devices(request.devices))
	var thermal_note := " 热需求为常量，暂不支持热需求CSV导入；供热服务权重是教学权重，非价格。" if _has_thermal_devices(request.devices) else ""
	if _has_fuel_devices(request.devices):
		thermal_note += " 燃料共享上限 %s MW LHV；价格 %s CNY/MWh 为教学假设。辅机耗电与散热单列；第五目标在原四目标固定后最小化燃料费用。" % [request.fuel_supply.max_input_mw if request.fuel_supply.enabled else 0, request.fuel_supply.price_per_mwh]
	panel.set_context("输入：" + "；".join(source_summary) + "。时段左值保持；电负荷按任务倍数，未新增设备。" + thermal_note)
	revision = int(host.scene_revision)
	baseline = make_baseline(request)
	if baseline.has("error"):
		panel.show_error(baseline.error)
		return
	last_result = {}
	run_folder = ProjectSettings.globalize_path("user://optimization_runs/" + request_id)
	DirAccess.make_dir_recursive_absolute(run_folder)
	var input_path := run_folder.path_join("request.json")
	output_path = run_folder.path_join("result.json")
	cancel_path = run_folder.path_join("cancel")
	timeout_s = clampf(float(options.get("timeout_s", 30)), 1.0, 120.0)
	request.options.timeout_s = timeout_s
	var file := FileAccess.open(input_path, FileAccess.WRITE)
	if file == null:
		panel.show_error("无法写入求解快照")
		return
	file.store_string(JSON.stringify(request)); file.close()
	timeout_s = clampf(float(options.get("timeout_s", 30)), 1.0, 120.0)
	request.options.timeout_s = timeout_s
	var script_path := ProjectSettings.globalize_path("res://tools/dispatch_solver.py")
	if not FileAccess.file_exists(script_path):
		panel.show_error("未找到后端脚本；桌面打包尚未验证。")
		return
	pid = OS.create_process(python_executable, PackedStringArray([script_path, "--input", input_path, "--output", output_path, "--glpsol", solver_executable, "--cancel-file", cancel_path]))
	if pid <= 0:
		panel.show_error("启动失败：需要Python 3与GLPK glpsol。")
		return
	started_ms = Time.get_ticks_msec()
	cancel_started_ms = 0
	cancel_reason = ""
	panel.set_busy(true)
	panel.set_status("GLPK异步求解中 · 固定已建容量 · %d个时段" % request.steps.size())

func cancel() -> void:
	request_cancel("已取消；未改变实时状态或存档。")

func request_cancel(reason: String) -> void:
	if pid <= 0: return
	if cancel_started_ms > 0: return
	cancel_reason = reason
	cancel_started_ms = Time.get_ticks_msec()
	var file := FileAccess.open(cancel_path, FileAccess.WRITE)
	if file != null: file.store_string("cancel"); file.close()
	panel.set_status("正在停止求解…")

func _process(_delta: float) -> void:
	if not is_instance_valid(host): return
	if pid <= 0:
		if not last_result.is_empty() and int(host.scene_revision) != revision:
			last_result = {}
			panel.mark_stale()
		return
	if int(host.scene_revision) != revision: request_cancel("场景已变化，旧快照结果已丢弃。")
	if Time.get_ticks_msec() - started_ms > int((timeout_s + 5.0) * 1000.0): request_cancel("求解超时；未改变实时状态或存档。")
	if cancel_started_ms > 0 and Time.get_ticks_msec() - cancel_started_ms > 3000 and OS.is_process_running(pid): OS.kill(pid)
	if OS.is_process_running(pid): return
	pid = -1
	panel.set_busy(false)
	if cancel_reason != "":
		panel.show_error(cancel_reason)
		return
	if not FileAccess.file_exists(output_path):
		panel.show_error("求解进程退出但未产生结果。请检查Python/GLPK安装。")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(output_path))
	if not parsed is Dictionary:
		panel.show_error("求解结果不是有效JSON，已拒绝。")
		return
	var solved: Dictionary = parsed
	if int(host.scene_revision) != revision or solved.get("metadata", {}).get("request_id", "") != request_id:
		panel.mark_stale()
		return
	if not solved.get("status", "error") in ["optimal", "feasible"]:
		var names := {"infeasible": "无可行解", "timeout": "超时且未得到可行解", "cancelled": "已取消", "error": "求解失败"}
		panel.show_error(str(names.get(solved.get("status"), solved.get("status", "求解失败"))) + "：" + str(solved.get("message", solved.get("error", "查看运行记录"))))
		return
	if not solved.get("validation", {}).get("valid", false):
		panel.show_error("独立守恒/边界复核未通过，拒绝显示为可用方案。")
		return
	if _has_thermal_devices(request.devices):
		if solved.get("schema_version") != request.schema_version:
			panel.show_error("求解结果版本须与冻结快照匹配；不能使用旧版结果。")
			return
		for step in solved.get("steps", []):
			if not step is Dictionary or not step.get("thermal") is Dictionary:
				panel.show_error("求解结果缺少热账本；不能退回纯电显示。")
				return
	if _has_fuel_devices(request.devices):
		for step in solved.get("steps", []):
			if not step is Dictionary or not step.get("fuel") is Dictionary:
				panel.show_error("求解结果缺少燃料/辅机账本，已拒绝。")
				return
	if request.devices.any(func(d):return d.kind=="solar_thermal"):
		for step in solved.get("steps",[]):
			if not step.get("solar") is Dictionary:
				panel.show_error("求解结果缺少太阳能独立账本，已拒绝。")
				return
	if request.devices.any(func(d):return Catalog.is_high_temp(d.kind)):
		for step in solved.get("steps",[]):
			if not step.get("high_temp") is Dictionary:
				panel.show_error("求解结果缺少高温油独立账本，已拒绝。")
				return
	if request.devices.any(func(d):return Catalog.is_tower(d.kind)):
		for step in solved.get("steps",[]):
			if not step.get("tower") is Dictionary:
				panel.show_error("求解结果缺少塔式熔盐独立账本，已拒绝。")
				return
	last_result = solved
	panel.show_result(solved, baseline)

func _exit_tree() -> void:
	if pid > 0:
		var file := FileAccess.open(cancel_path, FileAccess.WRITE)
		if file != null: file.store_string("cancel"); file.close()
