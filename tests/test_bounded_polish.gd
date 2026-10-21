extends SceneTree
## V16.2 bounded presentation regression. Deterministic terrain and pointer
## fixtures keep these checks about UI isolation, not native mouse coverage.
const Previous = preload("res://tests/test_interaction_polish.gd")
const SITE := 1000000
const PV := 0
const AC := 1
const BATTERY := 2
const BOILER := 3
const STORE := 4
const EXCHANGER := 5
var game: Previous.Fixture
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); print("FAIL BOUNDED_POLISH ", message)
func canonical(value) -> String: return JSON.stringify(JSON.parse_string(JSON.stringify(value)))
func unchanged(before: String, revision: int, undos: int, message: String) -> void:
	check(canonical(game.state()) == before, message + " preserves serialized state")
	check(game.scene_revision == revision and game.undo_states.size() == undos, message + " preserves edit/undo history")

func run() -> void:
	root.size = Vector2i(1440, 900)
	root.content_scale_size = Vector2i.ZERO
	root.gui_embed_subwindows = true
	game = Previous.Fixture.new(); root.add_child(game)
	game.camera.current = true
	game.paused = true
	game.interaction_caption = Label.new(); game.add_child(game.interaction_caption)
	for spec in [["pv", Vector2(-45, 0)], ["station", Vector2(-20, 0)], ["battery", Vector2(-20, 25)]]:
		check(game.add_equipment(spec[0], spec[1], false), "fixture places " + spec[0])
	check(game.add_station(Vector2(30, 0), false), "fixture places facility")
	for spec in [["electric_boiler", Vector2(-1.0, -0.7)], ["thermal_store", Vector2(0.9, -0.6)], ["heat_exchanger", Vector2(0, 1.0)]]:
		check(game.add_internal_device(SITE, spec[0], spec[1]), "fixture places " + spec[0])
	game.device(BATTERY).state.energy_mwh = 0.25
	game.device(STORE).state.energy_mwhth = 0.625
	game.elapsed_s = 123.5
	game.refresh(); game.undo_states.clear()
	check(game.validate_state(game.state()).is_empty(), "fixture nonzero inventories and metric scene validate")
	test_connection_captions()
	test_annotation_arbitration()
	test_repeated_cancellation()
	test_repeated_save_reads()
	for key in ["terrain", "infrastructure", "overlay", "confirmation", "param_dialog", "param_errors", "param_target", "data_dialog", "data_list", "line_dialog", "line_capacity", "line_loss", "line_choice", "station_interior"]:
		var node = game.get(key)
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	game.free(); await process_frame
	print("BOUNDED_POLISH checks=", checks, " failures=", failures.size(), " input=controller-dispatch")
	quit(0 if failures.is_empty() else 1)

func test_connection_captions() -> void:
	var before := canonical(game.state()); var revision := game.scene_revision; var undos := game.undo_states.size()
	game.set_mode("link")
	check(game.connection_caption(-2).contains("请选择起点"), "empty link mode explains the next first-endpoint action")
	game.link_to(AC)
	check(game.connection_caption(-2).contains("下一步") and game.connection_caption(-2).contains("Esc"), "pending source explains target selection and cancellation")
	check(game.connection_caption(AC).contains("不能连接自身"), "self-target explains rejection")
	var caption: String = game.connection_caption(PV)
	check(caption.begins_with(game.endpoint_name(PV) + " → " + game.endpoint_name(AC)), "reverse click order displays canonical electrical direction")
	check(caption.contains("AC") and caption.contains("MW") and caption.contains("可连接") and caption.count("\n") == 1, "valid electrical caption has two lines with carrier, capacity and action")
	check(game.connection_caption(STORE).contains("不兼容"), "cross-carrier mismatch has an explicit reason")
	check(game.connection_caption(SITE).contains("映射端口"), "facility target explains internal boundary-port mapping")
	game.picked_id = PV; game.update_interaction_visuals()
	check(game.interaction_caption.text == caption and game.interaction_caption.tooltip_text.contains(game.endpoint_description(PV)), "visible caption and full tooltip use the same authoritative candidate")
	check(is_instance_valid(game.link_preview), "compatible caption retains transient link preview")
	game.cancel_interaction()
	game.set_mode("link"); game.link_to(EXCHANGER)
	caption = game.connection_caption(BOILER)
	check(caption.begins_with(game.endpoint_name(BOILER) + " → " + game.endpoint_name(EXCHANGER)), "reverse thermal clicks display canonical output-to-input direction")
	check(caption.contains("90/60°C") and caption.contains("MWth") and caption.contains("可连接"), "thermal caption retains temperature grade and thermal unit")
	game.cancel_interaction()
	unchanged(before, revision, undos, "caption, tooltip, source/target preview and cancellation")
	var edge: Dictionary = game.connection_candidate(PV, AC)
	game.links.append(edge)
	var linked := canonical(game.state())
	game.set_mode("link"); game.link_to(AC)
	check(game.connection_caption(PV).contains("重复"), "duplicate caption reports authoritative topology rejection")
	game.picked_id = PV; game.update_interaction_visuals()
	check(game.link_preview == null, "duplicate target does not show a misleading valid route")
	game.cancel_interaction()
	unchanged(linked, revision, undos, "duplicate rejection display")
	game.links.pop_back()
	check(canonical(game.state()) == before, "test fixture duplicate edge cleanup restores original state")

func make_tag(caption: String, screen: Vector2) -> Label3D:
	var tag := Label3D.new(); tag.text = caption; tag.font = game.font_full; tag.font_size = 28
	game.equipment.add_child(tag)
	tag.global_position = game.camera.project_position(screen, 30.0)
	return tag

