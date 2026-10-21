extends Node3D
## Inspector-only representative MV transformer/switchgear assembly, authored in metres.
## Not OEM CAD or an electrical design; never used by placement, ports or simulation.
## No ground plane: the inspector owns its studio background and ground.
var device_kind := "station"
var _parts: Dictionary = {}
var _materials: Dictionary = {}
var _component_count := 0

func _init() -> void:
 name = "RepresentativeMVStation"
 set_meta("representative_only", true)
 set_meta("representation", "representative_mv_transformer_switchgear")
 set_meta("voltage_is_simulated", false)
 set_meta("geometry_assumption", "One illustrative MV transformer and enclosed switchgear; not OEM CAD, capacity, voltage rating or protection design.")
 _mat("tank", "778e87", 0.32, 0.48)
 _mat("edge", "556d67", 0.40, 0.50)
 _mat("steel", "9daeb3", 0.72, 0.34)
 _mat("cabinet", "c9d0d1", 0.25, 0.48)
 _mat("dark", "263438", 0.18, 0.68)
 _mat("porcelain", "695447", 0.15, 0.24)
 _mat("concrete", "aeb3af", 0.0, 0.93)
 _mat("warning", "e4b947", 0.05, 0.65)
 _mat("glass", "254450", 0.25, 0.26)
 _transformer()
 _switchgear()
 _connections()
 _bake()

func _transformer() -> void:
 # Local equipment foundations, not a site-sized platform or display ground.
 for x in [-2.35, -0.85]:
  _box("Footing", Vector3(.30,.18,2.75), Vector3(x,.09,0), "concrete")
  _box("BaseRail", Vector3(.16,.12,2.45), Vector3(x,.24,0), "steel")
 _box("Tank", Vector3(2.65,1.49,1.53), Vector3(-1.60,1.105,0), "tank")
 _box("BottomFlange", Vector3(2.77,.07,1.65), Vector3(-1.60,.39,0), "edge")
 _box("LidGasket", Vector3(2.78,.035,1.65), Vector3(-1.60,1.865,0), "dark")
 _box("BoltedLid", Vector3(2.87,.09,1.75), Vector3(-1.60,1.9275,0), "tank")
 for side in [-1,1]:
  # Separate cooling panels with visible gaps and upper/lower oil headers.
  for i in 23:
   _box("RadiatorFin", Vector3(.036,1.21,.35), Vector3(-2.76+i*.105,1.09,side*.94), "tank")
  for y in [.55,1.64]:
   _tube("RadiatorHeader", Vector3(-2.82,y,side*.95),Vector3(-.38,y,side*.95),.045,"edge")
   for x in [-2.65,-.55]:
    _tube("HeaderNeck",Vector3(x,y,side*.73),Vector3(x,y,side*.95),.045,"edge")
  for i in 12:
   _cylinder("LidBolt",.022,.018,.025,Vector3(-2.91+i*.238,1.985,side*.80),"steel",8)
 for x in [-2.88,-.32]:
  for z in [-.68,.68]:
   _box("LiftingLug",Vector3(.08,.17,.10),Vector3(x,1.81,z),"steel")
 # Three bushing stems, tapered porcelain sheds, flanges and clamped terminals.
 for phase in 3:
  var x := -2.48+phase*.84
  _cylinder("BushingFlange",.145,.145,.055,Vector3(x,2.00,-.28),"steel")
  _cylinder("BushingStem",.052,.064,.58,Vector3(x,2.305,-.28),"porcelain")
  for shed in 7:
   _cylinder("PorcelainShed",.095,.125,.045,Vector3(x,2.07+shed*.075,-.28),"porcelain")
  _cylinder("BushingTerminal",.035,.035,.11,Vector3(x,2.64,-.28),"steel")
  _box("TerminalClamp",Vector3(.13,.035,.08),Vector3(x,2.675,-.28),"steel")
 # Conservator is compact and does not imply a new operating parameter.
 for x in [-2.32,-.88]:
  _box("ConservatorSupport",Vector3(.08,.45,.10),Vector3(x,2.18,.63),"steel")
 _tube("Conservator",Vector3(-2.63,2.45,.64),Vector3(-.57,2.45,.64),.25,"tank",32)
 for x in [-2.64,-.56]:
  _tube("ConservatorEndRim",Vector3(x-.015,2.45,.64),Vector3(x+.015,2.45,.64),.258,"edge",32)
 _tube("OilLevelGauge",Vector3(-.537,2.45,.64),Vector3(-.516,2.45,.64),.10,"glass")
 _tube("OilPipe",Vector3(-.82,2.40,.64),Vector3(-.82,2.10,.64),.035,"edge")
 _tube("OilPipe",Vector3(-.82,2.10,.64),Vector3(-.82,1.98,.39),.035,"edge")
 _cylinder("FillCap",.065,.065,.045,Vector3(-1.60,2.72,.64),"steel")
 _box("CableTerminationBox",Vector3(.24,.68,.77),Vector3(-3.03,1.19,0),"tank")
 for z in [-.24,0,.24]:
  _tube("LVConduit",Vector3(-3.17,.91,z),Vector3(-3.17,.35,z),.045,"dark")
 # Accessory control box, drain valve and non-live identification plate.
 _box("MarshallingBox",Vector3(.37,.52,.17),Vector3(-.44,1.23,-1.12),"cabinet")
 _box("MarshallingDoor",Vector3(.32,.46,.018),Vector3(-.44,1.23,-1.215),"steel")
 _box("Nameplate",Vector3(.35,.17,.012),Vector3(-1.61,1.64,-1.13),"steel")
 for line in 4:
  _box("PlateEngraving",Vector3(.24,.008,.003),Vector3(-1.61,1.69-line*.027,-1.138),"dark")
 _tube("Drain",Vector3(-.40,.46,-.77),Vector3(-.40,.46,-1.07),.028,"steel")
 _box("ValveHandle",Vector3(.15,.025,.035),Vector3(-.40,.51,-1.02),"edge")

