extends SceneTree
## Read-only dock interactions use the real scene controls, with no terrain or
## equipment renderer. Explicitly cover closed hit regions and repeated toggles.

class DockGame:
	extends "res://scripts/world_game.gd"
	var world_clicks := 0
	func _ready():
		cfg = {"max_build_slope_degrees": 8.0}
		for kind in KINDS:
			templates[kind] = model.defaults(kind)
		make_ui()
		booted = true
		set_process(false)
	func pick_ground(_position: Vector2) -> Vector2: return Vector2.ZERO
	func nearest(_position: Vector2) -> int: return -2
	func select_site(_position: Vector2): world_clicks += 1
	func rebuild_cables(): pass

var checks := 0
var failures: Array[String] = []

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("SIDE_DOCK_FAIL: " + description)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1600, 1000)
	var game := DockGame.new()
	root.add_child(game)
	await process_frame
	await process_frame
	var dock = game.find_child("RightDock", true, false)
	check(dock != null, "dock is present in the real HUD")
	for key in ["energy", "demand", "location", "weather", "templates", "optimization"]:
		check(dock.buttons.has(key) and dock.panels.has(key), key + " section has an entry and panel")
	check(dock.buttons.size() == dock.panels.size(), "each section has exactly one navigation entry")
	check(dock.active_key.is_empty(), "all sections start collapsed")
	for key in dock.panels:
		check(not dock.panels[key].visible, key + " starts hidden")
		check(not dock.buttons[key].text.is_empty() and dock.buttons[key].icon != null, key + " uses labelled icon button")
		check(not dock.buttons[key].tooltip_text.is_empty() and not dock.buttons[key].tooltip_text.contains("\n"), key + " has a short name-only tooltip")
	var rail: Control = dock.get_hit_regions()[0]
	check(rail.size.x == 74 and game.pointer_over_ui(rail.get_global_rect().get_center()), "74px labelled rail captures its pointer area")
	var energy: Control = dock.panels.energy
	var former_panel_point: Vector2 = energy.get_global_rect().position + Vector2(10, 80)
	check(not game.pointer_over_ui(former_panel_point), "collapsed panel does not reserve map area")
	var clicked := InputEventMouseButton.new()
	clicked.button_index = MOUSE_BUTTON_LEFT
	clicked.pressed = true
	clicked.position = former_panel_point
	game._unhandled_input(clicked)
	check(game.world_clicks == 1, "map remains clickable where hidden panel was")
	dock.buttons.energy.pressed.emit()
	await process_frame
	check(dock.active_key == "energy" and energy.visible, "energy icon opens its section")
	check(game.pointer_over_ui(former_panel_point), "open panel captures its area")
	check(not game.modal_visible(), "dock stays nonmodal")
	check(is_instance_valid(game.speed_control) and game.speed_control.has_signal("speed_changed"), "simulation speed controls remain available")
	dock.buttons.weather.pressed.emit()
	await process_frame
	check(not energy.visible and dock.panels.weather.visible and not dock.buttons.energy.button_pressed, "another icon closes previous section")
	var open_count := 0
	for panel in dock.panels.values():
		if panel.visible:
			open_count += 1
	check(open_count == 1, "only one section is open")
	dock.buttons.weather.pressed.emit()
	check(dock.active_key.is_empty() and not dock.panels.weather.visible, "second click collapses the same section")
	check(not game.pointer_over_ui(former_panel_point), "closing restores map pointer access")
	for key in dock.panels:
		dock.toggle_panel(key)
		await process_frame
		await process_frame
		var shell: PanelContainer = dock.panels[key]
		var scroll: ScrollContainer = shell.get_child(0).get_child(1)
		check(shell.get_global_rect().end.y <= root.size.y - 100, key + " stays clear of bottom construction bar")
		check(not scroll.get_h_scroll_bar().visible, key + " requires no horizontal scrolling")
		var close: Button = shell.get_child(0).get_child(0).get_child(1)
		close.pressed.emit()
		check(dock.active_key.is_empty() and not shell.visible, key + " close button resets visibility and selection")
	dock.toggle_panel("location")
	var read_only_text := _all_text(dock.panels.location)
	check(read_only_text.contains("位置用于太阳位置计算") and read_only_text.contains("不会下载当地天气"), "location limitations are explicit")
	check(_all_text(dock.panels.weather).contains("没有气网压力、水量、煤炭、蒸汽或氢调度") and _all_text(dock.panels.weather).contains("独立燃料资源设置"), "resource display distinguishes bounded gas resource from unimplemented pressure/water/other carriers")
	check(_all_text(dock.panels.templates).contains("资源与气象模板库尚未实现"), "template scope is explicit")
	check(game.detail.is_ancestor_of(dock.panels.location) == false and dock.panels.location.is_ancestor_of(game.detail), "selected site detail lives in location section")
	dock.close_panels()
	for key in ["camera", "lod_camera", "terrain", "labels", "infrastructure", "selection", "overlay", "equipment", "cables"]:
		var node = game.get(key)
		if is_instance_valid(node) and node.get_parent() == null:
			node.free()
	game.free()
	await process_frame
	print("SIDE_DOCK_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _all_text(node: Node) -> String:
	var text := str(node.text) if node is Label or node is Button else ""
	for child in node.get_children():
		text += "\n" + _all_text(child)
	return text
