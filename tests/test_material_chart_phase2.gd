extends SceneTree
const Chart = preload("res://scripts/device_runtime_chart.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); push_error(text)
func _initialize() -> void:
	var chart := Chart.new()
	var tank := {"kind":"hydrogen_gas_store","params":{"capacity_kg":1000.0}}
	var r := {"hydrogen_in_kg_s":0.012,"hydrogen_out_kg_s":0.0,"next_inventory_kg":350.0}
	var out: Dictionary = chart._extract(tank, r)
	check(out.unit == "kg/s", "gas flow not electric MW")
	check(out.values == [0.012,0.0] and out.soc == 35.0, "actual gas flow and separate inventory percent")
	r = {"water_out_kg_s":0.11,"next_inventory_kg":900.0}
	out = chart._extract({"kind":"water_supply_boundary","params":{"capacity_kg":1000.0}},r)
	check(out.unit == "kg/s" and out.values == [0.11] and out.soc == 90.0, "finite water actual flow")
	out = chart._extract({"kind":"electrolyzer_station"},{"electric_input_mw":1.5,"hydrogen_out_kg_s":0.008})
	check(out.unit == "MW" and out.values == [1.5], "electrolysis units never mix kg and MW")
	out = chart._extract({"kind":"fuel_cell_station"},{"electric_output_mw":0.6})
	check(out.unit == "MW" and out.values == [0.6], "fuel cell actual net electricity")
	check(chart._extract(tank,{}).is_empty(), "no fabricated missing gas series")
	check(chart._extract(tank,{"valid":false}).is_empty(), "invalid transaction has no chart")
	chart.free()
	print("MATERIAL_CHART_PHASE2 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
