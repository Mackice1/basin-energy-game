extends Node3D
# Deterministic synthetic terrain; every overlay and site assessment uses this height field.
const MIN_CAMERA_DISTANCE := 8.0
const MAX_CAMERA_DISTANCE := 300.0
const MIN_CAMERA_PITCH := 0.25
const MAX_CAMERA_PITCH := 1.56
const CAMERA_GROUND_CLEARANCE := 0.6
var cfg: Dictionary
var noise := FastNoiseLite.new()
var camera := Camera3D.new()
var lod_camera := Camera3D.new()
var terrain := Terrain3D.new()
var height_image: Image
var control_image: Image
var base_color_image: Image
var terrain_initialized := false
var labels := Node3D.new()
var infrastructure := Node3D.new()
var selection := Node3D.new()
var overlay := Node3D.new()
var layer_buttons: Array[Button] = []
var yaw := -0.22
var pitch := 0.78
var distance := 235.0
var target := Vector3(0, 0, 0)
var layer := 0
var show_labels := true
var selected := Vector2(-14, 13)
var detail: Label
var layer_hint: Label
var font: Font
var frame := 0
var frame_times: Array[float] = []
var previous_tick := 0
var run_started := 0
var capture := false
var layer_names := ["地貌", "高程 / 坡度", "风资源", "太阳能", "水资源", "交通 / 燃料", "电网", "生态 / 禁建"]
var descriptions := ["砾石戈壁为主 · 北侧低山 / 南东局部沙丘", "同一高程场计算坡度 · 绿色缓坡 / 红色陡坡", "合成平均风速 · 风场仅作空间示意，非恒定出力", "合成太阳资源 · 辐照需由后续气象时序驱动", "蓝线为外引水走廊 · 干沟不作为稳定水源", "西侧公铁联运 · 外部煤源与天然气接入", "东侧送出节点 · 容量受限，尚未建设集电网络", "红色禁建：干沟洪道 / 盐碱洼地 / 生态保育区"]

func _ready():
	print("V2_INIT_START")
	height_image = Image.create_from_data(1024,1024,false,Image.FORMAT_RF,FileAccess.get_file_as_bytes("res://generated/height.raw"))
	control_image = Image.create_from_data(1024,1024,false,Image.FORMAT_RF,FileAccess.get_file_as_bytes("res://generated/control.raw"))
	base_color_image = Image.load_from_file("res://generated/colormap.png")
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://config/map.json"))
	noise.seed = int(cfg.seed)
	noise.frequency = 0.045
	noise.fractal_octaves = 4
	font = load("res://assets/BasinUI.otf")
	add_child(terrain)
	add_child(infrastructure)
	add_child(labels)
	add_child(selection)
	add_child(overlay)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("c7cfcd")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("d4dfdf")
	e.ambient_light_energy = 0.38
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	# Warm grazing light and cool ambient fill retain relief without shadow-map cost.
	sun.rotation_degrees = Vector3(-43, -33, 0)
	sun.light_color = Color("fff2d9")
	sun.light_energy = 0.82
	sun.shadow_enabled = not bool(cfg.get("low_spec",true))
	sun.directional_shadow_max_distance = 400
	add_child(sun)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = distance
	camera.far = 1000
	add_child(camera)
	camera.current = true
	add_child(lod_camera)
	lod_camera.current = false
	update_camera()
	print("V2_BUILD_TERRAIN")
	make_terrain()
	print("V2_BUILD_DETAILS")
	make_base()
	make_routes()
	make_details()
	make_ui()
	select_site(selected)
	capture = "--capture" in OS.get_cmdline_user_args()
	print("BASIN_TERRAIN3D_V2 READY capture=", capture, " args=", OS.get_cmdline_user_args())
	DirAccess.make_dir_recursive_absolute("res://preview")
	var log_file := FileAccess.open("res://preview/runtime.log",FileAccess.WRITE)
	if log_file:log_file.store_string("TERRAIN3D_V2 READY capture=%s args=%s\n" % [capture,OS.get_cmdline_user_args()])
	if "--self-test" in OS.get_cmdline_user_args():
		run_tests()

