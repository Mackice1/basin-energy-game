extends RefCounted
## Photo-referenced scenery and the metric-domain outer ground mesh.
## No CollisionObject3D, physics ports, resource production or economy registration.
## Outer ground height/picking/placement use map.gd and map_domain.gd, not decoration.
## See docs/phase2/ENVIRONMENT_REFERENCE_REVIEW.md for source and scale boundaries.
const Road = preload("res://scripts/road_visual.gd")
const Domain = preload("res://scripts/map_domain.gd")
const SURROUND_RADII = [Domain.HALF_EXTENTS.x, 240.0, 300.0, 380.0, 520.0]
# Decorative horizon now begins beyond the separately constructible 4 km domain.
const INNER_HALF_EXTENTS = Domain.HALF_EXTENTS
const SECTORS = 128
const RESOURCE_POINTS = {"gas":Vector2(-80,-5),"coal":Vector2(-85,13),"water":Vector2(-76,42)}

static func _surface() -> SurfaceTool:
 var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);return st
static func _tri(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,color:Color):
 for p in [a,c,b]:st.set_color(color);st.add_vertex(p)
static func _material() -> StandardMaterial3D:
 var m:=StandardMaterial3D.new();m.vertex_color_use_as_albedo=true;m.roughness=.96;m.metallic_specular=.12
 m.cull_mode=BaseMaterial3D.CULL_DISABLED;return m
static func _finish(st:SurfaceTool,parent:Node3D,label:String) -> MeshInstance3D:
 st.generate_normals();var m:=st.commit();m.surface_set_material(0,_material())
 var n:=MeshInstance3D.new();n.name=label;n.mesh=m;n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(n)
 n.set_meta("display_only",true);return n
static func _box(st:SurfaceTool,at:Vector3,size:Vector3,color:Color):
 var m:=BoxMesh.new();m.size=size
 # Primitive meshes have no vertex color: emit their indexed vertices with tint.
 var arrays=m.surface_get_arrays(0);var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var ids:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
 for i in ids:st.set_color(color);st.add_vertex(verts[i]+at)
static func _rod(st:SurfaceTool,a:Vector3,b:Vector3,r:float,color:Color,sides:int=8):
 var axis:Vector3=(b-a).normalized();var side:Vector3=axis.cross(Vector3.UP)
 if side.length_squared()<.01:side=axis.cross(Vector3.RIGHT)
 side=side.normalized();var other:=axis.cross(side).normalized()
 for i in sides:
  var q:=side*cos(TAU*i/sides)+other*sin(TAU*i/sides)
  var t:=side*cos(TAU*(i+1)/sides)+other*sin(TAU*(i+1)/sides)
  _tri(st,a+q*r,b+q*r,a+t*r,color);_tri(st,a+t*r,b+q*r,b+t*r,color)
  _tri(st,a,a+t*r,a+q*r,color.darkened(.08));_tri(st,b,b+q*r,b+t*r,color)
static func _group(parent:Node3D,label:String)->Node3D:
 var n:=Node3D.new();n.name=label;n.set_meta("display_only",true);parent.add_child(n);return n

