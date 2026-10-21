extends "res://scripts/map.gd"
# Rebuilt from the retained V2 terrain checkpoint. New implementation, not recovered V10 source.
const UITheme = preload("res://scripts/ui_theme.gd")
const Model = preload("res://scripts/energy_model.gd")
const Visual = preload("res://scripts/equipment_visual.gd")
const Series = preload("res://scripts/series_import.gd")
const SaveValidator = preload("res://scripts/save_validator.gd")
const Climate = preload("res://scripts/climate_model.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const HighTemp = preload("res://scripts/high_temp_thermal.gd")
const Tower = preload("res://scripts/solar_tower_thermal.gd")
const Rankine = preload("res://scripts/rankine_cycle.gd")
const FuelSupply = preload("res://scripts/fuel_supply.gd")
const DEVICE_NAMES = {"tower_station":"塔式熔盐发电站","solar_tower_receiver":"塔式熔盐接收器","molten_salt_store":"双罐熔盐储热","salt_steam_generator":"熔盐蒸汽发生器","steam_generator":"蒸汽发生器","steam_turbine":"汽轮发电机","steam_condenser":"蒸汽冷凝器","feedwater_pump":"给水泵","thermal_station":"电热站","tower_station_preview":"塔式未投运预览","wind":"风机","pv":"光伏","station":"变电站","load":"需求节点","battery":"电池","electric_boiler":"电热水锅炉","fuel_boiler":"燃气热水锅炉","parabolic_trough":"槽式聚光集热器","high_temp_store":"高温导热油储热","oil_water_exchanger":"油水换热器","solar_thermal":"太阳能集热器","thermal_store":"储热罐","heat_exchanger":"隔离换热器","heat_demand":"热需求节点"}
const KINDS = ["wind","pv","station","load","battery","electric_boiler","fuel_boiler","solar_thermal","parabolic_trough","high_temp_store","oil_water_exchanger","thermal_store","heat_exchanger","heat_demand","steam_generator","steam_turbine","steam_condenser","feedwater_pump","solar_tower_receiver","molten_salt_store","salt_steam_generator"]
const THERMAL_KINDS = ["electric_boiler","fuel_boiler","solar_thermal","parabolic_trough","high_temp_store","oil_water_exchanger","thermal_store","heat_exchanger","heat_demand","steam_generator","steam_turbine","steam_condenser","feedwater_pump","solar_tower_receiver","molten_salt_store","salt_steam_generator"]
const INTERNAL_KINDS=["electric_boiler","fuel_boiler","solar_thermal","parabolic_trough","high_temp_store","oil_water_exchanger","thermal_store","heat_exchanger","steam_generator","steam_turbine","steam_condenser","feedwater_pump","solar_tower_receiver","molten_salt_store","salt_steam_generator"]
const BUILDABLE_KINDS=["wind","pv","station","battery","thermal_station","tower_station","tower_station_preview"]
const RANKINE_KINDS=["steam_generator","steam_turbine","steam_condenser","feedwater_pump","salt_steam_generator"]
const FACILITY_KINDS=["thermal_station","tower_station","tower_station_preview"]
const ENERGY_ZERO = {"generated":0.0,"delivered":0.0,"curtailed":0.0,"loss":0.0,"served":0.0,"unserved":0.0,"charge":0.0,"discharge":0.0,"storage_loss":0.0,"boiler_electric":0.0,"boiler_conversion_loss":0.0}
const THERMAL_ENERGY_ZERO = {"demand":0.0,"served":0.0,"unserved":0.0,"boiler_heat":0.0,"charge":0.0,"discharge":0.0,"network_loss":0.0,"exchanger_loss":0.0,"storage_loss":0.0}
const ImportUI = preload("res://scripts/import_dialog.gd")
var model = Model.new()
var optimization_controller: Node
var devices: Array = []
var links: Array = []
var templates: Dictionary = {}
var imports: Array = []
var next_id := 0
var selected_id := -2
var mode := "select"
var build_kind := "wind"
var pending_link := -2
var physical_lines := true
var nodes: Dictionary = {}
var equipment := Node3D.new()
var cables := Node3D.new()
var ghost: Node3D
var placement_outline: MeshInstance3D
var placement_key := ""
var feedback_key := ""
var undo_states: Array = []
var elapsed_s := 0.0
var energy := ENERGY_ZERO.duplicate(true)
var thermal_energy := THERMAL_ENERGY_ZERO.duplicate(true)
var fuel_supply:Dictionary = FuelSupply.defaults()
const SOLAR_ENERGY_ZERO = {"incident_mwh":0.0,"optical_rejection_mwh":0.0,"thermal_loss_mwh":0.0,"available_mwhth":0.0,"useful_mwhth":0.0,"curtailed_mwhth":0.0,"auxiliary_mwh":0.0}
var high_temp_energy:Dictionary = HighTemp.initial_energy()
var rankine_energy:Dictionary = Rankine.initial_energy()
var tower_energy:Dictionary = Tower.initial_energy()
var solar_energy:Dictionary = SOLAR_ENERGY_ZERO.duplicate(true)
var fuel_energy:Dictionary = FuelSupply.initial_energy()
var fuel_summary:Label
var fuel_supply_enabled:CheckButton
var fuel_controls:Dictionary = {}
var thermal_detail:Label
var thermal_network_summary:Label
var line_capacity_title:Label
var dispatch_dt_s := 1.0
var line_choice := OptionButton.new()
var editing_line := -1
var scene_revision := 0
var paused := true
var speed := 1.0
var speed_control: Control
var weather_orb: Control
var accumulator := 0.0
var result: Dictionary = {}
var last_weather: Dictionary = {}
var climate_config: Dictionary = Climate.defaults()
var climate_panel: Control
var weather_snapshot: Dictionary = {}
var visual_device_weather: Dictionary = {}
var weather_effects: Node
var weather_effects_enabled := true
var weather_effects_toggle: CheckButton
var sources: Dictionary = {}
var notice: Label
var status_label: Label
var selection_label: Label
var source_label: Label
var run_button: Button
var mode_label: Label
var slot: OptionButton
var confirmation := ConfirmationDialog.new()
var confirm_action: Callable
var import_dialog
var param_dialog := Window.new()
var parameter_form
var parameter_scope_label: Label
var picker_signature := ""
var param_errors := Label.new()
var param_target := OptionButton.new()
var param_scope := "device"
var parameter_id := -2
var data_dialog := Window.new()
var data_list := VBoxContainer.new()
var line_dialog := Window.new()
var line_capacity := SpinBox.new()
var line_loss := SpinBox.new()
var font_full: Font
var metric_values: Dictionary = {}
var metric_names: Dictionary = {}
var device_picker: OptionButton
var demand_picker: OptionButton
var demand_summary: Label
var demand_signature := ""
var line_toggle: Button
var modal_shade: ColorRect
var device_summary: Label
var fleet_count: Label
var ui_regions: Array[Control] = []
var tool_buttons: Dictionary = {}
var booted := false
var last_mouse := Vector2.ZERO
# Presentation-only interaction state: excluded from save, dispatch and undo.
var hovered_id := -2
var drag_candidate := -2
var drag_origin := Vector2.ZERO
var drag_active := false
var drag_offset := Vector2.ZERO
var camera_drag_blocked := false
var link_preview: Node3D
var link_preview_key := ""
var interaction_caption: Label
var quick_station_enter: Button
var hover_cooldown := 0.0
var pending_example := false
const Spatial=preload("res://scripts/spatial_dimensions.gd")
var dimension_profile:String="legacy_illustrative"
var dimension_summary:Label
var stations:Array=[]
var next_station_id:int=1000000
var station_nodes:Dictionary={}
var station_interior:Window
var station_port_dialog:ConfirmationDialog
var station_port_picker:OptionButton
var station_enter_button:Button
var hud_root: Control
var hud_header: PanelContainer
var hud_context: PanelContainer
var hud_build: PanelContainer
var hud_footer: PanelContainer
var hud_views: PanelContainer
var hud_layers: PanelContainer
var hud_layer_button: Button
var hud_clock: Label
var hud_metrics: Dictionary = {}
var hud_actions: Dictionary = {}
var hud_dock: Control
var hud_brand_subtitle: Label
var save_root := "user://rebuild_slots"

func _ready():
	dimension_profile="metric_v1"
	for kind in KINDS: templates[kind] = model.defaults(kind).duplicate(true)
	add_child(equipment); add_child(cables)
	super._ready()
	weather_effects=load("res://scripts/scene_weather.gd").new();add_child(weather_effects);weather_effects.setup(self)
	cfg.grid_export_mw = 4.0
	booted = true
	refresh()
	if "--game-self-test" in OS.get_cmdline_user_args(): call_deferred("game_self_test")
	if "--tower-demo" in OS.get_cmdline_user_args():call_deferred("tower_example")
	if "--demo" in OS.get_cmdline_user_args(): call_deferred("example")
	if "--storage-demo" in OS.get_cmdline_user_args():call_deferred("storage_example")
	optimization_controller = load("res://scripts/optimization_controller.gd").new()
	add_child(optimization_controller)
	optimization_controller.setup(self)
	print("REBUILD_V13_READY")

func label(t:String, size_px:int=17)->Label:
	var l := Label.new(); l.text=t; l.add_theme_font_size_override("font_size",size_px)
	l.add_theme_color_override("font_color",UITheme.INK); return l

func button(t:String, fn:Callable, parent:Node)->Button:
	var b:=Button.new(); b.text=t; b.custom_minimum_size.x=clampf(float(t.length())*15.0+22.0,54.0,276.0); b.tooltip_text=t; b.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; b.pressed.connect(fn); parent.add_child(b); b.custom_minimum_size.y=36; return b

func make_panel(parent:Node,p:Vector2,sz:Vector2)->VBoxContainer:
	var box:=PanelContainer.new(); parent.add_child(box); box.position=p; box.size=sz
	var st:=UITheme.panel(UITheme.SURFACE,10,8)
	box.add_theme_stylebox_override("panel",st);ui_regions.append(box)
	var v:=VBoxContainer.new(); box.add_child(v);v.add_theme_constant_override("separation",6);return v

func metric(parent:Node,key:String,title:String,unit:String,big:bool=false):
	var row:=HBoxContainer.new();parent.add_child(row);row.add_theme_constant_override("separation",8)
	var name_label:=label(title,16);name_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(name_label);metric_names[key]=name_label
	var value:=label("0.000",29 if big else 17);value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;value.custom_minimum_size.x=112;row.add_child(value);metric_values[key]=value
	var units:=label(unit,13);units.custom_minimum_size.x=58;units.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;row.add_child(units)

func fold(parent:Node,title:String)->VBoxContainer:
	var content:=VBoxContainer.new();content.add_theme_constant_override("separation",5)
	var toggle:=button(title+"  ▸",func():content.visible=not content.visible,parent)
	toggle.pressed.connect(func():toggle.text=title+("  ▾" if content.visible else "  ▸"))
	parent.add_child(content);content.visible=false;return content

func icon_texture(kind:String)->Texture2D:
	if kind in FACILITY_KINDS:return icon_texture("station")
	if kind=="fuel_boiler":return icon_texture("electric_boiler")
	if kind in ["load","battery"]:return load("res://assets/icon_%s.svg"%kind)
	var paths={"wind":'<path d="M32 27L29 57H35L32 27M32 27L29 4H33L35 23M32 27L10 41L8 37L28 25M32 27L54 40L56 36L36 24"/>',"pv":'<path d="M12 15H52L58 42H6ZM16 15L12 42M28 15L27 42M40 15L42 42M9 28H55M25 42L22 55M39 42L42 55M17 55H47"/>',"electric_boiler":'<rect x="13" y="9" width="38" height="46" rx="8"/><path d="M31 17L24 34H35L29 46M8 40H13M51 23H59"/>',"thermal_store":'<ellipse cx="32" cy="12" rx="20" ry="7"/><path d="M12 12V51C12 60 52 60 52 51V12M12 33H52M7 43H12M52 23H59"/>',"heat_exchanger":'<rect x="12" y="10" width="40" height="44" rx="4"/><path d="M20 15V49M28 15V49M36 15V49M44 15V49M5 22H12M52 43H60"/>',"station":'<path d="M9 13H55V56H9ZM9 23H55M20 13V23M32 13V23M44 13V23M18 33H27V48H18ZM37 33H46V48H37ZM31 30V53"/>'}
	var svg='<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><g fill="none" stroke="#a8d9d0" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+paths[kind]+'</g></svg>'
	var im:=Image.new();im.load_svg_from_string(svg);return ImageTexture.create_from_image(im)

func make_ui():
	font_full=load("res://assets/InterfaceCJK.ttc")
	var ui:=CanvasLayer.new();add_child(ui)
	var root:=Control.new();ui.add_child(root);root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud_root=root;root.name="GameWorkspace"
	var theme:=UITheme.create(font_full);root.theme=theme
	var header:=make_panel(root,Vector2.ZERO,Vector2(1400,72));hud_header=header.get_parent();hud_header.name="WorkspaceHeader"
	var hr:=HBoxContainer.new();header.add_child(hr);hr.add_theme_constant_override("separation",14)
	var brand:=VBoxContainer.new();brand.custom_minimum_size.x=154;hr.add_child(brand)
	brand.add_child(label("荒原 / 能源基地",21))
	hud_brand_subtitle=label("BASIN 02   ·   教学工作台",11);hud_brand_subtitle.add_theme_color_override("font_color",UITheme.MUTED);brand.add_child(hud_brand_subtitle)
	for pair in [["generated","实际发电"],["served","负荷实供"],["unserved","缺供"]]:
		var tile:=VBoxContainer.new();tile.custom_minimum_size.x=106;hr.add_child(tile)
		var caption:=label(pair[1]+" · MW",11);caption.add_theme_color_override("font_color",UITheme.MUTED);tile.add_child(caption)
		var value:=label("0.000",22);tile.add_child(value);hud_metrics[pair[0]]=value
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;hr.add_child(spacer)
	hud_clock=label("已暂停\n00:00:00",13);hud_clock.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;hr.add_child(hud_clock)
	run_button=button("▶ 运行 ×1",toggle_run,hr);run_button.name="GlobalRun";run_button.custom_minimum_size=Vector2(112,44)
	var tools:=HBoxContainer.new();hr.add_child(tools)
	button("导入 CSV",open_import,tools).custom_minimum_size.y=26
	button("数据来源",open_data_manager,tools).custom_minimum_size.y=26
	weather_orb=load("res://scripts/weather_orb.gd").new();root.add_child(weather_orb);weather_orb.mount_enabled=false;weather_orb.scale=Vector2(0.68,0.68);ui_regions.append(weather_orb)
	var views:=make_panel(root,Vector2.ZERO,Vector2(412,46));hud_views=views.get_parent();hud_views.name="ViewToolbar"
	var vr:=HBoxContainer.new();views.add_child(vr)
	hud_layer_button=button("图层 · 地貌",func():hud_layers.visible=not hud_layers.visible,vr);hud_layer_button.custom_minimum_size.x=120
	for i in range(3):button(["俯视","等轴","透视"][i],set_view.bind(i),vr).tooltip_text="视角 F%d"%(i+1)
	button("全景",reset_camera,vr).tooltip_text="基地全景 R"
	button("聚焦",focus_selected,vr).tooltip_text="聚焦选中设备 F"
	var left:=make_panel(root,Vector2.ZERO,Vector2(234,392));hud_layers=left.get_parent();hud_layers.name="MapLayers";hud_layers.hide()
	left.add_child(label("地图图层",18))
	var names:=["地貌","坡度","风能","太阳能","水源","交通","电网","禁建"]
	var group:=ButtonGroup.new()
	var layer_grid:=GridContainer.new();layer_grid.columns=2;left.add_child(layer_grid)
	for i in range(8):
		var b:=button(names[i],func():change_layer(i);hud_layer_button.text="图层 · "+names[i];hud_layers.hide(),layer_grid);b.toggle_mode=true;b.button_group=group;b.button_pressed=i==0;b.tooltip_text=descriptions[i];b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;layer_buttons.append(b)
	layer_hint=label(descriptions[0],13);layer_hint.custom_minimum_size.x=216;layer_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;layer_hint.max_lines_visible=4;layer_hint.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;left.add_child(layer_hint)
	var selection_strip:=make_panel(root,Vector2.ZERO,Vector2(1000,46));hud_context=selection_strip.get_parent();hud_context.name="ContextToolbar"
	var selection_row:=HBoxContainer.new();selection_strip.add_child(selection_row)
	interaction_caption=label("单击选择 · 拖动移动 · 双击厂站进入",13);interaction_caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;interaction_caption.max_lines_visible=2;interaction_caption.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;interaction_caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL;selection_row.add_child(interaction_caption)
	quick_station_enter=button("进入厂站 →",func():self.open_station(self.selected_id),selection_row);quick_station_enter.action_mode=BaseButton.ACTION_MODE_BUTTON_PRESS;quick_station_enter.visible=false
	for command in [["select","选择 / Esc"],["move","移动"],["link","连线"]]:
		var b:=button(command[1],set_mode.bind(command[0]),selection_row);b.name="Tool_"+command[0];b.toggle_mode=true;hud_actions[command[0]]=b
	hud_actions.parameters=button("参数",func():open_parameters(false),selection_row)
	hud_actions.undo=button("撤销",undo,selection_row)
	# Nonmodal, default-collapsed icon navigation. Hidden panels never cover the map.
	var dock = load("res://scripts/side_dock.gd").new();root.add_child(dock);hud_dock=dock
	var right:VBoxContainer = dock.create_panel("energy", "能源运行")
	var rt:=HBoxContainer.new();right.add_child(rt);var title:=label("当前设备与网络",14);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rt.add_child(title);button("参数",func():open_parameters(false),rt)
	status_label=label("",14);right.add_child(status_label)
	var net:=PanelContainer.new();right.add_child(net);net.add_theme_stylebox_override("panel",UITheme.panel(UITheme.RAISED,8,6));metric(net,"net","净外送 NET","MW",true)
	metric(right,"generated","实际发电","MW");metric(right,"curtailed","限发 / 弃电","MW");metric(right,"loss","网络损耗","MW");metric(right,"energy","累计外送","MWh")
	metric(right,"served","负荷实供","MW");metric(right,"unserved","负荷缺供","MW")
	var power:=fold(right,"功率与能量分项");metric(power,"charge","电池充电","MW");metric(power,"discharge","电池放电","MW");metric(power,"storage_loss","储能内部损耗","MW");metric(power,"available","可用发电","MW");metric(power,"balance","功率守恒差","MW");metric(power,"energy_balance","电量守恒差","MWh");power.add_child(label("外网仅接收 ≤4 MW，无隐含进口\n有功容量流教学模型，非交流潮流\n优先：负荷 → 电池充电 → 外送\n缺口调用电池；同级按设备 ID",13))
	speed_control=load("res://scripts/speed_control.gd").new();right.add_child(speed_control)
	speed_control.speed_changed.connect(set_simulation_speed)
	speed_control.set_speed(speed)
	var action:=HBoxContainer.new();right.add_child(action);button("连接",set_mode.bind("link"),action);button("出线",open_line_settings,action);button("取消",set_mode.bind("select"),action);line_toggle=button("实体线",func():physical_lines=not physical_lines;rebuild_cables();update_status(),action)
	selection_label=label("未选择设备",20);right.add_child(selection_label)
	station_enter_button=button("进入电热站内部",func():self.open_station(self.selected_id),right);station_enter_button.action_mode=BaseButton.ACTION_MODE_BUTTON_PRESS;station_enter_button.visible=false
	device_picker=OptionButton.new();device_picker.fit_to_longest_item=false;right.add_child(device_picker);device_picker.item_selected.connect(func(i):select_device(int(device_picker.get_item_metadata(i))))
	device_summary=label("点击地图设备或从清单选择",15);device_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;right.add_child(device_summary)
	metric(right,"device_available","可用出力","MW");metric(right,"device_sent","实际送出","MW")
	var tech:=fold(right,"技术详情");source_label=label("",14);source_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;tech.add_child(source_label);metric(tech,"device_curtail","设备限发","MW");button("连接外部电网",func():link_to(-1),tech);button("编辑设备参数",func():open_parameters(false),tech)
	var edit_row:=HBoxContainer.new();right.add_child(edit_row);button("移动",set_mode.bind("move"),edit_row);button("拆除",remove_selected,edit_row);button("撤销",undo,edit_row)
	thermal_network_summary=label("",14);thermal_network_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;right.add_child(thermal_network_summary)
	thermal_detail=label("",14);thermal_detail.name="ThermalDeviceSummary";thermal_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;tech.add_child(thermal_detail)
	right.move_child(thermal_network_summary,8)
	dimension_summary=label("",13);dimension_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;tech.add_child(dimension_summary)
	button("校验并迁移为米制（不缩放原坐标）",request_metric_migration,tech)
	var fuel_panel:VBoxContainer = dock.create_panel("fuel", "燃料资源 · 天然气")
	make_fuel_resource_ui(fuel_panel)
	var demand:VBoxContainer = dock.create_panel("demand", "用电 / 用热需求")
	var demand_info:=label("电/热需求是外部任务，不是可建设备。接入点仅为网络标记，不代表工厂或居民区。",14);demand_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;demand.add_child(demand_info)
	button("添加需求接入点",start_demand_node,demand)
	button("添加热需求接入点（70/40°C）",start_heat_demand_node,demand)
	demand_picker=OptionButton.new();demand_picker.fit_to_longest_item=false;demand_picker.name="DemandPicker";demand.add_child(demand_picker)
	demand_picker.item_selected.connect(func(i):select_device(int(demand_picker.get_item_metadata(i))))
	button("编辑所选需求",edit_selected_demand,demand)
	button("移除所选需求接入点",func():
		if not device(selected_id).get("kind","") in ["load","heat_demand"]:tell("请先选择需求节点。");return
		remove_selected(),demand)
	button("连接需求节点",func():
		if not device(selected_id).get("kind","") in ["load","heat_demand"]:tell("请先从需求清单选择一个需求节点。");return
		set_mode("link");link_to(selected_id),demand)
	demand_summary=label("",14);demand_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;demand.add_child(demand_summary)
	var demand_scope:=label("电需求恒定 MW；热需求恒定 MWth，可设置优先级。当前热需求不支持CSV导入；没有隐含电网进口。
逐时需求、实供和缺供曲线在调度优化中查看；节点与旧存档仍兼容。",14);demand_scope.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;demand.add_child(demand_scope)
	button("查看需求与缺供曲线",func():
		if is_instance_valid(optimization_controller):optimization_controller.open(),demand)
	var location:VBoxContainer = dock.create_panel("location", "位置与时间")
	climate_panel=load("res://scripts/climate_panel.gd").new();location.add_child(climate_panel)
	climate_panel.set_config(climate_config)
	climate_panel.apply_requested.connect(func(candidate):ask("应用新气候设置并重置模拟时间及累计电量？设备、电池当前储能和CSV保留，可撤销。CSV相对时间按新起点对齐。",apply_climate.bind(candidate)))
	location.add_child(HSeparator.new());location.add_child(label("选中地块",17))
	detail=label("点击地图可查看本地坐标与场地初筛。",13);detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;location.add_child(detail)
	var weather:VBoxContainer = dock.create_panel("weather", "气象与资源")
	var weather_info:=label("未绑定出力字段使用所选教学情景。位置和日历计算太阳位置，不能生成真实当地天气。地图资源图层仍是空间示意。\n\n输入优先级：设备直接功率 → 设备专属气象 → 全局气象 → 未绑定字段的内置天气。",14);weather_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;weather.add_child(weather_info)
	button("导入气象 / 功率 CSV",open_import,weather);button("查看 / 移除数据来源",open_data_manager,weather)
	weather_effects_toggle=CheckButton.new();weather_effects_toggle.text="地图天气表现（轻量）";weather_effects_toggle.button_pressed=weather_effects_enabled;weather.add_child(weather_effects_toggle)
	weather_effects_toggle.tooltip_text="太阳/环境光与风线来自同一模拟气象；视觉不参与能量计算。夜间保留可读补光，风机旋转仅为示意，不代表功率。关闭恢复原地图光照。"
	weather_effects_toggle.toggled.connect(func(enabled):weather_effects_enabled=enabled;update_status())
	weather.add_child(HSeparator.new());weather.add_child(label("资源边界 · 只读说明",17))
	var resource_info:=label("非聚光太阳能集热仅使用全局POA与环境温度，不支持设备绑定或直接热功率。POA为声明的固定倾斜面教学等效辐照，非DNI，不重复转置。槽式聚光使用独立全局DNI；缺DNI CSV时仍为太阳高度与云量合成教学DNI，POA不能替代。\n\nCSV 可输入风速、等效面上POA、直接法向DNI、温度、云量、雨强或设备可用功率；空值拒绝，不外推。导入气象未含云雨则对应状态未知。当前未读取 wind_height_m，不能自动将10米风速转到轮毂；PV冷却复用相应风速是教学假设。\n\n地图水源、交通与燃料边界标记仍是场地示意。天然气热水锅炉使用右侧独立燃料资源设置，有限共享供给并计量辅机电；没有气网压力、水量、煤炭、蒸汽或氢调度。\n\n外部电网仅接收全场最多 4 MW，不进口电力。",14);resource_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;weather.add_child(resource_info)
	var storage:VBoxContainer = dock.create_panel("templates", "模板与场景")
	storage.add_child(label("可编辑 · 新建设备默认值",17));button("新建设备模板",func():open_parameters(true),storage)
	var template_info:=label("参数模板只影响之后新建的设备，不会批量改动已有设备。",14);template_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;storage.add_child(template_info)
	storage.add_child(HSeparator.new());storage.add_child(label("可载入 · 教学示例",17))
	button("塔式熔盐昼夜发电示例 · 1600 m²",func():ask("替换为100镜塔站、0.5MWh熔盐储热及闭式蒸汽循环？自动教学昼夜天气，风机与电池供辅机，可撤销。",tower_example),storage)
	button("槽式蒸汽发电示例 · 闭式循环",func():ask("替换为槽式导热油、储热、蒸汽发生器、汽轮发电机、冷凝器和给水泵闭环？外部风光提供预热后运行辅电，可撤销。",rankine_example),storage)
	button("槽式聚光示例 · 69.24 m²",func():ask("替换为300/200°C导热油、储热和两级换热链？25 kW需求；可撤销。",trough_example),storage)
	button("太阳能集热示例 · 30.3 m²",func():ask("替换为30.3 m²非聚光真空管集热、储热与换热链？约十几kW教学尺度，可撤销。",solar_example),storage)
	button("电热完整链示例",func():ask("替换为风光供电、锅炉、储热、换热器与独立热需求？可撤销。",thermal_example),storage)
	button("燃气＋电热联合示例",func():ask("替换为燃气/电热水锅炉联合供热链，并启用1.5 MW(LHV)天然气供给？热值10 kWh/Nm³、价格300元/MWh为教学假设。可撤销。",fuel_example),storage)
	button("源网荷储示例",func():ask("替换为风光、负荷和电池示例？可撤销。",storage_example),storage)
	button("4 MW 外送示例",func():ask("替换当前场景为风光 + 变电站示例？可撤销。",example),storage)
	var scene_info:=label("示例会替换当前场景，确认后执行，可撤销。资源与气象模板库尚未实现。",14);scene_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;storage.add_child(scene_info)
	storage.add_child(HSeparator.new());storage.add_child(label("本地存档",17))
	var sav:=HBoxContainer.new();storage.add_child(sav);slot=OptionButton.new();sav.add_child(slot)
	for i in range(3):slot.add_item("存档 %d"%(i+1))
	button("保存",func():ask("保存到槽 %d？已有存档会被覆盖。"%(slot.selected+1),save_slot),sav);button("读取",func():ask("读取槽 %d并替换当前场景？可撤销。"%(slot.selected+1),load_slot),sav)
	var optimize:VBoxContainer = dock.create_panel("optimization", "调度优化")
	var optimize_info:=label("GLPK 独立预测任务\n\n冻结当前设备容量、网络与库存，在指定时段内优化调度。结果仅用于时序查看和基线比较，不写回实时场景。\n\n这是有功容量流教学模型，不是 AC 潮流、扩建规划或经过校准的生产调度。",14);optimize_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;optimize.add_child(optimize_info)
	button("GLPK 运行优化与时序图",func():
		if is_instance_valid(optimization_controller):optimization_controller.open()
		else:tell("优化控制器尚未就绪。"),optimize)
	button("导出优化快照（未求解）",export_optimization_snapshot,optimize)
	for region in dock.get_hit_regions():ui_regions.append(region)
	var bar:=make_panel(root,Vector2.ZERO,Vector2(1400,90));hud_build=bar.get_parent();hud_build.name="ConstructionShelf"
	var build_scroll:=ScrollContainer.new();build_scroll.name="ConstructionScroll";build_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;build_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;bar.add_child(build_scroll)
	var br:=HBoxContainer.new();build_scroll.add_child(br);br.add_theme_constant_override("separation",7);br.add_child(label("建\n造",15))
	var short_names={"wind":"风机","pv":"光伏","station":"变电站","battery":"电池","thermal_station":"电热站","tower_station":"熔盐塔站","tower_station_preview":"塔站预览"}
	for k in BUILDABLE_KINDS:
		var b:=button(short_names[k],start_build.bind(k),br);b.tooltip_text=DEVICE_NAMES.get(k,k)+" · 点击后在场地放置，Esc取消";b.icon=icon_texture(k);b.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER;b.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP;b.custom_minimum_size=Vector2(98,66);b.toggle_mode=true;b.expand_icon=true;b.add_theme_constant_override("icon_max_width",30);tool_buttons[k]=b
	var bc:=VBoxContainer.new();br.add_child(bc);bc.custom_minimum_size.x=170;fleet_count=label("0 台 · 0 条线",13);bc.add_child(fleet_count)
	var footer:=make_panel(root,Vector2.ZERO,Vector2(1400,54));hud_footer=footer.get_parent();hud_footer.name="WorkspaceStatus"
	var footer_row:=HBoxContainer.new();footer.add_child(footer_row)
	mode_label=label("",12);mode_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;mode_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;footer_row.add_child(mode_label)
	notice=label("选择设备查看详情；建设与连线操作可随时按 Esc 取消。",12);notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;notice.max_lines_visible=1;notice.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;footer.add_child(notice)
	add_child(confirmation);confirmation.theme=theme;confirmation.add_theme_stylebox_override("panel",UITheme.panel());confirmation.ok_button_text="确认";confirmation.cancel_button_text="取消";confirmation.title="确认操作";confirmation.dialog_autowrap=true;confirmation.min_size=Vector2i(550,150);confirmation.confirmed.connect(func():if confirm_action.is_valid():confirm_action.call())
	import_dialog=ImportUI.new();add_child(import_dialog);import_dialog.theme=theme;import_dialog.applied.connect(apply_import)
	make_parameter_dialog(theme);make_data_dialog(theme);make_line_dialog(theme)
	station_interior=load("res://scripts/station_interior.gd").new();add_child(station_interior);station_interior.setup(self)
	station_port_dialog=ConfirmationDialog.new();add_child(station_port_dialog);station_port_dialog.theme=theme;station_port_dialog.title="选择厂站边界端口";station_port_dialog.min_size=Vector2i(500,160)
	station_port_picker=OptionButton.new();station_port_dialog.add_child(station_port_picker);station_port_picker.position=Vector2(20,45);station_port_picker.size=Vector2(460,45)
	station_port_dialog.confirmed.connect(func():
		if station_port_picker.item_count>0:link_to(int(station_port_picker.get_item_metadata(station_port_picker.selected))))
	modal_shade=ColorRect.new();root.add_child(modal_shade);modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);modal_shade.color=Color(0.025,0.045,0.07,0.58);modal_shade.visible=false

	root.resized.connect(_layout_workspace)
	call_deferred("_layout_workspace")

func _layout_workspace():
	if not is_instance_valid(hud_root):return
	var extent:=hud_root.size
	var w:=maxf(1000.0,extent.x)
	var h:=maxf(700.0,extent.y)
	hud_header.position=Vector2(12,10);hud_header.size=Vector2(w-24,76)
	hud_views.position=Vector2(12,96);hud_views.size=Vector2(464,46)
	hud_layers.position=Vector2(12,164);hud_layers.size=Vector2(244,328)
	var footer_height:=maxf(54,hud_footer.get_combined_minimum_size().y)
	var build_height:=maxf(90,hud_build.get_combined_minimum_size().y)
	var context_height:=maxf(60,hud_context.get_combined_minimum_size().y)
	var footer_y:=h-6-footer_height
	var build_y:=footer_y-6-build_height
	var context_y:=build_y-6-context_height
	hud_context.position=Vector2(12,context_y);hud_context.size=Vector2(w-24,context_height)
	hud_build.position=Vector2(12,build_y);hud_build.size=Vector2(w-24,build_height)
	hud_footer.position=Vector2(12,footer_y);hud_footer.size=Vector2(w-24,footer_height)
	weather_orb.position=Vector2(w-74,94)
	hud_brand_subtitle.visible=w>=1180
	if is_instance_valid(hud_dock):hud_dock.call("_layout")

func ask(message:String,action:Callable):
	confirm_action=action;confirmation.dialog_text=message;confirmation.popup_centered()

func tell(t:String):
	if is_instance_valid(notice):notice.text=t;notice.tooltip_text=t

func set_mode(value:String):
	if value=="move" and device(selected_id).has("parent_station_id"):selected_id=int(device(selected_id).parent_station_id)
	drag_candidate=-2;drag_active=false
	mode=value;pending_link=-2;clear_link_preview();clear_ghost();update_status()
	if mode=="move":
		var d:=device(selected_id)
		if not station(selected_id).is_empty():
			ghost=load("res://scripts/station_facade.gd").new();equipment.add_child(ghost);ghost.setup(visual_station(station(selected_id)));ghost.set_preview(false);return
		if d.is_empty():mode="select";tell("先选择要移动的设备。");update_status();return
		ghost=Visual.create(d.kind,visual_params(d.params),true);equipment.add_child(ghost);ghost.set_preview(false)

func start_demand_node():
	start_build("load")
	tell("设置外部需求接入点；这是需求标记，不是建设工厂。Esc取消。")

func edit_selected_demand():
	if not device(selected_id).get("kind","") in ["load","heat_demand"]:tell("请先从需求清单选择一个需求节点。");return
	open_parameters(false)

func start_build(kind:String):
	if dimension_profile=="metric_v1" and footprint(kind,templates.get(kind,{}))>65.0:
		tell("此容量所需模块与检修占地超过基地短边，请降低容量或另选模板。");return
	if kind in FACILITY_KINDS:
		if kind in ["tower_station","tower_station_preview"] and dimension_profile!="metric_v1":tell("塔式预览需要米制尺寸；请先显式迁移米制。");return
		build_kind=kind;set_mode("build");ghost=load("res://scripts/station_facade.gd").new();equipment.add_child(ghost);ghost.setup({"id":0,"kind":kind,"name":DEVICE_NAMES[kind],"visual_dimension_profile":dimension_profile});ghost.set_preview(false);return
	if kind in INTERNAL_KINDS:
		tell("请进入电热站内部建设此设备。");return
	build_kind=kind;set_mode("build")
	ghost=Visual.create(kind,visual_params(templates[kind]),true);equipment.add_child(ghost);ghost.set_preview(false)

func clear_ghost():
	if is_instance_valid(ghost):ghost.queue_free()
	ghost=null
	if is_instance_valid(placement_outline):placement_outline.queue_free()
	placement_outline=null;placement_key="";feedback_key=""

func device(id:int)->Dictionary:
	for d in devices:
		if int(d.id)==id:return d
	return {}

func footprint(kind:String,params:Dictionary={})->float:
	if dimension_profile=="metric_v1":return float(Spatial.profile(kind,params).clearance_radius_world)
	if kind=="thermal_station":return 8.0
	return maxf(7.0,float(params.get("rotor_diameter_m",126.0))*0.05+0.7) if kind=="wind" else Visual.footprint(kind)

func can_place(kind:String,p:Vector2,ignore_id:int=-2,params:Dictionary={})->String:
	if kind in ["tower_station","tower_station_preview"] and dimension_profile!="metric_v1":return "塔式预览需要米制尺寸"
	if not is_finite(p.x) or not is_finite(p.y):return "场地坐标必须是有限数值"
	var radius:=footprint(kind,params if not params.is_empty() else templates.get(kind,{}))
	if absf(p.x)>95-radius or absf(p.y)>65-radius:return "超出场地边界"
	for off in [Vector2.ZERO,Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
		var q:Vector2=p+off
		if exclusion(q.x,q.y)!="":return exclusion(q.x,q.y)
		if slope_at(q.x,q.y)>float(cfg.max_build_slope_degrees):return "地块坡度超过 8°"
	for d in devices:
		if not d.has("parent_station_id") and int(d.id)!=ignore_id and p.distance_to(Vector2(d.x,d.z))<radius+footprint(d.kind,d.params):return "与设备占地重叠"
	for facility in stations:
		if int(facility.id)!=ignore_id and p.distance_to(Vector2(facility.x,facility.z))<radius+footprint(str(facility.get("kind","thermal_station"))):return "与厂站占地重叠"
	return ""

func add_equipment(kind:String,p:Vector2,record:bool=true)->bool:
	if not kind in FACILITY_KINDS and devices.size()>=SaveValidator.MAX_DEVICES:tell("设备数量已达1024上限。");return false
	if not kind in FACILITY_KINDS and next_id>SaveValidator.MAX_ID:tell("设备ID已用尽。");return false
	if kind in FACILITY_KINDS:return add_station(p,record,kind)
	var error:=can_place(kind,p)
	if error!="":tell(error);return false
	if record:checkpoint()
	while not station(next_id).is_empty():next_id+=1
	var added:={"id":next_id,"kind":kind,"x":p.x,"z":p.y,"params":templates[kind].duplicate(true),"state":Catalog.initial_state(kind,templates[kind])}
	if kind in THERMAL_KINDS:added["model_profile"]=Catalog.model_profile(kind)
	devices.append(added)
	selected_id=next_id;next_id+=1;normalize_id_cursors();rebuild_equipment();refresh();return true

func rebuild_equipment():
	clear_ghost()
	for n in nodes.values():n.queue_free()
	nodes.clear()
	for n in station_nodes.values():n.queue_free()
	station_nodes.clear()
	for facility in stations:
		var facade=load("res://scripts/station_facade.gd").new();equipment.add_child(facade);facade.setup(visual_station(facility));facade.position=Vector3(facility.x,height_at(facility.x,facility.z)+0.15,facility.z);facade.set_selected(int(facility.id)==selected_id);station_nodes[str(int(facility.id))]=facade
	for d in devices:
		if d.has("parent_station_id"):continue
		var n=Visual.create(d.kind,visual_params(d.params),true);equipment.add_child(n);n.set_operating(0.0);n.position=Vector3(d.x,height_at(d.x,d.z)+0.15,d.z)
		n.set_highlight(int(d.id)==selected_id);nodes[str(int(d.id))]=n
		var title:=Label3D.new();title.text="%s #%d"%[DEVICE_NAMES[d.kind],int(d.id)]
		title.font=font_full;title.name="DeviceTitle";title.font_size=28;title.pixel_size=0.006;title.fixed_size=true;title.no_depth_test=false;title.billboard=BaseMaterial3D.BILLBOARD_ENABLED;title.modulate=Color("233e32");title.outline_size=5;title.outline_modulate=Color("edf3e7");title.position.y=15 if d.kind=="wind" else (1.2 if d.kind=="thermal_store" else 0.8) if dimension_profile=="metric_v1" else 5.3 if d.kind=="thermal_store" else 4.4 if d.kind in THERMAL_KINDS else 4;n.add_child(title)
		if d.kind in THERMAL_KINDS:continue
		var port_mark:=Label3D.new();port_mark.name="PortIndicator";port_mark.text="◉";port_mark.font=font_full;port_mark.font_size=32;port_mark.pixel_size=0.005;port_mark.fixed_size=true;port_mark.no_depth_test=false;port_mark.billboard=BaseMaterial3D.BILLBOARD_ENABLED;port_mark.outline_size=6;port_mark.outline_modulate=Color("eef5e8");port_mark.position=n.port_local+Vector3(0,0.1 if dimension_profile=="metric_v1" else 1.0,0);n.add_child(port_mark)
	rebuild_cables()

func endpoint(id:int,port_id:String="")->Vector3:
	if id==-1:return Vector3(87,height_at(87,3)+5,3)
	var child:=device(id)
	if child.has("parent_station_id"):
		var key:=str(int(child.parent_station_id))
		if station_nodes.has(key):return station_nodes[key].get_port_position("ac_out" if child.kind=="steam_turbine" else "ac_in" if child.kind in ["solar_tower_receiver","molten_salt_store","salt_steam_generator","electric_boiler","fuel_boiler","solar_thermal","parabolic_trough","oil_water_exchanger","steam_generator","steam_condenser","feedwater_pump"] else "heat_out")
	if station_nodes.has(str(id)):return station_nodes[str(id)].get_port_position("ac_in")
	if nodes.has(str(id)) and port_id!="" and nodes[str(id)].has_method("get_named_port_position") and nodes[str(id)].has_named_port(port_id):return nodes[str(id)].get_named_port_position(port_id)
	return nodes[str(id)].port_global() if nodes.has(str(id)) else Vector3.ZERO

func rebuild_cables():
	for n in cables.get_children():n.queue_free()
	for l in links:
		if same_internal_station(int(l.from),int(l.to)):continue
		var n=Visual.create_line(endpoint(int(l.from),str(l.get("from_port",""))),endpoint(int(l.to),str(l.get("to_port",""))),physical_lines,int(l.from)==selected_id or int(l.to)==selected_id);cables.add_child(n)
		if l.get("carrier","")in ["heat_water","heat_oil","heat_salt"] and (int(l.from)==selected_id or int(l.to)==selected_id):
			var tag:=Label3D.new();tag.text="热90/60" if l.get("grade_id","")=="hw_primary_90_60" else "热70/40";tag.font=font_full;tag.font_size=24;tag.pixel_size=0.005;tag.fixed_size=true;tag.no_depth_test=false;tag.billboard=BaseMaterial3D.BILLBOARD_ENABLED;tag.modulate=Color("e9b47b");tag.position=(endpoint(int(l.from),str(l.from_port))+endpoint(int(l.to),str(l.to_port)))*0.5+Vector3(0,1.5,0);cables.add_child(tag);Visual.fit_screen_label(tag,camera,18)

func nearest(pos:Vector2)->int:
	var best:=42.0;var found:=-2
	for d in devices:
		if d.has("parent_station_id"):continue
		if camera.is_position_behind(endpoint(int(d.id))):continue
		var screen:=camera.unproject_position(endpoint(int(d.id)))
		var dist:=screen.distance_to(pos)
		if dist<best:best=dist;found=int(d.id)
		for port in Catalog.ports(d.kind):
			dist=camera.unproject_position(endpoint(int(d.id),port.id)).distance_to(pos)
			if dist<best:best=dist;found=int(d.id)
	if camera.unproject_position(endpoint(-1)).distance_to(pos)<35:found=-1
	# Ports stay easy to click; selection mode also accepts visible equipment bodies.
	if found==-2:
		var ray_origin:=camera.project_ray_origin(pos)
		var ray_direction:=camera.project_ray_normal(pos)
		var closest:=INF
		for key in nodes:
			for surface in nodes[key].surfaces:
				if surface==nodes[key].selection_ring or not surface.visible:continue
				var inverse:Transform3D=surface.global_transform.affine_inverse()
				var hit=surface.mesh.get_aabb().intersects_ray(inverse*ray_origin,inverse.basis*ray_direction)
				if hit!=null:
					var separation:float=ray_origin.distance_to(surface.global_transform*hit)
					if separation<closest:closest=separation;found=int(key)
	for key in station_nodes:
		if camera.is_position_behind(station_nodes[key].global_position):continue
		for port_name in station_nodes[key].named_port_locals.keys():
			var distance_to_port:float=camera.unproject_position(station_nodes[key].get_port_position(port_name)).distance_to(pos)
			if distance_to_port<best:best=distance_to_port;found=int(key)
	if found==-2:
		var origin:=camera.project_ray_origin(pos);var direction:=camera.project_ray_normal(pos);var closest:=INF
		for key in station_nodes:
			for surface in station_nodes[key].surfaces:
				if surface==station_nodes[key].selection_ring or not surface.visible:continue
				var inverse:Transform3D=surface.global_transform.affine_inverse()
				var hit=surface.mesh.get_aabb().intersects_ray(inverse*origin,inverse.basis*direction)
				if hit!=null:
					var separation:float=origin.distance_to(surface.global_transform*hit)
					if separation<closest:closest=separation;found=int(key)
	return found

func select_device(id:int):
	selection.visible=id<0
	if mode=="move" and id!=selected_id:set_mode("select")
	selected_id=id
	for key in nodes:nodes[key].set_highlight(int(key)==id)
	for key in station_nodes:station_nodes[key].set_selected(int(key)==int(device(id).get("parent_station_id",id)))
	rebuild_cables();update_status()

func link_to(id:int):
	if not station(id).is_empty():choose_station_port(id);return
	if mode!="link":
		if selected_id>=0 and device(selected_id).get("kind","")=="station":pending_link=selected_id
		else:tell("先选变电站，或用端口连线选择两端。");return
	if pending_link==-2:
		if id<0:tell("请先点击设备端口。");return
		pending_link=id;select_device(id);tell("已选 #%d，再点另一设备；端口按类型和温区连接。"%id);return
	var candidate:=connection_candidate(pending_link,id)
	if candidate.is_empty():tell("不能连接：电/热端口或温区不匹配；90/60热须经过换热器才能供70/40需求。");return
	var error:String=Catalog.validate_link(devices,links,candidate)
	if error!="":tell("未连接："+error);return
	checkpoint();links.append(candidate);pending_link=-2;clear_link_preview();refresh();rebuild_cables();tell("连接完成；容量、损耗和真实连通关系已计入。")

func move_selected(p:Vector2)->bool:
	if device(selected_id).has("parent_station_id"):
		tell("站内设备请在厂站内部移动。");return false
	if not station(selected_id).is_empty():return move_station(selected_id,p)
	var d:=device(selected_id)
	if d.is_empty():tell("先选择要移动的设备。");return false
	var error:=can_place(d.kind,p,selected_id,d.params)
	if error!="":tell(error);return false
	if Vector2(float(d.x),float(d.z)).is_equal_approx(p):set_mode("select");return true
	checkpoint();d.x=p.x;d.z=p.y;rebuild_equipment();refresh();set_mode("select");return true

func remove_selected():
	if device(selected_id).has("parent_station_id"):
		open_station(int(device(selected_id).parent_station_id));tell("请在站内选择并拆除内部设备。");return
	if not station(selected_id).is_empty():
		ask("拆除整个电热站及内部设备、库存与所有关联线路？可撤销。",remove_station.bind(selected_id));return
	if device(selected_id).is_empty():tell("先选中设备。");return
	ask(("移除需求接入点 #%d 及关联线路？可撤销。" if device(selected_id).kind in ["load","heat_demand"] else "拆除 #%d 及关联线路和绑定数据？可撤销。")%selected_id,func():
		checkpoint();devices=devices.filter(func(d):return int(d.id)!=selected_id)
		links=links.filter(func(l):return int(l.from)!=selected_id and int(l.to)!=selected_id)
		imports=imports.filter(func(s):return str(s.target_device)!=str(selected_id))
		selected_id=-2;set_mode("select");rebuild_equipment();refresh())

func state()->Dictionary:
	var saved_templates:Dictionary=templates.duplicate(true)
	var saved_energy:Dictionary=ENERGY_ZERO.duplicate(true);saved_energy.merge(energy,true)
	for kind in KINDS:
		if not saved_templates.has(kind):saved_templates[kind]=model.defaults(kind).duplicate(true)
	return {"schema":12,"model_version":21,"tower_energy":tower_energy.duplicate(true),"rankine_energy":rankine_energy.duplicate(true),"high_temp_energy":high_temp_energy.duplicate(true),"solar_energy":solar_energy.duplicate(true),"fuel_supply":fuel_supply.duplicate(true),"fuel_energy":fuel_energy.duplicate(true),"dimension_profile":dimension_profile,"stations":stations.duplicate(true),"next_station_id":next_station_id,"rebuild":true,"devices":devices.duplicate(true),"links":links.duplicate(true),"templates":saved_templates,"imports":imports.duplicate(true),"next_id":next_id,"elapsed_s":elapsed_s,"energy":saved_energy,"thermal_energy":thermal_energy.duplicate(true),"physical_lines":physical_lines,"climate_config":climate_config.duplicate(true),"weather_effects_enabled":weather_effects_enabled}

func checkpoint():
	scene_revision+=1
	undo_states.append(state());if undo_states.size()>40:undo_states.pop_front()

func restore(s:Dictionary):
	dimension_profile=str(s.get("dimension_profile","legacy_illustrative"))
	fuel_supply=s.get("fuel_supply",FuelSupply.defaults()).duplicate(true)
	fuel_energy=s.get("fuel_energy",FuelSupply.initial_energy()).duplicate(true)
	high_temp_energy=s.get("high_temp_energy",HighTemp.initial_energy()).duplicate(true)
	rankine_energy=s.get("rankine_energy",Rankine.initial_energy()).duplicate(true)
	tower_energy=s.get("tower_energy",Tower.initial_energy()).duplicate(true)
	solar_energy=s.get("solar_energy",SOLAR_ENERGY_ZERO).duplicate(true)
	sync_fuel_resource_form()
	stations=s.get("stations",[]).duplicate(true);next_station_id=int(s.get("next_station_id",1000000))
	if is_instance_valid(station_interior):station_interior.hide()
	devices=s.devices.duplicate(true);links=s.links.duplicate(true);templates=s.templates.duplicate(true);imports=s.imports.duplicate(true);next_id=int(s.next_id);elapsed_s=float(s.elapsed_s);energy=s.energy.duplicate(true);thermal_energy=s.get("thermal_energy",THERMAL_ENERGY_ZERO).duplicate(true);physical_lines=bool(s.physical_lines)
	while not device(next_station_id).is_empty() or (next_station_id==next_id and next_station_id<=SaveValidator.MAX_ID):next_station_id+=1
	climate_config=s.get("climate_config",align_iso_origin(imports,Climate.defaults())).duplicate(true)
	weather_effects_enabled=bool(s.get("weather_effects_enabled",true))
	if is_instance_valid(climate_panel):climate_panel.set_config(climate_config)
	for kind in KINDS:
		if not templates.has(kind):templates[kind]=model.defaults(kind).duplicate(true)
	for key in ENERGY_ZERO:
		if not energy.has(key):energy[key]=0.0
	for d in devices:
		if d.kind in ["battery","thermal_store","high_temp_store"] and not d.has("state"):d.state=Catalog.initial_state(d.kind,d.params)
	scene_revision+=1;dispatch_dt_s=1.0
	paused=true;speed=1.0;accumulator=0;selected_id=-2;set_mode("select");rebuild_equipment();refresh()

func undo():
	if undo_states.is_empty():tell("没有可撤销的操作。");return
	restore(undo_states.pop_back());tell("已撤销；模拟暂停，避免意外继续累计。")

func validate_state(s:Variant)->String:
	var error:=SaveValidator.validate(s)
	if error!="":return error
	var origin_error:=iso_origin_error(s.imports)
	if origin_error!="":return origin_error
	if s.has("climate_config"):
		var climate_error:=Climate.validate(s.climate_config)
		if climate_error!="":return "气候设置无效："+climate_error
		if align_iso_origin(s.imports,s.climate_config).start_local!=s.climate_config.start_local:return "气候日历与ISO UTC数据原点不一致。"
	if s.has("weather_effects_enabled") and not s.weather_effects_enabled is bool:return "天气特效开关必须为布尔值。"
	for d in s.devices:
		if d.has("parent_station_id"):continue
		var radius:=SaveValidator.radius(d.kind,d.params,str(s.get("dimension_profile","legacy_illustrative")))
		for off in [Vector2.ZERO,Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
			var q:Vector2=Vector2(d.x,d.z)+off
			if exclusion(q.x,q.y)!="":return "存档设备位于禁建区："+exclusion(q.x,q.y)
			if slope_at(q.x,q.y)>float(cfg.max_build_slope_degrees):return "存档设备坡度超限。"
	for facility in s.get("stations",[]):
		var radius:=5.0 if s.get("dimension_profile","")=="metric_v1" else 8.0
		for off in [Vector2.ZERO,Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
			var q:Vector2=Vector2(facility.x,facility.z)+off
			if exclusion(q.x,q.y)!="" or slope_at(q.x,q.y)>float(cfg.max_build_slope_degrees):return "厂站位于禁建或陡坡地块。"
	return ""

func write_save(path:String)->bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if f==null:return false
	f.store_string(JSON.stringify(state(),"  "));f.close()
	return DirAccess.rename_absolute(path+".tmp",path)==OK

func read_save(path:String)->bool:
	if not FileAccess.file_exists(path):tell("这个存档槽还没有文件。");return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path));var error:=validate_state(parsed)
	if error!="":tell("未读取："+error);return false
	checkpoint();restore(parsed);tell("读取完成；旧档保留示意比例与原坐标。请在尺寸说明中显式校验米制迁移。" if dimension_profile!="metric_v1" else "读取完成，米制尺寸与库存已恢复；无需原CSV文件。");return true

func save_slot():
	tell("已保存槽 %d（含数据与参数）"%(slot.selected+1) if write_save(save_root+"/slot%d.json"%slot.selected) else "保存失败，原存档未改动。")

func load_slot():read_save(save_root+"/slot%d.json"%slot.selected)

func weather_at(t:float)->Dictionary:
	var fraction:=0.0
	for series in imports:
		if series.get("time_mode","")=="iso_utc":
			var parsed:Dictionary=Series._parse_iso_utc(str(series.time_origin_utc))
			if parsed.ok:fraction=float(parsed.value)-floor(float(parsed.value))
			break
	return Climate.sample(climate_config,t+fraction)

func active_series(candidate:Array=imports)->Array:
	var active:Array=[]
	for series in candidate:
		var target_id:=str(series.target_device)
		# Global meteorology also drives the visible world, even with no generators.
		if target_id=="" and series.field!="power":active.append(series);continue
		if series.field=="power":
			if not device(int(target_id)).is_empty():active.append(series)
			continue
		for d in devices:
			if not d.kind in ["wind","pv"] or (d.kind=="wind" and series.field!="wind_ms"):continue
			var key:=str(int(d.id))
			if target_id!="" and target_id!=key:continue
			var overridden:=false
			for other in candidate:
				if str(other.target_device)==key and (other.field=="power" or (target_id=="" and other.field==series.field)):overridden=true;break
			if not overridden:active.append(series);break
	return active

func common_interval(candidate:Array)->Dictionary:
	var lo:=0.0;var hi:=INF
	for series in active_series(candidate):lo=maxf(lo,series.start_s);hi=minf(hi,series.end_s)
	return {"start":lo,"end":hi}

func sampled(t:float)->Dictionary:
	var weather:=weather_at(t);var direct:Dictionary={};var src:Dictionary={}
	# A field may have a global dataset and device-specific overrides. Weather per-device is applied below.
	var weather_device:Dictionary={};var err:String=str(weather.get("error",""))
	for s in active_series():
		var v:Dictionary=Series.sample(s,t)
		if v.status!="ok":err="数据 %s 在 %.1f s 无值；模拟暂停，不外推。"%[s.get("source",{}).get("name",s.field),t];break
		var target_id:=str(s.target_device)
		if s.field=="power":direct[target_id]={"mw":float(v.value)/1000.0,"source":"CSV 直接出力"}
		else:
			var key:String={"wind_ms":"wind_speed_mps","irradiance_wm2":"irradiance_wm2","dni_wm2":"dni_wm2","temp_c":"air_temp_c","cloud_cover":"cloud_cover","precipitation_mm_h":"precipitation_mm_h"}[s.field]
			if target_id=="":weather[key]=v.value;src[key]="CSV气象"
			else:
				if not weather_device.has(target_id):weather_device[target_id]={}
				weather_device[target_id][key]=v.value
	if src.has("cloud_cover") and not src.has("irradiance_wm2"):
		# Only the fallback teaching irradiance uses imported clouds; measured POA and direct power remain authoritative.
		weather.irradiance_wm2=Climate.POA_SCALE_WM2*pow(maxf(sin(deg_to_rad(float(weather.solar_altitude_deg))),0.0),0.8)*(1.0-0.95*float(weather.cloud_cover))
	if devices.any(func(d):return d.kind in ["parabolic_trough","solar_tower_receiver"]) and not src.has("dni_wm2"):
		weather.dni_wm2=Climate.teaching_dni(weather)
		src.dni_wm2="教学DNI：太阳高度与云量代理；非POA"
	if weather.has("dni_wm2") and float(weather.get("solar_altitude_deg",0))<=0:weather.dni_wm2=0.0
	if weather.has("dni_wm2"):weather.dni_source="CSV DNI" if src.get("dni_wm2","")=="CSV气象" else "教学DNI：太阳高度与云量代理；非POA"
	if src.has("air_temp_c"):
		weather.air_density_kgm3=101325.0/(287.05*(float(weather.air_temp_c)+273.15))
	if src.values().has("CSV气象"):
		# Never infer imported cloud/rain from irradiance or silently claim the teaching sky.
		for field in ["cloud_cover","precipitation_mm_h"]:
			if not src.has(field):weather.erase(field)
		weather["weather_state"]="measured_fields"
		weather["source"]="CSV全局气象；未绑定出力字段采用教学值"
	weather["time_s"]=t
	weather["field_sources"]=src.duplicate(true)
	weather["valid"]=err==""
	return {"weather":weather,"direct":direct,"device_weather":weather_device,"sources":src,"error":err}

func dispatch_inputs(t:float)->Dictionary:
	var dat:=sampled(t)
	if dat.error!="":return {"error":dat.error}
	last_weather=dat.weather;sources={}
	# Model's direct input is also used for per-device meteorology generation; never added to generated power.
	for d in devices:
		var key:=str(int(d.id));sources[key]="自定义电功率曲线" if d.kind=="wind" and not d.params.get("power_curve_kw",[]).is_empty() else "内置模型"
		if dat.direct.has(key):sources[key]="CSV 直接出力"
		elif d.kind in ["wind","pv"]:
			var w:Dictionary=dat.weather.duplicate(true)
			if dat.device_weather.has(key):w.merge(dat.device_weather[key],true)
			if (d.kind=="wind" and ((dat.sources.has("wind_speed_mps") or dat.sources.has("air_temp_c")) or dat.device_weather.get(key,{}).has("wind_speed_mps"))) or (d.kind=="pv" and (not dat.sources.is_empty() or dat.device_weather.has(key))):
				var g:Dictionary=model.generation(d.kind,d.params,w)
				dat.direct[key]={"mw":g.mw,"source":"CSV 气象 → 物理模型"};sources[key]="CSV 气象 → 自定义曲线" if d.kind=="wind" and not d.params.get("power_curve_kw",[]).is_empty() else "CSV 气象 → 物理模型"
	dat.direct["_fuel_supply"]=fuel_supply.duplicate(true)
	return dat

func solve_at(t:float)->Dictionary:
	var dat:=dispatch_inputs(t)
	if dat.error!="":return {"error":dat.error}
	var r:Dictionary=model.dispatch(devices,links,dat.weather,dat.direct,dispatch_dt_s)
	if r.get("valid",false) and devices.any(func(d):return d.kind in ["fuel_boiler","solar_thermal","parabolic_trough","oil_water_exchanger"]):
		var audit:Array=model.audit_dispatch(devices,links,r,fuel_supply,dat.weather)
		if not audit.is_empty():r.valid=false;r.errors=audit
	r["error"]="; ".join(r.get("errors",[]))
	if not r.get("valid",false) and r.error=="":r.error="; ".join(r.get("warnings",["计算未通过校验"]))
	for line in r.get("lines",[]):
		if not line.get("valid",false):r.error="无效线路："+str(line.get("reason","端口/拓扑非法"));break
	return r

func refresh():
	if not booted:return
	if is_instance_valid(weather_orb):weather_orb.reset_transition()
	var r:=solve_at(elapsed_s)
	if r.get("error","")!="":paused=true;tell(r.error)
	else:result=r
	update_status()

func advance(dt:float)->bool:
	if not is_finite(dt) or dt<0.0:paused=true;tell("模拟步长必须是有限非负秒数。");return false
	# Advance between absolute float64 boundaries; avoid subtractive residual steps.
	var target_time:float=elapsed_s+dt
	while elapsed_s<target_time:
		var next_time:float=minf(target_time,elapsed_s+1.0)
		for s in active_series():
			var sampled_value:Dictionary=Series.sample(s,elapsed_s)
			if sampled_value.status!="ok":paused=true;tell("时间不在有效数据区间，模拟暂停。");return false
			var next_index:int=int(sampled_value.index)+1
			if next_index<s.samples.size():next_time=minf(next_time,float(s.samples[next_index].t))
			next_time=minf(next_time,float(s.end_s))
		if next_time<=elapsed_s:
			paused=true
			var endpoint:=solve_at(elapsed_s)
			if endpoint.get("error","")=="":result=endpoint
			tell("已到导入序列末端；模拟暂停，不外推。");return false
		dispatch_dt_s=next_time-elapsed_s
		var r:=solve_at(elapsed_s)
		dispatch_dt_s=1.0
		if r.get("error","")!="":paused=true;tell(r.error);return false
		result=r
		var step:float=next_time-elapsed_s
		for k in energy:energy[k]+=float(r.get(k+"_mw",0))*step/3600.0
		var heat:Dictionary=r.get("thermal",{})
		for k in thermal_energy:
			if k=="storage_loss":thermal_energy[k]+=(float(heat.get("storage_conversion_loss_mwth",0))*step/3600.0+float(heat.get("self_discharge_mwhth",0)))
			else:thermal_energy[k]+=float(heat.get(k+"_mwth",0))*step/3600.0
		var solar:Dictionary=r.get("solar",{})
		for pair in [["incident_mwh","incident_mw"],["optical_rejection_mwh","optical_rejection_mw"],["thermal_loss_mwh","thermal_loss_mw"],["available_mwhth","available_mwth"],["useful_mwhth","useful_mwth"],["curtailed_mwhth","curtailed_mwth"],["auxiliary_mwh","auxiliary_electric_mw"]]:
			solar_energy[pair[0]]+=float(solar.get(pair[1],0))*step/3600.0
		var hot:Dictionary=r.get("high_temp",{})
		for pair in [["incident_mwh","incident_mw"],["optical_rejection_mwh","optical_rejection_mw"],["thermal_loss_mwh","thermal_loss_mw"],["available_mwhth","available_mwth"],["useful_mwhth","useful_mwth"],["curtailed_mwhth","curtailed_mwth"],["auxiliary_mwh","collector_auxiliary_electric_mw"],["oil_auxiliary_mwh","oil_auxiliary_electric_mw"],["oil_water_output_mwhth","oil_water_output_mwth"],["exchanger_loss_mwhth","exchanger_loss_mwth"],["charge_mwhth","charge_mwth"],["discharge_mwhth","discharge_mwth"],["storage_conversion_loss_mwhth","storage_conversion_loss_mwth"]]:
			high_temp_energy[pair[0]]+=float(hot.get(pair[1],0))*step/3600.0
		high_temp_energy.self_discharge_mwhth+=float(hot.get("self_discharge_mwhth",0))
		if hot.has("rankine_oil_input_mwth"):high_temp_energy["rankine_oil_input_mwhth"]=float(high_temp_energy.get("rankine_oil_input_mwhth",0))+float(hot.rankine_oil_input_mwth)*step/3600.0
		var tower:Dictionary=r.get("tower",{})
		for key in tower_energy:
			var field:String=key.replace("_mwhth","_mwth").replace("_mwh","_mw")
			if key=="auxiliary_mwh":field="auxiliary_electric_mw"
			if key=="receiver_auxiliary_mwh":field="receiver_auxiliary_electric_mw"
			if key=="store_auxiliary_mwh":field="store_auxiliary_electric_mw"
			if key=="self_discharge_mwhth":tower_energy[key]+=float(tower.get(key,0))
			else:tower_energy[key]+=float(tower.get(field,0))*step/3600.0
		var cycle:Dictionary=r.get("rankine",{})
		if cycle.has("salt_input_mwth") and not rankine_energy.has("salt_input_mwhth"):rankine_energy.salt_input_mwhth=0.0
		for key in rankine_energy:
			if key=="circulated_mass_kg":rankine_energy[key]+=float(cycle.get("mass_flow_kg_s",0))*step
			else:rankine_energy[key]+=float(cycle.get(key.replace("_mwhth","_mwth").replace("_mwh","_mw"),0))*step/3600.0
		var fuel:Dictionary=r.get("fuel",{})
		for pair in [["input_mwh","input_mw"],["heat_output_mwhth","heat_output_mwth"],["conversion_loss_mwh","conversion_loss_mw"],["auxiliary_mwh","auxiliary_electric_mw"],["volume_nm3","volume_nm3_per_h"],["cost","cost_per_h"]]:
			fuel_energy[pair[0]]+=float(fuel.get(pair[1],0))*step/3600.0
		for d in devices:
			if r.get("next_states",{}).has(str(int(d.id))):d.state=r.next_states[str(int(d.id))].duplicate(true)
		elapsed_s=next_time;scene_revision+=1
	var displayed:=solve_at(elapsed_s)
	if displayed.get("error","")=="":result=displayed
	return true

func set_simulation_speed(value:float)->bool:
	if not is_finite(value) or value!=floor(value) or value<1.0 or value>60.0:return false
	speed=value
	update_status()
	return true

func speed_text()->String:
	return str(int(speed))

func simulation_clock()->String:
	var whole:=int(floor(elapsed_s))
	return "%02d:%02d:%02d"%[whole/3600,(whole/60)%60,whole%60]

func toggle_run():
	if not paused:paused=true
	else:
		var r:=solve_at(elapsed_s)
		if r.get("error","")!="":tell(r.error);return
		paused=false
	update_status()

func update_status():
	if not is_instance_valid(status_label):return
	run_button.text=("▶ 运行  ×%s" if paused else "Ⅱ 暂停  ×%s")%speed_text()
	if is_instance_valid(speed_control):speed_control.set_speed(speed)
	var dat:Dictionary=sampled(elapsed_s)
	weather_snapshot=dat.weather.duplicate(true)
	visual_device_weather=dat.device_weather.duplicate(true)
	var names:Array=[]
	for key in dat.sources:names.append({"wind_speed_mps":"风速","irradiance_wm2":"辐照","air_temp_c":"温度","cloud_cover":"云量","precipitation_mm_h":"雨强"}.get(key,key))
	var origin:String=str(weather_snapshot.get("source","内置教学天气")) if names.is_empty() else "CSV全局气象："+"、".join(names)+"；未绑定出力字段用教学天气，未导入云雨为未知"
	if not dat.direct.is_empty():origin+="；设备直接导入出力优先，不由天气重算"
	if imports.any(func(series):return str(series.target_device)!="" and series.field!="power"):origin+="；设备专属气象只影响绑定设备，不代表全局实景天气"
	if dat.sources.has("precipitation_mm_h") and not dat.sources.has("irradiance_wm2"):origin+="；雨强来自CSV，辐照仍是教学值，不额外扣雨损"
	origin+="；CSV风高未映射，未自动10m→轮毂换算"
	if is_instance_valid(weather_orb):weather_orb.set_weather(weather_snapshot if dat.error=="" else {},elapsed_s,origin if dat.error=="" else "数据区间无效，已暂停；未外推")
	if is_instance_valid(climate_panel):climate_panel.set_snapshot(weather_snapshot)
	if is_instance_valid(weather_effects_toggle):weather_effects_toggle.set_pressed_no_signal(weather_effects_enabled)
	if is_instance_valid(weather_effects):weather_effects.set_weather(weather_snapshot,elapsed_s,weather_effects_enabled)
	line_toggle.text="实体线" if physical_lines else "拓扑线"
	for kind in tool_buttons:tool_buttons[kind].set_pressed_no_signal(mode=="build" and kind==build_kind)
	status_label.text="%s  ·  %s ×%s"%[simulation_clock(),"已暂停" if paused else "模拟中",speed_text()]
	if is_instance_valid(hud_clock):hud_clock.text=("● 已暂停" if paused else "● 运行中")+"\n"+simulation_clock();hud_clock.add_theme_color_override("font_color",UITheme.MUTED if paused else UITheme.ACCENT)
	for key in hud_metrics:
		var value:float=float(result.get("generated_mw",0))-float(result.get("curtailed_mw",0)) if key=="generated" else float(result.get(key+"_mw",0))
		hud_metrics[key].text="%.3f"%value
		hud_metrics[key].add_theme_color_override("font_color",UITheme.AMBER if key=="unserved" and value>0.000001 else UITheme.INK)
	for key in ["select","move","link"]:
		if hud_actions.has(key):hud_actions[key].set_pressed_no_signal(mode==key)
	if hud_actions.has("parameters"):hud_actions.parameters.disabled=device(selected_id).is_empty()
	if hud_actions.has("move"):hud_actions.move.disabled=device(selected_id).is_empty() and station(selected_id).is_empty()
	if hud_actions.has("undo"):hud_actions.undo.disabled=undo_states.is_empty()
	var vals={"net":result.get("delivered_mw",0),"generated":result.get("generated_mw",0)-result.get("curtailed_mw",0),"available":result.get("generated_mw",0),"curtailed":result.get("curtailed_mw",0),"loss":result.get("loss_mw",0),"energy":energy.delivered,"balance":result.get("balance_error_mw",0),"energy_balance":energy.generated+energy.get("discharge",0)-energy.delivered-energy.curtailed-energy.loss-energy.get("served",0)-energy.get("charge",0)-energy.get("boiler_electric",0)}
	for key in ["served","unserved","charge","discharge","storage_loss"]:vals[key]=result.get(key+"_mw",0)
	var d:=device(selected_id);var report:Dictionary=result.get("devices",{}).get(str(selected_id),{})
	vals["device_available"]=report.get("input_mw",0) if d.get("kind","")=="station" else report.get("mw",0)
	metric_names["device_available"].text="实际输入" if d.get("kind","")=="station" else "可用出力"
	vals["device_sent"]=report.get("sent_mw",0);vals["device_curtail"]=report.get("curtailed_mw",0)
	for key in vals:
		if metric_values.has(key):metric_values[key].text=("%.8f" if key in ["balance","energy_balance"] else "%.5f" if key=="energy" else "%.3f")%vals[key]
	selection_label.text="设备运行" if d.is_empty() else "%s #%d"%[DEVICE_NAMES[d.kind],selected_id]
	var signature:=str(devices.map(func(item):return [item.id,item.kind,item.get("parent_station_id",-1)]))+str(stations)
	if signature!=picker_signature:
		picker_signature=signature;device_picker.clear();device_picker.add_item("选择设备 · %d 台"%devices.size());device_picker.set_item_metadata(0,-2)
		for facility in stations:
			device_picker.add_item(str(facility.name));device_picker.set_item_metadata(device_picker.item_count-1,int(facility.id))
		for item in devices:
			if item.has("parent_station_id"):continue
			device_picker.add_item("%s #%d"%[DEVICE_NAMES[item.kind],int(item.id)]);device_picker.set_item_metadata(device_picker.item_count-1,int(item.id))
	device_picker.select(0)
	for i in range(device_picker.item_count):
		if int(device_picker.get_item_metadata(i))==selected_id:device_picker.select(i)
	device_summary.text="点击设备外观或从清单选择" if d.is_empty() else "连接 · %s\n运行 · %s\n约束 · %s"%["已有线路" if report.get("connected",false) else "未连接", "已暂停" if paused else ("输送中" if report.get("input_mw",0)>0 else "待机 / 无输入") if d.get("kind","")=="station" else ("可发电" if report.get("mw",0)>0 else "待机 / 无出力"), ("接收容量已满" if report.get("utilization",0)>=0.99999 else "接收容量有余量") if d.get("kind","")=="station" else ("未接入或容量限发" if report.get("curtailed_mw",0)>0.00001 else "当前无额外限发")]
	if d.get("kind","")=="load":
		metric_names["device_available"].text="请求功率";metric_values["device_available"].text="%.3f"%report.get("demand_mw",0)
		metric_names["device_sent"].text="负荷实供";metric_values["device_sent"].text="%.3f"%report.get("served_mw",0)
		device_summary.text="需求节点 · 优先级 %d（数值小优先）\n缺供 %.3f MW · %s"%[d.params.get("priority",1),report.get("unserved_mw",0),"已连接" if report.get("connected",false) else "孤立 / 未连线"]
	elif d.get("kind","")=="battery":
		metric_names["device_available"].text="正在充电";metric_values["device_available"].text="%.3f"%report.get("charge_mw",0)
		metric_names["device_sent"].text="正在放电";metric_values["device_sent"].text="%.3f"%report.get("discharge_mw",0)
		device_summary.text="SOC %.2f%% · %.4f / %.2f MWh\n%s · %s\nAC端效率教学假设；无免费补能"%[100.0*float(d.get("state",{}).get("energy_mwh",0))/maxf(0.000001,d.params.get("capacity_mwh",1)),d.get("state",{}).get("energy_mwh",0),d.params.get("capacity_mwh",0),{"charge":"充电","discharge":"放电","idle":"待机"}.get(report.get("mode","idle"),"待机"),"已连接" if report.get("connected",false) else "孤立 / 未连线"]
	else:metric_names["device_sent"].text="实际送出"
	source_label.text="来源：%s\n数据集 %d · 风速 %.1f m/s\n辐照 %.0f W/m²"%[sources.get(str(selected_id),"变电站网络" if d.get("kind","")=="station" else "未选择"),imports.size(),last_weather.get("wind_speed_mps",0),last_weather.get("irradiance_wm2",0)]
	if d.get("kind","")=="wind":source_label.text+="\n空气密度：实际 %.3f / 参考 %.3f kg/m³"%[last_weather.get("air_density_kgm3",1.225),d.params.get("reference_air_density_kgm3",1.225)]
	for id in nodes:
		var marker=nodes[id].get_node_or_null("PortIndicator")
		if marker:marker.modulate=Color("3a9c83") if result.get("devices",{}).get(id,{}).get("connected",false) else Color("c29a4f")
	var demands:Array=devices.filter(func(item):return item.kind in ["load","heat_demand"])
	fleet_count.text="%d设备 · %d厂站\n%d需求 · %d条线"%[devices.size()-demands.size(),stations.size(),demands.size(),links.size()]
	if is_instance_valid(demand_picker):
		var sig:=str(demands.map(func(item):return int(item.id)))
		if sig!=demand_signature or demand_picker.item_count==0:
			demand_signature=sig;demand_picker.clear();demand_picker.add_item("选择需求节点 · %d 个"%demands.size());demand_picker.set_item_metadata(0,-2)
			for item in demands:
				demand_picker.add_item("%s #%d"%[DEVICE_NAMES[item.kind],int(item.id)]);demand_picker.set_item_metadata(demand_picker.item_count-1,int(item.id))
		demand_picker.select(0)
		for i in demand_picker.item_count:
			if int(demand_picker.get_item_metadata(i))==selected_id:demand_picker.select(i)
		demand_summary.text="总需求 %.3f MW\n实供 %.3f MW · 缺供 %.3f MW"%[result.get("demand_mw",0),result.get("served_mw",0),result.get("unserved_mw",0)]
	update_thermal_display(d,report)
	update_station_display()
	update_dimension_display()
	mode_label.text="%s  ·  右键旋转 / 中键平移 / 滚轮缩放 / F1–F3视角"%{"select":"选择设备","build":"放置 "+DEVICE_NAMES.get(build_kind,build_kind),"move":"移动选中设备","link":"选择起点与终点端口"}.get(mode,mode)

func pointer_over_ui(pos:Vector2,padding:Vector2=Vector2.ZERO)->bool:
	for control in ui_regions:
		if control.is_visible_in_tree() and control.get_global_rect().grow_individual(padding.x,padding.y,padding.x,padding.y).has_point(pos):return true
	return false

func cancel_interaction():
	if mode!="select" or pending_link!=-2 or drag_active:
		set_mode("select");tell("已取消操作；设备仍在原位，未修改布局。")
	elif selected_id!=-2:
		select_device(-2);tell("已取消选择。")

func _notification(what):
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT and booted and drag_active:
		set_mode("select");tell("移动已取消：窗口失去焦点；设备保留原位。")

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				if drag_active:set_mode("select");tell("移动已取消；设备保留原位。")
				camera_drag_blocked=pointer_over_ui(event.position) or modal_visible()
			else:camera_drag_blocked=false
		if event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
			if drag_active:
				finish_drag(event.position);get_viewport().set_input_as_handled()
			drag_candidate=-2
	if event is InputEventKey and event.pressed and not event.echo and not modal_visible():
		if event.keycode==KEY_ESCAPE:cancel_interaction();get_viewport().set_input_as_handled()

func begin_drag():
	if drag_candidate<0:return
	var chosen:=drag_candidate
	var item:=station(chosen)
	if item.is_empty():item=device(chosen)
	var ground:=pick_ground(drag_origin)
	drag_offset=ground-Vector2(float(item.x),float(item.z)) if is_finite(ground.x) else Vector2.ZERO
	set_mode("move")
	drag_candidate=chosen;drag_active=mode=="move"

func finish_drag(screen_point:Vector2):
	var point:=pick_ground(screen_point)-drag_offset
	var committed:=false
	if not modal_visible() and not pointer_over_ui(screen_point) and is_finite(point.x):
		committed=move_selected(point)
	else:tell("移动已取消：请在可建设地面松开；原位置保留。")
	# Failed release is terminal, unlike the explicit click-to-place move tool.
	if not committed:set_mode("select")
	drag_candidate=-2;drag_active=false

func _unhandled_input(event):
	if modal_visible():return
	if event is InputEventMouse and pointer_over_ui(event.position):return
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE:cancel_interaction();return
		if event.ctrl_pressed and event.keycode==KEY_Z:undo();return
		if event.keycode==KEY_F:focus_selected();return
	if event is InputEventMouseMotion:
		if drag_candidate>=0 and event.button_mask&MOUSE_BUTTON_MASK_LEFT and not drag_active and event.position.distance_to(drag_origin)>6:begin_drag()
		if drag_active:return
		if camera_drag_blocked:return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var p:=pick_ground(event.position)
		if mode=="build" and is_finite(p.x):
			if add_equipment(build_kind,p):start_build(build_kind);tell("需求接入点已添加；可继续设置，Esc退出。" if build_kind in ["load","heat_demand"] else "设备已建；可继续放置，Esc 退出。")
		elif mode=="move" and is_finite(p.x):move_selected(p)
		elif mode=="link":
			var id:=nearest(event.position)
			if id!=-2:link_to(id)
		else:
			var picked:=nearest(event.position)
			select_device(picked)
			if not station(picked).is_empty() and event.double_click:open_station(picked)
			elif picked>=0:drag_candidate=picked;drag_origin=event.position
			if picked==-2 and is_finite(p.x):select_site(p)
		return
	super._unhandled_input(event)

func focus_selected():
	var item:=station(selected_id)
	if item.is_empty():item=device(selected_id)
	if item.is_empty():tell("先选择设备或电热站，再聚焦。全景按钮返回整个基地。");return
	var kind:String=item.get("kind","thermal_station")
	target=Vector3(float(item.x),height_at(float(item.x),float(item.z)),float(item.z))
	distance=clampf(footprint(kind,item.get("params",{}))*(2.8 if kind in ["tower_station","tower_station_preview"] else 5.0),8.0,235.0)
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE;pitch=0.65;update_camera()

func clear_link_preview():
	if is_instance_valid(link_preview):link_preview.queue_free()
	link_preview=null;link_preview_key=""

func compatible_target(id:int)->bool:
	if pending_link==-2:return false
	if not station(id).is_empty():
		for d in devices:
			if int(d.get("parent_station_id",-1))==id:
				var candidate:=connection_candidate(pending_link,int(d.id))
				if not candidate.is_empty() and Catalog.validate_link(devices,links,candidate)=="":return true
		return false
	var candidate:=connection_candidate(pending_link,id)
	return not candidate.is_empty() and Catalog.validate_link(devices,links,candidate)==""

func endpoint_description(id:int)->String:
	if id==-1:return "外部电网 · AC输入 · 接收上限 4 MW"
	if station_is_preview(id):return str(station(id).name)+" · 未投运预览 · 无能量端口、无网络连接、零发电"
	if not station(id).is_empty():return str(station(id).name)+" · AC输入 / 70/40°C热输出 · 端口映射至内部设备"
	var d:=device(id)
	if d.is_empty():return ""
	var descriptions:Array[String]=[]
	for port in Catalog.ports(d.kind):
		var carrier:="熔盐565/290°C MWth" if port.carrier=="heat_salt" else "蒸汽/给水 kg/s" if port.carrier=="water_steam" else "导热油300/200°C MWth" if port.carrier=="heat_oil" else "交流电 MW" if port.carrier=="electricity_ac" else ("90/60°C 热水 MWth" if port.get("grade_id","")==Catalog.PRIMARY_GRADE else "70/40°C 热水 MWth")
		descriptions.append("%s %s"%[{"input":"输入","output":"输出","bidirectional":"双向"}.get(port.direction,port.direction),carrier])
	var capacity:=""
	match str(d.kind):
		"wind":capacity="额定 %.2f MW"%d.params.get("rated_mw",0)
		"pv":capacity="逆变上限 %.2f MW"%d.params.get("inverter_capacity_mw",0)
		"station":capacity="容量 %.2f MW"%d.params.get("capacity_mw",0)
		"battery":capacity="充/放 %.2f/%.2f MW"%[d.params.get("charge_mw",0),d.params.get("discharge_mw",0)]
		"load":capacity="需求 %.2f MW"%d.params.get("demand_mw",0)
		"heat_demand":capacity="需求 %.2f MWth"%d.params.get("demand_mwth",0)
		"solar_thermal":capacity="吸热面积 %.2f m² · 固定90/60°C"%d.params.get("absorber_area_m2",0)
		"fuel_boiler":capacity="燃料上限 %.2f MW(LHV) · 辅机 %.3f MW"%[d.params.get("rated_fuel_mw",0),float(d.params.get("rated_fuel_mw",0))*float(d.params.get("auxiliary_electric_ratio",0))]
		"electric_boiler":capacity="电输入上限 %.2f MW"%d.params.get("rated_electric_mw",0)
		"thermal_store":capacity="充/放 %.2f/%.2f MWth"%[d.params.get("charge_mwth",0),d.params.get("discharge_mwth",0)]
		"heat_exchanger":capacity="热侧上限 %.2f MWth"%d.params.get("capacity_mwth",0)
	return "%s #%d · %s · %s"%[DEVICE_NAMES[d.kind],id," / ".join(descriptions),capacity]

func endpoint_name(id:int)->String:
	if id==-1:return "外部电网"
	if not station(id).is_empty():return str(station(id).name)
	var d:=device(id)
	return "%s #%d"%[DEVICE_NAMES.get(d.get("kind",""),"设备"),id] if not d.is_empty() else "未选端口"

func connection_caption(target_id:int)->String:
	if pending_link==-2:return "连接：请选择起点，再选择高亮的兼容终点。"
	var first:="起点："+endpoint_name(pending_link)
	if target_id==-2:return first+"\n下一步：选择高亮终点；Esc 取消。"
	if target_id==pending_link:return first+"\n请选择另一个端口，不能连接自身。"
	if not station(target_id).is_empty():
		return first+" → "+endpoint_name(target_id)+"\n"+("点击选择站内映射端口" if compatible_target(target_id) else "没有兼容或尚未连接的映射端口")
	var candidate:=connection_candidate(pending_link,target_id)
	if candidate.is_empty():return first+" → "+endpoint_name(target_id)+"\n不可连接：载体、方向或厂站边界不兼容。"
	var error:=Catalog.validate_link(devices,links,candidate)
	var carrier:="蒸汽/给水" if candidate.get("carrier","")=="water_steam" else "AC" if candidate.get("carrier","")=="electricity_ac" else ("90/60°C" if candidate.get("grade_id","")==Catalog.PRIMARY_GRADE else "70/40°C")
	return "%s → %s\n%s · 上限 %.2f %s · %s"%[endpoint_name(int(candidate.from)),endpoint_name(int(candidate.to)),carrier,candidate.get("mass_flow_capacity_kg_s",candidate.get("capacity_mwth",candidate.get("capacity_mw",0))),candidate.get("unit","MW"),"可连接" if error=="" else error]

func suppress_annotation_collisions(annotations:Array)->void:
	# Read-only screen-space arbitration: selected title wins, then hover,
	# then secondary readouts. Required port hints are not arbitrated.
	# Equipment and pick positions never move.
	annotations.sort_custom(func(a,b):return a.priority>b.priority)
	var occupied:Array[Rect2]=[]
	var bounds:=get_viewport().get_visible_rect().grow(-6.0)
	for entry in annotations:
		var tag:Label3D=entry.tag
		if not tag.visible:continue
		var center:=camera.unproject_position(tag.global_position)
		var lines:=tag.text.split("\n")
		var text_width:=0.0
		for line in lines:
			text_width=maxf(text_width,tag.font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,tag.font_size).x if tag.font!=null else float(line.length()*tag.font_size))
		var height:float=entry.height*maxi(1,lines.size())
		var width:=clampf(text_width/maxf(float(tag.font_size),1.0)*float(entry.height),18.0,400.0)
		var rect:=Rect2(center-Vector2(width,height)*0.5,Vector2(width,height)).grow(4.0)
		if not bounds.encloses(rect) or occupied.any(func(other):return other.intersects(rect)):
			tag.visible=false
		else:occupied.append(rect)

func update_interaction_visuals():
	var mouse:=get_viewport().get_mouse_position()
	hovered_id=-2 if pointer_over_ui(mouse) else nearest(mouse)
	var annotations:Array=[]
	for collection in [nodes,station_nodes]:
		for key in collection:
			var n:Node3D=collection[key];var id:=int(key)
			var compatible:=mode=="link" and compatible_target(id)
			var source_owner:=int(device(pending_link).get("parent_station_id",pending_link))
			var selection_owner:=int(device(selected_id).get("parent_station_id",selected_id))
			if n.has_method("set_interaction_hint"):n.set_interaction_hint(id==hovered_id,compatible,id==source_owner)
			var details:=id==selection_owner or id==hovered_id
			if n.has_method("set_annotation_visibility"):n.set_annotation_visibility(details,mode=="link" and (compatible or id==pending_link or id==hovered_id))
			for tag in n.get_children():
				if tag is Label3D:
					Visual.fit_screen_label(tag,camera,22.0 if tag.name in ["DeviceTitle","StationTitle"] else 18.0)
					var show:bool=details or ((tag.name=="PortIndicator" or str(tag.name).contains("Port")) and mode=="link" and (compatible or id==pending_link))
					tag.visible=show and not camera.is_position_behind(tag.global_position) and not pointer_over_ui(camera.unproject_position(tag.global_position),Vector2(60,14))
					if not str(tag.name).contains("Port"):annotations.append({"tag":tag,"priority":(100 if id==selection_owner else 50 if id==hovered_id else 0)+(10 if tag.name in ["DeviceTitle","StationTitle"] else 0),"height":22.0 if tag.name in ["DeviceTitle","StationTitle"] else 18.0})
	suppress_annotation_collisions(annotations)
	var caption:=endpoint_description(hovered_id if hovered_id!=-2 else selected_id)
	if caption=="":caption="单击选中 · 拖动移动 · F 聚焦 · 双击厂站进入"
	if mode=="link":caption=connection_caption(hovered_id)
	if is_instance_valid(interaction_caption):
		interaction_caption.text=caption
		interaction_caption.tooltip_text=caption+"\n"+endpoint_description(hovered_id if hovered_id!=-2 else selected_id)
	if is_instance_valid(quick_station_enter):
		var enter_visible:=not station(selected_id).is_empty() and mode=="select"
		if quick_station_enter.visible!=enter_visible:quick_station_enter.visible=enter_visible
	var preview_key:="%s/%s/%s"%[mode,pending_link,hovered_id]
	if preview_key!=link_preview_key:
		clear_link_preview();link_preview_key=preview_key
		if mode=="link" and pending_link!=-2 and hovered_id!=-2 and hovered_id!=pending_link and compatible_target(hovered_id):
			link_preview=Visual.create_line(endpoint(pending_link),endpoint(hovered_id),false,true);equipment.add_child(link_preview)

func _process(delta):
	if not booted:return
	if drag_active and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		set_mode("select");tell("移动已取消：未在地面确认松开；设备保留原位。")
	if is_instance_valid(modal_shade):modal_shade.visible=modal_visible()
	if modal_visible():
		# Interior is navigation, not a second simulator; keep the single world clock.
		if is_instance_valid(station_interior) and station_interior.visible and not (is_instance_valid(station_interior.remove_confirmation) and station_interior.remove_confirmation.visible) and not param_dialog.visible and not confirmation.visible and not line_dialog.visible and not (is_instance_valid(optimization_controller) and is_instance_valid(optimization_controller.panel) and optimization_controller.panel.visible):
			if not paused:advance(delta*speed)
			update_status()
		return
	super._process(delta)
	for map_label in labels.get_children():
		map_label.visible=show_labels and not camera.is_position_behind(map_label.global_position) and not pointer_over_ui(camera.unproject_position(map_label.global_position),Vector2(70,16))
	hover_cooldown-=delta
	if hover_cooldown<=0:
		update_interaction_visuals();hover_cooldown=0.10
	if mode in ["build","move"] and is_instance_valid(ghost):
		var mouse:=get_viewport().get_mouse_position();var p:=pick_ground(mouse)
		if drag_active:p-=drag_offset
		ghost.visible=is_finite(p.x) and not pointer_over_ui(mouse)
		if is_instance_valid(placement_outline):placement_outline.visible=ghost.visible
		if ghost.visible:
			var d:=device(selected_id) if mode=="move" else {}
			var kind:String=str(station(selected_id).get("kind","thermal_station")) if mode=="move" and not station(selected_id).is_empty() else d.get("kind",build_kind)
			var params:Dictionary=d.get("params",templates.get(kind,{}))
			var reason:=can_place(kind,p,selected_id if mode=="move" else -2,params)
			ghost.position=Vector3(p.x,height_at(p.x,p.y)+0.15,p.y);ghost.set_preview(reason=="")
			update_placement_outline(p,footprint(kind,params),reason=="",Spatial.profile(kind,params).land_dimensions_m*0.1 if dimension_profile=="metric_v1" else Vector3.ZERO)
			var message:=("可放置 · 松开确认 · Esc 取消" if drag_active else "可放置 · 左键确认 · Esc 取消") if reason=="" else "无法放置 · "+reason
			if dimension_profile=="metric_v1":
				var dimensions:Vector3=Spatial.profile(kind,params).land_dimensions_m
				message+=" · 安装区 %.1f × %.1f m（圆线为保守避让）"%[dimensions.x,dimensions.z]
			if message!=feedback_key:tell(message);feedback_key=message
	if not paused:
		advance(delta*speed);update_status()
	for key in nodes:
		var d:=device(int(key))
		if d.kind=="wind":
			nodes[key].set_operating(0.0)
			if is_instance_valid(nodes[key].rotor) and weather_effects_enabled:
				# Illustrative wind motion only; no energy/power inference from rotation.
				var wind:float=float(visual_device_weather.get(str(key),{}).get("wind_speed_mps",weather_snapshot.get("wind_speed_mps",0.0)))
				var display_speed:=wind_visual_speed(d.params,wind)
				if display_speed>0:nodes[key].rotor.rotation.z=fposmod(elapsed_s*display_speed,TAU)

func update_placement_outline(p:Vector2,radius:float,valid:bool,land_dimensions:Vector3=Vector3.ZERO):
	var key:="%.2f/%.2f/%.2f/%s/%s"%[p.x,p.y,radius,valid,land_dimensions]
	if key==placement_key:return
	placement_key=key
	if not is_instance_valid(placement_outline):
		placement_outline=MeshInstance3D.new();equipment.add_child(placement_outline)
		placement_outline.name="PlacementFootprint"
	var mesh:=ImmediateMesh.new()
	var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color=Color("43c7a1") if valid else Color("e86354")
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,mat)
	for i in range(64):
		var a:=float(i)*TAU/64.0;var b:=float(i+1)*TAU/64.0
		var points:Array[Vector3]=[]
		var stroke:=minf(0.12,radius*0.035)
		for pair in [Vector2(a,radius-stroke),Vector2(a,radius+stroke),Vector2(b,radius+stroke),Vector2(b,radius-stroke)]:
			var q:Vector2=p+Vector2(cos(pair.x),sin(pair.x))*pair.y
			points.append(Vector3(q.x,height_at(q.x,q.y)+0.30,q.y))
		for index in [0,1,2,0,2,3]:mesh.surface_add_vertex(points[index])
	if land_dimensions.x>0 and land_dimensions.z>0:
		var half:=Vector2(land_dimensions.x,land_dimensions.z)*0.5
		var corners:Array[Vector2]=[p+Vector2(-half.x,-half.y),p+Vector2(half.x,-half.y),p+Vector2(half.x,half.y),p+Vector2(-half.x,half.y)]
		for i in 4:
			var a:=corners[i];var b:=corners[(i+1)%4];var normal:=(b-a).normalized().orthogonal()*0.06
			for q in [a-normal,a+normal,b+normal,a-normal,b+normal,b-normal]:mesh.surface_add_vertex(Vector3(q.x,height_at(q.x,q.y)+0.32,q.y))
	mesh.surface_end();placement_outline.mesh=mesh