func height_at(x: float, z: float) -> float:
	var px := clampf((x+128.0)*4.0,0,1022.99)
	var pz := clampf((z+128.0)*4.0,0,1022.99)
	var ix := int(px); var iz := int(pz)
	var a := lerpf(height_image.get_pixel(ix,iz).r,height_image.get_pixel(ix+1,iz).r,px-ix)
	var b := lerpf(height_image.get_pixel(ix,iz+1).r,height_image.get_pixel(ix+1,iz+1).r,px-ix)
	return lerpf(a,b,pz-iz)

func stream_x(z: float) -> float:
	return -28.0 + z * 0.20 + sin(z * 0.065) * 7.0

func slope_at(x: float,z: float) -> float:
	var dx := (height_at(x+0.5,z)-height_at(x-0.5,z))
	var dz := (height_at(x,z+0.5)-height_at(x,z-0.5))
	return rad_to_deg(atan(sqrt(dx*dx+dz*dz)))

func exclusion(x: float,z: float) -> String:
	if abs(x-stream_x(z)) < 4.0: return "季节性干沟 / 洪水通道"
	if Vector2(x+44,z-34).length() < 12: return "植被保育区"
	if Vector2(x-32,z-38).length() < 13: return "盐碱洼地 / 地基风险"
	return ""

func biome(x: float,z: float) -> String:
	if z < -39: return "低山与残丘"
	if Vector2(x-32,z-38).length() < 14: return "盐碱洼地"
	if abs(x-stream_x(z)) < 3: return "季节性干沟"
	if x > 38 and z > 25: return "局部活动沙丘"
	if z < -12: return "山前冲洪积扇"
	return "缓坡砾石戈壁"

func land_color(x: float,z: float) -> Color:
	var n := noise.get_noise_2d(x*3,z*3)
	var c := Color("a99d83")
	if z < -39: c = Color("827c70")
	elif z < -12: c = Color("a19780")
	if x > 38 and z > 25: c = Color("c8b38b")
	if Vector2(x-32,z-38).length() < 14: c = Color("d1cbbb")
	if abs(x-stream_x(z)) < 2.5: c = Color("7e8172")
	if Vector2(x+44,z-34).length() < 12: c = Color("8d9874")
	if layer == 1: c = Color("8eae91").lerp(Color("bd735b"),clampf(slope_at(x,z)/30,0,1))
	if layer == 2: c = Color("d4cba3").lerp(Color("5e9297"),clampf((height_at(x,z)+4)/25,0,1))
	if layer == 3: c = Color("c7a36a").lerp(Color("e1cf8e"),clampf((z+70)/140,0,1))
	if layer == 4: c = c.darkened(0.08); if abs(x-stream_x(z)) < 4: c = Color("8a9992")
	if layer == 7:
		if exclusion(x,z) != "": c = Color("b77c69")
		elif slope_at(x,z) > float(cfg.max_build_slope_degrees): c = Color("aa9b7d")
		else: c = Color("91aa8d")
	return c.lightened(n*0.12) if n >= 0 else c.darkened(-n*0.12)