static func build_surround(map:Node3D) -> Node3D:
 var root:=_group(map,"NonBuildableDesertSurround")
 root.set_meta("buildable",false);root.set_meta("inner_half_extents",INNER_HALF_EXTENTS)
 root.set_meta("changes_height_field",false);root.set_meta("reference_ids",["NPS_ARID_LANDFORMS","NFGA_SAXAUL"])
 var st:=_surface();var rings:Array=[]
 for ring in SURROUND_RADII.size():
  var points:Array[Vector3]=[]
  for i in SECTORS:
   var angle:=TAU*i/SECTORS
   # Seam meets the outside edge of the constructible extension, never overlays it.
   var dir:=Vector2(cos(angle),sin(angle));dir/=maxf(absf(dir.x),absf(dir.y))
   var inner:Vector2=dir*INNER_HALF_EXTENTS
   var q:Vector2=inner if ring==0 else dir*float(SURROUND_RADII[ring])
   var edge_h:float=map.height_at(inner.x,inner.y)
   var h:=edge_h
   if ring>0:
    var ridge:=maxf(0.0,sin(angle*3.0+.45)+.40*sin(angle*7.0-1.2)+.22*cos(angle*13.0))
    var north:=.45+.55*maxf(0.0,-sin(angle))
    h=lerpf(edge_h,2.0,float(ring)/4.0)+ridge*north*[0.0,2.0,13.0,23.0,11.0][ring]
   points.append(Vector3(q.x,h,q.y))
  rings.append(points)
 for ring in range(SURROUND_RADII.size()-1):
  for i in SECTORS:
   var j:=(i+1)%SECTORS
   var haze:=float(ring)/4.0
   var c:=Color("978873").lerp(Color("abb6b4"),haze*.74)
   c=c.lightened(.035*sin(i*1.73)+.015*cos(i*.77))
   _tri(st,rings[ring][i],rings[ring+1][i],rings[ring][j],c)
   _tri(st,rings[ring][j],rings[ring+1][i],rings[ring+1][j],c)
 _finish(st,root,"BasinApronAndDistantRidges")
 root.set_meta("triangles",(SURROUND_RADII.size()-1)*SECTORS*2)
 return root

## A real rendered ground surface for the expanded build domain. Picking and
## siting use exactly map.height_at, not physics collisions or triangle hit tests.
## The untouched Terrain3D core is a hole in this mesh, joined at 0.25-world
## raster spacing. Rings coarsen away from the seam; no new heightfield binary.
static func build_constructible_extension(map:Node3D)->Node3D:
 var root:=_group(map,"ConstructibleDesertExtension")
 root.set_meta("buildable",true);root.set_meta("surface_role","metric_4km_ground")
 root.set_meta("changes_core_height_field",false);root.set_meta("adds_resource_supply",false)
 var boundary:Array[Vector2]=[]
 var half:Vector2=Domain.CORE_HALF_EXTENTS
 var side_x:=int(half.x*2.0/.25);var side_z:=int(half.y*2.0/.25)
 for i in side_x:boundary.append(Vector2(-half.x+i*.25,-half.y))
 for i in side_z:boundary.append(Vector2(half.x,-half.y+i*.25))
 for i in side_x:boundary.append(Vector2(half.x-i*.25,half.y))
 for i in side_z:boundary.append(Vector2(-half.x,half.y-i*.25))
 var offsets:Array[float]=[0,0.25,0.5,1,1.5,2,2.5,3,3.5,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,-0.5,-1.0]
 var strides:Array[int]=[1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,4,4]
 var rings:Array=[]
 for ring in offsets.size():
  var points:Array[Vector3]=[]
  for i in range(0,boundary.size(),strides[ring]):
   var p:Vector2=boundary[i]
   var outer:Vector2=p*(Domain.HALF_EXTENTS.x/maxf(absf(p.x),absf(p.y)))
   var path:Vector2=outer-p
   var along:float=offsets[ring] if offsets[ring]>=0 else 32.0+(path.length()-32.0)*(-offsets[ring])
   var q:Vector2=p+path.normalized()*along
   if ring==offsets.size()-1:q=outer
   points.append(Vector3(q.x,map.height_at(q.x,q.y),q.y))
  rings.append(points)
 var st:=_surface();var triangles:=0
 for ring in range(rings.size()-1):
  var inner:Array=rings[ring];var outer:Array=rings[ring+1]
  var ratio:int=inner.size()/outer.size()
  for i in outer.size():
   var j:=(i+1)%outer.size();var a:Vector3=inner[i*ratio];var c:Vector3=inner[(i*ratio+ratio)%inner.size()]
   var d:Vector3=outer[i];var e:Vector3=outer[j]
   var color:=Color(.98,.97,.94)
   if int(map.get("layer")) in [1,2,3,7]:color=map.land_color((a.x+c.x+d.x+e.x)*.25,(a.z+c.z+d.z+e.z)*.25)
   if ratio==1:
    _tri(st,a,d,c,color);_tri(st,c,d,e,color);triangles+=2
   else:
    var mid:Vector3=inner[(i*ratio+1)%inner.size()]
    _tri(st,a,d,mid,color);_tri(st,mid,d,e,color);_tri(st,mid,e,c,color);triangles+=3
 var surface:=_finish(st,root,"BuildableOuterGround")
 if not int(map.get("layer")) in [1,2,3,7]:
  surface.mesh.surface_set_material(0,_extension_ground_material(map))
  root.set_meta("material_transition","core_edge_material_continuation_v1")
 root.set_meta("triangles",triangles);root.set_meta("core_seam_vertices",boundary.size())
 root.set_meta("core_half_extents",Domain.CORE_HALF_EXTENTS);root.set_meta("outer_half_extents",Domain.HALF_EXTENTS)
 return root