func _switchgear() -> void:
 for x in [.72,2.64]:
  _box("CabinetFooting",Vector3(.34,.18,2.45),Vector3(x,.09,.18),"concrete")
 _box("CabinetPlinth",Vector3(2.50,.15,2.23),Vector3(1.68,.255,.18),"dark")
 _box("Enclosure",Vector3(2.46,2.36,2.20),Vector3(1.68,1.51,.18),"cabinet")
 _box("RoofDripEdge",Vector3(2.59,.10,2.34),Vector3(1.68,2.74,.18),"steel")
 for panel in 3:
  var x := .87+panel*.81
  _box("DoorGasket",Vector3(.775,2.19,.025),Vector3(x,1.51,-.934),"dark")
  _box("Door",Vector3(.749,2.16,.035),Vector3(x,1.51,-.951),"cabinet")
  _box("RelayBezel",Vector3(.36,.31,.026),Vector3(x,2.14,-.981),"dark")
  _box("RelayWindow",Vector3(.30,.21,.012),Vector3(x,2.17,-.999),"glass")
  for indicator in 3:
   _box("StaticRelayMark",Vector3(.045,.012,.004),Vector3(x-.09+indicator*.09,2.08,-1.001),"steel")
  _box("OperatingPanel",Vector3(.37,.30,.015),Vector3(x,1.51,-.979),"steel")
  _tube("SwitchHandle",Vector3(x,1.50,-.99),Vector3(x,1.50,-1.06),.045,"dark")
  _box("HandleLever",Vector3(.025,.13,.035),Vector3(x,1.50,-1.08),"dark")
  _box("DoorHandle",Vector3(.024,.19,.042),Vector3(x+.26,1.18,-.997),"dark")
  for y in [.66,1.85]:
   _box("DoorHinge",Vector3(.032,.12,.04),Vector3(x-.35,y,-.978),"steel")
  _box("CautionPlate",Vector3(.17,.14,.01),Vector3(x,.94,-.980),"warning")
  _box("CautionMark",Vector3(.015,.065,.004),Vector3(x,.95,-.988),"dark")
  for slot in 6:
   _box("DoorVent",Vector3(.48,.015,.012),Vector3(x,.48+slot*.036,-.980),"dark")
 # Upper side/rear weatherproof ventilation, seam lines and bolted base trims.
 for side in [-1,1]:
  for slot in 10:
   _box("SideLouver",Vector3(.012,.025,.63),Vector3(1.68+side*1.237,2.15+slot*.04,.31),"edge")
 for x in [.55,1.68,2.81]:
  _cylinder("BaseAnchor",.028,.028,.035,Vector3(x,.345,-.84),"steel",8)