func make_terrain():
	if not terrain_initialized:
		terrain.name = "Terrain3D_Basin"
		terrain.vertex_spacing = 0.25
		terrain.region_size = 512
		terrain.mesh_size = 64
		terrain.mesh_lods = 5
		terrain.material.world_background = Terrain3DMaterial.NONE
		terrain.material.auto_shader = false
		if bool(cfg.get("low_spec",true)):
			terrain.material.shader_override = load("res://assets/desert_terrain.gdshader")
			terrain.material.shader_override_enabled = true
		terrain.material.set_shader_param("blend_sharpness",0.30)
		# Reuse the lightweight shader's two existing macro samples, no added passes.
		var desert_surface = preload("res://scripts/desert_surface.gd")
		terrain.material.set_shader_param("noise_texture",desert_surface.macro_texture(int(cfg.seed)))
		terrain.material.set_shader_param("macro_variation1",Color(0.93,0.90,0.85))
		terrain.material.set_shader_param("macro_variation2",Color(0.90,0.93,0.95))
		terrain.material.set_shader_param("noise1_scale",0.09)
		terrain.material.set_shader_param("noise2_scale",0.24)
		terrain.material.set_shader_param("noise1_angle",0.32)
		terrain.assets = Terrain3DAssets.new()
		var names := ["gravel", "bedrock", "sand", "salt"]
		for i in range(4):
			var ta := Terrain3DTextureAsset.new()
			ta.name = names[i]
			var alb: Image = Image.load_from_file("res://generated/%s_albedo.png" % names[i])
			var nrm: Image = Image.load_from_file("res://generated/%s_normal.png" % names[i])
			alb.generate_mipmaps(); nrm.generate_mipmaps()
			ta.albedo_texture = ImageTexture.create_from_image(alb)
			ta.normal_texture = ImageTexture.create_from_image(nrm)
			ta.uv_scale = [0.62,0.34,0.44,0.48][i]
			ta.normal_depth = [0.72,0.90,0.54,0.38][i]
			ta.roughness = 0.04
			terrain.assets.set_texture(i,ta)
		terrain.set_camera(lod_camera)
		terrain_initialized = true
	var col := base_color_image.duplicate()
	if layer in [1,2,3,7]:
		col = Image.create_empty(256,256,false,Image.FORMAT_RGBA8)
		for iz in range(256):
			for ix in range(256):
				var x := -128.0+ix
				var z := -128.0+iz
				var c := Color.WHITE
				if layer == 1: c = Color("87bb99").lerp(Color("e08064"),clampf(slope_at(x,z)/30,0,1))
				if layer == 2: c = Color("e5d5a0").lerp(Color("6da6c4"),clampf(height_at(x,z)/20,0,1))
				if layer == 3: c = Color("ddb173").lerp(Color("efe0a7"),clampf((z+70)/140,0,1))
				if layer == 7:
					c = Color("82bf9a")
					if exclusion(x,z) != "": c = Color("f18b72")
					elif slope_at(x,z) > float(cfg.max_build_slope_degrees): c = Color("d8bd87")
				c.a = 0.85
				col.set_pixel(ix,iz,c)
		col.resize(1024,1024,Image.INTERPOLATE_BILINEAR)
	terrain.data.import_images([height_image,control_image,col],Vector3(-128,0,-128),0.0,1.0)

func material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m

