extends Control
## Presentation-only ring buffer. Feed ONLY successfully committed simulation steps.
## No solving, interpolation, synthetic points, save-state mutation or history persistence.
const Catalog = preload("res://scripts/device_catalog.gd")
const ReadoutCard = preload("res://scripts/right_metric_card.gd")
const MAX_SAMPLES := 240
const MIN_SIM_INTERVAL := 1.0
const MIN_WALL_INTERVAL_MS := 200
const INK := Color("edf3f7")
const MUTED := Color("b3c1cd")
const CYAN := Color("72cbd8")
const AMBER := Color("e8b775")
const GREEN := Color("94d6a7")
var host: Node
var target_id := -2
var target_kind := ""
var target_name := ""
var series: Array = []
var power_unit := "MW"
var has_soc := false
var samples: Array[Dictionary] = []
var ring_head := 0
var sample_count := 0
var last_sim_time := -INF
var last_wall_ms := -1
var redraw_accumulator := 0.0
var dirty := false
var reset_generation := 0

func _init():
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(310,170)
	size = Vector2(350,220)
	samples.resize(MAX_SAMPLES)
	tooltip_text = "已提交运行步的低频瞬时采样；不代表连续积分。仅保留当前所选设备最近240点，切换设备或场景清空。暂停时隐藏。"

func setup(game: Node):
	host = game
	if game.get("font_full") is Font: add_theme_font_override("font",game.font_full)

func reset_history():
	ring_head = 0
	sample_count = 0
	last_sim_time = -INF
	last_wall_ms = -1
	for index in MAX_SAMPLES: samples[index] = {}
	series = []
	has_soc = false
	visible = false
	dirty = true
	reset_generation += 1

func _selected_item() -> Dictionary:
	if not is_instance_valid(host): return {}
	var selected: int = int(host.get("selected_id"))
	var item: Dictionary = host.device(selected)
	if item.is_empty() and host.has_method("station"): item = host.station(selected)
	return item

func sync_target():
	var item := _selected_item()
	var id: int = int(item.get("id",-2))
	var kind: String = str(item.get("kind",""))
	if id != target_id or kind != target_kind:
		reset_history()
		target_id = id
		target_kind = kind
		var names: Dictionary = host.get("DEVICE_NAMES") if is_instance_valid(host) and host.get("DEVICE_NAMES") is Dictionary else {}
		target_name = str(names.get(kind,kind)) + " #%d" % id
	var running: bool = is_instance_valid(host) and not bool(host.get("paused"))
	visible = running and target_id >= 0 and sample_count > 0
	if visible and host.has_method("modal_visible") and host.modal_visible(): visible = false
	if visible and host.get("build_tray_open") == true: visible = false
	if visible and host.get("runtime_chart_layout_available") == false: visible = false
	var layers: Variant = host.get("hud_layers") if is_instance_valid(host) else null
	if visible and layers is Control and layers.visible: visible = false

func _value(report: Dictionary, keys: Array) -> Variant:
	for key in keys:
		if report.has(key):
			var v: Variant = report[key]
			if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v)): return float(v)
	return null

