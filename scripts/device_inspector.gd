extends Window
## Read-only live view. Host remains the sole owner of devices, links and results.
## API: setup(host), open_device(id) -> bool, refresh(), close_device().
const Catalog = preload("res://scripts/device_catalog.gd")
const Visual = preload("res://scripts/equipment_visual.gd")
const TowerDetail = preload("res://scripts/tower_detail_sample.gd")
const StationDetail = preload("res://scripts/station_detail_sample.gd")
const PVDetail = preload("res://scripts/pv_detail_sample.gd")
const Form = preload("res://scripts/parameter_form.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
const SaveGeometry=preload("res://scripts/save_validator.gd")
const NAMES := {"nitrogen_supply_boundary":"有限氮气供料站","co2_supply_boundary":"有限CO₂供料站","ammonia_synthesis_station":"合成氨成套站","methanol_synthesis_station":"甲醇合成成套站","hydrogen_liquid_store":"液氢储存成套站","hydrogen_metal_hydride_store":"LaNi₅固态储氢站","collector_substation":"基地汇集升压站","co2_liquid_cycle_store":"压缩液化CO₂储能站","water_supply_boundary":"有限供水站","electrolyzer_station":"电解制氢站","hydrogen_gas_store":"气态储氢站","fuel_cell_station":"燃料电池电站","battery_sodium":"钠离子电池储能", "battery_flow":"液流电池储能", "caes_aboveground":"地上压缩空气储能", "liquid_air_store":"液态空气储能", "hydrogen_storage_system":"氢储能完整系统", "solid_thermal_store":"固体介质储热", "wind":"风机", "pv":"光伏", "station":"中压变配电单元", "load":"用电需求", "battery":"锂离子电池储能", "electric_boiler":"电热水锅炉", "thermal_store":"储热罐", "heat_exchanger":"隔离换热器", "heat_demand":"热需求", "fuel_boiler":"燃气热水锅炉", "solar_thermal":"太阳能集热器", "parabolic_trough":"槽式聚光集热器", "high_temp_store":"高温导热油储热", "oil_water_exchanger":"油水换热器", "steam_generator":"蒸汽发生器", "steam_turbine":"汽轮发电机", "steam_condenser":"蒸汽冷凝器", "feedwater_pump":"给水泵", "solar_tower_receiver":"塔式熔盐接收器", "molten_salt_store":"双罐熔盐储热", "salt_steam_generator":"熔盐蒸汽发生器"}
const LIMITS := {
"nitrogen_supply_boundary":"25°C气态N₂有限预制原料，初始导入明确记账；不模拟空分与物流补给，不可当免费空气源。",
"co2_supply_boundary":"25°C气态CO₂有限预制碳源，以低压气囊作教学边界；不是液CO₂罐，不宣称已模拟捕集、液化或运输。不可直接与闭式CO₂储能库存相连。",
"ammonia_synthesis_station":"N₂+3H₂→2NH₃，25°C气态产品有限缓冲；电驱工艺与电热、环境排热均入账。无液氨相变、销售或产品清空入口。缺原料/功率/冷却或满库停产；不模拟实际压力、催化动力学和安全控制。",
"methanol_synthesis_station":"CO₂+3H₂→CH₃OH+H₂O，25°C液态甲醇有限缓冲，副产液水计入环境边界。无碳源不能生产；整站电热、排热和产水显式守恒，无产品销售、消费或清空入口。教学固定单耗非实际装置性能。",
"hydrogen_liquid_store":"物种H₂内部为约20.27K富仲液氢，进出均为25°C气氢；相对焓−1.24kWh/kg不是可发电库存，也不是12kWh/kg液化用电。液化排热、有限环境气化器吸热和实际出氢辅机分别记账。固定蒸发0.1%/天为教学假设，新建0kg。只有风光或有限电储能能供出氢辅机，禁止燃料电池自举；未模拟压力、低温动态、安全或厂商性能。",
"hydrogen_metal_hydride_store":"物种H₂结合于LaNi₅，不是冻结的纯氢。干宿主可逆H₂容量=1.2%是教学假设；已建宿主质量固定，不能改参数变出材料。结合态相对焓−4.275kWh/kg，吸氢排热/电热解吸均有真实有限功率。内部工艺热不另算储电SOC；新建0kg。未模拟材料循环衰减、压力平台或安全控制。",
"collector_substation":"默认与上限200 MW为教学吞吐，1%为教学损耗，非特定120 MVA主变性能换算。固定100×102 m教学占地，参照公开AIS厂站分区；照片不作精确尺寸测量。支持一个汇集节点的星形网络，不支持变电站级联。未建模电压层级、无功、交流潮流和主变暂态；AC_BUS不是实际高压电压等级。",
"co2_liquid_cycle_store":"闭式CO₂压缩—液化—气化—膨胀成套站，含内部蓄热。工质总质量未标定，SOC=0不代表气仓无CO₂；不赠独立热库存/热输出。默认794.24MWh为内部等效库存。146MW×6.8h与100MW×6.14h来自河北院2026-10-09公开设计工况；净毛边界未核实，992.8→614MWh仅教学算术参考，非同循环实测性能。净转换系数0.8和614/794.24为教学拆分，不是压缩机/透平实测效率。默认自损0是理想化边界，可设置正值；未模拟温压/相平衡/启停。",
"water_supply_boundary":"显式物种、相态与kg库存；固定教学工况，不模拟压力容器应力、气体动态或安全控制。排向环境的氧、液水、热均记账，不等于可销售或可连接的产品端口。原完整氢储能系统另为封装模型，不与本站共用或重复计库存。",
"electrolyzer_station":"显式物种、相态与kg库存；固定教学工况，不模拟压力容器应力、气体动态或安全控制。排向环境的氧、液水、热均记账，不等于可销售或可连接的产品端口。原完整氢储能系统另为封装模型，不与本站共用或重复计库存。",
"hydrogen_gas_store":"显式物种、相态与kg库存；固定教学工况，不模拟压力容器应力、气体动态或安全控制。排向环境的氧、液水、热均记账，不等于可销售或可连接的产品端口。原完整氢储能系统另为封装模型，不与本站共用或重复计库存。",
"fuel_cell_station":"显式物种、相态与kg库存；固定教学工况，不模拟压力容器应力、气体动态或安全控制。排向环境的氧、液水、热均记账，不等于可销售或可连接的产品端口。原完整氢储能系统另为封装模型，不与本站共用或重复计库存。",
 "battery_sodium":"钠离子电池箱 + 双向PCS。聚合电能库存；不计算电芯化学、温度、老化或循环寿命。充放效率为可编辑教学假设，包含PCS，不重复扣逆变损耗。",
 "battery_flow":"正/负电解液罐 + 电堆 + 泵组 + 双向PCS。容量与功率分别约束；泵耗与PCS损耗已并入净充放效率，不额外生成电或热。未计算浓度、液位或膜传质。",
 "caes_aboveground":"地上承压容器组 + 电驱压缩机 + 膨胀发电机。不是地下洞穴。净效率覆盖压缩、储气热管理及发电的教学损失；没有免费外部燃料或热源。聚合库存不是压力/气体质量，未计算压力、温度、流量或动态热力循环。",
 "liquid_air_store":"电驱液化机/冷箱 + 低温绝热液罐 + 泵/膨胀发电机。净效率合并液化、冷/热回收与发电假设；自损代表等效待机损失，不声称计算实际蒸发量。未计算低温相变、压力或冷启动。",
 "hydrogen_storage_system":"电解制氢及压缩 → 储氢容器 → 燃料电池/逆变回发。库存MWh为氢低位热值LHV等效能量，不是可直接送出的AC电量。充电效率是电解+压缩净LHV效率；放电效率是燃料电池+逆变效率。不单设可接线氢端口，氢质量仅按33.33 kWh/kg LHV换算，不动态求解水耗、氢流体/压力或副产热。",
 "solid_thermal_store":"保温固体蓄热体 + 换热通道。当前仅90/60°C热水服务的等效热库存；容量是MWhth，不是电量。不自带电加热器、汽轮机或发电能力；需显式热源充热，发电需独立适配的转换链。当前90/60°C热端不兼容既有高温蒸汽发电链。未计算内部温度分布、材料热容曲线或冷启动。",
 "wind":"未建模：叶片结构、尾流、机械载荷与电网暂态。外形不是可进入的机舱仿真。",
 "pv":"未建模：逐组件电路、遮挡细节与逆变器开关暂态。代表性组件示例，非全场数量；不推断全场布置。",
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
const METRICS := {"nitrogen_in_kg_s":"氮气输入","nitrogen_out_kg_s":"有限氮气输出","co2_in_kg_s":"CO₂碳源输入","co2_out_kg_s":"有限CO₂输出","product_produced_kg_s":"实际产品生成","ammonia_produced_kg_s":"气态氨生成","methanol_produced_kg_s":"液态甲醇生成","chemical_electric_mw":"化工整站用电","water_in_kg_s":"液水输入","water_out_kg_s":"供水输出","hydrogen_in_kg_s":"氢输入","hydrogen_out_kg_s":"氢输出","electric_output_mw":"净电输出","oxygen_vented_kg_s":"氧排向环境","oxygen_from_air_kg_s":"从空气取氧","water_released_kg_s":"液态产水排出","heat_rejected_mwth":"环境排热（不可供热）","inventory_before_kg":"时步前物料库存","inventory_after_leak_kg":"泄漏后库存","next_inventory_kg":"预计时步末库存","leaked_kg":"本步泄漏质量","material_inventory_kg":"已提交物料库存","species_id":"物种","phase_id":"相态","mw":"可用功率 [MW]", "generated_mw":"发电功率", "sent_mw":"送出功率", "received_mw":"接收功率", "input_mw":"输入功率", "output_mw":"输出功率", "curtailed_mw":"弃电功率", "loss_mw":"损耗功率", "served_mw":"已供电", "unserved_mw":"缺电", "soc":"库存比例 [0–1]", "energy_mwh":"电库存", "energy_mwhth":"热库存", "status_reason":"运行说明", "connected":"已连接", "valid":"数据有效", "operating":"运行中", "heat_sent_mwth":"送热功率", "heat_output_mwth":"产热功率", "mass_flow_kg_s":"质量流量", "module_temp_c":"组件温度", "cell_temp_c":"电池片温度", "wind_speed_mps":"风速"}
const EXTRA_METRICS := {"hydrogen_mass_kg":"等效氢质量 [kg · LHV换算]", "hydrogen_produced_mw_lhv":"制氢能流 [MW(LHV)]", "hydrogen_consumed_mw_lhv":"耗氢能流 [MW(LHV)]", "hydrogen_energy_basis":"氢能量口径", "hydrogen_charge_loss_mw":"制氢/压缩净损失", "hydrogen_discharge_loss_mw":"燃料电池/逆变净损失", "charge_conversion_loss_mw":"充能净转换损失", "discharge_conversion_loss_mw":"放能净转换损失", "nameplate_clipped_mw":"额定容量削顶", "air_density_kgm3":"空气密度 [kg/m³]", "kinetic_mw":"风能功率", "reference_air_density_kgm3":"参考空气密度 [kg/m³]", "cp_aero":"气动功率系数 Cp", "curve_mode":"功率曲线模式", "input_mwth": "输入热功率", "output_mwth": "输出热功率", "loss_mwth": "热损耗", "heat_connected": "热端已连接", "electric_connected": "电端已连接", "cycle_complete": "蒸汽回路闭合", "steam_heat_mwth": "蒸汽增焓功率", "oil_input_mwth": "热油输入", "salt_input_mwth": "热盐输入", "gross_electric_mw": "毛发电", "generator_loss_mw": "发电机损耗", "condenser_rejection_mwth": "实际排热", "available_rejection_mwth": "可用排热能力", "pump_electric_mw": "给水泵用电", "pump_hydraulic_mw": "给水水力增焓", "pump_motor_loss_mw": "泵电机损耗", "auxiliary_electric_mw": "辅机用电", "auxiliary_electric_loss_mw": "辅机电损耗", "available_mwth": "可用热功率", "curtailed_mwth": "弃热功率", "hot_input_mwth": "热侧输入", "warm_output_mwth": "温侧输出", "incident_mw": "入射功率", "optical_rejection_mw": "光学未捕获", "potential_thermal_loss_mw": "潜在散热", "thermal_loss_mw": "实际散热", "dni_wm2": "直接法向辐照 DNI", "cos_incidence": "入射余弦", "electric_input_mw": "电输入", "conversion_loss_mw": "转换损耗", "fuel_input_mw": "燃料输入 [LHV]", "fuel_volume_nm3_per_h": "燃气量 [Nm³/h]", "fuel_cost_per_h": "教学燃料费 [元/h]", "demand_mw": "用电需求", "demand_mwth": "用热需求", "served_mwth": "已供热", "unserved_mwth": "缺热", "delivered_mw": "送达功率", "charge_mw": "充电功率", "discharge_mw": "放电功率", "charge_mwth": "充热功率", "discharge_mwth": "放热功率", "capacity_mwh": "电容量", "capacity_mwhth": "热容量", "capacity_mw": "线路额定容量", "mass_flow_capacity_kg_s": "质量流量上限", "mode": "储能模式", "soc_before": "时步前库存比例 [0–1]", "next_energy_mwh": "时步结束预计电库存", "next_energy_mwhth": "时步结束预计热库存", "storage_loss_mw": "储能损耗", "storage_conversion_loss_mw": "充放电转换损耗", "storage_conversion_loss_mwth": "充放热转换损耗", "self_discharge_mwh": "自损电量", "self_discharge_mwhth": "自损热量", "storage_balance_error_mwh": "电库存守恒差", "storage_balance_error_mwhth": "热库存守恒差", "priority": "调度优先级", "utilization": "利用率 [0–1]", "loss_fraction": "线路损耗比例 [0–1]", "carrier": "能量载体", "grade_id": "温度品质", "rated_mw": "额定功率", "gross_dc_mw": "毛直流功率", "dc_mw": "直流功率", "dc_loss_mw": "直流损耗", "ac_mw": "交流功率", "inverter_loss_mw": "逆变损耗", "clipping_mw": "逆变削顶", "irradiance_wm2": "面上辐照", "model_profile": "模型配置", "model_profile_version": "模型版本", "errors": "数据错误", "source": "输入来源"}
var host: Node
var device_id := -1
var viewport: SubViewport
var view_container: SubViewportContainer
var camera: Camera3D
var scene_root: Node3D
var model_node: Node3D
var studio_ground: MeshInstance3D
var studio_environment: Environment
var studio_light: DirectionalLight3D
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
# View constraints only; never part of the energy/saved state.
const MAX_ZOOM_OUT_FACTOR := 1.6
const PAN_SCREEN_FRACTION := 0.60
var model_bounds := AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
var model_center := Vector3.ZERO
var fit_distance := 10.0
var max_zoom_out_distance := 16.0
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
 viewport.size_changed.connect(func(): _update_camera.call_deferred())
 viewport.handle_input_locally = false
 viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
 view_container.add_child(viewport)
 scene_root = Node3D.new()
 viewport.add_child(scene_root)
 var environment := WorldEnvironment.new()
 environment.environment = Environment.new()
 environment.environment.background_mode = Environment.BG_COLOR
 environment.environment.background_color = Color("12212b")
 studio_environment = environment.environment
 environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 environment.environment.ambient_light_color = Color("cadfe9")
 environment.environment.ambient_light_energy = 0.75
 scene_root.add_child(environment)
 var light := DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-45, -35, 0)
 light.light_energy = 1.5
 studio_light = light
 scene_root.add_child(light)
 camera = Camera3D.new()
 camera.fov = 42
 camera.current = true
 scene_root.add_child(camera)
 model_label = Label.new()
 model_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 left.add_child(model_label)
 var help := Label.new()
 help.text = "按住左键 / 中键平移 · 右键旋转\n滚轮缩放（缩小有界）· 拖动限于可见区域\n放大仅保留数值安全距离 · 适配模型重置 · Esc返回"
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

func _device_visual_params(item: Dictionary) -> Dictionary:
 var params: Dictionary = item.get("params", {})
 # Keep one-argument host compatibility, then overwrite construction defaults
 # with this actual device's version, including absent legacy markers.
 var vp: Dictionary = host.visual_params(params) if is_instance_valid(host) and host.has_method("visual_params") else params.duplicate(true)
 vp.visual_site_geometry_profile = str(item.get("site_geometry_profile", ""))
 if item.get("kind") == "battery_flow": vp.visual_geometry_profile = SaveGeometry.geometry_profile_for_device(item)
 return vp

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
 var vp: Dictionary = _device_visual_params(item)
 var signature := str([kind, vp])
 if signature != _signature:
  if is_instance_valid(model_node): model_node.free()
  model_node = PVDetail.new() if kind == "pv" else (StationDetail.new() if kind == "station" else (TowerDetail.new() if kind == "solar_tower_receiver" else Visual.create(kind, vp, true)))
  _configure_studio()
  scene_root.add_child(model_node)
  _signature = signature
  reset_camera()
 model_label.text = "现有设备真实展示资产 · %s\n外形用于识别与检查，不代表额外内部物理仿真。" % ("米制尺寸" if vp.get("visual_dimension_profile", "") == "metric_v1" else "旧版示意尺寸")
 if kind == "pv":
  model_label.text = "代表性组件示例，非全场数量 · 3块组件结构示意\n边框 / 电池片 / 支架 / 接线细节仅用于展示；右侧仍为全场真实参数。"
 if kind == "station":
  model_label.text = "代表性中压变压器 / 开关柜示例，非全站数量\n非厂家CAD；不新增电压 / 保护仿真。右侧为全站真实参数。"
 if kind == "solar_tower_receiver":
  model_label.text = "接收塔结构示意 · 与塔站同源外观，非实厂尺寸 / CAD\n既有教学塔高25m / 靶点24m；形态参考非实厂尺寸复刻。"
 if Catalog.is_storage(kind):
  model_label.text = "完整设施教学外观 · %s\n%s" % [NAMES.get(kind, kind), str(model_node.get_meta("storage_stages", "库存与端口以右侧当前设备数据为准"))]
  if model_node.get_meta("representative_lod", false):
   model_label.text += "\n大规模布局抽样显示 %d / %d 模块；全场容量、占地与库存不变。" % [int(model_node.get_meta("display_module_count", 0)), int(model_node.get_meta("module_count", 0))]
 if kind=="battery_flow":
  model_label.text += "\n旧版图标化尺度 · 单模块14×10m工艺图标 / 18×14m安装区；保留原布局，不代表10MWh真实工艺尺寸。" if SaveGeometry.geometry_profile_for_device(item)==SaveGeometry.FLOW_ICON_GEOMETRY else "\n参考工艺米制尺寸 · 单模块38×15m / 安装区42×19m；检修预留为教学假设，非厂家CAD。"
 var results: Dictionary = host.get("result") if host.get("result") is Dictionary else {}
 var report: Dictionary = results.get("devices", {}).get(str(device_id), {})
 texts["运行"].text = "主场景最新计算结果\n\n" + (_rows(report) if not report.is_empty() else "尚无本设备计算结果；本页不会独立求解。") + "\n\n持久运行状态\n" + (_rows(item.get("state", {})) if not item.get("state", {}).is_empty() else "无独立持久状态")
 if Catalog.is_material(kind):
  texts["运行"].text = _material_summary(item, report) + "\n\n完整计算与持久状态\n物料与电能按实际已提交事务计量；下方预计库存只属下一计算步，不会因打开本页推进。\n\n" + texts["运行"].text
 if Catalog.is_storage(kind):
  texts["运行"].text = _storage_summary(item, report) + "\n\n" + texts["运行"].text
 var lines: Array[String] = []
 var boundaries: Array[String] = ["已建模 / 计算口径"]
 if Catalog.is_material(kind):boundaries.append("显式物种、相态和品位端口；流量单位kg/s，实际库存单位kg。电能与环境热另行计量，不将物料或参考焓直接当电量。")
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
 if kind=="battery_flow":
  boundaries.append("几何兼容：旧版图标化设备保留原坐标和旧占地；新建采用参考工艺尺寸。两者使用完全相同的容量参数、库存与单AC端口。本页不迁移尺寸、不移动设备。")
 boundaries.append("\n未建模与技术边界：" + str(LIMITS.get(kind, "仅展示现有模型；不新增求解。")))
 boundaries.append("\n3D视角、缩放、窗口开关不会改变设备参数、库存、线路或模拟时钟。")
 texts["边界"].text = "\n\n".join(boundaries)
 texts["连接"].text = _connections(kind)

func _configure_studio() -> void:
 # Ground is a sibling, deliberately excluded from model fitting/pan bounds.
 if is_instance_valid(studio_ground): studio_ground.free()
 studio_environment.background_color = Color("87989f")
 studio_environment.ambient_light_color = Color("c8d8e4")
 studio_environment.ambient_light_energy = 0.55
 studio_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 var sky_material := ProceduralSkyMaterial.new()
 sky_material.sky_top_color = Color("7897b2")
 sky_material.sky_horizon_color = Color("b5c4c8")
 sky_material.ground_horizon_color = Color("8d9790")
 var sky := Sky.new()
 sky.sky_material = sky_material
 studio_environment.sky = sky
 studio_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
 studio_light.shadow_enabled = true
 studio_light.light_energy = 0.8
 studio_light.light_color = Color("fff0d7")
 studio_light.light_angular_distance = 1.8
 studio_light.shadow_bias = 0.4
 studio_light.shadow_normal_bias = 2.0
 viewport.msaa_3d = Viewport.MSAA_4X
 studio_ground = PVDetail.box(scene_root, Vector3.ONE, Vector3.ZERO, PVDetail.material("626255", 0.0, 0.95))
 studio_ground.name = "DisplayGroundNotEquipment"

func _fit_studio_ground() -> void:
 if not is_instance_valid(studio_ground): return
 var span := maxf(model_radius, 0.1)
 var ground_width := maxf(model_bounds.size.x + span * 0.9, span * 1.25)
 var ground_depth := maxf(model_bounds.size.z + span * 0.9, span * 1.25)
 studio_ground.scale = Vector3(ground_width, span * 0.035, ground_depth)
 studio_ground.position = Vector3(model_center.x, model_bounds.position.y - span * 0.02, model_center.z)
 studio_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 studio_light.directional_shadow_max_distance = span * 12.0
 for child in studio_ground.get_children(): child.free()
 var joint := PVDetail.material("5c5d52", 0.0, 0.95)
 for coordinate in [-0.25, 0.0, 0.25]:
  PVDetail.box(studio_ground, Vector3(0.001, 0.006, 1), Vector3(coordinate, 0.502, 0), joint)
  PVDetail.box(studio_ground, Vector3(1, 0.006, 0.001), Vector3(0, 0.502, coordinate), joint)

func _material_summary(item: Dictionary, report: Dictionary) -> String:
 var kind := str(item.get("kind", ""))
 var lines: Array[String] = ["已提交库存"]
 if kind in Catalog.Materials.INVENTORY_KINDS:
  var species: String = Catalog.Materials.species(kind)
  var phase_name: String = {"water_supply_boundary":"H2O(l)", "nitrogen_supply_boundary":"N2(g)", "co2_supply_boundary":"CO2(g)", "ammonia_synthesis_station":"NH3(g)", "methanol_synthesis_station":"CH3OH(l)", "hydrogen_gas_store":"H2(g)", "hydrogen_liquid_store":"H2(l)", "hydrogen_metal_hydride_store":"H2 · LaNi5结合态"}.get(kind, species)
  var inventory: Variant = item.get("state", {}).get("material_inventory_kg", {}).get(species)
  var capacity: float = Catalog.inventory_capacity(kind, item.get("params", {}))
  if _material_finite(inventory) and is_finite(capacity) and capacity > 0.0:
   lines.append("%s  %s / %s kg · 库存占容 %.2f%%" % [phase_name, _value(inventory), _value(capacity), float(inventory) / capacity * 100.0])
  else: lines.append("%s 库存尚无有效已提交数据，不以预计值替代。" % phase_name)
 else: lines.append("本站无独立物料库存；进出料由实际计算流量计量。")
 lines.append("\n实际流量 · 主场景当前计算步")
 var flow_keys: Array = []
 match kind:
  "water_supply_boundary": flow_keys = ["water_out_kg_s"]
  "nitrogen_supply_boundary": flow_keys = ["nitrogen_out_kg_s"]
  "co2_supply_boundary": flow_keys = ["co2_out_kg_s"]
  "electrolyzer_station": flow_keys = ["hydrogen_out_kg_s", "water_in_kg_s", "oxygen_vented_kg_s"]
  "hydrogen_gas_store", "hydrogen_liquid_store", "hydrogen_metal_hydride_store": flow_keys = ["hydrogen_in_kg_s", "hydrogen_out_kg_s"]
  "fuel_cell_station": flow_keys = ["hydrogen_in_kg_s", "oxygen_from_air_kg_s", "water_released_kg_s"]
  "ammonia_synthesis_station": flow_keys = ["product_produced_kg_s", "hydrogen_in_kg_s", "nitrogen_in_kg_s"]
  "methanol_synthesis_station": flow_keys = ["product_produced_kg_s", "hydrogen_in_kg_s", "co2_in_kg_s", "water_released_kg_s"]
 var flows: Array[String] = []
 for key in flow_keys:
  if _material_finite(report.get(key)): flows.append("%s：%s kg/s" % [METRICS.get(key, key), _value(report[key])])
 lines.append("\n".join(flows) if not flows.is_empty() else "尚无有效流量结果；不显示虚构零值。")
 var powers: Array[String] = []
 if not kind in ["water_supply_boundary", "nitrogen_supply_boundary", "co2_supply_boundary"]:
  for spec in [["electric_input_mw", "实际用电", "MW"], ["electric_output_mw", "实际净出电", "MW"], ["heat_rejected_mwth", "环境排热", "MWth"], ["environment_heat_in_mwth", "环境吸热", "MWth"]]:
   if spec[0] == "electric_output_mw" and kind != "fuel_cell_station": continue
   if spec[0] == "environment_heat_in_mwth" and kind != "hydrogen_liquid_store": continue
   if _material_finite(report.get(spec[0])): powers.append("%s：%s %s" % [spec[1], _value(report[spec[0]]), spec[2]])
  lines.append("\n实际用电与排热 · 主场景当前计算步")
  lines.append("\n".join(powers) if not powers.is_empty() else "尚无有效电热结果；不显示虚构零值。")
 lines.append("\n库存读取已提交状态；流量与电热读取最新计算，不因浏览而推进。")
 return "\n".join(lines)

func _material_finite(value: Variant) -> bool:
 return (value is int or value is float) and is_finite(float(value))

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
 var item: Dictionary = host.device(device_id) if is_instance_valid(host) and device_id >= 0 else {}
 var kind := str(item.get("kind", ""))
 if Catalog.is_electric_storage(kind) and key in ["energy_mwh", "next_energy_mwh", "capacity_mwh"]:
  var basis := "氢LHV" if kind == "hydrogen_storage_system" else "内部等效"
  var caption := "容量" if key == "capacity_mwh" else ("时步结束预计库存" if key == "next_energy_mwh" else "库存")
  return basis + caption + (" [MWh(LHV)]" if kind == "hydrogen_storage_system" else " [MWh]")
 var unit := ""
 for suffix in ["_mwhth", "_mwth", "_mwh", "_mw", "_kg_s", "_kg", "_temp_c", "_mps", "_wm2", "_kpa", "_kj_kg"]:
  if key.ends_with(suffix):
   unit = {"_mwhth":"MWhth", "_mwth":"MWth", "_mwh":"MWh", "_mw":"MW", "_kg_s":"kg/s", "_kg":"kg", "_temp_c":"°C", "_mps":"m/s", "_wm2":"W/m²", "_kpa":"kPa", "_kj_kg":"kJ/kg"}[suffix]
   break
 return str(METRICS.get(key, EXTRA_METRICS.get(key, key))) + (" [" + unit + "]" if unit != "" else "")

func _rows(values: Dictionary) -> String:
 var lines: Array[String] = []
 for key in values:
  if str(key) in ["id", "kind", "model"]: continue
  var value_text := _value(values[key])
  if str(key)=="material_inventory_kg" and values[key] is Dictionary:
   var stocks:Array[String]=[]
   for species in values[key]:stocks.append("%s  %s kg" % [species,_value(values[key][species])])
   value_text="；".join(stocks)
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
 if not node.visible: return found
 var current := transform * node.transform
 if node is MeshInstance3D and node.mesh != null: found.append(current * node.get_aabb())
 for child in node.get_children():
  if child is Node3D: found.append_array(_bounds(child, current))
 return found

func reset_camera() -> void:
 if not is_instance_valid(model_node): return
 var parts := _bounds(model_node)
 model_bounds = AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
 if not parts.is_empty():
  model_bounds = parts[0]
  for part in parts: model_bounds = model_bounds.merge(part)
 model_center = model_bounds.get_center()
 model_radius = maxf(model_bounds.size.length() * 0.5, 0.1)
 _fit_studio_ground()
 camera_target = model_center
 camera_yaw = 145.0 if model_node.get("device_kind") == "pv" else (-145.0 if model_node.get("device_kind") == "station" else 35.0)
 camera_pitch = 25.0 if model_node.get("device_kind") in ["pv", "station"] else 22.0
 fit_distance = _fitted_distance()
 camera_distance = fit_distance
 _update_camera()

func _camera_axes() -> Array[Vector3]:
 var yaw := deg_to_rad(camera_yaw)
 var pitch := deg_to_rad(camera_pitch)
 var outward := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
 var right := Vector3(cos(yaw), 0, -sin(yaw))
 return [right, outward.cross(right), outward]

func _fitted_distance() -> float:
 # Model-relative limit recalculated for the actual rotation and viewport shape.
 var aspect := maxf(float(viewport.size.x) / maxf(float(viewport.size.y), 1.0), 0.1)
 var tan_vertical := tan(deg_to_rad(camera.fov * 0.5))
 var tan_horizontal := tan_vertical * aspect
 var axes := _camera_axes()
 var distance := 0.0
 for i in 8:
  var point := model_bounds.get_endpoint(i) - model_center
  var depth := point.dot(axes[2])
  distance = maxf(distance, depth + absf(point.dot(axes[0])) / tan_horizontal * 1.12)
  distance = maxf(distance, depth + absf(point.dot(axes[1])) / tan_vertical * 1.12)
 return maxf(distance, model_radius * 0.01)

func _update_camera() -> void:
 if not is_instance_valid(camera) or not is_instance_valid(model_node): return
 if not is_finite(camera_yaw): camera_yaw = 35.0
 if not is_finite(camera_pitch): camera_pitch = 22.0
 camera_yaw = wrapf(camera_yaw, -180.0, 180.0)
 camera_pitch = clampf(camera_pitch, -80.0, 80.0)
 fit_distance = _fitted_distance()
 max_zoom_out_distance = fit_distance * MAX_ZOOM_OUT_FACTOR
 # No product zoom-in cap. This tiny scale-relative floor only prevents the
 # eye crossing its look-at target / near plane and degenerate transforms.
 var numerical_min := maxf(model_radius * 0.0001, 0.00001)
 if not is_finite(camera_distance): camera_distance = fit_distance
 camera_distance = clampf(camera_distance, numerical_min, max_zoom_out_distance)
 var axes := _camera_axes()
 if not camera_target.is_finite(): camera_target = model_center
 var offset := camera_target - model_center
 var half_height := camera_distance * tan(deg_to_rad(camera.fov * 0.5))
 var aspect := maxf(float(viewport.size.x) / maxf(float(viewport.size.y), 1.0), 0.1)
 # Project the target back onto the model-center plane, then bound its screen
 # offset. The model center always remains in the central 60% of the viewport,
 # including after orbit, resize and zoom; drag cannot send the whole model away.
 var dx := clampf(offset.dot(axes[0]), -half_height * aspect * PAN_SCREEN_FRACTION, half_height * aspect * PAN_SCREEN_FRACTION)
 var dy := clampf(offset.dot(axes[1]), -half_height * PAN_SCREEN_FRACTION, half_height * PAN_SCREEN_FRACTION)
 camera_target = model_center + axes[0] * dx + axes[1] * dy
 camera.position = camera_target + axes[2] * camera_distance
 # Adaptive near plane preserves close zoom without wasting depth precision at fit distance.
 camera.near = maxf(0.0000001, minf(model_radius * 0.01, camera_distance * 0.05))
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
  set_input_as_handled()
  if not event.echo:
   if is_instance_valid(host) and host.has_method("handle_escape"): host.handle_escape()
   else: close_device()
  return
 if event is InputEventMouseButton and not event.pressed:
  if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: _orbit = false
  if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]: _pan = false


