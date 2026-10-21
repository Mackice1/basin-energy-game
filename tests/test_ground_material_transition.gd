extends SceneTree
## Headless material-contract test. This is not a rendered-pixel approval.
const Env=preload("res://scripts/environment_visual.gd")
const DomainTest=preload("res://tests/test_map_domain_4km.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,msg:String):
 checks+=1
 if not ok:failures.append(msg);push_error(msg)
func _initialize():call_deferred("run")
func run():
 var map=DomainTest.Ground.new();root.add_child(map)
 var config_before=var_to_bytes(map.cfg)
 var ext=Env.build_constructible_extension(map)
 var surface:MeshInstance3D=ext.get_child(0)
 var arrays=surface.mesh.surface_get_arrays(0)
 var baseline=JSON.parse_string(FileAccess.get_file_as_string("res://evidence/phase2_ground_transition/geometry_baseline.json"))
 for pair in [[Mesh.ARRAY_VERTEX,"vertices"],[Mesh.ARRAY_NORMAL,"normals"],[Mesh.ARRAY_INDEX,"indices"]]:
  var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(var_to_bytes(arrays[pair[0]]))
  check(hash.finish().hex_encode()==baseline[pair[1]],"Exact pre-fix geometry unchanged: "+pair[1])
 check(ext.get_meta("triangles")==baseline.triangles and baseline.triangles==105400,"Same ground triangles and coverage")
 check(ext.get_meta("core_seam_vertices")==2720,"Same original core seam")
 var material=surface.mesh.surface_get_material(0)
 check(material is ShaderMaterial,"Ground uses matching material, not untinted triplanar gravel")
 check(material.get_meta("surface_contract")=="core_edge_material_continuation_v1","Explicit source surface contract")
 check(material.get_shader_parameter("texture_uv_scales")==Vector4(.31,.17,.22,.24),"Exact core half-scale world UV frequencies")
 check(material.get_shader_parameter("transition_world")==60.0,"600m colour transition, no geometry expansion")
 for key in ["ground_albedo","ground_normal"]:
  var texture=material.get_shader_parameter(key)
  check(texture is Texture2DArray and texture.get_layers()==4,"Same four original surface textures "+key)
  check(texture.has_mipmaps(),"Mipmap filtering prevents overview grain "+key)
 var control:ImageTexture=material.get_shader_parameter("original_control")
 check(control.get_width()==1024 and control.get_height()==1024,"Untouched original control raster dimensions")
 var colors:Texture2D=material.get_shader_parameter("original_colormap")
 check(colors.get_width()==1024 and colors.get_height()==1024,"Original colormap dimensions and filtered mips")
 var shader:String=material.shader.code
 for token in ["source_color","filter_linear_mipmap_anisotropic","texelFetch(original_control","(raster+vec2(.5))/1024.","pos*scale+vec2(.5)","alb.rgb*color.rgb*macro","smoothstep(.08,.42,footprint)"]:
  check(shader.contains(token),"Core surface continuity expression: "+token)
 # Same explicit MODEL -> VIEW coordinate handling as the core shader.
 # Exactly one pure assignment at each stage, no local/world displacement.
 var assignment:=RegEx.new();assignment.compile("(?m)^\\s*VERTEX\\s*=")
 check(assignment.search_all(shader).size()==1 and shader.contains("VERTEX=(VIEW_MATRIX*vec4(ground_position,1.)).xyz;"),"Only pure view-space vertex assignment")
 assignment.compile("(?m)^\\s*ground_position\\s*=")
 check(assignment.search_all(shader).size()==1 and shader.contains("ground_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;"),"Only pure world-space vertex assignment")
 check(shader.contains("skip_vertex_transform") and not shader.contains("ground_position +=") and not shader.contains("VERTEX +="),"No duplicate transform or displacement")
 check(shader.contains("if(ground_up.y<0.){ground_up=-ground_up;}") and shader.contains("NORMAL=normalize((VIEW_MATRIX*vec4(up,0.)).xyz);"),"Upward fragment lighting frame despite original reversed winding")
 var positive_up:=true
 for normal in arrays[Mesh.ARRAY_NORMAL]:
  var corrected:Vector3=-normal if normal.y<0 else normal
  if corrected.y<=0.0:positive_up=false
 check(positive_up,"All original annulus normals can shade upward without rewriting mesh")
 check(shader.contains("float detail_fade=smoothstep(0.,12.,distance);") and shader.contains("weights=mix(weights,vec4(1.,0.,0.,0.),detail_fade);"),"High-frequency edge material ends within120m")
 check(shader.contains("max(lod,6.)") and shader.contains("color.rgb=mix(color.rgb,coarse_color,detail_fade);"),"Only low-frequency edge colour enters wide fade")
 check(shader.contains("alb/=max(total,1e-20)") and not shader.contains("alb/=max(total,.000001)"),"Normalised material weights cannot form a dark small-denominator ring")
 check(material.get_shader_parameter("macro_tint1")==Color(.93,.90,.85) and material.get_shader_parameter("macro_tint2")==Color(.90,.93,.95),"Same explicit core macro-tint uniforms")
 for x in range(-100,101,5):
  for z in [-70.0,70.0]:
   var p=Vector2(x,z)
   check(Env.extension_blend_at(p)==0.0,"Original colour/control at core edge")
   check(Env.extension_blend_at(p+Vector2(0,signf(z)*.001))<1e-8,"No immediate colour step outside core")
 for z in range(-70,71,5):
  for x in [-100.0,100.0]:
   var p=Vector2(x,z)
   check(Env.extension_blend_at(p)==0.0,"Side edge retains original colour/control")
   check(Env.extension_blend_at(p+Vector2(signf(x)*.001,0))<1e-8,"No immediate colour step outside side")
 for i in 61:
  var p=Vector2(100+i,0)
  check(Env.extension_blend_at(p)>=0.0 and Env.extension_blend_at(p)<=1.0,"Bounded colour blend")
  if i>0:check(Env.extension_blend_at(p)>=Env.extension_blend_at(p-Vector2.RIGHT),"Monotonic exterior fade")
 check(Env.extension_blend_at(Vector2(160,0))==1.0,"Far apron converges to same gravel family")
 for layer in [1,2,3,7]:
  map.layer=layer;var overlay=Env.build_constructible_extension(map)
  check(overlay.get_child(0).mesh.surface_get_material(0) is StandardMaterial3D,"Existing semantic overlay unchanged "+str(layer));overlay.free()
 check(var_to_bytes(map.cfg)==config_before,"No config or economy change")
 check(ext.find_children("*","CollisionObject3D",true,false).is_empty(),"Material adds no collision/picking")
 print("GROUND_MATERIAL_TRANSITION checks=",checks," failures=",failures.size())
 for n in [map.terrain,map.labels,map.infrastructure,map.selection,map.overlay]:n.free()
 map.free();quit(0 if failures.is_empty() else 1)
