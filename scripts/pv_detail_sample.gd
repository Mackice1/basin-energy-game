extends Node3D
## Inspector-only educational display. Never used by placement or simulation.
var device_kind := "pv"
const MODULE_COUNT := 3
func _init() -> void:
 name = "RepresentativePVSample"
 set_meta("representative_only", true)
 var frame := material("aebcc5", 0.65, 0.32)
 var backing := material("e1e7e9", 0.15, 0.7)
 var cell := material("163752", 0.05, 0.65)
 var bus := material("526b7b", 0.1, 0.65)
 var steel := material("8497a1", 0.6, 0.4)
 var concrete := material("c3c7c5", 0.0, 0.95)
 var cable := material("26333b", 0.0, 0.8)
 for index in MODULE_COUNT:
  var x := (index - 1) * 1.18
  var panel := Node3D.new()
  panel.name = "ExampleModule%d" % (index + 1)
  panel.position = Vector3(x, 1.12, 0)
  panel.rotation_degrees.x = -25
  add_child(panel)
  box(panel, Vector3(1.13, 0.038, 2.28), Vector3.ZERO, backing)
  for side in [-1, 1]:
   box(panel, Vector3(0.025, 0.055, 2.30), Vector3(side * 0.565, 0.012, 0), frame)
   box(panel, Vector3(1.13, 0.055, 0.025), Vector3(0, 0.012, side * 1.14), frame)
  for row in 12:
   for col in 6:
    var cx := (col - 2.5) * 0.176
    var cz := (row - 5.5) * 0.182
    box(panel, Vector3(0.169, 0.006, 0.174), Vector3(cx, 0.028, cz), cell).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    for line in [-1, 1]:
     box(panel, Vector3(0.0016, 0.001, 0.173), Vector3(cx + line * 0.043, 0.033, cz), bus).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  box(panel, Vector3(0.20, 0.065, 0.13), Vector3(0, -0.052, -0.65), cable)
  beam(panel, Vector3(0.07, -0.09, -0.65), Vector3(0.38, -0.10, -0.44), 0.012, cable)
  beam(panel, Vector3(0.38, -0.10, -0.44), Vector3(0.48, -0.10, 0.48), 0.012, cable)
 for z in [-0.72, 0.72]:
  var top: float = 1.12 + z * tan(deg_to_rad(25.0)) - 0.08
  box(self, Vector3(3.62, 0.07, 0.06), Vector3(0, top, z), steel)
  for x in [-1.25, 1.25]:
   box(self, Vector3(0.42, 0.12, 0.34), Vector3(x, 0.06, z), concrete)
   box(self, Vector3(0.07, top - 0.12, 0.07), Vector3(x, (top + 0.12) / 2, z), steel)
   box(self, Vector3(0.18, 0.018, 0.16), Vector3(x, 0.13, z), frame)
 for x in [-1.25, 1.25]:
  beam(self, Vector3(x, 0.18, -0.72), Vector3(x, 1.38, 0.72), 0.045, steel)
  beam(self, Vector3(x, 0.18, 0.72), Vector3(x, 0.68, -0.72), 0.04, steel)

 _merge_display_meshes()

func _merge_display_meshes() -> void:
 var groups: Dictionary = {}
 _collect_display_meshes(self, Transform3D.IDENTITY, groups)
 for child in get_children(): child.free()
 for group in groups.values():
  var node := MeshInstance3D.new()
  node.mesh = group.tool.commit()
  node.material_override = group.material
  node.cast_shadow = group.shadow
  add_child(node)
 set_meta("sample_module_count", MODULE_COUNT)

func _collect_display_meshes(parent: Node3D, transform: Transform3D, groups: Dictionary) -> void:
 for child in parent.get_children():
  if not child is Node3D: continue
  var current: Transform3D = transform * child.transform
  if child is MeshInstance3D:
   var key := str(child.material_override.get_instance_id()) + ":" + str(child.cast_shadow)
   if not groups.has(key):
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    groups[key] = {"tool":tool, "material":child.material_override, "shadow":child.cast_shadow}
   groups[key].tool.append_from(child.mesh, 0, current)
  _collect_display_meshes(child, current, groups)

static func material(color: String, metal: float, rough: float) -> StandardMaterial3D:
 var mat := StandardMaterial3D.new()
 mat.albedo_color = Color(color)
 mat.metallic = metal
 mat.roughness = rough
 return mat

static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
 var node := MeshInstance3D.new()
 var mesh := BoxMesh.new()
 mesh.size = size
 node.mesh = mesh
 node.material_override = mat
 node.position = pos
 parent.add_child(node)
 return node

static func beam(parent: Node3D, start: Vector3, end: Vector3, width: float, mat: Material) -> void:
 var node := box(parent, Vector3(width, width, start.distance_to(end)), (start + end) / 2, mat)
 node.look_at_from_position((start + end) / 2, end, Vector3.UP)
