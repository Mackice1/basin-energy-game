extends SceneTree
const V = preload("res://scripts/save_validator.gd")
const C = preload("res://scripts/device_catalog.gd")
const M = preload("res://scripts/material_dispatch.gd")
const R = preload("res://scripts/rankine_cycle.gd")
const T = preload("res://scripts/solar_tower_thermal.gd")
const Old = preload("res://tests/test_high_temp_catalog.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func blank(schema: int = 14) -> Dictionary:
	var old = Old.new()
	var s: Dictionary = old.blank()
	old.free()
	s.schema = schema
	s.model_version = 23 if schema == 14 else 22
	s.rankine_energy = R.initial_energy()
	s.tower_energy = T.initial_energy()
	s.templates = {}
	for kind in V.SCHEMA13_KINDS: s.templates[kind] = C.defaults(kind)
	if schema == 14:
		for kind in V.MATERIAL_KINDS: s.templates[kind] = C.defaults(kind)
		s.material_energy = M.initial_energy_v1()
	return s
func _initialize() -> void:
	var s := blank()
	check(V.validate(s).is_empty(), "schema14 empty valid: " + V.validate(s))
	var encoded := JSON.stringify(s)
	check(V.validate(JSON.parse_string(encoded)).is_empty(), "schema14 JSON roundtrip")
	check(JSON.stringify(s) == encoded, "validation never mutates ledger")
	check(V.validate(blank(13)).is_empty(), "schema13 original 27 templates remain valid")
	for missing in M.initial_energy_v1():
		var bad := s.duplicate(true); bad.material_energy.erase(missing)
		check(not V.validate(bad).is_empty(), "missing material field " + missing)
		for value in [-1.0, NAN, INF, "1", null, true]:
			bad = s.duplicate(true); bad.material_energy[missing] = value
			check(not V.validate(bad).is_empty(), "invalid material field " + missing)
	for value in [null, [], 0, "ledger"]:
		var bad := s.duplicate(true); bad.material_energy = value
		check(not V.validate(bad).is_empty(), "non-object material ledger")
	var bad := s.duplicate(true); bad.erase("material_energy")
	check(not V.validate(bad).is_empty(), "schema14 ledger mandatory")
	bad = blank(13); bad.material_energy = M.initial_energy_v1()
	check(not V.validate(bad).is_empty(), "schema13 rejects material history")
	bad = blank(13); bad.templates.hydrogen_gas_store = C.defaults("hydrogen_gas_store")
	check(not V.validate(bad).is_empty(), "schema13 rejects material template")
	for kind in V.MATERIAL_KINDS:
		bad = s.duplicate(true); bad.templates.erase(kind)
		check(not V.validate(bad).is_empty(), "schema14 requires template " + kind)
	bad = s.duplicate(true); bad.material_energy.hydrogen_produced_kg = 1.0
	check(not V.validate(bad).is_empty(), "hydrogen without stoichiometric water rejected")
	bad = s.duplicate(true); bad.material_energy.extra = 0.0
	check(not V.validate(bad).is_empty(), "extra material ledger field rejected")
	print("MATERIAL_SAVE_PHASE2 checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
