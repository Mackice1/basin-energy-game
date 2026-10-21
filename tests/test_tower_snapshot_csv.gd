extends SceneTree
const C = preload("res://scripts/device_catalog.gd")
const Series = preload("res://scripts/series_import.gd")
const Controller = preload("res://scripts/optimization_controller.gd")
const Tower = preload("res://scripts/solar_tower_thermal.gd")
class Fixture extends Node:
	var fuel_supply: Dictionary = preload("res://scripts/fuel_supply.gd").defaults()
	var devices: Array = []
	var links: Array = []
	var imports: Array = []
	var elapsed_s: float = 0.0
	var scene_revision: int = 0
	var climate_config: Dictionary = {}
	func common_interval(_imports: Array) -> Dictionary: return {"start":0.0,"end":3600.0}
	func active_series() -> Array: return imports
	func sampled(t: float) -> Dictionary:
		var dni: Dictionary = preload("res://scripts/series_import.gd").sample(imports[0],t)
		return {"error":"" if dni.status == "ok" else "out of range", "weather":{"dni_wm2":dni.get("value",0.0),"solar_altitude_deg":60.0,"solar_azimuth_deg":180.0,"is_day":true,"air_temp_c":25.0},"direct":{},"sources":{},"device_weather":{}}
var checks := 0
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize() -> void:
	var host:=Fixture.new()
	var service:=Controller.new();service.host=host
	var csv:String="t,DNI\n0,800\n60,0\n120,1000\n3600,1000"
	var parsed:Dictionary=Series.parse(csv,{"time_column":"t","value_column":"DNI","time_unit":"s","value_unit":"W/m2","field":"dni_wm2","target_device":""})
	check(parsed.ok,"global DNI CSV parses")
	host.imports=[parsed.series]
	for kind in ["solar_tower_receiver","molten_salt_store","salt_steam_generator"]:
		host.devices.append({"id":host.devices.size(),"kind":kind,"params":C.defaults(kind),"state":C.initial_state(kind),"model_profile":C.model_profile(kind)})
	host.devices[1].state.energy_mwhth=0.25
	var before:PackedByteArray=var_to_bytes(host.devices)
	var snapshot:Dictionary=service.snapshot({"horizon_hours":1.0,"step_minutes":60})
	check(not snapshot.has("error"),"tower snapshot succeeds: "+str(snapshot.get("error","")))
	if not snapshot.has("error"):
		check(snapshot.schema_version==6,"tower optimization schema6")
		check(snapshot.steps.size()==3,"exact CSV boundaries split 60-minute forecast")
		check(snapshot.steps[0].weather.dni_wm2==800 and snapshot.steps[1].weather.dni_wm2==0 and snapshot.steps[2].weather.dni_wm2==1000,"freeze original DNI samples")
		check(absf(snapshot.steps[0].dt_h-1.0/60.0)<1e-12 and absf(snapshot.steps[1].time_s-60)<1e-12,"exact source durations")
		check(snapshot.devices[1].state.energy_mwhth==0.25,"snapshot uses current usable salt inventory")
		check(snapshot.devices[0].params.mirror_area_m2==1600,"physical mirrors frozen without capacity expansion")
		check(snapshot.devices[2].model_profile=="tower_stage1_v1","salt SG model profile preserved")
		check(absf(Tower.evaluate(snapshot.devices[0].params,snapshot.steps[0].weather).available_mwth-0.6912)<1e-10,"800 DNI produces 0.6912MWth under declared efficiencies")
		check(Tower.evaluate(snapshot.devices[0].params,snapshot.steps[1].weather).available_mwth==0,"zero DNI boundary closes receiver")
		var path:String="res://evidence/tower_stage/tower_csv_snapshot.json"
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(snapshot,"  "));file.close()
		var restored:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		check(restored.steps.size()==3 and restored.devices[1].state.energy_mwhth==0.25,"snapshot persisted and reloaded")
		check(var_to_bytes(host.devices)==before,"read-only snapshot retains live salt inventory")
		check(host.imports[0].source.original_csv==csv,"CSV provenance unchanged")
		check(service.snapshot({"horizon_hours":2.0,"step_minutes":60}).has("error"),"no forecast beyond common CSV interval")
		host.devices=[{"id":0,"kind":"pv","params":C.defaults("pv")}]
		# No generation sampling needed for this legacy thermal node.
		host.devices=[{"id":0,"kind":"steam_generator","params":C.defaults("steam_generator")}]
		var legacy:Dictionary=service.snapshot({"horizon_hours":1.0,"step_minutes":60})
		check(legacy.schema_version==5 and not legacy.has("tower") and not legacy.has("tower_energy"),"old Rankine snapshots retain schema and no tower fields")
	service.free();host.free()
	print("TOWER_SNAPSHOT_CSV: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
