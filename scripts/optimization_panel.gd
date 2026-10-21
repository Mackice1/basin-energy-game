extends Window
## Read-only forecast UI. The controller owns snapshot capture, solver lifecycle,
## cancellation and all realtime state. This window only emits options/signals.

signal solve_requested(options: Dictionary)
signal cancel_requested

const Chart = preload("res://scripts/optimization_chart.gd")
const MaterialCatalog=preload("res://scripts/material_catalog.gd")
const ReadoutCard=preload("res://scripts/right_metric_card.gd")
const MATERIAL_RATES=[
	["water_withdrawn_kg_s","取水"],["hydrogen_produced_kg_s","制氢"],["hydrogen_consumed_kg_s","燃料电池用氢"],["hydrogen_charged_kg_s","充氢"],["hydrogen_discharged_kg_s","放氢"],["oxygen_vented_kg_s","排氧"],["oxygen_from_air_kg_s","空气取氧"],["water_released_kg_s","排水"]]
const MATERIAL_POWERS=[
	["electrolyzer_electric_mw","电解用电","MW","MWh"],["compression_electric_mw","压缩用电","MW","MWh"],["fuel_cell_output_mw","燃料电池净出电","MW","MWh"],["heat_rejected_mwth","环境排热","MWth","MWhth"]]
const PHASE_POWERS=[["phase_store_electric_mw","液态/固态储氢用电","MW","MWh"],["environment_heat_in_mwth","环境吸热","MWth","MWhth"]]
const CHEMICAL_RATES=[
	["nitrogen_withdrawn_kg_s","N2(g) 供料"],["co2_withdrawn_kg_s","CO2(g) 供料"],["chemical_hydrogen_consumed_kg_s","化工耗氢"],["ammonia_produced_kg_s","NH3(g) 生成"],["methanol_produced_kg_s","CH3OH(l) 生成"],["chemical_water_released_kg_s","化工排水（总排水子项）"]]
const CHEMICAL_STOCKS=[
	["nitrogen_inventory_kg","N2(g) 供料库存"],["co2_inventory_kg","CO2(g) 供料库存"],["ammonia_inventory_kg","NH3(g) 产品库存"],["methanol_inventory_kg","CH3OH(l) 产品库存"]]
const INK := Color("edf3f6")
const MUTED := Color("a5b7c4")
const BORDER := Color("344b59")
const ERROR := Color("ff9790")
const PAPER := Color("14212b")
const ACCENT := Color("69d1bd")
const AMBER := Color("efbc68")
const METRICS := [
	["served_mw", "实供电量"], ["unserved_mw", "缺供电量"],
	["curtailed_mw", "弃电量"], ["export_mw", "外送电量"],
	["charge_mw", "AC 充电电量"], ["discharge_mw", "AC 放电电量"],
	["loss_mw", "网络损耗电量"]
]
const THERMAL_METRICS := [
	["served_mwth", "实供热量"], ["unserved_mwth", "缺供热量"],
	["boiler_heat_mwth", "电锅炉出热"], ["charge_mwth", "储热充入"],
	["discharge_mwth", "储热放出"], ["network_loss_mwth", "热网损失"],
	["exchanger_loss_mwth", "换热损失"], ["storage_conversion_loss_mwth", "储热转换损失"]
]

var _built := false
var _busy := false
var _updating := false
var _result: Dictionary = {}
var _baseline: Dictionary = {}
var _steps: Array = []
var _selected := -1
var _status: Label
var _context: Label
var _error: Label
var _run: Button
var _cancel: Button
var _horizon: SpinBox
var _step: SpinBox
var _load: SpinBox
var _timeout: SpinBox
var _strict: CheckBox
var _terminal_enabled: CheckBox
var _terminal: SpinBox
var _thermal_enabled := false
var _thermal_settings: HFlowContainer
var _terminal_heat_enabled: CheckBox
var _terminal_heat: SpinBox
var _heat_weight: SpinBox
var _editors: Array[Control] = []
var _power_chart: Control
var _soc_chart: Control
var _thermal_chart: Control
var _thermal_soc_chart: Control
var _thermal_energy_chart: Control
var _thermal_tab_index := -1
var _comparison: GridContainer
var _comparison_note: Label
var _selection: Label
var _detail: RichTextLabel
var _step_choice: OptionButton
var _tabs: TabContainer
var _previous: Button
var _next: Button
var _material_enabled:=false
var _material_tab_index:=-1
var _material_targets:VBoxContainer
var _material_target_note:Label
var _material_summary:Label
var _material_controls:Dictionary={}
var _material_context:Array=[]
var _pending_material_targets:Dictionary={}
var _material_invalidated_targets:Array[String]=[]
var _product_enabled:=false
var _product_section:VBoxContainer
var _product_targets:VBoxContainer
var _product_target_note:Label
var _product_controls:Dictionary={}
var _pending_product_targets:Dictionary={}
var _product_invalidated_targets:Array[String]=[]

func _init() -> void:
	visible = false
	title = "GLPK · 隔离调度预测"
	size = Vector2i(1000, 740)
	min_size = Vector2i(700, 580)
	transient = true
	exclusive = true

func _ready() -> void:
	_build_ui()

func open() -> void:
	_build_ui()
	popup_centered_clamped(Vector2i(1000, 740), 0.94)

## Optional controller defaults; safe before or after _ready. Scene capacities
## are intentionally not editable here. terminal_soc_fraction is null or 0..1.
func configure(options: Dictionary = {}) -> void:
	_build_ui()
	_updating = true
	if options.has("terminal_heat_soc_fraction") or options.has("heat_service_weight"):
		set_thermal_context(true)
	_horizon.value = float(options.get("horizon_hours", _horizon.value))
	_step.value = float(options.get("step_minutes", _step.value))
	_load.value = float(options.get("load_multiplier", _load.value))
	_timeout.value = float(options.get("timeout_s", _timeout.value))
	_strict.button_pressed = bool(options.get("strict_supply", _strict.button_pressed))
	if options.has("terminal_soc_fraction"):
		var target: Variant = options.terminal_soc_fraction
		_terminal_enabled.button_pressed = target != null
		if target != null:
			_terminal.value = float(target)
	_terminal.editable = _terminal_enabled.button_pressed and not _busy
	if options.has("terminal_heat_soc_fraction"):
		var heat_target: Variant = options.terminal_heat_soc_fraction
		_terminal_heat_enabled.button_pressed = heat_target != null
		if heat_target != null:
			_terminal_heat.value = float(heat_target)
	_heat_weight.value = float(options.get("heat_service_weight", _heat_weight.value))
	_terminal_heat.editable = _terminal_heat_enabled.button_pressed and not _busy
	if options.get("terminal_hydrogen_kg") is Dictionary:
		_pending_material_targets=options.terminal_hydrogen_kg.duplicate(true)
		_apply_material_targets(_pending_material_targets)
		if _material_enabled:_pending_material_targets.clear()
	if options.get("terminal_product_kg") is Dictionary:
		_pending_product_targets=options.terminal_product_kg.duplicate(true)
		_apply_product_targets(_pending_product_targets)
		if _product_enabled:_pending_product_targets.clear()
	# SpinBox redraws its LineEdit later; keep immediate get_options() from
	# applying the previous text over freshly configured values.
	for editor in _editors:
		if editor is SpinBox:
			editor.get_line_edit().text = str(editor.value)
	_updating = false

func get_options() -> Dictionary:
	_build_ui()
	_commit_editors()
	var options := {
		"horizon_hours": _horizon.value,
		"step_minutes": _step.value,
		"load_multiplier": _load.value,
		"strict_supply": _strict.button_pressed,
		"terminal_soc_fraction": _terminal.value if _terminal_enabled.button_pressed else null,
		"timeout_s": int(_timeout.value)
	}
	# Preserve the original pure-electric UI contract. The controller always
	# supplies schema-2 defaults; heat options appear when the scene uses heat.
	if _thermal_enabled:
		options.terminal_heat_soc_fraction = _terminal_heat.value if _terminal_heat_enabled.button_pressed else null
		options.heat_service_weight = _heat_weight.value
	if _material_enabled:options.terminal_hydrogen_kg=_material_options()
	if _product_enabled:options.terminal_product_kg=_product_options()
	return options

func set_thermal_context(enabled: bool) -> void:
	_build_ui()
	_thermal_enabled = enabled
	_thermal_settings.visible = enabled
	_tabs.set_tab_hidden(_thermal_tab_index, not enabled)

func set_busy(value: bool) -> void:
	_build_ui()
	_busy = value
	_run.disabled = value
	_run.text = "正在求解…" if value else "运行 GLPK 优化"
	_cancel.disabled = not value
	for editor in _editors:
		if editor is SpinBox:
			editor.editable = not value
		elif editor is BaseButton:
			editor.disabled = value
	_terminal.editable = not value and _terminal_enabled.button_pressed
	_terminal_heat.editable = not value and _terminal_heat_enabled.button_pressed
	for controls in _material_controls.values()+_product_controls.values():controls.amount.editable=not value and controls.enabled.button_pressed
	if value:
		_clear_result("正在计算当前任务…")
		_error.hide()
	_status.add_theme_color_override("font_color", AMBER if value else MUTED)

func set_status(text: String) -> void:
	_build_ui()
	_status.text = text

func set_context(text: String) -> void:
	_build_ui()
	_context.text = text
	_context.visible = not text.is_empty()

func show_error(text: String) -> void:
	_build_ui()
	set_busy(false)
	_clear_result("本次任务没有可显示的结果")
	_error.text = text
	_error.show()
	_status.text = "未得到有效结果，请检查任务条件或求解器状态。"
	_status.add_theme_color_override("font_color", ERROR)

func mark_stale() -> void:
	_build_ui()
	_clear_result("场景或任务设置已变化，请重新求解")
	_status.text = "结果已失效：当前场景或任务设置与求解时不同。"
	_status.add_theme_color_override("font_color", AMBER)

