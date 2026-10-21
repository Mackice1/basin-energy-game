extends SceneTree
const Fixture=preload("res://tests/test_compact_build_bulk_ui_1003.gd")
const KINDS=["battery","battery_sodium","battery_flow","caes_aboveground","liquid_air_store","hydrogen_storage_system","solid_thermal_store","molten_salt_store"]
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures.append(note);push_error("STORAGE_ICON_FAIL "+note)
func _initialize():call_deferred("run")
func luminance(color:Color)->float:
	var linear:=color.srgb_to_linear();return 0.2126*linear.r+0.7152*linear.g+0.0722*linear.b
func run():
	var game=Fixture.UIController.new();root.add_child(game)
	for i in 4:await process_frame
	var contact:=Image.create(8*96,4*96,false,Image.FORMAT_RGBA8);contact.fill(Color("344956"))
	for row in 4:
		var size:int=[24,32,40,48][row]
		var hashes:Array[int]=[]
		for col in KINDS.size():
			var kind:String=KINDS[col]
			var texture:Texture2D=game.icon_texture(kind);var icon:Image=texture.get_image()
			check(icon.get_size()==Vector2i(64,64),"source icon size "+kind)
			icon.resize(size,size,Image.INTERPOLATE_LANCZOS)
			var fingerprint:int=hash(icon.get_data());check(not hashes.has(fingerprint),"unique silhouette at %dpx %s"%[size,kind]);hashes.append(fingerprint)
			var opaque:=0;var contrast_sum:=0.0;var weighted_alpha:=0.0
			for y in size:
				for x in size:
					var pixel:=icon.get_pixel(x,y)
					if pixel.a>0.8:
						opaque+=1
						var ratio:float=(luminance(pixel)+0.05)/(luminance(Color("344956"))+0.05)
						contrast_sum+=ratio
					weighted_alpha+=pixel.a
			check(opaque>=12,"readable solid stroke pixels %dpx %s"%[size,kind])
			check(contrast_sum/maxi(opaque,1)>=5.0,"bright stroke contrast %dpx %s"%[size,kind])
			check(weighted_alpha/(size*size)>=0.10,"small icon silhouette coverage %dpx %s"%[size,kind])
			contact.blend_rect(icon,Rect2i(Vector2i.ZERO,icon.get_size()),Vector2i(col*96+(96-size)/2,row*96+(96-size)/2))
	contact.save_png("res://evidence/storage_1003/storage_icon_sizes_contact.png")
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables"]:
		var node=game.get(key)
		if is_instance_valid(node) and node.get_parent()==null:node.free()
	game.free();await process_frame
	print("STORAGE_BUILD_ICONS_1003 checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
