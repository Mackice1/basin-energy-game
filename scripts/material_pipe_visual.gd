extends RefCounted
## Read-only indicative routing. No flow, capacity, terrain or collision state.
static func create(a:Vector3,b:Vector3,carrier:String,highlight:bool)->Node3D:
	var root:=Node3D.new();root.name="MaterialPipe"
	var color:Color={"material_h2_gas":Color("55bac7"),"material_water":Color("508ac0"),"material_n2_gas":Color("a0afc7"),"material_co2_gas":Color("c9b492")}.get(carrier,Color("8c9ba9"))
	var material:=StandardMaterial3D.new();material.albedo_color=color.lightened(0.25) if highlight else color;material.roughness=0.8
	var delta:=b-a
	if delta.length()<0.0001:return root
	var pipe:=MeshInstance3D.new();var mesh:=CylinderMesh.new();mesh.top_radius=0.025 if highlight else 0.015;mesh.bottom_radius=mesh.top_radius;mesh.height=delta.length();mesh.radial_segments=8;mesh.rings=1
	pipe.mesh=mesh;pipe.material_override=material;pipe.position=(a+b)*0.5
	var up:=delta.normalized();var side:=up.cross(Vector3.FORWARD).normalized()
	if side.length_squared()<0.01:side=up.cross(Vector3.RIGHT).normalized()
	pipe.basis=Basis(side,up,side.cross(up).normalized());root.add_child(pipe)
	root.set_meta("carrier",carrier);root.set_meta("unit","kg/s")
	return root
