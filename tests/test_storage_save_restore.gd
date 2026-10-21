extends SceneTree
## Exercise migration at the real controller boundary without booting terrain/UI.
const Validator = preload("res://scripts/save_validator.gd")
const Model = preload("res://scripts/energy_model.gd")
class SaveController:
	extends "res://scripts/world_game.gd"
	func _ready(): pass
	func set_mode(_mode: String): pass
	func rebuild_equipment(): pass
	func refresh(): pass

var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func legacy_fixture() -> Dictionary:
	return {"schema":3, "model_version":11, "rebuild":true,
		"devices":[{"id":0, "kind":"wind", "x":0.0, "z":0.0, "params":Model.defaults("wind")}],
		"links":[], "templates":{"wind":Model.defaults("wind"), "pv":Model.defaults("pv"), "station":Model.defaults("station")},
		"imports":[], "next_id":1, "elapsed_s":120.0,
		"energy":{"generated":0.04, "delivered":0.0, "curtailed":0.04, "loss":0.0}, "physical_lines":true}

func current_fixture() -> Dictionary:
	var result: Dictionary = legacy_fixture()
	result.schema = 4
	result.model_version = 12
	for kind in ["load", "battery"]:
		result.templates[kind] = Model.defaults(kind)
	for key in ["served", "unserved", "charge", "discharge", "storage_loss"]:
		result.energy[key] = 0.0
	var params: Dictionary = Model.defaults("battery")
	params.initial_soc = 0.8
	result.devices.append({"id":1, "kind":"battery", "x":20.0, "z":0.0, "params":params, "state":{"energy_mwh":2.7}})
	result.next_id = 2
	return result

func _initialize() -> void:
	var game: SaveController = SaveController.new()
	var source: Dictionary = legacy_fixture()
	var before: String = JSON.stringify(source)
	check(Validator.validate(source).is_empty(), "legacy source is valid before migration")
	game.paused = false
	game.accumulator = 9.0
	game.restore(source)
	check(game.paused and game.accumulator == 0.0, "loading legacy save pauses simulation and clears pending time")
	check(game.elapsed_s == 120.0 and game.next_id == 1, "migration preserves elapsed time and IDs")
	check(JSON.stringify(source) == before, "legacy restore never mutates caller's source object")
	check(game.templates.has("load") and game.templates.has("battery"), "legacy restore adds current build templates")
	for key in ["served", "unserved", "charge", "discharge", "storage_loss"]:
		check(game.energy.has(key) and game.energy[key] == 0.0, "legacy migration initializes only missing %s cumulative energy" % key)
	check(is_equal_approx(game.energy.generated, 0.04) and is_equal_approx(game.energy.curtailed, 0.04), "migration preserves old generation and curtailment")
	var saved: Dictionary = game.state()
	check(saved.schema == 12 and saved.model_version == 21, "next save upgrades to paired schema 12/model 21")
	check(Validator.validate(saved).is_empty(), "migrated scene saves as a valid current scene")
	check(Validator.validate(JSON.parse_string(JSON.stringify(saved))).is_empty(), "migrated save survives JSON round trip")

	source = current_fixture()
	before = JSON.stringify(source)
	check(Validator.validate(source).is_empty(), "current battery source is valid")
	game.restore(JSON.parse_string(before))
	check(is_equal_approx(game.devices[1].state.energy_mwh, 2.7), "load preserves actual battery energy instead of resetting initial SOC")
	check(is_equal_approx(game.devices[1].params.initial_soc, 0.8), "initial-SOC build parameter remains independent from current inventory")
	check(game.paused and game.elapsed_s == 120.0, "loading battery save does not advance its physical time")
	saved = game.state()
	check(Validator.validate(saved).is_empty(), "restored battery scene produces valid current save")
	check(JSON.stringify(source) == before, "battery source remains immutable")
	saved.devices[1].state.energy_mwh = 0.0
	check(is_equal_approx(game.devices[1].state.energy_mwh, 2.7), "save snapshot owns a deep copy of battery state")
	game.devices[1].state.energy_mwh = 1.25
	game.restore(JSON.parse_string(before))
	check(is_equal_approx(game.devices[1].state.energy_mwh, 2.7), "repeated restore reliably restores SOC without compounding")
	game.checkpoint()
	game.devices[1].state.energy_mwh = 0.75
	game.restore(game.undo_states.pop_back())
	check(is_equal_approx(game.devices[1].state.energy_mwh, 2.7), "undo snapshot restores actual stored energy")

	# Minimal test controllers may have only the old templates/ledger. state()
	# upgrades its copy so any checkpoint can be restored as a valid new save.
	game.templates = legacy_fixture().templates
	game.energy = legacy_fixture().energy
	var templates_before: String = JSON.stringify(game.templates)
	var energy_before: String = JSON.stringify(game.energy)
	saved = game.state()
	check(Validator.validate(saved).is_empty(), "snapshot fills missing default templates and cumulative fields")
	check(JSON.stringify(game.templates) == templates_before and JSON.stringify(game.energy) == energy_before, "snapshot default filling does not mutate live dictionaries")

	print("STORAGE_SAVE_RESTORE_TEST checks=", checks, " failures=", failures.size())
	# Base controller allocates UI nodes before _ready; dispose unparented members.
	for property in game.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var value: Variant = game.get(property.name)
		if value is Node and is_instance_valid(value) and value.get_parent() == null:
			value.free()
	game.free()
	quit(0 if failures.is_empty() else 1)
