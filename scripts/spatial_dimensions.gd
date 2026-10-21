extends RefCounted
## Authoritative metric geometry, independent of visual LOD and energy dispatch.
## Vector3 dimensions are (x, height, z), in metres; convert to world units once.
## Teaching installation allowances are not certified engineering clearances.
const Catalog = preload("res://scripts/device_catalog.gd")
const WORLD_UNITS_PER_METER: float = 0.1
const METRIC_PROFILE: String = "metric_v1"
const LEGACY_PROFILE: String = "legacy_illustrative"
const MODULE_SPACING_M: float = 2.0
const DEFAULT_MARGIN_M: float = 2.0
const PV_MARGIN_M: float = 4.0
const MAX_EXPLICIT_ORIGINS: int = 32768
const PANEL_WIDTH_M: float = 1.134
const PANEL_LENGTH_M: float = 2.278
const PANEL_THICKNESS_M: float = 0.035
const PANEL_RATING_W: float = 550.0
const PV_COLUMN_PITCH_M: float = 1.2
const PV_ROW_PITCH_M: float = 5.0
const PV_TILT_DEG: float = 25.0
# Vitosol 200-T SP2A 24-tube historical reference; installation is teaching geometry.
const SOLAR_ABSORBER_M2: float = 3.03
const SOLAR_APERTURE_M2: float = 3.19
const SOLAR_GROSS_M2: float = 4.62
const SOLAR_WIDTH_M: float = 2.061
const SOLAR_LENGTH_M: float = 2.241
const SOLAR_THICKNESS_M: float = 0.15
const SOLAR_TILT_DEG: float = 30.0
const SOLAR_COLUMN_PITCH_M: float = 2.4
const SOLAR_ROW_PITCH_M: float = 3.6
const SOLAR_BOTTOM_M: float = 0.35
const TROUGH_APERTURE_M2: float = 69.24
const TROUGH_FOCAL_LENGTH_M: float = 1.71
const TROUGH_AXIS_HEIGHT_M: float = 3.5
const TROUGH_SWEEP_RADIUS_M: float = 3.25
const OIL_ENTHALPY_KJ_KG: float = 238.0
const OIL_HOT_DENSITY_KG_M3: float = 809.0
const STATION_INTERIOR_HALF_WORLD: float = 2.4
const STATION_CLEARANCE_RADIUS_WORLD: float = 5.0
const TOWER_SITE_DIMENSIONS_M := Vector3(160.0, 0.0, 160.0)
const TOWER_INTERIOR_DIMENSIONS_M := Vector3(120.0, 0.0, 120.0)
const TOWER_HEIGHT_M: float = 25.0
const TOWER_HELIOSTAT_COUNT: int = 100
const TOWER_MIRROR_APERTURE_M2: float = 1600.0

const TOWER_RING_RADII_M = [18.0, 30.0, 42.0, 54.0]
const TOWER_RING_SLOTS = [16, 24, 32, 40]
const TOWER_SUN_DIRECTION := Vector3(-0.423999152002544, 0.847998304005088, -0.317999364001908)
const TOWER_RECEIVER_M := Vector3(0.0, 24.0, 0.0)

static func tower_mirror_layout() -> Array[Dictionary]:
	var layout: Array[Dictionary] = []
	for ring in range(TOWER_RING_RADII_M.size()):
		var radius: float = TOWER_RING_RADII_M[ring]
		var slots: int = TOWER_RING_SLOTS[ring]
		for slot in range(slots):
			var angle := TAU * (float(slot) + 0.5 * float(ring % 2)) / float(slots)
			var center := Vector3(radius * cos(angle), 3.0, radius * sin(angle))
			if absf(center.z) < 5.0: continue
			var target := (TOWER_RECEIVER_M - center).normalized()
			layout.append({"ring": ring, "center_m": center, "normal": (TOWER_SUN_DIRECTION + target).normalized()})
	return layout

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _base(kind: String) -> Dictionary:
	var origins: Array[Vector3] = []
	var origins_world: Array[Vector3] = []
	return {"valid": true, "errors": [], "kind": kind, "dimension_profile": METRIC_PROFILE,
		"units_per_meter": WORLD_UNITS_PER_METER, "module_count": 0,
		"unit_dimensions_m": Vector3.ZERO, "module_dimensions_m": Vector3.ZERO,
		"module_origins_m": origins, "module_origins_world": origins_world,
		"origins_complete": true, "columns": 0, "rows": 0, "layout_columns": 0, "layout_rows": 0,
		"grid_origin_m": Vector3.ZERO, "column_pitch_m": 0.0, "row_pitch_m": 0.0,
		"body_dimensions_m": Vector3.ZERO, "body_area_m2": 0.0,
		"land_dimensions_m": Vector3.ZERO, "land_area_m2": 0.0,
		"clearance_radius_m": 0.0, "clearance_radius_world": 0.0,
		"land_envelope_area_m2": 0.0, "maintenance_margin_m": 0.0,
		"description": "", "source_note": ""}

