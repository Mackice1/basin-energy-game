extends Window
## Read-only live view. Host remains the sole owner of devices, links and results.
## API: setup(host), open_device(id) -> bool, refresh(), close_device().
const Catalog = preload("res://scripts/device_catalog.gd")
const Visual = preload("res://scripts/equipment_visual.gd")
const Form = preload("res://scripts/parameter_form.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const NAMES := {"wind":"风机", "pv":"光伏", "station":"变电站", "load":"用电需求", "battery":"电池", "electric_boiler":"电热水锅炉", "thermal_store":"储热罐", "heat_exchanger":"隔离换热器", "heat_demand":"热需求", "fuel_boiler":"燃气热水锅炉", "solar_thermal":"太阳能集热器", "parabolic_trough":"槽式聚光集热器", "high_temp_store":"高温导热油储热", "oil_water_exchanger":"油水换热器", "steam_generator":"蒸汽发生器", "steam_turbine":"汽轮发电机", "steam_condenser":"蒸汽冷凝器", "feedwater_pump":"给水泵", "solar_tower_receiver":"塔式熔盐接收器", "molten_salt_store":"双罐熔盐储热", "salt_steam_generator":"熔盐蒸汽发生器"}
const LIMITS := {
 "wind":"未建模：叶片结构、尾流、机械载荷与电网暂态。外形不是可进入的机舱仿真。",
 "pv":"未建模：逐组件电路、遮挡细节与逆变器开关暂态。阵列外形为压缩展示。",
 "station":"未建模：交流潮流、电压、无功与变压器电磁暂态；这里不是电热站。",
 "load":"未建模：建筑内部、逐电器回路与电压响应。",
 "battery":"未建模：电芯电化学、热管理、老化与逐电芯结构。",
 "electric_boiler":"未建模：沸腾、蒸汽、压力和锅炉内部流场；仅固定温区热水。",
 "fuel_boiler":"未建模：火焰、燃烧化学、烟道流场、蒸汽和压力。",
 "solar_thermal":"未建模：逐管流场、瞬态升温、蒸汽和压力；固定热水温区。",
 "thermal_store":"未建模：逐层温度场、混合水箱和室温冷启动；SOC不是罐温。",
 "heat_exchanger":"未建模：板片流场、压降与动态传热；效率为能量比。",
 "heat_demand":"未建模：建筑室温、舒适度、管网水力与室内末端。",
 "parabolic_trough":"未建模：镜面光线追迹、启动升温、流场；本设备不直接发电。",
 "high_temp_store":"未建模：油罐内部流场、温度分层演化与室温冷启动。",
 "oil_water_exchanger":"未建模：流场、压降和动态传热；导热油与热水隔离。",
 "steam_generator":"未建模：冷启动、滑压运行和沸腾流场；仅固定蒸汽工况。",
 "steam_turbine":"未建模：逐级叶栅、转子动力学和变工况蒸汽物性。",
 "steam_condenser":"未建模：真空系统、冷却水水力与动态冷凝流场。",
 "feedwater_pump":"未建模：泵曲线、汽蚀与水库存动态；固定点水力增焓。",
 "solar_tower_receiver":"未建模：逐镜光线追迹、冷启动、融盐与防冻能耗。",
 "molten_salt_store":"未建模：冻结、融盐与动态罐温；SOC是预热基线以上库存。",
 "salt_steam_generator":"未建模：冷启动、动态沸腾与滑压；熔盐直接换热，不经导热油。"}
const METRICS := {"mw":"可用功率 [MW]", "generated_mw":"发电功率", "sent_mw":"送出功率", "received_mw":"接收功率", "input_mw":"输入功率", "output_mw":"输出功率", "curtailed_mw":"弃电功率", "loss_mw":"损耗功率", "served_mw":"已供电", "unserved_mw":"缺电", "soc":"库存比例 [0–1]", "energy_mwh":"电库存", "energy_mwhth":"热库存", "status_reason":"运行说明", "connected":"已连接", "valid":"数据有效", "operating":"运行中", "heat_sent_mwth":"送热功率", "heat_output_mwth":"产热功率", "mass_flow_kg_s":"质量流量", "module_temp_c":"组件温度", "cell_temp_c":"电池片温度", "wind_speed_mps":"风速"}
const EXTRA_METRICS := {"nameplate_clipped_mw":"额定容量削顶", "air_density_kgm3":"空气密度 [kg/m³]", "kinetic_mw":"风能功率", "reference_air_density_kgm3":"参考空气密度 [kg/m³]", "cp_aero":"气动功率系数 Cp", "curve_mode":"功率曲线模式", "input_mwth": "输入热功率", "output_mwth": "输出热功率", "loss_mwth": "热损耗", "heat_connected": "热端已连接", "electric_connected": "电端已连接", "cycle_complete": "蒸汽回路闭合", "steam_heat_mwth": "蒸汽增焓功率", "oil_input_mwth": "热油输入", "salt_input_mwth": "热盐输入", "gross_electric_mw": "毛发电", "generator_loss_mw": "发电机损耗", "condenser_rejection_mwth": "实际排热", "available_rejection_mwth": "可用排热能力", "pump_electric_mw": "给水泵用电", "pump_hydraulic_mw": "给水水力增焓", "pump_motor_loss_mw": "泵电机损耗", "auxiliary_electric_mw": "辅机用电", "auxiliary_electric_loss_mw": "辅机电损耗", "available_mwth": "可用热功率", "curtailed_mwth": "弃热功率", "hot_input_mwth": "热侧输入", "warm_output_mwth": "温侧输出", "incident_mw": "入射功率", "optical_rejection_mw": "光学未捕获", "potential_thermal_loss_mw": "潜在散热", "thermal_loss_mw": "实际散热", "dni_wm2": "直接法向辐照 DNI", "cos_incidence": "入射余弦", "electric_input_mw": "电输入", "conversion_loss_mw": "转换损耗", "fuel_input_mw": "燃料输入 [LHV]", "fuel_volume_nm3_per_h": "燃气量 [Nm³/h]", "fuel_cost_per_h": "教学燃料费 [元/h]", "demand_mw": "用电需求", "demand_mwth": "用热需求", "served_mwth": "已供热", "unserved_mwth": "缺热", "delivered_mw": "送达功率", "charge_mw": "充电功率", "discharge_mw": "放电功率", "charge_mwth": "充热功率", "discharge_mwth": "放热功率", "capacity_mwh": "电容量", "capacity_mwhth": "热容量", "capacity_mw": "线路额定容量", "mass_flow_capacity_kg_s": "质量流量上限", "mode": "储能模式", "soc_before": "时步前库存比例 [0–1]", "next_energy_mwh": "时步结束预计电库存", "next_energy_mwhth": "时步结束预计热库存", "storage_loss_mw": "储能损耗", "storage_conversion_loss_mw": "充放电转换损耗", "storage_conversion_loss_mwth": "充放热转换损耗", "self_discharge_mwh": "自损电量", "self_discharge_mwhth": "自损热量", "storage_balance_error_mwh": "电库存守恒差", "storage_balance_error_mwhth": "热库存守恒差", "priority": "调度优先级", "utilization": "利用率 [0–1]", "loss_fraction": "线路损耗比例 [0–1]", "carrier": "能量载体", "grade_id": "温度品质", "rated_mw": "额定功率", "gross_dc_mw": "毛直流功率", "dc_mw": "直流功率", "dc_loss_mw": "直流损耗", "ac_mw": "交流功率", "inverter_loss_mw": "逆变损耗", "clipping_mw": "逆变削顶", "irradiance_wm2": "面上辐照", "model_profile": "模型配置", "model_profile_version": "模型版本", "errors": "数据错误", "source": "输入来源"}
var host: Node
var device_id := -1
var viewport: SubViewport
var view_container: SubViewportContainer
var camera: Camera3D
var scene_root: Node3D
var model_node: Node3D
var title_label: Label
var status_label: Label
var model_label: Label
var tabs: TabContainer
var texts: Dictionary = {}
var camera_target := Vector3.ZERO
var camera_yaw := 35.0
var camera_pitch := 22.0
var camera_distance := 10.0
var model_radius := 1.0
var _built := false
var _signature := ""
var _orbit := false
var _pan := false
var _drag_travel := 0.0

func setup(controller: Node) -> void:
 host = controller
 _build_ui()

func open_device(id: int) -> bool:
 if not is_instance_valid(host): return false
 var item: Dictionary = host.device(id)
 if item.is_empty() or not item.get("kind", "") in Catalog.implemented_kinds(): return false
 _build_ui()
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 device_id = id
 _signature = ""
 tabs.current_tab = 0
 refresh()
 var available := get_parent().get_viewport().get_visible_rect().size
 var desired := Vector2i(available * 0.94)
 popup_centered(Vector2i(maxi(680, desired.x), maxi(480, desired.y)))
 reset_camera.call_deferred()
 return true

func close_device() -> void:
 if is_instance_valid(viewport): viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
 _orbit = false
 _pan = false
 hide()

func _build_ui() -> void:
 if _built: return
 _built = true
 title = "设备详情 · 只读实时视图"
 size = Vector2i(1180, 780)
 min_size = Vector2i(680, 480)
 transient = true
 exclusive = true
 visible = false
 close_requested.connect(close_device)
 focus_exited.connect(func(): _orbit = false; _pan = false)
 window_input.connect(_window_input)
 var panel := PanelContainer.new()
 add_child(panel)
 panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 panel.theme = UITheme.create(load("res://assets/InterfaceCJK.ttc"))
 var column := VBoxContainer.new()
 column.add_theme_constant_override("separation", 12)
 panel.add_child(column)
 var bar := HBoxContainer.new()
 column.add_child(bar)
 var back := Button.new()
 back.text = "← 返回上一级"
 back.pressed.connect(close_device)
 bar.add_child(back)
 title_label = Label.new()
 title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 title_label.add_theme_font_size_override("font_size", 22)
 bar.add_child(title_label)
 var reset := Button.new()
 reset.text = "适配模型"
 reset.pressed.connect(reset_camera)
 bar.add_child(reset)
 status_label = Label.new()
 status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 column.add_child(status_label)
 var split := HSplitContainer.new()
 split.size_flags_vertical = Control.SIZE_EXPAND_FILL
 column.add_child(split)
 var left := VBoxContainer.new()
 left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 left.size_flags_stretch_ratio = 1.6
 split.add_child(left)
 view_container = SubViewportContainer.new()
 view_container.stretch = true
 view_container.custom_minimum_size = Vector2(220, 180)
 view_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
 view_container.mouse_filter = Control.MOUSE_FILTER_STOP
 left.add_child(view_container)
 view_container.gui_input.connect(_view_input)
 viewport = SubViewport.new()
 viewport.own_world_3d = true
 viewport.size_changed.connect(reset_camera)
 viewport.handle_input_locally = false
 viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
 view_container.add_child(viewport)
 scene_root = Node3D.new()
 viewport.add_child(scene_root)
 var environment := WorldEnvironment.new()
 environment.environment = Environment.new()
 environment.environment.background_mode = Environment.BG_COLOR
 environment.environment.background_color = Color("12212b")
 environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 environment.environment.ambient_light_color = Color("cadfe9")
 environment.environment.ambient_light_energy = 0.75
 scene_root.add_child(environment)
 var light := DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-45, -35, 0)
 light.light_energy = 1.5
 scene_root.add_child(light)
 camera = Camera3D.new()
 camera.fov = 42
 camera.current = true
 scene_root.add_child(camera)
 model_label = Label.new()
 model_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 left.add_child(model_label)
 var help := Label.new()
 help.text = "按住左键 / 中键平移 · 右键旋转\n滚轮缩放 · 适配模型重置 · Esc返回"
 help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 left.add_child(help)
 tabs = TabContainer.new()
 tabs.custom_minimum_size.x = 350
 tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 split.add_child(tabs)
 for caption in ["运行", "参数", "连接", "边界"]:
  var scroll := ScrollContainer.new()
  scroll.name = caption
  scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  tabs.add_child(scroll)
  var label := Label.new()
  label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  label.size_flags_vertical = Control.SIZE_EXPAND_FILL
  label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
  scroll.add_child(label)
  texts[caption] = label
 var timer := Timer.new()
 timer.wait_time = 0.3
 timer.timeout.connect(func():
  if visible: refresh())
 add_child(timer)
 timer.start()

