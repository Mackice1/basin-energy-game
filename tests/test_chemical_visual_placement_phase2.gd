extends SceneTree
const World=preload("res://scripts/world_game.gd")
const Catalog=preload("res://scripts/device_catalog.gd")
func _initialize():call_deferred("run")
func run():
 var w:=World.new()
 w.height_image=Image.create_from_data(1024,1024,false,Image.FORMAT_RF,FileAccess.get_file_as_bytes("res://generated/height.raw"))
 w.cfg=JSON.parse_string(FileAccess.get_file_as_string("res://config/map.json"));w.noise.seed=int(w.cfg.seed);w.noise.frequency=.045;w.noise.fractal_octaves=4
 w.dimension_profile="metric_v1";w.devices=[];w.stations=[]
 var failures:=0
 for kind in ["nitrogen_supply_boundary","co2_supply_boundary","ammonia_synthesis_station","methanol_synthesis_station"]:
  var found:=false;var legal:=Vector2.ZERO
  for x in range(-40,41,5):
   for z in range(-40,41,5):
    if w.can_place(kind,Vector2(x,z)).is_empty():legal=Vector2(x,z);found=true;break
   if found:break
  if not found:failures+=1
  if w.can_place(kind,w.WorldDomain.HALF_EXTENTS+Vector2.ONE).is_empty():failures+=1
  print("CHEMICAL_ACTUAL_TERRAIN ",kind," legal=",found," center=",legal)
 var orphans:Array[Node]=[]
 for property in w.get_property_list():
  if not (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):continue
  var value:Variant=w.get(property.name)
  if value is Node and value!=w and not value.is_inside_tree() and not value.get_parent():orphans.append(value)
 w.free()
 for n in orphans:
  if is_instance_valid(n):n.free()
 print("CHEMICAL_PLACEMENT failures=",failures)
 quit(0 if failures==0 else 1)
