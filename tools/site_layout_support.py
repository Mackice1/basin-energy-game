"""Versioned finite site envelopes shared with the Godot runtime.

The checked-in JSON is the only source of bounds and geometry coefficients.
These assessments never merge catalog defaults, modify a device, clamp its
ratings or inventory, or assign a migration marker. An operable assessment is
not engineering certification: the caller must independently verify as-built
geometry and collisions before assigning ``reference_size_v1``.

Mass/volume results are static sizing metadata, not dispatch physics. They do
not introduce compression work, pressure-dependent delivery, hidden inventory,
temperature dynamics or additional conversion losses.
"""
from __future__ import annotations

import copy
import json
import math
from pathlib import Path


SPEC_ID = "site_layout_support_v1"
SPEC_VERSION = 1
SITE_GEOMETRY_PROFILE = "reference_size_v1"
SPEC_PATH = Path(__file__).resolve().parents[1] / "data/site_layout_support_v1.json"
_cache = {}


def _data():
    """Private read-only cache; public APIs return only defensive copies."""
    global _cache
    if not _cache:
        try:
            parsed = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, ValueError):
            return {}
        if (isinstance(parsed, dict)
                and parsed.get("spec_id") == SPEC_ID
                and parsed.get("spec_version") == SPEC_VERSION
                and parsed.get("site_geometry_profile") == SITE_GEOMETRY_PROFILE
                and isinstance(parsed.get("kinds"), dict)):
            _cache = parsed
    return _cache


def spec():
    """Return a defensive copy, or an empty dictionary for an unusable spec."""
    return copy.deepcopy(_data())


def shared_spec_version():
    return SPEC_VERSION


def supported_kinds():
    return list(_data().get("kinds", {}))


def parameter_limits(kind):
    return copy.deepcopy(_data().get("kinds", {}).get(kind, {}).get("bounds", {}))


def geometry(kind):
    """Return the raw shared geometry contract, not a capacity-scaled layout."""
    return copy.deepcopy(_data().get("kinds", {}).get(kind, {}).get("geometry", {}))


def _number(value):
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return False
    try:
        return math.isfinite(float(value))
    except (OverflowError, ValueError):
        return False


def _issue(code, parameter, message):
    return {"code": code, "parameter": parameter, "message": message}


def _base():
    return {
        "spec_id": SPEC_ID, "spec_version": SPEC_VERSION,
        "profile_id": SITE_GEOMETRY_PROFILE, "id": None, "kind": "",
        "applicable": True, "supported": True, "needs_migration": False,
        "operable": True, "issues": [], "supported_bounds": {}, "required_geometry": {},
    }


def _invalid(result, issue):
    result["supported"] = False
    result["needs_migration"] = True
    result["operable"] = False
    result["issues"].append(issue)
    return result


def assess_device(device):
    """Read a complete device without modifying, normalizing or defaulting it.

    Missing/unsupported site markers require explicit migration independently
    of parameter support. Unknown kinds are unassessed, not certified.
    """
    out = _base()
    data = _data()
    if not data:
        return _invalid(out, _issue("invalid_spec", "", "Site layout specification could not be loaded."))
    if not isinstance(device, dict):
        return _invalid(out, _issue("invalid_device", "", "Device must be a dictionary."))
    out["id"] = copy.deepcopy(device.get("id"))
    kind = device.get("kind")
    if not isinstance(kind, str) or not kind:
        return _invalid(out, _issue("invalid_device_kind", "kind", "Device kind must be a nonempty string."))
    out["kind"] = kind
    if kind not in data["kinds"]:
        out["applicable"] = False
        return out
    out["supported_bounds"] = parameter_limits(kind)
    params = device.get("params")
    if not isinstance(params, dict):
        return _invalid(out, _issue("invalid_parameters", "params", "Device params must be a dictionary."))
    for key, bound in out["supported_bounds"].items():
        if key not in params:
            out["issues"].append(_issue("missing_parameter", key, "Layout parameter is missing."))
        elif not _number(params[key]):
            out["issues"].append(_issue("invalid_parameter", key, "Layout parameter must be a finite number."))
        elif (float(params[key]) < float(bound["min"])
              or float(params[key]) > float(bound["max"])
              or (bound.get("min_exclusive", False) and float(params[key]) == float(bound["min"]))):
            problem = _issue("outside_supported_range", key,
                             "Layout parameter is outside the supported site envelope.")
            problem["actual"] = params[key]
            problem["maximum"] = bound["max"]
            out["issues"].append(problem)
    if (kind == "battery_flow" and device.get("site_geometry_profile") == SITE_GEOMETRY_PROFILE
            and "geometry_profile" in device and device["geometry_profile"] != "flow_process_v2"):
        out["issues"].append(_issue("incompatible_geometry_profile", "geometry_profile",
                                  "Reference-size flow storage requires flow_process_v2; old icon geometry must remain in legacy compatibility until migrated."))
    out["supported"] = not out["issues"]
    if out["supported"]:
        out["required_geometry"] = required_geometry(kind, params)
        if ("energy_screen_pass" in out["required_geometry"]
                and not out["required_geometry"]["energy_screen_pass"]):
            out["supported"] = False
            problem = _issue("energy_screen_exceeded", "discharge_efficiency",
                             "Capacity times discharge efficiency exceeds the finite net-electric geometry screen.")
            problem["actual"] = out["required_geometry"]["requested_net_electric_mwh"]
            problem["maximum"] = out["required_geometry"]["net_electric_screen_mwh"]
            out["issues"].append(problem)
        if ("hardware_capacity_sufficient" in out["required_geometry"]
                and not out["required_geometry"]["hardware_capacity_sufficient"]):
            out["supported"] = False
            out["issues"].append(_issue("insufficient_spec_geometry", "",
                                        "Reference hardware does not meet its own minimum volume."))
    if device.get("site_geometry_profile") != SITE_GEOMETRY_PROFILE:
        problem = _issue(
            "profile_migration_required", "site_geometry_profile",
            "Explicit site geometry migration is required; stored ratings and inventory must remain unchanged.",
        )
        if isinstance(device.get("site_geometry_profile"), str):
            problem["actual"] = device["site_geometry_profile"]
        out["issues"].append(problem)
        out["needs_migration"] = True
    out["needs_migration"] = out["needs_migration"] or not out["supported"]
    out["operable"] = out["supported"] and not out["needs_migration"]
    return out