func show_result(result: Dictionary, baseline: Dictionary = {}) -> void:
	_build_ui()
	set_busy(false)
	var steps: Variant = result.get("steps", [])
	var invalid := _validate_steps(steps)
	if not invalid.is_empty():
		show_error("结果无法展示：" + invalid)
		return
	_result = result.duplicate(true)
	_baseline = baseline.duplicate(true)
	_steps = _result.steps
	if _has_thermal_data(_steps):
		set_thermal_context(true)
	_tabs.set_tab_hidden(_material_tab_index,not (_material_enabled or _has_material_data(_steps)))
	_error.hide()
	_power_chart.set_steps(_steps)
	_soc_chart.set_steps(_steps)
	var thermal_steps := _thermal_plot_steps()
	_thermal_chart.set_steps(thermal_steps)
	_thermal_soc_chart.set_steps(thermal_steps)
	_thermal_energy_chart.set_steps(thermal_steps)
	_step_choice.clear()
	for index in range(_steps.size()):
		var step_data: Dictionary = _steps[index]
		_step_choice.add_item("第 %d 步 · t = %s h" % [index + 1, _num(float(step_data.time_s) / 3600.0)])
	_step_choice.disabled = false
	_build_comparison()
	_select_step(0)
	var solver_state := str(result.get("status", "完成"))
	var status_names := {"optimal": "已证明最优", "feasible": "已有可行解（未证明最优）", "success": "完成", "ok": "完成"}
	_status.text = "求解结果：%s · %d 个时段 · 固定容量、隔离预测" % [status_names.get(solver_state.to_lower(), solver_state), _steps.size()]
	_status.add_theme_color_override("font_color", ACCENT)

func _build_ui() -> void:
	if _built:
		return
	_built = true
	theme = _make_theme()
	close_requested.connect(_close)
	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override("panel", _style(Color("0c151e"), BORDER, 0, 0))
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	background.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var heading_row := HBoxContainer.new()
	column.add_child(heading_row)
	var heading := _label("隔离调度预测", 24)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(heading)
	var badge := _label("GLPK · 只读沙盒", 12, ACCENT)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading_row.add_child(badge)
	var subtitle := _label("固定当前设备容量与拓扑；预测可用风光，不是实测调度或 AC 潮流。结果不写回实时场景。", 13, MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(subtitle)
	_context = _label("", 13, MUTED)
	_context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context.hide()
	column.add_child(_context)
	var settings := HFlowContainer.new()
	settings.add_theme_constant_override("h_separation", 14)
	settings.add_theme_constant_override("v_separation", 4)
	column.add_child(settings)
	_horizon = _add_number(settings, "预测时长 / h", 0.25, 168, 0.25, 24)
	_step = _add_number(settings, "步长 / min", 5, 360, 1, 60)
	_load = _add_number(settings, "电负荷倍率", 0, 10, 0.05, 1)
	_timeout = _add_number(settings, "时限 / s", 1, 120, 1, 30)
	var toggles := HFlowContainer.new()
	toggles.add_theme_constant_override("h_separation", 12)
	column.add_child(toggles)
	_strict = CheckBox.new()
	_strict.text = "严格保供（电热全覆盖）"
	_strict.tooltip_text = "任何时段不能满足电需求或热需求，都可能使优化不可行。"
	toggles.add_child(_strict)
	_editors.append(_strict)
	_strict.toggled.connect(func(_value): _options_changed())
	_terminal_enabled = CheckBox.new()
	_terminal_enabled.text = "电池期末 SOC 下限"
	_terminal_enabled.tooltip_text = "可选约束；用 0–1 比例，例如 0.5 = 50%。"
	toggles.add_child(_terminal_enabled)
	_editors.append(_terminal_enabled)
	_terminal = SpinBox.new()
	_terminal.min_value = 0.0
	_terminal.max_value = 1.0
	_terminal.step = 0.01
	_terminal.value = 0.5
	_terminal.custom_minimum_size = Vector2(100, 34)
	_terminal.editable = false
	_terminal.tooltip_text = "比例 0–1；0.5 表示 50%。不改变已建电池的当前库存。"
	toggles.add_child(_terminal)
	_editors.append(_terminal)
	toggles.add_child(_label("比例 0–1", 12, MUTED))
	_terminal_enabled.toggled.connect(func(value):
		_terminal.editable = value and not _busy
		_options_changed())
	_terminal.value_changed.connect(func(_value): _options_changed())
	_thermal_settings = HFlowContainer.new()
	_thermal_settings.add_theme_constant_override("h_separation", 12)
	_thermal_settings.add_theme_constant_override("v_separation", 4)
	column.add_child(_thermal_settings)
	_terminal_heat_enabled = CheckBox.new()
	_terminal_heat_enabled.text = "热储期末 SOC 下限"
	_thermal_settings.add_child(_terminal_heat_enabled)
	_editors.append(_terminal_heat_enabled)
	_terminal_heat = _add_number(_thermal_settings, "比例 0–1", 0, 1, 0.01, 0.5)
	_terminal_heat.editable = false
	_terminal_heat.tooltip_text = "独立约束每个热储；不改变当前热库存，也不套用电池期末限制。"
	_terminal_heat_enabled.toggled.connect(func(value):
		_terminal_heat.editable = value and not _busy
		_options_changed())
	_heat_weight = _add_number(_thermal_settings, "供热服务权重", 0.01, 10000, 0.01, 1)
	_heat_weight.tooltip_text = "教学服务权重，非价格或电热经济等价。默认1；目标按优先级权重最小化未服务能量，不是严格优先级。"
	_thermal_settings.hide()
	_status = _label("设置任务后运行。仅显示实际返回的求解结果。", 14)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_stylebox_override("normal", _style(PAPER, BORDER, 6, 6))
	column.add_child(_status)
	_error = _label("", 14, ERROR)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.hide()
	column.add_child(_error)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_tabs)
	_build_chart_tab()
	_build_comparison_tab()
	_build_detail_tab()
	_build_thermal_chart_tab()
	_tabs.set_tab_hidden(_thermal_tab_index, true)
	_build_material_tab()
	_tabs.set_tab_hidden(_material_tab_index,true)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var hint := _label("电：MW / MWh · 热：MWth / MWhth · SOC 分开显示", 12, MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(hint)
	_run = _button("运行 GLPK 优化", _request_solve)
	for state in ["normal", "hover", "pressed"]:
		_run.add_theme_stylebox_override(state, _style(Color("224a4c") if state == "normal" else Color("2e6260"), ACCENT, 6, 8))
	_run.add_theme_color_override("font_color", INK)
	actions.add_child(_run)
	_cancel = _button("取消计算", _request_cancel)
	_cancel.disabled = true
	actions.add_child(_cancel)
	actions.add_child(_button("关闭", _close))
	_clear_result("尚无求解结果")

func _build_chart_tab() -> void:
	var body := _scroll_tab("结果曲线")
	_power_chart = Chart.new()
	_power_chart.custom_minimum_size.y = 225
	_power_chart.configure("功率时序", "MW", [
		{"key": "wind_mw", "label": "风可用", "color": Color("72b9ec")},
		{"key": "pv_mw", "label": "光可用", "color": Color("efbc68")},
		{"key": "demand_mw", "label": "需求", "color": Color("edf3f6")},
		{"key": "charge_mw", "label": "充电", "color": Color("ba9aef")},
		{"key": "discharge_mw", "label": "放电", "color": Color("f2a978")},
		{"key": "boiler_electric_mw", "label": "电锅炉", "color": Color("e69dbf")},
		{"key":"rankine.gross_electric_mw","label":"蒸汽毛发电","color":Color("7dd4e8")},
		{"key":"rankine.auxiliary_electric_mw","label":"循环辅机","color":Color("e9b39a")},
		{"key":"rankine.net_electric_mw","label":"循环净发电","color":Color("69d1bd")},
		{"key":"tower.auxiliary_electric_mw","label":"塔/盐泵辅机","color":Color("e99287")},
		{"key":"high_temp.collector_auxiliary_electric_mw","label":"槽式辅机","color":Color("f2bf83")},
		{"key":"high_temp.oil_auxiliary_electric_mw","label":"油水换热泵","color":Color("e99287")},
		{"key":"solar.auxiliary_electric_mw","label":"集热辅机","color":Color("f4d482")},
		{"key": "fuel.auxiliary_electric_mw", "label": "燃料辅机", "color": Color("aaadef")},
		{"key": "export_mw", "label": "外送", "color": Color("82d6aa")},
		{"key": "unserved_mw", "label": "缺供", "color": Color("ff9790")}
	])
	body.add_child(_power_chart)
	_power_chart.step_selected.connect(_select_step)
	_soc_chart = Chart.new()
	_soc_chart.custom_minimum_size.y = 155
	_soc_chart.configure("电池库存 · 时段末值", "%", [{"key": "soc", "label": "电池 SOC", "color": Color("69d1bd"), "multiplier": 100.0}], 100.0)
	body.add_child(_soc_chart)
	_soc_chart.step_selected.connect(_select_step)
	_selection = _label("点击曲线查看对应时段；详细 MW、MWh 见“逐时详情”。", 13, MUTED)
	_selection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_selection)

