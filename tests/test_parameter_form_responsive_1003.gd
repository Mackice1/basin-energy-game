extends SceneTree
const Form = preload("res://scripts/parameter_form.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures.append(message); push_error("PARAM_RESPONSIVE " + message)
func _initialize(): call_deferred("run")
func run():
 var form := Form.new()
 var theme := Theme.new(); theme.default_font = load("res://assets/InterfaceCJK.ttc")
 form.theme = theme
 root.add_child(form)
 for resolution in [Vector2i(1024,768), Vector2i(640,480)]:
  root.size = resolution
  for kind in Catalog.implemented_kinds():
   form.position = Vector2(20,100)
   # Reserve the same space used by the host's title and fixed footer.
   form.size = Vector2(resolution.x - 40, resolution.y - 260)
   form.set_parameters(kind, Catalog.defaults(kind), false)
   await process_frame
   await process_frame
   check(form.size.x <= resolution.x - 40, "%s %s outer form stays inside horizontal margin" % [resolution,kind])
   check(form.size.y <= resolution.y - 260, "%s %s outer form leaves footer room" % [resolution,kind])
   check(form._scroll.size.y >= 60, "%s %s usable scroll viewport" % [resolution,kind])
   check(form._scroll.get_h_scroll_bar().visible or form._groups.size.x <= form._scroll.size.x + .1, "%s %s wide grid is reachable rather than clipped" % [resolution,kind])
   for field in form._fields.values():
    form._scroll.ensure_control_visible(field)
    await process_frame
    var viewport := form._scroll.get_global_rect()
    viewport.size.x -= form._scroll.get_v_scroll_bar().size.x if form._scroll.get_v_scroll_bar().visible else 0.0
    viewport.size.y -= form._scroll.get_h_scroll_bar().size.y if form._scroll.get_h_scroll_bar().visible else 0.0
    var visible := viewport.grow(1.0).encloses(field.get_global_rect())
    check(visible, "%s %s %s can be scrolled fully into view" % [resolution,kind,field.name])
    check(field.size.x >= 125 and field.size.y >= 40, "%s %s input target retained" % [resolution,kind])
   # Expansion must stay inside the same viewport, not grow the window.
   for explanation in form.find_children("ParameterAssumptions", "Button", true, false):
    explanation.button_pressed = true
   await process_frame
   check(form.size.x <= resolution.x - 40 and form.size.y <= resolution.y - 260, "%s %s expanded model notes remain scrollable" % [resolution,kind])
 form.free()
 print("PARAMETER_RESPONSIVE_1003 checks=", checks, " failures=", failures.size())
 quit(0 if failures.is_empty() else 1)