func box(parent: Node3D, p: Vector3, size: Vector3,c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material(c)
	mi.position = p
	parent.add_child(mi)
	return mi

func make_base():
	box(self,Vector3(0,-4,0),Vector3(201,7,141),Color("6b716b"))
	box(self,Vector3(0,-8,0),Vector3(204,1,144),Color("424e4b"))
	var edge := SurfaceTool.new(); edge.begin(Mesh.PRIMITIVE_TRIANGLES)
	var boundary: Array[Vector2] = []
	for x in range(-100,101): boundary.append(Vector2(x,-70))
	for z in range(-69,71): boundary.append(Vector2(100,z))
	for x in range(99,-101,-1): boundary.append(Vector2(x,70))
	for z in range(69,-71,-1): boundary.append(Vector2(-100,z))
	for i in range(boundary.size()-1):
		var a := boundary[i]; var b := boundary[i+1]
		var verts := [Vector3(a.x,height_at(a.x,a.y),a.y),Vector3(b.x,height_at(b.x,b.y),b.y),Vector3(a.x,-0.5,a.y),Vector3(b.x,-0.5,b.y)]
		for idx in [0,1,2,1,3,2]: edge.add_vertex(verts[idx])
	edge.generate_normals()
	var skirt := MeshInstance3D.new(); skirt.mesh = edge.commit()
	var sm := material(Color("90816a")); sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	skirt.material_override = sm; add_child(skirt)


func line(parent: Node3D,points: Array,width: float,c: Color,offset: float=0.25):
	for i in range(points.size()-1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i+1]
		var steps := maxi(1,int(a.distance_to(b)/2))
		for k in range(steps):
			var u := a.lerp(b,float(k)/steps)
			var v := a.lerp(b,float(k+1)/steps)
			var pa := Vector3(u.x,height_at(u.x,u.y)+offset,u.y)
			var pb := Vector3(v.x,height_at(v.x,v.y)+offset,v.y)
			var seg := box(parent,(pa+pb)*0.5,Vector3(width,0.14,pa.distance_to(pb)),c)
			seg.look_at_from_position((pa+pb)*0.5,pb,Vector3.UP)

func marker(p: Vector2,title: String,c: Color):
	var h := height_at(p.x,p.y)
	# Geographic labels and external service pins are not constructed buildings.
	var geographic:bool=title in ["北西低山","局部沙丘","盐碱洼地","植被保育区"]
	if not geographic:
		var pin:=MeshInstance3D.new();var ring:=TorusMesh.new()
		ring.inner_radius=0.65;ring.outer_radius=0.85;ring.rings=20;ring.ring_segments=4
		pin.mesh=ring;pin.material_override=material(c);pin.position=Vector3(p.x,h+0.2,p.y)
		pin.name="ExternalServicePin";pin.set_meta("display_only",true);infrastructure.add_child(pin)
	var lbl := Label3D.new()
	lbl.text = title if geographic or title.begins_with("电网") else title+"（场地示意）"
	lbl.font = font
	lbl.font_size = 40
	lbl.pixel_size = 0.025
	lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	lbl.no_depth_test = false
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color("f8f3e5")
	lbl.outline_modulate = Color("344440")
	lbl.outline_size = 5
	lbl.position = Vector3(p.x,h+7,p.y)
	labels.add_child(lbl)

func make_routes():
	line(infrastructure,[Vector2(-100,13),Vector2(-78,13),Vector2(-48,5),Vector2(16,5),Vector2(66,3),Vector2(100,3)],1.5,Color("676c64"))
	line(infrastructure,[Vector2(-100,18),Vector2(-76,18),Vector2(-59,9)],0.75,Color("424e49"))
	for i in range(40):
		box(infrastructure,Vector3(-99+i,height_at(-99+i,18)+0.25,18),Vector3(0.25,0.2,1.5),Color("585b52"))
	line(infrastructure,[Vector2(-100,42),Vector2(-76,42),Vector2(-65,22)],0.65,Color("637f91"))
	line(infrastructure,[Vector2(-100,-5),Vector2(-82,-5),Vector2(-68,1)],0.55,Color("af9270"))
	marker(Vector2(-85,13),"公铁物流 / 煤源",Color("8b8272"))
	marker(Vector2(-80,-5),"天然气接口",Color("b59c73"))
	marker(Vector2(-76,42),"外引水 / 限额",Color("7b9ba5"))
	marker(Vector2(87,3),"电网送出 · %s MW" % int(cfg.grid_export_mw),Color("9d8070"))
	for x in [68,80,94]:
		var h := height_at(x,3)
		box(infrastructure,Vector3(x,h+4,3),Vector3(0.6,8,0.6),Color("5d6862"))
		box(infrastructure,Vector3(x,h+7,3),Vector3(4,0.3,0.4),Color("5d6862"))
	line(infrastructure,[Vector2(68,3),Vector2(100,3)],0.13,Color("53625c"),7)
	marker(Vector2(-68,-43),"北西低山",Color("8f8978"))
	marker(Vector2(61,48),"局部沙丘",Color("bca883"))
	marker(Vector2(31,39),"盐碱洼地",Color("d0c9b6"))
	marker(Vector2(-46,34),"植被保育区",Color("7f906f"))

func make_details():
	var surface = preload("res://scripts/desert_surface.gd")
	var rng := RandomNumberGenerator.new(); rng.seed = int(cfg.seed)
	var scatter := FastNoiseLite.new(); scatter.seed = int(cfg.seed) + 47
	scatter.frequency = 0.11; scatter.fractal_octaves = 2
	var rocks := MultiMesh.new(); rocks.transform_format = MultiMesh.TRANSFORM_3D; rocks.use_colors = true
	rocks.mesh = surface.rock_mesh(); rocks.instance_count = 1580
	for i in range(rocks.instance_count):
		var x := rng.randf_range(-98,98); var z := rng.randf_range(-68,68)
		# Broken concentrations, with quiet gaps, instead of even screen-wide pepper.
		for attempt in range(5):
			if scatter.get_noise_2d(x,z) + rng.randf_range(-0.35,0.35) > -0.08: break
			x = rng.randf_range(-98,98); z = rng.randf_range(-68,68)
		var sc := rng.randf_range(0.13,0.40)
		if i < 130:
			x = rng.randf_range(-94,-25); z = rng.randf_range(-58,-18)
			sc = rng.randf_range(0.55,1.25)
		# Sand and salt stay visually quiet. This changes decoration only.
		if (x > 40 and z > 28) or Vector2(x-32,z-38).length() < 13.0:
			sc *= 0.34
		var ground_normal := Vector3(height_at(x-0.5,z)-height_at(x+0.5,z),1.0,height_at(x,z-0.5)-height_at(x,z+0.5)).normalized()
		var basis := Basis(Quaternion(Vector3.UP,ground_normal)) * Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(sc,sc*rng.randf_range(0.60,1.00),sc*rng.randf_range(0.80,1.45)))
		rocks.set_instance_transform(i,Transform3D(basis,Vector3(x,height_at(x,z),z)))
		var tint := Color("8d897d").lerp(Color("b4a48b"),rng.randf())
		rocks.set_instance_color(i,tint)
	var ri := MultiMeshInstance3D.new(); ri.name = "Gravel_and_weathered_rocks"; ri.multimesh = rocks
	ri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(ri)
	var shrubs := MultiMesh.new(); shrubs.transform_format = MultiMesh.TRANSFORM_3D; shrubs.use_colors = true
	shrubs.mesh = surface.shrub_mesh(); shrubs.instance_count = 232
	for i in range(shrubs.instance_count):
		var z := rng.randf_range(-15,65)
		var bank := -1.0 if rng.randf() < 0.5 else 1.0
		var x := stream_x(z) + bank * rng.randf_range(1.5,4.8)
		if i > 145:
			var angle := rng.randf() * TAU
			var radius := sqrt(rng.randf()) * 10.2
			x = -44.0 + cos(angle) * radius; z = 34.0 + sin(angle) * radius * 0.78
		var sc := rng.randf_range(0.48,1.15)
		var basis := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(sc,sc*rng.randf_range(0.70,1.15),sc*rng.randf_range(0.80,1.25)))
		shrubs.set_instance_transform(i,Transform3D(basis,Vector3(x,height_at(x,z)+0.025,z)))
		var tint := Color("727c62").lerp(Color("9b9a78"),rng.randf())
		shrubs.set_instance_color(i,tint)
	var si := MultiMeshInstance3D.new(); si.name = "Sparse_desert_shrubs"; si.multimesh = shrubs
	si.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(si)
	# Retain light planning parcels without prebuilding a power station.
	for x in range(-8,60,8): line(infrastructure,[Vector2(x,13),Vector2(x,35)],0.045,Color("b8ad92"))
	for z in range(13,36,8): line(infrastructure,[Vector2(-8,z),Vector2(56,z)],0.045,Color("b8ad92"))