func _build_thermal_chart_tab() -> void:
	_thermal_tab_index = _tabs.get_tab_count()
	var body := _scroll_tab("供热曲线")
	var note := _label("热需求为常量，暂不支持热需求 CSV 导入。固定温区：主侧90/60°C → 次侧70/40°C；热储 SOC 是等效库存比例，不是水温。供热权重为教学服务权重，非价格。", 13, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	_thermal_chart = Chart.new()
	_thermal_chart.custom_minimum_size.y = 250
	_thermal_chart.configure("热功率 · 独立热账本", "MWth", [
		{"key": "thermal.demand_mwth", "label": "热需求", "color": Color("edf3f6")},
		{"key": "thermal.served_mwth", "label": "实供热", "color": Color("f2a978")},
		{"key": "baseline_thermal.served_mwth", "label": "基线实供热", "color": Color("b5c1cb")},
		{"key": "thermal.unserved_mwth", "label": "缺热", "color": Color("ff9790")},
		{"key": "thermal.boiler_heat_mwth", "label": "电锅炉", "color": Color("efbc68")},
		{"key":"rankine.oil_input_mwth","label":"循环油热输入","color":Color("deb893")},
		{"key":"rankine.condenser_rejection_mwth","label":"冷凝器环境排热","color":Color("8ab3e5")},
		{"key":"tower.available_mwth","label":"塔可用热","color":Color("f2bf83")},
		{"key":"tower.useful_mwth","label":"塔有用热","color":Color("f9a17f")},
		{"key":"tower.discharge_mwth","label":"盐储放热","color":Color("c3a0e4")},
		{"key":"high_temp.available_mwth","label":"槽式可用","color":Color("e5c486")},
		{"key":"high_temp.useful_mwth","label":"槽式有用","color":Color("e4a47b")},
		{"key":"high_temp.curtailed_mwth","label":"槽式弃热","color":Color("b9a995")},
		{"key":"solar.available_mwth","label":"太阳能可用","color":Color("f5d788")},
		{"key":"solar.useful_mwth","label":"太阳能有用","color":Color("f5b574")},
		{"key":"solar.curtailed_mwth","label":"弃热","color":Color("c4b69b")},
		{"key": "fuel.heat_output_mwth", "label": "燃料锅炉", "color": Color("c7bc9b")},
		{"key": "thermal.charge_mwth", "label": "充热", "color": Color("ba9aef")},
		{"key": "thermal.discharge_mwth", "label": "放热", "color": Color("72b9ec")}
	])
	body.add_child(_thermal_chart)
	_thermal_chart.step_selected.connect(_select_step)
	_thermal_soc_chart = Chart.new()
	_thermal_soc_chart.custom_minimum_size.y = 170
	_thermal_soc_chart.configure("热储 SOC · 时段末值", "%", [
		{"key": "thermal.soc", "label": "热储 SOC", "color": Color("f2a978"), "multiplier": 100.0},
		{"key": "baseline_thermal.soc", "label": "基线热储 SOC", "color": Color("b5c1cb"), "multiplier": 100.0}
	], 100.0)
	body.add_child(_thermal_soc_chart)
	_thermal_soc_chart.step_selected.connect(_select_step)
	_thermal_energy_chart = Chart.new()
	_thermal_energy_chart.custom_minimum_size.y = 180
	_thermal_energy_chart.configure("热储库存 · 时段末值", "MWhth", [
		{"key":"tower.energy_mwhth","label":"熔盐库存","color":Color("f9a17f")},
		{"key": "thermal.energy_mwhth", "label": "GLPK 热库存", "color": Color("f2a978")},
		{"key": "baseline_thermal.energy_mwhth", "label": "基线热库存", "color": Color("b5c1cb")}
	])
	body.add_child(_thermal_energy_chart)
	_thermal_energy_chart.step_selected.connect(_select_step)

func _has_thermal_data(steps: Array) -> bool:
	for step_data in steps:
		if step_data is Dictionary and step_data.get("thermal") is Dictionary:
			# Schema 2 can include a zero-valued thermal ledger for an all-electric
			# fleet. Do not invent thermal devices or show heat comparisons then.
			var devices: Variant = step_data.get("devices", {})
			if devices is Dictionary and not devices.is_empty():
				for device in devices.values():
					if device is Dictionary and device.get("kind", "") in ["solar_tower_receiver","molten_salt_store","salt_steam_generator","electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "high_temp_store", "oil_water_exchanger", "thermal_store", "heat_exchanger", "heat_demand","steam_generator","steam_turbine","steam_condenser","feedwater_pump"]:
						return true
			else:
				return true
	return false

func _thermal_plot_steps() -> Array:
	var rows := _steps.duplicate(true)
	var reference: Variant = _baseline.get("steps", [])
	if _validate_steps(reference).is_empty() and _same_intervals(reference, rows):
		for index in range(rows.size()):
			if reference[index].get("thermal") is Dictionary:
				rows[index].baseline_thermal = reference[index].thermal.duplicate(true)
	return rows

func _build_comparison_tab() -> void:
	var body := _scroll_tab("基线比较")
	body.add_child(_label("同一预测与初始库存下的分账比较", 18))
	_comparison_note = _label("求解后显示固定优先级策略与 GLPK 的结果。", 13, MUTED)
	_comparison_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_comparison_note)
	_comparison = GridContainer.new()
	_comparison.columns = 4
	_comparison.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_comparison.add_theme_constant_override("h_separation", 12)
	_comparison.add_theme_constant_override("v_separation", 3)
	body.add_child(_comparison)
	var note := _label("电量 MWh = Σ（MW × h）；热量 MWhth = Σ（MWth × h）。变化 = GLPK − 基线。自损已经是时段能量，不重复乘时长。缺供、损耗须连同实供与期末库存比较；电库存和热库存不能合并。充放电按 AC 端计算。", 13, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)

func _build_detail_tab() -> void:
	var body := _scroll_tab("逐时详情")
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 8)
	body.add_child(navigation)
	_previous = _button("上一时段", func(): _select_step(_selected - 1))
	navigation.add_child(_previous)
	_step_choice = OptionButton.new()
	_step_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_choice.item_selected.connect(_select_step)
	navigation.add_child(_step_choice)
	_next = _button("下一时段", func(): _select_step(_selected + 1))
	navigation.add_child(_next)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = false
	_detail.add_theme_color_override("default_color", INK)
	_detail.add_theme_color_override("selection_color", Color("315c66"))
	_detail.add_theme_font_size_override("normal_font_size", 14)
	_detail.add_theme_constant_override("line_separation", 5)
	_detail.add_theme_stylebox_override("normal", _style(Color("0c151e"), BORDER, 7, 12))
	_detail.selection_enabled = true
	_detail.fit_content = true
	_detail.scroll_active = false
	_detail.custom_minimum_size.y = 270
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_detail)

func _scroll_tab(label_text: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = label_text
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	scroll.add_child(margin)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)
	return body

func _request_solve() -> void:
	if _busy:
		return
	var options := get_options()
	if options.step_minutes > options.horizon_hours * 60.0:
		_error.text = "步长不能大于整个预测时长。"
		_error.show()
		return
	if ceili(options.horizon_hours * 60.0 / options.step_minutes) > 336:
		_error.text = "最多 336 个时段，请增大步长或缩短预测时长。"
		_error.show()
		return
	set_busy(true)
	set_status("正在准备独立快照并求解；可随时取消。")
	solve_requested.emit(options)

func _request_cancel() -> void:
	if not _busy:
		return
	set_busy(false)
	_clear_result("已取消；没有应用任何结果")
	_status.text = "任务已取消；实时场景不受影响。"
	cancel_requested.emit()

func _close() -> void:
	if _busy:
		_request_cancel()
	hide()

func _options_changed() -> void:
	if not _updating and not _steps.is_empty():
		mark_stale()

func _commit_editors() -> void:
	for editor in _editors:
		if editor is SpinBox and editor.editable:
			editor.apply()

func _clear_result(message: String) -> void:
	_result.clear()
	_baseline.clear()
	_steps.clear()
	_selected = -1
	_power_chart.clear(message)
	_soc_chart.clear(message)
	_thermal_chart.clear(message)
	_thermal_soc_chart.clear(message)
	_thermal_energy_chart.clear(message)
	_selection.text = message
	_step_choice.clear()
	_step_choice.add_item("无时段")
	_step_choice.disabled = true
	_previous.disabled = true
	_next.disabled = true
	_detail.text = message
	for child in _comparison.get_children():
		_comparison.remove_child(child)
		child.queue_free()
	_comparison_note.text = message
	if is_instance_valid(_material_summary):_material_summary.text=message

func _select_step(index: int) -> void:
	if _steps.is_empty():
		return
	_selected = clampi(index, 0, _steps.size() - 1)
	_power_chart.set_selected(_selected)
	_soc_chart.set_selected(_selected)
	_thermal_chart.set_selected(_selected)
	_thermal_soc_chart.set_selected(_selected)
	_thermal_energy_chart.set_selected(_selected)
	_step_choice.select(_selected)
	_previous.disabled = _selected == 0
	_next.disabled = _selected == _steps.size() - 1
	var step_data: Dictionary = _steps[_selected]
	var start_h := float(step_data.time_s) / 3600.0
	var dt := float(step_data.dt_h)
	var time_text := "第 %d / %d 时段 · t = %s–%s h · Δt = %s h" % [_selected + 1, _steps.size(), _num(start_h), _num(start_h + dt), _num(dt)]
	_selection.text = time_text + "\n供电 %s MW · 缺电 %s MW · 电池 %s MWh · SOC %s" % [_value(step_data, "served_mw"), _value(step_data, "unserved_mw"), _value(step_data, "energy_mwh"), _soc_text(step_data.get("soc"))]
	var lines: Array[String] = [time_text, "功率是本时段保持值；电量为功率 × Δt。风、光为可用预测。", ""]
	for spec in [["wind_mw", "风电可用"], ["pv_mw", "光伏可用"], ["available_mw", "总可用发电"], ["demand_mw", "负荷需求"], ["served_mw", "负荷实供"], ["unserved_mw", "未供电"], ["charge_mw", "储能 AC 充电"], ["discharge_mw", "储能 AC 放电"], ["export_mw", "外送"], ["curtailed_mw", "弃电"], ["loss_mw", "网络损耗"]]:
		var amount: Variant = float(step_data[spec[0]]) * dt if _valid_number(step_data.get(spec[0])) else null
		lines.append("%s：%s MW  ·  %s MWh" % [spec[1], _value(step_data, spec[0]), _display(amount)])
	lines.append("\n电池时段末库存：%s MWh  ·  SOC：%s" % [_value(step_data, "energy_mwh"), _soc_text(step_data.get("soc"))])
	_append_thermal(lines, step_data, dt)
	_append_fuel(lines, step_data, dt)
	_append_solar(lines,step_data,dt)
	_append_high_temp(lines,step_data,dt)
	_append_tower(lines,step_data,dt)
	_append_rankine(lines,step_data,dt)
	_append_material(lines,step_data,dt)
	_append_devices(lines, step_data, dt)
	_detail.text = "\n".join(lines)

