extends RefCounted
## Display-only route dressing. Ground, logical route and carriageway width are unchanged.
## The eastern visual carriageway bypasses the existing tower foundations.
## Two vertex-color batches replace ~100 individually materialized road boxes.
const CENTERLINE = [Vector2(-100,13),Vector2(-78,13),Vector2(-48,5),Vector2(16,5),Vector2(66,3),Vector2(100,3)]
# Preserve both original map-edge endpoints; only decorative road placement changes.
const DISPLAY_CENTERLINE = [Vector2(-100,13),Vector2(-78,13),Vector2(-48,5),Vector2(16,5),Vector2(54,4),Vector2(60,4.7),Vector2(64,6.4),Vector2(68,7.2),Vector2(94,7.2),Vector2(97,6.6),Vector2(99,5),Vector2(100,3)]
static func point(map:Node3D,p:Vector2,offset:float)->Vector3:
 return Vector3(p.x,map.height_at(p.x,p.y)+offset,p.y)
static func quad(st:SurfaceTool,map:Node3D,a:Vector2,b:Vector2,c:Vector2,d:Vector2,tint:Color,offset:float):
 for p in [a,c,b,b,c,d]:
  st.set_color(tint);st.add_vertex(point(map,p,offset))
static func join_normal(points:Array,index:int)->Vector2:
 var before:Vector2=(points[index]-points[maxi(0,index-1)]).normalized() if index>0 else (points[1]-points[0]).normalized()
 var after:Vector2=(points[mini(points.size()-1,index+1)]-points[index]).normalized() if index<points.size()-1 else before
 var n1:=Vector2(-before.y,before.x);var n2:=Vector2(-after.y,after.x)
 var joined:Vector2=(n1+n2).normalized()
 return joined/maxf(joined.dot(n2),0.7)
static func strip(st:SurfaceTool,map:Node3D,points:Array,lo:float,hi:float,tint:Color,offset:float,pattern:bool=false):
 var station:=0.0
 for i in range(points.size()-1):
  var a:Vector2=points[i];var b:Vector2=points[i+1]
  var length:=a.distance_to(b);var tangent:Vector2=(b-a).normalized();var normal:=Vector2(-tangent.y,tangent.x)
  var count:=maxi(1,int(ceil(length/0.65)))
  for k in count:
   var u:=float(k)/count;var v:=float(k+1)/count
   if pattern and fmod(station+length*(u+v)*0.5,3.4)>1.55:continue
   var p:=a.lerp(b,u);var q:=a.lerp(b,v)
   var shade:=1.0+0.018*sin((station+length*u)*2.7)
   var left_normal:=join_normal(points,i) if k==0 else normal
   var right_normal:=join_normal(points,i+1) if k==count-1 else normal
   quad(st,map,p+left_normal*lo,q+right_normal*lo,p+left_normal*hi,q+right_normal*hi,tint*Color(shade,shade,shade,1),offset)
  station+=length
static func finish(st:SurfaceTool,parent:Node3D,label:String):
 st.generate_normals();var mesh:=st.commit();var mat:=StandardMaterial3D.new()
 mat.vertex_color_use_as_albedo=true;mat.roughness=0.98;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
 mesh.surface_set_material(0,mat)
 var node:=MeshInstance3D.new();node.name=label;node.mesh=mesh
 node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(node)
static func build(map:Node3D,parent:Node3D)->Node3D:
 var root:=Node3D.new();root.name="RoadSurfaceDetail";root.set_meta("display_only",true);parent.add_child(root)
 var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
 # Slightly irregular gravel shoulder and dark asphalt, same 1.5-wide carriageway.
 strip(surface,map,DISPLAY_CENTERLINE,-1.02,1.02,Color("a79b82"),0.19)
 strip(surface,map,DISPLAY_CENTERLINE,-0.87,0.87,Color("817e6e"),0.24)
 strip(surface,map,DISPLAY_CENTERLINE,-0.75,0.75,Color("535a58"),0.29)
 strip(surface,map,DISPLAY_CENTERLINE,-0.59,-0.19,Color("59605d"),0.295)
 strip(surface,map,DISPLAY_CENTERLINE,0.19,0.59,Color("59605d"),0.295)
 finish(surface,root,"RoadShoulderAndPavement")
 var detail:=Node3D.new();detail.name="NearDetail";root.add_child(detail)
 var markings:=SurfaceTool.new();markings.begin(Mesh.PRIMITIVE_TRIANGLES)
 strip(markings,map,DISPLAY_CENTERLINE,-0.672,-0.632,Color("c5c3ad"),0.312)
 strip(markings,map,DISPLAY_CENTERLINE,0.632,0.672,Color("c5c3ad"),0.312)
 strip(markings,map,DISPLAY_CENTERLINE,-0.024,0.024,Color("c7b780"),0.315,true)
 # Restrained transverse maintenance seams, all in the same material batch.
 var station:=0.0
 for i in range(DISPLAY_CENTERLINE.size()-1):
  var a:Vector2=DISPLAY_CENTERLINE[i];var b:Vector2=DISPLAY_CENTERLINE[i+1];var t:Vector2=(b-a).normalized();var n:=Vector2(-t.y,t.x)
  for k in range(2,int(a.distance_to(b)),8):
   var p:=a+t*float(k)
   quad(markings,map,p-n*0.60,p+n*0.60,p-n*0.60+t*0.018,p+n*0.60+t*0.018,Color("414b48"),0.316)
  station+=a.distance_to(b)
 finish(markings,detail,"RoadMarkingsAndJoints")
 return root
static func set_detail(root:Node3D,close:bool):
 if is_instance_valid(root):root.get_node("NearDetail").visible=close