# Keep the extension's surface colour contract aligned with desert_terrain.gdshader.
# This is only a material: original mesh positions/normals, height/control/colour
# files and all placement calculations remain untouched. Texture arrays are cached.
const GROUND_TRANSITION_WORLD:float = 60.0 # 600 m, no new terrain geometry.
const GROUND_TEXTURE_UV_SCALES := Vector4(.31,.17,.22,.24)
static var _ground_albedo_array:Texture2DArray
static var _ground_normal_array:Texture2DArray
static var _ground_control:ImageTexture
static var _ground_colormap:ImageTexture
static var _ground_shader:Shader
static func extension_blend_at(p:Vector2)->float:
 var distance:=maxf(maxf(absf(p.x)-Domain.CORE_HALF_EXTENTS.x,absf(p.y)-Domain.CORE_HALF_EXTENTS.y),0.0)
 return smoothstep(0.0,GROUND_TRANSITION_WORLD,distance)
static func _extension_ground_material(map:Node3D)->ShaderMaterial:
 if _ground_shader==null:
  _ground_shader=Shader.new()
  _ground_shader.code="""
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, skip_vertex_transform;
uniform sampler2DArray ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray ground_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D original_control : filter_nearest, repeat_disable;
uniform sampler2D original_colormap : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D macro_noise : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 macro_tint1 : source_color = vec3(.93,.90,.85);
uniform vec3 macro_tint2 : source_color = vec3(.90,.93,.95);
uniform float transition_world = 60.0;
uniform vec4 texture_uv_scales = vec4(.31,.17,.22,.24);
varying vec3 ground_position;
varying vec3 ground_up;
void vertex(){
 ground_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 // The unchanged annulus mesh has clockwise, downward authored normals.
 // Correct the *shading* frame here only, not its positions or mesh normals.
 ground_up=normalize(MODEL_NORMAL_MATRIX*NORMAL);
 if(ground_up.y<0.){ground_up=-ground_up;}
 vec3 tangent=normalize(cross(ground_up,vec3(0.,0.,1.)));
 vec3 binormal=normalize(cross(ground_up,tangent));
 VERTEX=(VIEW_MATRIX*vec4(ground_position,1.)).xyz;
 NORMAL=normalize((VIEW_MATRIX*vec4(ground_up,0.)).xyz);
 TANGENT=normalize((VIEW_MATRIX*vec4(tangent,0.)).xyz);
 BINORMAL=normalize((VIEW_MATRIX*vec4(binormal,0.)).xyz);
}
void fragment(){
 // Explicit upward lighting normal also avoids back-face normal reversal.
 vec3 up=normalize(ground_up);
 NORMAL=normalize((VIEW_MATRIX*vec4(up,0.)).xyz);
 vec3 tangent=normalize(cross(up,vec3(0.,0.,1.)));
 TANGENT=normalize((VIEW_MATRIX*vec4(tangent,0.)).xyz);
 BINORMAL=normalize((VIEW_MATRIX*vec4(cross(up,tangent),0.)).xyz);
 vec2 pos=ground_position.xz;
 vec2 edge=clamp(pos,vec2(-100.,-70.),vec2(100.,70.));
 float distance=max(max(abs(pos.x)-100.,abs(pos.y)-70.),0.);
 float fade=smoothstep(0.,transition_world,distance);
 float detail_fade=smoothstep(0.,12.,distance); // edge detail ends after 120 m
 // The original raster starts at -128 world, with 0.25-world texels.
 vec2 raster=(edge+128.)*4.;
 ivec2 pixel=ivec2(floor(raster));vec2 f=fract(raster);
 vec4 bilinear=vec4((1.-f.x)*(1.-f.y),f.x*(1.-f.y),(1.-f.x)*f.y,f.x*f.y);
 ivec2 offsets[4]=ivec2[4](ivec2(0,0),ivec2(1,0),ivec2(0,1),ivec2(1,1));
 vec4 weights=vec4(0.);
 for(int j=0;j<4;j++){
  uint bits=floatBitsToUint(texelFetch(original_control,pixel+offsets[j],0).r);
  int base=int((bits>>27u)&31u);int over=int((bits>>22u)&31u);
  float blend=float((bits>>14u)&255u)/255.;
  if(base<4){weights[base]+=bilinear[j]*(1.-blend);}
  if(over<4){weights[over]+=bilinear[j]*blend;}
 }
 weights=mix(weights,vec4(1.,0.,0.,0.),detail_fade);
 vec2 dx=dFdx(pos);vec2 dy=dFdy(pos);
 vec4 alb=vec4(0.);vec4 nrm=vec4(0.);float total=0.;float depth=0.;
 vec4 normal_depths=vec4(.72,.90,.54,.38);
 for(int i=0;i<4;i++){
  if(weights[i]>.000001){
   float scale=texture_uv_scales[i];vec2 uv=pos*scale+vec2(.5);
   vec4 a=textureGrad(ground_albedo,vec3(uv,float(i)),dx*scale,dy*scale);
   vec4 n=textureGrad(ground_normal,vec3(uv,float(i)),dx*scale,dy*scale);
   float w=pow(weights[i]+a.a*clamp(ground_up.y,0.,1.),24.8);
   alb+=a*w;nrm+=n*w;depth+=normal_depths[i]*w;total+=w;
  }
 }
 alb/=max(total,1e-20);nrm/=max(total,1e-20);depth/=max(total,1e-20);
 float footprint=max(length(dx),length(dy));
 // Preserve the core's colormap mip at the seam; the edge clamp must not
 // force a fine mip in the outward direction at a far-away overview camera.
 float lod=max(log2(max(footprint*4.,.00001)),0.);
 vec4 color=textureLod(original_colormap,(raster+vec2(.5))/1024.,lod);
 // Do not extrude detailed edge bands across the whole new landscape.
 // Preserve exact edge detail only at the seam, then use a spatially averaged
 // edge colour. Global world-space macro noise supplies non-stretched detail.
 vec3 coarse_color=textureLod(original_colormap,(raster+vec2(.5))/1024.,max(lod,6.)).rgb;
 color.rgb=mix(color.rgb,coarse_color,detail_fade);
 color.rgb=mix(color.rgb,vec3(.85),fade*.65);
 float c=cos(.32);float s=sin(.32);mat2 rotation=mat2(vec2(c,s),vec2(-s,c));
 float noise1=texture(macro_noise,(pos*.009+vec2(.5))*rotation).r;
 float noise2=texture(macro_noise,pos*.024).r;
 vec3 macro=mix(macro_tint1,vec3(1.),noise1)*mix(macro_tint2,vec3(1.),noise2);
 macro=mix(vec3(1.),macro,clamp(ground_up.y+.333,0.,1.));
 ALBEDO=alb.rgb*color.rgb*macro;
 float base_rough=clamp(nrm.a+.04,0.,1.);
 ROUGHNESS=clamp((color.a-.5)*2.+base_rough,0.,1.);
 SPECULAR=1.-base_rough;
 NORMAL_MAP=nrm.rgb;
 NORMAL_MAP_DEPTH=depth*mix(1.,.42,smoothstep(.08,.42,footprint));
}
"""
  var albedos:Array[Image]=[];var normals:Array[Image]=[]
  for name in ["gravel","bedrock","sand","salt"]:
   var a:Image=load("res://generated/%s_albedo.png"%name).get_image()
   var n:Image=load("res://generated/%s_normal.png"%name).get_image()
   if a.is_compressed():a.decompress()
   if n.is_compressed():n.decompress()
   a.generate_mipmaps();n.generate_mipmaps();albedos.append(a);normals.append(n)
  _ground_albedo_array=Texture2DArray.new();_ground_albedo_array.create_from_images(albedos)
  _ground_normal_array=Texture2DArray.new();_ground_normal_array.create_from_images(normals)
  var controls:=Image.create_from_data(1024,1024,false,Image.FORMAT_RF,FileAccess.get_file_as_bytes("res://generated/control.raw"))
  _ground_control=ImageTexture.create_from_image(controls)
  var colors:Image=load("res://generated/landscape_detail_colormap.png").get_image()
  if colors.is_compressed():colors.decompress()
  colors.generate_mipmaps()
  _ground_colormap=ImageTexture.create_from_image(colors)
 var material:=ShaderMaterial.new();material.shader=_ground_shader
 material.set_shader_parameter("ground_albedo",_ground_albedo_array)
 material.set_shader_parameter("ground_normal",_ground_normal_array)
 material.set_shader_parameter("original_control",_ground_control)
 material.set_shader_parameter("original_colormap",_ground_colormap)
 material.set_shader_parameter("macro_noise",preload("res://scripts/desert_surface.gd").macro_texture(int(map.cfg.seed)))
 material.set_shader_parameter("texture_uv_scales",GROUND_TEXTURE_UV_SCALES)
 material.set_shader_parameter("transition_world",GROUND_TRANSITION_WORLD)
 material.set_shader_parameter("macro_tint1",Color(.93,.90,.85))
 material.set_shader_parameter("macro_tint2",Color(.90,.93,.95))
 material.set_meta("surface_contract","core_edge_material_continuation_v1")
 material.set_meta("changes_height_or_mesh",false)
 return material