func panel_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.corner_radius_top_left = 12; s.corner_radius_top_right = 12
	s.corner_radius_bottom_left = 12; s.corner_radius_bottom_right = 12
	s.content_margin_left = 20; s.content_margin_right = 20
	s.content_margin_top = 16; s.content_margin_bottom = 16
	return s

func text_label(t: String,size: int=18,c: Color=Color("e9eddf")) -> Label:
	var l := Label.new()
	l.text = t; l.add_theme_font_override("font",font)
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",c)
	return l

func make_ui():
	var canvas := CanvasLayer.new(); add_child(canvas)
	var root := Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE; canvas.add_child(root)
	var header := PanelContainer.new(); header.position = Vector2(24,20); header.size = Vector2(1552,82)
	header.add_theme_stylebox_override("panel",panel_style(Color("263a36"))); root.add_child(header)
	var hv := VBoxContainer.new(); header.add_child(hv)
	hv.add_child(text_label("荒原   /   BASIN 02",30))
	hv.add_child(text_label("Terrain3D 1.0.2  ·  合成地形 / 资源示意 / 非真实 GIS",16,Color("b8c5b2")))
	var lp := PanelContainer.new(); lp.position = Vector2(24,126); lp.custom_minimum_size = Vector2(182,0); root.add_child(lp)
	lp.add_theme_stylebox_override("panel",panel_style(Color("2b3d37")))
	var lv := VBoxContainer.new(); lv.add_theme_constant_override("separation",4); lp.add_child(lv)
	lv.add_child(text_label("地图图层",20))
	var group := ButtonGroup.new()
	for i in range(8):
		var b := Button.new(); b.text = "%02d   %s" % [i+1,layer_names[i]]; b.toggle_mode = true; b.button_group = group; b.button_pressed = i == 0
		b.custom_minimum_size = Vector2(142,32); b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font",font); b.add_theme_font_size_override("font_size",17)
		b.add_theme_stylebox_override("normal",panel_style(Color("354b41")))
		b.add_theme_stylebox_override("pressed",panel_style(Color("677d63")))
		b.pressed.connect(change_layer.bind(i)); lv.add_child(b); layer_buttons.append(b)
	var cb := CheckButton.new(); cb.text = "显示地名 / 接口"; cb.button_pressed = true; cb.add_theme_font_override("font",font); cb.toggled.connect(func(v): labels.visible = v); lv.add_child(cb)
	lv.add_child(text_label("视角  F1 / F2 / F3",16))
	var views := HBoxContainer.new(); lv.add_child(views)
	for i in range(3):
		var vb := Button.new(); vb.text = ["俯视","2.5D","透视"][i]
		vb.add_theme_font_override("font",font); vb.custom_minimum_size = Vector2(60,36)
		vb.pressed.connect(set_view.bind(i)); views.add_child(vb)
	var reset := Button.new(); reset.text = "重置视角  [R]"; reset.add_theme_font_override("font",font); reset.pressed.connect(reset_camera); lv.add_child(reset)
	var rp := PanelContainer.new(); rp.position = Vector2(1310,126); rp.custom_minimum_size = Vector2(266,0); root.add_child(rp)
	rp.add_theme_stylebox_override("panel",panel_style(Color("293c36")))
	var rv := VBoxContainer.new(); rv.add_theme_constant_override("separation",14); rp.add_child(rv)
	rv.add_child(text_label("地块勘察",22))
	detail = text_label("",14); rv.add_child(detail)
	rv.add_child(text_label("外部供给 / 设计占位",18,Color("d0c6a6")))
	rv.add_child(text_label("水  %s m³ / 日（上限）\n煤  %s t / 日\n气  %s m³ / 时\n送出  %s MW" % [int(cfg.water_supply_m3_day),int(cfg.coal_capacity_t_day),int(cfg.gas_capacity_m3_hour),int(cfg.grid_export_mw)],16))
	rv.add_child(text_label("无天然矿井 / 气田假设\n干沟 ≠ 稳定水源\n未建设任何发电设备",14,Color("b6c1ac")))
	var bottom := PanelContainer.new(); bottom.position = Vector2(24,914); bottom.size = Vector2(1552,66); root.add_child(bottom)
	bottom.add_theme_stylebox_override("panel",panel_style(Color("293b35")))
	var bv := VBoxContainer.new(); bottom.add_child(bv)
	layer_hint = text_label(descriptions[0],18); bv.add_child(layer_hint)
	bv.add_child(text_label("左键勘察地块     右键拖动旋转     中键拖动平移     滚轮缩放     WASD 移动     R 重置     1–8 图层",14,Color("b5c1af")))