def assess_world(devices):
    """Aggregate assessments in input order without touching any device."""
    out = {
        "spec_id": SPEC_ID, "spec_version": SPEC_VERSION, "profile_id": SITE_GEOMETRY_PROFILE,
        "supported": True, "needs_migration": False, "operable": True, "devices": [], "issues": [],
    }
    if not isinstance(devices, list):
        out.update(supported=False, needs_migration=True, operable=False)
        out["issues"].append(_issue("invalid_devices", "devices", "Devices must be an array."))
        return out
    for device in devices:
        item = assess_device(device)
        out["devices"].append(item)
        out["supported"] = out["supported"] and item["supported"]
        out["needs_migration"] = out["needs_migration"] or item["needs_migration"]
        out["operable"] = out["operable"] and item["operable"]
        for problem in item["issues"]:
            issue = copy.deepcopy(problem)
            issue["device_id"] = copy.deepcopy(item["id"])
            out["issues"].append(issue)
    return out


def validate_for_model(devices, require_reference=False):
    """Gate explicitly opted-in layouts without changing historical requests.

    Presence of any device marker, even null or unknown, makes the entire
    world strict. Partial migration cannot fall back to legacy compatibility.
    """
    enabled = require_reference or not isinstance(devices, list)
    if isinstance(devices, list):
        enabled = enabled or any(isinstance(item, dict) and "site_geometry_profile" in item
                                 for item in devices)
    if enabled:
        result = assess_world(devices)
        result.update(mode="reference_layout", applied=True)
        return result
    return {
        "spec_id": SPEC_ID, "spec_version": SPEC_VERSION, "profile_id": SITE_GEOMETRY_PROFILE,
        "supported": True, "needs_migration": False, "operable": True, "devices": [], "issues": [],
        "mode": "legacy_compatibility", "applied": False,
    }