static func rock_mesh(variant:int)->ArrayMesh:
 var st:=_surface();var low:Array[Vector3]=[];var upper:Array[Vector3]=[]
 for i in 7:
  var a:=TAU*i/7.0
  var r:=.40+.10*sin(i*2.7+variant*1.8)
  low.append(Vector3(cos(a)*r,-.15,sin(a)*r))
  upper.append(Vector3(cos(a)*r*.86+.04, .14+.12*sin(i*1.8+variant),sin(a)*r*.78))
 var top:=Vector3(-.12+.08*variant,.34+.07*variant,.06)
 for i in 7:
  var j:=(i+1)%7;var c:=Color.WHITE.darkened(.025+float((i+variant)%4)*.03)
  _tri(st,low[i],upper[i],low[j],c);_tri(st,low[j],upper[i],upper[j],c);_tri(st,upper[i],top,upper[j],c)
 st.generate_normals();var m:=st.commit();m.surface_set_material(0,_material());return m

static func plant_mesh(grass:bool)->ArrayMesh:
 var st:=_surface()
 # Slender tapered blades/branch shoots, not rectangular alpha cards or solid crowns.
 for i in (14 if grass else 8):
  var a:=TAU*i/(14.0 if grass else 8.0)+.23
  var radial:=Vector3(cos(a),0,sin(a));var crosswise:=Vector3(-sin(a),0,cos(a))
  var height:=.23+.16*(.5+.5*sin(i*2.4)) if grass else .29+.22*(.5+.5*cos(i*1.7))
  var tip:=radial*(.22 if grass else .31)+Vector3(0,height,0)
  var stem:=radial*.025+Vector3(0,-.035,0)
  if grass:
   _tri(st,stem-crosswise*.018,tip,stem+crosswise*.018,Color("aaa185").lightened(float(i%3)*.04))
   _tri(st,stem-radial*.012,tip,stem+radial*.012,Color("8e9174"))
  else:
   var mid:=stem.lerp(tip,.60)
   _rod(st,stem,tip,.012,Color("7b7458"),3)
   for j in 3:
    var branch:=mid+Vector3(0,j*.04,0)
    var end:=branch+radial*.09+crosswise*(.09 if j%2==0 else -.09)+Vector3(0,.12,0)
    _tri(st,branch-crosswise*.023,end,branch+crosswise*.023,Color("889070").lightened(float(j)*.035))
    _tri(st,branch-radial*.016,end,branch+radial*.016,Color("737f62"))
 st.generate_normals();var m:=st.commit();m.surface_set_material(0,_material());return m

