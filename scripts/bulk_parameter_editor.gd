extends Window
## A staged, explicit-field editor. Only the host can commit an atomic change.
const ThemeFactory = preload("res://scripts/ui_theme.gd")
const ParameterForm = preload("res://scripts/parameter_form.gd")
var host: Node
var current_kind := ""
var selected_ids: Array[int] = []
var _kinds: Array[String] = []
var _fields: Dictionary = {}
var _enabled: Dictionary = {}
var _cards: Dictionary = {}
var _type: OptionButton
var _selection: Label
var _error: Label
var _device_grid: GridContainer
var _field_column: VBoxContainer
var _apply: Button
var _built := false
var _refreshing := false
var _list_scroll: ScrollContainer
var _list_view: Control
var _card_panels: Dictionary = {}
var _card_order: Array[int] = []
var _select_all_checkbox: CheckBox
var _mixed_icon: Texture2D
var _range_anchor_id := -1
var _pointer_pending := false
var _drag_active := false
var _pointer_origin := Vector2.ZERO
var _pointer_last := Vector2.ZERO
var _drag_start_content := Vector2.ZERO
var _pointer_card_id := -1
var _pointer_on_checkbox := false
var _gesture_shift := false
var _gesture_additive := false
var _drag_base_ids: Array[int] = []
var _drag_preview_ids: Array[int] = []
var _marquee: SelectionMarquee

class SelectionMarquee extends Control:
	var rectangle := Rect2()
	func _draw():
		draw_rect(rectangle,Color(0.45,0.80,0.85,0.16),true)
		draw_rect(rectangle,Color("72cbd8"),false,1.5)

func _init():
	visible=false;title="批量设备参数";transient=true;exclusive=true
	size=Vector2i(1060,730);min_size=Vector2i(620,450)

func setup(game:Node):
	host=game
	theme=ThemeFactory.create(host.font_full)
	_build_ui()
	close_requested.connect(cancel)
	window_input.connect(_window_input)
	size_changed.connect(_layout)
	focus_exited.connect(_cancel_selection_gesture)

func _label(text:String,font_size:int=14,color:Color=ThemeFactory.INK)->Label:
	var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",Color("b3c1cd") if color==ThemeFactory.MUTED else color)
	return label

func _button(text:String,callback:Callable,parent:Node)->Button:
	var result:=Button.new();result.text=text;result.custom_minimum_size.y=34;result.pressed.connect(callback);parent.add_child(result)
	return result