func modal_visible()->bool:
	return (is_instance_valid(station_interior) and station_interior.visible) or (is_instance_valid(station_port_dialog) and station_port_dialog.visible) or (is_instance_valid(optimization_controller) and is_instance_valid(optimization_controller.panel) and optimization_controller.panel.visible) or confirmation.visible or param_dialog.visible or data_dialog.visible or line_dialog.visible or (is_instance_valid(import_dialog) and import_dialog.visible)

func window_background(w:Window):
	w.hide();w.transient=true;w.exclusive=true
	var bg:=ColorRect.new();bg.color=Color("0c151e");bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;w.add_child(bg);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func select_site(p:Vector2):
	super.select_site(p)
	detail.text="地块 %.1f, %.1f  / 坡度 %.1f°\n%s"%[p.x,p.y,slope_at(p.x,p.y),"可建初筛通过" if exclusion(p.x,p.y)=="" and slope_at(p.x,p.y)<=8 else "禁建或陡坡"]

func make_parameter_dialog(theme:Theme):
	add_child(param_dialog);param_dialog.title="设备参数";param_dialog.borderless=true;param_dialog.size=Vector2i(940,790);param_dialog.theme=theme;window_background(param_dialog)
	param_dialog.close_requested.connect(func():param_dialog.hide())
	var v:=VBoxContainer.new();param_dialog.add_child(v);v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);v.offset_left=20;v.offset_right=-20;v.offset_top=18;v.offset_bottom=-18;v.add_theme_constant_override("separation",10)
	v.add_child(label("设备参数",25));parameter_scope_label=label("",16);v.add_child(parameter_scope_label);v.add_child(param_target)
	param_target.item_selected.connect(func(_i):load_parameter_text())
	parameter_form=preload("res://scripts/parameter_form.gd").new();v.add_child(parameter_form)
	parameter_form.parameters_changed.connect(func():param_errors.text="修改后校验并应用。取消或关闭不修改场景。")
	param_errors.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;param_errors.add_theme_color_override("font_color",UITheme.AMBER);v.add_child(param_errors)
	var row:=HBoxContainer.new();v.add_child(row)
	button("恢复参考默认（待应用）",func():parameter_form.set_parameters(parameter_kind(),model.defaults(parameter_kind()),param_scope=="template");param_errors.text="参考默认已载入，校验并应用后生效。",row)
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(spacer)
	button("取消",func():param_dialog.hide(),row);button("校验并应用",apply_parameters,row)