static func clear_of_routes(p:Vector2)->bool:
 var paths:Array=[Road.DISPLAY_CENTERLINE,[Vector2(-100,18),Vector2(-76,18),Vector2(-59,9)],[Vector2(-100,42),Vector2(-76,42),Vector2(-65,22)],[Vector2(-100,-5),Vector2(-82,-5),Vector2(-68,1)]]
 for path in paths:
  for i in range(path.size()-1):
   if Geometry2D.get_closest_point_to_segment(p,path[i],path[i+1]).distance_to(p)<1.65:return false
 for k in RESOURCE_POINTS:
  if p.distance_to(RESOURCE_POINTS[k])<4.0:return false
 return true

static func _scatter_node(parent:Node3D,label:String,mesh:Mesh,transforms:Array,colors:Array)->MultiMeshInstance3D:
 var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.mesh=mesh;mm.instance_count=transforms.size()
 for i in transforms.size():mm.set_instance_transform(i,transforms[i]);mm.set_instance_color(i,colors[i])
 var n:=MultiMeshInstance3D.new();n.name=label;n.multimesh=mm;n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(n);return n

static func build_scatter(map:Node3D)->Node3D:
 var root:=_group(map,"NaturalDesertScatter");root.set_meta("reference_ids",["NFGA_SAXAUL","NPS_ARID_LANDFORMS"])
 var rng:=RandomNumberGenerator.new();rng.seed=int(map.cfg.seed)
 var noise:=FastNoiseLite.new();noise.seed=int(map.cfg.seed)+47;noise.frequency=.11;noise.fractal_octaves=2
 var ts:Array=[[],[],[]];var cs:Array=[[],[],[]]
 for i in 1580:
  var x:=rng.randf_range(-98,98);var z:=rng.randf_range(-68,68)
  for attempt in 5:
   if noise.get_noise_2d(x,z)+rng.randf_range(-.35,.35)>-.08:break
   x=rng.randf_range(-98,98);z=rng.randf_range(-68,68)
  var sc:=rng.randf_range(.13,.40)
  if i<130:x=rng.randf_range(-94,-25);z=rng.randf_range(-58,-18);sc=rng.randf_range(.55,1.25)
  if (x>40 and z>28) or Vector2(x-32,z-38).length()<13:sc*=.34
  var normal:=Vector3(map.height_at(x-.5,z)-map.height_at(x+.5,z),1,map.height_at(x,z-.5)-map.height_at(x,z+.5)).normalized()
  var basis:=Basis(Quaternion(Vector3.UP,normal))*Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(sc,sc*rng.randf_range(.60,1),sc*rng.randf_range(.80,1.45)))
  var tint:=Color("8d897d").lerp(Color("b4a48b"),rng.randf())
  if not clear_of_routes(Vector2(x,z)):continue
  # Buried lower ring, no hovering bases; tilted with the same sampled terrain slope.
  ts[i%3].append(Transform3D(basis,Vector3(x,map.height_at(x,z)-.04*sc,z)));cs[i%3].append(tint)
 for k in 3:_scatter_node(root,"WeatheredRockVariant%d"%k,rock_mesh(k),ts[k],cs[k])
 var plants:=_group(root,"NearPlantDetail");ts=[[],[]];cs=[[],[]]
 for i in 232:
  var z:=rng.randf_range(-15,65);var bank:=-1.0 if rng.randf()<.5 else 1.0
  var x:float=map.stream_x(z)+bank*rng.randf_range(1.5,4.8)
  if i>145:
   var angle:=rng.randf()*TAU;var radius:=sqrt(rng.randf())*10.2
   x=-44+cos(angle)*radius;z=34+sin(angle)*radius*.78
  var sc:=rng.randf_range(.48,1.15)
  var basis:=Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(sc,sc*rng.randf_range(.70,1.15),sc*rng.randf_range(.80,1.25)))
  var tint:=Color("899078").lerp(Color("b1a88a"),rng.randf())
  if not clear_of_routes(Vector2(x,z)):continue
  ts[i%2].append(Transform3D(basis,Vector3(x,map.height_at(x,z)-.015,z)));cs[i%2].append(tint)
 _scatter_node(plants,"OpenBranchedDesertShrubs",plant_mesh(false),ts[0],cs[0])
 _scatter_node(plants,"TaperedDryGrassTufts",plant_mesh(true),ts[1],cs[1])
 root.set_meta("max_instances",1812);return root

