extends SceneTree
const Base=preload("res://tests/test_storage_world_1003.gd")
const C=preload("res://scripts/device_catalog.gd")
const V=preload("res://scripts/save_validator.gd")
const Form=preload("res://scripts/parameter_form.gd")
const InspectorFixture=preload("res://tests/test_device_inspector_v23.gd")
class GeoFixture extends Base.Fixture:
	var slope_gate:=INF
	var exclusion_gate:=INF
	func slope_at(x:float,_z:float)->float:return 20.0 if x>=slope_gate else 0.0
	func exclusion(x:float,_z:float)->String:return "测试禁建区" if x>=exclusion_gate else ""
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error("FLOW_GEOMETRY "+message)
func near(a:float,b:float,message:String):check(absf(a-b)<1e-6,message)
func _initialize():call_deferred("run")
func fixture()->GeoFixture:
	var game:=GeoFixture.new()
	game.cfg={"max_build_slope_degrees":8.0};game.booted=true;game.dimension_profile="metric_v1"
	for kind in game.KINDS:game.templates[kind]=game.model.defaults(kind)
	game.templates.battery_flow.merge({"capacity_mwh":10.0,"charge_mw":2.0,"discharge_mw":2.0},true)
	return game
func run():
	var helper:=Base.new();var game:=fixture()
	check(game.add_equipment("battery_flow",Vector2.ZERO),"new flow placed")
	check(game.devices[0].geometry_profile==V.FLOW_PROCESS_GEOMETRY,"new construction explicit process marker")
	check(game.devices[0].site_geometry_profile=="reference_size_v1","current construction explicit finite-hardware marker")
	near(game.device_footprint(game.devices[0]),Vector2(42,36).length()*.05,"current derated 10MWh retains complete 12MWh hardware collision radius")
	check(game.device_dimensions(game.devices[0]).land_dimensions_m==Vector3(42,0,36),"current reference footprint keeps complete installed hardware")
	check(game.can_place("battery_flow",Vector2(3,0))!="","new tight placement rejected")
	check(game.add_equipment("battery_flow",Vector2(6,0)),"second new flow placed safely")
	var current_scene:Dictionary=game.state().duplicate(true)
	var old:Dictionary=game.state();old.schema=17;old.model_version=26;old.material_energy=game.Materials.initial_energy_v2(old.devices)
	for kind in old.templates.keys():
		if kind not in V.SCHEMA17_KINDS:old.templates.erase(kind)
	# Historical schema17 predates both geometry markers; keep values and stock.
	for d in old.devices:
		d.erase("geometry_profile");d.erase("site_geometry_profile")
	old.devices[1].x=3.0
	check(V.SCHEMA17_KINDS.size()==35 and old.templates.size()==35,"schema17 and18 freeze exact 35 kinds")
	check(V.validate(old)=="","historical tight flow scene valid before load")
	var process_scene:=old.duplicate(true);process_scene.schema=18
	for d in process_scene.devices:d.geometry_profile=V.FLOW_PROCESS_GEOMETRY
	process_scene.devices[1].x=6.0
	check(V.validate(process_scene)=="","schema18 process geometry without site marker remains valid")
	var process_fixture:=fixture();process_fixture.restore(process_scene)
	check(process_fixture.devices==process_scene.devices,"schema18 restore preserves all coordinates, parameters and stock")
	check(process_fixture.device_dimensions(process_fixture.devices[0]).land_dimensions_m==Vector3(42,0,19),"schema18 unmarked process retains historical 42x19 installation")
	near(process_fixture.device_footprint(process_fixture.devices[0]),Vector2(42,19).length()*.05,"schema18 process collision radius remains versioned")
	check(not process_fixture.devices[0].has("site_geometry_profile"),"schema18 restore never silently installs reference hardware")
	var snapshot:=old.duplicate(true);game.restore(old)
	check(old==snapshot and game.devices==old.devices,"restore never moves or rewrites historical devices")
	near(game.device_footprint(game.devices[0]),Vector2(18,14).length()*.05,"old site radius retained")
	check(game.device_dimensions(game.devices[0]).land_dimensions_m==Vector3(18,0,14),"old site layout retained")
	check(game.visual_params(game.devices[0].params,game.devices[0]).visual_geometry_profile==V.FLOW_ICON_GEOMETRY,"old map and move visual configuration")
	check(game.validate_state(game.state())=="" and game.state().schema==game.CURRENT_SAVE_SCHEMA and game.state().model_version==game.CURRENT_MODEL_VERSION,"old scene can resave current schema without movement")
	check(V.validate(JSON.parse_string(JSON.stringify(game.state())))=="","mixed geometry metadata JSON safe")
	check(game.can_place("battery_flow",Vector2(.5,0),0,game.devices[0].params)=="","moving old icon uses historical radius")
	game.selected_id=0;check(game.move_selected(Vector2(.5,0)),"old move accepted without upgrade")
	check(not game.devices[0].has("geometry_profile"),"moving never silently upgrades")
	game.undo();check(game.devices==old.devices,"undo retains old geometry and original coordinates")
	var parameters:Dictionary=game.devices[0].params.duplicate(true);parameters.charge_mw=1.5
	game.parameter_form=Form.new();game.parameter_form.set_parameters("battery_flow",parameters,false);game.param_scope="device";game.parameter_id=0
	game.apply_parameters();near(game.devices[0].params.charge_mw,1.5,"single parameter change uses historical footprint")
	check(not game.devices[0].has("geometry_profile") and game.devices[0].state==old.devices[0].state,"single parameter change preserves stock and geometry version")
	game.parameter_form.free();game.parameter_form=null
	var result:Dictionary=game.apply_bulk_parameters("battery_flow",[0,1],{"discharge_mw":1.4})
	check(result.ok and V.validate(game.state())=="","bulk parameters retain valid legacy tight layout")
	for d in game.devices:check(not d.has("geometry_profile"),"batch never upgrades legacy geometry")
	var mixed:Dictionary=game.state();mixed.devices[1].geometry_profile=V.FLOW_PROCESS_GEOMETRY
	check(V.validate(mixed)!="","new-old mixed overlap uses both actual stored radii")
	mixed.devices[1].x=6.0;check(V.validate(mixed)=="","valid old-new mixed layout accepted")
	for bad in ["future_geometry",true,2,null,""]:
		var invalid:=mixed.duplicate(true);invalid.devices[1].geometry_profile=bad;check(V.validate(invalid)!="","unknown/type-invalid marker rejected")
	var invalid:=mixed.duplicate(true);invalid.devices[1].kind="battery";check(V.validate(invalid)!="","wrong kind geometry marker rejected")
	invalid=old.duplicate(true);invalid.devices[1].geometry_profile=V.FLOW_PROCESS_GEOMETRY;check(V.validate(invalid)!="","schema17 refuses geometry metadata")
	invalid=old.duplicate(true);invalid.templates.future_kind={};check(V.validate(invalid)!="","schema17 stays closed to future catalog additions")
	var boundary:=old.duplicate(true);boundary.devices.resize(1);boundary.devices[0].x=93.0
	check(V.validate(boundary)=="","old near-edge scene remains valid")
	boundary.schema=18;boundary.devices[0].geometry_profile=V.FLOW_PROCESS_GEOMETRY;check(V.validate(boundary)!="","new larger near-edge footprint rejected")
	game.devices.resize(1);game.devices[0].x=0.0;game.slope_gate=1.8
	check(game.can_place("battery_flow",Vector2.ZERO,0,game.devices[0].params)=="","old slope probes use old radius")
	check(game.can_place("battery_flow",Vector2.ZERO).contains("旧比例"),"legacy scene explicitly refuses new construction before migration")
	# A legal current empty scene reaches the terrain rule, rather than passing
	# accidentally because the legacy-addition guard returned first.
	var terrain_fixture:=fixture();terrain_fixture.slope_gate=1.8
	check(terrain_fixture.is_reference_layout(),"separate current terrain fixture has a valid reference profile")
	check(terrain_fixture.can_place("battery_flow",Vector2.ZERO).contains("坡度"),"current larger radius rejects specifically because of slope")
	terrain_fixture.slope_gate=INF;terrain_fixture.exclusion_gate=1.8
	check(terrain_fixture.can_place("battery_flow",Vector2.ZERO).contains("测试禁建区"),"current larger radius reaches actual exclusion rule")
	check(game.validate_state(game.state())=="","load terrain validation uses stored old radius")
	game.slope_gate=INF;game.exclusion_gate=1.8
	check(game.validate_state(game.state())=="","old exclusion probes retain old radius")
	var expanded:=game.state();expanded.devices[0].geometry_profile=V.FLOW_PROCESS_GEOMETRY
	check(game.validate_state(expanded).contains("测试禁建区"),"historical process exclusion probes use larger stored footprint")
	game.exclusion_gate=INF
	var old_report:Dictionary=game.model.dispatch(game.devices,[],{}, {},1.0)
	var new_devices:Array=game.devices.duplicate(true);new_devices[0].geometry_profile=V.FLOW_PROCESS_GEOMETRY
	check(old_report==game.model.dispatch(new_devices,[],{}, {},1.0),"geometry metadata cannot change physical dispatch")
	game.dimension_summary=Label.new();game.selected_id=0;game.update_dimension_display();check(game.dimension_summary.text.contains("旧比例兼容") and game.dimension_summary.text.contains("待尺寸迁移"),"sidebar prioritizes whole-scene legacy mode")
	game.devices[0].geometry_profile=V.FLOW_PROCESS_GEOMETRY;game.update_dimension_display();check(game.dimension_summary.text.contains("旧比例兼容"),"historical process marker alone does not claim current reference mode")
	game.dimension_summary.free();game.dimension_summary=null
	# Existing one-argument host API must remain compatible with detail refresh.
	var host:=InspectorFixture.Host.new();root.add_child(host);var inspector:=InspectorFixture.Inspector.new();host.add_child(inspector);inspector.setup(host)
	host.devices=[old.devices[0].duplicate(true)];check(inspector.open_device(0),"legacy detail opens")
	check(inspector.model_label.text.contains("旧版图标化") and inspector._signature.contains(V.FLOW_ICON_GEOMETRY),"detail uses old model, label and signature")
	host.devices[0].geometry_profile=V.FLOW_PROCESS_GEOMETRY;inspector.refresh()
	check(inspector.model_label.text.contains("42×19") and inspector._signature.contains(V.FLOW_PROCESS_GEOMETRY),"schema18 detail retains process model and historical single-module description")
	check(inspector.model_node.get_meta("land_dimensions_m")==Vector3(42,0,19),"schema18 detail uses actual unmarked process dimensions")
	host.devices=[current_scene.devices[0].duplicate(true)];inspector.refresh()
	check(inspector._signature.contains("reference_size_v1") and inspector.model_node.get_meta("land_dimensions_m")==Vector3(42,0,36),"current detail uses complete reference hardware rather than the historical process footprint")
	check(host.devices[0]==current_scene.devices[0],"opening current detail preserves exact coordinates, parameters and inventory")
	host.free();helper.cleanup(game);helper.cleanup(process_fixture);helper.cleanup(terrain_fixture);helper.free();await process_frame
	print("FLOW_GEOMETRY_COMPAT checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
