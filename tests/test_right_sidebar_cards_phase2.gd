extends SceneTree
const Fixture=preload("res://tests/test_compact_build_bulk_ui_1003.gd")
const Card=preload("res://scripts/right_metric_card.gd")
var game
var checks:=0
var failures:Array[String]=[]
func _initialize():call_deferred("run")
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error("RIGHT_CARD_FAIL "+message)
func settle():
	for i in 8:await process_frame
func descendants(node:Node)->Array:
	var all:Array=[]
	for child in node.get_children():all.append(child);all.append_array(descendants(child))
	return all
func run():
	root.content_scale_size=Vector2i.ZERO;root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	check(Card.number(0.0)=="0.000" and Card.number(-0.0)=="0.000","zero format stable without negative zero")
	check(Card.number(-0.0000123)=="-1.23e-05" and Card.number(100000.0)=="1.00e+05","signed scientific notation preserves small and large readings")
	check(Card.number(0.00099999)=="1.00e-03","scientific rounding normalizes mantissa")
	check(Card.number(INF)=="—" and Card.number(NAN)=="—","nonfinite UI input never claims a numeric reading")
	game=Fixture.UIController.new();root.add_child(game);await settle()
	game.devices=[]
	for kind in ["fuel_boiler","solar_thermal","high_temp_store","thermal_store"]:
		game.devices.append({"id":game.devices.size(),"kind":kind,"params":game.model.defaults(kind),"x":0.0,"z":0.0,"state":{"energy_mwhth":0.1234567}})
	game.result={"generated_mw":2.7654321,"delivered_mw":1.2,"thermal":{"served_mwth":0.987654,"demand_mwth":1.2,"unserved_mwth":0.212346,"balance_error_mwth":0.0000000123},"fuel":{"input_mw":0.3333333,"volume_nm3_per_h":33.33333,"heat_output_mwth":0.3,"auxiliary_electric_mw":0.0001234,"conversion_loss_mw":0.0333333},"solar":{"available_mwth":0.11111,"useful_mwth":0.10111},"high_temp":{"available_mwth":0.02,"useful_mwth":0.01},"rankine":{"gross_electric_mw":0.012,"net_electric_mw":0.01,"auxiliary_electric_mw":0.002,"mass_flow_kg_s":0.000025}}
	game.fuel_energy={"input_mwh":1.1111111,"volume_nm3":12345.67,"auxiliary_mwh":0.00000012,"cost":123.4567}
	var result_before:Dictionary=game.result.duplicate(true)
	var fuel_before:Dictionary=game.fuel_energy.duplicate(true)
	game.update_status();game.update_site_sidebar(Vector2(123.4567,-2.33333));await settle()
	check(game.result==result_before and game.fuel_energy==fuel_before,"presentation does not alter physics or cumulative data")
	check(game.sidebar_readouts.heat_served.value.text=="0.988","thermal ordinary readings use consistent three decimals")
	check(game.sidebar_readouts.fuel_input.value.text=="0.333","fuel shares same normal precision")
	check(game.sidebar_readouts.fuel_cost.value.text=="123.46","currency keeps two decimals")
	check(game.sidebar_readouts.heat_balance.value.text=="1.23e-08","nonzero residual never falsely rounded to zero")
	check(game.sidebar_readouts.fuel_aux.value.text=="1.23e-04","small auxiliary load remains visible")
	check(game.sidebar_readouts.fuel_input.value.tooltip_text.contains("0.3333333"),"full raw precision accessible in tooltip")
	check(game.metric_values.net.get_theme_font_size("font_size")>game.sidebar_readouts.heat_served.value.get_theme_font_size("font_size"),"hero value has intentional hierarchy")
	check(game.sidebar_readouts.heat_served.caption.get_theme_font_size("font_size")<game.sidebar_readouts.heat_served.value.get_theme_font_size("font_size"),"value distinct from field caption")
	check(game.sidebar_readouts.heat_served.unit.get_theme_font_size("font_size")<game.sidebar_readouts.heat_served.caption.get_theme_font_size("font_size"),"units have consistent smaller hierarchy")
	check(game.time_local.text.contains("2026-") and game.time_utc.text.contains("2026-"),"local and UTC dates available separately")
	check(game.time_zone_caption.text.contains("UTC+08:00"),"local time has explicit accurate zone")
	check(not game.climate_panel.live.visible,"legacy mixed prose live weather hidden")
	for key in ["heat_served","heat_demand","heat_unserved","heat_boiler_electric","heat_inventory","heat_balance"]:check(game.sidebar_readouts.has(key),"separate thermal readout "+key)
	for key in ["electric","fuel_current","weather","calendar","demand_controls","template_settings","optimization"]:check(game.sidebar_groups[key] is PanelContainer,"semantic card group "+key)
	var scope_text:=""
	for node in descendants(game.hud_dock):
		if node is Label:scope_text+=node.text+"\n"
	check(scope_text.contains("101.325 kPa") and scope_text.contains("wind_height_m") and scope_text.contains("POA不能替代") and scope_text.contains("没有气网压力"),"all original measurement and resource caveats retained")
	# Expand actual help/settings controls, then inspect every layout including offscreen content.
	for node in descendants(game.hud_dock):
		if node is Button and node.text.ends_with("▸"):node.pressed.emit()
	await settle()
	for resolution in [Vector2i(1180,812),Vector2i(1024,768),Vector2i(800,600),Vector2i(640,480)]:
		root.size=resolution;await settle();game._layout_workspace();await settle()
		for key in ["energy","fuel","location","weather","demand","templates","optimization"]:
			game.hud_dock.close_panels();game.hud_dock.toggle_panel(key);await settle()
			var panel:Control=game.hud_dock.panels[key]
			var scroll:ScrollContainer=panel.get_child(0).get_child(1)
			var body:Control=scroll.get_child(0)
			check(panel.get_global_rect().end.x<=resolution.x and panel.get_global_rect().position.x>=0,"panel fits "+key+str(resolution))
			check(body.size.x<=scroll.size.x+1,"no horizontal overflow "+key+str(resolution)+" body="+str(body.size.x)+" scroll="+str(scroll.size.x))
			for node in descendants(body):
				if not node is Control or not node.is_visible_in_tree():continue
				check(node.get_global_rect().end.x<=scroll.get_global_rect().end.x+1,"right edge contained "+key+"/"+str(node.name)+str(resolution))
				if node is Label and (node.text.contains("MW") or node.text in ["Nm³/h","kWh/Nm³","kg/s"]):
					if node.autowrap_mode==TextServer.AUTOWRAP_OFF:check(node.get_line_count()==1,"units never isolated on extra line: "+node.text)
			for fields in game.sidebar_readouts.values():
				if not body.is_ancestor_of(fields.unit) or not fields.unit.is_visible_in_tree():continue
				scroll.ensure_control_visible(fields.row);await process_frame;await process_frame
				check(fields.unit.get_line_count()==1,"metric unit one line "+str(resolution)+fields.unit.text)
				check(scroll.get_global_rect().intersects(fields.value.get_global_rect()),"metric reachable by vertical scroll "+key)
				var measured:float=fields.unit.get_theme_font("font").get_string_size(fields.unit.text,HORIZONTAL_ALIGNMENT_LEFT,-1,fields.unit.get_theme_font_size("font_size")).x
				check(fields.unit.size.x+1>=measured,"complete unit fits reserved width "+fields.unit.text)
				var value_width:float=fields.value.get_theme_font("font").get_string_size(fields.value.text,HORIZONTAL_ALIGNMENT_LEFT,-1,fields.value.get_theme_font_size("font_size")).x
				check(fields.value.size.x+1>=value_width,"numeric reading fits without clipping "+fields.value.text)
			print("RIGHT_CARD_LAYOUT ",resolution," ",key," body=",body.size.x," scroll=",scroll.size.x)
	game.weather_snapshot={"valid":true,"local_datetime":"2026-01-01T12:00:00","utc_datetime":"2026-01-01T06:15:00","is_day":true};game.climate_config.utc_offset_hours=5.75;game.update_environment_sidebar("CSV; absent cloud and rain")
	check(game.sidebar_readouts.weather_cloud_cover.value.text=="未知" and game.sidebar_readouts.weather_precipitation_mm_h.value.text=="未知","missing imported cloud/rain never represented as zero")
	check(game.time_zone_caption.text.contains("UTC+05:45"),"quarter-hour offset not rounded incorrectly")
	game.weather_snapshot={"valid":false,"error":"out of range"};game.update_environment_sidebar("")
	check(game.time_local.text=="—" and game.time_utc.text=="—" and game.weather_origin.text.contains("out of range"),"invalid data clears stale dates and preserves reason")
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables"]:
		var node=game.get(key)
		if is_instance_valid(node) and node.get_parent()==null:node.free()
	game.free();await process_frame
	print("RIGHT_SIDEBAR_CARDS_PHASE2 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