func _connections() -> void:
 # Insulated, separately routed MV leads descend behind the enclosure.
 # No exposed HV bus yard or made-up breaker bay is added to this compact unit.
 for phase in 3:
  var x := -2.48+phase*.84
  var z := -.28-phase*.22
  var points := [Vector3(x,2.69,-.28),Vector3(x,2.83,z),Vector3(.20,2.83,z),Vector3(.20,1.00,z),Vector3(.45,1.00,z)]
  _cable(points)
  _box("CableCleat",Vector3(.09,.04,.09),Vector3(.20,1.65,z),"steel")
 _box("CableSupport",Vector3(.12,.08,.88),Vector3(.20,1.65,-.50),"steel")
 for x in [-2.38,.73]:
  _box("EarthLug",Vector3(.09,.04,.07),Vector3(x,.36,-1.10),"steel")
 _tube("BondingConductor",Vector3(-2.38,.31,-1.10),Vector3(.73,.31,-1.10),.012,"edge")

func _cable(points: Array) -> void:
 # Rounded bends rather than mechanically impossible sharp cable elbows.
 var previous: Vector3 = points[0]
 for i in range(1,points.size()-1):
  var corner: Vector3 = points[i]
  var incoming: Vector3 = corner-points[i-1]
  var outgoing: Vector3 = points[i+1]-corner
  var radius := minf(.12,minf(incoming.length(),outgoing.length())*.35)
  var a := corner-incoming.normalized()*radius
  var b := corner+outgoing.normalized()*radius
  _tube("InsulatedMVLead",previous,a,.025,"dark")
  previous = a
  for segment in range(1,6):
   var t := segment/5.0
   var point := a*(1-t)*(1-t)+corner*2*t*(1-t)+b*t*t
   _tube("CableBend",previous,point,.025,"dark")
   previous = point
 _tube("InsulatedMVLead",previous,points[-1],.025,"dark")

func _mat(key: String, color: String, metallic: float, roughness: float) -> void:
 var m := StandardMaterial3D.new()
 m.resource_name = "MV_"+key
 m.albedo_color = Color(color)
 m.metallic = metallic
 m.roughness = roughness
 _materials[key] = m
 _parts[key] = []

func _mesh(label: String, mesh: Mesh, at: Vector3, mat: String) -> MeshInstance3D:
 var n := MeshInstance3D.new()
 n.name = label
 n.mesh = mesh
 n.position = at
 n.material_override = _materials[mat]
 _parts[mat].append(n)
 _component_count += 1
 return n

func _box(label: String, size: Vector3, at: Vector3, mat: String) -> void:
 var m := BoxMesh.new()
 m.size = size
 _mesh(label,m,at,mat)

func _cylinder(label: String, top: float, bottom: float, height: float, at: Vector3, mat: String, segments := 16) -> MeshInstance3D:
 var m := CylinderMesh.new()
 m.top_radius = top
 m.bottom_radius = bottom
 m.height = height
 m.radial_segments = segments
 m.rings = 1
 return _mesh(label,m,at,mat)

func _tube(label: String, start: Vector3, end: Vector3, radius: float, mat: String, segments := 16) -> void:
 var n := _cylinder(label,radius,radius,start.distance_to(end),(start+end)*.5,mat,segments)
 n.quaternion = Quaternion(Vector3.UP,(end-start).normalized())

func _bake() -> void:
 # One merged surface per material; hundreds of details do not mean hundreds of draws.
 var triangles := 0
 for key in _materials:
  var st := SurfaceTool.new()
  st.begin(Mesh.PRIMITIVE_TRIANGLES)
  for part in _parts[key]:
   st.append_from(part.mesh,0,part.transform)
   part.free()
  st.set_material(_materials[key])
  var mesh := st.commit()
  var n := MeshInstance3D.new()
  n.name = "MVDetail_"+key
  n.mesh = mesh
  n.material_override = _materials[key]
  add_child(n)
  triangles += mesh.surface_get_array_index_len(0) / 3
 set_meta("component_count", _component_count)
 set_meta("triangle_count", triangles)
 set_meta("material_count", _materials.size())
 _parts.clear()