def required_geometry(kind, params):
    """Compute static NET internal requirements using the full installed size.

    Lower requested capacity reduces the working inventory requirement, never
    the installed hardware. Two full-inventory tanks copy volume, not mass.
    Capsule straight length excludes both hemispherical heads.
    """
    g = geometry(kind)
    if not g:
        return {}
    g["as_built_verified"] = False
    if g["method"] == "bounded_existing_layout":
        return g
    if g["method"] in ("compressed_air_static_screen", "liquid_air_static_screen"):
        return _air_energy_screen(g, params)
    key = g["capacity_key"]
    if not _number(params.get(key)):
        return {}
    requested = float(params[key])
    installed = float(g["installed_capacity"])
    g["requested_capacity"] = requested
    if g["method"] == "gas":
        mass_per_capacity = float(g["capacity_to_mass_kg"])
        density = float(g["sizing_density_kg_m3"])
    else:
        specific_energy = float(g.get("specific_enthalpy_difference_j_kg", 0.0))
        if g["method"] == "sensible":
            specific_energy = float(g["specific_heat_j_kg_k"]) * (
                float(g["hot_temperature_c"]) - float(g["cold_temperature_c"])
            )
        mass_per_capacity = 3600000000.0 / specific_energy
        density = float(g["density_kg_m3"])
    g["required_material_mass_kg"] = requested * mass_per_capacity
    g["minimum_installed_material_mass_kg"] = installed * mass_per_capacity
    g["required_effective_volume_m3"] = g["required_material_mass_kg"] / density
    g["minimum_installed_effective_volume_m3"] = g["minimum_installed_material_mass_kg"] / density
    copies = float(g.get("inventory_volume_copies", 1.0))
    fraction = float(g.get("material_volume_fraction", 1.0))
    g["minimum_container_volume_m3"] = g["minimum_installed_effective_volume_m3"] * copies / fraction
    hw = g["hardware"]
    n = float(hw["count"])
    hardware_volume = 0.0
    shape = hw["shape"]
    if shape == "capsule_bank":
        radius = float(hw["internal_radius_m"])
        hardware_volume = n * (math.pi * radius * radius * float(hw["straight_length_m"])
                               + 4.0 / 3.0 * math.pi * radius * radius * radius)
    elif shape == "parallel_cylinders":
        radius = float(hw["internal_radius_m"])
        hardware_volume = n * math.pi * radius * radius * float(hw["straight_length_m"])
    elif shape == "solid_blocks":
        dims = hw["net_block_dimensions_m"]
        hardware_volume = n * float(dims[0]) * float(dims[1]) * float(dims[2])
    elif shape == "ellipsoid":
        dims = hw["internal_diameters_m"]
        hardware_volume = n * math.pi / 6.0 * float(dims[0]) * float(dims[1]) * float(dims[2])
        fraction = float(hw["usable_volume_fraction"])
        g["minimum_container_volume_m3"] = g["minimum_installed_effective_volume_m3"] / fraction
    elif shape == "two_tanks_derived":
        each = float(g["minimum_container_volume_m3"]) / n
        ratio = float(hw["height_to_diameter"])
        diameter = math.pow(4.0 * each / (math.pi * ratio), 1.0 / 3.0)
        hw["internal_radius_m"] = diameter * 0.5
        hw["straight_length_m"] = diameter * ratio
        hardware_volume = n * math.pi * diameter * diameter * 0.25 * diameter * ratio
    g["hardware_internal_volume_m3"] = hardware_volume
    g["hardware_effective_volume_m3"] = hardware_volume * fraction
    g["hardware_capacity_sufficient"] = (
        g["hardware_effective_volume_m3"] + 1e-9 >= g["minimum_installed_effective_volume_m3"] * copies
    )
    return g


def _air_energy_screen(g, params):
    """Necessary static volume/AC check; never a pressure or SOC mapping."""
    if not _number(params.get("capacity_mwh")) or not _number(params.get("discharge_efficiency")):
        return {}
    hw = g["hardware"]
    volume = float(hw["count"]) * math.pi * math.pow(float(hw["internal_radius_m"]), 2.0) * float(hw["straight_length_m"])
    fraction = float(g["material_volume_fraction"])
    g["hardware_internal_volume_m3"] = volume
    g["hardware_effective_volume_m3"] = volume * fraction
    g["requested_capacity"] = float(params["capacity_mwh"])
    g["requested_net_electric_mwh"] = float(params["capacity_mwh"]) * float(params["discharge_efficiency"])
    if g["method"] == "compressed_air_static_screen":
        pressure = float(g["reference_pressure_bar_abs"]) * 100000.0
        ambient = float(g["ambient_pressure_bar_abs"]) * 100000.0
        ratio = ambient / pressure
        gamma = float(g["air_heat_capacity_ratio"])
        output_density = pressure / (gamma - 1.0) * (1.0 + (gamma - 1.0) * ratio - gamma * math.pow(ratio, (gamma - 1.0) / gamma)) / 3600000000.0
        g["ideal_isothermal_availability_mwh"] = volume * (pressure * math.log(pressure / ambient) - pressure + ambient) / 3600000000.0
        g["ideal_adiabatic_no_reheat_mwh"] = volume * output_density
        g["reference_full_pressure_gas_mass_kg"] = pressure * volume / (float(g["ideal_air_gas_constant_j_kg_k"]) * float(g["reference_temperature_k"]))
    else:
        g["reference_maximum_liquid_mass_kg"] = volume * fraction * float(g["density_kg_m3"])
        output_density = float(g["density_kg_m3"]) * float(g["net_specific_output_screen_kj_kg"]) / 3600000.0
        g["required_liquid_mass_kg"] = g["requested_net_electric_mwh"] * 3600000.0 / float(g["net_specific_output_screen_kj_kg"])
    g["net_electric_screen_mwh"] = volume * fraction * output_density
    g["required_effective_volume_m3"] = g["requested_net_electric_mwh"] / output_density
    g["required_container_volume_m3"] = g["required_effective_volume_m3"] / fraction
    g["energy_screen_pass"] = g["requested_net_electric_mwh"] <= g["net_electric_screen_mwh"]
    g["screen_is_performance_guarantee"] = False
    g["pressure_vessel_certified"] = False
    return g