func _extract(item: Dictionary, report: Dictionary) -> Dictionary:
	var kind: String = str(item.get("kind",""))
	if report.get("valid",true) == false: return {}
	if kind in Catalog.Materials.INVENTORY_KINDS:
		var params: Dictionary = item.get("params", {})
		var capacity: float = Catalog.inventory_capacity(kind, params)
		var inventory: Variant = _value(report, ["next_inventory_kg"])
		if inventory == null or not is_finite(capacity) or capacity <= 0.0: return {}
		var outputs: Dictionary = {
			"water_supply_boundary": ["water_out_kg_s", "实际供水"],
			"nitrogen_supply_boundary": ["nitrogen_out_kg_s", "N2(g)供料"],
			"co2_supply_boundary": ["co2_out_kg_s", "CO2(g)供料"],
			"ammonia_synthesis_station": ["product_produced_kg_s", "NH3(g)生成"],
			"methanol_synthesis_station": ["product_produced_kg_s", "CH3OH(l)生成"]}
		var output: Array = outputs.get(kind, ["hydrogen_out_kg_s", "出库氢"])
		var outbound: Variant = _value(report, [output[0]])
		if outbound == null: return {}
		var series: Array = [outbound]
		var names: Array = [output[1]]
		if kind in Catalog.Materials.HYDROGEN_STORE_KINDS:
			var inbound: Variant = _value(report, ["hydrogen_in_kg_s"])
			if inbound == null: return {}
			series = [inbound, outbound]; names = ["入库氢", "出库氢"]
		return {"values":series,"labels":names,"unit":"kg/s","soc":clampf(float(inventory)/capacity*100.0,0.0,100.0)}
	if Catalog.is_storage(kind):
		var thermal: bool = Catalog.is_thermal_storage(kind)
		var suffix := "mwth" if thermal else "mw"
		var charge: Variant = _value(report,["charge_"+suffix])
		var discharge: Variant = _value(report,["discharge_"+suffix])
		if charge == null or discharge == null: return {}
		var params: Dictionary = item.get("params",{})
		var state: Dictionary = item.get("state",{})
		var capacity: float = float(params.get("capacity_mwhth" if thermal else "capacity_mwh",0.0))
		var energy: Variant = _value(state,["energy_mwhth" if thermal else "energy_mwh"])
		if energy == null or capacity <= 0.0: return {}
		return {"values":[charge,discharge],"labels":["充热" if thermal else "充电","放热" if thermal else "放电"],"unit":"MWth" if thermal else "MW","soc":clampf(float(energy)/capacity*100.0,0.0,100.0)}
	var keys: Array = []
	var label := "实际功率"
	var unit := "MW"
	match kind:
		"electrolyzer_station": keys = ["electric_input_mw"]; label = "电解实际用电"
		"fuel_cell_station": keys = ["electric_output_mw"]; label = "实际净出力"
		"wind", "pv": keys = ["sent_mw"]; label = "实际送出"
		"station", "collector_substation": keys = ["sent_mw"]; label = "实际外送"
		"load": keys = ["served_mw"]; label = "实际供电"
		"heat_demand": keys = ["served_mwth"]; label = "实际供热"; unit = "MWth"
		"electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "solar_tower_receiver": keys = ["heat_output_mwth","output_mwth","heat_sent_mwth"]; label = "实际产热"; unit = "MWth"
		"heat_exchanger", "oil_water_exchanger": keys = ["warm_output_mwth","heat_output_mwth","output_mwth"]; label = "实际送热"; unit = "MWth"
		"steam_turbine": keys = ["gross_electric_mw"]; label = "机组毛出力"
		"feedwater_pump": keys = ["pump_electric_mw","electric_input_mw"]; label = "泵用电"
		"steam_condenser": keys = ["condenser_rejection_mwth"]; label = "实际排热"; unit = "MWth"
		"steam_generator", "salt_steam_generator": keys = ["steam_heat_mwth","output_mwth"]; label = "蒸汽增焓"; unit = "MWth"
		_: return {}
	var value: Variant = _value(report,keys)
	if value == null: return {}
	return {"values":[value],"labels":[label],"unit":unit}

func _facility_sample(item: Dictionary, report: Dictionary) -> Dictionary:
	var kind: String = str(item.get("kind",""))
	if kind == "tower_station_preview": return {}
	var thermal: bool = kind == "thermal_station"
	var total := 0.0
	var found := false
	for device_item in host.get("devices"):
		if int(device_item.get("parent_station_id",-1)) != target_id: continue
		if str(device_item.kind) != ("heat_exchanger" if thermal else "steam_turbine"): continue
		var part: Dictionary = _extract(device_item,report.get("devices",{}).get(str(int(device_item.id)),{}))
		if part.is_empty(): continue
		total += float(part.values[0]); found = true
	if not found: return {}
	return {"values":[total],"labels":["换热器实际供热" if thermal else "机组毛出力"],"unit":"MWth" if thermal else "MW"}

func capture_step(report: Dictionary, simulation_time: float, wall_ms: int = -1):
	# Called after inventory updates, never from refresh()/solve-only or a paused preview.
	sync_target()
	if not is_instance_valid(host) or bool(host.get("paused")) or target_id < 0: return
	if not is_finite(simulation_time) or report.get("error","") != "" or report.get("valid",true) == false or report.get("step_valid",true) == false: return
	if simulation_time < last_sim_time: reset_history()
	var now: int = Time.get_ticks_msec() if wall_ms < 0 else wall_ms
	if sample_count > 0 and (simulation_time-last_sim_time < MIN_SIM_INTERVAL or now-last_wall_ms < MIN_WALL_INTERVAL_MS): return
	var item := _selected_item()
	var datum: Dictionary = _facility_sample(item,report) if target_kind in ["thermal_station","tower_station","tower_station_preview"] else _extract(item,report.get("devices",{}).get(str(target_id),{}))
	if datum.is_empty(): return
	if not series.is_empty() and (series != datum.labels or power_unit != datum.unit): reset_history()
	series = datum.labels.duplicate()
	power_unit = str(datum.unit)
	has_soc = datum.has("soc")
	datum["t"] = simulation_time
	samples[ring_head] = datum
	ring_head = (ring_head+1)%MAX_SAMPLES
	sample_count = mini(sample_count+1,MAX_SAMPLES)
	last_sim_time = simulation_time
	last_wall_ms = now
	dirty = true
	sync_target()