func change_layer(i: int):
	layer = i
	make_terrain()
	layer_hint.text = descriptions[i]
	layer_buttons[i].button_pressed = true
	for child in overlay.get_children(): child.queue_free()
	if i == 4:
		line(overlay,[Vector2(-100,42),Vector2(-76,42),Vector2(-65,22)],1.4,Color("93c6df"),0.7)
	if i == 5:
		line(overlay,[Vector2(-100,13),Vector2(-78,13),Vector2(-48,5),Vector2(16,5),Vector2(66,3),Vector2(100,3)],2,Color("dfbd86"),0.7)
		line(overlay,[Vector2(-100,-5),Vector2(-82,-5),Vector2(-68,1)],1.2,Color("e1a778"),0.7)
	if i == 6:
		line(overlay,[Vector2(68,3),Vector2(100,3)],1,Color("e7d7a2"),7.3)
	if i == 2:
		for x in range(-65,80,25):
			for z in range(-20,60,25):
				line(overlay,[Vector2(x,z),Vector2(x+6,z+4),Vector2(x+3,z+4)],0.35,Color("e4ead3"),1.2)

func select_site(p: Vector2):
	selected = p
	for child in selection.get_children(): child.queue_free()
	var s := slope_at(p.x,p.y)
	var reason := exclusion(p.x,p.y)
	var ok := reason == "" and s <= float(cfg.max_build_slope_degrees)
	var c := Color("b8dba4") if ok else Color("df9476")
	var r := 3.0
	line(selection,[p+Vector2(-r,-r),p+Vector2(r,-r),p+Vector2(r,r),p+Vector2(-r,r),p+Vector2(-r,-r)],0.3,c,0.5)
	var condition := "可建 · 初步筛选通过" if ok else "禁建 / 不适宜"
	if reason == "" and not ok: reason = "超过 %s° 示意坡度阈值" % cfg.max_build_slope_degrees
	if ok: reason = "仍需地基 / 供水专项勘察"
	var wind := 5.8+height_at(p.x,p.y)*0.055
	detail.text = "坐标  %.1f, %.1f km\n地貌  %s\n相对高程  %.0f m\n坡度  %.1f°\n\n%s\n%s\n\n平均风速  %.1f m/s*\n太阳资源  佳*\n距送出点  %.1f km\n\n* 合成资源，非实测" % [p.x*float(cfg.meters_per_unit)/1000,p.y*float(cfg.meters_per_unit)/1000,biome(p.x,p.y),height_at(p.x,p.y)*float(cfg.meters_per_unit),s,condition,reason,wind,p.distance_to(Vector2(87,3))*float(cfg.meters_per_unit)/1000]

