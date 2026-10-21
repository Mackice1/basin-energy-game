extends SceneTree
const Form=preload("res://scripts/parameter_form.gd")
const Site=preload("res://scripts/site_layout_support.gd")
const C=preload("res://scripts/device_catalog.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures.append(message);push_error("SITE_BOUNDS_FORM "+message)
func _initialize():call_deferred("run")
func settle():
 for i in 3:await process_frame
func run():
 root.size=Vector2i(1180,812)
 var form:=Form.new();root.add_child(form);form.size=Vector2(1100,570)
 for kind in Site.supported_kinds():
  if not Form.GROUPS.has(kind):continue
  var p:Dictionary=C.defaults(kind);var original:=p.duplicate(true)
  form.set_parameters(kind,{},true)
  check(form.get_parameters()==p,"missing supplied fields merge full Catalog defaults "+kind)
  check(form._site_validation_errors().is_empty(),"default site bounds accepted "+kind)
  var bounds:Dictionary=Site.parameter_limits(kind)
  for key in bounds:
   check(form._fields.has(key),"site bound has labelled control "+kind+key)
   if not form._fields.has(key):continue
   var editor:LineEdit=form._fields[key]
   var text:String=editor.get_meta("parameter_range")
   if float(bounds[key].min)==float(bounds[key].max):check(text.contains("固定安装规格") and text.contains(String.num(float(bounds[key].max),6)),"fixed install size shown "+key)
   elif not Form.fixed_field(kind,key):check(text.contains(String.num(float(bounds[key].max),6)),"display upper bound from shared JSON "+kind+key)
   check(editor.tooltip_text.contains("统一安装规格") and editor.tooltip_text.contains(text),"tooltip and displayed range synchronized")
   if key.begins_with("capacity_"):check(editor.tooltip_text.contains("须先消耗库存") and editor.tooltip_text.contains("不得因缩容丢弃"),"no inventory clipping warning")
   if Form.fixed_field(kind,key):continue
   form.set_parameters(kind,p,true)
   var excessive:=float(bounds[key].max)+maxf(.001,absf(float(bounds[key].max))*.1)
   form._fields[key].text=str(excessive)
   check(form._site_validation_errors().has(key) and not form.get_validation_errors().is_empty(),"above envelope rejected "+kind+key)
   check(is_equal_approx(float(form.get_parameters()[key]),excessive),"invalid draft never clamped")
   form._fields[key].text="NaN";check(form._site_validation_errors().has(key),"site nonfinite rejected")
   form.set_parameters(kind,p,true);form._fields[key].text=str(float(bounds[key].min))
   check(form._site_validation_errors().has(key)==bool(bounds[key].get("min_exclusive",false)),"shared inclusive/exclusive lower bound "+kind+key)
   form.set_parameters(kind,p,true)
  check(p==original,"display/validation never changes source params "+kind)
 form.set_parameters("electric_boiler",{"rated_electric_mw":100.0},false)
 check(form._fields.rated_electric_mw.text=="100.0" and form.get_parameters().rated_electric_mw==100.0,"old oversized value shown and preserved")
 check(form._fields.rated_electric_mw.get_meta("parameter_range").contains("2") and not form._fields.rated_electric_mw.get_meta("parameter_range").contains("10000"),"boiler no misleading ten-thousand MW allowance")
 check(not form.get_validation_errors().is_empty(),"old unsupported value cannot be reapplied silently")
 form.set_parameters("wind",{"rotor_diameter_m":150.0},false)
 check(form._fields.rotor_diameter_m.text=="150.0" and form._fields.rotor_diameter_m.get_meta("parameter_range").contains("固定安装规格 126"),"old rotor retained next to fixed supported hardware size")
 form._fields.rotor_diameter_m.text="126";check(not form._site_validation_errors().has("rotor_diameter_m"),"explicit user correction to supported size accepted")
 form.set_parameters("battery",C.defaults("battery"),false)
 check(not form._fields.initial_soc.editable,"installed SOC remains read-only")
 check(form._fields.charge_efficiency.get_meta("parameter_range")=="0 < 值 ≤ 1","efficiency range unchanged")
 check(not form._fields.charge_efficiency.tooltip_text.contains("统一安装规格"),"efficiency notes not overwritten by capacity envelope")
 for resolution in [Vector2i(1180,812),Vector2i(640,480)]:
  root.size=resolution;form.position=Vector2(20,100);form.size=Vector2(resolution.x-40,resolution.y-260);form.set_parameters("wind",C.defaults("wind"),false);await settle()
  for editor in form._fields.values():
   form._scroll.ensure_control_visible(editor);await settle()
   var viewport:=form._scroll.get_global_rect();viewport.size.x-=form._scroll.get_v_scroll_bar().size.x if form._scroll.get_v_scroll_bar().visible else 0.0;viewport.size.y-=form._scroll.get_h_scroll_bar().size.y if form._scroll.get_h_scroll_bar().visible else 0.0
   check(viewport.grow(1).encloses(editor.get_global_rect()),"fixed-spec text does not make numeric fields inaccessible")
 form.free();await process_frame
 print("SITE_BOUNDS_PARAMETER_PHASE2C_UI checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