static func set_detail(root:Node3D,span:float):
 if is_instance_valid(root):root.get_node("NearPlantDetail").visible=span<180.0

static func build_resources(map:Node3D,parent:Node3D)->Node3D:
 var root:=_group(parent,"ExternalResourceIllustrations")
 root.set_meta("resource_production_added",0.0);root.set_meta("logical_ports_added",0)
 root.set_meta("not_constructed_devices",true)
 for kind in RESOURCE_POINTS:
  var p:Vector2=RESOURCE_POINTS[kind];var node:=_group(root,"External_"+kind)
  node.position=Vector3(p.x,map.height_at(p.x,p.y),p.y)
  node.set_meta("boundary_anchor",p);node.set_meta("not_to_engineering_scale",true)
  var st:=_surface()
  if kind=="gas":_gas_reference(st)
  elif kind=="coal":_coal_reference(st)
  else:_water_reference(st)
  var mesh:=_finish(st,node,"ReferenceBasedBoundaryIllustration")
  # Conform every vertex to the unchanged local terrain: no hovering plinths.
  var arrays=mesh.mesh.surface_get_arrays(0);var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
  for i in verts.size():verts[i].y+=map.height_at(p.x+verts[i].x,p.y+verts[i].z)-node.position.y
  arrays[Mesh.ARRAY_VERTEX]=verts
  var fitted:=ArrayMesh.new();fitted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);fitted.surface_set_material(0,_material());mesh.mesh=fitted
 return root

