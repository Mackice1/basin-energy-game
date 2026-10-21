extends Node3D
## Read-only detail of the same tower asset used by the site, not a second device.
var device_kind := "solar_tower_receiver"
func _init() -> void:
 name = "RepresentativeReceiverTower"
 set_meta("representative_only", true)
 preload("res://scripts/tower_visual.gd").build(self)