func _build_ui():
	if _built:return
	_built=true
	var background:=PanelContainer.new();add_child(background);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.add_theme_stylebox_override("panel",ThemeFactory.panel(Color("24303d"),16,12))
	var column:=VBoxContainer.new();background.add_child(column);column.add_theme_constant_override("separation",8)
	var heading:=HBoxContainer.new();column.add_child(heading)
	var title_label:=_label("批量设置设备参数",23);title_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(title_label)
	_button("关闭 / Esc",cancel,heading)
	var intro:=_label("选择同类设备，再编辑共同数值参数。位置、连线和库存不变；自定义功率曲线请单台编辑。",13,ThemeFactory.MUTED);intro.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(intro)
	var filter:=HBoxContainer.new();column.add_child(filter);filter.add_child(_label("设备类型"))
	_type=OptionButton.new();_type.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_type.fit_to_longest_item=false;filter.add_child(_type);_type.item_selected.connect(func(index):select_kind(_kinds[index]))
	_selection=_label("尚未选择设备",13,ThemeFactory.ACCENT);_selection.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;column.add_child(_selection)
	var split:=HSplitContainer.new();split.size_flags_vertical=Control.SIZE_EXPAND_FILL;split.split_offset=380;column.add_child(split)
	var left:=VBoxContainer.new();left.custom_minimum_size.x=230;split.add_child(left)
	var list_heading:=HBoxContainer.new();left.add_child(list_heading)
	var list_title:=_label("已安装设备",16);list_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list_heading.add_child(list_title)
	_select_all_checkbox=CheckBox.new();_select_all_checkbox.name="SelectAllInstalled";_select_all_checkbox.text="全选";_select_all_checkbox.custom_minimum_size.y=30;_select_all_checkbox.add_theme_font_size_override("font_size",13);list_heading.add_child(_select_all_checkbox)
	_select_all_checkbox.toggled.connect(func(on):
		if _refreshing:return
		_range_anchor_id=-1
		if on:select_all()
		else:set_selected_ids([]))
	var mixed_image:=Image.new();mixed_image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect x="1" y="1" width="14" height="14" rx="3" fill="#263f4d" stroke="#72cbd8"/><path d="M4 8H12" stroke="#72cbd8" stroke-width="2"/></svg>');_mixed_icon=ImageTexture.create_from_image(mixed_image)
	var list_hint:=_label("点击 · Shift 范围 · 拖动框选",12,ThemeFactory.MUTED);left.add_child(list_hint)
	_list_view=Control.new();_list_view.name="InstalledSelectionArea";_list_view.size_flags_vertical=Control.SIZE_EXPAND_FILL;_list_view.clip_contents=true;left.add_child(_list_view)
	_list_scroll=ScrollContainer.new();_list_scroll.name="InstalledDeviceScroll";_list_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;_list_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_list_view.add_child(_list_scroll)
	var list_margin:=MarginContainer.new();list_margin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	list_margin.add_theme_constant_override("margin_left",12);list_margin.add_theme_constant_override("margin_right",12);list_margin.add_theme_constant_override("margin_top",8);list_margin.add_theme_constant_override("margin_bottom",28);_list_scroll.add_child(list_margin)
	_list_view.tooltip_text="从卡片旁的留白拖动可框选；Ctrl 拖动追加选择。卡片文字区可点击，复选框可独立勾选。"
	_device_grid=GridContainer.new();_device_grid.columns=1;_device_grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_device_grid.add_theme_constant_override("v_separation",8);_device_grid.add_theme_constant_override("h_separation",8);list_margin.add_child(_device_grid)
	_marquee=SelectionMarquee.new();_marquee.mouse_filter=Control.MOUSE_FILTER_IGNORE;_marquee.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_marquee.hide();_list_view.add_child(_marquee)
	var right:=VBoxContainer.new();right.custom_minimum_size.x=300;split.add_child(right);right.add_child(_label("勾选的参数才会应用",16))
	var field_scroll:=ScrollContainer.new();field_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;field_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;right.add_child(field_scroll)
	_field_column=VBoxContainer.new();_field_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;_field_column.add_theme_constant_override("separation",10);field_scroll.add_child(_field_column)
	_error=_label("所有选中设备先校验，全部通过后一次应用；失败不会部分修改。",12,ThemeFactory.MUTED);_error.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_error.max_lines_visible=3;column.add_child(_error)
	var actions:=HBoxContainer.new();column.add_child(actions);var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(spacer)
	_button("取消",cancel,actions);_apply=_button("校验并应用到所选设备",apply_selection,actions)

func open():
	if not is_instance_valid(host):return
	host.paused=true;host.cancel_camera_drag();host.update_status()
	selected_ids.clear();_kinds.clear();_type.clear()
	for kind in host.KINDS:
		if host.devices.any(func(device):return device.kind==kind):
			_kinds.append(kind);_type.add_item(host.DEVICE_NAMES.get(kind,kind))
	if _kinds.is_empty():
		current_kind="";_refresh_cards();_refresh_fields();_error.text="尚未安装设备。请先建设设备，再批量设置参数。"
	else:select_kind(current_kind if current_kind in _kinds else _kinds[0])
	var extent:=host.get_viewport().get_visible_rect().size
	popup_centered(Vector2i(mini(1060,int(extent.x)-40),mini(730,int(extent.y)-40)))
	_layout()

func select_kind(kind:String):
	if not kind in _kinds:
		# Supports a programmatic preselection while preserving the installed-only list.
		if not host.devices.any(func(device):return device.kind==kind):return
		_kinds.append(kind);_type.add_item(host.DEVICE_NAMES.get(kind,kind))
	_cancel_selection_gesture();current_kind=kind;selected_ids.clear();_range_anchor_id=-1;_type.select(_kinds.find(kind));_refresh_cards();_refresh_fields();_list_scroll.scroll_vertical=0

func select_all():
	var ids:Array=[]
	for device in host.devices:
		if device.kind==current_kind:ids.append(int(device.id))
	set_selected_ids(ids)

func _valid_ids(ids:Array)->Array[int]:
	var valid:Array[int]=[]
	for id in ids:
		if typeof(id)!=TYPE_INT and (typeof(id)!=TYPE_FLOAT or not is_finite(float(id)) or float(id)!=floor(float(id))):continue
		var device:Dictionary=host.device(int(id))
		if not device.is_empty() and device.kind==current_kind and not valid.has(int(id)):valid.append(int(id))
	valid.sort();return valid