func refresh() -> void:
 if not _built or device_id < 0: return
 var item: Dictionary = host.device(device_id) if is_instance_valid(host) else {}
 if item.is_empty():
  title_label.text = "设备 #%d · 已移除" % device_id
  status_label.text = "设备已删除或场景已更换。返回场景继续操作；撤销恢复该设备后，本页会自动更新。"
  for label in texts.values(): label.text = "当前设备不存在，未保留旧结果。"
  if is_instance_valid(model_node): model_node.free()
  model_node = null
  model_label.text = "无当前模型"
  _signature = ""
  return
 var kind := str(item.kind)
 title_label.text = "%s #%d" % [NAMES.get(kind, kind), device_id]
 status_label.text = "实时只读 · 与主场景同一设备、同一计算结果 · 参数编辑请返回主场景"
 var params: Dictionary = item.get("params", {})
 var vp: Dictionary = host.visual_params(params) if host.has_method("visual_params") else params.duplicate(true)
 var signature := str([kind, vp])
 if signature != _signature:
  if is_instance_valid(model_node): model_node.free()
  model_node = Visual.create(kind, vp, true)
  scene_root.add_child(model_node)
  _signature = signature
  reset_camera()
 model_label.text = "现有设备真实展示资产 · %s\n外形用于识别与检查，不代表额外内部物理仿真。" % ("米制尺寸" if vp.get("visual_dimension_profile", "") == "metric_v1" else "旧版示意尺寸")
 var results: Dictionary = host.get("result") if host.get("result") is Dictionary else {}
 var report: Dictionary = results.get("devices", {}).get(str(device_id), {})
 texts["运行"].text = "主场景最新计算结果\n\n" + (_rows(report) if not report.is_empty() else "尚无本设备计算结果；本页不会独立求解。") + "\n\n持久运行状态\n" + (_rows(item.get("state", {})) if not item.get("state", {}).is_empty() else "无独立持久状态")
 var lines: Array[String] = []
 var boundaries: Array[String] = ["已建模 / 计算口径"]
 var known: Array[String] = []
 for group in Form.GROUPS.get(kind, []):
  lines.append(str(group.title))
  boundaries.append(str(group.get("source", "")))
  for field in group.get("fields", []):
   var key := str(field[0])
   known.append(key)
   if params.has(key): lines.append("%s：%s %s" % [field[1], _value(params[key]), field[2]])
  lines.append("")
 for key in params:
  if not str(key) in known: lines.append("%s：%s" % [_metric_name(str(key)), _value(params[key])])
 texts["参数"].text = "设备当前参数（非模板）\n\n" + "\n".join(lines)
 boundaries.append("\n" + str(LIMITS.get(kind, "仅展示现有模型；不新增求解。")))
 boundaries.append("\n3D视角、缩放、窗口开关不会改变设备参数、库存、线路或模拟时钟。")
 texts["边界"].text = "\n\n".join(boundaries)
 texts["连接"].text = _connections(kind)