func _storage_summary(item: Dictionary, report: Dictionary) -> String:
 var kind := str(item.kind)
 var thermal := Catalog.is_thermal_storage(kind)
 var p: Dictionary = Catalog.defaults(kind)
 p.merge(item.get("params", {}), true)
 var state: Dictionary = item.get("state", {})
 var energy_key := "energy_mwhth" if thermal else "energy_mwh"
 var capacity_key := "capacity_mwhth" if thermal else "capacity_mwh"
 var unit := "MWhth" if thermal else ("MWh(LHV)" if kind == "hydrogen_storage_system" else "MWh")
 var power_unit := "MWth" if thermal else "MW(AC)"
 var capacity := float(p.get(capacity_key, 0.0))
 var energy_text := "未提供持久库存，未假设初值"
 if state.has(energy_key):
  var energy := float(state[energy_key])
  energy_text = "%.4f / %.4f %s · SOC %.2f%%" % [energy, capacity, unit, 100.0 * energy / capacity if capacity > 0.0 else 0.0]
 var charging := "charge_mwth" if thermal else "charge_mw"
 var discharging := "discharge_mwth" if thermal else "discharge_mw"
 var ch := float(p.get("charge_efficiency", 1.0))
 var dis := float(p.get("discharge_efficiency", 1.0))
 var technology: Dictionary = Catalog.storage_technology(kind)
 var lines: Array[String] = ["储能技术：" + str(technology.get("name", NAMES.get(kind, kind))), "当前库存：" + energy_text,
  "功率上限：充 %.3f / 放 %.3f %s" % [float(p.get(charging, 0.0)), float(p.get(discharging, 0.0)), power_unit],
  "净效率：充 %.1f%% × 放 %.1f%% = %.1f%%（不含静置损失）" % [ch * 100.0, dis * 100.0, ch * dis * 100.0],
  "连续自损：λ = %.6f /h；库存按 exp(−λ×小时) 衰减" % float(p.get("self_discharge_per_h", 0.0)),
  "单步充放互斥；断线仍有自损，暂停时库存冻结。"]
 if report.has(charging) and report.has(discharging):
  lines.insert(3, "本步实际：充 %.4f / 放 %.4f %s" % [float(report[charging]), float(report[discharging]), power_unit])
 else:
  lines.insert(3, "本步实际充放：尚无计算结果，不以额定值代替。")
 if technology.has("charge_stage"):
  lines.append("充能链：" + str(technology.charge_stage))
  lines.append("放能链：" + str(technology.get("discharge_stage", "")))
 if thermal:
  lines.append("热储能仅输出热，不直接发电；发电必须另有显式、适配的转换设备。")
 if kind == "hydrogen_storage_system":
  lines.append("唯一外部能量接口为双向AC；电解、储氢与燃料电池在设施边界内，未开放氢管网。")
 return "\n".join(lines)
