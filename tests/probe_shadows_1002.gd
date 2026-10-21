extends SceneTree
const Inspector = preload("res://scripts/device_inspector.gd")
const TestHost = preload("res://tests/test_device_inspector_v23.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
func _initialize():call_deferred("run")
func shot(i, label):
 for k in 5:await process_frame
 await RenderingServer.frame_post_draw
 i.viewport.get_texture().get_image().save_png("res://evidence/detail_1002/shadow_probe_"+label+".png")
func run():
 root.size=Vector2i(1440,900);root.gui_embed_subwindows=true
 var host=TestHost.Host.new();root.add_child(host)
 host.devices=[{"id":0,"kind":"station","params":Catalog.defaults("station"),"state":{}}]
 var i=Inspector.new();host.add_child(i);i.setup(host);i.open_device(0)
 i.studio_light.shadow_bias=0.05;i.studio_light.shadow_normal_bias=0.5
 await shot(i,"baseline")
 i.studio_light.shadow_enabled=false
 await shot(i,"off")
 i.studio_light.shadow_enabled=true
 i.studio_light.shadow_bias=0.15;i.studio_light.shadow_normal_bias=1.0
 await shot(i,"bias15")
 i.studio_light.shadow_bias=0.4;i.studio_light.shadow_normal_bias=2.0
 await shot(i,"bias40")
 i.studio_light.shadow_bias=0.15;i.studio_light.shadow_normal_bias=1.0
 i.studio_light.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
 i.studio_light.directional_shadow_max_distance=i.camera_distance+i.model_radius*2
 await shot(i,"splits")
 print("SHADOW_PROBE_COMPLETE")
 quit()
