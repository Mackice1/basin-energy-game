extends "res://tests/test_visual_ui.gd"
## Run unchanged legacy control/metric assertions against semantic card nesting.
func test_ui_events_and_layout() -> void:
	var ancestor:Node=game.device_picker.get_parent()
	while not ancestor is ScrollContainer:ancestor=ancestor.get_parent()
	var scroll:ScrollContainer=ancestor
	var body:VBoxContainer=scroll.get_child(0)
	var dock = game.find_child("RightDock", true, false)
	var shell: PanelContainer = dock.panels.energy
	check(not shell.visible, "energy panel starts collapsed")
	dock.toggle_panel("energy")
	await process_frame
	await process_frame
	var footer: PanelContainer = game.hud_footer
	var right_point := shell.global_position + Vector2(3, 3)
	var footer_point := footer.global_position + Vector2(3, 3)
	check(game.pointer_over_ui(right_point) and game.pointer_over_ui(footer_point), "HUD regions are included in pointer mask")
	click(right_point)
	await process_frame
	check(game.world_clicks == 0, "right-panel padding does not click through to the world")
	click(footer_point)
	await process_frame
	check(game.world_clicks == 0, "footer padding does not click through to the world")
	var map_point := Vector2(250, 350)
	check(not game.pointer_over_ui(map_point), "test world point is outside all HUD regions")
	click(map_point)
	await process_frame
	check(game.world_clicks == 1, "uncovered map click reaches the controller")
	game.select_device(0)
	game.open_parameters(false)
	click(map_point)
	await process_frame
	check(game.world_clicks == 1, "parameter modal blocks underlying map interaction")
	game.param_dialog.hide()
	var previous_size := shell.size
	for caption in ["电力分项与守恒", "技术详情"]:
		press_button(body, caption, true)
	await process_frame
	await process_frame
	await process_frame
	check(scroll.get_v_scroll_bar().visible, "expanded details use vertical scrolling")
	check(body.size.y > scroll.size.y, "expanded content remains inside bounded scroll viewport")
	check(shell.size == previous_size, "expanding details does not grow the HUD shell")
	check(shell.get_global_rect().end.y <= root.size.y, "right HUD shell remains within viewport height")
	check(not scroll.get_h_scroll_bar().visible and body.size.x <= scroll.size.x, "expanded CJK content fits without horizontal clipping")

