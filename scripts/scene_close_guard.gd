extends AcceptDialog
## Owns only the close decision, never persistence or SceneTree.quit().
## Host: refresh dirty state, then request_close(scene_name, scene_is_dirty).
## Connect request_save to the existing scene/save card, quit_confirmed to quit.
signal request_save
signal quit_confirmed

const UITheme = preload("res://scripts/ui_theme.gd")
var save_button: Button
var discard_button: Button
var _configured := false
var _decision_pending := false
var _quit_emitted := false

func _ready() -> void:
	setup()

func setup(shared_theme: Theme = null) -> void:
	if shared_theme != null:
		theme = shared_theme
	elif theme == null:
		theme = UITheme.create(load("res://assets/InterfaceCJK.ttc"))
	if _configured: return
	_configured = true
	name = "SceneCloseGuard"
	title = "关闭前确认"
	visible = false
	transient = true
	exclusive = true
	unresizable = true
	dialog_autowrap = true
	dialog_hide_on_ok = false
	ok_button_text = "取消"
	get_ok_button().name = "CancelClose"
	get_ok_button().tooltip_text = "继续当前场景，不保存、不退出。Esc同样取消。"
	save_button = add_button("前往保存", false, "save")
	save_button.name = "GoToSceneSave"
	save_button.tooltip_text = "仅打开现有场景存档卡；仍需手动选择槽位并确认保存，不会自动退出。"
	discard_button = add_button("放弃更改并退出", false, "discard")
	discard_button.name = "DiscardAndQuit"
	discard_button.tooltip_text = "明确丢弃当前未保存更改并退出；不覆盖任何存档。"
	discard_button.add_theme_color_override("font_color", UITheme.ERROR)
	confirmed.connect(_cancel)
	canceled.connect(_cancel)
	close_requested.connect(_cancel)
	custom_action.connect(_on_action)
	window_input.connect(_window_input)

func request_close(scene_name: String, dirty: bool) -> void:
	setup()
	if _quit_emitted: return
	# Repeated OS close requests may not bypass an already open decision,
	# even if a stale/recomputed dirty flag differs while the dialog is visible.
	if _decision_pending and visible:
		get_ok_button().grab_focus()
		return
	_decision_pending = false
	if not dirty:
		_confirm_quit()
		return
	_decision_pending = true
	var caption := scene_name.replace("\n", " ").replace("\r", " ").strip_edges()
	if caption.is_empty(): caption = "当前场景"
	if caption.length() > 80: caption = caption.left(79) + "…"
	dialog_text = "场景“%s”有未保存更改。\n\n前往保存仅打开场景存档卡，不会写入文件或自动退出。\n“放弃更改并退出”将丢弃这些未保存更改。" % caption
	get_label().tooltip_text = scene_name
	var available := Vector2i(get_tree().root.get_visible_rect().size)
	var target := Vector2i(maxi(320, mini(560, available.x - 32)), maxi(210, mini(250, available.y - 32)))
	min_size = Vector2i(mini(480, target.x), 180)
	popup_centered(target)
	# The non-destructive choice is the initial keyboard/default action.
	get_ok_button().grab_focus()

func handle_escape() -> bool:
	if not _decision_pending or not visible: return false
	_cancel()
	return true

func _window_input(event: InputEvent) -> void:
	if not _decision_pending or not visible: return
	if event is InputEventKey and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		set_input_as_handled()
		if event.pressed and not event.echo: _cancel()

func _cancel() -> void:
	_decision_pending = false
	hide()

func _on_action(action: StringName) -> void:
	if not _decision_pending or not visible: return
	if action == &"save":
		_cancel()
		request_save.emit()
	elif action == &"discard":
		_cancel()
		_confirm_quit()

func _confirm_quit() -> void:
	if _quit_emitted: return
	_quit_emitted = true
	quit_confirmed.emit()