func set_selected_ids(ids:Array):
	var next:=_valid_ids(ids)
	var changed:=next!=selected_ids
	selected_ids=next
	_sync_selection_visuals(selected_ids);_update_selection_summary(selected_ids)
	if changed:_refresh_fields()

func select_card(id:int,shift:bool=false,additive:bool=false):
	if not _card_order.has(id) or not id in _valid_ids([id]):return
	var anchor:=_range_anchor_id
	var next:Array=selected_ids.duplicate()
	if shift and _card_order.has(anchor) and anchor in _valid_ids([anchor]):
		if not additive:next.clear()
		var first:=mini(_card_order.find(anchor),_card_order.find(id))
		var last:=maxi(_card_order.find(anchor),_card_order.find(id))
		for index in range(first,last+1):
			if not next.has(_card_order[index]):next.append(_card_order[index])
	else:
		if not additive:next=[id]
		elif next.has(id):next.erase(id)
		else:next.append(id)
		anchor=id
	set_selected_ids(next);_range_anchor_id=anchor
	_cards[id].grab_focus()

func _toggle_device(on:bool,id:int):
	if _refreshing:return
	var ids:Array=selected_ids.duplicate()
	if on and not ids.has(id):ids.append(id)
	elif not on:ids.erase(id)
	set_selected_ids(ids);_range_anchor_id=id

func refresh_devices():
	_cancel_selection_gesture();_refresh_cards();_refresh_fields()

func _refresh_cards():
	_range_anchor_id=-1
	for child in _device_grid.get_children():_device_grid.remove_child(child);child.queue_free()
	_cards.clear();_card_panels.clear();_card_order.clear()
	selected_ids=_valid_ids(selected_ids)
	for device in host.devices:
		if device.kind!=current_kind:continue
		var id:=int(device.id)
		var card:=PanelContainer.new();card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;card.add_theme_stylebox_override("panel",ThemeFactory.panel(ThemeFactory.RAISED,8,6));_device_grid.add_child(card);_card_panels[id]=card;_card_order.append(id)
		var body:=VBoxContainer.new();card.add_child(body)
		var check:=CheckBox.new();check.button_mask=0;check.text=host.DEVICE_NAMES.get(device.kind,device.kind)+" #%d"%id;check.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;check.size_flags_horizontal=Control.SIZE_EXPAND_FILL;check.add_theme_font_size_override("font_size",14);check.custom_minimum_size.y=32;body.add_child(check);check.toggled.connect(_toggle_device.bind(id));_cards[id]=check
		var where:String="厂站 #%d · 内部设备"%int(device.parent_station_id) if device.has("parent_station_id") else "地图位置 (%.1f, %.1f)"%[float(device.x),float(device.z)]
		var info:=_label(where,12,ThemeFactory.MUTED);info.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;body.add_child(info)
		check.tooltip_text=check.text+"\n"+where+"\n点击切换；Shift 点击选中首末之间；拖动可框选。"
	if _cards.is_empty():_device_grid.add_child(_label("此类型没有已安装设备",13,ThemeFactory.MUTED))
	_sync_selection_visuals(selected_ids)

func _sync_selection_visuals(ids:Array):
	for id in _cards:
		_cards[id].set_pressed_no_signal(ids.has(int(id)))
		var style:=ThemeFactory.panel(Color("26434e") if ids.has(int(id)) else ThemeFactory.RAISED,8,6)
		style.border_color=Color("72cbd8") if ids.has(int(id)) else ThemeFactory.BORDER
		_card_panels[id].add_theme_stylebox_override("panel",style)
	var count:=ids.size();var total:=_valid_ids(_card_order).size()
	var partial:=count>0 and count<total
	_select_all_checkbox.set_meta("indeterminate",partial)
	_select_all_checkbox.set_pressed_no_signal(total>0 and count==total)
	_select_all_checkbox.disabled=total==0
	if partial:_select_all_checkbox.add_theme_icon_override("unchecked",_mixed_icon)
	else:_select_all_checkbox.remove_theme_icon_override("unchecked")
	_select_all_checkbox.tooltip_text="已选 %d / %d 台；点击%s。选择变化会清空字段草稿。"%[count,total,"清空" if count==total and total>0 else "全选"]

func _update_selection_summary(ids:Array,preview:bool=false):
	var text_ids:Array[String]=[]
	for id in ids:text_ids.append("#%d"%id)
	_selection.text=("框选预览 " if preview else "已选 ")+"%d / %d 台"%[ids.size(),_valid_ids(_card_order).size()]+("："+", ".join(text_ids) if not ids.is_empty() else " · 点击或拖动选择")
	_selection.tooltip_text=_selection.text