func parameter_kind()->String:
	return KINDS[param_target.selected] if param_scope=="template" else device(parameter_id).get("kind","wind")

func open_parameters(as_template:bool):
	if not as_template and device(selected_id).is_empty():tell("先选中设备。");return
	paused=true;param_scope="template" if as_template else "device";parameter_id=selected_id
	param_target.clear()
	for k in KINDS:param_target.add_item(DEVICE_NAMES[k]+"默认值")
	param_target.visible=as_template;load_parameter_text();update_status();param_dialog.popup_centered(Vector2i(mini(940,int(get_viewport().get_visible_rect().size.x)-48),mini(790,int(get_viewport().get_visible_rect().size.y)-48)))

func load_parameter_text():
	var p:Dictionary=templates[parameter_kind()] if param_scope=="template" else device(parameter_id).params
	parameter_form.set_parameters(parameter_kind(),p,param_scope=="template")
	parameter_scope_label.text="应用范围 · 仅未来新建模板；不修改现有设备。" if param_scope=="template" else "应用范围 · 仅当前设备 #%d；不修改其他设备或未来模板。"%parameter_id
	param_errors.text="修改后校验并应用。取消或关闭不修改场景。"

func apply_parameters():
	var parsed=parameter_form.get_parameters()
	if not parsed is Dictionary:param_errors.text="JSON格式错误，未应用。";return
	var errors:Array=model.validate(parameter_kind(),parsed)
	if not errors.is_empty():param_errors.text="未应用："+"；".join(parameter_form.get_validation_errors());return
	var complete:Dictionary=model.defaults(parameter_kind());complete.merge(parsed,true);parsed=complete
	if param_scope=="device":
		var d:=device(parameter_id);var placement_error:=can_place_internal(int(d.parent_station_id),d.kind,Vector2(d.interior_x,d.interior_z),parameter_id,parsed) if d.has("parent_station_id") else can_place(d.kind,Vector2(d.x,d.z),parameter_id,parsed)
		if placement_error!="":param_errors.text="尺寸不适合当前地块："+placement_error;return
	if param_scope=="device" and parameter_kind()=="battery" and float(device(parameter_id).get("state",{}).get("energy_mwh",0))>float(parsed.capacity_mwh):
		param_errors.text="容量不能小于当前已存电量；请先放电，不能通过改参删除能量。";return
	if param_scope=="device" and parameter_kind() in ["thermal_store","high_temp_store","molten_salt_store"] and float(device(parameter_id).get("state",{}).get("energy_mwhth",0))>float(parsed.capacity_mwhth):
		param_errors.text="热容量不能小于当前库存；不允许通过改参删除热量。";return
	checkpoint()
	if param_scope=="template":templates[parameter_kind()]=parsed.duplicate(true)
	else:device(parameter_id).params=parsed.duplicate(true)
	param_dialog.hide();set_mode("select");rebuild_equipment();refresh();tell("参数已应用，可撤销；单台参数随存档保留。")