static func _gas_reference(st:SurfaceTool):
 var origin:=Vector3(-.35,0,-2.0);var steel:=Color("727f7e");var pipe:=Color("a79c59")
 _box(st,origin+Vector3(0,.035,0),Vector3(2.1,.07,1.1),Color("827f73"))
 for z in [-.28,.28]:
  _box(st,origin+Vector3(0,.10,z),Vector3(1.85,.10,.09),steel)
  _rod(st,origin+Vector3(-.82,.33,z),origin+Vector3(.82,.33,z),.065,pipe)
  for x in [-.57,.5]:
   _rod(st,origin+Vector3(x-.04,.33,z),origin+Vector3(x+.04,.33,z),.105,steel)
   _rod(st,origin+Vector3(x,.33,z),origin+Vector3(x,.49,z),.022,steel)
   _rod(st,origin+Vector3(x-.07,.49,z),origin+Vector3(x+.07,.49,z),.015,Color("526864"))
  _rod(st,origin+Vector3(-.16,.33,z),origin+Vector3(-.16,.57,z),.095,Color("a6aaa0"))
  _rod(st,origin+Vector3(.22,.33,z),origin+Vector3(.22,.60,z),.015,steel)
  _rod(st,origin+Vector3(.22,.60,z-.02),origin+Vector3(.22,.60,z+.02),.061,Color("c4c4ad"))
 _box(st,origin+Vector3(.80,.38,.38),Vector3(.25,.48,.20),Color("8f9c9b"))
 for x in [-1.0,1.0]:
  for z in [-.50,.50]:_rod(st,origin+Vector3(x,0,z),origin+Vector3(x,.64,z),.014,steel,4)
 _rod(st,origin+Vector3(-1,.62,.50),origin+Vector3(1,.62,.50),.014,steel,4)

