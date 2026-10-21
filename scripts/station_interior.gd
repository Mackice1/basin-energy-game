extends Window
## A view/controller of the host's authoritative station devices. There is no
## second model, terrain, clock, inventory, or copied simulation state here.
## Public API: setup(host), open_station(station_id), refresh(), close_station(),
## focus_selection(), reset_camera(), set_camera_view(yaw, pitch, distance), undo_edit().
const UITheme = preload("res://scripts/ui_theme.gd")
const Visual = preload("res://scripts/equipment_visual.gd")
const SpeedControl = preload("res://scripts/speed_control.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const INTERNAL_KINDS := ["steam_generator","steam_turbine","steam_condenser","feedwater_pump","electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "high_temp_store", "oil_water_exchanger", "thermal_store", "heat_exchanger","solar_tower_receiver","molten_salt_store","salt_steam_generator"]
const NAMES := {"solar_tower_receiver":"塔式接收器","molten_salt_store":"双罐熔盐储热","salt_steam_generator":"熔盐蒸汽发生器","steam_generator":"蒸汽发生器","steam_turbine":"汽轮发电机","steam_condenser":"蒸汽冷凝器","feedwater_pump":"给水泵","electric_boiler":"电热水锅炉", "fuel_boiler":"燃气热水锅炉", "parabolic_trough":"槽式聚光集热器", "high_temp_store":"高温油储热", "oil_water_exchanger":"油水换热器", "solar_thermal":"太阳能集热器", "thermal_store":"储热罐", "heat_exchanger":"隔离换热器"}
const HALF_EXTENT := 24.0
const GRID_STEP := 2.0
const DEFAULT_CAMERA_DISTANCE := 62.0
const DEFAULT_CAMERA_YAW := 145.0
const DEFAULT_CAMERA_PITCH := 30.0
const MIN_CAMERA_DISTANCE := 18.0
const MAX_CAMERA_DISTANCE := 110.0
const MIN_CAMERA_PITCH := 16.0
const MAX_CAMERA_PITCH := 76.0
const AC_COLOR := Color("66a9d2")
const PRIMARY_COLOR := Color("df9155")
const SECONDARY_COLOR := Color("f2ca6e")
const SELECTED_COLOR := Color("f4d476")
const HOVER_COLOR := Color("dcece8")
const COMPATIBLE_COLOR := Color("64e2d1")
const SOURCE_COLOR := Color("ffc06a")
const DRAG_THRESHOLD_PX := 5.0

var host: Node
var station_id := -1
var preview_only := false
var tower_site := false
var tower_geometry:Node3D
var interior_sun:DirectionalLight3D
var interior_environment:Environment
var inactive_build_tools:Node
var build_category: OptionButton
var build_category_row: HBoxContainer
var build_toolbar: HFlowContainer
var edit_toolbar: HFlowContainer
var selected_id := -1
var interaction_mode := "select"
var build_kind := "electric_boiler"
var pending_link := -1
var viewport: SubViewport
var view_container: SubViewportContainer
var camera: Camera3D
var scene_root: Node3D
var scenery_root: Node3D
var visual_scale := 1.0
var dimension_profile := "legacy_illustrative"
var equipment_root: Node3D
var connections_root: Node3D
var equipment_nodes: Dictionary = {}
var name_labels: Dictionary = {}
var title_label: Label
var status_label: Label
var summary_label: Label
var selected_label: Label
var hover_label: Label
var input_ports_label: Label
var output_ports_label: Label
var device_picker: OptionButton
var link_from: OptionButton
var link_to: OptionButton
var remove_confirmation: ConfirmationDialog
var run_button: Button
var speed_control: Control
var sidebar_tabs: TabContainer
var connection_help: Label
var connect_button: Button
var tools: Dictionary = {}
var preview: Node3D
var refresh_timer: Timer
var _built := false
var _font: Font
var _visual_signatures: Dictionary = {}
var _picker_signature := "!uninitialized"
var _connection_signature := ""
var _pending_remove := -1
var _last_cursor := Vector2.ZERO
var _has_cursor := false
var hovered_id := -1
var camera_target := Vector3(0, 1.7, 0)
var camera_yaw := DEFAULT_CAMERA_YAW
var camera_pitch := DEFAULT_CAMERA_PITCH
var camera_distance := DEFAULT_CAMERA_DISTANCE
var placement_grid: MeshInstance3D
var _orbit_drag := false
var _pan_drag := false
var _drag_distance := 0.0
var _left_pan_pending := false
var _left_pan_active := false
var _left_pan_start := Vector2.ZERO
var _left_pan_pick := -1
var _left_pan_double := false
# Transient input state only. The host remains untouched until a valid release.
var _move_drag_candidate := -1
var _move_drag_active := false
var _move_drag_start := Vector2.ZERO
var _move_drag_origin := Vector2.ZERO
var _move_drag_grab := Vector2.ZERO
var _label_nodes: Dictionary = {}
var _materials: Dictionary = {}
var _tube_meshes: Dictionary = {}
var _base_viewport: Viewport
var _base_render_disabled_before := false
var _base_render_suspended := false

func setup(controller: Node) -> void:
	host = controller
	_read_dimension_profile()
	_build_ui()

func _read_dimension_profile() -> void:
	var next_profile := "metric_v1" if is_instance_valid(host) and host.get("dimension_profile") == "metric_v1" else "legacy_illustrative"
	if dimension_profile == next_profile: return
	dimension_profile = next_profile
	visual_scale = 0.1 if dimension_profile == "metric_v1" else 1.0
	if is_instance_valid(scene_root):
		_clear_preview()
		scene_root.free()
		equipment_nodes.clear()
		name_labels.clear()
		_label_nodes.clear()
		_visual_signatures.clear()
		_connection_signature = ""
		_build_world()

func _footprint(kind: String, params: Dictionary = {}) -> float:
	return Visual.footprint(kind, _visual_params(params))

func _visual_params(params: Dictionary) -> Dictionary:
	var value := params.duplicate(true)
	value["visual_dimension_profile"] = dimension_profile
	return value

func open_station(id: int) -> bool:
	if not is_instance_valid(host) or host.station(id).is_empty():
		return false
	_build_ui()
	station_id = id
	var next_preview:bool = host.station(id).get("kind", "thermal_station") == "tower_station_preview"
	var next_tower:bool = host.station(id).get("kind", "") in ["tower_station_preview","tower_station"]
	var mode_changed:bool = next_preview != preview_only or next_tower != tower_site
	tower_site = next_tower
	preview_only = next_preview
	_read_dimension_profile()
	if mode_changed: _rebuild_interior_world()
	selected_id = -1
	interaction_mode = "select"
	pending_link = -1
	_pending_remove = -1
	sidebar_tabs.current_tab = 0
	build_category.select(0)
	remove_confirmation.hide()
	_picker_signature = "!uninitialized"
	_connection_signature = ""
	_reset_move_drag()
	_clear_preview()
	_has_cursor = false
	hovered_id = -1
	_orbit_drag = false
	_pan_drag = false
	refresh()
	reset_camera()
	var available := Vector2i(get_tree().root.get_visible_rect().size)
	var target := Vector2i(mini(1320, available.x - 48), mini(850, available.y - 48))
	popup_centered(Vector2i(maxi(900, target.x), maxi(570, target.y)))
	_suspend_base_rendering()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	refresh_timer.start()
	_set_status("未投运预览：左拖平移 · 右拖环视 · 中拖平移 · 滚轮缩放；无能量端口、禁止建设运行设备。" if preview_only else "左拖平移 · 移动工具调整设备 · 右拖环视 · 中拖平移 · 滚轮缩放。Esc：取消操作 → 清除选择 → 返回。")
	return true

func close_station() -> void:
	interaction_mode = "select"
	pending_link = -1
	_pending_remove = -1
	_has_cursor = false
	_orbit_drag = false
	_pan_drag = false
	hovered_id = -1
	_reset_move_drag()
	_clear_preview()
	remove_confirmation.hide()
	refresh_timer.stop()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_restore_base_rendering()
	hide()
	if is_instance_valid(host) and not host.station(station_id).is_empty():
		host.select_device(station_id)