func open_import():
	paused=true;var options:Array=[]
	for d in devices:
		if not d.kind in ["wind","pv"]:continue
		options.append({"id":str(int(d.id)),"name":"%s #%d"%[d.kind,int(d.id)],"kind":d.kind,"rated_kw":float(d.params.get("rated_mw",d.params.get("inverter_capacity_mw",1)))*1000.0})
	import_dialog.setup(options);import_dialog.open();update_status()

func apply_import(series:Dictionary):
	var candidate:Array=imports.filter(func(s):return not(s.field==series.field and str(s.target_device)==str(series.target_device)))
	candidate.append(series.duplicate(true))
	var origin_error:=iso_origin_error(candidate)
	if origin_error!="":tell("未导入："+origin_error);return
	var aligned:=align_iso_origin(candidate,climate_config)
	var climate_error:=Climate.validate(aligned)
	if climate_error!="":tell("CSV日期超出气候模型范围："+climate_error);return
	var interval:=common_interval(candidate)
	if interval.start>=interval.end:tell("未应用：有效数据没有共同的可积分时间区间。");return
	checkpoint();imports=candidate;climate_config=aligned;elapsed_s=interval.start
	if is_instance_valid(climate_panel):climate_panel.set_config(climate_config)
	energy=ENERGY_ZERO.duplicate(true);thermal_energy=THERMAL_ENERGY_ZERO.duplicate(true);fuel_energy=FuelSupply.initial_energy();solar_energy=SOLAR_ENERGY_ZERO.duplicate(true);high_temp_energy=HighTemp.initial_energy();rankine_energy=Rankine.initial_energy();tower_energy=Tower.initial_energy();paused=true;set_mode("select")
	refresh();tell("已导入；时间设为共同有效区间起点 %.1f s，累计电量归零，可撤销。"%elapsed_s)

