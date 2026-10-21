extends SceneTree

const Visual = preload("res://scripts/equipment_visual.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var wind = Visual.create("wind")
	var pv = Visual.create("pv")
	var station = Visual.create("station")
	for label in ["ServiceApron", "AnchorFlange", "DoorStep", "NacelleVent", "WindVane"]:
		check(wind.has_node(label), "wind includes " + label)
	for label in ["FieldGravel", "InverterPlinth", "InverterVent"]:
		check(pv.has_node(label), "PV includes " + label)
	var solar: StandardMaterial3D = pv.get_node("Panel_0_0/Cells").material_override
	check(solar.albedo_texture != null, "PV has cell texture")
	check(solar.roughness < 0.3 and solar.clearcoat_enabled, "PV glass uses restrained reflective coating")
	check(pv.get_node("Panel_2_3/Cells").material_override == solar, "PV panels share one material")
	for label in ["OilConservator", "RearCoolingFin7", "BushingTerminal2", "CabinetHandle", "GravelBed"]:
		check(station.has_node(label), "station includes " + label)
	for item in [wind, pv, station]:
		check(item.get_meta("visual_only") and item.get_meta("capacity_added") == 0.0, "polish remains display only")
		check(item.surfaces.size() < 145, "mesh count remains bounded")
		check(item.surfaces.size() == item.base_materials.size(), "all decorative surfaces participate in material restoration")
		item.free()
	print("EQUIPMENT_POLISH_TEST checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
