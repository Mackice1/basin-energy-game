extends SceneTree
const S=preload('res://scripts/spatial_dimensions.gd')
const V=preload('res://scripts/equipment_visual.gd')
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func _init():
 for imported in [false,true]:
  var item=V.create('tower_station',{},imported);root.add_child(item)
  check(item.get_meta('commissioned') and not item.get_meta('preview_only'),'operating site separate from old preview')
  check(item.named_ports.is_empty(),'site facade itself creates no duplicate source terminal')
  var mirrors=item.find_children('MirrorSurface*','MeshInstance3D',true,false)
  check(mirrors.size()==100,'same100 mirrors')
  for angles in [Vector2(60,130),Vector2(20,260),Vector2(-5,180)]:
   item.set_tower_tracking(angles.x,angles.y)
   var alt=deg_to_rad(angles.x);var az=deg_to_rad(angles.y)
   var sun=Vector3(cos(alt)*sin(az),sin(alt),-cos(alt)*cos(az))
   for mirror in mirrors:
    var n:Vector3=mirror.basis.y.normalized()
    var backing:Node3D=mirror.get_parent().find_child('MirrorBacking*',false,false)
    check(absf(mirror.position.distance_to(backing.position)-(.06 if imported else .006))<.0001,'mirror backing clear offset in authored local units')
    if angles.x<=0:check(n.distance_to(Vector3.UP)<.0001,'night mirror stow')
    else:
     var actual:Vector3=-sun+2*sun.dot(n)*n
     check(actual.distance_to((Vector3(0,24.0 if imported else 2.4,0)-mirror.position).normalized())<.0001,'weather reflected ray reaches receiver')
  item.free()
 var preview=V.create('tower_station_preview',{},true);root.add_child(preview)
 var face:Node3D=preview.find_children('MirrorSurface*','MeshInstance3D',true,false)[0]
 var before:Basis=face.basis;preview.set_tower_tracking(20,10)
 check(face.basis.is_equal_approx(before),'old preview remains fixed pose')
 preview.free()
 for kind in ['solar_tower_receiver','molten_salt_store','salt_steam_generator']:
  var d=S.profile(kind)
  check(d.valid,'valid metric profile '+kind)
  var item=V.create(kind,{},true);root.add_child(item)
  check(item.named_ports.has('ac_in'),'explicit external AC '+kind)
  check(item.get_meta('capacity_added')==0,'geometry adds no energy')
  if kind=='salt_steam_generator':check(item.named_ports.has('salt_in') and not item.named_ports.has('oil_in'),'no disguised oil port')
  if kind=='solar_tower_receiver':check(item.find_children('MirrorSurface*','MeshInstance3D',true,false).is_empty(),'receiver console does not duplicate field')
  if kind=='molten_salt_store':
   check(absf(d.salt_inventory_mass_kg-4363.636363636)<.001,'0.5MWh cp1500 delta275 mass')
   check(absf(d.tank_geometric_volume_m3_each*0.8*1800-d.salt_inventory_mass_kg)<.001,'each tank holds full salt inventory plus freeboard')
  item.free()
 check(not S.tower_equipment_position_error('steam_condenser',{},Vector2(1.662983,0.68883)).is_empty(),'cannot occupy inner mirror sweep')
 check(not S.tower_equipment_position_error('molten_salt_store',{},Vector2(0,0)).is_empty(),'cannot occupy tower foot')
 print('TOWER_OPERATION_GEOMETRY ',checks,' checks ',failures,' failures')
 quit(1 if failures else 0)