func set_view(mode: int):
	target = Vector3.ZERO
	distance = 235
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE if mode == 2 else Camera3D.PROJECTION_ORTHOGONAL
	camera.fov = 45
	if mode == 0: yaw = 0; pitch = 1.56
	elif mode == 1: yaw = -PI/4; pitch = atan(1/sqrt(2.0))
	else: yaw = -0.22; pitch = 0.78
	update_camera()

func reset_camera():
	yaw = -0.22; pitch = 0.78; distance = 235; target = Vector3.ZERO; camera.projection = Camera3D.PROJECTION_ORTHOGONAL; update_camera()

func update_camera():
	# Camera constraints are display-only. Close inspection uses the real metric
	# mesh and never rescales equipment, changes placement or advances the model.
	distance = clampf(distance, MIN_CAMERA_DISTANCE, MAX_CAMERA_DISTANCE) if is_finite(distance) else 235.0
	yaw = wrapf(yaw, -PI, PI) if is_finite(yaw) else -0.22
	pitch = clampf(pitch, MIN_CAMERA_PITCH, MAX_CAMERA_PITCH) if is_finite(pitch) else 0.78
	if not target.is_finite(): target = Vector3.ZERO
	target.x = clampf(target.x, -100.0, 100.0)
	target.z = clampf(target.z, -70.0, 70.0)
	var ground := height_at(target.x, target.z)
	target.y = clampf(target.y, ground + 0.05, ground + 32.0)
	camera.size = distance
	camera.position = target + Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*(distance*1.25 if camera.projection == Camera3D.PROJECTION_PERSPECTIVE else 250.0)
	if absf(camera.position.x) <= 128.0 and absf(camera.position.z) <= 128.0:
		camera.position.y = maxf(camera.position.y, height_at(camera.position.x, camera.position.z) + CAMERA_GROUND_CLEARANCE)
	camera.look_at(target)
	lod_camera.position = target + Vector3(0,20,0)