static func _fail(result: Dictionary, message: String) -> Dictionary:
	result.valid = false
	result.errors.append(message)
	result.description = message
	return result

static func _check_values(p: Dictionary, limits: Dictionary) -> String:
	for key in limits:
		var limit: Vector2 = limits[key]
		if not _finite_number(p.get(key)):
			return "%s must be a finite numeric geometry parameter." % key
		if float(p[key]) < limit.x or float(p[key]) > limit.y or (float(p[key]) == 0.0 and not key in ["charge_mw", "discharge_mw"]):
			return "%s is outside supported geometry bounds." % key
	return ""

static func _set_radius(result: Dictionary, radius_m: float) -> void:
	result.clearance_radius_m = radius_m
	result.clearance_radius_world = radius_m * WORLD_UNITS_PER_METER
	# This is a conservative collision envelope, never a building/base area.
	result.land_envelope_area_m2 = PI * radius_m * radius_m

static func _set_origins(result: Dictionary, include_origins: bool = true) -> void:
	var count: int = int(result.module_count)
	result.origins_complete = include_origins and count <= MAX_EXPLICIT_ORIGINS
	if not include_origins:
		return
	# Large PV fields retain their full analytical layout and exact counts.
	# Do not allocate millions of vectors merely to reject an oversized site.
	for index in mini(count, MAX_EXPLICIT_ORIGINS):
		var origin: Vector3 = module_origin_m(result, index)
		result.module_origins_m.append(origin)
		result.module_origins_world.append(origin * WORLD_UNITS_PER_METER)

## Returns a ground-level module origin (PV: tilted panel center), including
## entries beyond explicit-origin LOD limits. The layout is never downscaled.
static func module_origin_m(dimensions: Dictionary, index: int) -> Vector3:
	if index < 0 or index >= int(dimensions.get("module_count", 0)) or int(dimensions.get("columns", 0)) <= 0:
		return Vector3.ZERO
	var columns: int = int(dimensions.columns)
	return dimensions.grid_origin_m + Vector3(float(index % columns) * float(dimensions.column_pitch_m), 0.0,
		float(index / columns) * float(dimensions.row_pitch_m))

static func panel_origin_m(dimensions: Dictionary, index: int) -> Vector3:
	return module_origin_m(dimensions, index)

static func _modules(result: Dictionary, count: int, unit: Vector3, source: String, include_origins: bool = true) -> Dictionary:
	result.module_count = count
	result.unit_dimensions_m = unit
	result.module_dimensions_m = unit
	var pitch_x: float = unit.x + MODULE_SPACING_M
	var pitch_z: float = unit.z + MODULE_SPACING_M
	var columns: int = maxi(1, int(ceil(sqrt(float(count) * pitch_z / pitch_x))))
	if result.kind in ["parabolic_trough", "high_temp_store", "oil_water_exchanger"]:
		columns = mini(columns, count)
	var rows: int = int(ceil(float(count) / float(columns)))
	result.columns = columns
	result.rows = rows
	result.layout_columns = columns
	result.layout_rows = rows
	result.column_pitch_m = pitch_x
	result.row_pitch_m = pitch_z
	result.grid_origin_m = Vector3(-float(columns - 1) * pitch_x * 0.5, 0.0, -float(rows - 1) * pitch_z * 0.5)
	var body := Vector3(float(columns - 1) * pitch_x + unit.x, unit.y, float(rows - 1) * pitch_z + unit.z)
	result.body_dimensions_m = body
	result.body_area_m2 = float(count) * unit.x * unit.z
	result.land_dimensions_m = Vector3(body.x + DEFAULT_MARGIN_M * 2.0, 0.0, body.z + DEFAULT_MARGIN_M * 2.0)
	result.land_area_m2 = result.land_dimensions_m.x * result.land_dimensions_m.z
	result.maintenance_margin_m = DEFAULT_MARGIN_M
	_set_radius(result, Vector2(result.land_dimensions_m.x, result.land_dimensions_m.z).length() * 0.5)
	_set_origins(result, include_origins)
	result.description = "%d个等尺寸模块；单模块 %.3f×%.3f×%.3f m（长×宽×高）；实体投影 %.2f m²；教学安装区 %.2f m²。模块组仅共用一套设备端口及运行限额。" % [count, unit.x, unit.z, unit.y, result.body_area_m2, result.land_area_m2]
	result.source_note = source + " 模块间距2 m、四周检修预留2 m为教学假设，非工程或消防认证。"
	return result