func _list_input_rect()->Rect2:
	var rect:=_list_view.get_global_rect()
	var scrollbar:=_list_scroll.get_v_scroll_bar()
	if scrollbar.visible:rect.size.x=maxf(0,scrollbar.get_global_rect().position.x-rect.position.x)
	return rect

func _card_at(point:Vector2)->int:
	for id in _card_order:
		if _card_panels[id].get_global_rect().has_point(point):return id
	return -1

func handle_list_input(event:InputEvent)->bool:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _list_input_rect().has_point(event.position):return false
			# One owner for pointer gestures: BaseButton mouse toggling is disabled on
			# device checks so a Shift range cannot be toggled again by the GUI pass.
			# Native keyboard acceptance and toggled signals remain available.
			_pointer_pending=true;_drag_active=false;_pointer_origin=event.position;_pointer_last=event.position
			_drag_start_content=event.position-_device_grid.global_position;_pointer_card_id=_card_at(event.position)
			_pointer_on_checkbox=_pointer_card_id>=0 and _cards[_pointer_card_id].get_global_rect().has_point(event.position)
			_gesture_shift=event.shift_pressed;_gesture_additive=event.ctrl_pressed or event.meta_pressed
			_drag_base_ids=selected_ids.duplicate();_drag_preview_ids=selected_ids.duplicate()
			return true
		if _pointer_pending:
			_pointer_last=event.position
			if _drag_active:
				_update_marquee();var chosen:=_drag_preview_ids.duplicate();_cancel_selection_gesture();set_selected_ids(chosen);_range_anchor_id=-1
			else:
				var id:=_pointer_card_id;var shift:=_gesture_shift;var additive:=_gesture_additive;var checkbox_click:=_pointer_on_checkbox
				_cancel_selection_gesture()
				if id>=0 and _card_at(event.position)==id:
					if checkbox_click and not shift:_toggle_device(not selected_ids.has(id),id);_cards[id].grab_focus()
					else:select_card(id,shift,additive)
				elif id<0:set_selected_ids([]);_range_anchor_id=-1
			return true
	elif event is InputEventMouseMotion and _pointer_pending:
		_pointer_last=event.position
		if _drag_active or event.position.distance_to(_pointer_origin)>=6.0:
			_drag_active=true;_marquee.show();_apply.disabled=true;_update_marquee()
		return true
	return false

func _update_marquee():
	var area:=_list_input_rect()
	var clipped_pointer:=_pointer_last.clamp(area.position,area.end)
	var current:=clipped_pointer-_device_grid.global_position
	var rectangle:=Rect2(_drag_start_content,current-_drag_start_content).abs()
	var ids:Array[int]=[]
	if _gesture_shift or _gesture_additive:ids.assign(_drag_base_ids)
	for id in _card_order:
		var card_rect:Rect2=_card_panels[id].get_global_rect();card_rect.position-=_device_grid.global_position
		if rectangle.intersects(card_rect) and not ids.has(id):ids.append(id)
	_drag_preview_ids=_valid_ids(ids)
	var local_rectangle:=rectangle;local_rectangle.position+=_device_grid.global_position-_list_view.global_position
	_marquee.rectangle=local_rectangle.intersection(Rect2(Vector2.ZERO,_list_input_rect().size));_marquee.queue_redraw()
	_sync_selection_visuals(_drag_preview_ids);_update_selection_summary(_drag_preview_ids,true)

func _cancel_selection_gesture():
	_pointer_pending=false;_drag_active=false
	if is_instance_valid(_marquee):_marquee.hide()
	if is_instance_valid(_select_all_checkbox):_sync_selection_visuals(selected_ids);_update_selection_summary(selected_ids)
	if is_instance_valid(_apply):_apply.disabled=selected_ids.is_empty()

func _process(delta:float):
	if not visible or not _drag_active:return
	var area:=_list_input_rect();var speed:=0.0
	if _pointer_last.y<area.position.y+26:speed=-320.0
	elif _pointer_last.y>area.end.y-26:speed=320.0
	if speed!=0:
		_list_scroll.scroll_vertical+=int(speed*delta)
		_update_marquee()

func handle_escape():
	if _pointer_pending:_cancel_selection_gesture()
	else:cancel()