func _build_ui() -> void:
	if _built:
		return
	_built = true
	name = "StationInterior"
	title = "电热站内部"
	size = Vector2i(1320, 850)
	min_size = Vector2i(900, 570)
	transient = true
	exclusive = false # Existing host parameter dialog is an exclusive sibling.
	visible = false
	_font = load("res://assets/InterfaceCJK.ttc")
	var ui_theme := UITheme.create(_font)
	var parameter_window = host.get("param_dialog") if is_instance_valid(host) else null
	theme = parameter_window.theme if is_instance_valid(parameter_window) and parameter_window.theme != null else ui_theme
	close_requested.connect(close_station)
	window_input.connect(_window_input)
	size_changed.connect(_on_window_resized)
	get_tree().root.size_changed.connect(_fit_to_parent_window)
	focus_exited.connect(func():
		_orbit_drag = false
		_pan_drag = false
		if _move_drag_active: _cancel_move_drag("移动已取消：窗口失去焦点，设备保留原位。")
		else: _reset_move_drag())
	var background := ColorRect.new()
	background.color = Color("0c151e")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 9)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	title_label = _label("电热站内部", 22)
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.clip_text = true
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	tools.focus = _button("聚焦所选", focus_selection, header, "FocusInternalSelection")
	_button("全景", reset_camera, header, "ResetInteriorView")
	_button("返回基地", close_station, header, "ReturnToBase")
	# Separate construction from editing. Each row wraps within the window;
	# no essential command disappears into a horizontal strip at 1024 × 768.
	build_category_row = HBoxContainer.new()
	build_category_row.name = "ConstructionCategoryRow"
	layout.add_child(build_category_row)
	var category_caption:=_label("设备库",14)
	category_caption.custom_minimum_size.x=58
	category_caption.autowrap_mode=TextServer.AUTOWRAP_OFF
	build_category_row.add_child(category_caption)
	build_category = OptionButton.new()
	build_category.name = "ConstructionCategory"
	for caption in ["常用 · 电热 / 低温", "槽式 / 导热油", "蒸汽发电循环", "全部适用设备"]: build_category.add_item(caption)
	build_category.custom_minimum_size=Vector2(230,32)
	build_category_row.add_child(build_category)
	build_category.item_selected.connect(func(_index):refresh())
	var library_hint:=_label("切换分类查找设备 · 选择后在场地连续放置 · Esc 取消",12)
	library_hint.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	library_hint.add_theme_color_override("font_color",UITheme.MUTED)
	build_category_row.add_child(library_hint)
	build_toolbar = HFlowContainer.new()
	inactive_build_tools=Node.new();inactive_build_tools.name="InactiveConstructionTools";add_child(inactive_build_tools)
	build_toolbar.name = "StationBuildToolbar"
	build_toolbar.add_theme_constant_override("h_separation", 6)
	build_toolbar.add_theme_constant_override("v_separation", 5)
	layout.add_child(build_toolbar)
	build_toolbar.add_child(_toolbar_caption("建设"))
	for kind in INTERNAL_KINDS:
		tools[kind] = _button("＋ " + NAMES[kind], start_build.bind(kind), build_toolbar, "Build_" + kind)
	var toolbar := HFlowContainer.new()
	edit_toolbar = toolbar
	toolbar.name = "StationEditToolbar"
	toolbar.add_theme_constant_override("h_separation", 6)
	toolbar.add_theme_constant_override("v_separation", 5)
	layout.add_child(toolbar)
	toolbar.add_child(_toolbar_caption("编辑"))
	tools.select = _button("选择", set_interaction_mode.bind("select"), toolbar, "Select")
	tools.move = _button("移动", _start_move, toolbar, "Move")
	tools.connect = _button("连接", set_interaction_mode.bind("connect"), toolbar, "Connect")
	tools.lines = _button("设备线路", _open_line_settings, toolbar, "DeviceLines")
	tools.parameters = _button("参数", _open_parameters, toolbar, "Parameters")
	tools.remove = _button("拆除…", request_remove, toolbar, "Remove")
	tools.undo = _button("撤销", undo_edit, toolbar, "UndoInteriorEdit")
	tools.undo.tooltip_text = "撤销最近一次编辑（Ctrl+Z / ⌘Z）；模拟将暂停。预览中先取消当前操作。"
	tools.cancel = _button("取消 / 清选", _cancel_current_interaction, toolbar, "CancelInteriorInteraction")
	tools.cancel.tooltip_text = "Esc：先取消当前操作，再清除设备选择，最后返回基地。"
	for key in INTERNAL_KINDS + ["select", "move", "connect"]: tools[key].toggle_mode = true
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	layout.add_child(body)
	var view_panel := PanelContainer.new()
	view_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(view_panel)
	view_container = SubViewportContainer.new()
	view_container.name = "InteriorViewportContainer"
	view_container.custom_minimum_size = Vector2(540, 320)
	view_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view_container.stretch = true
	view_container.mouse_filter = Control.MOUSE_FILTER_STOP
	view_panel.add_child(view_container)
	viewport = SubViewport.new()
	viewport.name = "InteriorViewport"
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.size = Vector2i(800, 620)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view_container.add_child(viewport)
	view_container.gui_input.connect(_view_input)
	view_container.mouse_exited.connect(_view_mouse_exited)
	view_container.resized.connect(_fit_visible_labels)
	_build_world()
	sidebar_tabs = TabContainer.new()
	sidebar_tabs.name = "StationSidebarTabs"
	sidebar_tabs.custom_minimum_size.x = 310
	sidebar_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar_tabs.clip_contents = true
	body.add_child(sidebar_tabs)
	# The host theme styles buttons but not tabs; never inherit a dark default
	# panel underneath our dark-green text.
	sidebar_tabs.add_theme_stylebox_override("panel", _sidebar_style(Color("14212b"), 3))
	for tabs in [sidebar_tabs, sidebar_tabs.get_tab_bar()]:
		tabs.add_theme_font_size_override("font_size", 14)
		for key in ["font_selected_color", "font_unselected_color", "font_hovered_color", "font_focus_color"]:
			tabs.add_theme_color_override(key, Color("edf3f6"))
		for entry in [["tab_selected", Color("254e4e")], ["tab_unselected", Color("1c2d3a")], ["tab_hovered", Color("2b4352")], ["tab_disabled", Color("17242e")]]:
			tabs.add_theme_stylebox_override(entry[0], _sidebar_style(entry[1], 8))
	var side := _sidebar_page("StationOverviewScroll", "设备与运行")
	side.add_child(_label("站内设备", 17))
	device_picker = OptionButton.new()
	device_picker.name = "InternalDevicePicker"
	device_picker.fit_to_longest_item = false
	device_picker.custom_minimum_size.y = 34
	side.add_child(device_picker)
	device_picker.item_selected.connect(func(index: int): _select(int(device_picker.get_item_metadata(index))))
	selected_label = _label("", 14)
	selected_label.name = "SelectedInternalDeviceState"
	selected_label.add_theme_constant_override("line_spacing", 4)
	side.add_child(selected_label)
	tools.details = _button("查看设备详情 →", _open_device_details, side, "OpenInternalDeviceDetails")
	tools.details.tooltip_text = "打开所选设备的二级详情；也可在选择模式双击设备。"
	hover_label = _label("", 12)
	hover_label.name = "InteriorHoverHelp"
	hover_label.add_theme_color_override("font_color", Color("a5b7c4"))
	side.add_child(hover_label)
	side.add_child(HSeparator.new())
	side.add_child(_label("与基地共用模拟时间", 17))
	run_button = _button("运行", _toggle_run, side, "RunHostSimulation")
	speed_control = SpeedControl.new()
	side.add_child(speed_control)
	speed_control.speed_changed.connect(func(value: float):
		if host.has_method("set_simulation_speed"): host.set_simulation_speed(value)
		refresh())
	summary_label = _label("", 14)
	summary_label.name = "StationRuntimeSummary"
	summary_label.add_theme_constant_override("line_spacing", 4)
	side.add_child(summary_label)
	var connections := _sidebar_page("StationConnectionsScroll", "连线与端口")
	connections.add_child(_label("站内热管 / 蒸汽给水闭环", 17))
	var source_label := _label("起点 · 对应载体输出", 13)
	source_label.name = "InternalLinkSourceLabel"
	source_label.add_theme_color_override("font_color", Color("efbc68"))
	connections.add_child(source_label)
	link_from = OptionButton.new()
	link_from.name = "InternalLinkSource"
	link_from.fit_to_longest_item = false
	link_from.custom_minimum_size.y = 34
	connections.add_child(link_from)
	var target_label := _label("↓ 终点 · 对应载体输入", 13)
	target_label.name = "InternalLinkTargetLabel"
	target_label.add_theme_color_override("font_color", Color("89bde3"))
	connections.add_child(target_label)
	link_to = OptionButton.new()
	link_to.name = "InternalLinkTarget"
	link_to.fit_to_longest_item = false
	link_to.custom_minimum_size.y = 34
	connections.add_child(link_to)
	connect_button = _button("连接所选端口", _connect_pickers, connections, "ConnectSelectedPorts")
	connection_help = _label("", 13)
	connection_help.name = "InternalConnectionHelp"
	connection_help.add_theme_constant_override("line_spacing", 3)
	connections.add_child(connection_help)
	link_from.item_selected.connect(func(_index: int): _sync_connection_help())
	link_to.item_selected.connect(func(_index: int): _sync_connection_help())
	connections.add_child(HSeparator.new())
	connections.add_child(_label("对外端口映射", 17))
	input_ports_label = _label("", 13)
	input_ports_label.name = "ExternalACMappings"
	input_ports_label.add_theme_color_override("font_color", Color("89bde3"))
	connections.add_child(input_ports_label)
	output_ports_label = _label("", 13)
	output_ports_label.name = "ExternalHeatMappings"
	output_ports_label.add_theme_color_override("font_color", Color("efbc68"))
	connections.add_child(output_ports_label)
	connections.add_child(_label("在基地连接站体时，可分别选择每台电锅炉 AC 入口、燃气锅炉辅机 AC 入口或换热器 70/40°C 出口。天然气取自基地共享供应，外部需求位于基地。", 12))
	status_label = _label("", 14)
	status_label.custom_minimum_size.y = 42
	status_label.max_lines_visible = 2
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.name = "InteriorStatus"
	layout.add_child(status_label)
	remove_confirmation = ConfirmationDialog.new()
	remove_confirmation.name = "ConfirmRemoveInternalDevice"
	remove_confirmation.title = "拆除站内设备"
	remove_confirmation.ok_button_text = "拆除"
	remove_confirmation.cancel_button_text = "取消"
	remove_confirmation.min_size = Vector2i(440, 180)
	add_child(remove_confirmation)
	remove_confirmation.confirmed.connect(_confirm_remove)
	remove_confirmation.canceled.connect(func(): _pending_remove = -1)
	refresh_timer = Timer.new()
	refresh_timer.name = "ReadOnlyDisplayRefresh"
	refresh_timer.wait_time = 0.25
	refresh_timer.timeout.connect(refresh)
	add_child(refresh_timer)
	visibility_changed.connect(_visibility_changed)

func _construction_category_allows(kind:String)->bool:
	match build_category.selected:
		0:return kind in ["electric_boiler","fuel_boiler","solar_thermal","thermal_store","heat_exchanger"]
		1:return kind in ["parabolic_trough","high_temp_store","oil_water_exchanger"]
		2:return kind in ["steam_generator","steam_turbine","steam_condenser","feedwater_pump"]
	return true

func _toolbar_caption(caption: String) -> Label:
	var node := _label(caption, 13)
	node.custom_minimum_size = Vector2(40, 34)
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return node