## include_origins=false is a cheap bounds/count query for live placement and
## persistence validation. It never changes geometry or procedural-origin access.
static func profile(kind: String, params: Dictionary = {}, include_origins: bool = true) -> Dictionary:
	var result: Dictionary = _base(kind)
	var p: Dictionary = Catalog.defaults(kind)
	p.merge(params, true)
	var limits: Dictionary = {}
	match kind:
		"steam_generator", "salt_steam_generator", "steam_condenser": limits = {"capacity_mwth": Vector2(0.0, 10000.0)}
		"steam_turbine", "feedwater_pump": limits = {"mass_flow_capacity_kg_s": Vector2(0.0, 1000.0)}
		"parabolic_trough": limits = {"aperture_area_m2": Vector2(0.0, 6924000.0)}
		"high_temp_store", "molten_salt_store": limits = {"capacity_mwhth": Vector2(0.0, 100000.0)}
		"oil_water_exchanger": limits = {"capacity_mwth": Vector2(0.0, 10000.0)}
		"wind": limits = {"rotor_diameter_m": Vector2(0.0, 1000.0), "hub_height_m": Vector2(0.0, 2000.0)}
		"solar_thermal": limits = {"absorber_area_m2": Vector2(0.0, 3030.0)}
		"pv": limits = {"dc_capacity_mw": Vector2(0.0, 10000.0)}
		"station": limits = {"capacity_mw": Vector2(0.0, 10000.0)}
		"battery", "battery_sodium", "battery_flow", "caes_aboveground", "liquid_air_store", "hydrogen_storage_system": limits = {"capacity_mwh": Vector2(0.0, 100000.0), "charge_mw": Vector2(0.0, 10000.0), "discharge_mw": Vector2(0.0, 10000.0)}
		"electric_boiler": limits = {"rated_electric_mw": Vector2(0.0, 10000.0)}
		"fuel_boiler": limits = {"rated_fuel_mw": Vector2(0.0, 10000.0)}
		"thermal_store", "solid_thermal_store": limits = {"capacity_mwhth": Vector2(0.0, 100000.0)}
		"heat_exchanger": limits = {"capacity_mwth": Vector2(0.0, 10000.0)}
		"load", "heat_demand", "thermal_station", "tower_station_preview", "tower_station", "solar_tower_receiver": pass
		_: return _fail(result, "Unknown spatial device kind: " + kind)
	var error: String = _check_values(p, limits)
	if not error.is_empty():
		return _fail(result, error)
	match kind:
		"steam_generator", "salt_steam_generator", "steam_turbine", "steam_condenser", "feedwater_pump":
			var reference := .1 if kind in ["steam_generator", "salt_steam_generator"] else .08 if kind == "steam_condenser" else .05
			var key := "capacity_mwth" if kind in ["steam_generator", "salt_steam_generator", "steam_condenser"] else "mass_flow_capacity_kg_s"
			var unit := Vector3(4,3,2.5) if kind in ["steam_generator", "salt_steam_generator"] else Vector3(4,2.2,2.5) if kind == "steam_turbine" else Vector3(6,4.2,4) if kind == "steam_condenser" else Vector3(2,1.5,1.2)
			result.reference_rating_per_module = reference
			result.rating_parameter = key
			result.rating_unit = "MWth" if key == "capacity_mwth" else "kg/s"
			result.requested_rating = float(p[key])
			result.installed_reference_rating = maxi(1, int(ceil(float(p[key]) / reference - .000000001))) * reference
			return _modules(result, maxi(1, int(ceil(float(p[key]) / reference - .000000001))), unit, "Original closed teaching Rankine equipment: " + kind + "; reference module " + str(reference) + " " + result.rating_unit + ". Fixed original process-skid envelope, not manufacturer CAD or certified capacity sizing; full-size modules replicate without rescaling. Dry air cooling only for condenser.", include_origins)
		"parabolic_trough":
			var count := maxi(1, int(ceil(float(p.aperture_area_m2) / TROUGH_APERTURE_M2 - 0.000000001)))
			_modules(result, count, Vector3(6.5, 6.75, 13.0), "EuroTrough-inspired 12 m N–S teaching segment, 5.77 m aperture, f=1.71 m; original mesh, not manufacturer CAD. Full-circle 3.25 m sweep radius and 3.5 m horizontal axis height; fixed access is independent of tracking.", include_origins)
			result.requested_aperture_area_m2 = float(p.aperture_area_m2)
			result.installed_aperture_area_m2 = count * TROUGH_APERTURE_M2
			result.last_module_utilization = clampf((float(p.aperture_area_m2) - (count - 1) * TROUGH_APERTURE_M2) / TROUGH_APERTURE_M2, 0.0, 1.0)
			result.sweep_radius_m = TROUGH_SWEEP_RADIUS_M
			result.axis_height_m = TROUGH_AXIS_HEIGHT_M
			result.focal_length_m = TROUGH_FOCAL_LENGTH_M
			result.axis_orientation = "north_south_horizontal"
			return result
		"solar_tower_receiver":
			_modules(result, 1, Vector3(2,1.5,1.2), "Tower receiver control terminal only; 25m tower and 1600m2 mirror field rendered once by parent tower site. Full field land is counted by site, not this console.", include_origins)
			result.field_aperture_area_m2 = 1600.0
			return result
		"molten_salt_store":
			var mass: float = float(p.capacity_mwhth) * 3600000000.0 / (1500.0 * 275.0)
			var volume: float = mass / 1800.0
			var geometric: float = volume / .8
			var diameter: float = pow(4.0 * geometric / PI, 1.0 / 3.0)
			_modules(result, 1, Vector3(2*diameter+2,diameter+.6,diameter+1), "Solar Salt 565/290C useful enthalpy only: teaching cp1500 J/kgK, density1800 kg/m3. Each of two tanks holds full inventory with 20% freeboard; no ambient cold start.", include_origins)
			result.tank_diameter_m = diameter
			result.tank_height_m = diameter
			result.hot_full_volume_m3_each = volume
			result.tank_geometric_volume_m3_each = geometric
			result.salt_inventory_mass_kg = mass
			result.freeboard_fraction = .2
			return result
		"high_temp_store":
			var hot_volume := float(p.capacity_mwhth) * 3600000.0 / OIL_ENTHALPY_KJ_KG / OIL_HOT_DENSITY_KG_M3
			var tank_volume := hot_volume / 0.8
			var diameter := pow(4.0 * tank_volume / PI, 1.0 / 3.0)
			_modules(result, 1, Vector3(2.0 * diameter + 2.0, diameter + 0.6, diameter + 1.0), "Direct Therminol 66 two-tank teaching storage, 300/200°C. Each tank accommodates the entire hot-volume inventory plus 20% freeboard. Enthalpy difference 238 kJ/kg; hot density 809 kg/m³. Two metres tank separation; no water or molten salt.", include_origins)
			result.tank_diameter_m = diameter
			result.tank_height_m = diameter
			result.hot_full_volume_m3_each = hot_volume
			result.tank_geometric_volume_m3_each = tank_volume
			result.oil_inventory_mass_kg = hot_volume * OIL_HOT_DENSITY_KG_M3
			result.freeboard_fraction = 0.2
			return result
		"oil_water_exchanger":
			return _modules(result, maxi(1, int(ceil(float(p.capacity_mwth) / 0.1 - 0.000000001))), Vector3(3.0, 1.8, 2.0), "Original 0.1 MWth oil/water heat-transfer skid; 300/200°C oil isolated from 90/60°C water; AC circulation pump. Dimensions and rated duty are teaching assumptions.", include_origins)
		"battery":
			var count: int = maxi(1, int(ceil(maxf(float(p.capacity_mwh) / 5.015, maxf(float(p.charge_mw) / 2.5, float(p.discharge_mw) / 2.5)))))
			result.reference_capacity_mwh_per_module = 5.015
			result.reference_power_mw_per_module = 2.5
			return _modules(result, count, Vector3(6.058, 2.896, 2.438), "Sungrow ST5015kWh-2500kW-2h参考箱体；实际教学可用容量及总充放功率仍由原参数限定。", include_origins)
		"battery_sodium", "battery_flow", "caes_aboveground", "liquid_air_store", "hydrogen_storage_system", "solid_thermal_store":
			# Technology-specific site envelopes are teaching assumptions, not pressure-vessel sizing.
			var specifications := {
				"battery_sodium": [5.0, 2.5, Vector3(6.5, 3.0, 3.2)],
				"battery_flow": [10.0, 2.0, Vector3(14.0, 5.5, 10.0)],
				"caes_aboveground": [0.25, 0.1, Vector3(24.0, 6.0, 18.0)],
				"liquid_air_store": [10.0, 3.0, Vector3(20.0, 11.0, 16.0)],
				"hydrogen_storage_system": [20.0, 2.0, Vector3(24.0, 5.0, 16.0)],
				"solid_thermal_store": [4.0, 2.0, Vector3(8.0, 5.0, 6.0)]}
			var spec: Array = specifications[kind]
			var thermal := kind == "solid_thermal_store"
			var capacity_key := "capacity_mwhth" if thermal else "capacity_mwh"
			var charge_key := "charge_mwth" if thermal else "charge_mw"
			var discharge_key := "discharge_mwth" if thermal else "discharge_mw"
			var count := maxi(1, int(ceil(maxf(float(p[capacity_key]) / float(spec[0]), maxf(float(p[charge_key]), float(p[discharge_key])) / float(spec[1])))))
			result.reference_capacity_per_module = spec[0]
			result.reference_power_per_module = spec[1]
			result.geometry_is_teaching_assumption = true
			return _modules(result, count, spec[2], "完整储能设施教学单元；容量/功率增加会增加模块与占地。尺寸不用于推导实际压力、介质质量或工业安全距离；不是厂家CAD或工程设计。", include_origins)
		"station":
			result.reference_capacity_mw_per_module = 2.0
			return _modules(result, maxi(1, int(ceil(float(p.capacity_mw) / 2.0))), Vector3(6.813, 2.941, 5.538), "SMA MV Power Station 2000SC带平台参考；2 MVA按功率因数1映射2 MW；不重复增加逆变容量。", include_origins)
		"electric_boiler":
			result.reference_power_mw_per_module = 2.0
			return _modules(result, maxi(1, int(ceil(float(p.rated_electric_mw) / 2.0))), Vector3(4.0, 2.5, 2.5), "ECOTHERM 2000 kW电热水锅炉外形参考；功率为电输入，热输出另乘效率。", include_origins)
		"fuel_boiler":
			result.reference_fuel_input_mw_per_module = 2.0
			result.fuel_energy_basis = "LHV"
			result.reference_boiler_body_dimensions_m = Vector3(3.48, 1.73, 1.51)
			# Source-sized casing; original burner, gas train and 4.5 m flue stack.
			# Each full module is authored at metres; never squeeze capacity into a site.
			return _modules(result, maxi(1, int(ceil(float(p.rated_fuel_mw) / 2.0))), Vector3(5.0, 4.5, 3.0), "参考Bosch Uni 3000 F 1850 kW热水锅炉3.480×1.510×1.730 m外形；5×3×4.5 m燃烧器/燃气阀组/烟道底撬为原创教学单元，非厂家CAD；每模块2 MW_LHV燃料输入为教学额定。详见FUEL_BOILER_SOURCES.md。", include_origins)
		"thermal_store":
			result.reference_capacity_mwhth_per_module = 4.0
			# Authored vessel, roof and top fittings reach 7.635 m above grade.
			return _modules(result, maxi(1, int(ceil(float(p.capacity_mwhth) / 4.0))), Vector3(8.5, 7.635, 5.0), "4 MWhth双水罐教学模块，约125 m³名义水容积；90/60°C等效库存，不宣称厂家标准罐型。", include_origins)
		"heat_exchanger":
			result.reference_power_mwth_per_module = 2.0
			return _modules(result, maxi(1, int(ceil(float(p.capacity_mwth) / 2.0))), Vector3(3.0, 1.8, 2.0), "参考Alfa Laval M10系列外形量级；含泵阀底撬的3×2×1.8 m单元和2 MWth额定均为教学假设。", include_origins)
		"solar_thermal": return _solar_thermal(result, p, include_origins)
		"pv": return _pv(result, p, include_origins)
		"wind":
			result.module_count = 1
			result.columns = 1; result.rows = 1; result.layout_columns = 1; result.layout_rows = 1
			result.unit_dimensions_m = Vector3(18.0, float(p.hub_height_m), 18.0)
			result.module_dimensions_m = result.unit_dimensions_m
			result.body_dimensions_m = result.unit_dimensions_m
			result.body_area_m2 = 18.0 * 18.0
			result.foundation_dimensions_m = Vector3(18.0, 0.0, 18.0)
			result.land_dimensions_m = Vector3(32.0, 0.0, 32.0)
			result.land_area_m2 = 32.0 * 32.0
			result.maintenance_margin_m = 7.0
			result.rotor_radius_m = float(p.rotor_diameter_m) * 0.5
			result.rotor_swept_area_m2 = PI * result.rotor_radius_m * result.rotor_radius_m
			result.rotor_swept_dimensions_m = Vector3(float(p.rotor_diameter_m), float(p.rotor_diameter_m), float(p.rotor_diameter_m))
			_set_radius(result, maxf(result.rotor_radius_m + 7.0, Vector2(result.land_dimensions_m.x, result.land_dimensions_m.z).length() * 0.5))
			_set_origins(result, include_origins)
			result.description = "基础投影324 m²（18×18 m教学设定）；维护区1024 m²；转子扫掠半径%.1f m；避让圆不是建筑面积。" % result.rotor_radius_m
			result.source_note = "基础及7 m维护预留为教学假设；转子直径、轮毂高度沿用设备参数。基础/塔架与转子运动包络分开计量。"
		"tower_station_preview", "tower_station":
			result.module_count = 1
			result.columns = 1; result.rows = 1; result.layout_columns = 1; result.layout_rows = 1
			result.unit_dimensions_m = Vector3(TOWER_SITE_DIMENSIONS_M.x, TOWER_HEIGHT_M, TOWER_SITE_DIMENSIONS_M.z)
			result.module_dimensions_m = result.unit_dimensions_m
			result.body_dimensions_m = result.unit_dimensions_m
			result.body_area_m2 = 0.0
			result.land_dimensions_m = TOWER_SITE_DIMENSIONS_M
			result.land_area_m2 = 25600.0
			result.interior_dimensions_m = TOWER_INTERIOR_DIMENSIONS_M
			result.interior_area_m2 = 14400.0
			result.is_site_container = true
			result.commissioned = kind == "tower_station"
			result.preview_only = kind == "tower_station_preview"
			result.tower_height_m = TOWER_HEIGHT_M
			result.heliostat_count = tower_mirror_layout().size()
			result.ring_radii_m = TOWER_RING_RADII_M
			result.sun_direction = TOWER_SUN_DIRECTION
			result.receiver_target_m = TOWER_RECEIVER_M
			result.tracking_mode = "weather_bisector_teaching_optics" if kind == "tower_station" else "fixed_teaching_snapshot_not_realtime"
			result.mirror_dimensions_m = Vector3(4.0, 0.12, 4.0)
			result.mirror_aperture_area_m2 = TOWER_MIRROR_APERTURE_M2
			result.description = "塔式光热站未投运预览：院区160×160 m（25600 m²），净区120×120 m（14400 m²，包含于院区）；塔高25 m；100面4×4 m定日镜，四圈半径18/30/42/54 m，镜面面积1600 m²。无能量端口、无发电。"
			result.source_note = "原创教学总图，非工程化聚光电站设计；同心错列镜环及径向道路；固定教学太阳方向，镜法线为太阳与接收器方向的角平分线，非实时跟踪，不承诺光学效率或防阴影。物理尺度0.1 world/m，不因相机或内部视图改变。"
			if kind == "tower_station":
				result.description = "塔式熔盐运行站：院区160×160m（25600m²），内区120×120m包含于院区；25m塔、四圈100面4×4m镜、总镜面积1600m²。独立565/290°C盐回路与有限库存。"
				result.source_note = "原教学米制镜场，按天气太阳方向作角平分线跟踪；光学功率仍为固定等效效率，未计算逐镜遮挡/截获。运行设备按真实占地避让镜扫掠区。"
			_set_radius(result, Vector2(TOWER_SITE_DIMENSIONS_M.x, TOWER_SITE_DIMENSIONS_M.z).length() * .5)
			_set_origins(result, include_origins)
		"thermal_station":
			result.module_count = 1
			result.columns = 1; result.rows = 1; result.layout_columns = 1; result.layout_rows = 1
			# The open-air site model's tallest authored feature reaches 9.1 m.
			result.unit_dimensions_m = Vector3(80.0, 9.1, 60.0)
			result.module_dimensions_m = result.unit_dimensions_m
			result.body_dimensions_m = result.unit_dimensions_m
			result.land_dimensions_m = Vector3(80.0, 0.0, 60.0)
			result.land_area_m2 = 4800.0
			result.interior_dimensions_m = Vector3(48.0, 0.0, 48.0)
			result.interior_area_m2 = 2304.0
			result.is_site_container = true
			# This is an open-air site boundary, not an 80x60 m building.
			result.body_area_m2 = 0.0
			_set_radius(result, 50.0)
			_set_origins(result, include_origins)
			result.description = "电热站院区80×60 m，占地4800 m²；内含48×48 m净布置区2304 m²，不重复相加，不当作建筑面积。"
			result.source_note = "厂区、净区及余量为教学设计；外接圆半径50 m包含全部院区角点。内部与外部共用0.1 world/m，观察只改变相机。"
		"load", "heat_demand":
			result.is_service_marker = true
			# 0.25 world is interaction separation, not a physical site footprint.
			result.marker_radius_world = 0.25
			_set_radius(result, 2.5)
			result.description = "外部服务连接点；未建模实际建筑，占地不计（0 m²）；标记拾取/间隔半径0.25 world。"
			result.source_note = "抽象负荷边界标记，不表示住宅、工厂或真实用地。"
	return result