func remove_import(index:int):
	if index<0 or index>=imports.size():return
	var candidate:Array=imports.duplicate(true);candidate.remove_at(index)
	var interval:=common_interval(candidate)
	if interval.start>=interval.end:tell("未移除：恢复的下层数据没有共同有效区间，请先移除冲突气象数据。");return
	checkpoint();imports=candidate;elapsed_s=interval.start
	energy=ENERGY_ZERO.duplicate(true);thermal_energy=THERMAL_ENERGY_ZERO.duplicate(true);fuel_energy=FuelSupply.initial_energy();solar_energy=SOLAR_ENERGY_ZERO.duplicate(true);high_temp_energy=HighTemp.initial_energy();rankine_energy=Rankine.initial_energy();tower_energy=Tower.initial_energy();paused=true
	refresh();tell("已移除数据；重新从共同区间起点运行，累计电量归零，可撤销。")

func make_data_dialog(theme:Theme):
	add_child(data_dialog);data_dialog.title="数据来源 / 优先级";data_dialog.size=Vector2i(820,540);data_dialog.theme=theme;window_background(data_dialog);data_dialog.close_requested.connect(func():data_dialog.hide())
	var scroll:=ScrollContainer.new();data_dialog.add_child(scroll);scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);scroll.add_child(data_list);data_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL

func open_data_manager():
	for n in data_list.get_children():n.queue_free()
	data_list.add_child(label("直接出力优先，其次气象物理模型，其余用内置天气。\n同一设备不叠加两份出力；所有出力仍经过网络容量和损耗。\n序列按左值保持，末端暂停，不外推、不填缺值。",17))
	if imports.is_empty():data_list.add_child(label("当前没有导入数据。"))
	for i in range(imports.size()):
		var s:Dictionary=imports[i];var row:=HBoxContainer.new();data_list.add_child(row)
		row.add_child(label("%s → %s  [%s]\n%d 行 / %.1f–%.1f s"%[s.field,"全局气象" if str(s.target_device)=="" else "#"+str(s.target_device),s.get("source",{}).get("name","CSV"),s.samples.size(),s.start_s,s.end_s],16))
		button("移除",func():remove_import(i);open_data_manager(),row)
	button("关闭",func():data_dialog.hide(),data_list);data_dialog.popup_centered()

func make_line_dialog(theme:Theme):
	add_child(line_dialog);line_dialog.title="设备关联线路设置";line_dialog.size=Vector2i(580,430);line_dialog.theme=theme;window_background(line_dialog);line_dialog.close_requested.connect(func():line_dialog.hide())
	var v:=VBoxContainer.new();line_dialog.add_child(v);v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);v.offset_left=22;v.offset_right=-22;v.offset_top=20;v.offset_bottom=-20;v.add_theme_constant_override("separation",12)
	v.add_child(line_choice);line_choice.item_selected.connect(func(i):select_editing_line(int(line_choice.get_item_metadata(i))))
	line_capacity_title=label("线路发送侧容量 MW（外网总接收上限 4 MW）");v.add_child(line_capacity_title);line_capacity.min_value=0.01;line_capacity.max_value=100;line_capacity.step=0.1;v.add_child(line_capacity)
	v.add_child(label("线路损耗比例 0–0.5（电池线双向均适用）"));line_loss.min_value=0;line_loss.max_value=0.5;line_loss.step=0.001;v.add_child(line_loss)
	button("应用",apply_line_values,v)
	button("移除此线路",func():
		if editing_line<0 or editing_line>=links.size():return
		checkpoint();links.remove_at(editing_line);editing_line=-1;line_dialog.hide();rebuild_cables();refresh(),v)
	button("取消",func():line_dialog.hide(),v)

func select_editing_line(index:int):
	editing_line=index
	if index>=0 and index<links.size():
		var heat:bool=links[index].get("carrier","")in ["heat_water","heat_oil","heat_salt"]
		var mass:bool=links[index].get("carrier","")=="water_steam"
		line_capacity.min_value=0.001 if mass else 0.01;line_capacity.step=0.001 if mass else 0.1
		line_capacity.value=links[index].get("mass_flow_capacity_kg_s",0.0) if mass else links[index].get("capacity_mwth",0.0) if heat else links[index].capacity_mw
		line_loss.value=links[index].loss_fraction;line_loss.editable=not (heat or mass)
		line_capacity_title.text="蒸汽/给水质量流量上限 kg/s（闭式循环，质量损失锁定0）" if mass else "热服务发送侧容量 MWth（固定温区，管路损耗锁定0）" if heat else "线路发送侧容量 MW（外网总接收上限4MW）"

func open_line_settings():
	line_choice.clear()
	for index in links.size():
		var l:Dictionary=links[index]
		if int(l.from)==selected_id or int(l.to)==selected_id or (not station(selected_id).is_empty() and not same_internal_station(int(l.from),int(l.to)) and (int(device(int(l.from)).get("parent_station_id",-1))==selected_id or int(device(int(l.to)).get("parent_station_id",-1))==selected_id)):
			line_choice.add_item("#%d → %s · %s"%[int(l.from),"外网" if int(l.to)==-1 else "#%d"%int(l.to),"蒸汽/给水 / kg/s" if l.get("carrier","")=="water_steam" else "热服务 / MWth" if l.get("carrier","")in ["heat_water","heat_oil","heat_salt"] else "AC / MW"])
			line_choice.set_item_metadata(line_choice.item_count-1,index)
	if line_choice.item_count>0:
		line_choice.select(0);select_editing_line(int(line_choice.get_item_metadata(0)));line_dialog.popup_centered();return
	tell("选中设备尚无关联线路。")