func pick_ground(pos: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	var prev := origin
	for i in range(1200):
		var p := origin+dir*i*0.5
		if p.x >= -100 and p.x <= 100 and p.z >= -70 and p.z <= 70 and p.y <= height_at(p.x,p.z):
			for j in range(10):
				var mid := (prev+p)*0.5
				if mid.y > height_at(mid.x,mid.z): prev = mid
				else: p = mid
			return Vector2(p.x,p.z)
		prev = p
	return Vector2(INF,INF)

func pan_camera(screen_delta: Vector2) -> void:
	# Use the same screen-space pan for left and middle drags at every zoom.
	var view_height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var span := camera.size
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		span = 2.0 * camera.position.distance_to(target) * tan(deg_to_rad(camera.fov * 0.5))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	target += (-right * screen_delta.x - forward * screen_delta.y) * span / view_height
	update_camera()

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(MIN_CAMERA_DISTANCE,distance*0.91); update_camera()
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(MAX_CAMERA_DISTANCE,distance*1.1); update_camera()
		if event.button_index == MOUSE_BUTTON_LEFT:
			var p := pick_ground(event.position)
			if is_finite(p.x): select_site(p)
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= event.relative.x*0.006; pitch = clampf(pitch+event.relative.y*0.004,MIN_CAMERA_PITCH,MAX_CAMERA_PITCH); update_camera()
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			pan_camera(event.relative)
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R: reset_camera()
		if event.keycode == KEY_F1: set_view(0)
		if event.keycode == KEY_F2: set_view(1)
		if event.keycode == KEY_F3: set_view(2)
		if event.keycode >= KEY_1 and event.keycode <= KEY_8: change_layer(event.keycode-KEY_1)

func _process(delta):
	var now := Time.get_ticks_usec()
	if run_started == 0: run_started = now
	if previous_tick > 0 and frame > 10: frame_times.append((now-previous_tick)/1000.0)
	previous_tick = now
	var move := Vector3.ZERO
	if not camera_keyboard_blocked():
		if Input.is_physical_key_pressed(KEY_W): move.z -= 1
		if Input.is_physical_key_pressed(KEY_S): move.z += 1
		if Input.is_physical_key_pressed(KEY_A): move.x -= 1
		if Input.is_physical_key_pressed(KEY_D): move.x += 1
	if move.length() > 0:
		target += move.rotated(Vector3.UP,yaw)*delta*distance*0.3; update_camera()
	frame += 1
	if capture and frame == 30:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://preview/01-terrain.png")
		print("CAPTURE_SAVED terrain")
	if capture and frame == 35: change_layer(7); select_site(Vector2(-44,34))
	if capture and frame == 55:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://preview/02-ecology.png")
		print("CAPTURE_SAVED ecology")
	if capture and frame == 60: change_layer(1); select_site(Vector2(3,-55))
	if capture and frame == 80:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://preview/03-slope.png")
		print("CAPTURE_SAVED slope")
	if capture and frame == 85: change_layer(0); set_view(0); select_site(Vector2(0,15))
	if capture and frame == 105:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://preview/04-overhead.png")
		print("CAPTURE_SAVED overhead")
	if capture and frame == 110: set_view(1)
	if capture and frame == 130:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://preview/05-isometric.png")
		print("CAPTURE_SAVED isometric")
	if capture and frame == 135: set_view(2)
	if capture and frame == 155:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://preview/06-perspective.png")
		print("CAPTURE_SAVED perspective")
	if capture and frame == 160:
		write_performance()
		get_tree().quit()

func camera_keyboard_blocked() -> bool:
	# Text in the nonmodal side dock must not double as a WASD navigation input.
	var focus := get_viewport().gui_get_focus_owner()
	while is_instance_valid(focus):
		if focus is LineEdit or focus is TextEdit or focus is SpinBox:
			return true
		focus = focus.get_parent() as Control
	return false

func run_tests():
	assert(exclusion(-44,34) != "")
	assert(exclusion(stream_x(0),0) != "")
	assert(exclusion(32,38) != "")
	assert(exclusion(0,15) == "")
	assert(slope_at(0,15) < float(cfg.max_build_slope_degrees))
	assert(height_at(-70,-42) > height_at(0,15))
	for i in range(8):
		change_layer(i)
		assert(terrain.data.get_region_count() == 4)
	select_site(Vector2(-44,34)); assert("禁建" in detail.text)
	select_site(Vector2(0,15)); assert("可建" in detail.text)
	reset_camera()
	var p := pick_ground(camera.unproject_position(Vector3(0,height_at(0,15),15)))
	assert(p.distance_to(Vector2(0,15)) < 0.1)
	for mode in range(3):
		set_view(mode)
		var hit := pick_ground(camera.unproject_position(Vector3(0,height_at(0,15),15)))
		assert(hit.distance_to(Vector2(0,15)) < 0.1)
	assert(camera.projection == Camera3D.PROJECTION_PERSPECTIVE)
	var old_distance := camera.position.distance_to(target)
	distance *= 0.9; update_camera()
	assert(camera.position.distance_to(target) < old_distance)
	reset_camera()
	change_layer(0)
	print("SELF_TEST_PASS: terrain, 8 overlays, exclusions, slope, selection, ray picking, 3 camera presets, perspective zoom")
	if not capture: get_tree().quit()

func write_performance():
	if frame_times.is_empty(): return
	var samples := frame_times.duplicate(); samples.sort()
	var sum_ms := 0.0
	for ms in samples: sum_ms += ms
	var result := {"sample_frames":samples.size(),"mean_fps":1000.0/(sum_ms/samples.size()),"median_frame_ms":samples[samples.size()/2],"p95_frame_ms":samples[int(samples.size()*0.95)],"max_frame_ms":samples[-1],"elapsed_seconds":(Time.get_ticks_usec()-run_started)/1000000.0,"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"low_spec":cfg.get("low_spec",true),"note":"Capture run includes overlay rebuilds and image writes; not a steady-state benchmark."}
	var f := FileAccess.open("res://preview/performance.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(result,"  "))
	print("PERFORMANCE ",JSON.stringify(result))