func _sidebar_style(fill: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color("344b59")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

func _sidebar_page(node_name: String, caption: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar_tabs.add_child(scroll)
	sidebar_tabs.set_tab_title(sidebar_tabs.get_tab_count() - 1, caption)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 7)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	return column

func _fit_to_parent_window() -> void:
	if not visible: return
	# Embedded windows use the parent's logical canvas, not physical pixels.
	# Using root.size here applies canvas-items scaling a second time on a small
	# screen. Root resize still invalidates gestures when that canvas is fixed.
	_on_window_resized()
	var available := Vector2i(get_tree().root.get_visible_rect().size)
	var limit := Vector2i(maxi(min_size.x, available.x - 48), maxi(min_size.y, available.y - 48))
	size = size.min(limit)
	position = Vector2i(clampi(position.x, 0, maxi(0, available.x - size.x)), clampi(position.y, 24, maxi(24, available.y - size.y)))

func _on_window_resized() -> void:
	if not is_instance_valid(view_container): return
	# Ray projection changes with the viewport rectangle. Never commit a drag
	# using a press/grab offset measured before a resize, or orbit from stale input.
	_orbit_drag = false
	_pan_drag = false
	_has_cursor = false
	hovered_id = -1
	if _move_drag_active: _cancel_move_drag("移动已取消：窗口尺寸改变，设备保留原位。")
	else:
		_reset_move_drag()
		_clear_preview()
		_sync_annotations()

## The station has its own rendering viewport. Pause only the hidden base
## map's 3D draw work; its process/simulation and GUI remain untouched.
func _suspend_base_rendering() -> void:
	if _base_render_suspended or not is_instance_valid(host): return
	_base_viewport = host.get_viewport()
	if not is_instance_valid(_base_viewport) or _base_viewport == viewport: return
	_base_render_disabled_before = _base_viewport.disable_3d
	_base_viewport.disable_3d = true
	_base_render_suspended = true

func _restore_base_rendering() -> void:
	if not _base_render_suspended: return
	if is_instance_valid(_base_viewport): _base_viewport.disable_3d = _base_render_disabled_before
	_base_render_suspended = false

func _exit_tree() -> void:
	_restore_base_rendering()

func _visibility_changed() -> void:
	if not is_instance_valid(refresh_timer): return
	if visible:
		_suspend_base_rendering()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		refresh_timer.start()
	else:
		_reset_move_drag()
		_orbit_drag = false
		_pan_drag = false
		_has_cursor = false
		hovered_id = -1
		pending_link = -1
		interaction_mode = "select"
		_clear_preview()
		_restore_base_rendering()
		refresh_timer.stop()
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

## Angles are in degrees. Kept public for repeatable view/capture checks.
func set_camera_view(yaw_degrees: float, pitch_degrees: float, distance: float) -> void:
	if not is_finite(yaw_degrees) or not is_finite(pitch_degrees) or not is_finite(distance): return
	camera_yaw = wrapf(yaw_degrees, -180.0, 180.0)
	camera_pitch = clampf(pitch_degrees, MIN_CAMERA_PITCH, MAX_CAMERA_PITCH)
	camera_distance = clampf(distance, MIN_CAMERA_DISTANCE * visual_scale, (320.0 if tower_site else MAX_CAMERA_DISTANCE) * visual_scale)
	_update_camera()

func reset_camera() -> void:
	camera_target = Vector3(0, 1.7 * visual_scale, 0)
	var distance := (175.0 if tower_site else DEFAULT_CAMERA_DISTANCE) * visual_scale
	var members := _members()
	if not members.is_empty() and not tower_site:
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for item in members:
			var point := Vector2(float(item.get("interior_x", 0)), float(item.get("interior_z", 0)))
			var extent := Vector2.ONE * _footprint(item.kind, item.get("params", {}))
			minimum = minimum.min(point - extent)
			maximum = maximum.max(point + extent)
		var middle := (minimum + maximum) * 0.5
		camera_target = Vector3(middle.x, 1.7 * visual_scale, middle.y)
		# Frame the actual plant with breathing room; do not shrink it to a board.
		distance = clampf((maximum - minimum).length() * 1.15 + 7.0 * visual_scale, 26.0 * visual_scale, 85.0 * visual_scale)
	set_camera_view(35.0 if tower_site else DEFAULT_CAMERA_YAW, 42.0 if tower_site else DEFAULT_CAMERA_PITCH, distance)

## Focus is independent of the panorama control and never changes selection.
func focus_selection() -> void:
	var item := _member(selected_id)
	if item.is_empty() or not equipment_nodes.has(selected_id): return
	var visual: Node3D = equipment_nodes[selected_id]
	var bounds: AABB = visual.get_meta("pick_bounds")
	camera_target = Vector3(float(item.get("interior_x", 0)), 1.7 * visual_scale, float(item.get("interior_z", 0)))
	var span := maxf(bounds.size.length(), _footprint(item.kind, item.get("params", {})) * 2.0)
	set_camera_view(camera_yaw, camera_pitch, span * 1.65 + 4.0 * visual_scale)
	_set_status("已聚焦 #%d；全景按钮恢复全站视野。" % selected_id)

func _update_camera() -> void:
	if not is_instance_valid(camera): return
	camera_target.x = clampf(camera_target.x, -_half_extent() * visual_scale, _half_extent() * visual_scale)
	camera_target.z = clampf(camera_target.z, -_half_extent() * visual_scale, _half_extent() * visual_scale)
	camera_target.y = (6.0 if tower_site else 1.7) * visual_scale
	var yaw := deg_to_rad(camera_yaw)
	var pitch := deg_to_rad(camera_pitch)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * camera_distance
	camera.position = camera_target + offset
	camera.look_at(camera_target)
	_fit_visible_labels()
	if _has_cursor: _update_preview(_last_cursor)

func _pan_camera(delta: Vector2) -> void:
	var scale := 2.0 * camera_distance * tan(deg_to_rad(camera.fov * 0.5)) / maxf(view_container.size.y, 1.0)
	var right := Vector3(camera.basis.x.x, 0, camera.basis.x.z).normalized()
	var forward := Vector3(camera.basis.z.x, 0, camera.basis.z.z).normalized()
	camera_target += (-right * delta.x - forward * delta.y) * scale
	_update_camera()

func _label(value: String, font_size: int = 15) -> Label:
	var node := Label.new()
	node.text = value
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", Color("edf3f6"))
	return node

func _button(caption: String, callback: Callable, parent: Node, node_name: String) -> Button:
	var node := Button.new()
	node.name = node_name
	node.text = caption
	node.tooltip_text=caption
	node.custom_minimum_size.y = 34
	parent.add_child(node)
	node.pressed.connect(callback)
	return node

func _material(color: Color) -> StandardMaterial3D:
	if _materials.has(color): return _materials[color]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	_materials[color] = material
	return material

func _box(parent: Node3D, node_name: String, dimensions: Vector3, at: Vector3, tint: Color) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = dimensions
	var node := MeshInstance3D.new()
	node.name = node_name
	if node_name in ["GroundShoulder", "FoundationFooting", "StationFloor", "ConcreteJoint", "ServiceLane", "LaneMark"]:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.mesh = shape
	node.material_override = _material(tint)
	node.position = at
	parent.add_child(node)
	return node

func _build_world() -> void:
	scene_root = Node3D.new()
	scene_root.name = "StationInteriorWorld"
	viewport.add_child(scene_root)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	interior_environment=environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("87989f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c8d8e4")
	environment.ambient_light_energy = 0.55
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("7897b2")
	sky_material.sky_horizon_color = Color("b5c4c8")
	sky_material.ground_horizon_color = Color("8d9790")
	sky_material.ground_bottom_color = Color("59635c")
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	scene_root.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	interior_sun=sun
	sun.name = "AfternoonKeyLight"
	sun.rotation_degrees = Vector3(-38, -38, 0)
	sun.light_color = Color("fff0d7")
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 130.0 * visual_scale
	sun.shadow_bias = 0.12
	sun.shadow_normal_bias = 0.8
	sun.light_angular_distance = 1.8
	scene_root.add_child(sun)
	camera = Camera3D.new()
	camera.name = "InteriorCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 48.0
	camera.near = 0.1 * visual_scale
	camera.far = 320.0 * visual_scale
	camera.current = true
	scene_root.add_child(camera)
	_update_camera()
	scenery_root = Node3D.new()
	scenery_root.name = "CivilYard"
	scenery_root.scale = Vector3.ONE * visual_scale
	scene_root.add_child(scenery_root)
	if tower_site:
		_build_tower_preview_world()
		return
	# The shoulder and a thick civil foundation give a grounded, dimensional
	# yard. These meshes are scenery, with no simulation devices or flows.
	_box(scenery_root, "GroundShoulder", Vector3(180, 0.25, 180), Vector3(0, -1.08, 0), Color("606d64"))
	_box(scenery_root, "FoundationFooting", Vector3(50.0, 0.35, 50.0), Vector3(0, -0.78, 0), Color("454d4b"))
	_box(scenery_root, "StationFloor", Vector3(HALF_EXTENT * 2, 0.95, HALF_EXTENT * 2), Vector3(0, -0.475, 0), Color("858b85"))
	# Quiet expansion joints have a much larger spacing than the placement grid.
	for coordinate in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		_box(scenery_root, "ConcreteJoint", Vector3(0.025, 0.008, 48), Vector3(coordinate, 0.006, 0), Color("737a74"))
		_box(scenery_root, "ConcreteJoint", Vector3(48, 0.008, 0.025), Vector3(0, 0.006, coordinate), Color("737a74"))
	# All service-lane details stay outside the valid build footprint.
	_box(scenery_root, "ServiceLane", Vector3(59, 0.10, 5), Vector3(0, -0.88, -27.5), Color("3f494b"))
	for x in range(-26, 29, 6):
		_box(scenery_root, "LaneMark", Vector3(2.1, 0.012, 0.075), Vector3(x, -0.819, -27.5), Color("b2b198"))
	for x in [-24.35, 24.35]:
		_box(scenery_root, "DrainChannel", Vector3(0.24, 0.12, 48), Vector3(x, -0.52, 0), Color("333e41"))
		for z in range(-23, 24, 2):
			_box(scenery_root, "DrainGrate", Vector3(0.27, 0.035, 0.06), Vector3(x, -0.443, z), Color("697675"))
	for z in [-24.36, 24.36]:
		_box(scenery_root, "FoundationEdge", Vector3(48.9, 0.14, 0.14), Vector3(0, -0.56, z), Color("adb1a4"))
	for x in [-22.0, -11.0, 0.0, 11.0, 22.0]:
		_box(scenery_root, "SafetyBollardFoot", Vector3(0.52, 0.14, 0.52), Vector3(x, -0.84, 24.75), Color("565f5c"))
		_box(scenery_root, "SafetyBollard", Vector3(0.18, 1.0, 0.18), Vector3(x, -0.30, 24.75), Color("727d79"))
		_box(scenery_root, "SafetyBollardCap", Vector3(0.20, 0.15, 0.20), Vector3(x, 0.13, 24.75), Color("b8a66d"))
	var grid := ImmediateMesh.new()
	grid.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in range(-12, 13):
		var coordinate := float(index) * GRID_STEP
		grid.surface_add_vertex(Vector3(coordinate, 0.025, -HALF_EXTENT))
		grid.surface_add_vertex(Vector3(coordinate, 0.025, HALF_EXTENT))
		grid.surface_add_vertex(Vector3(-HALF_EXTENT, 0.025, coordinate))
		grid.surface_add_vertex(Vector3(HALF_EXTENT, 0.025, coordinate))
	grid.surface_end()
	placement_grid = MeshInstance3D.new()
	placement_grid.name = "PlacementGrid"
	placement_grid.mesh = grid
	var grid_material := _material(Color(0.65, 0.75, 0.69, 0.38)).duplicate() as StandardMaterial3D
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	placement_grid.material_override = grid_material
	placement_grid.hide()
	scenery_root.add_child(placement_grid)
	equipment_root = Node3D.new()
	equipment_root.name = "InternalEquipment"
	scene_root.add_child(equipment_root)
	connections_root = Node3D.new()
	connections_root.name = "TypedInternalConnections"
	scene_root.add_child(connections_root)

func _half_extent() -> float:
	return 60.0 if tower_site else HALF_EXTENT

func _rebuild_interior_world() -> void:
	_clear_preview()
	if is_instance_valid(scene_root): scene_root.free()
	equipment_nodes.clear()
	name_labels.clear()
	_label_nodes.clear()
	_visual_signatures.clear()
	_connection_signature = ""
	_build_world()

func _build_tower_preview_world() -> void:
	# A facility-sized, entirely visual scene. No device nodes or carrier ports.
	var preview_geometry := Visual.create("tower_station_preview" if preview_only else "tower_station", {"visual_dimension_profile":"metric_v1", "preview_interior":true}, true)
	tower_geometry=preview_geometry
	preview_geometry.name = "TowerPreviewGeometry"
	scene_root.add_child(preview_geometry)
	preview_geometry.set_annotation_visibility(false, false)
	preview_geometry.set_meta("preview_only", true)
	placement_grid = null
	equipment_root = Node3D.new()
	equipment_root.name = "InternalEquipment"
	scene_root.add_child(equipment_root)
	connections_root = Node3D.new()
	connections_root.name = "TypedInternalConnections"
	scene_root.add_child(connections_root)

func _sign(parent: Node3D, caption: String, at: Vector3, tint: Color, font_size: int = 28) -> Label3D:
	var node := Label3D.new()
	node.text = caption
	node.font = _font
	node.font_size = font_size
	node.pixel_size = 0.017 * visual_scale
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.modulate = tint
	node.outline_size = 6
	node.outline_modulate = Color("263937")
	node.no_depth_test = false
	node.position = at
	parent.add_child(node)
	Visual.fit_screen_label(node, camera, 20.0)
	return node

func _tube(parent: Node3D, a: Vector3, b: Vector3, color: Color, radius: float = 0.10) -> void:
	if a.distance_to(b) < 0.001:
		return
	if not _tube_meshes.has(radius):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = 1.0
		mesh.radial_segments = 10
		_tube_meshes[radius] = mesh
	var node := MeshInstance3D.new()
	node.mesh = _tube_meshes[radius]
	node.material_override = _material(color)
	node.position = (a + b) * 0.5
	node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	node.scale.y = a.distance_to(b)
	parent.add_child(node)

func _members() -> Array:
	var members: Array = []
	if not is_instance_valid(host): return members
	for item in host.devices:
		if int(item.get("parent_station_id", -1)) == station_id and item.get("kind", "") in INTERNAL_KINDS:
			members.append(item)
	return members

func _member(id: int) -> Dictionary:
	if not is_instance_valid(host): return {}
	var item: Dictionary = host.device(id)
	return item if int(item.get("parent_station_id", -1)) == station_id and item.get("kind", "") in INTERNAL_KINDS else {}

func refresh() -> void:
	if not _built or not is_instance_valid(host) or station_id < 0:
		return
	var station_data: Dictionary = host.station(station_id)
	if station_data.is_empty():
		close_station()
		return
	var members := _members()
	if tower_site and not preview_only and is_instance_valid(tower_geometry) and tower_geometry.has_method("set_tower_tracking"):
		var sky:Dictionary=host.sampled(host.elapsed_s).weather
		tower_geometry.set_tower_tracking(float(sky.get("solar_altitude_deg",0)) if sky.get("is_day",true) else -1.0,float(sky.get("solar_azimuth_deg",0)))
		var is_day:bool=sky.get("is_day",true) and float(sky.get("solar_altitude_deg",0))>0
		interior_sun.light_energy=0.8 if is_day else 0.16
		interior_environment.ambient_light_energy=0.55 if is_day else 0.28
		interior_environment.background_color=Color("87989f") if is_day else Color("263a42")
	title_label.text = str(station_data.get("name", "电热站 #%d" % station_id)) + (" · 120 × 120 米预览内区" if preview_only else " · 120 × 120 米熔盐运行内区" if tower_site else " · 48 × 48 米厂区" if dimension_profile == "metric_v1" else " · 旧版示意布局")
	title = title_label.text
	title_label.tooltip_text = title_label.text
	build_category_row.visible = not preview_only and not tower_site
	build_toolbar.visible = not preview_only
	edit_toolbar.visible = not preview_only
	tools.details.visible = not preview_only
	sidebar_tabs.set_tab_hidden(1, preview_only)
	if preview_only:
		_sync_preview_runtime()
		return
	if tower_site:
		summary_label.get_parent().move_child(run_button,0)
		summary_label.get_parent().move_child(speed_control,1)
		summary_label.get_parent().move_child(summary_label,2)
		summary_label.add_theme_font_size_override("font_size",13)
		summary_label.add_theme_constant_override("line_spacing",1)
	else:
		summary_label.get_parent().move_child(summary_label,summary_label.get_parent().get_child_count()-1)
	for kind in INTERNAL_KINDS:
		var active:bool=kind in ["solar_tower_receiver","molten_salt_store","salt_steam_generator","steam_turbine","steam_condenser","feedwater_pump"] if tower_site else not kind in ["solar_tower_receiver","molten_salt_store","salt_steam_generator"]
		if active and not tower_site:active=_construction_category_allows(kind)
		var owner_node:Node=build_toolbar if active else inactive_build_tools
		if tools[kind].get_parent()!=owner_node:tools[kind].reparent(owner_node)
		tools[kind].visible=active
	if _member(selected_id).is_empty():
		selected_id = -1
		if _move_drag_candidate >= 0 or interaction_mode == "move":
			_reset_move_drag()
			interaction_mode = "select"
			_clear_preview()
	if pending_link >= 0 and _member(pending_link).is_empty(): pending_link = -1
	_sync_equipment(members)
	_sync_pickers(members)
	_sync_connections(members)
	_sync_runtime(members)
	_sync_annotations()
	for key in ["move", "parameters", "remove", "lines", "focus", "details"]: tools[key].disabled = selected_id < 0
	for key in INTERNAL_KINDS + ["select", "move", "connect"]:
		tools[key].set_pressed_no_signal(interaction_mode == key or (interaction_mode == "build" and build_kind == key))
	tools.cancel.disabled = interaction_mode == "select" and selected_id < 0 and not _move_drag_active
	tools.undo.disabled = not host.has_method("undo") or (interaction_mode == "select" and not _move_drag_active and not _has_undo_history())
	if _has_cursor and interaction_mode in ["build", "move"]: _update_preview(_last_cursor)

func _sync_equipment(members: Array) -> void:
	var present: Dictionary = {}
	for item in members:
		var id := int(item.id)
		present[id] = true
		var signature := str(item.kind) + JSON.stringify(item.get("params", {}))
		if not equipment_nodes.has(id) or _visual_signatures.get(id, "") != signature:
			if equipment_nodes.has(id):
				equipment_nodes[id].free()
			var node: Node3D = Visual.create(item.kind, _visual_params(item.get("params", {})), true)
			node.name = "InternalDevice_%d" % id
			equipment_root.add_child(node)
			equipment_nodes[id] = node
			_visual_signatures[id] = signature
			var bounds := _visual_bounds(node)
			node.set_meta("pick_bounds", bounds)
			_label_nodes[id] = node.find_children("*", "Label3D", true, false)
			name_labels[id] = _sign(node, "#%d %s" % [id, NAMES[item.kind]], Vector3(0, bounds.end.y + (0.2 if dimension_profile == "metric_v1" else 0.6), 0), Color("eef3e8"), 27)
		var visual: Node3D = equipment_nodes[id]
		visual.position = Vector3(float(item.get("interior_x", 0)), 0, float(item.get("interior_z", 0)))
		visual.set_highlight(id == selected_id)
		if item.kind=="parabolic_trough" and visual.has_method("set_solar_tracking"):
			var sky:Dictionary=host.sampled(host.elapsed_s).weather
			visual.set_solar_tracking(float(sky.get("solar_altitude_deg",0)),float(sky.get("solar_azimuth_deg",0)))
		if item.kind in ["thermal_store","high_temp_store","molten_salt_store"]:
			var capacity := float(item.params.get("capacity_mwhth", 0))
			visual.set_thermal_soc(float(item.get("state", {}).get("energy_mwhth", 0)) / capacity if capacity > 0 else 0.0)
	for id in equipment_nodes.keys():
		if not present.has(id):
			equipment_nodes[id].free()
			equipment_nodes.erase(id)
			name_labels.erase(id)
			_visual_signatures.erase(id)
			_label_nodes.erase(id)

func _sync_pickers(members: Array) -> void:
	var signature := ""
	for item in members: signature += "%d:%s;" % [item.id, item.kind]
	if signature != _picker_signature:
		var old_source := _picker_id(link_from)
		var old_target := _picker_id(link_to)
		device_picker.clear()
		if not members.is_empty(): _add_choice(device_picker, "选择站内设备…", -1)
		link_from.clear()
		link_to.clear()
		for item in members:
			var caption := "#%d %s" % [item.id, NAMES[item.kind]]
			_add_choice(device_picker, caption, item.id)
			if item.kind in ["electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "high_temp_store", "oil_water_exchanger", "thermal_store","steam_generator","steam_turbine","steam_condenser","feedwater_pump"]: _add_choice(link_from, caption + (" · 工质出口" if item.kind in ["steam_generator","steam_turbine","steam_condenser","feedwater_pump"] else " · 热出口"), item.id)
			if item.kind in ["thermal_store", "heat_exchanger", "high_temp_store", "oil_water_exchanger","steam_generator","steam_turbine","steam_condenser","feedwater_pump"]: _add_choice(link_to, caption + (" · 工质入口" if item.kind in ["steam_generator","steam_turbine","steam_condenser","feedwater_pump"] else " · 热入口"), item.id)
		if members.is_empty(): _add_choice(device_picker, "站内尚无设备", -1)
		if link_from.item_count == 0: _add_choice(link_from, "先建设锅炉 / 储热罐", -1)
		if link_to.item_count == 0: _add_choice(link_to, "先建设储热罐 / 换热器", -1)
		_select_choice(link_from, old_source)
		_select_choice(link_to, old_target)
		_picker_signature = signature
	_select_choice(device_picker, selected_id)

func _add_choice(picker: OptionButton, caption: String, id: int) -> void:
	picker.add_item(caption)
	picker.set_item_metadata(picker.item_count - 1, id)

func _picker_id(picker: OptionButton) -> int:
	return int(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 and picker.selected < picker.item_count else -1

func _select_choice(picker: OptionButton, id: int) -> void:
	for index in picker.item_count:
		if int(picker.get_item_metadata(index)) == id:
			picker.select(index)
			return
	if picker == device_picker and id < 0: picker.select(-1)

func _visual_bounds(visual: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for surface in visual.find_children("*", "MeshInstance3D", true, false):
		if surface.name == "SelectionRing" or surface.mesh == null: continue
		var relative: Transform3D = visual.global_transform.affine_inverse() * surface.global_transform
		var bounds: AABB = relative * surface.get_aabb()
		result = result.merge(bounds) if found else bounds
		found = true
	return result if found else AABB(Vector3(-2, 0, -2), Vector3(4, 4, 4))

func _sync_annotations() -> void:
	if is_instance_valid(placement_grid): placement_grid.visible = interaction_mode in ["build", "move"]
	for id in equipment_nodes:
		var selected: bool = id == selected_id
		var source: bool = id == pending_link
		var compatible: bool = interaction_mode == "connect" and pending_link >= 0 and id != pending_link and _connection_error(pending_link, int(id)).is_empty()
		var hovered: bool = id == hovered_id
		var tint := SELECTED_COLOR if selected else SOURCE_COLOR if source else COMPATIBLE_COLOR if compatible else HOVER_COLOR
		var visual: Node3D = equipment_nodes[id]
		visual.set_highlight(selected)
		visual.set_interaction_hint(hovered, compatible, source)
		visual.set_meta("interaction_highlight", "selected" if selected else "source" if source else "compatible" if compatible else "hover" if hovered else "none")
		if name_labels.has(id):
			name_labels[id].visible = selected or source or hovered or compatible
			name_labels[id].modulate = tint
			name_labels[id].text = (_endpoint_caption(int(id)) if source else "已选 · " if selected else _compatible_caption(int(id)) if compatible else "") + "#%d %s" % [id, NAMES[_member(int(id)).kind]]
		# Intrinsic port labels follow the shared equipment annotation policy;
		# the view owns only the separate equipment name and route captions.
		visual.set_annotation_visibility(false, (selected or source or hovered or compatible) and interaction_mode == "connect")
	for route in connections_root.get_children():
		var caption = route.get_meta("caption_node", null)
		if is_instance_valid(caption): caption.visible = interaction_mode == "connect"
	_fit_visible_labels()
	if is_instance_valid(hover_label):
		hover_label.text = _device_hover_help(hovered_id)
		hover_label.visible = not hover_label.text.is_empty()
	_sync_connection_help()

func _fit_visible_labels() -> void:
	if not is_instance_valid(camera): return
	for id in equipment_nodes:
		var visual: Node3D = equipment_nodes[id]
		visual.fit_annotation_labels()
		if name_labels.has(id) and name_labels[id].visible: Visual.fit_screen_label(name_labels[id], camera, 22.0)
	if not is_instance_valid(connections_root): return
	for route in connections_root.get_children():
		var caption = route.get_meta("caption_node", null)
		if is_instance_valid(caption) and caption.visible: Visual.fit_screen_label(caption, camera, 18.0)

func _device_hover_help(id: int) -> String:
	var item := _member(id)
	if item.is_empty(): return ""
	var p: Dictionary = item.get("params", {})
	var text := "悬停 #%d %s\n" % [id, NAMES[item.kind]]
	match item.kind:
		"electric_boiler":
			var electric := float(p.get("rated_electric_mw", 0))
			text += "AC 电输入 → 90/60°C 热水输出\n电额定 %.3f MW · 热上限 %.3f MWth" % [electric, electric * float(p.get("thermal_efficiency", 0))]
		"parabolic_trough":
			text += "DNI → Therminol 66导热油300/200°C\n开口面积 %.2f m² · AC辅机不可省略"%p.get("aperture_area_m2",0)
		"oil_water_exchanger":
			text += "导热油300/200°C → 热水90/60°C\n额定 %.3f MWth · 必须接AC泵电"%p.get("capacity_mwth",0)
		"solar_thermal":
			text += "非聚光真空管 · AC辅机 → 90/60°C\n吸热面积 %.2f m² · 固定面等效POA\n辅机电与下游接纳限制有用集热"%p.get("absorber_area_m2",0)
		"fuel_boiler":
			var fuel := float(p.get("rated_fuel_mw", 0))
			text += "共享天然气 + AC 辅机 → 90/60°C 热水\n燃料额定 %.3f MW(LHV) · 热上限 %.3f MWth\n辅机上限 %.3f MW · 无辅机电不供热" % [fuel, fuel * float(p.get("thermal_efficiency", 0)), fuel * float(p.get("auxiliary_electric_ratio", 0))]
		"molten_salt_store", "thermal_store", "high_temp_store":
			text += "90/60°C 热水 · 热入口 → 库存 → 热出口\n充 / 放 %.3f / %.3f MWth · 库容 %.3f MWhth" % [p.get("charge_mwth", 0), p.get("discharge_mwth", 0), p.get("capacity_mwhth", 0)]
		"heat_exchanger":
			text += "热水 90/60°C 输入 → 70/40°C 输出\n热侧额定 %.3f MWth" % p.get("capacity_mwth", 0)
	if interaction_mode == "connect" and pending_link >= 0:
		var error := _connection_error(pending_link, id)
		if not error.is_empty(): return text + "\n不可连接：" + error
		var candidate := _connection_candidate(pending_link, id)
		text += "\n可连接 #%d.%s → #%d.%s\n%s · 管线容量 %.3f %s" % [candidate.from, candidate.from_port, candidate.to, candidate.to_port, _carrier_caption(candidate), candidate.get("mass_flow_capacity_kg_s",candidate.get("capacity_mwth",0)),candidate.get("unit","MWth")]
	return text

# Prefer the host's canonical candidate. The fallback supports a minimal display
# host in tests; Catalog remains the shared validator for carrier/grade/topology.
func _connection_candidate(first: int, second: int) -> Dictionary:
	if _member(first).is_empty() or _member(second).is_empty() or first == second: return {}
	if host.has_method("connection_candidate"): return host.connection_candidate(first, second)
	for pair in [[first, second], [second, first]]:
		var source := _member(int(pair[0]))
		var target := _member(int(pair[1]))
		if not (source.kind in ["electric_boiler", "fuel_boiler", "solar_thermal"] and target.kind in ["thermal_store", "heat_exchanger"] or source.kind == "thermal_store" and target.kind == "heat_exchanger"): continue
		return {"from":int(pair[0]), "to":int(pair[1]), "from_port":"heat_out", "to_port":"heat_in" if target.kind == "thermal_store" else "hot_in", "carrier":"heat_water", "unit":"MWth", "grade_id":"hw_primary_90_60", "capacity_mwth":2.0, "loss_fraction":0.0}
	return {}

func _carrier_caption(candidate: Dictionary) -> String:
	if candidate.get("carrier", "") == "water_steam": return str(candidate.get("grade_id", "蒸汽/给水"))
	return "heat_salt · 565/290°C" if candidate.get("carrier", "") == "heat_salt" else "heat_oil · 300/200°C" if candidate.get("carrier", "") == "heat_oil" else "heat_water · 90/60°C"

func _connection_error(first: int, second: int) -> String:
	if first == second: return "不能连接到自身；请选择另一台设备。"
	if _member(first).is_empty() or _member(second).is_empty(): return "请选择两台站内设备。"
	var candidate := _connection_candidate(first, second)
	if candidate.is_empty(): return "端口方向 / 温区不兼容；请选择相同载体与方向的端口；蒸汽回路须按发生器 → 汽轮机 → 冷凝器 → 给水泵闭合。"
	return Catalog.validate_link(host.devices, host.links, candidate)

func _endpoint_caption(id: int) -> String:
	match str(_member(id).get("kind", "")):
		"electric_boiler", "fuel_boiler", "solar_thermal": return "起点已选 · "
		"heat_exchanger": return "终点已选 · "
	return "端点已选 · "

func _compatible_caption(id: int) -> String:
	var candidate := _connection_candidate(pending_link, id)
	return "可作起点 · " if int(candidate.get("from", -1)) == id else "可作终点 · "

func _sync_connection_help() -> void:
	if not is_instance_valid(connection_help): return
	var first := _picker_id(link_from)
	var second := _picker_id(link_to)
	var error := _connection_error(first, second)
	connect_button.disabled = not error.is_empty()
	connect_button.tooltip_text = error if not error.is_empty() else "按输出 → 输入连接；与场景内点击设备共用同一连接规则。"
	if interaction_mode == "connect" and pending_link >= 0:
		var item := _member(pending_link)
		connection_help.text = "%s#%d %s\n" % [_endpoint_caption(pending_link), pending_link, NAMES.get(item.get("kind", ""), "设备")]
		match str(item.get("kind", "")):
			"electric_boiler", "fuel_boiler", "solar_thermal": connection_help.text += "在场景点击绿色终点：储热罐或换热器。"
			"heat_exchanger": connection_help.text += "在场景点击绿色起点：锅炉或储热罐。自动按输出 → 输入连接。"
			_: connection_help.text += "在场景点击绿色锅炉作输入起点，或换热器作输出终点。"
		connection_help.text += "\nEsc 取消当前端点。"
	elif not error.is_empty():
		connection_help.text = "端口选择：" + error
	else:
		var candidate := _connection_candidate(first, second)
		connection_help.text = "#%d.%s → #%d.%s\n%s · %.3f %s\n也可点上方“连接”，在场景选择两个端点。" % [candidate.from, candidate.from_port, candidate.to, candidate.to_port, _carrier_caption(candidate), candidate.get("mass_flow_capacity_kg_s",candidate.get("capacity_mwth",0)),candidate.get("unit","MWth")]
	# Hover details must remain readable on the connection tab itself. The
	# overview label keeps its public API, while this mirrors the same live text.
	if interaction_mode == "connect":
		var hover_help := _device_hover_help(hovered_id)
		if not hover_help.is_empty(): connection_help.text += "\n\n" + hover_help

func _port(id: int, port_name: String) -> Vector3:
	var visual: Node3D = equipment_nodes[id]
	return scene_root.to_local(visual.get_named_port_position(port_name))

func _has_port(id: int, port_name: String) -> bool:
	return equipment_nodes.has(id) and equipment_nodes[id].has_named_port(port_name)

func _rounded_route(parent: Node3D, points: Array[Vector3], tint: Color, radius: float) -> void:
	var clean: Array[Vector3] = []
	for point in points:
		if clean.is_empty() or clean.back().distance_to(point) > 0.001: clean.append(point)
	if clean.size() < 2: return
	parent.set_meta("route_points", PackedVector3Array(clean))
	var previous: Vector3 = clean[0]
	for index in range(1, clean.size() - 1):
		var corner: Vector3 = clean[index]
		var incoming: Vector3 = (clean[index - 1] - corner).normalized()
		var outgoing: Vector3 = (clean[index + 1] - corner).normalized()
		if absf(incoming.dot(outgoing)) > 0.99:
			_tube(parent, previous, corner, tint, radius)
			previous = corner
			continue
		var bend := minf(0.40 * visual_scale, minf(corner.distance_to(clean[index - 1]), corner.distance_to(clean[index + 1])) * 0.32)
		var start := corner + incoming * bend
		var finish := corner + outgoing * bend
		_tube(parent, previous, start, tint, radius)
		var last := start
		for step in range(1, 7):
			var t := float(step) / 6.0
			var arc := start.lerp(corner, t).lerp(corner.lerp(finish, t), t)
			_tube(parent, last, arc, tint, radius)
			last = arc
		previous = finish
	_tube(parent, previous, clean.back(), tint, radius)

func _pipe_support(parent: Node3D, at: Vector3) -> void:
	# Avoid actual equipment bounds rather than their large maintenance circle.
	# Supports terminate under the pipe centerline, never float under a rack.
	if at.y < .35 * visual_scale: return
	for visual: Node3D in equipment_nodes.values():
		var bounds: AABB = visual.get_meta("pick_bounds")
		bounds.position += visual.position
		if Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(.15*visual_scale).has_point(Vector2(at.x, at.z)): return
	var tint := Color("737d80")
	_box(parent, "PipeSupportFoot", Vector3(0.65, 0.12, 0.65) * visual_scale, Vector3(at.x, 0.06 * visual_scale, at.z), Color("93968c"))
	_box(parent, "PipeSupportColumn", Vector3(0.10 * visual_scale, at.y - 0.18 * visual_scale, 0.10 * visual_scale), Vector3(at.x, (at.y - 0.18 * visual_scale) * 0.5, at.z), tint)
	_box(parent, "PipeSupportSaddle", Vector3(0.60, 0.13, 0.30) * visual_scale, at - Vector3(0, 0.18 * visual_scale, 0), tint)

func _service_pipe_points(a: Vector3, b: Vector3, lane_z: float, level: float, stub_m: float = .35) -> Array[Vector3]:
	# All authored water service nozzles point toward -Z. First leave the nozzle
	# axially, then use a low accessible service corridor in front of equipment.
	var a_stub := a + Vector3(0,0,-stub_m*visual_scale)
	var b_stub := b + Vector3(0,0,-stub_m*visual_scale)
	return [a, a_stub, Vector3(a_stub.x,level,a_stub.z), Vector3(a_stub.x,level,lane_z), Vector3(b_stub.x,level,lane_z), Vector3(b_stub.x,level,b_stub.z), b_stub, b]

func _physical_return(id: int, port_name: String) -> Variant:
	if not equipment_nodes.has(id): return null
	var visual: Node3D = equipment_nodes[id]
	if not visual.physical_return_locals.has(port_name): return null
	return scene_root.to_local(visual.to_global(visual.physical_return_locals[port_name]))


func _sync_connections(members: Array) -> void:
	var signature := ""
	var rack_height := 3.2 * visual_scale
	for item in members:
		var id := int(item.id)
		var visual: Node3D = equipment_nodes[id]
		var bounds: AABB = visual.get_meta("pick_bounds")
		rack_height = maxf(rack_height, bounds.end.y + 0.85 * visual_scale)
		signature += "%d:%s:%s:%s;" % [id, visual.position, _visual_signatures.get(id, ""), str(visual.named_port_locals)]
	var edges: Array = []
	for edge in host.links:
		if equipment_nodes.has(int(edge.get("from", -1))) or equipment_nodes.has(int(edge.get("to", -1))): edges.append(edge)
	signature += JSON.stringify(edges)
	if signature == _connection_signature: return
	_connection_signature = signature
	for child in connections_root.get_children(): child.free()
	for edge in edges:
		var source_id := int(edge.get("from", -1))
		var target_id := int(edge.get("to", -1))
		var source_inside := equipment_nodes.has(source_id)
		var target_inside := equipment_nodes.has(target_id)
		var from_port := str(edge.get("from_port", ""))
		var to_port := str(edge.get("to_port", ""))
		var carrier := str(edge.get("carrier", ""))
		var tint := PRIMARY_COLOR
		var caption := "565/290°C · 熔盐" if carrier=="heat_salt" else "300/200°C · Therminol 66" if carrier=="heat_oil" else "90/60°C"
		if carrier=="heat_oil":tint=Color("ce843c")
		if carrier=="water_steam":
			tint=Color("a9c6cf");caption=str(edge.get("grade_id","蒸汽/给水"))+" · kg/s"
		var a: Vector3
		var b: Vector3
		var electric := carrier == "electricity_ac"
		if source_inside and target_inside:
			if not carrier in ["heat_water","heat_oil","heat_salt","water_steam"] or not _has_port(source_id, from_port) or not _has_port(target_id, to_port): continue
			a = _port(source_id, from_port)
			b = _port(target_id, to_port)
		elif target_inside and electric and _member(target_id).kind in ["solar_tower_receiver","molten_salt_store","salt_steam_generator","electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "oil_water_exchanger", "steam_generator", "steam_condenser", "feedwater_pump"] and _has_port(target_id, to_port):
			b = _port(target_id, to_port)
			a = Vector3(-_half_extent() * visual_scale, 0.25 * visual_scale, b.z - 1.2 * visual_scale)
			tint = AC_COLOR
			caption = "AC · #%d → #%d" % [source_id, target_id]
		elif source_inside and electric and _member(source_id).kind == "steam_turbine" and _has_port(source_id, from_port):
			a = _port(source_id, from_port)
			b = Vector3(_half_extent() * visual_scale, 0.25 * visual_scale, a.z - 1.2 * visual_scale)
			tint = AC_COLOR;caption = "AC发电 · #%d → #%d" % [source_id, target_id]
		elif source_inside and carrier == "heat_water" and _member(source_id).kind == "heat_exchanger" and _has_port(source_id, from_port):
			a = _port(source_id, from_port)
			b = Vector3(_half_extent() * visual_scale, a.y, a.z - 1.2 * visual_scale)
			tint = SECONDARY_COLOR
			caption = "70/40°C · → #%d" % target_id
		else: continue
		var route := Node3D.new()
		route.name = ("ACCable" if electric else "HeatPipe") + "_%d_%d" % [source_id, target_id]
		route.set_meta("from", source_id)
		route.set_meta("to", target_id)
		route.set_meta("from_port", from_port)
		route.set_meta("to_port", to_port)
		route.set_meta("carrier", carrier)
		route.set_meta("source_position", a)
		route.set_meta("target_position", b)
		connections_root.add_child(route)
		if electric:
			# AC is a low cable in a rectangular tray, not another hot-water pipe.
			var bend := Vector3(b.x, 0.25 * visual_scale, a.z)
			_box(route, "ACCableTray", Vector3(absf(b.x - a.x) + 0.2 * visual_scale, 0.12 * visual_scale, 0.30 * visual_scale), (a + bend) * 0.5 - Vector3(0, 0.07 * visual_scale, 0), Color("334b57"))
			_rounded_route(route, [a, bend, Vector3(b.x, b.y, a.z), b], tint, 0.055 * visual_scale)
		else:
			# Neutral metal insulation is the physical material. Small ID sleeves
			# carry circuit colour separately from thermal/runtime information.
			var lane_z := minf(a.z,b.z) - 1.0*visual_scale
			for visual: Node3D in equipment_nodes.values():
				var bounds: AABB = visual.get_meta("pick_bounds")
				lane_z = minf(lane_z, visual.position.z + bounds.position.z - .85*visual_scale)
			var level := maxf(maxf(a.y,b.y), .90*visual_scale)
			var physical_tint := Color("a8afb0")
			var points := _service_pipe_points(a,b,lane_z,level)
			_rounded_route(route, points, physical_tint, .14*visual_scale)
			route.set_meta("route_style", "physical_low_service_corridor")
			for endpoint in [a,b]:
				_tube(route, endpoint+Vector3(0,0,-.10*visual_scale), endpoint+Vector3(0,0,-.28*visual_scale),tint,.145*visual_scale)
			var ar: Variant = _physical_return(source_id,from_port)
			var br: Variant = _physical_return(target_id,to_port)
			if ar is Vector3 and br is Vector3 and carrier == "heat_water":
				var return_route := Node3D.new()
				return_route.name = "PhysicalReturnService"
				return_route.set_meta("visual_only",true)
				return_route.set_meta("capacity_added",0.0)
				route.add_child(return_route)
				_rounded_route(return_route, _service_pipe_points(ar,br,lane_z-.40*visual_scale,level-.30*visual_scale,.65), physical_tint,.10*visual_scale)
				for endpoint in [ar,br]:
					_tube(return_route,endpoint+Vector3(0,0,-.10*visual_scale),endpoint+Vector3(0,0,-.28*visual_scale),Color("4c829a"),.105*visual_scale)
			var first := Vector3(a.x,level,lane_z)
			var last := Vector3(b.x,level,lane_z)
			var count := maxi(1,ceili(first.distance_to(last)/(4.0*visual_scale)))
			for index in range(count+1):
				var support_at := first.lerp(last,float(index)/count)
				_pipe_support(route,support_at)
				if ar is Vector3 and br is Vector3 and carrier == "heat_water":
					_pipe_support(route,support_at+Vector3(0,-.30*visual_scale,-.40*visual_scale))

		route.set_meta("caption_node", _sign(route, caption, (a + b) * 0.5 + Vector3(0, 1.25 * visual_scale if not electric else 1.0 * visual_scale, 0), tint, 22))

func _sync_preview_runtime() -> void:
	device_picker.clear()
	_add_choice(device_picker, "未投运预览 · 无运行设备", -1)
	device_picker.disabled = true
	selected_label.text = "未投运预览\n25 m塔体 · 100面定日镜\n4圈径向错列 · 东西向道路缺口\n每面4 × 4 m，总镜面1600 m²\n固定教学太阳姿态，非实时天气追踪\n镜场内区120 × 120 m\n基地站场160 × 160 m，计地一次。"
	hover_label.text = "左拖平移 · 右拖环视 · 中拖平移 · 滚轮缩放"
	hover_label.visible = true
	input_ports_label.text = "无输入端口"
	output_ports_label.text = "无输出端口"
	summary_label.text = "本站发电 0 MW\n本站供热 0 MWth\n本站能量库存 0 MWh\n没有接收器热模型、工质、管路或可运行设备。\n预览设施不能连接网络，也不参与调度、累计能量或优化。"
	run_button.text = ("▶ 运行" if host.get("paused") != false else "Ⅱ 暂停") + "基地模拟（预览仍零输出）"
	speed_control.set_speed(float(host.get("speed")))
	connect_button.disabled = true

func _sync_runtime(members: Array) -> void:
	device_picker.disabled = false
	var reports: Dictionary = host.result.get("devices", {})
	var ac := 0.0
	var heat := 0.0
	var gross := 0.0
	var rejected := 0.0
	var rankine_aux := 0.0
	var fuel := 0.0
	var fuel_cost := 0.0
	var fuel_volume := 0.0
	var fuel_count := 0
	var delivered := 0.0
	var stored := 0.0
	var capacity := 0.0
	var ac_mappings: Array[String] = []
	var heat_mappings: Array[String] = []
	for item in members:
		var report: Dictionary = reports.get(str(int(item.id)), {})
		match item.kind:
			"steam_turbine":
				gross += float(report.get("gross_electric_mw",0))
				heat_mappings.append("#%d AC发电 ac_out → %s"%[item.id,_external_peers(int(item.id),false)])
			"salt_steam_generator", "steam_generator", "steam_condenser", "feedwater_pump":
				ac += float(report.get("auxiliary_electric_mw",0))
				rankine_aux += float(report.get("auxiliary_electric_mw",0))
				rejected += float(report.get("condenser_rejection_mwth",0))
				ac_mappings.append("#%d 蒸汽辅机 ac_in ← %s"%[item.id,_external_peers(int(item.id),true)])
			"electric_boiler":
				ac += float(report.get("electric_input_mw", 0))
				heat += float(report.get("heat_output_mwth", report.get("output_mwth", 0)))
				ac_mappings.append("#%d 电锅炉 ac_in ← %s" % [item.id, _external_peers(int(item.id), true)])
			"solar_tower_receiver", "solar_thermal", "parabolic_trough":
				ac += float(report.get("auxiliary_electric_mw",0))
				heat += float(report.get("heat_output_mwth",0))
				ac_mappings.append("#%d 集热辅机 ac_in ← %s"%[item.id,_external_peers(int(item.id),true)])
			"oil_water_exchanger":
				ac += float(report.get("auxiliary_electric_mw",0))
				ac_mappings.append("#%d 油水泵 ac_in ← %s"%[item.id,_external_peers(int(item.id),true)])
			"fuel_boiler":
				fuel_count += 1
				fuel += float(report.get("fuel_input_mw", 0))
				fuel_volume += float(report.get("fuel_volume_nm3_per_h", 0))
				fuel_cost += float(report.get("fuel_cost_per_h", 0))
				ac += float(report.get("auxiliary_electric_mw", 0))
				heat += float(report.get("heat_output_mwth", 0))
				ac_mappings.append("#%d 燃气辅机 ac_in ← %s" % [item.id, _external_peers(int(item.id), true)])
			"molten_salt_store", "thermal_store", "high_temp_store":
				stored += float(item.get("state", {}).get("energy_mwhth", 0))
				capacity += float(item.params.get("capacity_mwhth", 0))
				if item.kind=="molten_salt_store":ac+=float(report.get("auxiliary_electric_mw",0))
			"heat_exchanger":
				delivered += float(report.get("warm_output_mwth", report.get("output_mwth", 0)))
				heat_mappings.append("#%d warm_out → %s" % [item.id, _external_peers(int(item.id), false)])
	input_ports_label.text = "AC 输入 · electricity_ac / MW\n" + ("尚无锅炉入口" if ac_mappings.is_empty() else "\n".join(ac_mappings))
	output_ports_label.text = "70/40°C热输出 / AC发电输出\n" + ("尚无换热器出口" if heat_mappings.is_empty() else "\n".join(heat_mappings))
	var paused: bool = host.get("paused") != false
	var speed_value := float(host.get("speed")) if host.get("speed") != null else 1.0
	run_button.text = ("▶ 运行" if paused else "Ⅱ 暂停") + "基地模拟 · ×%d" % int(speed_value)
	speed_control.set_speed(speed_value)
	summary_label.text = "本站 %d 台设备\nAC 输入 %.5f MW\n热源出热 %.4f MWth\n70/40°C 外供 %.3f MWth\n储热 %.3f / %.3f MWhth\nSOC %.1f%%" % [members.size(), ac, heat, delivered, stored, capacity, stored / capacity * 100.0 if capacity > 0 else 0.0]
	if members.any(func(d):return d.kind in ["steam_generator","steam_turbine","steam_condenser","feedwater_pump"]):
		summary_label.text = "本站蒸汽循环 · 已预热固定工况\n毛发电 %.4f kW\n循环辅机 %.4f kW\n循环净发电 %.4f kW\n冷凝器环境排热 %.4f kWth\n运行辅电由外部风光或电池保障。\n油热库存 %.5f / %.3f MWhth"%[gross*1000,rankine_aux*1000,(gross-rankine_aux)*1000,rejected*1000,stored,capacity]
	if tower_site:
		summary_label.text = host.tower_report_text(host.result.get("tower",{})) + "\n毛发电 %.3f · 全辅机 %.3f kW\n设备净 %.3f kW（未计线损）\n盐库存 %.4f/%.3f MWhth\n闭环流量 %.5f kg/s\n外部风机/电池供辅电"%[gross*1000,ac*1000,(gross-ac)*1000,stored,capacity,host.result.get("rankine",{}).get("mass_flow_kg_s",0)]
	if tower_site:
		var initial_battery:=0.0
		for d in host.devices:
			if d.kind=="battery":initial_battery+=float(d.params.get("capacity_mwh",0))*float(d.params.get("initial_soc",0))
		summary_label.text+="\n基地电池初始 %.3f MWh（设定）"%initial_battery
	if fuel_count > 0:
		summary_label.text += "\n天然气 %.3f MW(LHV)\n燃气体积 %.2f Nm³/h\n燃料成本 %.2f 元/h（教学）" % [fuel, fuel_volume, fuel_cost]
		summary_label.text += "\n" + _fuel_supply_status()
	if members.is_empty(): summary_label.text += "\n空站：先建设并连接内部热链。"
	elif not host.result.get("valid", false): summary_label.text += "\n当前调度不可用；请检查设备与连接。"
	var item := _member(selected_id)
	if item.is_empty():
		selected_label.text = "点击模型或从清单选择。\n左拖平移 · 双击查看详情\n建设 / 移动时显示定位网格。"
		return
	var report: Dictionary = reports.get(str(selected_id), {})
	selected_label.text = "#%d %s\n位置 %.1f, %.1f 米\n" % [selected_id, NAMES[item.kind], float(item.get("interior_x", 0)) / 0.1, float(item.get("interior_z", 0)) / 0.1]
	match item.kind:
		"salt_steam_generator", "steam_generator", "steam_turbine", "steam_condenser", "feedwater_pump":
			selected_label.text += host.rankine_report_text(item.kind,report)
		"solar_tower_receiver":
			selected_label.text += host.tower_report_text(report)
		"electric_boiler":
			selected_label.text += "AC → 90/60°C\n电输入 %.3f MW\n热输出 %.3f MWth\n转换散失 %.3f MW" % [report.get("electric_input_mw", 0), report.get("heat_output_mwth", report.get("output_mwth", 0)), report.get("conversion_loss_mw", 0)]
		"parabolic_trough", "oil_water_exchanger":
			selected_label.text += host.high_temp_report_text(item.kind,report)+"\n"+host.thermal_connection_status(selected_id)
		"solar_thermal":
			selected_label.text += host.solar_report_text(report)+"\n"+host.thermal_connection_status(selected_id)
		"fuel_boiler":
			selected_label.text += "天然气 → 90/60°C\n燃料输入 %.3f MW(LHV)\n热输出 %.3f MWth\n燃料转换散失 %.3f MW\n辅机用电 %.3f MW\n辅机电散失 %.3f MW\n燃气体积 %.2f Nm³/h\n燃料成本 %.2f 元/h（教学）\n%s" % [report.get("fuel_input_mw", 0), report.get("heat_output_mwth", 0), report.get("conversion_loss_mw", 0), report.get("auxiliary_electric_mw", 0), report.get("auxiliary_electric_loss_mw", 0), report.get("fuel_volume_nm3_per_h", 0), report.get("fuel_cost_per_h", 0), _fuel_supply_status()]
			selected_label.text += "\n额定燃料 %.3f MW(LHV) · 效率 %.1f%%\n辅机比例 %.3f · 占地半径 %.1f 米" % [item.params.get("rated_fuel_mw", 0), float(item.params.get("thermal_efficiency", 0)) * 100.0, item.params.get("auxiliary_electric_ratio", 0), _footprint(item.kind, item.params) / 0.1]
			if host.has_method("thermal_connection_status"):
				selected_label.text += "\n" + host.thermal_connection_status(selected_id)
		"molten_salt_store", "thermal_store", "high_temp_store":
			var stock := float(item.get("state", {}).get("energy_mwhth", 0))
			var cap := float(item.params.get("capacity_mwhth", 0))
			selected_label.text += ("565/290°C 熔盐 · SOC0=290°C基线\n" if item.kind=="molten_salt_store" else "300/200°C Therminol 66 · SOC0=200°C基线\n" if item.kind=="high_temp_store" else "") + "固定温区\n库存 %.3f / %.3f MWhth\nSOC %.1f%%\n充热 %.3f MWth\n放热 %.3f MWth\nSOC 表示库存，不是罐温。" % [stock, cap, stock / cap * 100.0 if cap > 0 else 0.0, report.get("charge_mwth", 0), report.get("discharge_mwth", 0)]
		"heat_exchanger":
			selected_label.text += "90/60 → 70/40°C\n热侧输入 %.3f MWth\n冷侧输出 %.3f MWth\n散失 %.3f MWth" % [report.get("hot_input_mwth", report.get("input_mwth", 0)), report.get("warm_output_mwth", report.get("output_mwth", 0)), report.get("loss_mwth", 0)]

func _fuel_supply_status() -> String:
	var supply: Variant = host.get("fuel_supply")
	if not supply is Dictionary or not supply.get("enabled", false):
		return "共享天然气供应已关闭；在基地资源中启用。"
	return "共享供应上限 %.3f MW(LHV)；各燃气锅炉共用。" % float(supply.get("max_input_mw", 0))

func _external_peers(id: int, incoming: bool) -> String:
	var peers: Array[String] = []
	for edge in host.links:
		if int(edge.get("to" if incoming else "from", -1)) != id: continue
		var peer := int(edge.get("from" if incoming else "to", -1))
		if equipment_nodes.has(peer): continue
		var other: Dictionary = host.device(peer)
		peers.append("#%d %s" % [peer, "变电站" if other.get("kind", "") == "station" else "热需求" if other.get("kind", "") == "heat_demand" else str(other.get("kind", "外部"))])
	return "未连接" if peers.is_empty() else "、".join(peers)

func set_interaction_mode(value: String) -> void:
	if preview_only and value != "select": _set_status("未投运预览：不允许建设、移动设备或连线。"); return
	if value not in ["select", "build", "move", "connect"]: return
	_reset_move_drag()
	interaction_mode = value
	sidebar_tabs.current_tab = 1 if value == "connect" else 0
	pending_link = -1
	_clear_preview()
	match interaction_mode:
		"select": _set_status("选择模式：单击选中 · 左拖平移 · 双击查看设备详情；移动设备请使用移动工具。")
		"move": _set_status("移动 #%d：拖动设备后松开，或点击目标网格；右键 / Esc 取消。" % selected_id)
		"connect": _set_status("连接模式：先选设备，再点绿色兼容端点；悬停查看方向 / 温区 / 容量。Esc 取消。")
	refresh()

func _check_build_space(kind: String, params: Dictionary) -> bool:
	var radius := _footprint(kind, params)
	if radius <= _half_extent() * visual_scale: return true
	set_interaction_mode("select")
	_set_status("%s模板占地超出厂区：需半径 %.1f 米，允许 %.1f 米。请先调整设备规模。" % [NAMES[kind], radius / 0.1, _half_extent() * visual_scale / 0.1])
	return false

func start_build(kind: String) -> void:
	if preview_only: _set_status("未投运预览：不能放置运行设备。"); return
	if kind not in INTERNAL_KINDS: return
	if kind=="solar_tower_receiver":
		host.add_internal_device(station_id,kind,Vector2.ZERO);refresh();return
	if not _check_build_space(kind, host.templates.get(kind, {})): return
	build_kind = kind
	set_interaction_mode("build")
	_set_status("建设%s：点击空闲网格；占地半径 %.1f 米，右键 / Esc 取消。" % [NAMES[kind], _footprint(kind, host.templates.get(kind, {})) / 0.1])

func _start_move() -> void:
	if not _member(selected_id).is_empty(): set_interaction_mode("move")

func _select(id: int) -> void:
	if _member(id).is_empty(): return
	if id != selected_id:
		if _move_drag_active:
			interaction_mode = "select"
			_clear_preview()
		_reset_move_drag()
	selected_id = id
	if interaction_mode == "select":_set_status("已选择 #%d %s；可查看详情、编辑参数，或使用移动工具调整位置。"%[id,NAMES[_member(id).kind]])
	host.select_device(id)
	refresh()

func _open_device_details() -> void:
	if _member(selected_id).is_empty() or not host.has_method("open_device_details"): return
	set_interaction_mode("select")
	host.open_device_details(selected_id)

func _open_parameters() -> void:
	if _member(selected_id).is_empty(): return
	host.select_device(selected_id)
	host.open_parameters(false)

func _open_line_settings() -> void:
	if _member(selected_id).is_empty(): return
	host.select_device(selected_id)
	host.open_line_settings()

func _toggle_run() -> void:
	if host.has_method("toggle_run"): host.toggle_run()
	refresh()

func _connect_pickers() -> void:
	_connect(_picker_id(link_from), _picker_id(link_to))

func _connect(first: int, second: int) -> void:
	var error := _connection_error(first, second)
	if not error.is_empty():
		_set_status("连接未添加：" + error)
		refresh()
		return
	var candidate := _connection_candidate(first, second)
	if host.connect_internal_devices(first, second):
		pending_link = -1
		_set_status("已连接 #%d.%s → #%d.%s · %s · %.3f %s。" % [candidate.from, candidate.from_port, candidate.to, candidate.to_port, _carrier_caption(candidate), candidate.get("mass_flow_capacity_kg_s",candidate.get("capacity_mwth",0)),candidate.get("unit","MWth")])
	else:
		_set_status("连接未添加：设备或线路已变化，请重新选择端点。")
	refresh()

func request_remove() -> void:
	if _member(selected_id).is_empty(): return
	_pending_remove = selected_id
	remove_confirmation.dialog_text = "拆除 #%d %s 及其站内 / 对外关联线路？\n此操作使用基地的撤销记录。" % [selected_id, NAMES[_member(selected_id).kind]]
	remove_confirmation.popup_centered()

func _confirm_remove() -> void:
	var target := _pending_remove
	_pending_remove = -1
	if _member(target).is_empty(): return
	if host.remove_internal_device(target):
		if selected_id == target: selected_id = -1
		if pending_link == target: pending_link = -1
		set_interaction_mode("select")
		_set_status("已拆除 #%d 及其关联线路。" % target)
	else: _set_status("未拆除；设备可能已被其他操作修改。")
	refresh()

func placement_error(kind: String, point: Vector2, ignore_id: int = -1) -> String:
	if preview_only: return "未投运预览：不能放置运行设备。"
	if kind not in INTERNAL_KINDS: return "站内只支持锅炉、储热罐和换热器。"
	if not is_finite(point.x) or not is_finite(point.y): return "无效位置。"
	if host.has_method("can_place_internal"):
		return host.can_place_internal(station_id, kind, point, ignore_id)
	var params: Dictionary = _member(ignore_id).get("params", {}) if ignore_id >= 0 else host.templates.get(kind, {})
	var radius := _footprint(kind, params)
	if absf(point.x) + radius > _half_extent() * visual_scale or absf(point.y) + radius > _half_extent() * visual_scale:
		return "设备占地超出站内边界。"
	for item in _members():
		if int(item.id) == ignore_id: continue
		var center := Vector2(float(item.get("interior_x", 0)), float(item.get("interior_z", 0)))
		if center.distance_to(point) < radius + _footprint(item.kind, item.get("params", {})):
			return "与 #%d %s 占地重叠。" % [item.id, NAMES[item.kind]]
	return ""

## Container-local event positions are converted to this viewport before casting.
func floor_at(view_position: Vector2) -> Variant:
	if not is_instance_valid(camera) or view_container.size.x <= 0 or view_container.size.y <= 0:
		return null
	var viewport_position := view_position * Vector2(viewport.size) / view_container.size
	var origin := camera.project_ray_origin(viewport_position)
	var direction := camera.project_ray_normal(viewport_position)
	if absf(direction.y) < 0.000001: return null
	var distance := -origin.y / direction.y
	if distance < 0: return null
	var hit := origin + direction * distance
	return Vector2(hit.x, hit.z)

func _device_at(point: Vector2) -> int:
	var chosen := -1
	var nearest := INF
	for item in _members():
		var position_2d := Vector2(float(item.get("interior_x", 0)), float(item.get("interior_z", 0)))
		var distance := point.distance_to(position_2d)
		if distance <= _footprint(item.kind, item.get("params", {})) and distance < nearest:
			nearest = distance
			chosen = int(item.id)
	return chosen

## Hit actual 3D equipment bounds, rather than projecting a visible tank onto
## the floor behind it. This remains correct after arbitrary orbit and pan.
func device_at_view(view_position: Vector2) -> int:
	if view_container.size.x <= 0 or view_container.size.y <= 0: return -1
	var pixel := view_position * Vector2(viewport.size) / view_container.size
	var origin := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	var nearest := INF
	var chosen := -1
	for id in equipment_nodes:
		var visual: Node3D = equipment_nodes[id]
		var inverse := visual.global_transform.affine_inverse()
		var bounds: AABB = visual.get_meta("pick_bounds")
		var hit = bounds.grow(0.12 * visual_scale).intersects_ray(inverse * origin, inverse.basis * direction)
		if hit == null: continue
		var distance: float = origin.distance_to(visual.to_global(hit))
		if distance < nearest:
			nearest = distance
			chosen = int(id)
	return chosen

func _view_mouse_exited() -> void:
	_has_cursor = false
	hovered_id = -1
	_orbit_drag = false
	_pan_drag = false
	if _move_drag_active:
		_cancel_move_drag("移动已取消：请在站内视图中松开；设备保留原位。")
	else: _reset_move_drag()
	_sync_annotations()
	if is_instance_valid(preview): preview.hide()

func _reset_move_drag() -> void:
	_left_pan_pending = false
	_left_pan_active = false
	_left_pan_pick = -1
	_left_pan_double = false
	_move_drag_candidate = -1
	_move_drag_active = false

func _begin_move_drag(id: int, view_position: Vector2) -> void:
	var point = floor_at(view_position)
	var item := _member(id)
	if point == null or item.is_empty(): return
	_move_drag_candidate = id
	_move_drag_active = false
	_move_drag_start = view_position
	_move_drag_grab = point
	_move_drag_origin = Vector2(float(item.get("interior_x", 0)), float(item.get("interior_z", 0)))

func _placement_point(view_position: Vector2) -> Variant:
	var point = floor_at(view_position)
	if point == null: return null
	# Preserve the grab offset so grabbing a tank's visible upper body does not
	# jump its centre to the floor intersection behind it.
	if _move_drag_active: point = _move_drag_origin + point - _move_drag_grab
	return point.snapped(Vector2(GRID_STEP, GRID_STEP) * visual_scale)

func _cancel_move_drag(reason: String) -> void:
	_reset_move_drag()
	interaction_mode = "select"
	_clear_preview()
	refresh()
	_set_status(reason)

func _finish_move_drag(view_position: Vector2) -> void:
	if not _move_drag_active:
		_reset_move_drag()
		return
	var id := _move_drag_candidate
	var point = _placement_point(view_position)
	var item := _member(id)
	var error := "设备已变化；请重新选择。" if item.is_empty() else ""
	if point == null: error = "没有有效的地面位置。"
	elif error.is_empty(): error = placement_error(str(item.kind), point, id)
	var original := _move_drag_origin
	# Clear the gesture BEFORE calling the host, whose refresh is re-entrant.
	_reset_move_drag()
	interaction_mode = "select"
	_clear_preview()
	if not error.is_empty():
		refresh()
		_set_status("移动未应用，设备保留原位：" + error)
		return
	if (point as Vector2).is_equal_approx(original):
		refresh()
		_set_status("位置未改变；没有新增撤销记录。")
		return
	var success: bool = host.move_internal_device(id, point)
	refresh()
	_set_status("已移动 #%d · %.1f, %.1f 米；可撤销。" % [id, point.x / 0.1, point.y / 0.1] if success else "移动未应用，设备保留原位：布局限制已变化。")

func _view_input(event: InputEvent) -> void:
	if remove_confirmation.visible: return
	if event is InputEventMouseMotion:
		_last_cursor = event.position
		_has_cursor = true
		if _left_pan_pending:
			if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
				_reset_move_drag()
			else:
				var displacement: Vector2 = event.position - _left_pan_start
				if _left_pan_active:
					_pan_camera(event.relative)
				elif displacement.length() >= DRAG_THRESHOLD_PX:
					_left_pan_active = true
					_pan_camera(displacement)
				view_container.accept_event()
				return
		if _move_drag_candidate >= 0:
			if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
				if _move_drag_active: _cancel_move_drag("移动已取消：未在视图中确认松开，设备保留原位。")
				else: _reset_move_drag()
			elif _move_drag_active or event.position.distance_to(_move_drag_start) >= DRAG_THRESHOLD_PX:
				_move_drag_active = true
				interaction_mode = "move"
				_update_preview(event.position)
				_sync_annotations()
				view_container.accept_event()
				return
		# Camera gestures can only start inside this viewport. Leaving it clears
		# both flags, so dragging a sidebar/control never rotates the world.
		if _orbit_drag and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
			_drag_distance += event.relative.length()
			set_camera_view(camera_yaw - event.relative.x * 0.32, camera_pitch + event.relative.y * 0.24, camera_distance)
		elif _pan_drag and (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
			_pan_camera(event.relative)
		else:
			_orbit_drag = false
			_pan_drag = false
			hovered_id = device_at_view(event.position)
			_sync_annotations()
			_update_preview(event.position)
		view_container.accept_event()
	elif event is InputEventMouseButton:
		_last_cursor = event.position
		_has_cursor = true
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if _move_drag_active: _cancel_move_drag("移动已取消，设备保留原位。")
				else: _reset_move_drag()
				_orbit_drag = true
				_drag_distance = 0.0
			else:
				if _orbit_drag and _drag_distance < 3.0 and interaction_mode != "select": _cancel_current_interaction()
				_orbit_drag = false
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if not _move_drag_active: _pan_drag = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed:
				if _left_pan_pending:
					var should_click: bool = not _left_pan_active and event.position.distance_to(_left_pan_start) < DRAG_THRESHOLD_PX and Rect2(Vector2.ZERO, view_container.size).has_point(event.position)
					var pick: int = _left_pan_pick
					var open_details: bool = _left_pan_double
					_reset_move_drag()
					if should_click and interaction_mode == "select":
						if pick >= 0 and device_at_view(event.position) == pick:
							_click_device(pick)
							if open_details: _open_device_details()
						elif pick < 0: _clear_selection()
				else: _finish_move_drag(event.position)
			else:
				_reset_move_drag()
				var id := device_at_view(event.position)
				if interaction_mode == "select":
					_left_pan_pending = true
					_left_pan_start = event.position
					_left_pan_pick = id
					_left_pan_double = event.double_click
				elif interaction_mode == "build":
					var point = floor_at(event.position)
					if point != null: _click_floor(point)
				elif interaction_mode == "move":
					if id == selected_id: _begin_move_drag(id, event.position)
					else:
						var point = floor_at(event.position)
						if point != null: _click_floor(point)
				elif id >= 0:
					_click_device(id)
		elif event.pressed and not _move_drag_active and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_camera_view(camera_yaw, camera_pitch, camera_distance - 3.0 * visual_scale)
		elif event.pressed and not _move_drag_active and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_camera_view(camera_yaw, camera_pitch, camera_distance + 3.0 * visual_scale)
		if _has_cursor: _update_preview(_last_cursor)
		view_container.accept_event()

func _click_floor(point: Vector2) -> void:
	if interaction_mode in ["build", "move"]:
		var snapped := point.snapped(Vector2(GRID_STEP, GRID_STEP) * visual_scale)
		var item := _member(selected_id)
		var kind := build_kind if interaction_mode == "build" else str(item.get("kind", ""))
		var error := placement_error(kind, snapped, selected_id if interaction_mode == "move" else -1)
		if error != "":
			_set_status(error)
			return
		if interaction_mode == "move" and snapped.is_equal_approx(Vector2(float(item.get("interior_x", 0)), float(item.get("interior_z", 0)))):
			set_interaction_mode("select")
			_set_status("位置未改变；没有新增撤销记录。")
			return
		var was_build := interaction_mode == "build"
		var success: bool = host.add_internal_device(station_id, kind, snapped) if was_build else host.move_internal_device(selected_id, snapped)
		if success:
			if not was_build: set_interaction_mode("select")
			refresh()
			_set_status(("已建设%s" % NAMES[kind] if was_build else "已移动 #%d" % selected_id) + " · %.1f, %.1f 米" % [snapped.x / 0.1, snapped.y / 0.1])
		else: _set_status("操作未应用；请检查站内布局限制。")
		return
	var id := _device_at(point)
	if id < 0:
		if interaction_mode == "connect": _set_status("请点击锅炉、储热罐或换热器；空白网格不是端口。")
		return
	_click_device(id)

func _click_device(id: int) -> void:
	_select(id)
	if interaction_mode == "connect":
		if pending_link < 0:
			pending_link = id
			_set_status("%s#%d；点击绿色兼容端点，按输出 → 输入连接。Esc 取消。" % [_endpoint_caption(id), id])
			refresh()
		else: _connect(pending_link, id)

func _update_preview(view_position: Vector2) -> void:
	if interaction_mode not in ["build", "move"]: return
	if _move_drag_candidate >= 0 and not _move_drag_active:
		if is_instance_valid(preview): preview.hide()
		return
	var point = _placement_point(view_position)
	if point == null: return
	var item := _member(selected_id)
	var kind := build_kind if interaction_mode == "build" else str(item.get("kind", ""))
	if kind not in INTERNAL_KINDS: return
	var params: Dictionary = host.templates.get(kind, {}) if interaction_mode == "build" else item.get("params", {})
	if interaction_mode == "build" and not _check_build_space(kind, params): return
	var signature := kind + JSON.stringify(params) + dimension_profile
	if not is_instance_valid(preview) or preview.get_meta("preview_signature", "") != signature:
		_clear_preview()
		preview = Visual.create(kind, _visual_params(params), true)
		preview.name = "InteriorPlacementPreview"
		preview.set_meta("preview_kind", kind)
		preview.set_meta("preview_signature", signature)
		scene_root.add_child(preview)
		for label in preview.find_children("*", "Label3D", true, false): label.hide()
	var snapped: Vector2 = point
	var error := placement_error(kind, snapped, selected_id if interaction_mode == "move" else -1)
	preview.position = Vector3(snapped.x, 0.04 * visual_scale, snapped.y)
	preview.set_preview(error.is_empty())
	preview.set_meta("placement_error", error)
	preview.show()
	if _move_drag_active:
		_set_status("松开确认移动 · %.1f, %.1f 米 · Esc 取消" % [snapped.x / 0.1, snapped.y / 0.1] if error.is_empty() else "无法移动：" + error + " 松开将保留原位。")

func _clear_preview() -> void:
	if is_instance_valid(preview): preview.free()
	preview = null

func _clear_selection() -> void:
	_reset_move_drag()
	selected_id = -1
	if is_instance_valid(host): host.select_device(station_id)
	refresh()
	_set_status("已清除选择；点击设备查看，Esc 返回基地。")

func _cancel_current_interaction() -> void:
	if interaction_mode != "select" or pending_link >= 0 or _move_drag_active:
		set_interaction_mode("select")
		_set_status("已取消操作；设备和线路未改变。再按 Esc 返回基地。")
	elif selected_id >= 0: _clear_selection()
	else: _reset_move_drag()

func _has_undo_history() -> bool:
	if not is_instance_valid(host) or not host.has_method("undo"): return false
	var history = host.get("undo_states")
	return history is Array and not history.is_empty()

## Host undo restores the single authoritative snapshot and hides this window.
## Reopen only a surviving station, preserving the user's observation and choice.
func undo_edit() -> void:
	if remove_confirmation.visible:
		remove_confirmation.hide()
		_pending_remove = -1
		_set_status("已取消拆除确认；再次撤销将恢复最近一次编辑。")
		return
	if _move_drag_active or interaction_mode != "select" or pending_link >= 0:
		_cancel_current_interaction()
		_set_status("已取消当前预览 / 连线；未撤销之前的编辑。再次撤销可恢复最近一次编辑。")
		return
	_reset_move_drag()
	if not _has_undo_history():
		_set_status("没有可撤销的操作。")
		return
	var previous_station := station_id
	var previous_selection := selected_id
	var previous_target := camera_target
	var previous_yaw := camera_yaw
	var previous_pitch := camera_pitch
	var previous_distance := camera_distance
	var previous_size := size
	var previous_position := position
	host.undo()
	if host.station(previous_station).is_empty():
		close_station()
		return
	if not open_station(previous_station): return
	size = previous_size
	position = previous_position
	if not _member(previous_selection).is_empty(): _select(previous_selection)
	camera_target = previous_target
	set_camera_view(previous_yaw, previous_pitch, previous_distance)
	_set_status("已撤销最近一次编辑；视角保留，模拟暂停。")

func _window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_Z or event.physical_keycode == KEY_Z) and (event.ctrl_pressed or event.meta_pressed) and not event.shift_pressed and not event.alt_pressed:
		var focused := gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit: return
		undo_edit()
		set_input_as_handled()
		return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _left_pan_pending and not view_container.get_global_rect().has_point(event.position): _reset_move_drag()
		if _move_drag_active and not view_container.get_global_rect().has_point(event.position):
			_cancel_move_drag("移动已取消：请在站内视图中松开；设备保留原位。")
	if event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		# Consume key repeats without stepping through another modal layer.
		if not event.echo:
			if is_instance_valid(host) and host.has_method("handle_escape"): host.handle_escape()
			else: handle_escape()
		set_input_as_handled()

## One Esc affects exactly one layer. A selected device is not an edit mode.
func handle_escape() -> bool:
	if not visible: return false
	if remove_confirmation.visible:
		remove_confirmation.hide()
		_pending_remove = -1
	elif interaction_mode != "select" or pending_link >= 0 or _move_drag_active or _move_drag_candidate >= 0:
		_cancel_current_interaction()
		_reset_move_drag()
	else:
		close_station()
	return true

func _set_status(message: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = message
		status_label.tooltip_text = message