func _append_thermal(lines: Array[String], step_data: Dictionary, dt: float) -> void:
	if not _has_thermal_data([step_data]):
		return
	var heat: Dictionary = step_data.thermal
	_selection.text += "\n供热 %s MWth · 缺热 %s MWth · 热储 %s MWhth · SOC %s" % [_value(heat, "served_mwth"), _value(heat, "unserved_mwth"), _value(heat, "energy_mwhth"), _soc_text(heat.get("soc"))]
	lines.append("\n电热转换（锅炉为内生耗电，不计入外生电需求）")
	for spec in [["boiler_electric_mw", "锅炉电输入"], ["boiler_conversion_loss_mw", "锅炉转换损失"]]:
		var amount: Variant = float(step_data[spec[0]]) * dt if _valid_number(step_data.get(spec[0])) else null
		lines.append("%s：%s MW  ·  %s MWh" % [spec[1], _value(step_data, spec[0]), _display(amount)])
	lines.append("\n独立热账本（热功率 × Δt = 热量）")
	for spec in [["demand_mwth", "热需求"], ["served_mwth", "热实供"], ["unserved_mwth", "缺热"], ["boiler_heat_mwth", "电锅炉出热"], ["charge_mwth", "储热充入"], ["discharge_mwth", "储热放出"], ["network_loss_mwth", "热网损失"], ["exchanger_loss_mwth", "换热损失"], ["storage_conversion_loss_mwth", "储热转换损失"]]:
		var amount: Variant = float(heat[spec[0]]) * dt if _valid_number(heat.get(spec[0])) else null
		lines.append("%s：%s MWth  ·  %s MWhth" % [spec[1], _value(heat, spec[0]), _display(amount)])
	lines.append("热储自损：%s MWhth（本时段能量，不再次乘时长）" % _value(heat, "self_discharge_mwhth"))
	lines.append("热储时段末库存：%s MWhth  ·  SOC：%s" % [_value(heat, "energy_mwhth"), _soc_text(heat.get("soc"))])
	var reference: Variant = _baseline.get("steps", [])
	if _validate_steps(reference).is_empty() and _same_intervals(reference, _steps) and reference[_selected].get("thermal") is Dictionary:
		var baseline_heat: Dictionary = reference[_selected].thermal
		lines.append("同一时段基线：供热 %s MWth · 缺热 %s MWth · 热库存 %s MWhth · SOC %s" % [_value(baseline_heat, "served_mwth"), _value(baseline_heat, "unserved_mwth"), _value(baseline_heat, "energy_mwhth"), _soc_text(baseline_heat.get("soc"))])

func _has_fuel_data(steps: Array) -> bool:
	for row in steps:
		if not row is Dictionary: continue
		var records: Variant = row.get("devices", {})
		if records is Dictionary: records = records.values()
		if not records is Array: continue
		for device in records:
			if device is Dictionary and device.get("kind") == "fuel_boiler": return true
	return false

func _append_fuel(lines: Array[String], step_data: Dictionary, dt: float) -> void:
	if not _has_fuel_data([step_data]): return
	if not step_data.get("fuel") is Dictionary:
		lines.append("\n燃料账本缺失，不能将燃料视为免费热源。")
		return
	var fuel: Dictionary = step_data.fuel
	_selection.text += "\n燃料 %s MW LHV · 辅机 %s MW · 教学费用 %s CNY/h" % [_value(fuel, "input_mw"), _value(fuel, "auxiliary_electric_mw"), _value(fuel, "cost_per_h")]
	lines.append("\n独立燃料账本（低位热值 LHV；价格为可配置教学假设，非市场报价）")
	for spec in [["input_mw", "燃料输入", "MW LHV", "MWh LHV"], ["heat_output_mwth", "燃料锅炉出热", "MWth", "MWhth"], ["conversion_loss_mw", "燃料转换损失", "MW", "MWh"], ["auxiliary_electric_mw", "辅机耗电", "MW", "MWh"], ["auxiliary_electric_loss_mw", "辅机散热", "MW", "MWh"], ["volume_nm3_per_h", "天然气用量", "Nm³/h", "Nm³"], ["cost_per_h", "教学燃料费用", "CNY/h", "CNY"]]:
		var amount: Variant = float(fuel[spec[0]]) * dt if _valid_number(fuel.get(spec[0])) else null
		lines.append("%s：%s %s  ·  %s %s" % [spec[1], _value(fuel, spec[0]), spec[2], _display(amount), spec[3]])
	lines.append("燃料输入 = 有用出热 + 燃料转换损失；辅机耗电另行散失，不加到有用热量。")