func storage_example():
	checkpoint();devices=[];stations=[];next_station_id=1000000;links=[];imports=[];next_id=0;elapsed_s=0;energy=ENERGY_ZERO.duplicate(true);thermal_energy=THERMAL_ENERGY_ZERO.duplicate(true);fuel_energy=FuelSupply.initial_energy();solar_energy=SOLAR_ENERGY_ZERO.duplicate(true);high_temp_energy=HighTemp.initial_energy();rankine_energy=Rankine.initial_energy();tower_energy=Tower.initial_energy();paused=true
	# Placement follows exactly the normal terrain/spacing guard; no hidden devices.
	for spec in [["wind",Vector2(-15,0)],["pv",Vector2(7,14)],["station",Vector2(24,14)],["load",Vector2(40,14)],["battery",Vector2(24,-2)]]:
		if not add_equipment(spec[0],spec[1],false):
			for x in range(-30,61,15):
				var placed:=false
				for z in range(-30,46,15):
					if can_place(spec[0],Vector2(x,z))=="":add_equipment(spec[0],Vector2(x,z),false);placed=true;break
				if placed:break
	if devices.size()==5:
		links=[{"from":0,"to":2,"capacity_mw":6.0,"loss_fraction":0.02},{"from":1,"to":2,"capacity_mw":2.0,"loss_fraction":0.02},{"from":2,"to":3,"capacity_mw":5.0,"loss_fraction":0.02},{"from":4,"to":2,"capacity_mw":3.0,"loss_fraction":0.02}]
	set_mode("select");selected_id=4;distance=110;target=Vector3(20,0,10);update_camera();rebuild_equipment();refresh();tell("源网荷储示例：优先供负荷，余电充电；没有外网进口。电池初始5 MWh为教学设定。")

func export_optimization_snapshot():
	var dat:=dispatch_inputs(elapsed_s)
	if dat.error!="":tell(dat.error);return
	var snapshot:Dictionary=model.optimization_snapshot(devices,links,dat.weather,dat.direct,1.0,{"simulation_time":elapsed_s,"scene_revision":scene_revision,"request_id":"scene-%d"%scene_revision})
	var f:=FileAccess.open("user://optimization_snapshot.json",FileAccess.WRITE)
	if f==null:tell("快照写入失败。");return
	f.store_string(JSON.stringify(snapshot,"  "));f.close()
	tell("仅导出快照，未运行求解器："+ProjectSettings.globalize_path("user://optimization_snapshot.json"))

func example():
	checkpoint();devices=[];stations=[];next_station_id=1000000;links=[];imports=[];next_id=0;elapsed_s=0;energy=ENERGY_ZERO.duplicate(true);thermal_energy=THERMAL_ENERGY_ZERO.duplicate(true);fuel_energy=FuelSupply.initial_energy();solar_energy=SOLAR_ENERGY_ZERO.duplicate(true);high_temp_energy=HighTemp.initial_energy();rankine_energy=Rankine.initial_energy();tower_energy=Tower.initial_energy();paused=true
	# Known flat central parcel; validated with the same terrain constraints as placement.
	for spec in [["wind",Vector2(-15,0)],["pv",Vector2(7,14)],["station",Vector2(24,14)]]:add_equipment(spec[0],spec[1],false)
	if devices.size()==3:links=[{"from":0,"to":2,"capacity_mw":6.0,"loss_fraction":0.02},{"from":1,"to":2,"capacity_mw":2.0,"loss_fraction":0.02},{"from":2,"to":-1,"capacity_mw":4.0,"loss_fraction":0.02}]
	set_mode("select");selected_id=0;distance=110;target=Vector3(20,0,10);update_camera();rebuild_equipment();refresh();tell("示例已连接；送出受 4 MW 电网约束，可运行、改参数或导入数据。")

func game_self_test():
	var checks:=0
	example();assert(devices.size()==3,"example placement");checks+=1
	assert(absf(result.balance_error_mw)<0.000001);assert(float(result.delivered_mw)<=4.0);checks+=2
	assert(not add_equipment("pv",Vector2(7,14)));checks+=1
	var original:=state();checkpoint();devices[0].x+=0.5;undo();assert(devices[0].x==original.devices[0].x);checks+=1
	assert(write_save("user://tests/rebuild_roundtrip.json"));devices=[];assert(read_save("user://tests/rebuild_roundtrip.json"));assert(devices.size()==3);checks+=3
	assert(advance(10));assert(absf(energy.generated-energy.delivered-energy.curtailed-energy.loss)<0.000001);checks+=2
	var parsed:Dictionary=Series.parse("time,power\n0,2000\n60,1000",{"time_column":"time","value_column":"power","time_unit":"s","value_unit":"kW","field":"power","target_device":"0"},{})
	assert(parsed.ok,str(parsed));apply_import(parsed.series);assert(imports.size()==1);assert(sources["0"]=="CSV 直接出力");checks+=3
	assert(write_save("user://tests/rebuild_import.json"));imports=[];assert(read_save("user://tests/rebuild_import.json"));assert(imports.size()==1);checks+=3
	assert(advance(60));assert(not advance(1));assert(absf(energy.generated-energy.delivered-energy.curtailed-energy.loss)<0.000001);checks+=3
	var bad=state();bad.schema=99;assert(validate_state(bad)!="");checks+=1
	undo();print("GAME_SELF_TEST_PASS checks=",checks);get_tree().quit()

func apply_climate(candidate:Dictionary)->void:
	var error:=Climate.validate(candidate)
	if error!="":tell("未应用："+error);return
	var aligned:=align_iso_origin(imports,candidate)
	if aligned.start_local!=candidate.start_local:
		tell("ISO UTC数据固定了起始时刻，请先移除ISO数据再改日期；改变时区时请保持同一UTC起点。");return
	checkpoint();climate_config=candidate.duplicate(true)
	elapsed_s=float(common_interval(imports).start);energy=ENERGY_ZERO.duplicate(true);thermal_energy=THERMAL_ENERGY_ZERO.duplicate(true);fuel_energy=FuelSupply.initial_energy();solar_energy=SOLAR_ENERGY_ZERO.duplicate(true);high_temp_energy=HighTemp.initial_energy();rankine_energy=Rankine.initial_energy();tower_energy=Tower.initial_energy();paused=true;accumulator=0
	if is_instance_valid(climate_panel):climate_panel.set_config(climate_config)
	refresh();tell("气候设置已应用；太阳位置按位置与日历计算，气象仍为教学/导入。可撤销。")

func iso_origin_error(candidate:Array)->String:
	var origin := NAN
	for series in candidate:
		if series.get("time_mode","")!="iso_utc":continue
		var parsed:Dictionary=Series._parse_iso_utc(str(series.get("time_origin_utc","")))
		if not parsed.ok:return "ISO UTC时间原点无效。"
		var value:float=parsed.value
		if not is_nan(origin) and absf(origin-value)>0.000001:return "ISO UTC 数据须使用同一首行起点；请先对齐CSV时间范围，不能将不同日期各自当作零时刻。"
		origin=value
	return ""

func align_iso_origin(candidate:Array, config:Dictionary)->Dictionary:
	var aligned:=config.duplicate(true)
	for series in candidate:
		if series.get("time_mode","")!="iso_utc":continue
		var parsed:Dictionary=Series._parse_iso_utc(str(series.time_origin_utc))
		if not parsed.ok:return aligned
		var utc:=int(floor(float(parsed.value)))
		aligned.start_local=Time.get_datetime_string_from_unix_time(utc+int(round(float(aligned.utc_offset_hours)*3600)),false)
		break
	return aligned

func start_heat_demand_node():
	start_build("heat_demand")
	tell("设置70/40°C热需求接入点；这是需求标记，不是发热设备。")

func connection_candidate(first:int,second:int)->Dictionary:
	if first<0 or first==second:return {}
	var a:=first;var b:=second
	var ka:String=device(a).get("kind","");var kb:String=device(b).get("kind","grid" if b==-1 else "")
	var mass_paths:={"salt_steam_generator>steam_turbine":["steam_out","steam_in","rankine_live_v1"],"feedwater_pump>salt_steam_generator":["feed_out","feed_in","rankine_feedwater_v1"],"steam_generator>steam_turbine":["steam_out","steam_in","rankine_live_v1"],"steam_turbine>steam_condenser":["exhaust_out","exhaust_in","rankine_exhaust_v1"],"steam_condenser>feedwater_pump":["condensate_out","condensate_in","rankine_condensate_v1"],"feedwater_pump>steam_generator":["feed_out","feed_in","rankine_feedwater_v1"]}
	for pair in [[a,b,ka,kb],[b,a,kb,ka]]:
		var key:String=pair[2]+">"+pair[3]
		if mass_paths.has(key):
			if not same_internal_station(int(pair[0]),int(pair[1])):return {}
			var ports:Array=mass_paths[key]
			return {"from":int(pair[0]),"to":int(pair[1]),"from_port":ports[0],"to_port":ports[1],"carrier":"water_steam","unit":"kg/s","grade_id":ports[2],"mass_flow_capacity_kg_s":0.05,"loss_fraction":0.0}
	var heat_paths:={"solar_tower_receiver>molten_salt_store":["heat_out","heat_in","salt_565_290"],"solar_tower_receiver>salt_steam_generator":["heat_out","salt_in","salt_565_290"],"molten_salt_store>salt_steam_generator":["heat_out","salt_in","salt_565_290"],"parabolic_trough>steam_generator":["heat_out","oil_in","oil_300_200"],"high_temp_store>steam_generator":["heat_out","oil_in","oil_300_200"],"parabolic_trough>high_temp_store":["heat_out","heat_in","oil_300_200"],"parabolic_trough>oil_water_exchanger":["heat_out","hot_in","oil_300_200"],"high_temp_store>oil_water_exchanger":["heat_out","hot_in","oil_300_200"],"oil_water_exchanger>heat_exchanger":["warm_out","hot_in","hw_primary_90_60"],"solar_thermal>heat_exchanger":["heat_out","hot_in","hw_primary_90_60"],"solar_thermal>thermal_store":["heat_out","heat_in","hw_primary_90_60"],"fuel_boiler>heat_exchanger":["heat_out","hot_in","hw_primary_90_60"],"fuel_boiler>thermal_store":["heat_out","heat_in","hw_primary_90_60"],"electric_boiler>heat_exchanger":["heat_out","hot_in","hw_primary_90_60"],"electric_boiler>thermal_store":["heat_out","heat_in","hw_primary_90_60"],"thermal_store>heat_exchanger":["heat_out","hot_in","hw_primary_90_60"],"heat_exchanger>heat_demand":["warm_out","heat_in","hw_secondary_70_40"]}
	if heat_paths.has(kb+">"+ka):
		var swap:=a;a=b;b=swap;var swap_kind:=ka;ka=kb;kb=swap_kind
	if heat_paths.has(ka+">"+kb):
		var pa:int=int(device(a).get("parent_station_id",-1));var pb:int=int(device(b).get("parent_station_id",-1))
		if pa!=pb and not (ka=="heat_exchanger" and kb=="heat_demand" and pb==-1):return {}
		var ports:Array=heat_paths[ka+">"+kb]
		return {"from":a,"to":b,"from_port":ports[0],"to_port":ports[1],"carrier":"heat_salt" if ports[2]=="salt_565_290" else "heat_oil" if ports[2]=="oil_300_200" else "heat_water","unit":"MWth","grade_id":ports[2],"capacity_mwth":2.0,"loss_fraction":0.0}
	if ka in ["solar_tower_receiver","molten_salt_store","salt_steam_generator","load","electric_boiler","fuel_boiler","solar_thermal","parabolic_trough","oil_water_exchanger","steam_generator","steam_condenser","feedwater_pump"] or (ka=="station" and kb in ["wind","pv","battery","steam_turbine"]):
		var swap:=a;a=b;b=swap;var swap_kind:=ka;ka=kb;kb=swap_kind
	if not ((ka in ["wind","pv","battery","steam_turbine"] and kb=="station") or (ka=="station" and kb in ["solar_tower_receiver","molten_salt_store","salt_steam_generator","load","electric_boiler","fuel_boiler","solar_thermal","parabolic_trough","oil_water_exchanger","steam_generator","steam_condenser","feedwater_pump","grid"])):return {}
	var candidate:={"from":a,"to":b,"capacity_mw":8.0 if b!=-1 else 4.0,"loss_fraction":0.02,"carrier":"electricity_ac","unit":"MW"}
	candidate.merge(Catalog.connection_ports(devices,candidate),true)
	candidate.erase("grade_id")
	return candidate

func update_thermal_display(d:Dictionary,report:Dictionary)->void:
	update_fuel_resource_summary()
	var heat:Dictionary=result.get("thermal",{})
	var any_heat:=devices.any(func(item):return item.kind in THERMAL_KINDS)
	var actual_heat_inventory:=0.0
	for item in devices:
		if item.kind in ["thermal_store","high_temp_store","molten_salt_store"]:
			var stock:float=item.get("state",{}).get("energy_mwhth",0)
			actual_heat_inventory+=stock
			if nodes.has(str(int(item.id))) and nodes[str(int(item.id))].has_method("set_thermal_soc"):nodes[str(int(item.id))].set_thermal_soc(stock/float(item.params.capacity_mwhth))
	if is_instance_valid(thermal_network_summary):
		thermal_network_summary.visible=any_heat
		thermal_network_summary.text="热服务 · %.3f / %.3f MWth\n缺热 %.3f MWth · 电锅炉用电 %.3f MW\n储热 %.3f MWhth · 热网守恒差 %.8f MWth"%[heat.get("served_mwth",0),heat.get("demand_mwth",0),heat.get("unserved_mwth",0),result.get("boiler_electric_mw",0),actual_heat_inventory,heat.get("balance_error_mwth",0)]
		if devices.any(func(item):return item.kind=="fuel_boiler"):
			var fuel:Dictionary=result.get("fuel",{})
			thermal_network_summary.text+="\n燃气出热 %.3f MWth · 辅机 %.3f MW"%[fuel.get("heat_output_mwth",0),fuel.get("auxiliary_electric_mw",0)]
		if devices.any(func(item):return item.kind=="solar_thermal"):
			var solar:Dictionary=result.get("solar",{})
			thermal_network_summary.text+="\n太阳能可用 %.4f / 有用 %.4f MWth\n弃热 %.4f MWth · 辅机 %.5f MW\n累计有用 %.4f MWhth"%[solar.get("available_mwth",0),solar.get("useful_mwth",0),solar.get("curtailed_mwth",0),solar.get("auxiliary_electric_mw",0),solar_energy.useful_mwhth]
		if devices.any(func(item):return Catalog.is_high_temp(item.kind)):
			var hot:Dictionary=result.get("high_temp",{})
			thermal_network_summary.text+="\n导热油300/200°C：可用 %.1f / 有用 %.1f kWth\n槽辅机 %.3f / 油水泵 %.3f kW\n高温累计有用 %.5f MWhth · 守恒差 %.8f"%[float(hot.get("available_mwth",0))*1000,float(hot.get("useful_mwth",0))*1000,float(hot.get("collector_auxiliary_electric_mw",0))*1000,float(hot.get("oil_auxiliary_electric_mw",0))*1000,high_temp_energy.useful_mwhth,hot.get("balance_error_mwth",0)]
		if result.get("rankine") is Dictionary:
			var cycle:Dictionary=result.rankine
			thermal_network_summary.text+="\n蒸汽循环：毛发电 %.3f / 辅机 %.3f / 净发电 %.3f kW\n排热 %.3f kWth · 流量 %.5f kg/s\n累计毛发电 %.6f MWh · 累计净发电 %.6f MWh"%[float(cycle.get("gross_electric_mw",0))*1000,float(cycle.get("auxiliary_electric_mw",0))*1000,float(cycle.get("net_electric_mw",0))*1000,float(cycle.get("condenser_rejection_mwth",0))*1000,cycle.get("mass_flow_kg_s",0),rankine_energy.get("gross_electric_mwh",0),rankine_energy.get("net_electric_mwh",0)]
	var kind:String=d.get("kind","")
	for key in ["device_available","device_sent","device_curtail"]:
		if metric_values.has(key):metric_values[key].get_parent().visible=not kind in THERMAL_KINDS
	if is_instance_valid(thermal_detail):
		thermal_detail.visible=kind in THERMAL_KINDS
		var text:=""
		match kind:
			"steam_generator", "steam_turbine", "steam_condenser", "feedwater_pump":
				text=rankine_report_text(kind,report)
			"parabolic_trough", "oil_water_exchanger":
				text=high_temp_report_text(kind,report)+"\n"+thermal_connection_status(int(d.id))
			"high_temp_store":
				text="Therminol 66 · 固定300/200°C\n库存 %.5f MWhth · SOC0=200°C冷端基线\n充热 %.5f / 放热 %.5f MWth\n非室温冷启动；放热需要下游换热或蒸汽循环辅电"%[d.get("state",{}).get("energy_mwhth",0),report.get("charge_mwth",0),report.get("discharge_mwth",0)]
			"solar_thermal":
				text=solar_report_text(report)+"\n"+thermal_connection_status(int(d.id))
			"fuel_boiler":
				text="燃气热水锅炉 · 天然气 LHV + AC辅机 → 90/60°C\n燃料 %.4f MW(LHV) · 出热 %.4f MWth\n燃料转换散失 %.4f MW · 辅机 %.4f MW\n气量 %.3f Nm³/h · 教学燃料费 %.2f 元/h\n%s"%[report.get("fuel_input_mw",0),report.get("heat_output_mwth",0),report.get("conversion_loss_mw",0),report.get("auxiliary_electric_mw",0),report.get("fuel_volume_nm3_per_h",0),report.get("fuel_cost_per_h",0),thermal_connection_status(int(d.id))]
			"electric_boiler":
				text="电热水锅炉 · AC → 90/60°C\n电输入 %.4f MW\n出热 %.4f MWth · 转换散失 %.4f MW\n%s"%[report.get("electric_input_mw",report.get("input_mw",0)),report.get("output_mwth",report.get("heat_output_mwth",0)),report.get("conversion_loss_mw",0),thermal_connection_status(int(d.id))]
			"thermal_store":
				var stored:float=d.get("state",{}).get("energy_mwhth",0);var capacity:float=d.params.get("capacity_mwhth",1)
				text="90/60°C 双区等效储热\n库存 %.4f / %.3f MWhth · SOC %.2f%%\n充 %.4f / 放 %.4f MWth\n%s\n自损系数 %.4f /h\n固定供热品质，SOC不是罐温；断线仍自损。"%[stored,capacity,stored/capacity*100.0,report.get("charge_mwth",0),report.get("discharge_mwth",0),"已空" if stored<0.000001 else "已满" if stored>=capacity-0.000001 else "库存可用",d.params.get("self_discharge_per_h",0)]
				if nodes.has(str(int(d.id))) and nodes[str(int(d.id))].has_method("set_thermal_soc"):nodes[str(int(d.id))].set_thermal_soc(stored/capacity)
			"heat_exchanger":
				text="隔离换热器 · 90/60 → 70/40°C\n热侧输入 %.4f MWth\n冷侧输出 %.4f MWth · 散失 %.4f MWth\n热侧容量 %.3f MWth · 最小端温差 %.1f K\n%s"%[report.get("input_mwth",0),report.get("output_mwth",0),report.get("loss_mwth",report.get("exchanger_loss_mwth",0)),d.params.get("capacity_mwth",0),d.params.get("min_approach_k",0),thermal_connection_status(int(d.id))]
			"heat_demand":
				text="70/40°C 独立热需求\n请求 %.4f MWth · 实供 %.4f MWth\n缺供 %.4f MWth · 优先级 %d\n当前为常量任务，无热需求CSV。"%[report.get("demand_mwth",d.params.get("demand_mwth",0)),report.get("served_mwth",0),report.get("unserved_mwth",d.params.get("demand_mwth",0)),d.params.get("priority",10)]
		thermal_detail.text=text
		if kind in THERMAL_KINDS:
			device_summary.text=thermal_connection_status(int(d.id))
			source_label.text="天然气低位热值输入；AC辅机独立计量并列为散失。\n固定90/60°C热水教学模型；不是蒸汽火电。" if kind=="fuel_boiler" else "固定温区热服务模型\n已充水、循环辅机包含于等效效率\n不是蒸汽压力/流量仿真。"
			if Catalog.is_high_temp(kind):source_label.text="Therminol 66 · 固定300/200°C预热教学模型\nDNI独立；辅机、换热泵电独立计量；本设备不直接发电。"
			if kind in RANKINE_KINDS:source_label.text="固定1MPa/280°C蒸汽 → 10kPa冷凝闭式循环\n质量流量与焓差分账；外部电源保证辅机，禁止自举。\n已预热固定工况；无冷启动、汽包库存或瞬态压力仿真。"
			if kind=="solar_thermal":source_label.text="非聚光真空管 · 固定90/60°C\n教学等效固定面POA；不是DNI，不再转置。\n吸热面积基准，辅机电独立计量。"
	if is_instance_valid(demand_summary) and any_heat:demand_summary.text+="\n热需求 %.3f MWth\n实供 %.3f · 缺供 %.3f MWth"%[heat.get("demand_mwth",0),heat.get("served_mwth",0),heat.get("unserved_mwth",0)]