func _value(value: Variant) -> String:
 if value is bool: return "是" if value else "否"
 if value is float: return String.num(value, 6)
 if value is Array: return "无" if value.is_empty() else "%d 项（完整数据请查看主场景参数）" % value.size()
 if value is Dictionary: return "%d 个字段（结构化数据）" % value.size()
 if value is String and value in ["cubic", "custom"]:
  return "约束立方近似" if value == "cubic" else "自定义曲线"
 if value is String and value in ["idle", "charge", "discharge"]:
  return {"idle":"待机", "charge":"充能", "discharge":"放能"}[value]
 return str(value)

func _metric_name(key: String) -> String:
 var unit := ""
 for suffix in ["_mwhth", "_mwth", "_mwh", "_mw", "_kg_s", "_temp_c", "_mps", "_wm2", "_kpa", "_kj_kg"]:
  if key.ends_with(suffix):
   unit = {"_mwhth":"MWhth", "_mwth":"MWth", "_mwh":"MWh", "_mw":"MW", "_kg_s":"kg/s", "_temp_c":"°C", "_mps":"m/s", "_wm2":"W/m²", "_kpa":"kPa", "_kj_kg":"kJ/kg"}[suffix]
   break
 return str(METRICS.get(key, EXTRA_METRICS.get(key, key))) + (" [" + unit + "]" if unit != "" else "")

