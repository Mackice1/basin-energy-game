extends SceneTree
const Domain=preload("res://scripts/map_domain.gd")
const Env=preload("res://scripts/environment_visual.gd")
const Spatial=preload("res://scripts/spatial_dimensions.gd")
class Ground extends "res://scripts/map.gd":
 func _ready():
  height_image=Image.create_from_data(1024,1024,false,Image.FORMAT_RF,FileAccess.get_file_as_bytes("res://generated/height.raw"))
  cfg=JSON.parse_string(FileAccess.get_file_as_string("res://config/map.json"))
  noise.seed=int(cfg.seed);noise.frequency=.045;noise.fractal_octaves=4
  add_child(camera);add_child(lod_camera);camera.current=true;camera.far=2000;set_process(false)
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,msg:String):
 checks+=1
 if not ok:failures.append(msg);push_error(msg)
func original(map:Ground,x:float,z:float)->float:
 var px:=clampf((x+128.0)*4.0,0,1022.99);var pz:=clampf((z+128.0)*4.0,0,1022.99)
 var ix:=int(px);var iz:=int(pz)
 var a:=lerpf(map.height_image.get_pixel(ix,iz).r,map.height_image.get_pixel(ix+1,iz).r,px-ix)
 var b:=lerpf(map.height_image.get_pixel(ix,iz+1).r,map.height_image.get_pixel(ix+1,iz+1).r,px-ix)
 return lerpf(a,b,pz-iz)
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1440,900)
 var map:=Ground.new();root.add_child(map)
 check(Domain.METERS_PER_UNIT*Spatial.WORLD_UNITS_PER_METER==1.0,"Map and equipment share one metre")
 check(map.cfg.meters_per_unit==10 and Vector2(map.cfg.world_size[0],map.cfg.world_size[1])==Domain.WORLD_SIZE,"Config represents 4 x 4 km at 10m/world")
 check(Domain.WORLD_SIZE*Domain.METERS_PER_UNIT==Vector2(4000,4000),"Real 4km square")
 check(Domain.BUILD_GRID_WORLD*Domain.METERS_PER_UNIT==10.0 and Domain.MAJOR_GRID_WORLD*Domain.METERS_PER_UNIT==100.0,"10m snap and 100m survey spacing")
 for p in [Vector2(200,200),Vector2(-200,-200),Vector2(200,0),Vector2(0,-200)]:check(Domain.contains(p),"Inclusive domain boundary")
 for p in [Vector2(200.01,0),Vector2(0,-200.01),Vector2(INF,0)]:check(not Domain.contains(p),"Outside build domain rejects")
 check(Domain.contains(Vector2(190,0),10) and not Domain.contains(Vector2(190.01,0),10),"Whole footprint required inside boundary")
 var max_core_error:=0.0;var max_slope_error:=0.0
 for x in range(-100,101):
  for z in range(-70,71):
   max_core_error=maxf(max_core_error,absf(map.height_at(x,z)-original(map,x,z)))
   if x%10==0 or z%10==0:
    var dx:=original(map,x+.5,z)-original(map,x-.5,z)
    var dz:=original(map,x,z+.5)-original(map,x,z-.5)
    max_slope_error=maxf(max_slope_error,absf(map.slope_at(x,z)-rad_to_deg(atan(sqrt(dx*dx+dz*dz)))))
 check(max_core_error==0.0,"Every integer core height is bit-exact old interpolation")
 check(max_slope_error==0.0,"Core and edge slope stencils remain bit-exact")
 var rng:=RandomNumberGenerator.new();rng.seed=8234
 for i in 2000:
  var x:=rng.randf_range(-100,100);var z:=rng.randf_range(-70,70)
  check(map.height_at(x,z)==original(map,x,z),"Fractional core samples unchanged")
 for p in [Vector2(100,20),Vector2(-100,-22),Vector2(33,70),Vector2(-66,-70),Vector2(100,70)]:
  check(map.height_at(p.x,p.y)==original(map,p.x,p.y),"Original seam unchanged")
 var max_outer_slope:=0.0;var max_slope_location:=Vector2.ZERO;var buildable_samples:=0;var outer_samples:=0
 for x in range(-195,196,5):
  for z in range(-195,196,5):
   if Domain.in_core(Vector2(x,z)):continue
   check(is_finite(map.height_at(x,z)),"Finite outer ground")
   outer_samples+=1
   if map.slope_at(x,z)<=8.0:buildable_samples+=1
   if map.slope_at(x,z)>max_outer_slope:max_outer_slope=map.slope_at(x,z);max_slope_location=Vector2(x,z)
 print("OUTER_SLOPE ",max_outer_slope," at ",max_slope_location," buildable ",buildable_samples," / ",outer_samples)
 check(float(buildable_samples)/outer_samples>.98,"Most outer extension buildable; original seam slopes are never flattened")
 var started:=Time.get_ticks_usec();var ext:=Env.build_constructible_extension(map);var build_usec:=Time.get_ticks_usec()-started
 check(ext.get_meta("buildable") and not ext.get_meta("changes_core_height_field"),"Constructible extension, unchanged core")
 check(ext.get_meta("triangles")<120000,"Bounded new ground triangle budget")
 check(ext.get_meta("core_seam_vertices")==2720,"Exact quarter-world perimeter seam")
 var mesh:Mesh=ext.get_child(0).mesh;var verts:PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
 var max_display_error:=0.0;var max_error_center:=Vector3.ZERO;var area:=0.0
 for i in range(0,verts.size(),3):
  var a:Vector3=verts[i];var b:Vector3=verts[i+1];var c:Vector3=verts[i+2]
  var center:Vector3=(a+b+c)/3.0
  check(not (absf(center.x)<99.999 and absf(center.z)<69.999),"Outer ground never covers original core")
  if absf(center.y-map.height_at(center.x,center.z))>max_display_error:
   max_display_error=absf(center.y-map.height_at(center.x,center.z));max_error_center=center
  area+=absf((b-a).cross(c-a).y)*.5
 check(absf(area-(400*400-200*140))<1.0,"Full annulus coverage with no overlaps or voids")
 print("SURFACE_ERROR_POINT ",max_error_center)
 check(max_display_error<.05,"Rendered low-poly surface agrees with analytic ground within 0.5m")
 for n in ext.find_children("*","CollisionObject3D",true,false):check(false,"No redundant physics collider")
 var bg:=Env.build_surround(map)
 check(bg.get_meta("inner_half_extents")==Domain.HALF_EXTENTS and not bg.get_meta("buildable"),"Decorative horizon starts outside real domain")
 for projection in [Camera3D.PROJECTION_ORTHOGONAL,Camera3D.PROJECTION_PERSPECTIVE]:
  map.camera.projection=projection;map.camera.fov=45
  for p in [Vector2(0,15),Vector2(150,100),Vector2(-160,-110),Vector2(195,195),Vector2(-195,195)]:
   map.target=Vector3(p.x,map.height_at(p.x,p.y),p.y);map.distance=60;map.pitch=.8;map.yaw=.25;map.update_camera()
   var screen:=map.camera.unproject_position(Vector3(p.x,map.height_at(p.x,p.y),p.y))
   var hit:=map.pick_ground(screen)
   check(hit.is_finite() and hit.distance_to(p)<.01,"Ground picking works across core and extension "+str(p))
 map.target=Vector3(999,0,-999);map.distance=9999;map.update_camera()
 check(map.target.x==200 and map.target.z==-200 and map.distance==650,"Expanded camera clamp")
 print("MAP_DOMAIN_4KM checks=",checks," failures=",failures.size()," core_error=",max_core_error," slope_error=",max_slope_error," outer_max_slope=",max_outer_slope," triangles=",ext.get_meta("triangles")," surface_error_world=",max_display_error," area_world2=",area," build_usec=",build_usec)
 for orphan in [map.terrain,map.labels,map.infrastructure,map.selection,map.overlay]:orphan.free()
 map.free();quit(0 if failures.is_empty() else 1)