func thermal_connection_status(id:int)->String:
	var kind:String=device(id).get("kind","")
	var incoming:=false;var outgoing:=false;var electric:=false
	for line in links:
		if int(line.to)==id:
			incoming=true
			if line.get("carrier","electricity_ac")=="electricity_ac":electric=true
		if int(line.from)==id:outgoing=true
	if kind in RANKINE_KINDS:return str(result.get("devices",{}).get(str(id),{}).get("status_reason","需闭合蒸汽/冷凝水/给水回路并为辅机接入外部AC电源"))
	if kind in ["parabolic_trough","oil_water_exchanger"]:
		if not electric:return "辅机未接电：没有AC供电不能送热"
		if not outgoing:return "热出口未连接"
		return "导热油300/200°C；辅机供电与下游接纳共同限制传热"
	if kind=="high_temp_store":return "高温库存可供油水换热器或蒸汽发生器；放热须有对应辅机电"
	if kind=="solar_thermal":
		if not electric:return "辅机未接电：需变电站AC供电"
		if not outgoing:return "热出口未连接：可用集热计为弃热"
		return "面上辐照、环境温度、辅机电与下游接纳共同限制供热"
	if kind=="fuel_boiler":
		if not electric:return "辅机未接电：没有AC供电不能燃烧产热"
		if not outgoing:return "热出口未连接：不消耗燃料或辅机电"
		if not fuel_supply.enabled or float(fuel_supply.max_input_mw)<=0:return "燃料供给关闭：在独立燃料资源页配置供给上限"
		return "受共用燃料供给、辅机电和下游热接纳联合约束"
	if kind=="electric_boiler":
		if not electric:return "未接电：需变电站AC输入"
		if not outgoing:return "热出口未连接：不消耗电力"
		var report:Dictionary=result.get("devices",{}).get(str(id),{})
		if float(report.get("electric_input_mw",report.get("input_mw",0)))<0.000001:return "待机：供电或下游热接纳不足，无虚构热汇"
		return "电热端均已连接；实际活动受供电与下游能力约束"
	if kind=="heat_exchanger":return "热端未连接" if not incoming else "冷侧出口未连接" if not outgoing else "双侧已连接；下游需求与热侧容量限制供热"
	if kind=="heat_demand":return "热需求未连接：缺供单独统计" if not incoming else "需求已接次温区"
	return "孤岛：仅库存自损" if not incoming and not outgoing else "热端已连接"

func thermal_example():
	checkpoint();devices=[];stations=[];next_station_id=1000000;links=[];imports=[];next_id=0;elapsed_s=0;energy=ENERGY_ZERO.duplicate(true);thermal_energy=THERMAL_ENERGY_ZERO.duplicate(true);fuel_energy=FuelSupply.initial_energy();solar_energy=SOLAR_ENERGY_ZERO.duplicate(true);high_temp_energy=HighTemp.initial_energy();rankine_energy=Rankine.initial_energy();tower_energy=Tower.initial_energy();paused=true
	for spec in [["wind",Vector2(-35,0)],["pv",Vector2(-15,14)],["station",Vector2(3,14)],["electric_boiler",Vector2(21,14)],["thermal_store",Vector2(21,-3)],["heat_exchanger",Vector2(39,14)],["heat_demand",Vector2(56,14)],["load",Vector2(3,31)]]:
		if not add_equipment(spec[0],spec[1],false):
			for x in range(-60,71,15):
				var placed:=false
				for z in range(-40,46,15):
					if can_place(spec[0],Vector2(x,z))=="":add_equipment(spec[0],Vector2(x,z),false);placed=true;break
				if placed:break
	if devices.size()==8:
		device(7).params.demand_mw=0.5
		for pair in [[0,2],[1,2],[2,3],[2,7],[3,4],[3,5],[4,5],[5,6]]:links.append(connection_candidate(pair[0],pair[1]))
	var sid:=next_station_id;next_station_id+=1
	for i in [3,4,5]:
		device(i).parent_station_id=sid
		var internal_point:Vector2={3:Vector2(-1.0,-0.7),4:Vector2(0.9,-0.6),5:Vector2(0,1.0)}[i] if dimension_profile=="metric_v1" else Vector2({3:-12.0,4:0.0,5:12.0}[i],0)
		device(i).interior_x=internal_point.x;device(i).interior_z=internal_point.y
	var site:=Vector2(21,14)
	if can_place("thermal_station",site)!="":
		for x in range(-60,71,15):
			var located:=false
			for z in range(-40,46,15):
				if can_place("thermal_station",Vector2(x,z))=="":site=Vector2(x,z);located=true;break
			if located:break
	stations.append({"id":sid,"name":"电热站 1","x":site.x,"z":site.y})
	set_mode("select");selected_id=sid;distance=125;target=Vector3(12,0,10);update_camera();rebuild_equipment();refresh();tell("电热教学链：电与热需求分开统计；锅炉按可用电和热接纳工作。储热初始为空。")

func apply_line_values():
	if editing_line<0 or editing_line>=links.size():return
	line_capacity.apply();line_loss.apply()
	var updated:Dictionary=links[editing_line].duplicate(true)
	var heat:bool=updated.get("carrier","")in ["heat_water","heat_oil","heat_salt"]
	var mass:bool=updated.get("carrier","")=="water_steam"
	updated["mass_flow_capacity_kg_s" if mass else "capacity_mwth" if heat else "capacity_mw"]=line_capacity.value
	updated.loss_fraction=0.0 if heat or mass else line_loss.value
	var other:Array=links.duplicate(true);other.remove_at(editing_line)
	var error:=Catalog.validate_link(devices,other,updated)
	if error!="":tell("未修改线路："+error);return
	checkpoint();links[editing_line]=updated;line_dialog.hide();rebuild_cables();refresh()

func station(id:int)->Dictionary:
	for item in stations:
		if int(item.id)==id:return item
	return {}

func same_internal_station(a:int,b:int)->bool:
	var da:=device(a);var db:=device(b)
	return da.has("parent_station_id") and db.has("parent_station_id") and int(da.parent_station_id)==int(db.parent_station_id)

func station_is_preview(id:int)->bool:
	return station(id).get("kind", "thermal_station")=="tower_station_preview"

func add_station(p:Vector2,record:bool=true,facility_kind:String="thermal_station")->bool:
	if not facility_kind in FACILITY_KINDS:return false
	if next_station_id>SaveValidator.MAX_ID:tell("厂站ID已用尽。");return false
	if stations.size()>=SaveValidator.MAX_STATIONS:tell("厂站数量已达128上限。");return false
	var error:=can_place(facility_kind,p)
	if error!="":tell(error);return false
	if record:checkpoint()
	while not device(next_station_id).is_empty() or not station(next_station_id).is_empty() or (next_station_id==next_id and next_station_id<=SaveValidator.MAX_ID):next_station_id+=1
	var id:=next_station_id;next_station_id+=1
	var item:={"id":id,"name":"%s %d"%[DEVICE_NAMES[facility_kind],stations.size()+1],"x":p.x,"z":p.y}
	if facility_kind!="thermal_station":item["kind"]=facility_kind
	stations.append(item)
	selected_id=id;normalize_id_cursors();rebuild_equipment();refresh();return true

func move_station(id:int,p:Vector2)->bool:
	var item:=station(id)
	if item.is_empty():return false
	var error:=can_place(str(item.get("kind","thermal_station")),p,id)
	if error!="":tell(error);return false
	if Vector2(float(item.x),float(item.z)).is_equal_approx(p):set_mode("select");return true
	checkpoint();item.x=p.x;item.z=p.y;rebuild_equipment();refresh();set_mode("select");return true

func remove_station(id:int)->bool:
	if station(id).is_empty():return false
	checkpoint()
	var ids:Array=[]
	for d in devices:
		if int(d.get("parent_station_id",-1))==id:ids.append(int(d.id))
	devices=devices.filter(func(d):return not int(d.id) in ids)
	links=links.filter(func(l):return not int(l.from) in ids and not int(l.to) in ids)
	imports=imports.filter(func(series):return not str(series.target_device).to_int() in ids if str(series.target_device).is_valid_int() else true)
	stations=stations.filter(func(item):return int(item.id)!=id)
	if is_instance_valid(station_interior):station_interior.hide()
	selected_id=-2;set_mode("select");rebuild_equipment();refresh();return true

func can_place_internal(sid:int,kind:String,p:Vector2,ignore_id:int=-2,params:Dictionary={})->String:
	if kind in ["solar_thermal","parabolic_trough","high_temp_store","oil_water_exchanger","steam_generator","steam_turbine","steam_condenser","feedwater_pump"] and dimension_profile!="metric_v1":return "太阳能集热器需要米制尺寸；请先在尺寸说明中显式迁移米制。"
	if station(sid).is_empty():return "父厂站不存在"
	if station_is_preview(sid):return "塔式设施为未投运预览，不能放置运行设备、接线或产生能量"
	if not kind in INTERNAL_KINDS:return "该设备不属于本站内部设备"
	var effective:Dictionary=params if not params.is_empty() else device(ignore_id).get("params",templates.get(kind,{}))
	var radius:=footprint(kind,effective)
	if kind in ["solar_tower_receiver","molten_salt_store","salt_steam_generator"] and station(sid).get("kind","")!="tower_station":return "熔盐设备必须位于运行塔站"
	if kind=="solar_tower_receiver":
		if not p.is_equal_approx(Vector2.ZERO):return "塔接收器固定在镜场中心 (0,0)，不可移位"
		for other in devices:
			if int(other.get("parent_station_id",-1))==sid and other.kind==kind and int(other.id)!=ignore_id:return "每个塔站仅允许一个接收器，100面镜场不重复计能"
	if station(sid).get("kind","")=="tower_station":
		var civil_error:=Spatial.tower_equipment_position_error(kind,effective,p)
		if civil_error!="":return civil_error
	var half:=6.0 if station(sid).get("kind","")=="tower_station" else 2.4 if dimension_profile=="metric_v1" else 24.0
	if not is_finite(p.x) or not is_finite(p.y) or absf(p.x)>half-radius or absf(p.y)>half-radius:return "超出站内布局边界"
	for d in devices:
		if int(d.get("parent_station_id",-1))==sid and int(d.id)!=ignore_id and p.distance_to(Vector2(d.interior_x,d.interior_z))<radius+footprint(d.kind,d.params):return "与站内设备占地重叠"
	return ""

func add_internal_device(sid:int,kind:String,p:Vector2)->bool:
	if kind=="solar_tower_receiver":p=Vector2.ZERO
	if next_id>SaveValidator.MAX_ID:tell("设备ID已用尽。");return false
	if devices.size()>=SaveValidator.MAX_DEVICES:tell("设备数量已达1024上限。");return false
	var error:=can_place_internal(sid,kind,p)
	if error!="":tell(error);return false
	checkpoint()
	while not station(next_id).is_empty():next_id+=1
	var parent:=station(sid)
	devices.append({"id":next_id,"kind":kind,"x":parent.x,"z":parent.z,"parent_station_id":sid,"interior_x":p.x,"interior_z":p.y,"params":templates[kind].duplicate(true),"state":Catalog.initial_state(kind,templates[kind]),"model_profile":Catalog.model_profile(kind)})
	selected_id=next_id;next_id+=1;normalize_id_cursors();rebuild_equipment();refresh();return true

func move_internal_device(id:int,p:Vector2)->bool:
	var d:=device(id)
	if not d.has("parent_station_id"):return false
	var error:=can_place_internal(int(d.parent_station_id),d.kind,p,id)
	if error!="":tell(error);return false
	checkpoint();d.interior_x=p.x;d.interior_z=p.y;refresh();return true

func remove_internal_device(id:int)->bool:
	if not device(id).has("parent_station_id"):return false
	checkpoint();devices=devices.filter(func(d):return int(d.id)!=id)
	links=links.filter(func(l):return int(l.from)!=id and int(l.to)!=id)
	selected_id=-2;rebuild_equipment();refresh();return true

func connect_internal_devices(a:int,b:int)->bool:
	if not same_internal_station(a,b):tell("内部设备必须位于同一厂站。");return false
	var candidate:=connection_candidate(a,b)
	if candidate.is_empty():tell("端口或温区不匹配。");return false
	var error:=Catalog.validate_link(devices,links,candidate)
	if error!="":tell(error);return false
	checkpoint();links.append(candidate);rebuild_cables();refresh();return true

func open_station(id:int):
	if station(id).is_empty():return
	set_mode("select")
	if is_instance_valid(station_interior):station_interior.open_station(id)

func choose_station_port(sid:int):
	if station_is_preview(sid):tell("塔式设施为未投运预览，没有能量端口，不能接入网络。");return
	if mode!="link":tell("请先选择连接，再点厂站边界端口。");return
	station_port_picker.clear()
	for d in devices:
		if int(d.get("parent_station_id",-1))!=sid:continue
		if not d.kind in ["solar_tower_receiver","molten_salt_store","salt_steam_generator","electric_boiler","fuel_boiler","solar_thermal","parabolic_trough","oil_water_exchanger","heat_exchanger","steam_generator","steam_turbine","steam_condenser","feedwater_pump"]:continue
		# When the other endpoint is known, show only compatible mapped nodes.
		if pending_link!=-2 and (same_internal_station(pending_link,int(d.id)) or connection_candidate(pending_link,int(d.id)).is_empty()):continue
		station_port_picker.add_item(("AC发电 ← 汽轮机" if d.kind=="steam_turbine" else "AC给水泵 → 给水泵" if d.kind=="feedwater_pump" else "AC冷却辅机 → 冷凝器" if d.kind=="steam_condenser" else "AC油泵 → 蒸汽发生器" if d.kind=="steam_generator" else "AC泵 → 油水换热器" if d.kind=="oil_water_exchanger" else "AC辅机 → 槽式集热器" if d.kind=="parabolic_trough" else "AC辅机 → 集热器" if d.kind=="solar_thermal" else "AC辅机 → 燃气锅炉" if d.kind=="fuel_boiler" else "AC输入 → 电锅炉" if d.kind=="electric_boiler" else "AC熔盐辅机 → "+DEVICE_NAMES[d.kind] if d.kind in ["solar_tower_receiver","molten_salt_store","salt_steam_generator"] else "70/40热输出 ← 换热器")+" #%d"%int(d.id))
		station_port_picker.set_item_metadata(station_port_picker.item_count-1,int(d.id))
	if station_port_picker.item_count==0:tell("本站没有兼容边界端口；请先进入内部建设锅炉或换热器。");return
	station_port_dialog.dialog_text="端口直接映射到内部设备，不另建容量或重复计能。"
	station_port_dialog.popup_centered()

func update_station_display():
	for facility in stations:
		if facility.get("kind","")=="tower_station" and station_nodes.has(str(int(facility.id))):
			station_nodes[str(int(facility.id))].set_tower_tracking(float(weather_snapshot.get("solar_altitude_deg",0)) if weather_snapshot.get("is_day",true) else -1.0,float(weather_snapshot.get("solar_azimuth_deg",0)))
		if station_is_preview(int(facility.id)):
			if station_nodes.has(str(int(facility.id))):station_nodes[str(int(facility.id))].set_status(0,0,0)
			if int(facility.id)==selected_id:
				selection_label.text=str(facility.name)
				device_summary.text="未投运预览 · 可进入查看镜场与塔体\n4圈径向错列 · 100面4×4 m镜\n总镜面1600 m² · 固定教学太阳姿态\n非实时天气追踪\n无能量端口、无网络连接、零发电。\n镜面仅为结构预览；无接收器热模型、工质或运行循环。"
				source_label.text="独立设施预览，不属于能量设备目录。"
			continue
		var pin:=0.0;var qout:=0.0;var stock:=0.0;var gross:=0.0
		for d in devices:
			if int(d.get("parent_station_id",-1))!=int(facility.id):continue
			var r:Dictionary=result.get("devices",{}).get(str(int(d.id)),{})
			if d.kind=="electric_boiler":pin+=float(r.get("electric_input_mw",0))
			if d.kind in ["solar_tower_receiver","molten_salt_store","salt_steam_generator","fuel_boiler","solar_thermal","parabolic_trough","oil_water_exchanger","steam_generator","steam_condenser","feedwater_pump"]:pin+=float(r.get("auxiliary_electric_mw",0))
			if d.kind=="steam_turbine":gross+=float(r.get("gross_electric_mw",0))
			if d.kind=="heat_exchanger":qout+=float(r.get("output_mwth",0))
			if d.kind in ["thermal_store","high_temp_store","molten_salt_store"]:stock+=float(d.get("state",{}).get("energy_mwhth",0))
		if station_nodes.has(str(int(facility.id))):station_nodes[str(int(facility.id))].set_status(pin,qout,stock)
		if int(facility.id)==selected_id:
			selection_label.text=str(facility.name)
			device_summary.text="电热站整体 · 双击或按“进入”查看内部\n电输入 %.3f MW · 热输出 %.3f MWth\n热库存 %.3f MWhth\n容器只汇总内部活动，不重复产生或消耗能量。"%[pin,qout,stock]
			if devices.any(func(d):return int(d.get("parent_station_id",-1))==int(facility.id) and d.kind=="steam_turbine"):device_summary.text+="\n内部汽轮机毛发电 %.4f kW（独立AC输出）"%(gross*1000)
		if int(facility.id)==selected_id and facility.get("kind","")=="tower_station":device_summary.text="塔式运行站 · 100镜/1600m²/25m塔\n毛发电 %.3f / 全辅机 %.3f kW\n设备净 %.3f kW（未计线损）\n盐热库存 %.4f MWhth\n镜场仅驱动中心接收器一次，不重复计能。"%[gross*1000,pin*1000,(gross-pin)*1000,stock]
	if is_instance_valid(station_enter_button):
		station_enter_button.visible=not station(selected_id).is_empty()
		station_enter_button.text="进入塔式未投运预览" if station_is_preview(selected_id) else "进入塔式熔盐发电站" if station(selected_id).get("kind","")=="tower_station" else "进入电热站内部"
	if is_instance_valid(station_interior) and station_interior.visible:station_interior.refresh()

func normalize_id_cursors():
	while not station(next_id).is_empty():next_id+=1
	while not device(next_station_id).is_empty() or not station(next_station_id).is_empty() or (next_station_id==next_id and next_station_id<=SaveValidator.MAX_ID):next_station_id+=1

func visual_params(params:Dictionary)->Dictionary:
	var result_params:=params.duplicate(true);result_params.visual_dimension_profile=dimension_profile;return result_params

func visual_station(item:Dictionary)->Dictionary:
	var result_item:=item.duplicate(true);result_item.visual_dimension_profile=dimension_profile
	result_item["has_rankine_output"]=not station_is_preview(int(item.id)) and devices.any(func(d):return int(d.get("parent_station_id",-1))==int(item.id) and d.kind=="steam_turbine")
	return result_item

func request_metric_migration():
	if dimension_profile=="metric_v1":tell("当前已采用0.1世界单位/米；本体与检修预留分别显示。");return
	var candidate:=state();candidate.dimension_profile="metric_v1"
	var error:=validate_state(candidate)
	if error!="":tell("米制迁移未执行："+error+"。保留旧坐标与库存；请先调整布局或另建米制示例，不会自动压缩。");return
	ask("按代表规格与模块数量切换米制外形和占地？所有原坐标、容量、库存保持不变；可撤销。",func():checkpoint();restore(candidate);tell("已显式迁移米制；没有缩放布局坐标或修改容量。"))

func update_dimension_display():
	if not is_instance_valid(dimension_summary):return
	if dimension_profile!="metric_v1":dimension_summary.text="旧版示意比例 · 未宣称真实占地
保留原布局；可显式校验米制迁移。";return
	var d:=device(selected_id)
	if station_is_preview(selected_id):
		dimension_summary.text="米制 · 0.1单位/米\n站场160×160m = 25600m²；预览内区120×120m计入站场。\n塔高25m · 镜面4×4m × 100 = 1600m²；零能量输出。";return
	if not station(selected_id).is_empty():
		dimension_summary.text="米制 · 0.1单位/米
站场80×60m = 4800m²；站内48×48m计入其中，不重复计地。
外接圆检修/避让预留7854m²；宽松教学厂区。";return
	if d.is_empty():dimension_summary.text="米制 · 0.1单位/米
本体、检修/避让预留和转子包络分别计量。";return
	var spatial:=Spatial.profile(d.kind,d.params)
	dimension_summary.text="代表模块 %d 个 · 本体投影 %.1f m²
用地包络 %.1f m²（含检修/避让）
%s
%s"%[spatial.module_count,spatial.body_area_m2,spatial.land_envelope_area_m2,spatial.get("description",""),spatial.get("source_note","")]

func wind_visual_speed(params:Dictionary,wind_mps:float)->float:
	if not is_finite(wind_mps) or wind_mps<float(params.get("cut_in_mps",3.0)) or wind_mps>=float(params.get("cut_out_mps",25.0)):return 0.0
	return clampf(wind_mps/12.0,0.0,2.0)