func _rows(values: Dictionary) -> String:
 var lines: Array[String] = []
 for key in values:
  if str(key) in ["id", "kind", "model"]: continue
  var value_text := _value(values[key])
  if str(key) in ["errors", "warnings"] and values[key] is Array:
   value_text = "无" if values[key].is_empty() else "；".join(values[key].slice(0, 6))
  lines.append("%s：%s" % [_metric_name(str(key)), value_text])
 return "\n".join(lines) if not lines.is_empty() else "暂无记录"

func _endpoint(id: int) -> String:
 if id == -1: return "外部电网"
 var item: Dictionary = host.device(id)
 return "%s #%d" % [NAMES.get(item.get("kind", ""), "未知设备"), id]

func _connections(kind: String) -> String:
 var lines: Array[String] = ["设备端口（目录定义）"]
 for port in Catalog.ports(kind):
  lines.append("%s · %s\n%s · %s %s" % [port.id, {"input":"输入", "output":"输出", "bidirectional":"双向"}.get(port.direction, port.direction), {"electricity_ac":"交流电", "heat_water":"热水", "heat_oil":"导热油", "heat_salt":"熔盐", "water_steam":"水 / 蒸汽"}.get(port.carrier, port.carrier), port.get("unit", "MW"), port.get("grade_id", "")])
 lines.append("\n实际线路（主场景当前拓扑）")
 var count := 0
 for link in host.get("links"):
  if int(link.get("from", -999)) != device_id and int(link.get("to", -999)) != device_id: continue
  count += 1
  lines.append("%s / %s\n→ %s / %s" % [_endpoint(int(link.from)), link.get("from_port", "默认端口"), _endpoint(int(link.to)), link.get("to_port", "默认端口")])
  for key in ["carrier", "grade_id", "capacity_mw", "capacity_mwth", "mass_flow_capacity_kg_s", "capacity_kg_s", "loss_fraction"]:
   if link.has(key): lines.append("  %s：%s" % [_metric_name(key), _value(link[key])])
 if count == 0: lines.append("尚未连接任何线路。端口存在不代表已经接线。")
 return "\n\n".join(lines)