static func _pv(result: Dictionary, p: Dictionary, include_origins: bool = true) -> Dictionary:
	var count: int = maxi(1, int(ceil(float(p.dc_capacity_mw) * 1000000.0 / PANEL_RATING_W)))
	var columns: int = maxi(1, int(ceil(sqrt(float(count) * PV_ROW_PITCH_M / PV_COLUMN_PITCH_M))))
	columns = mini(columns, count)
	var rows: int = int(ceil(float(count) / float(columns)))
	var projected_length: float = PANEL_LENGTH_M * cos(deg_to_rad(PV_TILT_DEG)) + PANEL_THICKNESS_M * sin(deg_to_rad(PV_TILT_DEG))
	var projected_height: float = PANEL_LENGTH_M * sin(deg_to_rad(PV_TILT_DEG)) + PANEL_THICKNESS_M * cos(deg_to_rad(PV_TILT_DEG))
	result.module_count = count
	result.panel_count = count
	result.columns = columns; result.rows = rows
	result.layout_columns = columns; result.layout_rows = rows
	result.panel_width_m = PANEL_WIDTH_M
	result.panel_length_m = PANEL_LENGTH_M
	result.panel_thickness_m = PANEL_THICKNESS_M
	result.panel_rating_w = PANEL_RATING_W
	result.tilt_deg = PV_TILT_DEG
	result.column_pitch_m = PV_COLUMN_PITCH_M
	result.row_pitch_m = PV_ROW_PITCH_M
	result.unit_dimensions_m = Vector3(PANEL_WIDTH_M, PANEL_THICKNESS_M, PANEL_LENGTH_M)
	result.module_dimensions_m = result.unit_dimensions_m
	result.grid_origin_m = Vector3(-float(columns - 1) * PV_COLUMN_PITCH_M * 0.5, 0.6 + projected_height * 0.5, -float(rows - 1) * PV_ROW_PITCH_M * 0.5)
	result.body_dimensions_m = Vector3(float(columns - 1) * PV_COLUMN_PITCH_M + PANEL_WIDTH_M, 0.6 + projected_height, float(rows - 1) * PV_ROW_PITCH_M + projected_length)
	result.module_area_m2 = float(count) * PANEL_WIDTH_M * PANEL_LENGTH_M
	result.body_area_m2 = float(count) * PANEL_WIDTH_M * projected_length
	result.installed_dc_mwp = float(count) * PANEL_RATING_W / 1000000.0
	result.land_dimensions_m = Vector3(result.body_dimensions_m.x + PV_MARGIN_M * 2.0, 0.0, result.body_dimensions_m.z + PV_MARGIN_M * 2.0)
	result.land_area_m2 = result.land_dimensions_m.x * result.land_dimensions_m.z
	result.maintenance_margin_m = PV_MARGIN_M
	_set_radius(result, Vector2(result.land_dimensions_m.x, result.land_dimensions_m.z).length() * 0.5)
	_set_origins(result, include_origins)
	result.description = "%d片550 Wp组件，%d列×%d排（末排可不满）；组件面面积%.2f m²；含排距及边带用地%.2f m²；控制额定仍为%.4f MWdc。" % [count, columns, rows, result.module_area_m2, result.land_area_m2, float(p.dc_capacity_mw)]
	result.source_note = "Jinko JKM550M-72HL4-V F3参考2.278×1.134×0.035 m、550 Wp；25°倾角、1.2 m列距、5 m排距、4 m四周边带为教学假设，不保证无阴影或工程合规。"
	return result