func make_fuel_resource_ui(parent:VBoxContainer)->void:
	var note:=label("天然气为外部资源，不是建设设备。全基地锅炉共享供给上限；默认关闭。热值和价格是可改教学假设，不是实时行情。",14)
	note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(note)
	fuel_supply_enabled=CheckButton.new();fuel_supply_enabled.name="FuelSupplyEnabled";fuel_supply_enabled.text="启用天然气外部供给";parent.add_child(fuel_supply_enabled)
	for spec in [["max_input_mw","供给上限 · MW(LHV)",0.0,10000.0,0.1],["lower_heating_value_kwh_per_nm3","低位热值 · kWh/Nm³",0.1,100.0,0.1],["price_per_mwh","教学燃料价 · 元/MWh(LHV)",0.0,1000000.0,1.0]]:
		parent.add_child(label(spec[1],14))
		var spin:=SpinBox.new();spin.name="Fuel_"+spec[0];spin.min_value=spec[2];spin.max_value=spec[3];spin.step=spec[4];spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(spin);fuel_controls[spec[0]]=spin
	var actions:=HBoxContainer.new();parent.add_child(actions)
	button("应用供给",apply_fuel_resource_form,actions).name="ApplyFuelSupply"
	button("取消编辑",sync_fuel_resource_form,actions)
	var scope:=label("Nm³按本模型0°C、101.325 kPa计量；实际气质/计量基准应与供气数据一致。辅机必须接AC；其耗电单列为散失，不伪装为燃料热效率。",13)
	scope.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(scope)
	fuel_summary=label("",14);fuel_summary.name="FuelResourceSummary";fuel_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(fuel_summary)
	sync_fuel_resource_form()

func sync_fuel_resource_form()->void:
	if is_instance_valid(fuel_supply_enabled):fuel_supply_enabled.set_pressed_no_signal(bool(fuel_supply.get("enabled",false)))
	for key in fuel_controls:fuel_controls[key].set_value_no_signal(float(fuel_supply.get(key,FuelSupply.defaults()[key])))

func apply_fuel_resource_form()->void:
	var candidate:=fuel_supply.duplicate(true)
	candidate.enabled=fuel_supply_enabled.button_pressed
	for key in fuel_controls:
		fuel_controls[key].apply();candidate[key]=fuel_controls[key].value
	apply_fuel_supply(candidate)

func apply_fuel_supply(candidate:Dictionary)->bool:
	var error:=FuelSupply.validate(candidate)
	if error!="":tell("未应用燃料资源："+error);return false
	if candidate==fuel_supply:sync_fuel_resource_form();return true
	checkpoint();fuel_supply=candidate.duplicate(true);paused=true;sync_fuel_resource_form();refresh()
	if is_instance_valid(station_interior) and station_interior.visible:station_interior.refresh()
	tell("天然气供给已更新；模拟暂停。累计消耗与成本保留，可撤销。")
	return true

func update_fuel_resource_summary()->void:
	if not is_instance_valid(fuel_summary):return
	var fuel:Dictionary=result.get("fuel",{})
	fuel_summary.text="供给 %s · 共用上限 %.3f MW(LHV)\n实际燃料 %.4f MW(LHV)\n实际气量 %.3f Nm³/h\n燃气出热 %.4f MWth\n辅机电 %.4f MW\n燃料转换散失 %.4f MW\n累计燃料 %.4f MWh(LHV)\n累计气量 %.3f Nm³\n累计辅机 %.4f MWh\n累计教学燃料费 %.2f 元"%["开启" if fuel_supply.enabled else "关闭",fuel_supply.max_input_mw,fuel.get("input_mw",0),fuel.get("volume_nm3_per_h",0),fuel.get("heat_output_mwth",0),fuel.get("auxiliary_electric_mw",0),fuel.get("conversion_loss_mw",0),fuel_energy.input_mwh,fuel_energy.volume_nm3,fuel_energy.auxiliary_mwh,fuel_energy.cost]

func fuel_example()->void:
	# thermal_example checkpoints once; this fixture extension is the same edit.
	thermal_example()
	if stations.is_empty():tell("未建立厂站，燃气示例未添加。");return
	var sid:=int(stations[0].id)
	var position:=Vector2.INF
	var layout_scale:=1.0 if dimension_profile=="metric_v1" else 10.0
	for x in [1.5,-1.5,0.0,1.0,-1.0]:
		for z in [1.5,-1.5,0.0,1.0,-1.0]:
			if can_place_internal(sid,"fuel_boiler",Vector2(x,z)*layout_scale)=="":position=Vector2(x,z)*layout_scale;break
		if is_finite(position.x):break
	if not is_finite(position.x):tell("站内没有燃气锅炉合法安装位置；保留电热示例。");return
	var item:=station(sid);var id:=next_id;next_id+=1
	devices.append({"id":id,"kind":"fuel_boiler","x":item.x,"z":item.z,"parent_station_id":sid,"interior_x":position.x,"interior_z":position.y,"params":templates.fuel_boiler.duplicate(true),"state":{},"model_profile":"thermal_stage1_v1"})
	device(3).params.rated_electric_mw=0.5
	device(6).params.demand_mwth=1.5
	for pair in [[2,id],[id,4],[id,5]]:
		var candidate:=connection_candidate(pair[0],pair[1])
		if Catalog.validate_link(devices,links,candidate)=="":links.append(candidate)
	fuel_supply=FuelSupply.defaults();fuel_supply.enabled=true;fuel_supply.max_input_mw=1.5
	fuel_energy=FuelSupply.initial_energy();solar_energy=SOLAR_ENERGY_ZERO.duplicate(true);high_temp_energy=HighTemp.initial_energy();rankine_energy=Rankine.initial_energy();tower_energy=Tower.initial_energy();sync_fuel_resource_form();normalize_id_cursors()
	selected_id=sid;rebuild_equipment();refresh()
	tell("联合热水教学链：燃气供给1.5 MW(LHV)，辅机必须接AC；燃料/电/热分账，资源和价格是假设，可独立修改。")

func solar_report_text(report:Dictionary)->String:
	var solar:Dictionary=report
	return "非聚光真空管 · 固定90/60°C\n入射 %.4f MW · 光学未捕获 %.4f MW\n潜在散热 %.4f MW · 实际散热 %.4f MW · 可用 %.4f MWth\n有用 %.4f MWth · 弃热 %.4f MWth\n辅机 %.5f MW"%[solar.get("incident_mw",0),solar.get("optical_rejection_mw",0),solar.get("potential_thermal_loss_mw",0),solar.get("thermal_loss_mw",0),solar.get("available_mwth",0),report.get("heat_output_mwth",0),solar.get("curtailed_mwth",0),report.get("auxiliary_electric_mw",0)]

func solar_example()->void:
	if dimension_profile!="metric_v1":tell("太阳能示例需要米制尺寸；请先在尺寸说明中显式迁移米制。");return
	thermal_example()
	if stations.is_empty():return
	var collector:=device(3)
	collector.kind="solar_thermal"
	collector.params=templates.solar_thermal.duplicate(true)
	collector.state={}
	collector.interior_x=-0.7;collector.interior_z=-0.8
	device(4).interior_x=1.2;device(4).interior_z=-0.7
	device(5).interior_x=0.8;device(5).interior_z=1.1
	device(4).params.capacity_mwhth=0.06
	device(4).params.charge_mwth=0.02;device(4).params.discharge_mwth=0.02
	device(5).params.capacity_mwth=0.03
	device(6).params.demand_mwth=0.016
	stations[0].name="太阳能热水站"
	selected_id=int(stations[0].id)
	rebuild_equipment();refresh()
	tell("30.3 m²吸热面积 · 10模块 · 90/60°C非聚光真空管；热需求16 kW。实际集热随等效固定面POA与温度变化，辅机须接AC。")

func high_temp_report_text(kind:String,r:Dictionary)->String:
	if kind=="oil_water_exchanger":
		return "油水换热 · 300/200 → 90/60°C\n热油输入 %.3f kWth · 热水输出 %.3f kWth\n换热散失 %.3f kWth · 泵电 %.3f kW\n泵无电不传热；下游再隔离换热至70/40°C"%[float(r.get("hot_input_mwth",r.get("input_mwth",0)))*1000,float(r.get("warm_output_mwth",r.get("output_mwth",0)))*1000,float(r.get("loss_mwth",0))*1000,float(r.get("auxiliary_electric_mw",0))*1000]
	return (str(sampled(elapsed_s).weather.get("dni_source","DNI来源未声明"))+"\n") + "槽式单轴跟踪 · Therminol 66 · 300/200°C\nDNI %.1f W/m² · 入射余弦 %.3f\n入射 %.3f kW · 光学未捕获 %.3f kW\n潜在散热 %.3f / 实际 %.3f kW\n可用 %.3f / 有用 %.3f / 弃热 %.3f kWth\n辅机 %.3f kW · 无电不送热\n预热固定温区教学代理；不发电"%[r.get("dni_wm2",0),r.get("cos_incidence",0),float(r.get("incident_mw",0))*1000,float(r.get("optical_rejection_mw",0))*1000,float(r.get("potential_thermal_loss_mw",0))*1000,float(r.get("thermal_loss_mw",0))*1000,float(r.get("available_mwth",0))*1000,float(r.get("heat_output_mwth",0))*1000,float(r.get("curtailed_mwth",0))*1000,float(r.get("auxiliary_electric_mw",0))*1000]

func trough_example()->void:
	if dimension_profile!="metric_v1":tell("槽式聚光示例需要米制尺寸；请先显式迁移米制。");return
	thermal_example()
	if stations.is_empty():return
	var sid:int=int(stations[0].id)
	var collector:=device(3);collector.kind="parabolic_trough";collector.params=templates.parabolic_trough.duplicate(true);collector.state={};collector.model_profile=Catalog.model_profile(collector.kind)
	collector.interior_x=-1.1;collector.interior_z=-0.65
	var store:=device(4);store.kind="high_temp_store";store.params=templates.high_temp_store.duplicate(true);store.state=Catalog.initial_state(store.kind,store.params);store.model_profile=Catalog.model_profile(store.kind);store.interior_x=1.1;store.interior_z=-1.1
	device(5).interior_x=1.1;device(5).interior_z=1.1
	device(5).params.capacity_mwth=0.1
	var oil_id:=next_id;next_id+=1
	devices.append({"id":oil_id,"kind":"oil_water_exchanger","x":collector.x,"z":collector.z,"parent_station_id":sid,"interior_x":-0.65,"interior_z":1.35,"params":templates.oil_water_exchanger.duplicate(true),"state":{},"model_profile":Catalog.model_profile("oil_water_exchanger")})
	device(6).params.demand_mwth=0.025
	links=[]
	for pair in [[0,2],[1,2],[2,3],[2,7],[2,oil_id],[3,4],[3,oil_id],[4,oil_id],[oil_id,5],[5,6]]:links.append(connection_candidate(pair[0],pair[1]))
	stations[0].name="槽式导热油热站"
	selected_id=sid;rebuild_equipment();refresh()
	tell("单槽12×5.77m / 69.24m²；300/200°C油储0.2MWh → 90/60°C → 70/40°C，需求25kW。DNI独立，辅机与换热泵须接AC；预热教学模型，不发电。")

func rankine_report_text(kind:String,r:Dictionary)->String:
	var text:="闭式蒸汽循环 · 质量流量 %.6f kg/s\n"%float(r.get("mass_flow_kg_s",0))
	match kind:
		"salt_steam_generator":text+="565/290°C熔盐 → 1MPa/280°C蒸汽\n盐热输入 %.4f kWth · 蒸汽增焓 %.4f kWth\n发生器散失 %.4f kWth · 盐泵辅机 %.4f kW"%[float(r.get("salt_input_mwth",0))*1000,float(r.get("steam_heat_mwth",0))*1000,float(r.get("loss_mwth",0))*1000,float(r.get("auxiliary_electric_mw",0))*1000]
		"steam_generator":text+="300/200°C油 → 1MPa/280°C蒸汽\n油热输入 %.4f kWth · 蒸汽增焓 %.4f kWth\n发生器散失 %.4f kWth · 油泵辅机 %.4f kW"%[float(r.get("oil_input_mwth",0))*1000,float(r.get("steam_heat_mwth",0))*1000,float(r.get("loss_mwth",0))*1000,float(r.get("auxiliary_electric_mw",0))*1000]
		"steam_turbine":text+="1MPa/280°C → 10kPa湿蒸汽\n毛发电 %.4f kW · 发电机损失 %.4f kW\n毛电须送至变电站；运行辅机须由外部风光或电池保障。"%[float(r.get("gross_electric_mw",0))*1000,float(r.get("generator_loss_mw",0))*1000]
		"steam_condenser":text+="10kPa/45.806°C冷凝 · 环境散热\n实际排热 %.4f / 可用排热 %.4f kWth\n冷却辅机 %.4f kW · 热量不计为供热服务"%[float(r.get("condenser_rejection_mwth",0))*1000,float(r.get("available_rejection_mwth",0))*1000,float(r.get("auxiliary_electric_mw",0))*1000]
		"feedwater_pump":text+="10kPa冷凝水 → 1MPa给水\n泵用电 %.4f kW · 水力增焓 %.4f kW\n电机损失 %.4f kW"%[float(r.get("pump_electric_mw",0))*1000,float(r.get("pump_hydraulic_mw",0))*1000,float(r.get("pump_motor_loss_mw",0))*1000]
	return text+"\n"+str(r.get("status_reason","等待闭合回路与辅机供电"))

func rankine_example()->void:
	if dimension_profile!="metric_v1":tell("蒸汽循环示例需要米制尺寸；请先显式迁移米制。");return
	trough_example()
	if stations.is_empty():return
	var sid:int=int(stations[0].id)
	devices=devices.filter(func(d):return not int(d.id) in [5,6,8])
	device(4).params.charge_mwth=0.01
	device(7).params.demand_mw=0.01
	device(0).params.rated_mw=0.03
	device(1).params.dc_capacity_mw=0.02;device(1).params.inverter_capacity_mw=0.02
	var parent:=station(sid)
	var ids:Dictionary={}
	for spec in [["steam_generator",Vector2(-0.65,1.3)],["steam_turbine",Vector2(0.45,1.3)],["steam_condenser",Vector2(1.3,0.4)],["feedwater_pump",Vector2(0.2,0.1)]]:
		var kind:String=spec[0];var point:Vector2=spec[1];var id:=next_id;next_id+=1;ids[kind]=id
		devices.append({"id":id,"kind":kind,"x":parent.x,"z":parent.z,"parent_station_id":sid,"interior_x":point.x,"interior_z":point.y,"params":templates[kind].duplicate(true),"state":{},"model_profile":Catalog.model_profile(kind)})
	links=[]
	for pair in [[0,2],[1,2],[2,3],[2,7],[2,ids.steam_generator],[2,ids.steam_condenser],[2,ids.feedwater_pump],[3,4],[3,ids.steam_generator],[4,ids.steam_generator],[ids.steam_generator,ids.steam_turbine],[ids.steam_turbine,ids.steam_condenser],[ids.steam_condenser,ids.feedwater_pump],[ids.feedwater_pump,ids.steam_generator],[ids.steam_turbine,2],[2,-1]]:
		links.append(connection_candidate(pair[0],pair[1]))
	stations[0].name="槽式蒸汽发电站"
	selected_id=sid;rebuild_equipment();refresh()
	tell("槽式油热 → 1MPa/280°C闭式蒸汽循环 → 10kPa冷凝；外部风光供辅机，毛/净发电分开。塔式仍是独立未投运预览。")

func tower_report_text(r:Dictionary)->String:
	var sky:Dictionary=sampled(elapsed_s).weather
	var dni_label:String="CSV DNI" if str(sky.get("dni_source","")).begins_with("CSV") else "教学DNI"
	return "熔盐565/290°C · 已预热\n%s · ×%.0f\n4圈100镜/1600m² · 单接收器\n%s %.1f W/m² · 高度 %.1f°\n可用 %.1f / 有用 %.1f kWth\n弃热 %.1f kWth · 夜间DNI归零\n充热 %.1f / 放热 %.1f kWth\n塔辅机 %.2f / 盐泵 %.2f kW\n累计热 %.4f MWhth\n盐侧守恒差 %.8f MWth"%[sky.get("local_datetime",""),speed,dni_label,sky.get("dni_wm2",0),sky.get("solar_altitude_deg",0),float(r.get("available_mwth",0))*1000,float(r.get("useful_mwth",r.get("heat_output_mwth",0)))*1000,float(r.get("curtailed_mwth",0))*1000,float(r.get("charge_mwth",0))*1000,float(r.get("discharge_mwth",0))*1000,float(r.get("receiver_auxiliary_electric_mw",r.get("auxiliary_electric_mw",0)))*1000,float(r.get("store_auxiliary_electric_mw",0))*1000,tower_energy.get("useful_mwhth",0),r.get("balance_error_mwth",0)]

func tower_example()->void:
	if dimension_profile!="metric_v1":tell("塔式运行示例需要米制尺寸；请先显式迁移米制。");return
	checkpoint();devices=[];stations=[];next_station_id=1000000;links=[];imports=[];next_id=0;elapsed_s=0
	energy=ENERGY_ZERO.duplicate(true);thermal_energy=THERMAL_ENERGY_ZERO.duplicate(true);fuel_energy=FuelSupply.initial_energy();solar_energy=SOLAR_ENERGY_ZERO.duplicate(true);high_temp_energy=HighTemp.initial_energy();rankine_energy=Rankine.initial_energy();tower_energy=Tower.initial_energy();paused=true;accumulator=0
	climate_config=Climate.defaults();climate_config.start_local="2026-06-21T12:00:00";climate_config.scenario="clear"
	if is_instance_valid(climate_panel):climate_panel.set_config(climate_config)
	var placed:=false
	for x in [21.0,0.0,-21.0,42.0,-42.0]:
		for z in [14.0,0.0,-21.0,35.0]:
			if can_place("tower_station",Vector2(x,z))=="":placed=add_station(Vector2(x,z),false,"tower_station");break
		if placed:break
	if not placed:tell("当前场地没有合法160×160m塔站地块。");return
	var sid:int=int(stations[0].id);stations[0].name="塔式熔盐昼夜发电站"
	var ids:Dictionary={}
	for kind in ["wind","station","battery","load"]:
		placed=false
		for x in range(-50,61,10):
			for z in range(-30,41,10):
				if can_place(kind,Vector2(x,z))=="":
					var id:=next_id
					placed=add_equipment(kind,Vector2(x,z),false);ids[kind]=id;break
			if placed:break
		if not placed:tell("塔站示例外部辅电设备无合法位置。");return
	device(ids.wind).params.rated_mw=0.2
	device(ids.battery).params.capacity_mwh=1.0
	device(ids.battery).state.energy_mwh=0.5
	device(ids.load).params.demand_mw=0.1
	var parent:=station(sid)
	for spec in [["solar_tower_receiver",Vector2.ZERO],["molten_salt_store",Vector2(-1.1,-1.1)],["salt_steam_generator",Vector2(-1.3,1.2)],["steam_turbine",Vector2(0,1.25)],["steam_condenser",Vector2(1.2,1.2)],["feedwater_pump",Vector2(1.15,0)]]:
		var kind:String=spec[0];var point:Vector2=spec[1];var id:=next_id;next_id+=1;ids[kind]=id
		if kind in ["solar_tower_receiver","molten_salt_store","salt_steam_generator","steam_turbine","steam_condenser","feedwater_pump"] and parent.get("kind","")=="tower_station":
			if can_place_internal(sid,kind,point)!="":
				var found:=false
				for ring in [1.0,1.2,0.8,1.4,5.5]:
					for angle in range(0,360,15):
						var trial:Vector2=Vector2(cos(deg_to_rad(angle)),sin(deg_to_rad(angle)))*ring
						if can_place_internal(sid,kind,trial)=="":point=trial;found=true;break
					if found:break
				if not found:
					for xi in range(-55,56,4):
						for zi in range(-55,56,4):
							var trial:=Vector2(xi,zi)*0.1
							if can_place_internal(sid,kind,trial)=="":point=trial;found=true;break
						if found:break
				if not found:tell("无法合法布置 "+kind);return
		devices.append({"id":id,"kind":kind,"x":parent.x,"z":parent.z,"parent_station_id":sid,"interior_x":point.x,"interior_z":point.y,"params":templates[kind].duplicate(true),"state":Catalog.initial_state(kind,templates[kind]),"model_profile":Catalog.model_profile(kind)})
	for pair in [[ids.wind,ids.station],[ids.battery,ids.station],[ids.station,ids.load],[ids.station,ids.solar_tower_receiver],[ids.station,ids.molten_salt_store],[ids.station,ids.salt_steam_generator],[ids.station,ids.steam_condenser],[ids.station,ids.feedwater_pump],[ids.solar_tower_receiver,ids.molten_salt_store],[ids.solar_tower_receiver,ids.salt_steam_generator],[ids.molten_salt_store,ids.salt_steam_generator],[ids.salt_steam_generator,ids.steam_turbine],[ids.steam_turbine,ids.steam_condenser],[ids.steam_condenser,ids.feedwater_pump],[ids.feedwater_pump,ids.salt_steam_generator],[ids.steam_turbine,ids.station],[ids.station,-1]]:
		var edge:=connection_candidate(pair[0],pair[1])
		if not edge.is_empty():links.append(edge)
	selected_id=sid;normalize_id_cursors();set_mode("select");distance=60;target=Vector3(parent.x,0,parent.z);update_camera();rebuild_equipment();refresh()
	tell("12:00 UTC+8起点 · 35°N/105°E · 内置晴天随模拟时钟昼夜推进，无需CSV。正午充热、日落后靠盐储发电，耗尽即停；风机/0.5MWh初始电池供辅电；独立电需求100kW。可暂停、倍速、存读档。")
