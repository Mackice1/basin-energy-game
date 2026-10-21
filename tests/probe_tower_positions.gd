extends SceneTree
const Spatial=preload('res://scripts/spatial_dimensions.gd')
func _init():
 for kind in ['molten_salt_store','salt_steam_generator','steam_turbine','steam_condenser','feedwater_pump']:
  var found=[]
  for x in range(-12,13,2):
   for z in range(-12,13,2):
    var pos:=Vector2(x,z)*.1
    if Spatial.tower_equipment_position_error(kind,{},pos)=='':found.append(pos)
  print(kind,': ',found)
 quit()