## Full installed collectors remain at their physical size even if the final
## collector is only partly credited by the requested aggregate absorber area.
static func _solar_thermal(result: Dictionary, p: Dictionary, include_origins: bool = true) -> Dictionary:
	var requested: float = float(p.absorber_area_m2)
	var count: int = maxi(1, int(ceil(requested / SOLAR_ABSORBER_M2 - 0.000000001)))
	var columns: int = mini(count, maxi(1, int(ceil(sqrt(float(count) * SOLAR_ROW_PITCH_M / SOLAR_COLUMN_PITCH_M)))))
	var rows: int = int(ceil(float(count) / float(columns)))
	var depth: float = SOLAR_LENGTH_M * cos(deg_to_rad(SOLAR_TILT_DEG)) + SOLAR_THICKNESS_M * sin(deg_to_rad(SOLAR_TILT_DEG))
	var height: float = SOLAR_BOTTOM_M + SOLAR_LENGTH_M * sin(deg_to_rad(SOLAR_TILT_DEG)) + SOLAR_THICKNESS_M * cos(deg_to_rad(SOLAR_TILT_DEG))
	result.module_count = count
	result.tube_count = 24 * count
	result.columns = columns; result.rows = rows
	result.layout_columns = columns; result.layout_rows = rows
	result.column_pitch_m = SOLAR_COLUMN_PITCH_M; result.row_pitch_m = SOLAR_ROW_PITCH_M
	result.tilt_deg = SOLAR_TILT_DEG
	result.collector_dimensions_m = Vector3(SOLAR_WIDTH_M, SOLAR_THICKNESS_M, SOLAR_LENGTH_M)
	result.unit_dimensions_m = Vector3(SOLAR_WIDTH_M, height, depth)
	result.module_dimensions_m = result.unit_dimensions_m
	result.reference_absorber_area_m2_per_module = SOLAR_ABSORBER_M2
	result.requested_absorber_area_m2 = requested
	result.installed_absorber_area_m2 = count * SOLAR_ABSORBER_M2
	result.installed_aperture_area_m2 = count * SOLAR_APERTURE_M2
	result.installed_gross_area_m2 = count * SOLAR_GROSS_M2
	result.last_module_utilization = clampf((requested - (count - 1) * SOLAR_ABSORBER_M2) / SOLAR_ABSORBER_M2, 0.0, 1.0)
	result.grid_origin_m = Vector3(-float(columns - 1) * SOLAR_COLUMN_PITCH_M * 0.5, 0, -float(rows - 1) * SOLAR_ROW_PITCH_M * 0.5)
	result.body_dimensions_m = Vector3((columns - 1) * SOLAR_COLUMN_PITCH_M + SOLAR_WIDTH_M, height, (rows - 1) * SOLAR_ROW_PITCH_M + depth)
	result.body_area_m2 = count * SOLAR_WIDTH_M * depth
	result.land_dimensions_m = Vector3(result.body_dimensions_m.x + 4.0, 0, result.body_dimensions_m.z + 4.0)
	result.land_area_m2 = result.land_dimensions_m.x * result.land_dimensions_m.z
	result.maintenance_margin_m = 2.0
	_set_radius(result, Vector2(result.land_dimensions_m.x, result.land_dimensions_m.z).length() * 0.5)
	_set_origins(result, include_origins)
	result.description = "%d组×24根真空管；有效吸热面积%.2f m²，安装吸热/孔径/毛面积%.2f/%.2f/%.2f m²；末组利用%.1f%%；含排距及检修用地%.2f m²。" % [count, requested, result.installed_absorber_area_m2, result.installed_aperture_area_m2, result.installed_gross_area_m2, 100.0 * result.last_module_utilization, result.land_area_m2]
	result.source_note = "Vitosol 200-T SP2A历史24管规格2.061×2.241×0.150 m；每组吸热3.03、孔径3.19、毛面积4.62 m²。固定30°、底部净高0.35 m、列距2.4 m、排距3.6 m及四周2 m检修区为教学假设，不保证无阴影或工程合规；非聚光、非光伏。"
	return result

## Teaching collision envelope: infrastructure must not occupy moving mirrors.
static func tower_equipment_position_error(kind: String, params: Dictionary, position_world: Vector2) -> String:
	if kind == "solar_tower_receiver":
		return "" if position_world.length() < .00001 else "塔接收器固定在塔中心"
	var d := profile(kind, params, false)
	if not d.valid: return d.error
	var point := position_world * 10.0
	var half: Vector2 = Vector2(d.land_dimensions_m.x,d.land_dimensions_m.z)*.5
	for mirror in tower_mirror_layout():
		var center: Vector3 = mirror.center_m
		var nearest := Vector2(clampf(center.x,point.x-half.x,point.x+half.x),clampf(center.z,point.y-half.y,point.y+half.y))
		if nearest.distance_to(Vector2(center.x,center.z)) < sqrt(8.01): return "设备占地进入定日镜扫掠区"
	if absf(point.x) < half.x+4.0 and absf(point.y) < half.y+4.0: return "设备占地进入塔基区"
	if absf(point.x-48) < half.x+7.1 and absf(point.y-48) < half.y+4.1: return "设备占地进入服务建筑"
	return ""