static func _coal_reference(st:SurfaceTool):
 var origin:=Vector3(0,0,2.5);var dark:=Color("373e3d");var steel:=Color("757a70")
 _box(st,origin+Vector3(0,.025,0),Vector3(4.0,.05,1.45),Color("817d6e"))
 # Long low stockpiles and an elevated belt; not a scaled replica of the port.
 for x in [-.85,.85]:
  for i in 8:
   var a:=TAU*i/8.0;var b:=TAU*(i+1)/8.0
   var p:=origin+Vector3(x+cos(a)*.65,.06,sin(a)*.48)
   var q:=origin+Vector3(x+cos(b)*.65,.06,sin(b)*.48)
   _tri(st,p,origin+Vector3(x,.43,-.04),q,dark.lightened(float(i%3)*.018))
 for x in [-1.6,0,1.6]:
  for z in [-.60,-.40]:_rod(st,origin+Vector3(x,.06,z),origin+Vector3(x,.68,z),.025,steel,4)
 _box(st,origin+Vector3(0,.69,-.50),Vector3(3.8,.10,.28),Color("4d5855"))
 for x in [-1.8,1.8]:_box(st,origin+Vector3(x,.86,-.50),Vector3(.35,.30,.42),Color("a09265"))
 _box(st,origin+Vector3(1.65,.28,.44),Vector3(.48,.48,.45),Color("9a998b"))
 # A stationary short hopper on the pre-existing siding, not a new railway.
 var wagon:=Vector3(-.5,0,5.0)
 _box(st,wagon+Vector3(0,.47,0),Vector3(1.8,.46,.57),Color("4a504b"))
 _box(st,wagon+Vector3(0,.70,0),Vector3(1.65,.025,.45),dark)
 for x in [-.65,.65]:_rod(st,wagon+Vector3(x,.20,-.36),wagon+Vector3(x,.20,.36),.16,dark)

static func _water_reference(st:SurfaceTool):
 var origin:=Vector3(.10,0,-2.0);var steel:=Color("899c9b");var blue:=Color("537b8c")
 _box(st,origin+Vector3(0,.04,0),Vector3(2.0,.08,1.1),Color("8d8a7b"))
 # Open-front service shelter makes a real pump/header train readable.
 for x in [-.9,.9]:
  for z in [-.46,.46]:_box(st,origin+Vector3(x,.48,z),Vector3(.045,.88,.045),steel)
 _box(st,origin+Vector3(0,.95,0),Vector3(2.05,.09,1.18),Color("6d7d7a"))
 for z in [-.26,.26]:_rod(st,origin+Vector3(-.76,.22,z),origin+Vector3(.76,.22,z),.075,blue)
 for x in [-.53,0,.53]:
  _rod(st,origin+Vector3(x,.19,0),origin+Vector3(x,.57,0),.09,steel)
  _rod(st,origin+Vector3(x,.57,0),origin+Vector3(x,.76,0),.105,Color("455d61"))
  _rod(st,origin+Vector3(x,.22,-.26),origin+Vector3(x,.22,.26),.05,steel)
 _box(st,origin+Vector3(.78,.49,.30),Vector3(.23,.53,.18),Color("adb3aa"))
 _box(st,origin+Vector3(.78,.58,.20),Vector3(.11,.11,.014),Color("314f59"))