func test_annotation_arbitration() -> void:
	var before := canonical(game.state()); var revision := game.scene_revision; var undos := game.undo_states.size()
	for dimensions in [Vector2i(1024, 768), Vector2i(1440, 900)]:
		root.size = dimensions
		var center := Vector2(dimensions) * 0.5
		var selected := make_tag("Selected device #2", center)
		var hovered := make_tag("Hovered device #0", center)
		var secondary := make_tag("Same-owner status", center)
		var port := make_tag("Port", center); port.name = "PortLabel"
		var outside := make_tag("Clipped title", Vector2(2, 2))
		var hidden := make_tag("Already hidden", center); hidden.hide()
		var selected_transform := selected.transform
		var port_transform := port.transform
		var entries := [{"tag":hovered, "priority":50, "height":22.0}, {"tag":selected, "priority":110, "height":22.0}, {"tag":secondary, "priority":100, "height":18.0}, {"tag":outside, "priority":0, "height":22.0}, {"tag":hidden, "priority":200, "height":22.0}]
		game.suppress_annotation_collisions(entries)
		check(selected.visible and not hovered.visible, "%s selected title wins overlap regardless of input order" % dimensions)
		check(not secondary.visible, "%s selected title also wins same-owner secondary status overlap" % dimensions)
		check(not outside.visible and not hidden.visible, "%s viewport clipping and pre-hidden labels remain quiet" % dimensions)
		check(port.visible and port.transform == port_transform, "%s port omitted from title arbitration remains available and unmoved" % dimensions)
		check(selected.transform == selected_transform, "%s overlap suppression never moves actual annotation anchor" % dimensions)
		for iteration in 12:
			selected.show(); hovered.show(); game.suppress_annotation_collisions(entries)
			check(selected.visible and not hovered.visible, "%s arbitration stays deterministic on refresh %d" % [dimensions, iteration])
		var multiline := make_tag("Power status\nThermal inventory", center + Vector2(0, 32))
		selected.show()
		game.suppress_annotation_collisions([{"tag":multiline, "priority":100, "height":18.0}, {"tag":selected, "priority":110, "height":22.0}])
		check(selected.visible and not multiline.visible, "%s second status line participates in overlap rectangle" % dimensions)
		multiline.global_position = game.camera.project_position(center + Vector2(0, 70), 30.0)
		multiline.show()
		game.suppress_annotation_collisions([{"tag":multiline, "priority":100, "height":18.0}, {"tag":selected, "priority":110, "height":22.0}])
		check(selected.visible and multiline.visible, "%s separated multiline readout remains visible" % dimensions)
		multiline.free()
		for tag in [selected, hovered, secondary, port, outside, hidden]: tag.free()
		game.picked_id = -2; game.select_device(SITE); game.focus_selected()
		var facade = game.station_nodes[str(SITE)]
		var saved_status_position: Vector3 = facade.status_label.position
		var title_position: Vector3 = facade.title_label.position
		var port_position: Vector3 = facade.get_port_position("ac_in")
		facade.status_label.position = title_position
		game.update_interaction_visuals()
		check(facade.title_label.visible and not facade.status_label.visible, "%s actual selected facade title wins co-located runtime readout" % dimensions)
		check(facade.title_label.position == title_position and facade.get_port_position("ac_in") == port_position, "%s actual facade title arbitration preserves anchors and physical ports" % dimensions)
		facade.status_label.position = saved_status_position
	unchanged(before, revision, undos, "two-size projected annotation arbitration")

func test_repeated_cancellation() -> void:
	var before := canonical(game.state()); var revision := game.scene_revision; var undos := game.undo_states.size()
	for iteration in 24:
		game.set_mode("link"); game.link_to(PV); game.picked_id = AC; game.update_interaction_visuals()
		check(is_instance_valid(game.link_preview), "cycle %d produces actual transient route" % iteration)
		game.cancel_interaction(); game.cancel_interaction()
		check(game.pending_link == -2 and game.link_preview == null and game.mode == "select", "cycle %d clears endpoint, route and mode" % iteration)
		game.start_build("battery"); game.cursor = Vector2(0, 25); game._process(0.0)
		check(is_instance_valid(game.ghost), "cycle %d creates transient construction preview" % iteration)
		game.cancel_interaction(); game.cancel_interaction()
		check(game.ghost == null and game.placement_outline == null and not game.drag_active, "cycle %d removes all construction/transient state" % iteration)
		unchanged(before, revision, undos, "repeated cancellation cycle %d" % iteration)

func test_repeated_save_reads() -> void:
	game.cancel_interaction()
	var before := canonical(game.state())
	var path := "user://bounded_polish_%d.json" % OS.get_process_id()
	check(game.write_save(path), "actual isolated save writes")
	var digest := FileAccess.get_sha256(path)
	for iteration in 8:
		game.set_mode("link"); game.link_to(PV); game.picked_id = AC; game.update_interaction_visuals()
		game.cancel_interaction()
		check(game.read_save(path), "cycle %d reads through real validated save path" % iteration)
		check(canonical(game.state()) == before, "cycle %d disk restore preserves inventory, layout and ledgers" % iteration)
		check(FileAccess.get_sha256(path) == digest, "cycle %d read and presentation never rewrites input file" % iteration)
		check(game.paused and game.speed == 1 and game.accumulator == 0, "cycle %d restore resets only playback controls" % iteration)
	check(game.device(STORE).state.energy_mwhth == 0.625 and game.device(BATTERY).state.energy_mwh == 0.25 and game.elapsed_s == 123.5, "all repeated flows retain both nonzero stocks and clock")
	check(game.state().schema == 12 and game.state().model_version == 21 and game.state().dimension_profile == "metric_v1", "bounded UI polish preserves model/schema and metric dimension profile")
	DirAccess.remove_absolute(path)