func _refresh_fields():
	_refreshing=true
	_error.add_theme_color_override("font_color",ThemeFactory.MUTED)
	for child in _field_column.get_children():_field_column.remove_child(child);child.queue_free()
	_fields.clear();_enabled.clear()
	_update_selection_summary(selected_ids)
	_apply.disabled=selected_ids.is_empty()
	if selected_ids.is_empty():
		_field_column.add_child(_label("选中设备后显示共同参数。",13,ThemeFactory.MUTED));_error.text="选择已清空，之前暂存的字段也已清空；没有修改设备。";_refreshing=false;return
	for group in ParameterForm.GROUPS.get(current_kind,[]):
		var editable_specs:Array=group.fields.filter(func(spec):return not ParameterForm.construction_only(str(spec[0])) and not ParameterForm.fixed_field(current_kind,str(spec[0])))
		if editable_specs.is_empty():continue
		_field_column.add_child(_label(group.title,15,ThemeFactory.ACCENT))
		for spec in editable_specs:
			var key:String=spec[0]
			var block:=VBoxContainer.new();block.add_theme_constant_override("separation",3);_field_column.add_child(block)
			var row:=HBoxContainer.new();block.add_child(row)
			var enabled:=CheckBox.new();enabled.text=spec[1];enabled.size_flags_horizontal=Control.SIZE_EXPAND_FILL;enabled.add_theme_font_size_override("font_size",13);row.add_child(enabled);_enabled[key]=enabled
			var editor:=LineEdit.new();editor.custom_minimum_size=Vector2(104,32);editor.alignment=HORIZONTAL_ALIGNMENT_RIGHT;editor.add_theme_font_size_override("font_size",14);row.add_child(editor);_fields[key]=editor
			var unit:=_label(spec[2],11,ThemeFactory.MUTED);unit.custom_minimum_size.x=54;row.add_child(unit)
			var common:Variant=null;var first:=true;var mixed:=false
			for id in selected_ids:
				var target:Dictionary=host.device(id)
				if target.is_empty() or target.kind!=current_kind:mixed=true;continue
				var value:Variant=target.params.get(key,host.model.defaults(current_kind).get(key))
				if first:common=value;first=false
				elif common!=value:mixed=true
			if not mixed and common!=null:editor.text=str(common)
			else:editor.placeholder_text="混合值"
			var hint:=_label(("混合值 · 未勾选保持各自值 · " if mixed else "未勾选不修改 · ")+str(spec[3]),11,ThemeFactory.MUTED);hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;block.add_child(hint)
			editor.text_changed.connect(func(_text):
				if not _refreshing:enabled.set_pressed_no_signal(true);_error.text="仅勾选字段会统一应用；当前库存与设备ID保持不变。")
			enabled.toggled.connect(func(_on):_error.text="仅勾选字段会统一应用；当前库存与设备ID保持不变。")
	_error.text="已更新选择范围，之前暂存的字段已清空。混合值不会被自动覆盖。"
	_refreshing=false

func get_patch()->Dictionary:
	var patch:Dictionary={}
	for key in _enabled:
		if not _enabled[key].button_pressed:continue
		if ParameterForm.construction_only(key) or ParameterForm.fixed_field(current_kind,key):return {"ok":false,"error":"初始库存、宿主质量和固定profile不能批量修改。","patch":{}}
		var text_value:String=_fields[key].text.strip_edges()
		if not text_value.is_valid_float() or not is_finite(float(text_value)):return {"ok":false,"error":"参数 %s 需要有限数字。"%key,"patch":{}}
		patch[key]=float(text_value)
	return {"ok":true,"error":"","patch":patch}

func apply_selection()->Dictionary:
	var prepared:=get_patch()
	if not prepared.ok:_error.text=prepared.error;return prepared
	var result:Dictionary=host.apply_bulk_parameters(current_kind,selected_ids,prepared.patch)
	_error.text=result.error if not result.ok else "已统一设置 %d 台设备；可一次撤销。"%int(result.count)
	_error.add_theme_color_override("font_color",ThemeFactory.ERROR if not result.ok else ThemeFactory.ACCENT)
	if result.ok:
		for key in _enabled:_enabled[key].set_pressed_no_signal(false)
	return result

func cancel():
	_cancel_selection_gesture();hide()

func _layout():
	if is_instance_valid(_device_grid):_device_grid.columns=1

func _window_input(event:InputEvent):
	if handle_list_input(event):set_input_as_handled();return
	if event is InputEventKey and (event.keycode==KEY_ESCAPE or event.physical_keycode==KEY_ESCAPE):
		if event.pressed and not event.echo:
			if is_instance_valid(host):host.handle_escape()
			else:cancel()
		set_input_as_handled()