func _bounds(node: Node3D, transform: Transform3D = Transform3D.IDENTITY) -> Array[AABB]:
 var found: Array[AABB] = []
 var current := transform * node.transform
 if node is MeshInstance3D and node.mesh != null: found.append(current * node.get_aabb())
 for child in node.get_children():
  if child is Node3D: found.append_array(_bounds(child, current))
 return found

func reset_camera() -> void:
 if not is_instance_valid(model_node): return
 var parts := _bounds(model_node)
 var bounds := AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
 if not parts.is_empty():
  bounds = parts[0]
  for part in parts: bounds = bounds.merge(part)
 camera_target = bounds.get_center()
 model_radius = maxf(bounds.size.length() * 0.5, 0.1)
 camera_yaw = 35.0
 camera_pitch = 22.0
 var aspect := maxf(float(viewport.size.x) / maxf(float(viewport.size.y), 1.0), 0.1)
 # Fit projected AABB corners rather than a circumscribed sphere. Long, flat
 # arrays and tall turbines should fill the view without wasting vertical space.
 var tan_vertical := tan(deg_to_rad(camera.fov * 0.5))
 var tan_horizontal := tan_vertical * aspect
 var yaw := deg_to_rad(camera_yaw)
 var pitch := deg_to_rad(camera_pitch)
 var outward := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
 var right := Vector3(cos(yaw), 0, -sin(yaw))
 var up := outward.cross(right)
 camera_distance = 0.0
 for i in 8:
  var point := bounds.get_endpoint(i) - camera_target
  var depth := point.dot(outward)
  camera_distance = maxf(camera_distance, depth + absf(point.dot(right)) / tan_horizontal * 1.12)
  camera_distance = maxf(camera_distance, depth + absf(point.dot(up)) / tan_vertical * 1.12)
 _update_camera()

func _update_camera() -> void:
 camera_distance = clampf(camera_distance, model_radius * 0.25, model_radius * 30.0)
 camera_pitch = clampf(camera_pitch, -80.0, 80.0)
 var yaw := deg_to_rad(camera_yaw)
 var pitch := deg_to_rad(camera_pitch)
 camera.position = camera_target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * camera_distance
 camera.near = maxf(0.001, model_radius * 0.001)
 camera.far = maxf(100.0, camera_distance + model_radius * 60.0)
 camera.look_at(camera_target, Vector3.UP)

func _view_input(event: InputEvent) -> void:
 if event is InputEventMouseButton:
  if event.pressed: _drag_travel = 0.0
  if event.button_index == MOUSE_BUTTON_LEFT:
   _pan = event.pressed
   _orbit = false
  elif event.button_index == MOUSE_BUTTON_RIGHT: _orbit = event.pressed
  elif event.button_index == MOUSE_BUTTON_MIDDLE: _pan = event.pressed
  elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
   camera_distance *= 0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.12
   _update_camera()
  view_container.accept_event()
 elif event is InputEventMouseMotion:
  _drag_travel += event.relative.length()
  if _drag_travel < 4.0: return
  if _orbit:
   camera_yaw -= event.relative.x * 0.35
   camera_pitch += event.relative.y * 0.3
  elif _pan:
   var scale := camera_distance * 0.0018
   camera_target += (-camera.basis.x * event.relative.x + camera.basis.y * event.relative.y) * scale
  if _orbit or _pan:
   _update_camera()
   view_container.accept_event()

func _window_input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
  close_device()
  set_input_as_handled()
 if event is InputEventMouseButton and not event.pressed:
  if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: _orbit = false
  if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]: _pan = false