func _append_devices(lines: Array[String], step_data: Dictionary, dt: float) -> void:
	var devices: Variant = step_data.get("devices", step_data.get("per_device", step_data.get("by_device", {})))
	if not devices is Dictionary and not devices is Array:
		return
	if devices.is_empty():
		return
	lines.append("\n设备分项（仅显示求解器返回字段）")
	var records: Array = []
	if devices is Dictionary:
		for id in devices:
			if devices[id] is Dictionary:
				var record: Dictionary = devices[id].duplicate(true)
				record["id"] = str(id)
				records.append(record)
	else:
		records = devices
	for device in records:
		if not device is Dictionary:
			continue
		device = device.duplicate(true)
		if device.get("kind") in MaterialCatalog.KINDS:
			_append_material_device(lines,device,dt)
			continue
		if device.get("kind") == "electric_boiler":
			device.electric_input_mw = device.get("electric_input_mw", device.get("boiler_electric_mw", device.get("input_mw")))
			device.heat_output_mwth = device.get("heat_output_mwth", device.get("boiler_heat_mwth", device.get("output_mwth")))
			device.conversion_loss_mw = device.get("conversion_loss_mw", device.get("boiler_conversion_loss_mw"))
		var parts: Array[String] = []
		if device.get("kind") in ["steam_generator","steam_turbine","steam_condenser","feedwater_pump"]:
			parts.append("闭式蒸汽循环 · 流量 %s kg/s"%_value(device,"mass_flow_kg_s"))
			for spec in [["salt_input_mwth","盐热输入","MWth","MWhth"],["oil_input_mwth","油热输入","MWth"],["steam_heat_mwth","蒸汽增焓","MWth"],["gross_electric_mw","毛发电","MW"],["condenser_rejection_mwth","环境排热","MWth"],["auxiliary_electric_mw","辅机电","MW"],["pump_hydraulic_mw","泵水力功","MW"],["pump_motor_loss_mw","泵电机损失","MW"]]:
				if _valid_number(device.get(spec[0])):parts.append("%s %s %s"%[spec[1],_value(device,spec[0]),spec[2]])
			if device.has("status_reason"):parts.append(str(device.status_reason))
		if device.get("kind") in ["solar_thermal","parabolic_trough"]:
			parts.append("太阳能可用 %s / 有用 %s / 弃热 %s MWth；辅机 %s MW"%[_value(device,"available_mwth"),_value(device,"heat_output_mwth"),_value(device,"curtailed_mwth"),_value(device,"auxiliary_electric_mw")])
		if device.get("kind") == "fuel_boiler":
			parts.append("燃料输入 %s MW LHV / %s MWh LHV" % [_value(device, "fuel_input_mw"), _display(float(device.fuel_input_mw) * dt if _valid_number(device.get("fuel_input_mw")) else null)])
			parts.append("辅机 %s MW；散热 %s MW" % [_value(device, "auxiliary_electric_mw"), _value(device, "auxiliary_electric_loss_mw")])
			parts.append("天然气 %s Nm³/h；教学费用 %s CNY/h" % [_value(device, "fuel_volume_nm3_per_h"), _value(device, "fuel_cost_per_h")])
		for spec in [["available_mw", "可用"], ["demand_mw", "需求"], ["served_mw", "实供"], ["unserved_mw", "缺供"], ["charge_mw", "充电"], ["discharge_mw", "放电"], ["export_mw", "外送"], ["curtailed_mw", "弃电"], ["loss_mw", "网损"]]:
			if device.get("kind") in ["solar_tower_receiver","molten_salt_store","salt_steam_generator","electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "high_temp_store", "oil_water_exchanger", "thermal_store", "heat_exchanger", "heat_demand","steam_generator","steam_turbine","steam_condenser","feedwater_pump"]:
				continue
			if _valid_number(device.get(spec[0])):
				parts.append("%s %s MW / %s MWh" % [spec[1], _value(device, spec[0]), _num(float(device[spec[0]]) * dt)])
		if _valid_number(device.get("energy_mwh")):
			parts.append("电库存 %s MWh" % _value(device, "energy_mwh"))
		for spec in [["electric_input_mw", "锅炉电输入"], ["conversion_loss_mw", "锅炉转换损失"]]:
			if _valid_number(device.get(spec[0])):
				parts.append("%s %s MW / %s MWh" % [spec[1], _value(device, spec[0]), _num(float(device[spec[0]]) * dt)])
		for spec in [["heat_output_mwth", "锅炉出热"], ["input_mwth", "热输入"], ["output_mwth", "热输出"], ["demand_mwth", "热需求"], ["served_mwth", "热实供"], ["unserved_mwth", "缺热"], ["charge_mwth", "充热"], ["discharge_mwth", "放热"], ["loss_mwth", "热损失"], ["storage_conversion_loss_mwth", "储热转换损失"]]:
			if device.get("kind") in ["electric_boiler", "fuel_boiler"] and spec[0] == "input_mwth":
				continue
			if device.get("kind") in ["thermal_store", "high_temp_store","molten_salt_store"] and spec[0] in ["input_mwth", "output_mwth"]:
				continue
			if device.get("kind") == "heat_demand" and spec[0] == "output_mwth":
				continue
			if _valid_number(device.get(spec[0])) and not (device.get("kind") in ["electric_boiler", "fuel_boiler"] and spec[0] == "output_mwth" and device.has("heat_output_mwth")):
				parts.append("%s %s MWth / %s MWhth" % [spec[1], _value(device, spec[0]), _num(float(device[spec[0]]) * dt)])
		if _valid_number(device.get("energy_mwhth")):
			parts.append("热库存 %s → %s MWhth" % [_value(device, "energy_before_mwhth"), _value(device, "energy_mwhth")])
		if _valid_number(device.get("self_discharge_mwhth")):
			parts.append("热储自损 %s MWhth" % _value(device, "self_discharge_mwhth"))
		if device.get("kind") in ["parabolic_trough","high_temp_store"]:parts.append("Therminol 66 · 300/200°C；预热库存基线200°C")
		if device.get("kind")=="oil_water_exchanger":parts.append("油300/200 → 水90/60°C；泵电 %s MW"%_value(device,"auxiliary_electric_mw"))
		if device.get("kind") == "heat_exchanger":
			parts.append("90/60 → 70/40°C")
		if device.has("mode"):
			var names := {"charge": "充入", "charging": "充入", "discharge": "放出", "discharging": "放出", "idle": "闲置"}
			parts.append("模式 " + str(names.get(str(device.mode), device.mode)))
		if _valid_number(device.get("soc")):
			parts.append("SOC %s" % _soc_text(device.soc))
		var kind_names := {"solar_tower_receiver":"塔接收器","molten_salt_store":"熔盐储热","salt_steam_generator":"熔盐蒸汽发生器","steam_generator":"蒸汽发生器","steam_turbine":"汽轮发电机","steam_condenser":"蒸汽冷凝器","feedwater_pump":"给水泵","electric_boiler": "电热水锅炉", "fuel_boiler": "燃料热水锅炉", "parabolic_trough":"槽式聚光集热器", "high_temp_store":"高温油储热", "oil_water_exchanger":"油水换热器", "solar_thermal":"太阳能集热器", "thermal_store": "热储", "heat_exchanger": "换热器", "heat_demand": "热需求"}
		var name := str(device.get("name", str(kind_names.get(device.get("kind", ""), "设备")) + " " + str(device.get("id", ""))))
		lines.append("%s：%s" % [name, "；".join(parts) if not parts.is_empty() else "无可显示数值"])

func _build_comparison() -> void:
	for child in _comparison.get_children():
		_comparison.remove_child(child)
		child.queue_free()
	var baseline_steps: Variant = _baseline.get("steps", [])
	var comparable := _validate_steps(baseline_steps).is_empty() and _same_intervals(baseline_steps, _steps)
	_comparison_note.text = "单位 MWh · 变化 = GLPK − 固定优先级基线" if comparable else "未提供同一时段的有效基线；不显示虚构比较。GLPK 电量仍按返回时段积分。"
	for heading in ["电指标 / MWh", "固定策略基线", "GLPK", "变化"]:
		_add_metric_cell(heading, true)
	for metric in METRICS:
		var optimized: Variant = _integral(_steps, metric[0])
		var reference: Variant = _integral(baseline_steps, metric[0]) if comparable else null
		var delta: Variant = float(optimized) - float(reference) if optimized != null and reference != null else null
		_add_metric_cell(metric[1])
		_add_metric_cell(_display(reference))
		_add_metric_cell(_display(optimized))
		_add_metric_cell(_display(delta, true))
	var end_energy: Variant = _steps[-1].get("energy_mwh")
	var base_energy: Variant = baseline_steps[-1].get("energy_mwh") if comparable else null
	var energy_delta: Variant = float(end_energy) - float(base_energy) if _valid_number(end_energy) and _valid_number(base_energy) else null
	_add_metric_cell("期末储能库存")
	_add_metric_cell(_display(base_energy))
	_add_metric_cell(_display(end_energy))
	_add_metric_cell(_display(energy_delta, true))
	if _has_thermal_data(_steps):
		_build_thermal_comparison(baseline_steps, comparable)
	if _has_fuel_data(_steps):
		_build_fuel_comparison(baseline_steps, comparable)
	if _has_material_data(_steps):_build_material_comparison(baseline_steps,comparable)
	if _steps[0].get("solar") is Dictionary:
		for spec in [["incident_mw","太阳能入射 / MWh"],["optical_rejection_mw","光学未捕获 / MWh"],["thermal_loss_mw","集热散热 / MWh"],["available_mwth","可用集热 / MWhth"],["useful_mwth","有用集热 / MWhth"],["curtailed_mwth","弃热 / MWhth"],["auxiliary_electric_mw","集热辅机 / MWh"]]:
			_comparison_row(spec[1],_solar_total(_steps,spec[0]),_solar_total(baseline_steps,spec[0]) if comparable else null)

	if _steps[0].get("high_temp") is Dictionary:
		for spec in [["incident_mw","槽式入射 / MWh"],["useful_mwth","槽式有用热 / MWhth"],["curtailed_mwth","槽式弃热 / MWhth"],["collector_auxiliary_electric_mw","槽式辅机 / MWh"],["oil_auxiliary_electric_mw","油水泵 / MWh"]]:
			_comparison_row(spec[1],_hot_total(_steps,spec[0]),_hot_total(baseline_steps,spec[0]) if comparable else null)

	if _steps[0].get("rankine") is Dictionary:
		for spec in [["oil_input_mwth","蒸汽循环油热 / MWhth"],["gross_electric_mw","蒸汽毛发电 / MWh"],["auxiliary_electric_mw","循环辅机 / MWh"],["net_electric_mw","循环净发电 / MWh"],["condenser_rejection_mwth","冷凝器环境排热 / MWhth"]]:
			_comparison_row(spec[1],_rankine_total(_steps,spec[0]),_rankine_total(baseline_steps,spec[0]) if comparable else null)

func _build_thermal_comparison(reference: Array, comparable: bool) -> void:
	_comparison_note.text += "。电、热分账；热服务权重是教学权重，非价格。基线不强制电池或热储期末 SOC 下限。"
	for spec in [["boiler_electric_mw", "锅炉用电 / MWh"], ["boiler_conversion_loss_mw", "锅炉转换损失 / MWh"]]:
		_comparison_row(spec[1], _integral(_steps, spec[0]), _integral(reference, spec[0]) if comparable else null)
	for heading in ["热指标 / MWhth", "固定策略基线", "GLPK", "变化"]:
		_add_metric_cell(heading, true)
	for metric in THERMAL_METRICS:
		_comparison_row(metric[1] + " / MWhth", _thermal_total(_steps, metric[0]), _thermal_total(reference, metric[0]) if comparable else null)
	_comparison_row("热储自损 / MWhth", _thermal_total(_steps, "self_discharge_mwhth", false), _thermal_total(reference, "self_discharge_mwhth", false) if comparable else null)
	var optimized: Variant = _thermal_field(_steps[-1], "energy_mwhth")
	var baseline_value: Variant = _thermal_field(reference[-1], "energy_mwhth") if comparable else null
	_comparison_row("期末热储库存 / MWhth", optimized, baseline_value)

func _build_fuel_comparison(reference: Array, comparable: bool) -> void:
	_comparison_note.text += " 燃料计入独立消耗/费用；辅机耗电不计入有用热。费用为教学假设，非经济最优承诺。"
	for heading in ["燃料指标 / 各行单位", "固定策略基线", "GLPK", "变化"]:
		_add_metric_cell(heading, true)
	for spec in [["input_mw", "燃料输入 / MWh LHV"], ["volume_nm3_per_h", "天然气 / Nm³"], ["cost_per_h", "教学燃料费用 / CNY"], ["heat_output_mwth", "燃料锅炉出热 / MWhth"], ["conversion_loss_mw", "燃料转换损失 / MWh"], ["auxiliary_electric_mw", "辅机耗电 / MWh"], ["auxiliary_electric_loss_mw", "辅机散热 / MWh"]]:
		_comparison_row(spec[1], _fuel_total(_steps, spec[0]), _fuel_total(reference, spec[0]) if comparable else null)

func _fuel_total(steps: Array, key: String) -> Variant:
	var total := 0.0
	for row in steps:
		if not row.get("fuel") is Dictionary or not _valid_number(row.fuel.get(key)) or not _valid_number(row.get("dt_h")): return null
		total += float(row.fuel[key]) * float(row.dt_h)
	return total

func _comparison_row(label_text: String, optimized: Variant, reference: Variant) -> void:
	var delta: Variant = float(optimized) - float(reference) if _valid_number(optimized) and _valid_number(reference) else null
	_add_metric_cell(label_text)
	_add_metric_cell(_display(reference))
	_add_metric_cell(_display(optimized))
	_add_metric_cell(_display(delta, true))

func _thermal_field(step_data: Dictionary, key: String) -> Variant:
	return step_data.thermal.get(key) if step_data.get("thermal") is Dictionary else null

func _thermal_total(steps: Array, key: String, integrate_power: bool = true) -> Variant:
	var total := 0.0
	for step_data in steps:
		var value: Variant = _thermal_field(step_data, key)
		if not _valid_number(value) or not _valid_number(step_data.get("dt_h")):
			return null
		total += float(value) * (float(step_data.dt_h) if integrate_power else 1.0)
	return total

func _add_metric_cell(text: String, heading: bool = false) -> void:
	var index := _comparison.get_child_count()
	var cell := _label(text, 14, ACCENT if heading else (MUTED if text == "—" else INK))
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.custom_minimum_size.y = 30
	cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if index % 4 != 0:
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var fill := Color("1c2d3a") if heading else (Color("101c26") if int(index / 4) % 2 == 0 else PAPER)
	cell.add_theme_stylebox_override("normal", _style(fill, fill, 3, 4, 0))
	_comparison.add_child(cell)

func _same_intervals(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if absf(float(left[index].time_s) - float(right[index].time_s)) > 0.001 or absf(float(left[index].dt_h) - float(right[index].dt_h)) > 0.0000001:
			return false
	return true

func _integral(steps: Array, key: String) -> Variant:
	var total := 0.0
	for step_data in steps:
		if not _valid_number(step_data.get(key)) or not _valid_number(step_data.get("dt_h")):
			return null
		total += float(step_data[key]) * float(step_data.dt_h)
	return total

func _validate_steps(steps: Variant) -> String:
	if not steps is Array or steps.is_empty():
		return "没有时段数据。"
	var previous_end := -INF
	for index in range(steps.size()):
		var step_data: Variant = steps[index]
		if not step_data is Dictionary:
			return "第 %d 步格式无效。" % (index + 1)
		if not _valid_number(step_data.get("time_s")) or not _valid_number(step_data.get("dt_h")) or float(step_data.dt_h) <= 0:
			return "第 %d 步缺少有效时间或时长。" % (index + 1)
		if float(step_data.time_s) < previous_end - 0.001:
			return "第 %d 步与前一时段重叠或倒序。" % (index + 1)
		previous_end = float(step_data.time_s) + float(step_data.dt_h) * 3600.0
	return ""

func _value(data: Dictionary, key: String) -> String:
	return _display(data.get(key))

func _display(value: Variant, signed: bool = false) -> String:
	if not _valid_number(value):
		return "—"
	return ("+" if signed and float(value) > 0.0000001 else "") + _num(float(value))

func _num(value: float) -> String:
	return "%.3f" % (0.0 if absf(value) < 0.0000005 else value)

func _soc_text(value: Variant) -> String:
	return "%.1f%%" % (float(value) * 100.0) if _valid_number(value) else "—"

func _valid_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _label(text: String, font_size: int = 15, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.pressed.connect(callback)
	return button

func _add_number(parent: Control, text: String, minimum: float, maximum: float, increment: float, initial: float) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	row.add_child(_label(text, 13, MUTED))
	var editor := SpinBox.new()
	editor.min_value = minimum
	editor.max_value = maximum
	editor.step = increment
	editor.value = initial
	editor.custom_minimum_size = Vector2(105, 34)
	row.add_child(editor)
	_editors.append(editor)
	editor.value_changed.connect(func(_value): _options_changed())
	return editor

func _make_theme() -> Theme:
	var result := Theme.new()
	result.default_font = load("res://assets/InterfaceCJK.ttc")
	result.default_font_size = 14
	for type in ["Label", "Button", "OptionButton", "CheckBox", "LineEdit", "RichTextLabel", "PopupMenu", "TabContainer"]:
		result.set_color("font_color", type, INK)
		result.set_color("font_disabled_color", type, Color("788e9d"))
	for type in ["Button", "OptionButton"]:
		for state in ["font_hover_color", "font_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
			result.set_color(state, type, INK)
		result.set_stylebox("normal", type, _style(PAPER, BORDER, 6, 8))
		result.set_stylebox("hover", type, _style(Color("263e4d"), Color("69d1bd"), 6, 8))
		result.set_stylebox("pressed", type, _style(Color("224a4c"), Color("69d1bd"), 6, 8))
		result.set_stylebox("disabled", type, _style(Color("101c26"), BORDER, 6, 8))
		result.set_stylebox("focus", type, _style(Color(0, 0, 0, 0), Color("69d1bd"), 6, 8, 2))
	result.set_stylebox("normal", "LineEdit", _style(PAPER, BORDER, 6, 7))
	result.set_stylebox("read_only", "LineEdit", _style(Color("101c26"), BORDER, 6, 7))
	result.set_stylebox("focus", "LineEdit", _style(Color(0, 0, 0, 0), Color("69d1bd"), 6, 7, 2))
	result.set_color("caret_color", "LineEdit", INK)
	result.set_color("selection_color", "LineEdit", Color("315c66"))
	result.set_color("font_uneditable_color", "LineEdit", MUTED)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_stylebox("panel", "TabContainer", _style(Color("14212b"), BORDER, 7, 0))
	result.set_stylebox("tab_selected", "TabContainer", _style(Color("14212b"), BORDER, 5, 10))
	result.set_stylebox("tab_unselected", "TabContainer", _style(Color("0c151e"), BORDER, 5, 10))
	result.set_color("font_selected_color", "TabContainer", INK)
	result.set_color("font_unselected_color", "TabContainer", MUTED)
	# TabContainer delegates tab drawing to TabBar in Godot 4.
	for type in ["TabContainer", "TabBar"]:
		result.set_stylebox("tab_selected", type, _style(Color("1c2d3a"), ACCENT, 5, 10))
		result.set_stylebox("tab_unselected", type, _style(Color("0c151e"), BORDER, 5, 10))
		result.set_stylebox("tab_hovered", type, _style(Color("263e4d"), BORDER, 5, 10))
		result.set_color("font_selected_color", type, ACCENT)
		result.set_color("font_unselected_color", type, MUTED)
		result.set_color("font_hovered_color", type, INK)
	for state in ["font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		result.set_color(state, "CheckBox", INK)
	result.set_stylebox("panel", "PopupMenu", _style(PAPER, BORDER, 6, 8))
	result.set_stylebox("hover", "PopupMenu", _style(Color("224a4c"), BORDER, 4, 6))
	result.set_color("font_hover_color", "PopupMenu", INK)
	for type in ["VScrollBar", "HScrollBar"]:
		result.set_stylebox("scroll", type, _style(Color("0c151e"), Color("0c151e"), 4, 4))
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			result.set_stylebox(state, type, _style(Color("486575"), Color("486575"), 4, 4))
	return result

func _style(fill: Color, border: Color, radius: int, padding: int, width: int = 1) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(width)
	result.set_corner_radius_all(radius)
	result.content_margin_left = padding
	result.content_margin_right = padding
	result.content_margin_top = padding
	result.content_margin_bottom = padding
	return result

func _append_solar(lines:Array[String],step_data:Dictionary,dt:float)->void:
	if not step_data.get("solar") is Dictionary:return
	var solar:Dictionary=step_data.solar
	lines.append("\n独立太阳能账本 · 吸热面积口径 · 固定面等效POA · 非DNI")
	for spec in [["incident_mw","入射","MW","MWh"],["optical_rejection_mw","光学未捕获","MW","MWh"],["thermal_loss_mw","实际散热","MW","MWh"],["available_mwth","可用热","MWth","MWhth"],["useful_mwth","有用热","MWth","MWhth"],["curtailed_mwth","弃热","MWth","MWhth"],["auxiliary_electric_mw","集热辅机电","MW","MWh"]]:
		var amount:Variant=float(solar[spec[0]])*dt if _valid_number(solar.get(spec[0])) else null
		lines.append("%s：%s %s · %s %s"%[spec[1],_value(solar,spec[0]),spec[2],_display(amount),spec[3]])
	lines.append("入射 = 光学未捕获 + 实际散热 + 有用 + 弃热；辅机用电独立，不作为有用热。")

func _solar_total(steps:Array,key:String)->Variant:
	var total:=0.0
	for row in steps:
		if not row.get("solar") is Dictionary or not _valid_number(row.solar.get(key)) or not _valid_number(row.get("dt_h")):return null
		total+=float(row.solar[key])*float(row.dt_h)
	return total

func _append_high_temp(lines:Array[String],step_data:Dictionary,dt:float)->void:
	if not step_data.get("high_temp") is Dictionary:return
	var hot:Dictionary=step_data.high_temp
	lines.append("\n独立高温油账本 · 开口面积 · DNI · Therminol 66 300/200°C")
	for spec in [["incident_mw","入射"],["optical_rejection_mw","光学未捕获"],["thermal_loss_mw","散热"],["available_mwth","可用热"],["useful_mwth","有用热"],["curtailed_mwth","弃热"],["collector_auxiliary_electric_mw","槽辅机电"],["oil_auxiliary_electric_mw","油水泵电"],["oil_water_output_mwth","90/60热水输出"],["exchanger_loss_mwth","油水换热损失"],["charge_mwth","高温充热"],["discharge_mwth","高温放热"],["storage_conversion_loss_mwth","高温储热转换损失"]]:
		var value:Variant=hot.get(spec[0])
		lines.append("%s：%s kW / %s kWh"%[spec[1],_display(float(value)*1000 if _valid_number(value) else null),_display(float(value)*dt*1000 if _valid_number(value) else null)])
	lines.append("库存 %s MWhth · 自损 %s MWhth · 守恒差 %s MWth；SOC0=200°C基线，非室温冷启动。"%[_value(hot,"energy_mwhth"),_value(hot,"self_discharge_mwhth"),_value(hot,"balance_error_mwth")])

func _hot_total(steps:Array,key:String)->Variant:
	var total:=0.0
	for row in steps:
		if not row.get("high_temp") is Dictionary or not _valid_number(row.high_temp.get(key)) or not _valid_number(row.get("dt_h")):return null
		total+=float(row.high_temp[key])*float(row.dt_h)
	return total

func _append_rankine(lines:Array[String],step_data:Dictionary,dt:float)->void:
	if not step_data.get("rankine") is Dictionary:return
	var cycle:Dictionary=step_data.rankine
	lines.append("\n闭式蒸汽循环 · 1MPa/280°C → 10kPa（已预热）")
	lines.append("循环质量流量 %s kg/s；外部电源保障辅机，不允许毛电自举启动。"%_value(cycle,"mass_flow_kg_s"))
	for spec in [["salt_input_mwth","盐热输入","MWth","MWhth"],["oil_input_mwth","油热输入","MWth","MWhth"],["steam_heat_mwth","蒸汽增焓","MWth","MWhth"],["gross_electric_mw","毛发电","MW","MWh"],["auxiliary_electric_mw","循环辅机","MW","MWh"],["net_electric_mw","净发电","MW","MWh"],["condenser_rejection_mwth","环境排热","MWth","MWhth"],["steam_generator_loss_mwth","发生器散失","MWth","MWhth"],["generator_loss_mw","发电机损失","MW","MWh"],["pump_hydraulic_mw","泵水力增焓","MW","MWh"],["pump_motor_loss_mw","泵电机损失","MW","MWh"]]:
		var amount:Variant=float(cycle[spec[0]])*dt if _valid_number(cycle.get(spec[0])) else null
		lines.append("%s：%s %s · %s %s"%[spec[1],_value(cycle,spec[0]),spec[2],_display(amount),spec[3]])
	lines.append("循环能量守恒差 %s MW"%_value(cycle,"balance_error_mw"))

func _rankine_total(steps:Array,key:String)->Variant:
	var total:=0.0
	for row in steps:
		if not row.get("rankine") is Dictionary or not _valid_number(row.rankine.get(key)) or not _valid_number(row.get("dt_h")):return null
		total+=float(row.rankine[key])*float(row.dt_h)
	return total

func _append_tower(lines:Array[String],step_data:Dictionary,dt:float)->void:
	if not step_data.get("tower") is Dictionary:return
	var salt:Dictionary=step_data.tower
	lines.append("\n独立塔式熔盐账本 · DNI · 565/290°C · 单接收器100镜")
	for spec in [["available_mwth","可用热"],["useful_mwth","有用热"],["curtailed_mwth","弃热"],["receiver_auxiliary_electric_mw","塔辅机电"],["store_auxiliary_electric_mw","盐罐泵电"],["rankine_salt_input_mwth","蒸汽盐热输入"],["charge_mwth","充热"],["discharge_mwth","放热"],["storage_conversion_loss_mwth","储热转换损失"]]:
		var value:Variant=salt.get(spec[0])
		lines.append("%s：%s kW / %s kWh"%[spec[1],_display(float(value)*1000 if _valid_number(value) else null),_display(float(value)*dt*1000 if _valid_number(value) else null)])
	lines.append("盐库存 %s MWhth · 自损 %s MWhth · 守恒差 %s MWth；SOC0=290°C基线。"%[_value(salt,"energy_mwhth"),_value(salt,"self_discharge_mwhth"),_value(salt,"balance_error_mwth")])

## IDs and kg targets are forecast-only. Never retain references to live devices.
func set_material_context(devices:Array)->void:
	_build_ui()
	var context:Array=[]
	for device in devices:
		if not device is Dictionary or not device.get("kind","") in MaterialCatalog.KINDS:continue
		var item:Dictionary={"id":int(device.get("id",-1)),"kind":device.kind}
		if device.kind in MaterialCatalog.HYDROGEN_STORE_KINDS or device.kind in MaterialCatalog.SYNTHESIS_KINDS:
			var params:Dictionary=MaterialCatalog.defaults(device.kind).merged(device.get("params",{}),true)
			item.capacity=MaterialCatalog.inventory_capacity(device.kind,params)
			item.stock=float(device.get("state",{}).get("material_inventory_kg",{}).get(MaterialCatalog.species(device.kind),params.get("initial_inventory_kg",0)))
		context.append(item)
	if context==_material_context:return
	var previous:=_material_options()
	var product_previous:=_product_options()
	if not _pending_material_targets.is_empty():previous=_pending_material_targets.duplicate(true)
	if not _pending_product_targets.is_empty():product_previous=_pending_product_targets.duplicate(true)
	_pending_material_targets.clear();_pending_product_targets.clear()
	_material_context=context.duplicate(true);_material_enabled=not context.is_empty()
	_product_enabled=context.any(func(item):return item.kind in MaterialCatalog.SYNTHESIS_KINDS)
	_product_section.visible=_product_enabled
	_tabs.set_tab_hidden(_material_tab_index,not _material_enabled)
	for controls in _material_controls.values()+_product_controls.values():_editors.erase(controls.enabled);_editors.erase(controls.amount)
	_material_controls.clear();_product_controls.clear()
	for parent in [_material_targets,_product_targets]:
		for child in parent.get_children():parent.remove_child(child);child.queue_free()
	for item in context:
		if item.kind in MaterialCatalog.HYDROGEN_STORE_KINDS:_add_inventory_target(item,_material_targets,_material_controls,_hydrogen_store_name(item.kind))
		elif item.kind in MaterialCatalog.SYNTHESIS_KINDS:_add_inventory_target(item,_product_targets,_product_controls,_product_store_name(item.kind))
	var was_updating:=_updating;_updating=true
	_apply_material_targets(previous);_apply_product_targets(product_previous)
	_updating=was_updating
	if not _steps.is_empty():mark_stale()

func _add_inventory_target(item:Dictionary,parent:VBoxContainer,controls_by_id:Dictionary,caption:String)->void:
	if item.id<0 or not _valid_number(item.get("capacity")) or item.capacity<=0 or not _valid_number(item.get("stock")):return
	var id:=str(item.id)
	if controls_by_id.has(id):return
	var card:=ReadoutCard.new();parent.add_child(card)
	var content:VBoxContainer=card.setup(caption+" #"+id)
	var note:=_label("当前库存 %s kg / 容量 %s kg"%[_num(item.stock),_num(item.capacity)],13,MUTED);note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;content.add_child(note)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);content.add_child(row)
	var enabled:=CheckBox.new();enabled.text="启用期末下限";enabled.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(enabled)
	var amount:=SpinBox.new();amount.min_value=0;amount.max_value=item.capacity;amount.step=0.001;amount.value=clampf(item.stock,0,item.capacity);amount.custom_minimum_size=Vector2(120,36);amount.alignment=HORIZONTAL_ALIGNMENT_RIGHT;amount.editable=false;row.add_child(amount)
	row.add_child(_label("kg",12,MUTED));_editors.append(enabled);_editors.append(amount)
	controls_by_id[id]={"enabled":enabled,"amount":amount}
	enabled.disabled=_busy
	enabled.toggled.connect(func(value):amount.editable=value and not _busy;_options_changed())
	amount.value_changed.connect(func(_value):_options_changed())

func _inventory_options(controls_by_id:Dictionary)->Dictionary:
	var targets:Dictionary={}
	for id in controls_by_id:
		var controls:Dictionary=controls_by_id[id]
		if controls.enabled.button_pressed:targets[id]=controls.amount.value
	return targets

func _material_options()->Dictionary:return _inventory_options(_material_controls)
func _product_options()->Dictionary:return _inventory_options(_product_controls)

func _hydrogen_store_name(kind:String)->String:
	return {"hydrogen_gas_store":"气态储氢站","hydrogen_liquid_store":"液氢储罐站","hydrogen_metal_hydride_store":"LaNi5 固态储氢站"}.get(kind,"储氢站")

func _product_store_name(kind:String)->String:
	return "合成氨 · NH3(g) 产品缓冲" if kind=="ammonia_synthesis_station" else "合成甲醇 · CH3OH(l) 产品缓冲"

func _apply_inventory_targets(targets:Dictionary,controls_by_id:Dictionary)->Array[String]:
	var invalidated:Array[String]=[]
	for raw_id in targets:
		var id:=str(raw_id)
		var value:Variant=targets[raw_id]
		if not raw_id is String or not controls_by_id.has(id) or not _valid_number(value) or float(value)<0.0 or float(value)>controls_by_id[id].amount.max_value:invalidated.append("#"+id)
	for id in controls_by_id:
		var controls:Dictionary=controls_by_id[id]
		var target:Variant=targets.get(id)
		var valid:bool=_valid_number(target) and float(target)>=0.0 and float(target)<=controls.amount.max_value
		controls.enabled.set_pressed_no_signal(valid)
		if valid:controls.amount.set_value_no_signal(float(target));controls.amount.get_line_edit().text=str(target)
		controls.amount.editable=valid and not _busy
	return invalidated

func _target_notice(note:Label,base:String,invalidated:Array[String])->void:
	note.text=base
	if not invalidated.is_empty():
		var warning:="目标已失效："+"、".join(invalidated)+"。设备已删除、容量改变或数值无效；已停用，未截断到新容量。请检查后重新设定。"
		note.text+="\n"+warning;_status.text=warning
	note.add_theme_color_override("font_color",AMBER if not invalidated.is_empty() else MUTED)

func _apply_material_targets(targets:Dictionary)->void:
	_material_invalidated_targets=_apply_inventory_targets(targets,_material_controls)
	_target_notice(_material_target_note,"只约束勾选的气态 / 液态 / LaNi5 储氢站；默认关闭。目标不修改实时库存，固定策略基线不强制此目标。" if not _material_controls.is_empty() else "当前没有已安装储氢站；没有期末氢目标。",_material_invalidated_targets)

func _apply_product_targets(targets:Dictionary)->void:
	_product_invalidated_targets=_apply_inventory_targets(targets,_product_controls)
	_target_notice(_product_target_note,"NH3(g) 与 CH3OH(l) 分别按设备ID设定kg下限，默认关闭。目标只约束隔离优化，不修改实时库存；实时/固定策略基线不保证期末目标。资源不足时求解应明确不可行。产品缓冲满则停产，无外售或自动清空。",_product_invalidated_targets)

func _build_material_tab()->void:
	_material_tab_index=_tabs.get_tab_count()
	var body:=_scroll_tab("物质与库存")
	body.add_child(_label("储氢站期末目标 · 可选",18))
	_material_target_note=_label("默认无期末目标；只影响隔离优化，不修改实时库存。",13,MUTED);_material_target_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(_material_target_note)
	_material_targets=VBoxContainer.new();_material_targets.add_theme_constant_override("separation",12);body.add_child(_material_targets)
	_product_section=VBoxContainer.new();_product_section.add_theme_constant_override("separation",10);_product_section.hide();body.add_child(_product_section)
	_product_section.add_child(_label("化工产品期末目标 · 可选",18))
	_product_target_note=_label("",13,MUTED);_product_target_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_product_section.add_child(_product_target_note)
	_product_targets=VBoxContainer.new();_product_targets.add_theme_constant_override("separation",12);_product_section.add_child(_product_targets)
	var card:=ReadoutCard.new();body.add_child(card);var content:VBoxContainer=card.setup("所选时段 · 物质账本")
	_material_summary=_label("尚无求解结果",14);_material_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;content.add_child(_material_summary)
	var note:=_label("流量 kg/s × 秒 = kg；电功率 MW × 小时 = MWh；排热 MWth × 小时 = MWhth。泄漏已是本时段 kg，不再次积分。库存为时段末 kg，不能按时长累计。完整设备与守恒分项见逐时详情。",12,MUTED);note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(note)

func _has_material_data(steps:Array)->bool:
	return steps.any(func(row):return row is Dictionary and row.get("material") is Dictionary and not row.material.is_empty())

func _material_total(steps:Array,key:String)->Variant:
	if steps.is_empty():return null
	# Stocks are snapshots; do not sum them. LHV inventory is not electric energy.
	if key in ["hydrogen_inventory_kg","water_inventory_kg","hydrogen_lhv_mwh","phase_enthalpy_mwh","nitrogen_inventory_kg","co2_inventory_kg","ammonia_inventory_kg","methanol_inventory_kg"]:
		if not steps[-1].get("material") is Dictionary:return null
		var last:Variant=steps[-1].material.get(key)
		return last if _valid_number(last) else null
	var total:=0.0
	for row in steps:
		if not row.get("material") is Dictionary or not _valid_number(row.material.get(key)) or not _valid_number(row.get("dt_h")):return null
		var multiplier:=1.0
		if key.ends_with("_kg_s"):multiplier=float(row.dt_h)*3600.0
		elif key.ends_with("_mw") or key.ends_with("_mwth"):multiplier=float(row.dt_h)
		total+=float(row.material[key])*multiplier
	return total

func _has_phase_material_row(row:Dictionary)->bool:
	var devices:Variant=row.get("devices",{})
	return devices is Dictionary and devices.values().any(func(device):return device is Dictionary and device.get("kind") in MaterialCatalog.PHASE_KINDS)

func _has_chemical_material_row(row:Dictionary)->bool:
	var devices:Variant=row.get("devices",{})
	return devices is Dictionary and devices.values().any(func(device):return device is Dictionary and device.get("kind") in MaterialCatalog.CHEMICAL_KINDS)

func _append_material(lines:Array[String],row:Dictionary,dt:float)->void:
	if not row.get("material") is Dictionary:
		_material_summary.text="当前时段未返回物质账本；不以零替代。";return
	var material:Dictionary=row.material
	var summary:Array[String]=["物质流量 / 时段总量（不是库存）"]
	for spec in MATERIAL_RATES:
		var amount:Variant=float(material[spec[0]])*dt*3600.0 if _valid_number(material.get(spec[0])) else null
		summary.append("%s：%s kg/s  ·  %s kg"%[spec[1],_material_value(material,spec[0]),ReadoutCard.number(float(amount)) if _valid_number(amount) else "—"])
	summary.append("\n时段末氢库存：%s kg"%_material_value(material,"hydrogen_inventory_kg"))
	summary.append("时段末水库存：%s kg"%_material_value(material,"water_inventory_kg"))
	summary.append("库存低位热值：%s MWh(LHV)（非电量）"%_material_value(material,"hydrogen_lhv_mwh"))
	summary.append("本时段泄漏：%s kg（不再乘时长）"%_material_value(material,"hydrogen_leaked_kg"))
	summary.append("泄漏低位热值：%s MWh(LHV)"%_material_value(material,"hydrogen_leak_lhv_mwh"))
	for spec in MATERIAL_POWERS:
		var amount:Variant=float(material[spec[0]])*dt if _valid_number(material.get(spec[0])) else null
		summary.append("%s：%s %s  ·  %s %s"%[spec[1],_material_value(material,spec[0]),spec[2],ReadoutCard.number(float(amount)) if _valid_number(amount) else "—",spec[3]])
	if _has_phase_material_row(row):
		for spec in PHASE_POWERS:
			var amount:Variant=float(material[spec[0]])*dt if _valid_number(material.get(spec[0])) else null
			summary.append("%s：%s %s  ·  %s %s"%[spec[1],_material_value(material,spec[0]),spec[2],ReadoutCard.number(float(amount)) if _valid_number(amount) else "—",spec[3]])
		summary.append("期末相态/结合焓：%s MWh；本时段变化：%s MWh（参考态账本，非可用电量/热库存）"%[_material_value(material,"phase_enthalpy_mwh"),_material_value(material,"phase_enthalpy_change_mwh")])
		var by_reference:Variant=material.get("inventory_by_reference_kg",{})
		if by_reference is Dictionary:
			for spec in [["H2_gas_25c","气态氢库存"],["H2_liquid_20k","液氢库存"],["H2_bound_lani5","LaNi5 结合氢库存"]]:summary.append("%s：%s kg"%[spec[1],_material_value(by_reference,spec[0])])
	if _has_chemical_material_row(row):
		summary.append("\n化工供料与产品 · 有限库存，无自动外售/清空")
		for spec in CHEMICAL_RATES:
			var amount:Variant=float(material[spec[0]])*dt*3600.0 if _valid_number(material.get(spec[0])) else null
			summary.append("%s：%s kg/s  ·  %s kg"%[spec[1],_material_value(material,spec[0]),ReadoutCard.number(float(amount)) if _valid_number(amount) else "—"])
		for spec in CHEMICAL_STOCKS:summary.append("时段末 %s：%s kg"%[spec[1],_material_value(material,spec[0])])
		var chemical_energy:Variant=float(material.chemical_electric_mw)*dt if _valid_number(material.get("chemical_electric_mw")) else null
		summary.append("化工用电：%s MW  ·  %s MWh"%[_material_value(material,"chemical_electric_mw"),ReadoutCard.number(float(chemical_energy)) if _valid_number(chemical_energy) else "—"])
		summary.append("化工排热已包含在环境排热中；化工排水是总排水子项，不重复累计。")
		for spec in [["carbon_element_error_kg","碳元素差"],["nitrogen_element_error_kg","氮元素差"]]:summary.append("%s：%s kg"%[spec[1],_material_value(material,spec[0])])
	for spec in [["mass_balance_error_kg","质量守恒差","kg"],["hydrogen_element_error_kg","氢元素差","kg"],["oxygen_element_error_kg","氧元素差","kg"],["enthalpy_balance_error_mw","参考态焓差","MW"]]:summary.append("%s：%s %s"%[spec[1],_material_value(material,spec[0]),spec[2]])
	lines.append("\n独立物质账本");lines.append_array(summary)
	_material_summary.text="\n".join(summary)
	_selection.text+="\n氢库存 %s kg · 制氢 %s kg/s · 本时段泄漏 %s kg"%[_material_value(material,"hydrogen_inventory_kg"),_material_value(material,"hydrogen_produced_kg_s"),_material_value(material,"hydrogen_leaked_kg")]

func _append_material_device(lines:Array[String],device:Dictionary,dt:float)->void:
	var names:Dictionary={"water_supply_boundary":"有限水源","electrolyzer_station":"电解制氢站","hydrogen_gas_store":"氢气库","hydrogen_liquid_store":"液氢储罐站","hydrogen_metal_hydride_store":"LaNi5 固态储氢站","fuel_cell_station":"燃料电池站","nitrogen_supply_boundary":"有限 N2(g) 氮源","co2_supply_boundary":"有限 CO2(g) 碳源","ammonia_synthesis_station":"合成氨 · NH3(g)","methanol_synthesis_station":"合成甲醇 · CH3OH(l)"}
	lines.append("\n%s #%s"%[names.get(device.get("kind",""),"物质设备"),str(device.get("id",""))])
	for spec in [["nitrogen_in_kg_s","N2(g) 进料"],["nitrogen_out_kg_s","N2(g) 出料"],["co2_in_kg_s","CO2(g) 进料"],["co2_out_kg_s","CO2(g) 出料"],["product_produced_kg_s","产品生成"],["water_in_kg_s","进水"],["water_out_kg_s","出水"],["hydrogen_in_kg_s","进氢"],["hydrogen_out_kg_s","出氢"],["oxygen_vented_kg_s","排氧"],["oxygen_from_air_kg_s","空气取氧"],["water_released_kg_s","排水"]]:
		if _valid_number(device.get(spec[0])):lines.append("%s：%s kg/s / %s kg"%[spec[1],_material_value(device,spec[0]),ReadoutCard.number(float(device[spec[0]])*dt*3600.0)])
	for spec in [["electric_input_mw","设备用电","MW","MWh"],["electric_output_mw","设备出电","MW","MWh"],["heat_rejected_mwth","环境排热","MWth","MWhth"],["environment_heat_in_mwth","环境吸热","MWth","MWhth"]]:
		if _valid_number(device.get(spec[0])):lines.append("%s：%s %s / %s %s"%[spec[1],_material_value(device,spec[0]),spec[2],ReadoutCard.number(float(device[spec[0]])*dt),spec[3]])
	if device.get("kind") in MaterialCatalog.INVENTORY_KINDS:
		lines.append("库存：%s → 泄漏后 %s → 时段末 %s kg；本时段泄漏 %s kg"%[_material_value(device,"inventory_before_kg"),_material_value(device,"inventory_after_leak_kg"),_material_value(device,"next_inventory_kg"),_material_value(device,"leaked_kg")])
	if device.get("kind") in MaterialCatalog.PHASE_KINDS:
		for spec in [["phase_enthalpy_mwh","期末相态/结合焓","MWh"],["phase_enthalpy_change_mwh","本时段相态/结合焓变化","MWh"],["host_dry_mass_kg","固定宿主干质量","kg"]]:
			if _valid_number(device.get(spec[0])):lines.append("%s：%s %s"%[spec[1],_material_value(device,spec[0]),spec[2]])
		lines.append("相态/结合焓是独立参考态账本，不是可用电量或额外热库存。")

func _build_material_comparison(reference:Array,comparable:bool)->void:
	_comparison_note.text+=" 物质流量按秒积分；泄漏kg直接相加，库存仅比较末值。基线不强制期末氢目标，也不强制期末化工产品目标。"
	for heading in ["物质指标 / 各行单位","固定策略基线","GLPK","变化"]:_add_metric_cell(heading,true)
	for spec in MATERIAL_RATES:_material_comparison_row(spec[1]+" / kg",_material_total(_steps,spec[0]),_material_total(reference,spec[0]) if comparable else null)
	for spec in MATERIAL_POWERS:_material_comparison_row(spec[1]+" / "+spec[3],_material_total(_steps,spec[0]),_material_total(reference,spec[0]) if comparable else null)
	if _steps.any(func(row):return row is Dictionary and _has_phase_material_row(row)):
		for spec in PHASE_POWERS:_material_comparison_row(spec[1]+" / "+spec[3],_material_total(_steps,spec[0]),_material_total(reference,spec[0]) if comparable else null)
		for spec in [["phase_enthalpy_mwh","期末相态/结合焓 / MWh（非电量）"],["phase_enthalpy_change_mwh","相态/结合焓变化 / MWh（非电量）"]]:_material_comparison_row(spec[1],_material_total(_steps,spec[0]),_material_total(reference,spec[0]) if comparable else null)
	if _steps.any(func(row):return row is Dictionary and _has_chemical_material_row(row)):
		for spec in CHEMICAL_RATES:_material_comparison_row(spec[1]+" / kg",_material_total(_steps,spec[0]),_material_total(reference,spec[0]) if comparable else null)
		_material_comparison_row("化工用电 / MWh",_material_total(_steps,"chemical_electric_mw"),_material_total(reference,"chemical_electric_mw") if comparable else null)
		for spec in CHEMICAL_STOCKS:_material_comparison_row("期末 "+spec[1]+" / kg",_material_total(_steps,spec[0]),_material_total(reference,spec[0]) if comparable else null)
	for spec in [["hydrogen_leaked_kg","氢泄漏 / kg"],["hydrogen_leak_lhv_mwh","泄漏低位热值 / MWh(LHV)"],["hydrogen_inventory_kg","期末氢库存 / kg"],["water_inventory_kg","期末水库存 / kg"],["hydrogen_lhv_mwh","期末氢低位热值 / MWh(LHV)"]]:_material_comparison_row(spec[1],_material_total(_steps,spec[0]),_material_total(reference,spec[0]) if comparable else null)

func _material_value(data:Dictionary,key:String)->String:
	return ReadoutCard.number(float(data[key])) if _valid_number(data.get(key)) else "—"

func _material_comparison_row(caption:String,optimized:Variant,reference:Variant)->void:
	var delta:Variant=float(optimized)-float(reference) if _valid_number(optimized) and _valid_number(reference) else null
	_add_metric_cell(caption)
	for value in [reference,optimized,delta]:
		_add_metric_cell(ReadoutCard.number(float(value)) if _valid_number(value) else "—")
		_comparison.get_child(_comparison.get_child_count()-1).tooltip_text=str(value) if _valid_number(value) else "没有有效物质账本，不以零替代。"
