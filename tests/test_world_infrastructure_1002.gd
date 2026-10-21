extends SceneTree
const Road=preload("res://scripts/road_visual.gd")
const Corridor=preload("res://scripts/export_corridor_visual.gd")
var failures:Array[String]=[]
func check(ok:bool,label:String):
 if not ok:failures.append(label)
func _initialize():call_deferred("run")
func run():
 var game=load("res://main.tscn").instantiate();root.add_child(game)
 await process_frame
 game.example();game.paused=true
 var state=var_to_bytes(game.state())
 check(Road.CENTERLINE==[Vector2(-100,13),Vector2(-78,13),Vector2(-48,5),Vector2(16,5),Vector2(66,3),Vector2(100,3)],"Original road centerline")
 check(Road.DISPLAY_CENTERLINE[0]==Road.CENTERLINE[0] and Road.DISPLAY_CENTERLINE[-1]==Road.CENTERLINE[-1],"Road bypass preserves map-edge endpoints")
 var clearance:=INF
 for i in range(Road.DISPLAY_CENTERLINE.size()-1):
  var a:Vector2=Road.DISPLAY_CENTERLINE[i];var b:Vector2=Road.DISPLAY_CENTERLINE[i+1]
  for tx in Corridor.TOWER_X:
   var nearest=Geometry2D.get_closest_point_to_segment(Vector2(tx,3),a,b)
   clearance=minf(clearance,nearest.distance_to(Vector2(tx,3)))
 # Tower pads fit within radius1.70; visible shoulder extends1.02 from centerline.
 check(clearance>3.1,"Visual road shoulder stays outside all tower foundations")
 print("ROAD_TOWER_CENTERLINE_CLEARANCE ",clearance)
 check(game.road_detail.get_meta("display_only"),"Road remains decorative")
 check(game.road_detail.get_child_count()==2,"Road has one base batch and one detail group")
 for span in [235.0,70.0,8.0,300.0,40.0,205.0]:
  game.distance=span;game.update_camera()
  check(game.road_detail.get_node("NearDetail").visible==(span<115),"Road screen-span LOD")
  check(game.export_corridor.get_node("Near").visible==(span<65),"Tower screen-span LOD")
  check(game.export_corridor.get_node("Far").visible==(span>=65),"Tower exclusive far LOD")
 for mode in range(3):
  game.set_view(mode)
  var p=Vector2(0,15)
  var hit=game.pick_ground(game.camera.unproject_position(Vector3(p.x,game.height_at(p.x,p.y),p.y)))
  check(hit.distance_to(p)<0.1,"Ground pick unchanged in camera preset")
 var fixture=Node3D.new();game.add_child(fixture)
 game.line(fixture,[Vector2(0,0),Vector2(8,0)],0.3,Color.WHITE,0.5)
 check(fixture.get_child_count()==1,"Line submits one material batch")
 check(fixture.get_child(0).get_meta("segment_count")==4,"Original two-unit segment samples")
 check(fixture.get_child(0).mesh.surface_get_array_index_len(0)==4*36,"Original box triangles retained")
 fixture.queue_free()
 check(state==var_to_bytes(game.state()),"Visual changes preserve exact simulation state")
 check(game.cfg.grid_export_mw==4,"Original export cap retained")
 check(game.base_color_image.get_size()==Vector2i(1024,1024),"No enlarged color texture")
 check(game.height_image.get_size()==Vector2i(1024,1024),"Original terrain resolution")
 print("WORLD_INFRASTRUCTURE_RESULT ","PASS" if failures.is_empty() else str(failures))
 game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