func history() -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	var first: int = (ring_head-sample_count+MAX_SAMPLES)%MAX_SAMPLES
	for offset in sample_count: points.append(samples[(first+offset)%MAX_SAMPLES].duplicate(true))
	return points

func _process(delta: float):
	sync_target()
	redraw_accumulator += maxf(0.0,delta)
	if dirty and redraw_accumulator >= 0.25:
		redraw_accumulator = 0.0
		dirty = false
		queue_redraw()

func _text(point: Vector2, value: String, font_size: int, color: Color = INK, width: float = -1.0):
	draw_string(get_theme_font("font"),point,value,HORIZONTAL_ALIGNMENT_LEFT,width,font_size,color)

func _plot(points: Array[Dictionary], box: Rect2, index: int, max_value: float, color: Color, soc: bool = false):
	var vertices := PackedVector2Array()
	var begin: float = float(points[0].t)
	var span: float = maxf(1.0,float(points[-1].t)-begin)
	for point in points:
		var value: float = float(point.get("soc",0.0)) if soc else float(point.values[index])
		vertices.append(Vector2(box.position.x+(float(point.t)-begin)/span*box.size.x,box.end.y-clampf(value/max_value,0.0,1.0)*box.size.y))
	if vertices.size() > 1: draw_polyline(vertices,color,1.8,true)
	elif vertices.size() == 1: draw_circle(vertices[0],2.8,color)

func _series_number(value: float) -> String:
	# A real low hydrogen flow must not be labelled 0.000 kg/s.
	if power_unit == "kg/s" and value != 0.0 and absf(value) < 0.001:
		return ReadoutCard.number(value)
	return "%.3f" % value

func _inventory_axis_label() -> String:
	if target_kind in Catalog.Materials.SYNTHESIS_KINDS: return "产品占容"
	if target_kind in Catalog.Materials.INVENTORY_KINDS: return "库存占容"
	return "SOC"

func _draw():
	if sample_count == 0: return
	var panel := StyleBoxFlat.new(); panel.bg_color = Color("24303ded"); panel.set_corner_radius_all(12);panel.border_color = Color("425565");panel.set_border_width_all(1)
	draw_style_box(panel,Rect2(Vector2.ZERO,size))
	_text(Vector2(14,23),target_name+" · 运行",14,INK,size.x-28)
	var points := history()
	var latest: Dictionary = points[-1]
	var colors: Array[Color] = [CYAN,AMBER]
	for index in series.size():
		_text(Vector2(14+index*152,44),"%s %s %s"%[series[index],_series_number(float(latest.values[index])),power_unit],11,colors[index%2],150)
	var graph := Rect2(45,62,maxf(120,size.x-61),maxf(36,size.y-142) if has_soc else maxf(60,size.y-102))
	var maximum := 0.001 if power_unit == "kg/s" else 0.1 # Keep finite low mass flows readable, with a separate SOC axis.
	for point in points:
		for value in point.values: maximum = maxf(maximum,float(value))
	maximum *= 1.1
	for index in 3:
		var y: float = graph.position.y+graph.size.y*index/2.0
		draw_line(Vector2(graph.position.x,y),Vector2(graph.end.x,y),Color("44515f"),1)
		_text(Vector2(5,y+4),("%.4f" if power_unit == "kg/s" else "%.2f")%(maximum*(1.0-index/2.0)),10,MUTED,38)
	_text(Vector2(8,58),power_unit,10,MUTED)
	for index in series.size(): _plot(points,graph,index,maximum,colors[index%2])
	if has_soc:
		var soc_box := Rect2(graph.position.x,graph.end.y+26,graph.size.x,30)
		draw_line(soc_box.position,Vector2(soc_box.end.x,soc_box.position.y),Color("44515f"),1)
		draw_line(Vector2(soc_box.position.x,soc_box.end.y),soc_box.end,Color("44515f"),1)
		_text(Vector2(8,soc_box.position.y+4),"100%",10,MUTED)
		_text(Vector2(8,soc_box.end.y+3),"0%",10,MUTED)
		_text(Vector2(graph.position.x,soc_box.position.y-6),"%s %.1f%%"%[_inventory_axis_label(),float(latest.soc)],11,GREEN)
		_plot(points,soc_box,0,100.0,GREEN,true)
	_text(Vector2(14,size.y-10),"%.0f–%.0f s · 实际运行采样 · %d 点"%[float(points[0].t),float(latest.t),sample_count],10,MUTED,size.x-28)
