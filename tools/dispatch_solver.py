#!/usr/bin/env python3
"""Fixed-capacity radial dispatch through the real GLPK `glpsol` executable.

Only the Python standard library is required. See DISPATCH_SOLVER.md for the
JSON contract, objective and deliberate modelling limits. No shell or network
access is used. Import solve(snapshot) or run --input FILE --output FILE.
"""
from __future__ import annotations

import argparse
import copy
import json
import math
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

SCHEMA_VERSION = 3
# Schema 7 adds bounded, lumped storage models; earlier schema contracts stay intact.
EXPANDED_ELECTRIC_STORAGE_KINDS = ("battery_sodium", "battery_flow", "caes_aboveground",
                                   "liquid_air_store", "hydrogen_storage_system")
EXPANDED_STORAGE_KINDS = EXPANDED_ELECTRIC_STORAGE_KINDS + ("solid_thermal_store",)
ELECTRIC_STORAGE_KINDS = ("battery",) + EXPANDED_ELECTRIC_STORAGE_KINDS
WATER_STORAGE_KINDS = ("thermal_store", "solid_thermal_store")
THERMAL_STORAGE_KINDS = WATER_STORAGE_KINDS + ("high_temp_store", "molten_salt_store")
STORAGE_KINDS = ELECTRIC_STORAGE_KINDS + THERMAL_STORAGE_KINDS
HYDROGEN_LHV_KWH_PER_KG = 33.33
THERMAL_PROFILE = "thermal_stage1_v1"
PRIMARY_GRADE = "hw_primary_90_60"
SECONDARY_GRADE = "hw_secondary_70_40"
HIGH_TEMP_PROFILE = "high_temp_stage1_v1"
OIL_GRADE = "oil_300_200"
HIGH_TEMP_KINDS = ("parabolic_trough", "high_temp_store", "oil_water_exchanger")
RANKINE_PROFILE = "rankine_stage1_v1"
TOWER_PROFILE = "tower_stage1_v1"
SALT_GRADE = "salt_565_290"
TOWER_KINDS = ("solar_tower_receiver", "molten_salt_store", "salt_steam_generator")
RANKINE_KINDS = ("salt_steam_generator", "steam_generator", "steam_turbine", "steam_condenser", "feedwater_pump")
RANKINE_AUX_KINDS = ("salt_steam_generator", "steam_generator", "steam_condenser", "feedwater_pump")
THERMAL_KINDS = TOWER_KINDS + RANKINE_KINDS + HIGH_TEMP_KINDS + ("solar_thermal", "fuel_boiler", "electric_boiler", "thermal_store", "solid_thermal_store", "heat_exchanger", "heat_demand")
THERMAL_ROUTES = {
    ("solar_thermal", "heat_exchanger"): ("heat_out", "hot_in", PRIMARY_GRADE),
    ("solar_thermal", "thermal_store"): ("heat_out", "heat_in", PRIMARY_GRADE),
    ("fuel_boiler", "heat_exchanger"): ("heat_out", "hot_in", PRIMARY_GRADE),
    ("fuel_boiler", "thermal_store"): ("heat_out", "heat_in", PRIMARY_GRADE),
    ("electric_boiler", "heat_exchanger"): ("heat_out", "hot_in", PRIMARY_GRADE),
    ("electric_boiler", "thermal_store"): ("heat_out", "heat_in", PRIMARY_GRADE),
    ("thermal_store", "heat_exchanger"): ("heat_out", "hot_in", PRIMARY_GRADE),
    ("heat_exchanger", "heat_demand"): ("warm_out", "heat_in", SECONDARY_GRADE),
}
ABS_TOL = 2e-6
REL_TOL = 2e-7
MAX_STEPS = 10000
MAX_DEVICES = 2000
MAX_VARIABLES = 300000
DEFAULTS = {
    "wind": {"rated_mw": 5.0, "rotor_diameter_m": 126.0, "hub_height_m": 90.0,
             "cut_in_mps": 3.0, "rated_speed_mps": 11.4, "cut_out_mps": 25.0,
             "drivetrain_efficiency": .944, "cp_max": .49, "shear_exponent": .14,
             "reference_air_density_kgm3": 1.225, "power_curve_kw": []},
    "pv": {"dc_capacity_mw": 1.2, "inverter_capacity_mw": 1.0,
           "inverter_efficiency": .96, "temp_coefficient_per_c": -.004,
           "faiman_u0": 25.0, "faiman_u1": 6.84, "dc_loss_fraction": .02,
           "cell_delta_c_at_1000": 3.0},
    "station": {"capacity_mw": 4.0, "loss_fraction": .01},
    "load": {"demand_mw": 2.0, "priority": 10},
    "battery": {"capacity_mwh": 10.0, "charge_mw": 3.0, "discharge_mw": 3.0,
                "charge_efficiency": .9, "discharge_efficiency": .9,
                "self_discharge_per_h": 0.0, "initial_soc": .5},
}
RANGES = {
    "wind": {"rated_mw": (0, 1000, True), "rotor_diameter_m": (0, 1000, True),
             "hub_height_m": (0, 2000, True), "cut_in_mps": (0, 99),
             "rated_speed_mps": (0, 100, True), "cut_out_mps": (0, 150, True),
             "drivetrain_efficiency": (0, 1, True), "cp_max": (0, 16/27, True),
             "shear_exponent": (0, 1), "reference_air_density_kgm3": (.5, 2)},
    "pv": {"dc_capacity_mw": (0, 10000, True), "inverter_capacity_mw": (0, 10000, True),
           "inverter_efficiency": (0, 1, True), "temp_coefficient_per_c": (-.02, 0),
           "faiman_u0": (0, 500, True), "faiman_u1": (0, 100),
           "dc_loss_fraction": (0, 1), "cell_delta_c_at_1000": (0, 30)},
    "station": {"capacity_mw": (0, 10000, True), "loss_fraction": (0, .999999)},
    "load": {"demand_mw": (0, 10000), "priority": (0, 1000)},
    "battery": {"capacity_mwh": (0, 100000, True), "charge_mw": (0, 10000),
                "discharge_mw": (0, 10000), "charge_efficiency": (0, 1, True),
                "discharge_efficiency": (0, 1, True), "self_discharge_per_h": (0, 1),
                "initial_soc": (0, 1)},
}

DEFAULTS.update({
    "solar_thermal": {"absorber_area_m2": 30.3, "optical_efficiency": .785,
                      "heat_loss_w_m2k": 1.42, "heat_loss_quadratic_w_m2k2": .005,
                      "auxiliary_electric_ratio": .02, "supply_temp_c": 90., "return_temp_c": 60.},
    "fuel_boiler": {"rated_fuel_mw": 2.0, "thermal_efficiency": .90, "auxiliary_electric_ratio": .01},
    "electric_boiler": {"rated_electric_mw": 2.0, "thermal_efficiency": .98},
    "thermal_store": {"capacity_mwhth": 4.0, "charge_mwth": 2.0, "discharge_mwth": 2.0,
                      "charge_efficiency": .98, "discharge_efficiency": .98,
                      "self_discharge_per_h": .002, "initial_soc": 0.0},
    "heat_exchanger": {"capacity_mwth": 2.0, "transfer_efficiency": .98, "min_approach_k": 5.0},
    "heat_demand": {"demand_mwth": 1.0, "priority": 10},
})
RANGES.update({
    "solar_thermal": {"absorber_area_m2": (0, 3030, True), "optical_efficiency": (0, 1, True),
                      "heat_loss_w_m2k": (0, 20), "heat_loss_quadratic_w_m2k2": (0, .2),
                      "auxiliary_electric_ratio": (.001, .2), "supply_temp_c": (90, 90), "return_temp_c": (60, 60)},
    "fuel_boiler": {"rated_fuel_mw": (0, 10000, True), "thermal_efficiency": (0, 1, True),
                    "auxiliary_electric_ratio": (.001, .2)},
    "electric_boiler": {"rated_electric_mw": (0, 10000, True), "thermal_efficiency": (0, 1, True)},
    "thermal_store": {"capacity_mwhth": (0, 100000, True), "charge_mwth": (0, 10000),
                      "discharge_mwth": (0, 10000), "charge_efficiency": (0, 1, True),
                      "discharge_efficiency": (0, 1, True), "self_discharge_per_h": (0, 1),
                      "initial_soc": (0, 1)},
    "heat_exchanger": {"capacity_mwth": (0, 10000, True), "transfer_efficiency": (0, 1, True),
                       "min_approach_k": (0, 20)},
    "heat_demand": {"demand_mwth": (0, 10000), "priority": (0, 1000)},
})


# AC powers are net terminal powers. CAES and liquid-air conversion efficiencies
# include their charge/discharge trains; no pressure/fluid transient is claimed.
# Hydrogen charge efficiency is net electrolyzer + compression (LHV basis), and
# discharge efficiency is net fuel-cell + inverter. Inventory remains energy_mwh.
for _kind, _values in {
    "battery_sodium": (6., 2., 2., .92, .92, .0001),
    "battery_flow": (12., 2., 2., .85, .85, .0002),
    "caes_aboveground": (.25, .1, .1, .75, .70, .002),
    "liquid_air_store": (8., 2., 1., .70, .65, .002),
    "hydrogen_storage_system": (20., 2., 1., .65, .50, .0001),
}.items():
    DEFAULTS[_kind] = dict(zip(("capacity_mwh", "charge_mw", "discharge_mw",
                               "charge_efficiency", "discharge_efficiency", "self_discharge_per_h"), _values),
                           initial_soc=0.)
    RANGES[_kind] = dict(RANGES["battery"])
RANGES["caes_aboveground"].update(capacity_mwh=(0, 10, True), charge_mw=(0, 2), discharge_mw=(0, 2))
DEFAULTS["solid_thermal_store"] = {
    "capacity_mwhth": 8., "charge_mwth": 2., "discharge_mwth": 1.,
    "charge_efficiency": .95, "discharge_efficiency": .95,
    "self_discharge_per_h": .001, "initial_soc": 0.,
}
RANGES["solid_thermal_store"] = dict(RANGES["thermal_store"])
# The solid store exposes only the same primary-water-grade exchanger interface
# as thermal_store. It has neither an AC port nor a direct electric-return path.
for (_source, _sink), _route in list(THERMAL_ROUTES.items()):
    if _source == "thermal_store" or _sink == "thermal_store":
        THERMAL_ROUTES[("solid_thermal_store" if _source == "thermal_store" else _source,
                        "solid_thermal_store" if _sink == "thermal_store" else _sink)] = _route


DEFAULTS.update({
    "parabolic_trough": {"aperture_area_m2": 69.24, "optical_efficiency": .75,
                        "heat_loss_w_m2k": .1, "heat_loss_quadratic_w_m2k2": .0002,
                        "auxiliary_electric_ratio": .02, "supply_temp_c": 300., "return_temp_c": 200.},
    "high_temp_store": {**DEFAULTS["thermal_store"], "capacity_mwhth": .2,
                        "charge_mwth": .1, "discharge_mwth": .1, "self_discharge_per_h": .005},
    "oil_water_exchanger": {**DEFAULTS["heat_exchanger"], "capacity_mwth": .1,
                            "min_approach_k": 10., "auxiliary_electric_ratio": .01},
})
RANGES.update({
    "parabolic_trough": {**RANGES["solar_thermal"], "aperture_area_m2": (0, 6924, True),
                        "supply_temp_c": (300, 300), "return_temp_c": (200, 200)},
    "high_temp_store": dict(RANGES["thermal_store"]),
    "oil_water_exchanger": {**RANGES["heat_exchanger"], "min_approach_k": (0, 140),
                            "auxiliary_electric_ratio": (.001, .2)},
})
del RANGES["parabolic_trough"]["absorber_area_m2"]
THERMAL_ROUTES.update({
    ("parabolic_trough", "high_temp_store"): ("heat_out", "heat_in", OIL_GRADE),
    ("parabolic_trough", "oil_water_exchanger"): ("heat_out", "hot_in", OIL_GRADE),
    ("high_temp_store", "oil_water_exchanger"): ("heat_out", "hot_in", OIL_GRADE),
    ("oil_water_exchanger", "heat_exchanger"): ("warm_out", "hot_in", PRIMARY_GRADE),
})


# Fixed-state, continuous-flow teaching Rankine model. Enthalpies are kJ/kg;
# pressure losses, startup inventories and part-load efficiency are not modelled.
RANKINE_H = {"rankine_condensate_v1": 191.81, "rankine_feedwater_v1": 193.238810,
             "rankine_live_v1": 3008.6, "rankine_exhaust_v1": 2426.78753}
RANKINE_ROUTES = {
    ("steam_generator", "steam_turbine"): ("steam_out", "steam_in", "rankine_live_v1"),
    ("steam_turbine", "steam_condenser"): ("exhaust_out", "exhaust_in", "rankine_exhaust_v1"),
    ("steam_condenser", "feedwater_pump"): ("condensate_out", "condensate_in", "rankine_condensate_v1"),
    ("feedwater_pump", "steam_generator"): ("feed_out", "feed_in", "rankine_feedwater_v1"),
}
DEFAULTS.update({
    "steam_generator": {"capacity_mwth": .1, "transfer_efficiency": .97, "auxiliary_electric_ratio": .005},
    "steam_turbine": {"mass_flow_capacity_kg_s": .05, "generator_efficiency": .95},
    "steam_condenser": {"capacity_mwth": .08, "auxiliary_electric_ratio": .02,
                        "condensing_temp_c": 45.806, "design_ambient_c": 25., "min_approach_k": 10.},
    "feedwater_pump": {"mass_flow_capacity_kg_s": .05, "motor_efficiency": .90},
})
RANGES.update({
    "steam_generator": {"capacity_mwth": (0, 10000, True), "transfer_efficiency": (.97, .97),
                        "auxiliary_electric_ratio": (.001, .2)},
    "steam_turbine": {"mass_flow_capacity_kg_s": (0, 1000, True), "generator_efficiency": (.95, .95)},
    "steam_condenser": {"capacity_mwth": (0, 10000, True), "auxiliary_electric_ratio": (.001, .2),
                        "condensing_temp_c": (45.806, 45.806), "design_ambient_c": (25, 25), "min_approach_k": (10, 10)},
    "feedwater_pump": {"mass_flow_capacity_kg_s": (0, 1000, True), "motor_efficiency": (.9, .9)},
})
THERMAL_ROUTES.update({
    ("parabolic_trough", "steam_generator"): ("heat_out", "oil_in", OIL_GRADE),
    ("high_temp_store", "steam_generator"): ("heat_out", "oil_in", OIL_GRADE),
})



DEFAULTS.update({
    "solar_tower_receiver": {"mirror_area_m2": 1600., "optical_efficiency": .6,
        "receiver_efficiency": .9, "auxiliary_electric_ratio": .02,
        "supply_temp_c": 565., "return_temp_c": 290.},
    "molten_salt_store": {**DEFAULTS["high_temp_store"], "capacity_mwhth": .5,
        "charge_mwth": .8, "discharge_mwth": .1, "auxiliary_electric_ratio": .01},
    "salt_steam_generator": dict(DEFAULTS["steam_generator"]),
})
RANGES.update({
    "solar_tower_receiver": {"mirror_area_m2": (1600, 1600), "optical_efficiency": (0, 1, True),
        "receiver_efficiency": (0, 1, True), "auxiliary_electric_ratio": (.001, .2),
        "supply_temp_c": (565, 565), "return_temp_c": (290, 290)},
    "molten_salt_store": {**RANGES["high_temp_store"], "auxiliary_electric_ratio": (.001, .2)},
    "salt_steam_generator": dict(RANGES["steam_generator"]),
})
THERMAL_ROUTES.update({
    ("solar_tower_receiver", "molten_salt_store"): ("heat_out", "heat_in", SALT_GRADE),
    ("solar_tower_receiver", "salt_steam_generator"): ("heat_out", "salt_in", SALT_GRADE),
    ("molten_salt_store", "salt_steam_generator"): ("heat_out", "salt_in", SALT_GRADE),
})
RANKINE_ROUTES.update({
    ("salt_steam_generator", "steam_turbine"): ("steam_out", "steam_in", "rankine_live_v1"),
    ("feedwater_pump", "salt_steam_generator"): ("feed_out", "feed_in", "rankine_feedwater_v1"),
})


def tower_physics(params, weather):
    """Equivalent optical receiver; no ray tracing, shading or blocking model."""
    dni = weather["dni_wm2"] if weather["is_day"] and weather["solar_altitude_deg"] > 0 else 0.
    incident = dni*params["mirror_area_m2"]/1e6
    absorbed = incident*params["optical_efficiency"]
    loss = absorbed*(1-params["receiver_efficiency"])
    return {"incident_mw": incident, "optical_rejection_mw": incident-absorbed,
            "potential_thermal_loss_mw": loss, "thermal_loss_mw": loss,
            "available_mwth": absorbed-loss}


def rankine_profile(kind):
    return TOWER_PROFILE if kind in TOWER_KINDS else RANKINE_PROFILE if kind in RANKINE_KINDS else (HIGH_TEMP_PROFILE if kind in HIGH_TEMP_KINDS else THERMAL_PROFILE)


def rankine_coefficients():
    # Recompute from the immutable published state points at every use. No
    # cached LP coefficient or user-supplied performance field is authoritative.
    h1, h2 = RANKINE_H["rankine_condensate_v1"], RANKINE_H["rankine_feedwater_v1"]
    h3, h4 = RANKINE_H["rankine_live_v1"], RANKINE_H["rankine_exhaust_v1"]
    return {"steam_heat": (h3-h2)/1000, "shaft": (h3-h4)/1000,
            "rejection": (h4-h1)/1000, "pump_work": (h2-h1)/1000}


def condenser_capacity(params, weather):
    ambient = weather["air_temp_c"]
    if ambient >= params["condensing_temp_c"]-params["min_approach_k"]:
        return 0.
    return params["capacity_mwth"]*min(1., max(0., (params["condensing_temp_c"]-ambient)/
        (params["condensing_temp_c"]-params["design_ambient_c"])))


def rankine_loops(nodes, links):
    """Only exact SG→turbine→condenser→pump→same SG loops can operate."""
    following = {str(line["from"]): str(line["to"]) for line in links if line["carrier"] == "water_steam"}
    loops = []
    for k, node in nodes.items():
        if node["kind"] not in ("steam_generator", "salt_steam_generator"):
            continue
        loop, at = [k], k
        for _ in range(4):
            at = following.get(at)
            if at is None:
                break
            loop.append(at)
        if len(loop) == 5 and loop[-1] == k and len(set(loop[:-1])) == 4:
            loops.append(tuple(loop[:-1]))
    return loops


def trough_physics(params, weather):
    """Horizontal N-S single-axis teaching proxy; coefficients are not vendor fits.

    The oil inventory represents useful 200-to-300 C enthalpy above its cold
    reference, not arbitrary tank temperature or free ambient heating.
    """
    altitude = math.radians(weather["solar_altitude_deg"])
    azimuth = math.radians(weather["solar_azimuth_deg"])
    cosine = math.sqrt(max(0., 1-(math.cos(altitude)*math.cos(azimuth))**2))
    if not weather.get("is_day", True) or altitude <= 0:
        cosine = 0.
    incident = params["aperture_area_m2"]*weather["dni_wm2"]*cosine/1e6
    absorbed = incident*params["optical_efficiency"]
    delta = max(0., 250-weather["air_temp_c"])
    potential = params["aperture_area_m2"]*(params["heat_loss_w_m2k"]*delta+params["heat_loss_quadratic_w_m2k2"]*delta**2)/1e6
    return {"incident_mw": incident, "optical_rejection_mw": incident-absorbed,
            "potential_thermal_loss_mw": potential, "thermal_loss_mw": min(absorbed, potential),
            "available_mwth": max(0., absorbed-potential), "cos_incidence": cosine}


def collector_physics(node, weather):
    return tower_physics(node["params"], weather) if node["kind"] == "solar_tower_receiver" else trough_physics(node["params"], weather) if node["kind"] == "parabolic_trough" else solar_physics(node["params"], weather)


FUEL_SUPPLY_DEFAULTS = {"enabled": False, "max_input_mw": 0.0,
                        "lower_heating_value_kwh_per_nm3": 10.0, "price_per_mwh": 300.0}
FUEL_FIELDS = ("input_mw", "volume_nm3_per_h", "cost_per_h", "heat_output_mwth",
               "conversion_loss_mw", "auxiliary_electric_mw", "auxiliary_electric_loss_mw")


class InputError(ValueError):
    pass


def number(value, label, low=None, high=None, positive=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InputError(f"{label} must be a finite number")
    try:
        value = float(value)
    except OverflowError as exc:
        raise InputError(f"{label} is too large") from exc
    if not math.isfinite(value):
        raise InputError(f"{label} must be a finite number")
    if low is not None and (value < low or (positive and value == low)):
        raise InputError(f"{label} must be {'>' if positive else '>='} {low}")
    if high is not None and value > high:
        raise InputError(f"{label} must be <= {high}")
    return value


def integer(value, label, low=0):
    v = number(value, label, low, 2**53-1)
    if v != math.floor(v):
        raise InputError(f"{label} must be an integer")
    return int(v)


def object_value(value, label):
    if not isinstance(value, dict):
        raise InputError(f"{label} must be an object")
    return value


def normalize_fuel_supply(raw):
    supplied = object_value(raw, "fuel_supply")
    unknown = set(supplied)-set(FUEL_SUPPLY_DEFAULTS)
    if unknown:
        raise InputError("Unknown fuel_supply field(s): " + ", ".join(sorted(unknown)))
    supply = dict(FUEL_SUPPLY_DEFAULTS, **supplied)
    if not isinstance(supply["enabled"], bool):
        raise InputError("fuel_supply.enabled must be boolean")
    for key, low, high, positive in (("max_input_mw", 0, 10000, False),
                                     ("lower_heating_value_kwh_per_nm3", 0, 100, True),
                                     ("price_per_mwh", 0, 1e6, False)):
        supply[key] = number(supply[key], "fuel_supply."+key, low, high, positive)
    if not math.isfinite(supply["max_input_mw"]*1000/supply["lower_heating_value_kwh_per_nm3"]):
        raise InputError("Fuel volume conversion must remain finite at the configured input cap")
    return supply


SOLAR_FIELDS = ("incident_mw", "optical_rejection_mw", "potential_thermal_loss_mw",
                "thermal_loss_mw", "available_mwth", "useful_mwth", "curtailed_mwth",
                "auxiliary_electric_mw")


def solar_physics(params, weather):
    """Nonconcentrating collector: irradiance is teaching-equivalent POA, never DNI.

    Loss is capped by absorbed irradiation for a nonnegative energy ledger;
    the uncapped operating-temperature loss remains separately visible.
    """
    area = params["absorber_area_m2"]
    irradiance = weather["irradiance_wm2"] if weather.get("is_day", True) else 0.0
    incident = area*irradiance/1e6
    absorbed = incident*params["optical_efficiency"]
    delta = max(0., (params["supply_temp_c"]+params["return_temp_c"])/2-weather["air_temp_c"])
    potential = area*(params["heat_loss_w_m2k"]*delta+params["heat_loss_quadratic_w_m2k2"]*delta**2)/1e6
    loss = min(absorbed, potential)
    return {"incident_mw": incident, "optical_rejection_mw": incident-absorbed,
            "potential_thermal_loss_mw": potential, "thermal_loss_mw": loss,
            "available_mwth": max(0., absorbed-potential)}


def normalize(snapshot):
    """Reject an invalid snapshot as a whole; never optimize a partial topology."""
    root = object_value(snapshot, "snapshot")
    schema = integer(root.get("schema_version", 1), "schema_version", 1)
    if schema not in (1, 2, 3, 4, 5, 6, 7):
        raise InputError("Unsupported dispatch schema_version")
    raw_devices, raw_links, raw_steps = root.get("devices"), root.get("links"), root.get("steps")
    if not isinstance(raw_devices, list) or len(raw_devices) > MAX_DEVICES:
        raise InputError(f"devices must be an array of at most {MAX_DEVICES} devices")
    if not isinstance(raw_links, list) or len(raw_links) > MAX_DEVICES * 2:
        raise InputError("links must be a bounded array")
    if not isinstance(raw_steps, list) or not 1 <= len(raw_steps) <= MAX_STEPS:
        raise InputError(f"steps must contain 1 to {MAX_STEPS} entries")
    fuel_supply = normalize_fuel_supply(root.get("fuel_supply", {}))
    nodes = {}
    for raw in raw_devices:
        d = object_value(raw, "device")
        ident = str(integer(d.get("id"), "device.id"))
        if ident in nodes:
            raise InputError(f"Duplicate device id {ident}")
        kind = d.get("kind")
        if not isinstance(kind, str) or kind not in DEFAULTS:
            raise InputError(f"Unknown device kind for {ident}")
        if kind in EXPANDED_STORAGE_KINDS and schema < 7:
            raise InputError("Expanded storage devices require dispatch schema_version 7")
        if kind in TOWER_KINDS and schema < 6:
            raise InputError("Tower devices require dispatch schema_version 6")
        if kind in RANKINE_KINDS and schema < 5:
            raise InputError("Rankine devices require dispatch schema_version 5")
        if kind in HIGH_TEMP_KINDS and schema < 4:
            raise InputError("High-temperature devices require dispatch schema_version 4")
        if kind in THERMAL_KINDS:
            if schema < 2:
                raise InputError("Thermal devices require dispatch schema_version 2 or 3")
            profile = rankine_profile(kind)
            if d.get("model_profile", profile) != profile:
                raise InputError(f"Unknown thermal model_profile for {ident}")
            if integer(d.get("model_profile_version", 1), "model_profile_version", 1) != 1:
                raise InputError("Unsupported thermal model_profile_version")
            unknown = set(d) - {"id", "kind", "params", "state", "model_profile", "model_profile_version"}
            if unknown:
                raise InputError("Unknown thermal device field(s): " + ", ".join(sorted(unknown)))
        p = copy.deepcopy(DEFAULTS[kind])
        supplied = object_value(d.get("params", {}), f"device {ident}.params")
        unknown = set(supplied) - set(p)
        if unknown:
            raise InputError(f"Unknown {kind} parameter(s): {', '.join(sorted(unknown))}")
        p.update(supplied)
        for key, bounds in RANGES[kind].items():
            p[key] = number(p[key], f"device {ident}.{key}", bounds[0], bounds[1],
                            len(bounds) > 2 and bounds[2])
        if kind in ("load", "heat_demand"):
            p["priority"] = integer(p["priority"], f"device {ident}.priority")
        if kind == "wind":
            curve = p["power_curve_kw"]
            if not isinstance(curve, list) or (curve and not 2 <= len(curve) <= 256):
                raise InputError("power_curve_kw must be empty or contain 2 to 256 points")
            previous = -1.0
            for point in curve:
                q = object_value(point, "power_curve_kw point")
                if set(q) != {"wind_mps", "power_kw"}:
                    raise InputError("power_curve_kw point requires only wind_mps and power_kw")
                speed = number(q["wind_mps"], "curve wind_mps", 0, 100)
                number(q["power_kw"], "curve power_kw", 0, p["rated_mw"] * 1000)
                if speed <= previous:
                    raise InputError("power_curve_kw wind speeds must strictly increase")
                previous = speed
            if p["cut_in_mps"] >= p["cut_out_mps"] or (not curve and not
                    p["cut_in_mps"] < p["rated_speed_mps"] < p["cut_out_mps"]):
                raise InputError("Wind speeds must satisfy cut-in < rated < cut-out")
            if p["hub_height_m"] <= p["rotor_diameter_m"] / 2:
                raise InputError("Wind hub height must exceed rotor radius")
        if kind in STORAGE_KINDS:
            ek = "energy_mwhth" if kind in THERMAL_STORAGE_KINDS else "energy_mwh"
            ck = "capacity_mwhth" if kind in THERMAL_STORAGE_KINDS else "capacity_mwh"
            state = object_value(d.get("state", {ek: p[ck] * p["initial_soc"]}),
                                 f"{kind} {ident}.state")
            if set(state) != {ek}:
                raise InputError(f"{kind} state requires only {ek}")
            energy = number(state[ek], f"{kind} {ident}.{ek}", 0, p[ck])
        else:
            state = d.get("state", {})
            if not isinstance(state, dict) or state:
                raise InputError("Only storage devices have state")
            energy = None
        nodes[ident] = {"id": int(ident), "kind": kind, "params": p, "energy": energy}
    if schema == 7 and not any(d["kind"] in EXPANDED_STORAGE_KINDS for d in nodes.values()):
        raise InputError("Schema 7 is reserved for the expanded storage extension")
    if schema == 6 and not any(d["kind"] in TOWER_KINDS for d in nodes.values()):
        raise InputError("Schema 6 is reserved for the tower extension")
    if schema == 5 and not any(d["kind"] in RANKINE_KINDS for d in nodes.values()):
        raise InputError("Schema 5 is reserved for the Rankine extension")
    if schema == 4 and not any(d["kind"] in HIGH_TEMP_KINDS for d in nodes.values()):
        raise InputError("Schema 4 is reserved for the high-temperature extension")
    nodes = dict(sorted(nodes.items(), key=lambda item: int(item[0])))
    links, attachments, outputs, attached, pairs = [], {}, {}, set(), set()
    mass_ports = set()
    for i, raw in enumerate(raw_links):
        line = object_value(raw, f"link {i}")
        a = str(integer(line.get("from"), f"link {i}.from"))
        b = str(integer(line.get("to"), f"link {i}.to", -1))
        if a == b or a not in nodes or (b != "-1" and b not in nodes):
            raise InputError(f"Link {i} has a missing endpoint or self-connection")
        # JSON readers may round-trip integral identifiers as 3.0. Canonicalize
        # validated endpoints once, before thermal maps use string keys.
        line = {**line, "from": int(a), "to": int(b)}
        ak, bk = nodes[a]["kind"], "grid" if b == "-1" else nodes[b]["kind"]
        mass_route = RANKINE_ROUTES.get((ak, bk))
        if mass_route is not None or line.get("carrier") == "water_steam":
            if schema < 5 or mass_route is None:
                raise InputError(f"Link {i}: unsupported Rankine mass route")
            allowed = {"from", "to", "from_port", "to_port", "carrier", "unit", "grade_id",
                       "mass_flow_capacity_kg_s", "loss_fraction"}
            if set(line) != allowed:
                raise InputError(f"Link {i}: mass edges require exactly explicit water_steam fields")
            for key, expected in zip(("from_port", "to_port", "grade_id"), mass_route):
                if line[key] != expected:
                    raise InputError(f"Link {i}: incompatible mass {key}; expected {expected}")
            if line["carrier"] != "water_steam" or line["unit"] != "kg/s":
                raise InputError(f"Link {i}: mass carrier/unit must be water_steam/kg/s")
            cap = number(line["mass_flow_capacity_kg_s"], f"link {i}.mass_flow_capacity_kg_s", 0, 1000)
            loss = number(line["loss_fraction"], f"link {i}.loss_fraction", 0, 0)
            for port in ((a, mass_route[0]), (b, mass_route[1])):
                if port in mass_ports:
                    raise InputError(f"Link {i}: Rankine mass port is multiply attached")
                mass_ports.add(port)
            links.append({**line, "index": i, "mass_flow_capacity_kg_s": cap, "loss_fraction": loss})
            continue
        route = THERMAL_ROUTES.get((ak, bk))
        if route is not None or line.get("carrier") in ("heat_water", "heat_oil", "heat_salt"):
            if schema < 2 or route is None:
                raise InputError(f"Link {i}: unsupported thermal route")
            allowed = {"from", "to", "from_port", "to_port", "carrier", "unit", "grade_id",
                       "capacity_mwth", "loss_fraction"}
            if set(line) != allowed:
                raise InputError(f"Link {i}: heat edges require exactly explicit thermal fields (capacity_mwth only)")
            for key, expected in zip(("from_port", "to_port", "grade_id"), route):
                if line[key] != expected:
                    raise InputError(f"Link {i}: incompatible thermal {key}; expected {expected}")
            if line["carrier"] != ("heat_salt" if route[2] == SALT_GRADE else "heat_oil" if route[2] == OIL_GRADE else "heat_water") or line["unit"] != "MWth":
                raise InputError(f"Link {i}: thermal carrier/unit must be heat_water/MWth")
            cap = number(line["capacity_mwth"], f"link {i}.capacity_mwth", 0, 10000)
            loss = number(line["loss_fraction"], f"link {i}.loss_fraction", 0, 0)
            pair = (a, b, route[0], route[1])
            if pair in pairs:
                raise InputError(f"Link {i}: duplicate thermal port connection")
            pairs.add(pair)
            links.append({**line, "index": i, "capacity_mwth": cap, "loss_fraction": loss})
            continue
        if not ((ak in ("wind", "pv", "steam_turbine") + ELECTRIC_STORAGE_KINDS and bk == "station") or
                (ak == "station" and bk in ("load", "grid", "electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "oil_water_exchanger") + ELECTRIC_STORAGE_KINDS + RANKINE_AUX_KINDS + ("solar_tower_receiver", "molten_salt_store"))):
            raise InputError(f"Link {i}: unsupported electricity route")
        if "capacity_mwth" in line or "grade_id" in line or "mass_flow_capacity_kg_s" in line:
            raise InputError(f"Link {i}: electricity edge cannot contain heat capacity or grade")
        fp = "ac" if ak in ELECTRIC_STORAGE_KINDS else ("ac_out" if ak == "steam_turbine" else "out")
        tp = "ac" if bk in ELECTRIC_STORAGE_KINDS else ("ac_in" if bk in ("electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "oil_water_exchanger") + RANKINE_AUX_KINDS + ("solar_tower_receiver", "molten_salt_store") else "in")
        if line.get("from_port", fp) != fp or line.get("to_port", tp) != tp:
            raise InputError(f"Link {i}: invalid electric port")
        if bk in ("electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "oil_water_exchanger") + RANKINE_AUX_KINDS + ("solar_tower_receiver", "molten_salt_store") and not {"from_port", "to_port", "carrier", "unit"} <= set(line):
            raise InputError(f"Link {i}: boiler electric edge requires explicit ports/carrier/unit")
        for key, expected in (("carrier", "electricity_ac"), ("unit", "MW"), ("voltage_level", "AC_BUS")):
            if line.get(key, expected) != expected:
                raise InputError(f"Link {i}: {key} must be {expected}")
        station, leaf = (a, b) if ak == "station" else (b, a)
        pair = tuple(sorted((int(a), int(b))))
        if pair in pairs or (leaf != "-1" and leaf in attached):
            raise InputError(f"Link {i}: duplicate connection or multiply attached electric leaf")
        pairs.add(pair)
        attached.add(leaf)
        cap = number(line.get("capacity_mw", 4), f"link {i}.capacity_mw", 0, 1e9)
        loss = number(line.get("loss_fraction", .01), f"link {i}.loss_fraction", 0, 1)
        if loss >= 1:
            raise InputError(f"Link {i}.loss_fraction must be < 1")
        links.append({"index": i, "from": int(a), "to": int(b), "capacity_mw": cap,
                      "loss_fraction": loss, "station": station, "leaf": leaf,
                      "from_port": fp, "to_port": tp, "carrier": "electricity_ac", "unit": "MW",
                      "voltage_level": "AC_BUS"})
        kind = "grid" if leaf == "-1" else nodes[leaf]["kind"]
        if kind in ("wind", "pv", "steam_turbine") + ELECTRIC_STORAGE_KINDS:
            attachments[leaf] = (station, i)
        if kind in ("load", "grid", "electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "oil_water_exchanger") + ELECTRIC_STORAGE_KINDS + RANKINE_AUX_KINDS + ("solar_tower_receiver", "molten_salt_store"):
            outputs.setdefault(station, []).append((leaf, i))
    paths = []
    for source, (station, incoming) in sorted(attachments.items(), key=lambda x: int(x[0])):
        for sink, outgoing in sorted(outputs.get(station, []), key=lambda x: int(x[0])):
            sk = nodes[source]["kind"]
            tk = "grid" if sink == "-1" else nodes[sink]["kind"]
            if sk == "steam_turbine" and tk not in ("load", "grid") + ELECTRIC_STORAGE_KINDS:
                continue
            if sk in ELECTRIC_STORAGE_KINDS and tk not in ("load", "electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "oil_water_exchanger") + RANKINE_AUX_KINDS + ("solar_tower_receiver", "molten_salt_store"):
                continue
            arriving = 1 - links[incoming]["loss_fraction"]
            after = arriving * (1 - nodes[station]["params"]["loss_fraction"])
            received = after * (1 - links[outgoing]["loss_fraction"])
            if (len(paths)+1)*len(raw_steps) > MAX_VARIABLES:
                raise InputError("Model too large: path-flow variable limit exceeded")
            paths.append({"source": source, "sink": sink, "station": station,
                          "incoming": incoming, "outgoing": outgoing,
                          "arriving": arriving, "after": after, "received": received})
    options = object_value(root.get("options", {}), "options")
    unknown = set(options) - {"terminal_soc_fraction", "strict_supply", "timeout_s", "horizon_hours", "step_minutes", "load_multiplier", "terminal_heat_soc_fraction", "heat_service_weight"}
    if unknown:
        raise InputError("Unknown option(s): " + ", ".join(sorted(unknown)))
    for key in ("horizon_hours", "step_minutes", "load_multiplier"):
        if key in options:
            number(options[key], "options." + key, 0, 1e9)
    strict = options.get("strict_supply", False)
    if not isinstance(strict, bool):
        raise InputError("options.strict_supply must be boolean")
    terminal = options.get("terminal_soc_fraction")
    if terminal is not None:
        terminal = number(terminal, "options.terminal_soc_fraction", 0, 1)
    terminal_heat = options.get("terminal_heat_soc_fraction")
    if terminal_heat is not None:
        terminal_heat = number(terminal_heat, "options.terminal_heat_soc_fraction", 0, 1)
    heat_weight = number(options.get("heat_service_weight", 1), "options.heat_service_weight", 0, 10000, True)
    timeout = number(options.get("timeout_s", 30), "options.timeout_s", 0, 3600, True)
    grid = number(root.get("grid_capacity_mw", 4), "grid_capacity_mw", 0, 1e9)
    generators = [k for k, d in nodes.items() if d["kind"] in ("wind", "pv")]
    loads = [k for k, d in nodes.items() if d["kind"] == "load"]
    batteries = [k for k, d in nodes.items() if d["kind"] in ELECTRIC_STORAGE_KINDS]
    solar_collectors = [k for k, d in nodes.items() if d["kind"] == "solar_thermal"]
    troughs = [k for k, d in nodes.items() if d["kind"] == "parabolic_trough"]
    receivers = [k for k, d in nodes.items() if d["kind"] == "solar_tower_receiver"]
    salt_stores = [k for k, d in nodes.items() if d["kind"] == "molten_salt_store"]
    source_collectors = solar_collectors + troughs + receivers
    oil_exchangers = [k for k, d in nodes.items() if d["kind"] == "oil_water_exchanger"]
    boilers = [k for k, d in nodes.items() if d["kind"] == "electric_boiler"]
    fuel_boilers = [k for k, d in nodes.items() if d["kind"] == "fuel_boiler"]
    thermal_stores = [k for k, d in nodes.items() if d["kind"] in THERMAL_STORAGE_KINDS]
    heat_demands = [k for k, d in nodes.items() if d["kind"] == "heat_demand"]
    exchangers = [k for k, d in nodes.items() if d["kind"] in ("heat_exchanger", "oil_water_exchanger")]
    rankine_ids = [k for k, d in nodes.items() if d["kind"] in RANKINE_KINDS]
    turbines = [k for k in rankine_ids if nodes[k]["kind"] == "steam_turbine"]
    rankine_aux = [k for k in rankine_ids if nodes[k]["kind"] in RANKINE_AUX_KINDS]
    mass_links = [line["index"] for line in links if line["carrier"] == "water_steam"]
    loops = rankine_loops(nodes, links)
    heat_links = [line["index"] for line in links if line["carrier"] in ("heat_water", "heat_oil", "heat_salt")]
    steps = []
    previous_end = None
    for i, raw in enumerate(raw_steps):
        step = object_value(raw, f"step {i}")
        start = number(step.get("time_s"), f"step {i}.time_s", 0, 1e15)
        dt = number(step.get("dt_h"), f"step {i}.dt_h", 0, 8760, schema == 1)
        if previous_end is not None and abs(start - previous_end) > max(1e-5, abs(previous_end)*1e-12):
            raise InputError("Steps must be contiguous and ordered (time_s is interval start)")
        previous_end = start + dt * 3600
        available, demand, heat_demand = {}, {}, {}
        if schema >= 2 and heat_demands and "heat_demand_mwth" not in step:
            raise InputError(f"step {i}: missing heat_demand_mwth")
        for key, ids, target in (("available_mw", generators, available), ("demand_mw", loads, demand),
                                 ("heat_demand_mwth", heat_demands, heat_demand)):
            values = object_value(step.get(key, {}), f"step {i}.{key}")
            if set(values) != set(ids):
                raise InputError(f"step {i}.{key} must contain exactly the relevant device IDs as strings")
            for ident in ids:
                value = number(values[ident], f"step {i}.{key}.{ident}", 0, 10000)
                if key == "available_mw":
                    p = nodes[ident]["params"]
                    rating = p["rated_mw"] if nodes[ident]["kind"] == "wind" else p["inverter_capacity_mw"]
                    if value > rating + 1e-9:
                        raise InputError(f"step {i} availability exceeds generator {ident} nameplate")
                target[ident] = value
        normalized_step = {"time_s": start, "dt_h": dt, "available_mw": available, "demand_mw": demand, "heat_demand_mwth": heat_demand}
        if solar_collectors:
            weather = object_value(step.get("weather"), f"step {i}.weather")
            is_day = weather.get("is_day", True)
            if not isinstance(is_day, bool):
                raise InputError(f"step {i}.weather.is_day must be boolean")
            irradiance_kind = weather.get("irradiance_kind", "teaching_equivalent_poa")
            if irradiance_kind not in ("teaching_equivalent_poa", "poa", "plane_of_array"):
                raise InputError("Solar irradiance must be POA or teaching_equivalent_poa, not GHI or DNI")
            weather = {"is_day": is_day, "irradiance_kind": irradiance_kind,
                       "irradiance_wm2": number(weather.get("irradiance_wm2"), f"step {i}.weather.irradiance_wm2", 0, 2000),
                       "air_temp_c": number(weather.get("air_temp_c"), f"step {i}.weather.air_temp_c", -100, 100)}
            solar_available = {k: solar_physics(nodes[k]["params"], weather)["available_mwth"] for k in solar_collectors}
            if "solar_available_mwth" in step:
                cache = object_value(step["solar_available_mwth"], "solar_available_mwth")
                if set(cache) != set(solar_collectors):
                    raise InputError("solar_available_mwth requires exactly solar device IDs")
                for k, value in cache.items():
                    number(value, "solar_available_mwth."+k, 0, 10000)
                    if abs(value-solar_available[k]) > ABS_TOL:
                        raise InputError("Solar availability disagrees with independent weather physics")
            normalized_step.update(weather=weather, solar_available_mwth=solar_available)
        if troughs:
            raw_weather = object_value(step.get("weather"), f"step {i}.weather")
            is_day = raw_weather.get("is_day", True)
            if not isinstance(is_day, bool):
                raise InputError("weather.is_day must be boolean")
            weather = dict(normalized_step.get("weather", {}), is_day=is_day)
            for key, low, high in (("dni_wm2", 0, 2000), ("air_temp_c", -100, 100),
                                   ("solar_altitude_deg", -90, 90), ("solar_azimuth_deg", 0, 360)):
                weather[key] = number(raw_weather.get(key), f"step {i}.weather.{key}", low, high)
            available_heat = {k: trough_physics(nodes[k]["params"], weather)["available_mwth"] for k in troughs}
            if "trough_available_mwth" in step:
                cache = object_value(step["trough_available_mwth"], "trough_available_mwth")
                if set(cache) != set(troughs):
                    raise InputError("trough_available_mwth requires exactly trough device IDs")
                for k, value in cache.items():
                    number(value, "trough_available_mwth."+k, 0, 10000)
                    if abs(value-available_heat[k]) > ABS_TOL:
                        raise InputError("Trough availability disagrees with independent DNI physics")
            normalized_step.update(weather=weather, trough_available_mwth=available_heat)
            normalized_step.setdefault("solar_available_mwth", {}).update(available_heat)
        if receivers:
            raw_weather = object_value(step.get("weather"), f"step {i}.weather")
            if not isinstance(raw_weather.get("is_day"), bool):
                raise InputError("Tower weather.is_day must be explicitly boolean")
            weather = dict(normalized_step.get("weather", {}), is_day=raw_weather["is_day"])
            for key, low, high in (("dni_wm2", 0, 2000), ("air_temp_c", -100, 100),
                                   ("solar_altitude_deg", -90, 90), ("solar_azimuth_deg", 0, 360)):
                weather[key] = number(raw_weather.get(key), f"step {i}.weather.{key}", low, high)
            available_heat = {k: tower_physics(nodes[k]["params"], weather)["available_mwth"] for k in receivers}
            if "tower_available_mwth" in step:
                cache = object_value(step["tower_available_mwth"], "tower_available_mwth")
                if set(cache) != set(receivers):
                    raise InputError("tower_available_mwth requires exactly receiver IDs")
                for k, value in cache.items():
                    number(value, "tower_available_mwth."+k, 0, 10000)
                    if abs(value-available_heat[k]) > ABS_TOL:
                        raise InputError("Tower availability disagrees with independent DNI physics")
            normalized_step.update(weather=weather, tower_available_mwth=available_heat)
            normalized_step.setdefault("solar_available_mwth", {}).update(available_heat)
        if rankine_ids:
            raw_weather = object_value(step.get("weather"), f"step {i}.weather")
            normalized_step.setdefault("weather", {})["air_temp_c"] = number(raw_weather.get("air_temp_c"), f"step {i}.weather.air_temp_c", -100, 100)
        steps.append(normalized_step)
    if not math.isfinite(fuel_supply["max_input_mw"]*1000/fuel_supply["lower_heating_value_kwh_per_nm3"]*sum(step["dt_h"] for step in steps)):
        raise InputError("Fuel volume over the requested horizon must remain finite")
    variables = len(steps) * (len(paths) + len(loads) + len(generators) + 4*len(batteries) + 4*len(thermal_stores) + len(heat_links) + len(boilers) + len(fuel_boilers) + len(source_collectors) + len(exchangers) + len(heat_demands) + len(rankine_ids) + len(mass_links)) + 1
    if variables > MAX_VARIABLES:
        raise InputError(f"Model too large: {variables} variables (limit {MAX_VARIABLES})")
    return {"nodes": nodes, "links": links, "paths": paths, "steps": steps,
            "receivers": receivers, "salt_stores": salt_stores,
            "has_tower": any(d["kind"] in TOWER_KINDS for d in nodes.values()),
            "rankine_ids": rankine_ids, "rankine_aux": rankine_aux, "turbines": turbines,
            "mass_links": mass_links, "rankine_loops": loops, "has_rankine": bool(rankine_ids),
            "generators": generators, "loads": loads, "batteries": batteries,
            "grid": grid, "strict": strict, "terminal": terminal, "timeout": timeout,
            "schema": schema, "solar_collectors": solar_collectors, "source_collectors": source_collectors, "troughs": troughs, "oil_exchangers": oil_exchangers, "boilers": boilers, "fuel_boilers": fuel_boilers, "fuel_supply": fuel_supply, "thermal_stores": thermal_stores, "heat_demands": heat_demands,
            "high_stores": [k for k in thermal_stores if nodes[k]["kind"] == "high_temp_store"],
            "water_stores": [k for k in thermal_stores if nodes[k]["kind"] in WATER_STORAGE_KINDS],
            "water_exchangers": [k for k in exchangers if nodes[k]["kind"] == "heat_exchanger"],
            "has_high_temp": any(d["kind"] in HIGH_TEMP_KINDS for d in nodes.values()),
            "exchangers": exchangers, "heat_links": heat_links, "terminal_heat": terminal_heat,
            "heat_weight": heat_weight, "has_thermal": any(d["kind"] in THERMAL_KINDS for d in nodes.values())}


def add(terms, name, value):
    if value:
        terms[name] = terms.get(name, 0.0) + value


def expression(terms):
    if not any(terms.values()):
        return "0 anchor"
    return " ".join(f"{'+' if v >= 0 else '-'} {abs(v):.16g} {k}"
                    for k, v in terms.items() if v)


class LinearModel:
    def __init__(self):
        self.rows = []
        self.bounds = {"anchor": (0, 0)}
        self.binaries = []
        self.objectives = [{}, {}, {}, {}]

    def row(self, terms, relation, value):
        self.rows.append((terms, relation, value))

    def variable(self, name, low=0, high=None):
        self.bounds[name] = (low, high)
        return name

    def write(self, path, stage, locks):
        lines = ["Minimize", " obj: " + expression(self.objectives[stage]), "Subject To", " anchor_row: anchor = 0"]
        for i, (terms, relation, value) in enumerate(self.rows + locks):
            lines.append(f" r{i}: {expression(terms)} {relation} {value:.16g}")
        lines.append("Bounds")
        for name, (low, high) in self.bounds.items():
            if high is None:
                lines.append(f" {low:.16g} <= {name}")
            elif low == high:
                lines.append(f" {name} = {low:.16g}")
            else:
                lines.append(f" {low:.16g} <= {name} <= {high:.16g}")
        if self.binaries:
            lines.extend(["Binary", " " + "\n ".join(self.binaries)])
        lines.append("End")
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def build_model(problem):
    model = LinearModel()
    # GLPK 5.0 presolve may discard a nearly-active singleton objective lock
    # for tiny Rankine flow / large unmet-demand scales. Preserve exact rows.
    model.rankine_no_presolve = problem["has_rankine"]
    if not problem["has_thermal"]:
        model.objectives.pop()
    if problem["fuel_boilers"]:
        model.objectives.append({})
    nodes, paths = problem["nodes"], problem["paths"]
    for t, step in enumerate(problem["steps"]):
        dt = step["dt_h"]
        source_terms = {k: {} for k in problem["generators"] + problem["batteries"] + problem["turbines"]}
        sink_terms = {k: {} for k in problem["loads"] + problem["batteries"] + problem["boilers"] + problem["fuel_boilers"] + problem["source_collectors"] + problem["oil_exchangers"] + problem["rankine_aux"] + problem["salt_stores"] + ["-1"]}
        line_terms = [{} for _ in problem["links"]]
        station_terms = {k: {} for k, d in nodes.items() if d["kind"] == "station"}
        for j, p in enumerate(paths):
            x = model.variable(f"x_{t}_{j}", 0, None if dt else 0)
            add(source_terms[p["source"]], x, 1)
            add(sink_terms[p["sink"]], x, p["received"])
            add(line_terms[p["incoming"]], x, 1)
            add(line_terms[p["outgoing"]], x, p["after"])
            add(station_terms[p["station"]], x, p["arriving"])
        for k in problem["generators"]:
            c = model.variable(f"curt_{t}_{k}", 0, step["available_mw"][k])
            add(source_terms[k], c, 1)
            model.row(source_terms[k], "=", step["available_mw"][k])
        for k in problem["loads"]:
            u = model.variable(f"unmet_{t}_{k}", 0, 0 if problem["strict"] and dt else step["demand_mw"][k])
            add(sink_terms[k], u, 1)
            model.row(sink_terms[k], "=", step["demand_mw"][k])
            add(model.objectives[0], u, dt * (1001 - nodes[k]["params"]["priority"]))
        heat_in, heat_out = {k: {} for k in nodes}, {k: {} for k in nodes}
        for i in problem["heat_links"]:
            line = problem["links"][i]
            q = model.variable(f"heat_{t}_{i}", 0, line["capacity_mwth"] if dt else 0)
            add(heat_out[str(line["from"])], q, 1)
            add(heat_in[str(line["to"])], q, 1-line["loss_fraction"])
        mass_in, mass_out = {k: {} for k in problem["rankine_ids"]}, {k: {} for k in problem["rankine_ids"]}
        for i in problem["mass_links"]:
            line = problem["links"][i]
            mass = model.variable(f"mass_{t}_{i}", 0, line["mass_flow_capacity_kg_s"] if dt else 0)
            add(mass_out[str(line["from"])], mass, 1)
            add(mass_in[str(line["to"])], mass, 1)
        operating_nodes = {k for loop in problem["rankine_loops"] for k in loop}
        coefficients = rankine_coefficients()
        for k in problem["rankine_ids"]:
            kind, p = nodes[k]["kind"], nodes[k]["params"]
            cap = p.get("mass_flow_capacity_kg_s")
            if kind in ("steam_generator", "salt_steam_generator"):
                cap = p["capacity_mwth"]*p["transfer_efficiency"]/coefficients["steam_heat"]
            elif kind == "steam_condenser":
                cap = condenser_capacity(p, step["weather"])/coefficients["rejection"]
            mass = model.variable(f"rankine_{t}_{k}", 0, cap if dt and k in operating_nodes else 0)
            add(mass_in[k], mass, -1)
            add(mass_out[k], mass, -1)
            model.row(mass_in[k], "=", 0)
            model.row(mass_out[k], "=", 0)
            if kind in ("steam_generator", "salt_steam_generator"):
                oil = coefficients["steam_heat"]/p["transfer_efficiency"]
                add(heat_in[k], mass, -oil)
                model.row(heat_in[k], "=", 0)
                add(sink_terms[k], mass, -oil*p["auxiliary_electric_ratio"])
                model.row(sink_terms[k], "=", 0)
                add(model.objectives[3], mass, oil*dt)
            elif kind == "steam_turbine":
                add(source_terms[k], mass, -coefficients["shaft"]*p["generator_efficiency"])
                model.row(source_terms[k], "=", 0)
            else:
                auxiliary = (coefficients["rejection"]*p["auxiliary_electric_ratio"] if kind == "steam_condenser"
                             else coefficients["pump_work"]/p["motor_efficiency"])
                add(sink_terms[k], mass, -auxiliary)
                model.row(sink_terms[k], "=", 0)
        for k in problem["boilers"]:
            p = nodes[k]["params"]
            power = model.variable(f"boiler_{t}_{k}", 0, p["rated_electric_mw"] if dt else 0)
            add(sink_terms[k], power, -1)
            model.row(sink_terms[k], "=", 0)
            add(heat_out[k], power, -p["thermal_efficiency"])
            model.row(heat_out[k], "=", 0)
            add(model.objectives[3], power, dt)
        for k in problem["source_collectors"]:
            p = nodes[k]["params"]
            useful = model.variable(f"solar_{t}_{k}", 0, step["solar_available_mwth"][k] if dt else 0)
            add(sink_terms[k], useful, -p["auxiliary_electric_ratio"])
            model.row(sink_terms[k], "=", 0)
            add(heat_out[k], useful, -1)
            model.row(heat_out[k], "=", 0)
        fuel_terms = {}
        for k in problem["fuel_boilers"]:
            p = nodes[k]["params"]
            fuel = model.variable(f"fuel_{t}_{k}", 0, p["rated_fuel_mw"] if dt else 0)
            add(fuel_terms, fuel, 1)
            # Auxiliary consumption is an endogenous AC sink, supplied only by
            # physically connected renewable/battery paths. No implicit import.
            add(sink_terms[k], fuel, -p["auxiliary_electric_ratio"])
            model.row(sink_terms[k], "=", 0)
            add(heat_out[k], fuel, -p["thermal_efficiency"])
            model.row(heat_out[k], "=", 0)
            add(model.objectives[4], fuel, dt*problem["fuel_supply"]["price_per_mwh"])
        supply = problem["fuel_supply"]
        model.row(fuel_terms, "<=", supply["max_input_mw"] if supply["enabled"] and dt else 0)
        for k in problem["exchangers"]:
            p = nodes[k]["params"]
            activity = model.variable(f"exchange_{t}_{k}", 0, p["capacity_mwth"] if dt else 0)
            if k in problem["oil_exchangers"]:
                add(sink_terms[k], activity, -p["auxiliary_electric_ratio"])
                model.row(sink_terms[k], "=", 0)
            add(heat_in[k], activity, -1)
            add(heat_out[k], activity, -p["transfer_efficiency"])
            model.row(heat_in[k], "=", 0)
            model.row(heat_out[k], "=", 0)
            add(model.objectives[3], activity, dt)
        for k in problem["heat_demands"]:
            unmet = model.variable(f"heat_unmet_{t}_{k}", 0,
                                   0 if problem["strict"] and dt else step["heat_demand_mwth"][k])
            add(heat_in[k], unmet, 1)
            model.row(heat_in[k], "=", step["heat_demand_mwth"][k])
            add(model.objectives[0], unmet, dt * problem["heat_weight"] * (1001-nodes[k]["params"]["priority"]))
        for thermal, ids in ((False, problem["batteries"]), (True, problem["thermal_stores"])):
            suffix, prefix = ("mwth", "h_") if thermal else ("mw", "")
            for k in ids:
                node, p = nodes[k], nodes[k]["params"]
                capacity = p["capacity_mwhth" if thermal else "capacity_mwh"]
                charge_cap, discharge_cap = (p[f"charge_{suffix}"] if dt else 0), (p[f"discharge_{suffix}"] if dt else 0)
                charge = model.variable(f"{prefix}charge_{t}_{k}", 0, charge_cap)
                discharge = model.variable(f"{prefix}discharge_{t}_{k}", 0, discharge_cap)
                energy = model.variable(f"{prefix}energy_{t}_{k}", 0, capacity)
                mode = model.variable(f"{prefix}mode_{t}_{k}", 0, 1)
                model.binaries.append(mode)
                ins, outs = (heat_in[k], heat_out[k]) if thermal else (sink_terms[k], source_terms[k])
                add(ins, charge, -1)
                add(outs, discharge, -1)
                if k in problem["salt_stores"]:
                    add(sink_terms[k], charge, -p["auxiliary_electric_ratio"])
                    add(sink_terms[k], discharge, -p["auxiliary_electric_ratio"])
                    model.row(sink_terms[k], "=", 0)
                model.row(ins, "=", 0)
                model.row(outs, "=", 0)
                model.row({charge: 1, mode: -charge_cap}, "<=", 0)
                model.row({discharge: 1, mode: discharge_cap}, "<=", discharge_cap)
                decay = math.exp(-p["self_discharge_per_h"] * dt)
                terms = {energy: 1, charge: -p["charge_efficiency"]*dt, discharge: dt/p["discharge_efficiency"]}
                if t:
                    terms[f"{prefix}energy_{t-1}_{k}"] = -decay
                    rhs = 0
                else:
                    rhs = node["energy"] * decay
                model.row(terms, "=", rhs)
                terminal = problem["terminal_heat"] if thermal else problem["terminal"]
                if t == len(problem["steps"])-1 and terminal is not None:
                    model.row({energy: 1}, ">=", terminal*capacity)
                add(model.objectives[2], charge, dt)
                add(model.objectives[2], discharge, dt)
        for i, terms in enumerate(line_terms):
            if problem["links"][i]["carrier"] == "electricity_ac":
                model.row(terms, "<=", problem["links"][i]["capacity_mw"])
        for k, terms in station_terms.items():
            model.row(terms, "<=", nodes[k]["params"]["capacity_mw"])
        model.row(sink_terms["-1"], "<=", problem["grid"])
        for name, value in sink_terms["-1"].items():
            add(model.objectives[1], name, -value*dt)
    return model


def read_solution(solution_path, names_path):
    names = {}
    for line in names_path.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[:2] == ["n", "j"]:
            names[int(parts[2])] = parts[3]
    status, values, objective = "error", {}, None
    form = None
    for line in solution_path.read_text(encoding="utf-8").splitlines():
        p = line.split()
        if not p:
            continue
        if p[0] == "s":
            form = p[1]
            if form == "mip":
                status = {"o": "optimal", "f": "feasible", "n": "infeasible", "u": "error"}.get(p[4], "error")
                objective = float(p[5])
            elif form == "bas":
                status = "optimal" if p[4:6] == ["f", "f"] else ("feasible" if p[4] == "f" else "error")
                objective = float(p[6])
        elif p[0] == "j":
            index = int(p[1])
            values[names[index]] = float(p[2] if form == "mip" else p[3])
    return status, values, objective


def run_glpk(executable, model, stage, locks, directory, deadline, cancel_file=None):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        return {"status": "timeout", "values": {}, "log": "Shared timeout budget exhausted"}
    lp = directory / f"stage{stage}.lp"
    sol = directory / f"stage{stage}.sol"
    names = directory / f"stage{stage}.glp"
    model.write(lp, stage, locks)
    command = [executable, "--lp", str(lp), "--write", str(sol), "--wglp", str(names),
               "--tmlim", str(max(1, int(remaining))), "--mipgap", "0"]
    if getattr(model, "rankine_no_presolve", False):
        command += ["--nopresol", "--nointopt"]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, encoding="utf-8", errors="replace", shell=False)
    timed_out = False
    cancelled = False
    try:
        while True:
            if cancel_file and Path(cancel_file).exists():
                cancelled = True
                process.kill()
                log, _ = process.communicate()
                break
            remaining = deadline-time.monotonic()
            if remaining <= 0:
                timed_out = True
                process.kill()
                log, _ = process.communicate()
                break
            try:
                log, _ = process.communicate(timeout=min(.1, remaining))
                break
            except subprocess.TimeoutExpired:
                continue
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
    if cancelled:
        return {"status": "cancelled", "values": {}, "log": "Cancelled by request"}
    values, status = {}, "timeout" if timed_out else "error"
    if sol.is_file() and names.is_file():
        try:
            status, values, _ = read_solution(sol, names)
        except (ValueError, KeyError, IndexError, OSError) as exc:
            return {"status": "error", "values": {}, "log": f"Malformed GLPK solution: {exc}\n{log[-6000:]}"}
    upper = log.upper()
    timed_out = timed_out or "TIME LIMIT EXCEEDED" in upper
    if status not in ("optimal", "feasible"):
        if timed_out:
            status = "timeout"
        elif any(s in upper for s in ("NO PRIMAL FEASIBLE SOLUTION", "NO INTEGER FEASIBLE SOLUTION",
                                      "PROBLEM HAS NO FEASIBLE SOLUTION")):
            status = "infeasible"
    if process.returncode and not timed_out:
        status = "error"
    return {"status": status, "values": values, "log": log[-6000:], "timed_out": timed_out,
            "returncode": process.returncode}


def assemble_schedule(problem, values):
    """Expose raw decisions and dimensional physical ledgers without clamping."""
    nodes = problem["nodes"]
    energy_before = {k: nodes[k]["energy"] for k in problem["batteries"]+problem["thermal_stores"]}
    reports = []
    for t, step in enumerate(problem["steps"]):
        dt = step["dt_h"]
        devices = {}
        for k, node in nodes.items():
            devices[k] = {"id": node["id"], "kind": node["kind"], "valid": True,
                          "input_mw": 0.0, "output_mw": 0.0, "sent_mw": 0.0,
                          "received_mw": 0.0, "delivered_mw": 0.0, "loss_mw": 0.0}
            if node["kind"] in THERMAL_KINDS:
                devices[k].update(model_profile=rankine_profile(node["kind"]), model_profile_version=1,
                                  input_mwth=0.0, output_mwth=0.0, sent_mwth=0.0,
                                  received_mwth=0.0, loss_mwth=0.0)
        lines = []
        for line in problem["links"]:
            if line["carrier"] == "water_steam":
                detail = {key: line[key] for key in ("index", "from", "to", "mass_flow_capacity_kg_s", "loss_fraction", "from_port", "to_port", "carrier", "unit", "grade_id")}
                detail.update(flow_from=line["from"], flow_to=line["to"], direction=0, active=False, valid=True,
                              sent_kg_s=0., received_kg_s=0., signed_kg_s=0., loss_kg_s=0.,
                              enthalpy_kj_kg=RANKINE_H[line["grade_id"]], enthalpy_flow_mw=0.)
                lines.append(detail)
                continue
            thermal = line["carrier"] in ("heat_water", "heat_oil", "heat_salt")
            suffix = "mwth" if thermal else "mw"
            keys = ("index", "from", "to", f"capacity_{suffix}", "loss_fraction", "from_port", "to_port", "carrier", "unit")
            detail = {key: line[key] for key in keys}
            if thermal:
                detail["grade_id"] = line["grade_id"]
            else:
                detail["voltage_level"] = "AC_BUS"
            detail.update(flow_from=line["from"], flow_to=line["to"], direction=0, active=False, valid=True)
            detail.update({f"sent_{suffix}": 0.0, f"received_{suffix}": 0.0, f"loss_{suffix}": 0.0,
                           f"signed_{suffix}": 0.0})
            lines.append(detail)
        report = {"time_s": step["time_s"], "dt_h": dt, "dt_s": dt*3600, "devices": devices,
                  "lines": lines, "next_states": {}, "path_flows": [], "heat_flows": [],
                  "valid": True, "step_valid": True, "export_mw": 0.0}
        for j, path in enumerate(problem["paths"]):
            sent = values[f"x_{t}_{j}"]
            # Recompute from the original physical parameters, not cached LP coefficients.
            arrived = sent*(1-problem["links"][path["incoming"]]["loss_fraction"])
            after = arrived*(1-nodes[path["station"]]["params"]["loss_fraction"])
            received = after*(1-problem["links"][path["outgoing"]]["loss_fraction"])
            source, station = devices[path["source"]], devices[path["station"]]
            source["sent_mw"] += sent
            source["output_mw"] += sent
            station["input_mw"] += arrived
            station["received_mw"] += arrived
            station["output_mw"] += after
            station["sent_mw"] += after
            station["loss_mw"] += arrived-after
            if path["sink"] == "-1":
                report["export_mw"] += received
                source["delivered_mw"] += received
                station["delivered_mw"] += received
            else:
                sink = devices[path["sink"]]
                sink["input_mw"] += received
                sink["received_mw"] += received
            for i, a, b, send, receive in ((path["incoming"], path["source"], path["station"], sent, arrived),
                                          (path["outgoing"], path["station"], path["sink"], after, received)):
                line = lines[i]
                # Tiny opposite-direction solver roundoff must not reverse a
                # materially charging battery cable. Keep every raw flow value.
                if send > 0 and (not problem["has_rankine"] or send > line["sent_mw"]):
                    line["flow_from"], line["flow_to"] = int(a), int(b)
                    line["direction"] = 1 if line["from"] == int(a) else -1
                line["sent_mw"] += send
                line["received_mw"] += receive
                line["loss_mw"] += send-receive
                line["signed_mw"] = line["direction"]*line["sent_mw"]
            report["path_flows"].append({"source_id": int(path["source"]), "station_id": int(path["station"]),
                                         "sink_id": int(path["sink"]), "sent_mw": sent})
        for i in problem["heat_links"]:
            line = lines[i]
            sent = values[f"heat_{t}_{i}"]
            received = sent*(1-line["loss_fraction"])
            line.update(sent_mwth=sent, received_mwth=received, loss_mwth=sent-received,
                        signed_mwth=sent, direction=1 if sent > 0 else 0)
            source, sink = devices[str(line["from"])], devices[str(line["to"])]
            source["output_mwth"] += sent
            source["sent_mwth"] += sent
            sink["input_mwth"] += received
            sink["received_mwth"] += received
            report["heat_flows"].append({"line_index": i, "sent_mwth": sent})
        if problem["has_rankine"]:
            report["mass_flows"] = []
            for i in problem["mass_links"]:
                line = lines[i]
                mass = values[f"mass_{t}_{i}"]
                line.update(sent_kg_s=mass, received_kg_s=mass, signed_kg_s=mass,
                            direction=1 if mass > 0 else 0,
                            enthalpy_flow_mw=mass*RANKINE_H[line["grade_id"]]/1000)
                report["mass_flows"].append({"line_index": i, "sent_kg_s": mass})
            for k in problem["rankine_ids"]:
                detail = devices[k]
                detail.update(rankine_device_metrics(nodes[k], values[f"rankine_{t}_{k}"], step["weather"]))
        for k in problem["generators"]:
            detail, available = devices[k], step["available_mw"][k]
            detail.update(available_mw=available, generated_mw=available, mw=available,
                          curtailed_mw=values[f"curt_{t}_{k}"], produced_mw=detail["output_mw"])
        for thermal, ids in ((False, problem["loads"]), (True, problem["heat_demands"])):
            suffix, prefix = ("mwth", "heat_") if thermal else ("mw", "")
            for k in ids:
                detail = devices[k]
                detail.update({f"demand_{suffix}": step["heat_demand_mwth" if thermal else "demand_mw"][k],
                               f"served_{suffix}": detail[f"input_{suffix}"],
                               f"unserved_{suffix}": values[f"{prefix}unmet_{t}_{k}"],
                               "priority": nodes[k]["params"]["priority"]})
        for k in problem["boilers"]:
            detail = devices[k]
            power = values[f"boiler_{t}_{k}"]
            heat = power*nodes[k]["params"]["thermal_efficiency"]
            detail.update(boiler_electric_mw=power, boiler_heat_mwth=heat,
                          boiler_conversion_loss_mw=power-heat, thermal_efficiency=nodes[k]["params"]["thermal_efficiency"])
        for k in problem["source_collectors"]:
            detail, p = devices[k], nodes[k]["params"]
            physics = collector_physics(nodes[k], step["weather"])
            useful = values[f"solar_{t}_{k}"]
            detail.update(physics)
            if nodes[k]["kind"] == "parabolic_trough":
                detail.update(dni_wm2=step["weather"]["dni_wm2"] if step["weather"].get("is_day", True) and step["weather"]["solar_altitude_deg"] > 0 else 0.,
                              mean_fluid_temp_c=250., area_basis="aperture", irradiance_kind="dni",
                              tracking_axis="north_south_horizontal", fluid="Therminol66")
            detail.update(useful_mwth=useful, heat_output_mwth=useful,
                          curtailed_mwth=physics["available_mwth"]-useful,
                          auxiliary_electric_mw=useful*p["auxiliary_electric_ratio"])
        for k in problem["fuel_boilers"]:
            detail, p = devices[k], nodes[k]["params"]
            fuel = values[f"fuel_{t}_{k}"]
            auxiliary = fuel*p["auxiliary_electric_ratio"]
            detail.update(fuel_input_mw=fuel,
                          fuel_volume_nm3_per_h=fuel*1000/problem["fuel_supply"]["lower_heating_value_kwh_per_nm3"],
                          fuel_cost_per_h=fuel*problem["fuel_supply"]["price_per_mwh"],
                          heat_output_mwth=fuel*p["thermal_efficiency"],
                          conversion_loss_mw=fuel*(1-p["thermal_efficiency"]),
                          auxiliary_electric_mw=auxiliary, auxiliary_electric_loss_mw=auxiliary)
        for k in problem["exchangers"]:
            detail, p = devices[k], nodes[k]["params"]
            activity = values[f"exchange_{t}_{k}"]
            detail.update(hot_input_mwth=activity, warm_output_mwth=activity*p["transfer_efficiency"],
                          exchanger_loss_mwth=activity*(1-p["transfer_efficiency"]),
                          loss_mwth=activity*(1-p["transfer_efficiency"]), capacity_mwth=p["capacity_mwth"],
                          hot_grade_id=PRIMARY_GRADE, warm_grade_id=SECONDARY_GRADE,
                          hot_supply_c=90.0, hot_return_c=60.0, cold_supply_c=70.0, cold_return_c=40.0,
                          min_approach_k=p["min_approach_k"])
            if k in problem["oil_exchangers"]:
                detail.update(hot_grade_id=OIL_GRADE, warm_grade_id=PRIMARY_GRADE,
                              hot_supply_c=300., hot_return_c=200., cold_supply_c=90., cold_return_c=60.,
                              auxiliary_electric_mw=activity*p["auxiliary_electric_ratio"])
        for thermal, ids in ((False, problem["batteries"]), (True, problem["thermal_stores"])):
            suffix, energy_unit, prefix = ("mwth", "mwhth", "h_") if thermal else ("mw", "mwh", "")
            for k in ids:
                detail, p = devices[k], nodes[k]["params"]
                before = energy_before[k]
                decay = before*math.exp(-p["self_discharge_per_h"]*dt)
                energy = values[f"{prefix}energy_{t}_{k}"]
                charge, discharge = values[f"{prefix}charge_{t}_{k}"], values[f"{prefix}discharge_{t}_{k}"]
                conversion = charge*(1-p["charge_efficiency"])+discharge*(1/p["discharge_efficiency"]-1)
                capacity = p[f"capacity_{energy_unit}"]
                detail.update({f"energy_before_{energy_unit}": before,
                               f"energy_after_self_discharge_{energy_unit}": decay,
                               f"self_discharge_{energy_unit}": before-decay, f"energy_{energy_unit}": energy,
                               f"next_energy_{energy_unit}": energy, "soc_before": before/capacity, "soc": energy/capacity,
                               f"capacity_{energy_unit}": capacity, f"charge_{suffix}": charge, f"discharge_{suffix}": discharge,
                               "mode": "charge" if charge > ABS_TOL else ("discharge" if discharge > ABS_TOL else "idle"),
                               "mode_binary": values[f"{prefix}mode_{t}_{k}"],
                               f"storage_conversion_loss_{suffix}": conversion,
                               f"storage_loss_{suffix}": conversion+(before-decay)/dt if dt else 0.0})
                if nodes[k]["kind"] in ELECTRIC_STORAGE_KINDS:
                    detail.update(charge_conversion_loss_mw=charge*(1-p["charge_efficiency"]),
                                  discharge_conversion_loss_mw=discharge*(1/p["discharge_efficiency"]-1))
                if nodes[k]["kind"] == "hydrogen_storage_system":
                    detail.update(hydrogen_charge_loss_mw=charge*(1-p["charge_efficiency"]),
                                  hydrogen_discharge_loss_mw=discharge*(1/p["discharge_efficiency"]-1),
                                  hydrogen_produced_mw_lhv=charge*p["charge_efficiency"],
                                  hydrogen_consumed_mw_lhv=discharge/p["discharge_efficiency"],
                                  hydrogen_mass_kg=energy*1000/HYDROGEN_LHV_KWH_PER_KG,
                                  hydrogen_energy_basis="LHV")
                if k in problem["salt_stores"]:
                    detail["auxiliary_electric_mw"] = (charge+discharge)*p["auxiliary_electric_ratio"]
                report["next_states"][k] = {f"energy_{energy_unit}": energy}
                energy_before[k] = energy
        for k, detail in devices.items():
            if detail["kind"] == "station":
                detail["capacity_mw"] = nodes[k]["params"]["capacity_mw"]
                detail["utilization"] = detail["input_mw"]/detail["capacity_mw"]
        for line in lines:
            if line["carrier"] == "water_steam":
                line["active"] = line["sent_kg_s"] > ABS_TOL
                cap = line["mass_flow_capacity_kg_s"]
                line["utilization"] = line["sent_kg_s"]/cap if cap else 0.
                continue
            suffix = "mwth" if line["carrier"] in ("heat_water", "heat_oil", "heat_salt") else "mw"
            line["active"] = line[f"sent_{suffix}"] > ABS_TOL
            line["utilization"] = line[f"sent_{suffix}"]/line[f"capacity_{suffix}"] if line[f"capacity_{suffix}"] else 0.0
        for kind in ("wind", "pv"):
            report[kind+"_mw"] = sum(step["available_mw"][k] for k in problem["generators"] if nodes[k]["kind"] == kind)
        for key, ids in (("available_mw", problem["generators"]), ("curtailed_mw", problem["generators"]),
                         ("demand_mw", problem["loads"]), ("served_mw", problem["loads"]), ("unserved_mw", problem["loads"]),
                         ("charge_mw", problem["batteries"]), ("discharge_mw", problem["batteries"]),
                         ("energy_mwh", problem["batteries"]), ("self_discharge_mwh", problem["batteries"]),
                         ("storage_loss_mw", problem["batteries"]), ("storage_conversion_loss_mw", problem["batteries"]),
                         ("boiler_electric_mw", problem["boilers"]), ("boiler_conversion_loss_mw", problem["boilers"])):
            report[key] = sum(devices[k][key] for k in ids)
        fuel = {key: sum(devices[k]["fuel_"+key if key in ("input_mw", "volume_nm3_per_h", "cost_per_h") else key]
                         for k in problem["fuel_boilers"]) for key in FUEL_FIELDS}
        fuel["balance_error_mw"] = fuel["input_mw"]+fuel["auxiliary_electric_mw"]-fuel["heat_output_mwth"]-fuel["conversion_loss_mw"]-fuel["auxiliary_electric_loss_mw"]
        fuel["energy_balance_error_mwh"] = fuel["balance_error_mw"]*dt
        report["fuel"] = fuel
        solar = {field: sum(devices[k][field] for k in problem["source_collectors"]) for field in SOLAR_FIELDS}
        salt_aux = sum(devices[k]["auxiliary_electric_mw"] for k in problem["salt_stores"])
        oil_aux = sum(devices[k]["auxiliary_electric_mw"] for k in problem["oil_exchangers"])
        if problem["has_high_temp"]:
            report["high_temp"] = high_temp_ledger(problem, report)
        if problem["has_tower"]:
            report["tower"] = tower_ledger(problem, report)
        oil_warm = sum(devices[k]["warm_output_mwth"] for k in problem["oil_exchangers"])
        if problem["solar_collectors"]:
            report["solar"] = {field: sum(devices[k][field] for k in problem["solar_collectors"]) for field in SOLAR_FIELDS}
        cycle = rankine_ledger(problem, report) if problem["has_rankine"] else {"gross_electric_mw": 0., "auxiliary_electric_mw": 0.}
        if problem["has_rankine"]:
            report["rankine"] = cycle
        report["generated_mw"] = report["available_mw"]
        report["produced_mw"] = report["available_mw"]-report["curtailed_mw"]
        if problem["has_rankine"]:
            report["generated_mw"] += cycle["gross_electric_mw"]
            report["produced_mw"] += cycle["gross_electric_mw"]
        report["delivered_mw"] = report["export_mw"]
        report["line_loss_mw"] = sum(line["loss_mw"] for line in lines if line["carrier"] == "electricity_ac")
        report["station_loss_mw"] = sum(detail["loss_mw"] for detail in devices.values() if detail["kind"] == "station")
        report["loss_mw"] = report["line_loss_mw"]+report["station_loss_mw"]
        report["network_loss_mw"] = report["loss_mw"]
        report["total_loss_mw"] = report["loss_mw"]+report["storage_loss_mw"]
        capacity = sum(nodes[k]["params"]["capacity_mwh"] for k in problem["batteries"])
        report["soc"] = report["energy_mwh"]/capacity if capacity else 0.0
        report["balance_error_mw"] = (report["produced_mw"]+report["discharge_mw"]-report["served_mw"]
                                      -report["charge_mw"]-report["boiler_electric_mw"]-fuel["auxiliary_electric_mw"]-solar["auxiliary_electric_mw"]-oil_aux-salt_aux-report["export_mw"]-report["loss_mw"])
        before_total = sum(devices[k]["energy_before_mwh"] for k in problem["batteries"])
        report["energy_balance_error_mwh"] = ((report["produced_mw"]-report["served_mw"]-report["boiler_electric_mw"]-fuel["auxiliary_electric_mw"]-solar["auxiliary_electric_mw"]-oil_aux-salt_aux
                                              -report["export_mw"]-report["total_loss_mw"])*dt+before_total-report["energy_mwh"])
        if problem["has_rankine"]:
            report["balance_error_mw"] -= cycle["auxiliary_electric_mw"]
            report["energy_balance_error_mwh"] -= cycle["auxiliary_electric_mw"]*dt
        thermal = {}
        for key, ids in (("demand_mwth", problem["heat_demands"]), ("served_mwth", problem["heat_demands"]),
                         ("unserved_mwth", problem["heat_demands"]), ("boiler_heat_mwth", problem["boilers"]),
                         ("charge_mwth", problem["water_stores"]), ("discharge_mwth", problem["water_stores"]),
                         ("energy_mwhth", problem["water_stores"]), ("self_discharge_mwhth", problem["water_stores"]),
                         ("storage_conversion_loss_mwth", problem["water_stores"]),
                         ("storage_loss_mwth", problem["water_stores"]), ("exchanger_loss_mwth", problem["water_exchangers"])):
            thermal[key] = sum(devices[k][key] for k in ids)
        thermal["network_loss_mwth"] = sum(lines[i]["loss_mwth"] for i in problem["heat_links"])
        capacity = sum(nodes[k]["params"]["capacity_mwhth"] for k in problem["water_stores"])
        thermal["soc"] = thermal["energy_mwhth"]/capacity if capacity else 0.0
        thermal["balance_error_mwth"] = (thermal["boiler_heat_mwth"]+fuel["heat_output_mwth"]+sum(devices[k]["useful_mwth"] for k in problem["solar_collectors"])+oil_warm+thermal["discharge_mwth"]-thermal["served_mwth"]
                                         -thermal["charge_mwth"]-thermal["exchanger_loss_mwth"]-thermal["network_loss_mwth"])
        before_total = sum(devices[k]["energy_before_mwhth"] for k in problem["water_stores"])
        thermal["energy_balance_error_mwhth"] = ((thermal["boiler_heat_mwth"]+fuel["heat_output_mwth"]+sum(devices[k]["useful_mwth"] for k in problem["solar_collectors"])+oil_warm-thermal["served_mwth"]-thermal["exchanger_loss_mwth"]
                                                 -thermal["network_loss_mwth"]-thermal["storage_loss_mwth"])*dt
                                                +before_total-thermal["energy_mwhth"])
        report["thermal"] = thermal
        reports.append(report)
    return reports



def high_temp_ledger(problem, report):
    """Oil-grade balance independently assembled from device ports/inventories.

    Exchanger output crosses into the primary-water ledger. Auxiliary electric
    inputs are separate dissipation, never thermal output or inventory gain.
    """
    devices, dt = report["devices"], report["dt_h"]
    high = {field: sum(devices[k][field] for k in problem["troughs"]) for field in SOLAR_FIELDS}
    high["collector_auxiliary_electric_mw"] = high["auxiliary_electric_mw"]
    high["oil_auxiliary_electric_mw"] = sum(devices[k]["auxiliary_electric_mw"] for k in problem["oil_exchangers"])
    high["auxiliary_electric_mw"] += high["oil_auxiliary_electric_mw"]
    high["oil_water_output_mwth"] = sum(devices[k]["output_mwth"] for k in problem["oil_exchangers"])
    high["exchanger_loss_mwth"] = sum(devices[k]["input_mwth"]-devices[k]["output_mwth"] for k in problem["oil_exchangers"])
    for field in ("charge_mwth", "discharge_mwth", "storage_conversion_loss_mwth", "storage_loss_mwth",
                  "self_discharge_mwhth", "energy_mwhth"):
        high[field] = sum(devices[k][field] for k in problem["high_stores"])
    capacity = sum(problem["nodes"][k]["params"]["capacity_mwhth"] for k in problem["high_stores"])
    high["soc"] = high["energy_mwhth"]/capacity if capacity else 0.
    source = sum(devices[k]["output_mwth"] for k in problem["troughs"])
    high["balance_error_mwth"] = source+high["discharge_mwth"]-high["charge_mwth"]-high["oil_water_output_mwth"]-high["exchanger_loss_mwth"]
    before = sum(devices[k]["energy_before_mwhth"] for k in problem["high_stores"])
    high["energy_balance_error_mwhth"] = (source-high["oil_water_output_mwth"]-high["exchanger_loss_mwth"]-high["storage_loss_mwth"])*dt+before-high["energy_mwhth"]
    if problem["has_rankine"]:
        draw = sum(devices[k]["input_mwth"] for k in problem["rankine_ids"] if problem["nodes"][k]["kind"] == "steam_generator")
        high["rankine_oil_input_mwth"] = draw
        high["balance_error_mwth"] -= draw
        high["energy_balance_error_mwhth"] -= draw*dt
    return high



def tower_ledger(problem, report):
    """Independent salt inventory ledger; SG heat and auxiliaries belong to Rankine."""
    devices, dt = report["devices"], report["dt_h"]
    tower = {field: sum(devices[k][field] for k in problem["receivers"]) for field in SOLAR_FIELDS}
    tower["receiver_auxiliary_electric_mw"] = tower["auxiliary_electric_mw"]
    tower["store_auxiliary_electric_mw"] = sum(devices[k]["auxiliary_electric_mw"] for k in problem["salt_stores"])
    tower["auxiliary_electric_mw"] += tower["store_auxiliary_electric_mw"]
    tower["rankine_salt_input_mwth"] = sum(devices[k]["input_mwth"] for k in problem["rankine_ids"]
                                         if problem["nodes"][k]["kind"] == "salt_steam_generator")
    for field in ("charge_mwth", "discharge_mwth", "storage_conversion_loss_mwth", "storage_loss_mwth",
                  "self_discharge_mwhth", "energy_mwhth"):
        tower[field] = sum(devices[k][field] for k in problem["salt_stores"])
    capacity = sum(problem["nodes"][k]["params"]["capacity_mwhth"] for k in problem["salt_stores"])
    tower["soc"] = tower["energy_mwhth"]/capacity if capacity else 0.
    source = sum(devices[k]["output_mwth"] for k in problem["receivers"])
    draw = tower["rankine_salt_input_mwth"]
    tower["balance_error_mwth"] = source+tower["discharge_mwth"]-tower["charge_mwth"]-draw
    before = sum(devices[k]["energy_before_mwhth"] for k in problem["salt_stores"])
    tower["energy_balance_error_mwhth"] = (source-draw-tower["storage_loss_mwth"])*dt+before-tower["energy_mwhth"]
    return tower


def rankine_device_metrics(node, mass, weather):
    p, kind = node["params"], node["kind"]
    c = rankine_coefficients()
    result = {"mass_flow_kg_s": mass}
    if kind in ("steam_generator", "salt_steam_generator"):
        heat = mass*c["steam_heat"]
        oil = heat/p["transfer_efficiency"]
        result.update(steam_heat_mwth=heat, loss_mwth=oil-heat,
                      auxiliary_electric_mw=oil*p["auxiliary_electric_ratio"])
        result["salt_input_mwth" if kind == "salt_steam_generator" else "oil_input_mwth"] = oil
    elif kind == "steam_turbine":
        gross = mass*c["shaft"]*p["generator_efficiency"]
        result.update(mw=gross, generated_mw=gross, gross_electric_mw=gross,
                      generator_loss_mw=mass*c["shaft"]-gross)
    elif kind == "steam_condenser":
        reject = mass*c["rejection"]
        result.update(condenser_rejection_mwth=reject, available_rejection_mwth=condenser_capacity(p, weather),
                      auxiliary_electric_mw=reject*p["auxiliary_electric_ratio"])
    elif kind == "feedwater_pump":
        hydraulic = mass*c["pump_work"]
        power = hydraulic/p["motor_efficiency"]
        result.update(pump_electric_mw=power, auxiliary_electric_mw=power,
                      pump_hydraulic_mw=hydraulic, pump_motor_loss_mw=power-hydraulic)
    return result


def rankine_ledger(problem, report):
    devices = report["devices"]
    ids = {kind: [k for k in problem["rankine_ids"] if problem["nodes"][k]["kind"] == kind] for kind in RANKINE_KINDS}
    def total(kind, field):
        return sum(devices[k][field] for k in ids[kind])
    result = {"mass_flow_kg_s": total("steam_generator", "mass_flow_kg_s"),
              "oil_input_mwth": total("steam_generator", "oil_input_mwth"),
              "steam_heat_mwth": total("steam_generator", "steam_heat_mwth"),
              "gross_electric_mw": total("steam_turbine", "gross_electric_mw"),
              "condenser_rejection_mwth": total("steam_condenser", "condenser_rejection_mwth"),
              "generator_loss_mw": total("steam_turbine", "generator_loss_mw"),
              "pump_hydraulic_mw": total("feedwater_pump", "pump_hydraulic_mw"),
              "pump_motor_loss_mw": total("feedwater_pump", "pump_motor_loss_mw"),
              "steam_generator_loss_mwth": total("steam_generator", "loss_mwth"),
              "sg_auxiliary_electric_mw": total("steam_generator", "auxiliary_electric_mw"),
              "cooling_auxiliary_electric_mw": total("steam_condenser", "auxiliary_electric_mw"),
              "pump_electric_mw": total("feedwater_pump", "pump_electric_mw")}
    if problem["has_tower"]:
        result["salt_input_mwth"] = total("salt_steam_generator", "salt_input_mwth")
        for field in ("mass_flow_kg_s", "steam_heat_mwth"):
            result[field] += total("salt_steam_generator", field)
        result["steam_generator_loss_mwth"] += total("salt_steam_generator", "loss_mwth")
        result["sg_auxiliary_electric_mw"] += total("salt_steam_generator", "auxiliary_electric_mw")
    result["auxiliary_electric_mw"] = result["sg_auxiliary_electric_mw"]+result["cooling_auxiliary_electric_mw"]+result["pump_electric_mw"]
    result["net_electric_mw"] = result["gross_electric_mw"]-result["auxiliary_electric_mw"]
    result["balance_error_mw"] = (result["oil_input_mwth"]+result.get("salt_input_mwth", 0.)+result["pump_electric_mw"]-result["gross_electric_mw"]-
        result["condenser_rejection_mwth"]-result["generator_loss_mw"]-result["steam_generator_loss_mwth"]-result["pump_motor_loss_mw"])
    return result


def validate_schedule(problem, reports):
    """Independent topology/parameter audit; reported zero residuals prove nothing."""
    errors, maximum = [], 0.0

    def equal(a, b, label):
        nonlocal maximum
        if isinstance(a, bool) or isinstance(b, bool) or not isinstance(a, (int, float)) or not isinstance(b, (int, float)) or not math.isfinite(a) or not math.isfinite(b):
            errors.append(label+": nonfinite/nonnumeric value")
            return
        residual = abs(a-b)
        maximum = max(maximum, residual)
        if residual > ABS_TOL+REL_TOL*max(abs(a), abs(b)):
            errors.append(f"{label}: residual {residual:.8g}")

    def bound(value, low, high, label):
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < low-ABS_TOL-REL_TOL*abs(low) or value > high+ABS_TOL+REL_TOL*abs(high):
            errors.append(f"{label}: {value} outside [{low}, {high}]")

    def same(actual, expected, label):
        if actual != expected:
            errors.append(label+": incompatible structure/identity")

    nodes = problem["nodes"]
    storage = problem["batteries"]+problem["thermal_stores"]
    prior = {k: nodes[k]["energy"] for k in storage}
    if len(reports) != len(problem["steps"]):
        return {"valid": False, "errors": ["Wrong schedule length"], "max_residual": 0.0}
    try:
        for t, (step, report) in enumerate(zip(problem["steps"], reports)):
            label = f"step {t}"
            dt = step["dt_h"]
            devices = report["devices"]
            same(set(devices), set(nodes), label+" device IDs")
            same(len(report["lines"]), len(problem["links"]), label+" line count")
            same(set(report["next_states"]), set(storage), label+" next state IDs")
            equal(report["time_s"], step["time_s"], label+" time")
            equal(report["dt_h"], dt, label+" duration")
            equal(report["dt_s"], dt*3600, label+" duration seconds")
            incoming, outgoing = {k: 0.0 for k in nodes}, {k: 0.0 for k in nodes}
            heat_in, heat_out = {k: 0.0 for k in nodes}, {k: 0.0 for k in nodes}
            mass_in, mass_out = {k: 0.0 for k in nodes}, {k: 0.0 for k in nodes}
            export, line_loss, heat_loss = 0.0, 0.0, 0.0
            for expected, line in zip(problem["links"], report["lines"]):
                for key in ("index", "from", "to", "from_port", "to_port", "carrier", "unit"):
                    same(line[key], expected[key], label+" line "+key)
                a, b = str(line["flow_from"]), str(line["flow_to"])
                same({a, b}, {str(expected["from"]), str(expected["to"])}, label+" line endpoints")
                if expected["carrier"] == "water_steam":
                    same((a, b), (str(expected["from"]), str(expected["to"])), label+" Rankine mass direction")
                    same((line["from_port"], line["to_port"], line["grade_id"]),
                         RANKINE_ROUTES.get((nodes[a]["kind"], nodes[b]["kind"])), label+" fixed-state mass route")
                    same(line["grade_id"], expected["grade_id"], label+" mass state grade")
                    if any(key in line for key in ("sent_mw", "capacity_mw", "sent_mwth", "capacity_mwth")):
                        errors.append(label+": mass line mixes electric/heat capacity units")
                    sent = line["sent_kg_s"]
                    bound(sent, 0, expected["mass_flow_capacity_kg_s"] if dt else 0, label+" mass line capacity")
                    equal(line["mass_flow_capacity_kg_s"], expected["mass_flow_capacity_kg_s"], label+" mass capacity metadata")
                    equal(line["received_kg_s"], sent, label+" closed mass line delivery")
                    equal(line["signed_kg_s"], sent, label+" mass signed direction")
                    equal(line["loss_kg_s"], 0, label+" no invented mass loss")
                    equal(line["loss_fraction"], 0, label+" mass line loss setting")
                    equal(line["enthalpy_kj_kg"], RANKINE_H[expected["grade_id"]], label+" immutable mass-state enthalpy")
                    equal(line["enthalpy_flow_mw"], sent*RANKINE_H[expected["grade_id"]]/1000, label+" mass enthalpy transport")
                    same(line["direction"], 1 if sent > 0 else 0, label+" mass line direction metadata")
                    mass_out[a] += sent
                    mass_in[b] += sent
                    continue
                thermal = expected["carrier"] in ("heat_water", "heat_oil", "heat_salt")
                suffix = "mwth" if thermal else "mw"
                sent, received = line[f"sent_{suffix}"], line[f"received_{suffix}"]
                if thermal:
                    same((a, b), (str(expected["from"]), str(expected["to"])), label+" heat direction")
                    same(line["grade_id"], expected["grade_id"], label+" heat grade")
                    same((line["from_port"], line["to_port"], line["grade_id"]),
                         THERMAL_ROUTES.get((nodes[a]["kind"], nodes[b]["kind"])), label+" allowed heat route")
                    equal(expected["loss_fraction"], 0, label+" stage1 heat edge loss")
                    if "sent_mw" in line or "capacity_mw" in line:
                        errors.append(label+": heat line mixes electrical units")
                elif line["flow_from"] != expected["from"] and not (
                        nodes.get(a, {}).get("kind") in ELECTRIC_STORAGE_KINDS or nodes.get(b, {}).get("kind") in ELECTRIC_STORAGE_KINDS):
                    errors.append(label+": illegal electric line reversal")
                bound(sent, 0, expected[f"capacity_{suffix}"], label+" line cap")
                bound(received, 0, expected[f"capacity_{suffix}"], label+" received flow")
                equal(line[f"capacity_{suffix}"], expected[f"capacity_{suffix}"], label+" line rated capacity")
                equal(line["loss_fraction"], expected["loss_fraction"], label+" line loss setting")
                equal(received, sent*(1-expected["loss_fraction"]), label+" line delivery")
                equal(line[f"loss_{suffix}"], sent-received, label+" line loss")
                if not dt:
                    equal(sent, 0, label+" paused flow")
                if thermal:
                    heat_out[a] += sent
                    heat_in[b] += received
                    heat_loss += sent-received
                else:
                    outgoing[a] += sent
                    line_loss += sent-received
                    if b == "-1":
                        export += received
                    else:
                        incoming[b] += received
            tower_expected = {key: 0.0 for key in SOLAR_FIELDS}
            salt_aux = 0.0
            trough_expected = {key: 0.0 for key in SOLAR_FIELDS}
            oil_aux = 0.0
            oil_warm = 0.0
            solar_expected = {key: 0.0 for key in SOLAR_FIELDS}
            fuel_expected = {key: 0.0 for key in FUEL_FIELDS}
            station_loss, boiler_power, boiler_heat, boiler_loss, exchanger_loss = 0.0, 0.0, 0.0, 0.0, 0.0
            sums = {False: {"before": 0.0, "energy": 0.0, "charge": 0.0, "discharge": 0.0, "conversion": 0.0, "self": 0.0},
                    True: {"before": 0.0, "energy": 0.0, "charge": 0.0, "discharge": 0.0, "conversion": 0.0, "self": 0.0}}
            for k, node in nodes.items():
                detail, params, kind = devices[k], node["params"], node["kind"]
                same(detail["id"], node["id"], label+" device id")
                same(detail["kind"], kind, label+" device kind")
                equal(detail["input_mw"], incoming[k], label+f" device {k} electric input")
                equal(detail["output_mw"], outgoing[k], label+f" device {k} electric output")
                if kind in THERMAL_KINDS:
                    same(detail["model_profile"], rankine_profile(kind), label+" thermal profile")
                    same(detail["model_profile_version"], 1, label+" thermal profile version")
                    equal(detail["input_mwth"], heat_in[k], label+f" device {k} thermal input")
                    equal(detail["output_mwth"], heat_out[k], label+f" device {k} thermal output")
                if kind in ("wind", "pv"):
                    equal(outgoing[k]+detail["curtailed_mw"], step["available_mw"][k], label+" source balance")
                    equal(detail["available_mw"], step["available_mw"][k], label+" source available")
                    equal(detail["produced_mw"], outgoing[k], label+" source production")
                    bound(detail["curtailed_mw"], 0, step["available_mw"][k], label+" curtailment")
                elif kind in RANKINE_KINDS:
                    mass = mass_in[k]
                    equal(mass_out[k], mass, label+f" Rankine {k} closed mass balance")
                    bound(mass, 0, 10000 if dt else 0, label+" nonnegative Rankine mass activity")
                    operating = {ident for loop in rankine_loops(nodes, problem["links"]) for ident in loop}
                    if k not in operating:
                        equal(mass, 0, label+" incomplete or cross-loop Rankine circuit cannot operate")
                    # Derived solely from original fixed states and reported physical
                    # port flows; the optimized activity and LP rows are not trusted.
                    expected_metrics = rankine_device_metrics(node, mass, step["weather"])
                    for field, expected_value in expected_metrics.items():
                        equal(detail[field], expected_value, label+" Rankine "+kind+" "+field)
                    if kind in ("steam_generator", "salt_steam_generator"):
                        bound(heat_in[k], 0, params["capacity_mwth"], label+" SG oil input capacity")
                        equal(heat_in[k], expected_metrics["salt_input_mwth" if kind == "salt_steam_generator" else "oil_input_mwth"], label+" SG accepted oil to steam enthalpy rise")
                    else:
                        equal(heat_in[k], 0, label+" Rankine non-SG has no oil input")
                    equal(heat_out[k], 0, label+" Rankine cannot create water/oil grade heat")
                    if kind == "steam_turbine":
                        bound(mass, 0, params["mass_flow_capacity_kg_s"], label+" turbine mass rating")
                        equal(outgoing[k], expected_metrics["gross_electric_mw"], label+" turbine shaft to accepted AC")
                        equal(incoming[k], 0, label+" turbine has no AC input")
                    else:
                        equal(incoming[k], expected_metrics["auxiliary_electric_mw"], label+" Rankine external auxiliary AC")
                        equal(outgoing[k], 0, label+" Rankine auxiliary cannot generate electricity")
                    if kind == "steam_condenser":
                        bound(expected_metrics["condenser_rejection_mwth"], 0,
                              condenser_capacity(params, step["weather"]), label+" ambient-limited condenser rejection")
                    if kind == "feedwater_pump":
                        bound(mass, 0, params["mass_flow_capacity_kg_s"], label+" pump mass rating")
                elif kind == "station":
                    bound(incoming[k], 0, params["capacity_mw"], label+" station cap")
                    equal(outgoing[k], incoming[k]*(1-params["loss_fraction"]), label+" station balance")
                    equal(detail["loss_mw"], incoming[k]-outgoing[k], label+" station loss")
                    station_loss += incoming[k]-outgoing[k]
                elif kind in ("load", "heat_demand"):
                    thermal = kind == "heat_demand"
                    suffix = "mwth" if thermal else "mw"
                    demand = step["heat_demand_mwth" if thermal else "demand_mw"][k]
                    served = heat_in[k] if thermal else incoming[k]
                    equal(detail[f"demand_{suffix}"], demand, label+" requested demand")
                    equal(detail[f"served_{suffix}"], served, label+" served demand")
                    equal(served+detail[f"unserved_{suffix}"], demand, label+" demand balance")
                    bound(served, 0, demand, label+" demand bound")
                    bound(detail[f"unserved_{suffix}"], 0, demand, label+" unmet bound")
                    if problem["strict"] and dt:
                        equal(detail[f"unserved_{suffix}"], 0, label+" strict supply")
                elif kind == "electric_boiler":
                    power = incoming[k]
                    heat = power*params["thermal_efficiency"]
                    bound(power, 0, params["rated_electric_mw"], label+" boiler rating")
                    equal(heat_out[k], heat, label+" boiler conversion and accepted heat")
                    equal(detail["boiler_electric_mw"], power, label+" raw boiler activity")
                    equal(detail["boiler_heat_mwth"], heat, label+" boiler heat")
                    equal(detail["boiler_conversion_loss_mw"], power-heat, label+" boiler loss")
                    boiler_power += power
                    boiler_heat += heat
                    boiler_loss += power-heat
                elif kind in ("solar_thermal", "parabolic_trough", "solar_tower_receiver"):
                    # Recompute the source from original weather, never the cached LP bound.
                    expected = collector_physics(node, step["weather"])
                    useful = heat_out[k]
                    if kind == "parabolic_trough":
                        for field, expected_value in (("mean_fluid_temp_c", 250.), ("area_basis", "aperture"),
                                                      ("irradiance_kind", "dni"), ("tracking_axis", "north_south_horizontal"),
                                                      ("fluid", "Therminol66")):
                            same(detail[field], expected_value, label+" trough metadata "+field)
                        effective_dni = step["weather"]["dni_wm2"] if step["weather"].get("is_day", True) and step["weather"]["solar_altitude_deg"] > 0 else 0.
                        equal(detail["dni_wm2"], effective_dni, label+" independent trough DNI")
                    bound(useful, 0, expected["available_mwth"] if dt else 0, label+" solar weather availability")
                    expected.update(useful_mwth=useful, curtailed_mwth=expected["available_mwth"]-useful,
                                    auxiliary_electric_mw=useful*params["auxiliary_electric_ratio"])
                    equal(incoming[k], expected["auxiliary_electric_mw"], label+" solar auxiliary AC coupling")
                    equal(detail["heat_output_mwth"], useful, label+" solar accepted heat")
                    equal(expected["incident_mw"], expected["optical_rejection_mw"]+expected["thermal_loss_mw"]+expected["curtailed_mwth"]+useful,
                          label+" independent solar energy conservation")
                    for field, value in expected.items():
                        equal(detail[field], value, label+" solar device "+field)
                        if field in SOLAR_FIELDS:
                            solar_expected[field] += value
                            if kind == "solar_tower_receiver":
                                tower_expected[field] += value
                            if kind == "parabolic_trough":
                                trough_expected[field] += value
                elif kind == "fuel_boiler":
                    fuel = detail["fuel_input_mw"]
                    bound(fuel, 0, params["rated_fuel_mw"] if dt else 0, label+" fuel boiler rating")
                    heat = fuel*params["thermal_efficiency"]
                    auxiliary = fuel*params["auxiliary_electric_ratio"]
                    expected = {"input_mw": fuel,
                                "volume_nm3_per_h": fuel*1000/problem["fuel_supply"]["lower_heating_value_kwh_per_nm3"],
                                "cost_per_h": fuel*problem["fuel_supply"]["price_per_mwh"],
                                "heat_output_mwth": heat, "conversion_loss_mw": fuel-heat,
                                "auxiliary_electric_mw": auxiliary, "auxiliary_electric_loss_mw": auxiliary}
                    equal(incoming[k], auxiliary, label+" fuel auxiliary AC coupling")
                    equal(heat_out[k], heat, label+" fuel conversion and accepted heat")
                    for field, value in expected.items():
                        device_field = "fuel_"+field if field in ("input_mw", "volume_nm3_per_h", "cost_per_h") else field
                        equal(detail[device_field], value, label+" fuel device "+field)
                        fuel_expected[field] += value
                elif kind in ("heat_exchanger", "oil_water_exchanger"):
                    bound(heat_in[k], 0, params["capacity_mwth"], label+" exchanger hot-side rating")
                    equal(heat_out[k], heat_in[k]*params["transfer_efficiency"], label+" exchanger conversion and accepted heat")
                    equal(detail["hot_input_mwth"], heat_in[k], label+" raw exchanger activity")
                    equal(detail["warm_output_mwth"], heat_out[k], label+" exchanger warm output")
                    equal(detail["exchanger_loss_mwth"], heat_in[k]-heat_out[k], label+" exchanger loss")
                    same(detail["hot_grade_id"], OIL_GRADE if kind == "oil_water_exchanger" else PRIMARY_GRADE,
                         label+" exchanger hot grade")
                    same(detail["warm_grade_id"], PRIMARY_GRADE if kind == "oil_water_exchanger" else SECONDARY_GRADE,
                         label+" exchanger warm grade")
                    temperatures = (300, 200, 90, 60) if kind == "oil_water_exchanger" else (90, 60, 70, 40)
                    if kind == "oil_water_exchanger":
                        auxiliary = heat_in[k]*params["auxiliary_electric_ratio"]
                        equal(incoming[k], auxiliary, label+" oil exchanger auxiliary AC coupling")
                        equal(detail["auxiliary_electric_mw"], auxiliary, label+" oil exchanger auxiliary ledger")
                        oil_aux += auxiliary
                        oil_warm += heat_out[k]
                    for field, value in zip(("hot_supply_c", "hot_return_c", "cold_supply_c", "cold_return_c"), temperatures):
                        equal(detail[field], value, label+" fixed temperature "+field)
                    bound(params["min_approach_k"], 0, min(temperatures[0]-temperatures[2], temperatures[1]-temperatures[3]), label+" both exchanger approaches")
                    if kind == "heat_exchanger":
                        exchanger_loss += heat_in[k]-heat_out[k]
                elif kind in STORAGE_KINDS:
                    thermal = kind in THERMAL_STORAGE_KINDS
                    suffix, energy_unit = ("mwth", "mwhth") if thermal else ("mw", "mwh")
                    ek = f"energy_{energy_unit}"
                    same(set(report["next_states"][k]), {ek}, label+" dimensioned state")
                    if thermal and "energy_mwh" in detail:
                        errors.append(label+": thermal store mixes electric inventory")
                    charge, discharge, energy = detail[f"charge_{suffix}"], detail[f"discharge_{suffix}"], detail[ek]
                    if kind == "molten_salt_store":
                        auxiliary = (charge+discharge)*params["auxiliary_electric_ratio"]
                        equal(incoming[k], auxiliary, label+" salt store external auxiliary AC")
                        equal(detail["auxiliary_electric_mw"], auxiliary, label+" salt store auxiliary ledger")
                        salt_aux += auxiliary
                    capacity = params[f"capacity_{energy_unit}"]
                    equal(charge, heat_in[k] if thermal else incoming[k], label+" storage charge")
                    equal(discharge, heat_out[k] if thermal else outgoing[k], label+" storage discharge")
                    bound(charge, 0, params[f"charge_{suffix}"] if dt else 0, label+" storage charge rating")
                    bound(discharge, 0, params[f"discharge_{suffix}"] if dt else 0, label+" storage discharge rating")
                    bound(energy, 0, capacity, label+" storage energy")
                    mode = detail["mode_binary"]
                    bound(mode, 0, 1, label+" binary mode")
                    equal(mode, round(mode), label+" binary integrality")
                    bound(charge, 0, params[f"charge_{suffix}"]*mode, label+" charging mode")
                    bound(discharge, 0, params[f"discharge_{suffix}"]*(1-mode), label+" discharging mode")
                    if charge > ABS_TOL and discharge > ABS_TOL:
                        errors.append(label+f" storage {k}: simultaneous charge/discharge")
                    same(detail["mode"], "charge" if charge > ABS_TOL else ("discharge" if discharge > ABS_TOL else "idle"), label+" mode label")
                    before = prior[k]
                    decay = before*math.exp(-params["self_discharge_per_h"]*dt)
                    conversion = charge*(1-params["charge_efficiency"])+discharge*(1/params["discharge_efficiency"]-1)
                    if dt:
                        bound(charge, 0, max(0, capacity-decay)/(params["charge_efficiency"]*dt), label+" storage headroom")
                        bound(discharge, 0, decay*params["discharge_efficiency"]/dt, label+" stored energy available")
                    equal(detail[f"energy_before_{energy_unit}"], before, label+" fixed initial/current inventory")
                    equal(detail[f"energy_after_self_discharge_{energy_unit}"], decay, label+" self-discharge timing")
                    equal(detail[f"self_discharge_{energy_unit}"], before-decay, label+" self-discharge energy")
                    equal(detail[f"storage_conversion_loss_{suffix}"], conversion, label+" storage conversion loss")
                    equal(detail[f"storage_loss_{suffix}"], conversion+(before-decay)/dt if dt else 0, label+" storage total loss")
                    equal(energy, decay+(params["charge_efficiency"]*charge-discharge/params["discharge_efficiency"])*dt, label+" storage recurrence")
                    if kind in ELECTRIC_STORAGE_KINDS:
                        equal(detail["charge_conversion_loss_mw"], incoming[k]*(1-params["charge_efficiency"]),
                              label+" storage charge conversion loss")
                        equal(detail["discharge_conversion_loss_mw"], outgoing[k]*(1/params["discharge_efficiency"]-1),
                              label+" storage discharge conversion loss")
                    if kind == "hydrogen_storage_system":
                        # Independently reconstruct stage quantities from audited AC
                        # flows and dimensioned inventory, not reported losses/SOC.
                        equal(detail["hydrogen_charge_loss_mw"], incoming[k]*(1-params["charge_efficiency"]),
                              label+" hydrogen electrolyzer/compression loss")
                        equal(detail["hydrogen_discharge_loss_mw"], outgoing[k]*(1/params["discharge_efficiency"]-1),
                              label+" hydrogen fuel-cell/inverter loss")
                        equal(detail["hydrogen_produced_mw_lhv"], incoming[k]*params["charge_efficiency"],
                              label+" hydrogen produced LHV energy")
                        equal(detail["hydrogen_consumed_mw_lhv"], outgoing[k]/params["discharge_efficiency"],
                              label+" hydrogen consumed LHV energy")
                        equal(detail["hydrogen_mass_kg"], report["next_states"][k][ek]*1000/HYDROGEN_LHV_KWH_PER_KG,
                              label+" hydrogen LHV mass")
                        same(detail["hydrogen_energy_basis"], "LHV", label+" hydrogen energy basis")
                    equal(detail["soc"], energy/capacity, label+" storage SOC")
                    equal(detail["soc_before"], before/capacity, label+" storage initial SOC")
                    equal(report["next_states"][k][ek], energy, label+" next state")
                    for key, value in (("before", before), ("energy", energy), ("charge", charge), ("discharge", discharge),
                                       ("conversion", conversion), ("self", before-decay)):
                        if kind not in ("high_temp_store", "molten_salt_store"):
                            sums[thermal][key] += value
                    prior[k] = energy
            cycle_gross, cycle_aux = 0., 0.
            if problem["has_rankine"]:
                # AC provenance is reconstructed from original cable endpoints and
                # port flows, never a claimed zero residual or cached path factor.
                for station, node in nodes.items():
                    if node["kind"] != "station":
                        continue
                    external, conversion = 0., 0.
                    for line in report["lines"]:
                        if line["carrier"] != "electricity_ac":
                            continue
                        a, b = str(line["flow_from"]), str(line["flow_to"])
                        if b == station and nodes[a]["kind"] in ("wind", "pv") + ELECTRIC_STORAGE_KINDS:
                            external += line["received_mw"]
                        if a == station and b != "-1" and nodes[b]["kind"] not in ("load",) + ELECTRIC_STORAGE_KINDS:
                            conversion += line["sent_mw"]
                    bound(conversion, 0, external*(1-node["params"]["loss_fraction"]), label+" external-only conversion/auxiliary provenance")
            if problem["has_rankine"] or problem["schema"] >= 7:
                path_lines = {i: 0. for i, line in enumerate(problem["links"]) if line["carrier"] == "electricity_ac"}
                same(len(report["path_flows"]), len(problem["paths"]), label+" path decision count")
                for path, flow in zip(problem["paths"], report["path_flows"]):
                    for field, ident in (("source_id", "source"), ("station_id", "station"), ("sink_id", "sink")):
                        same(flow[field], int(path[ident]), label+" physical path "+field)
                    source, sink = path["source"], path["sink"]
                    sk = nodes[source]["kind"]
                    tk = "grid" if sink == "-1" else nodes[sink]["kind"]
                    if sk == "steam_turbine" and tk not in ("load", "grid") + ELECTRIC_STORAGE_KINDS:
                        errors.append(label+": turbine electricity cannot feed conversion/auxiliary sinks")
                    if sk in ELECTRIC_STORAGE_KINDS and (tk in ELECTRIC_STORAGE_KINDS or tk == "grid"):
                        errors.append(label+": storage electricity cannot feed storage or export")
                    sent = flow["sent_mw"]
                    bound(sent, 0, problem["links"][path["incoming"]]["capacity_mw"] if dt else 0, label+" path source flow")
                    path_lines[path["incoming"]] += sent
                    path_lines[path["outgoing"]] += sent*(1-problem["links"][path["incoming"]]["loss_fraction"])*(1-nodes[path["station"]]["params"]["loss_fraction"])
                for i, sent in path_lines.items():
                    equal(report["lines"][i]["sent_mw"], sent, label+" independent path-to-cable provenance")
            if problem["has_rankine"]:
                same(len(report["mass_flows"]), len(problem["mass_links"]), label+" mass decision count")
                for i, flow in zip(problem["mass_links"], report["mass_flows"]):
                    same(flow["line_index"], i, label+" mass decision identity")
                    equal(flow["sent_kg_s"], report["lines"][i]["sent_kg_s"], label+" mass decision to port")
                expected_cycle = rankine_ledger(problem, report)
                same(set(report["rankine"]), set(expected_cycle), label+" Rankine ledger fields")
                for field, expected in expected_cycle.items():
                    equal(report["rankine"][field], expected, label+" aggregate Rankine "+field)
                equal(expected_cycle["balance_error_mw"], 0, label+" independent closed Rankine energy balance")
                cycle_gross, cycle_aux = expected_cycle["gross_electric_mw"], expected_cycle["auxiliary_electric_mw"]
            if problem["solar_collectors"]:
                for field, expected in solar_expected.items():
                    equal(report["solar"][field], expected-trough_expected[field]-tower_expected[field], label+" aggregate solar "+field)
            if problem["has_high_temp"]:
                expected_high = high_temp_ledger(problem, report)
                same(set(report["high_temp"]), set(expected_high), label+" high-temperature ledger fields")
                for field, expected in expected_high.items():
                    equal(report["high_temp"][field], expected, label+" high-temperature ledger "+field)
                equal(expected_high["balance_error_mwth"], 0, label+" independent oil-grade balance")
                equal(expected_high["energy_balance_error_mwhth"], 0, label+" independent oil inventory balance")
            if problem["has_tower"]:
                expected_tower = tower_ledger(problem, report)
                same(set(report["tower"]), set(expected_tower), label+" tower ledger fields")
                for field, expected in expected_tower.items():
                    equal(report["tower"][field], expected, label+" tower ledger "+field)
                equal(expected_tower["balance_error_mwth"], 0, label+" independent salt-grade balance")
                equal(expected_tower["energy_balance_error_mwhth"], 0, label+" independent salt inventory balance")
            supply = problem["fuel_supply"]
            bound(fuel_expected["input_mw"], 0, supply["max_input_mw"] if supply["enabled"] and dt else 0,
                  label+" shared enabled fuel resource cap")
            fuel = report["fuel"]
            for field, expected in fuel_expected.items():
                equal(fuel[field], expected, label+" aggregate fuel "+field)
            fuel_balance = fuel_expected["input_mw"]+fuel_expected["auxiliary_electric_mw"]-fuel_expected["heat_output_mwth"]-fuel_expected["conversion_loss_mw"]-fuel_expected["auxiliary_electric_loss_mw"]
            equal(fuel_balance, 0, label+" independent fuel and auxiliary energy conservation")
            equal(fuel["balance_error_mw"], fuel_balance, label+" reported fuel power residual")
            equal(fuel["energy_balance_error_mwh"], fuel_balance*dt, label+" reported fuel energy residual")
            bound(export, 0, problem["grid"], label+" grid export cap")
            equal(report["export_mw"], export, label+" total export")
            for thermal, ids in ((False, problem["loads"]), (True, problem["heat_demands"])):
                suffix = "mwth" if thermal else "mw"
                ledger = report["thermal"] if thermal else report
                for field in ("demand", "served", "unserved"):
                    key = f"{field}_{suffix}"
                    equal(ledger[key], sum(devices[k][key] for k in ids), label+" total "+key)
                inventory = sums[thermal]
                energy_unit = "mwhth" if thermal else "mwh"
                for field in ("charge", "discharge"):
                    equal(ledger[f"{field}_{suffix}"], inventory[field], label+" total storage "+field)
                equal(ledger[f"energy_{energy_unit}"], inventory["energy"], label+" total stored energy")
                equal(ledger[f"self_discharge_{energy_unit}"], inventory["self"], label+" total storage self loss")
                equal(ledger[f"storage_conversion_loss_{suffix}"], inventory["conversion"], label+" total storage conversion")
                store_loss = inventory["conversion"]+(inventory["self"]/dt if dt else 0)
                equal(ledger[f"storage_loss_{suffix}"], store_loss, label+" total storage loss")
                cap = sum(nodes[k]["params"][f"capacity_{energy_unit}"] for k in (problem["water_stores"] if thermal else problem["batteries"]))
                equal(ledger["soc"], inventory["energy"]/cap if cap else 0, label+" aggregate SOC")
                if thermal:
                    equal(ledger["boiler_heat_mwth"], boiler_heat, label+" total boiler heat")
                    equal(ledger["network_loss_mwth"], heat_loss, label+" total heat line loss")
                    equal(ledger["exchanger_loss_mwth"], exchanger_loss, label+" total exchanger loss")
                    balance = boiler_heat+fuel_expected["heat_output_mwth"]+solar_expected["useful_mwth"]-trough_expected["useful_mwth"]-tower_expected["useful_mwth"]+oil_warm+inventory["discharge"]-ledger["served_mwth"]-inventory["charge"]-exchanger_loss-heat_loss
                    energy_balance = (boiler_heat+fuel_expected["heat_output_mwth"]+solar_expected["useful_mwth"]-trough_expected["useful_mwth"]-tower_expected["useful_mwth"]+oil_warm-ledger["served_mwth"]-exchanger_loss-heat_loss-store_loss)*dt+inventory["before"]-inventory["energy"]
                else:
                    available = sum(step["available_mw"].values())
                    curtailed = sum(devices[k]["curtailed_mw"] for k in problem["generators"])
                    produced = available-curtailed
                    if problem["has_rankine"]:
                        produced += cycle_gross
                        equal(report["generated_mw"], available+cycle_gross, label+" total generation including turbine")
                    equal(report["available_mw"], available, label+" total available")
                    equal(report["curtailed_mw"], curtailed, label+" total curtailment")
                    equal(report["produced_mw"], produced, label+" total production")
                    equal(report["boiler_electric_mw"], boiler_power, label+" total boiler power")
                    equal(report["boiler_conversion_loss_mw"], boiler_loss, label+" total boiler loss")
                    equal(report["line_loss_mw"], line_loss, label+" total electric line loss")
                    equal(report["station_loss_mw"], station_loss, label+" total station loss")
                    equal(report["loss_mw"], line_loss+station_loss, label+" total electric loss")
                    equal(report["total_loss_mw"], line_loss+station_loss+store_loss, label+" total electric and battery loss")
                    balance = produced+inventory["discharge"]-report["served_mw"]-inventory["charge"]-boiler_power-fuel_expected["auxiliary_electric_mw"]-solar_expected["auxiliary_electric_mw"]-oil_aux-salt_aux-cycle_aux-export-line_loss-station_loss
                    energy_balance = (produced-report["served_mw"]-boiler_power-fuel_expected["auxiliary_electric_mw"]-solar_expected["auxiliary_electric_mw"]-oil_aux-salt_aux-cycle_aux-export-line_loss-station_loss-store_loss)*dt+inventory["before"]-inventory["energy"]
                equal(balance, 0, label+" independently recomputed "+suffix+" balance")
                equal(energy_balance, 0, label+" independently recomputed "+energy_unit+" balance")
                equal(ledger[f"balance_error_{suffix}"], balance, label+" reported power residual")
                equal(ledger[f"energy_balance_error_{energy_unit}"], energy_balance, label+" reported energy residual")
        for thermal, ids in ((False, problem["batteries"]), (True, problem["thermal_stores"])):
            terminal = problem["terminal_heat"] if thermal else problem["terminal"]
            if terminal is not None:
                for k in ids:
                    cap = nodes[k]["params"]["capacity_mwhth" if thermal else "capacity_mwh"]
                    bound(prior[k], terminal*cap, cap, f"storage {k} terminal floor")
    except (KeyError, IndexError, TypeError, ValueError, OverflowError) as exc:
        errors.append("Malformed physical report: "+str(exc))
    return {"valid": not errors, "errors": errors[:100], "max_residual": maximum,
            "absolute_tolerance": ABS_TOL, "relative_tolerance": REL_TOL,
            "checks": ["finite_values", "source_and_demand_balance", "typed_line_caps_and_losses",
                       "station_incoming_caps_and_losses", "grid_export_cap", "storage_power_caps",
                       "storage_binary_mode_exclusivity", "fixed_initial_energy", "storage_recurrence",
                       "SOC_bounds", "separate_terminal_floors", "aggregate_power_and_energy_balance",
                       "boiler_endogenous_electric_heat_coupling", "heat_exchanger_conversion_and_both_approaches",
                       "fixed_temperature_grades", "no_free_heat_sink", "dimensioned_next_states",
                       "shared_fuel_supply_cap", "fuel_auxiliary_electric_coupling",
                       "fuel_conversion_and_auxiliary_dissipation", "fuel_volume_and_teaching_cost"]
                      + (["closed_four_device_mass_circuit", "fixed_state_enthalpy_transport",
                          "ambient_limited_dry_condenser", "external_only_auxiliary_provenance",
                          "rankine_shaft_motor_and_SG_losses", "shared_oil_and_station_caps"] if problem["has_rankine"] else [])
                      + (["independent_salt_grade_inventory", "tower_DNI_daylight_gate",
                          "salt_storage_external_charge_discharge_auxiliaries"] if problem["has_tower"] else [])
                      + (["restricted_storage_path_provenance", "expanded_storage_conversion_losses",
                          "hydrogen_LHV_stage_energy_and_mass"] if problem["schema"] >= 7 else [])}


def validate_physical_decisions(problem, values):
    """Audit the original decisions against topology/physics, independently of LP rows.

    assemble_schedule reads each original activity, flow, binary and inventory;
    line deliveries here are rebuilt from original loss parameters, not the LP's
    cached path coefficients. validate_schedule then recomputes every balance.
    This audit therefore also rejects a physically wrong model with feasible rows.
    """
    try:
        audit = validate_schedule(problem, assemble_schedule(problem, values))
        return audit["errors"]
    except (KeyError, TypeError, ValueError, OverflowError) as exc:
        return ["Malformed raw physical decisions: "+str(exc)]


def validate_decisions(model, values):
    """Catch missing, nonfinite or materially infeasible raw solver decisions."""
    errors = []
    for name, (low, high) in model.bounds.items():
        value = values.get(name)
        if value is None or not math.isfinite(value):
            errors.append(f"Missing or nonfinite decision {name}")
        elif value < low-ABS_TOL or (high is not None and value > high+ABS_TOL+REL_TOL*abs(high)):
            errors.append(f"Out-of-bound decision {name}")
    if errors:
        return errors
    for name in model.binaries:
        if abs(values[name]-round(values[name])) > ABS_TOL:
            errors.append(f"Noninteger storage mode {name}")
    for i, (terms, relation, rhs) in enumerate(model.rows):
        lhs = sum(values[name]*coefficient for name, coefficient in terms.items())
        tolerance = ABS_TOL+REL_TOL*max(abs(lhs), abs(rhs))
        if ((relation == "=" and abs(lhs-rhs) > tolerance) or
                (relation == "<=" and lhs > rhs+tolerance) or (relation == ">=" and lhs < rhs-tolerance)):
            errors.append(f"Constraint {i} failed independent residual check")
            if len(errors) >= 100:
                break
    return errors


def summarize(problem, reports):
    totals = {"duration_h": sum(s["dt_h"] for s in reports),
              "initial_energy_mwh": sum(problem["nodes"][k]["energy"] for k in problem["batteries"]),
              "final_energy_mwh": reports[-1]["energy_mwh"], "final_soc": reports[-1]["soc"]}
    for key in ("wind", "pv", "available", "generated", "produced", "demand", "served", "unserved",
                "charge", "discharge", "export", "curtailed", "loss", "line_loss", "station_loss",
                "storage_loss", "storage_conversion_loss", "total_loss"):
        totals[key+"_mwh"] = sum(s[key+"_mw"]*s["dt_h"] for s in reports)
    totals["self_discharge_mwh"] = sum(s["self_discharge_mwh"] for s in reports)
    totals["weighted_unserved_mwh"] = sum(
        s["devices"][k]["unserved_mw"] * s["dt_h"] * (1001-problem["nodes"][k]["params"]["priority"])
        for s in reports for k in problem["loads"])
    totals["balance_error_mwh"] = sum(s["balance_error_mw"]*s["dt_h"] for s in reports)
    totals["energy_balance_error_mwh"] = sum(s["energy_balance_error_mwh"] for s in reports)
    totals["boiler_electric_mwh"] = sum(step["boiler_electric_mw"]*step["dt_h"] for step in reports)
    totals["boiler_conversion_loss_mwh"] = sum(step["boiler_conversion_loss_mw"]*step["dt_h"] for step in reports)
    thermal = {"initial_energy_mwhth": sum(problem["nodes"][k]["energy"] for k in problem["water_stores"]),
               "final_energy_mwhth": reports[-1]["thermal"]["energy_mwhth"], "final_soc": reports[-1]["thermal"]["soc"]}
    for field in ("demand", "served", "unserved", "boiler_heat", "charge", "discharge", "network_loss",
                  "exchanger_loss", "storage_conversion_loss", "storage_loss", "balance_error"):
        thermal[field+"_mwhth"] = sum(step["thermal"][field+"_mwth"]*step["dt_h"] for step in reports)
    for field in ("self_discharge_mwhth", "energy_balance_error_mwhth"):
        thermal[field] = sum(step["thermal"][field] for step in reports)
    thermal["weighted_unserved_mwhth"] = sum(
        step["devices"][k]["unserved_mwth"]*step["dt_h"]*(1001-problem["nodes"][k]["params"]["priority"])
        for step in reports for k in problem["heat_demands"])
    totals["fuel"] = {target: sum(step["fuel"][source]*step["dt_h"] for step in reports)
                      for target, source in (("input_mwh", "input_mw"), ("volume_nm3", "volume_nm3_per_h"),
                                             ("cost", "cost_per_h"), ("heat_output_mwhth", "heat_output_mwth"),
                                             ("conversion_loss_mwh", "conversion_loss_mw"),
                                             ("auxiliary_mwh", "auxiliary_electric_mw"),
                                             ("auxiliary_loss_mwh", "auxiliary_electric_loss_mw"),
                                             ("balance_error_mwh", "balance_error_mw"))}
    if problem["solar_collectors"]:
        totals["solar"] = {field.replace("_mw", "_mwh"):
                           sum(step["solar"][field]*step["dt_h"] for step in reports) for field in SOLAR_FIELDS}
    if problem["has_high_temp"]:
        high = {}
        for field in reports[0]["high_temp"]:
            if field.endswith(("_mw", "_mwth")):
                high[field.replace("_mw", "_mwh")] = sum(step["high_temp"][field]*step["dt_h"] for step in reports)
        high["initial_energy_mwhth"] = sum(problem["nodes"][k]["energy"] for k in problem["high_stores"])
        high["final_energy_mwhth"] = reports[-1]["high_temp"]["energy_mwhth"]
        high["final_soc"] = reports[-1]["high_temp"]["soc"]
        high["self_discharge_mwhth"] = sum(step["high_temp"]["self_discharge_mwhth"] for step in reports)
        high["energy_balance_error_mwhth"] = sum(step["high_temp"]["energy_balance_error_mwhth"] for step in reports)
        totals["high_temp"] = high
    if problem["has_tower"]:
        tower = {field.replace("_mw", "_mwh"): sum(step["tower"][field]*step["dt_h"] for step in reports)
                 for field in reports[0]["tower"] if field.endswith(("_mw", "_mwth"))}
        tower["initial_energy_mwhth"] = sum(problem["nodes"][k]["energy"] for k in problem["salt_stores"])
        tower["final_energy_mwhth"] = reports[-1]["tower"]["energy_mwhth"]
        tower["final_soc"] = reports[-1]["tower"]["soc"]
        for field in ("self_discharge_mwhth", "energy_balance_error_mwhth"):
            tower[field] = sum(step["tower"][field] for step in reports)
        totals["tower"] = tower
    if problem["has_rankine"]:
        totals["rankine"] = {field.replace("_mw", "_mwh"): sum(step["rankine"][field]*step["dt_h"] for step in reports)
                             for field in reports[0]["rankine"] if field.endswith(("_mw", "_mwth"))}
        totals["rankine"]["circulated_mass_kg"] = sum(step["rankine"]["mass_flow_kg_s"]*step["dt_h"]*3600 for step in reports)
    totals["thermal"] = thermal
    totals["weighted_unserved_service_energy"] = totals["weighted_unserved_mwh"]+problem["heat_weight"]*thermal["weighted_unserved_mwhth"]
    return totals


def solve(snapshot, glpsol="glpsol", cancel_file=None):
    started = time.monotonic()
    result = {"schema_version": SCHEMA_VERSION, "solver": "GLPK/glpsol", "solver_invoked": False,
              "status": "error", "success": False, "optimal": False, "steps": [], "totals": {},
              "errors": [], "warnings": [], "validation": {"valid": False, "errors": []},
              "model": "fixed-capacity radial active-power transport; not AC power flow",
              "metadata": {}, "objective": {"policy": "lexicographic_three_stage",
                  "stages": ["minimize weighted unmet MWh (weight = 1001 - priority)",
                             "maximize renewable export MWh",
                             "minimize battery AC throughput MWh"],
                  "completed_stages": 0, "economic_optimality_claimed": False}}
    try:
        root = object_value(snapshot, "snapshot")
        metadata = object_value(root.get("metadata", {}), "metadata")
        # Echo correlation-only metadata; JSON encoding forbids nonfinite values.
        json.dumps(metadata, allow_nan=False)
        result["metadata"] = copy.deepcopy(metadata)
        problem = normalize(snapshot)
        result["schema_version"] = max(2, problem["schema"])
        if problem["has_thermal"]:
            result["model"] = "fixed-capacity joint electric transport and fixed-grade hot-water service; not AC power flow or hydraulics"
            result["objective"].update(policy="lexicographic_four_stage", stages=[
                "minimize weighted unmet service energy: dt*((1001-priority_e)*u_e + heat_service_weight*(1001-priority_h)*u_h)",
                "maximize delivered renewable export MWh",
                "minimize battery and thermal-store port throughput (explicit weights 1 and 1)",
                "minimize boiler electrical activity plus exchanger hot-side activity (explicit weights 1 and 1)"],
                heat_service_weight=problem["heat_weight"],
                service_weight_note="Teaching service weight; not electrical/thermal economic equivalence or strict priority ordering",
                thermal_profile=THERMAL_PROFILE)
        if problem["has_high_temp"]:
            result["model"] = "fixed-capacity coupled electricity, Therminol66 oil 300/200 C and water 90/60-to-70/40 C transport; not AC flow or hydraulics"
            result["objective"]["high_temp_profile"] = HIGH_TEMP_PROFILE
            result["high_temp_assumptions"] = {
                "fluid": "Therminol66", "grade_id": OIL_GRADE,
                "source": "Explicit DNI with horizontal north-south single-axis incidence; no POA substitution",
                "coefficients": "Optical efficiency and heat-loss coefficients are teaching proxies, not vendor-fitted performance",
                "inventory": "Useful 200-to-300 C enthalpy above the cold reference; no UA/free-heating tank model",
                "auxiliary": "Separate collector and oil-water circulation AC inputs dissipate outside useful heat",
                "oil_water_endpoint_approaches_k": [210, 140],
            }
        if problem["has_rankine"]:
            result["model"] = "fixed-state closed Rankine mass/enthalpy cycle with shared electric/oil resources; continuous-flow teaching approximation"
            result["objective"]["rankine_profile"] = RANKINE_PROFILE
            result["objective"]["stages"][3] = "minimize boiler electrical activity plus exchanger and steam-generator oil input activity (explicit weights 1)"
            result["rankine_assumptions"] = {
                "model_profile": RANKINE_PROFILE, "model_profile_version": 1,
                "enthalpy_kj_kg": dict(RANKINE_H), "live_pressure_mpa": 1., "live_temp_c": 280.,
                "condenser_pressure_mpa": .01, "condensing_temp_c": 45.806,
                "turbine_isentropic_efficiency": .75, "pump_isentropic_efficiency": .70,
                "auxiliary_supply": "Connected wind/PV or discharging battery only; no same-step turbine-fed conversion or auxiliaries",
                "cooling": "Explicit dry condenser rejection with ambient capacity and 10 K minimum approach",
                "limitations": "Fixed states, no startup or minimum load, no pressure losses, no dynamic fluid inventory"}
        if problem["has_tower"]:
            result["model"] = "fixed-state Rankine cycle with independent salt 565/290 C and oil 300/200 C resources; continuous-flow teaching approximation"
            result["objective"]["stages"][3] = "minimize boiler electrical activity plus exchanger and steam-generator accepted heat input activity (explicit weights 1)"
            result["objective"]["tower_profile"] = TOWER_PROFILE
            result["tower_assumptions"] = {"model_profile": TOWER_PROFILE, "model_profile_version": 1,
                "grade_id": SALT_GRADE, "hot_temp_c": 565., "cold_temp_c": 290.,
                "optics": "Fixed equivalent optical efficiency; no shading, blocking or ray tracing",
                "weather": "Explicit DNI and shared is_day/solar altitude gate; no POA substitution",
                "inventory": "Useful 290-to-565 C salt enthalpy above cold reference",
                "auxiliary": "External AC for receiver, salt charging/discharging and Rankine auxiliaries",
                "steam": "Direct salt SG into fixed 1 MPa / 280 C Rankine states; no oil intermediate"}
        if problem["fuel_boilers"]:
            result["objective"]["policy"] = "lexicographic_five_stage"
            result["objective"]["stages"].append("minimize fuel input cost in CNY using the configured teaching price; prior four optima fixed")
            result["fuel_supply"] = copy.deepcopy(problem["fuel_supply"])
            result["fuel_assumptions"] = {"energy_basis": "lower heating value (MW_LHV / MWh_LHV)",
                "currency": "CNY", "price_note": "User-configurable teaching assumption, not a market price or public cost claim",
                "auxiliary_note": "AC auxiliary electricity is consumed and dissipated separately; it is not useful heat",
                "emissions_model": False}
        if problem["schema"] >= 7:
            result["expanded_storage_assumptions"] = {
                "inventory": "Finite lumped energy with exponential self-discharge before port conversion",
                "electric_ports": "Net AC terminal powers; no storage-to-storage paths or storage-fed export",
                "conversion": "Constant net charge/discharge efficiencies include conversion trains and auxiliaries",
                "caes": "Aboveground vessels only, capacity <= 10 MWh and each power <= 2 MW; no underground caverns",
                "solid_thermal": "Useful heat through primary-water 90/60 C ports only; no direct electricity output",
                "hydrogen_energy_basis": "LHV", "hydrogen_lhv_kwh_per_kg": HYDROGEN_LHV_KWH_PER_KG,
                "hydrogen_charge": "Net electrolyzer plus compression efficiency on an LHV basis",
                "hydrogen_discharge": "Net fuel-cell plus inverter efficiency; no recovered-heat credit",
                "limitations": "Teaching energy ledger, not pressure/temperature/fluid transients, gas safety or equipment sizing",
            }
            result["objective"]["stages"][2] = (
                "minimize electric and thermal storage port throughput (explicit weights 1 and 1)"
                if problem["has_thermal"] else "minimize electric-storage AC throughput MWh")
        if cancel_file and Path(cancel_file).exists():
            result.update(status="cancelled", message="Cancelled before solver start")
            return result
        executable = shutil.which(os.fspath(glpsol))
        if not executable:
            raise InputError(f"GLPK executable not found: {glpsol}. Install GLPK or supply --glpsol PATH.")
        model = build_model(problem)
        deadline = started + problem["timeout"]
        locks, incumbent, stage_results = [], None, []
        with tempfile.TemporaryDirectory(prefix="basin_glpk_") as tmp:
            for stage in range(len(model.objectives)):
                run = run_glpk(executable, model, stage, locks, Path(tmp), deadline, cancel_file)
                result["solver_invoked"] = True
                stage_results.append({"stage": stage+1, "status": run["status"], "log": run.get("log", "")})
                if run["status"] == "cancelled":
                    result.update(status="cancelled", message="Dispatch optimization cancelled")
                    return result
                if run["status"] not in ("optimal", "feasible"):
                    if incumbent is None:
                        result.update(status=run["status"], message={"timeout": "GLPK timed out without a feasible schedule",
                                      "infeasible": "No schedule satisfies strict supply and/or the terminal SOC floor"}.get(
                                          run["status"], "GLPK did not return a usable solution"))
                        result["solver_stages"] = stage_results
                        return result
                    result["warnings"].append(f"Stage {stage+1} ended with {run['status']}; returning the prior validated feasible schedule")
                    result["termination_reason"] = run["status"]
                    break
                errors = validate_decisions(model, run["values"])
                if not errors:
                    errors.extend(validate_physical_decisions(problem, run["values"]))
                    for terms, _, rhs in locks:
                        lhs = sum(run["values"][name]*coefficient for name, coefficient in terms.items())
                        if lhs > rhs+ABS_TOL+REL_TOL*max(abs(lhs), abs(rhs)):
                            errors.append("Prior lexicographic objective lock violated")
                if errors:
                    result["errors"] = errors
                    result["validation"]["errors"] = errors
                    result["message"] = "GLPK decisions failed independent validation"
                    result["solver_stages"] = stage_results
                    return result
                incumbent = run["values"]
                objective = sum(incumbent[k]*v for k, v in model.objectives[stage].items())
                stage_results[-1]["objective_value"] = objective
                if run["status"] != "optimal":
                    result["termination_reason"] = "timeout" if run.get("timed_out") else "feasible_limit"
                    break
                result["objective"]["completed_stages"] += 1
                # Fix each preceding optimum exactly. Physical validation tolerates
                # floating-point solver residuals, never an intentional objective trade.
                locks.append((model.objectives[stage], "<=", objective))
        reports = assemble_schedule(problem, incumbent)
        validation = validate_schedule(problem, reports)
        validation["raw_decisions_validated"] = True
        result["validation"] = validation
        result["solver_stages"] = stage_results
        if not validation["valid"]:
            result.update(message="Schedule failed independent physical validation", errors=validation["errors"])
            return result
        optimal = result["objective"]["completed_stages"] == len(model.objectives)
        result.update(status="optimal" if optimal else "feasible", success=True, optimal=optimal,
                      steps=reports, totals=summarize(problem, reports),
                      message="Validated optimal dispatch" if optimal else "Validated feasible dispatch; optimality not proven",
                      initial_states={k: {"energy_mwhth" if problem["nodes"][k]["kind"] in THERMAL_STORAGE_KINDS else "energy_mwh": problem["nodes"][k]["energy"]}
                                      for k in problem["batteries"]+problem["thermal_stores"]},
                      final_states=reports[-1]["next_states"])
        for report in reports:
            report["status"] = result["status"]
            report["optimal"] = optimal
            report["dispatch_policy"] = "glpk_fixed_capacity_horizon"
    except (InputError, ValueError, TypeError, OSError, KeyError, IndexError, OverflowError) as exc:
        result.update(status="error", message=str(exc), error=str(exc), errors=[str(exc)])
    except InterruptedError:
        result.update(status="cancelled", message="Dispatch optimization cancelled")
    finally:
        result["elapsed_s"] = time.monotonic()-started
    return result


def reject_constant(value):
    raise InputError(f"Nonfinite JSON number is not allowed: {value}")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise InputError(f"Duplicate JSON object key: {key}")
        result[key] = value
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--glpsol", default="glpsol", help="GLPK executable name or filesystem path")
    parser.add_argument("--cancel-file", type=Path, help="Cancel when this file exists; its contents are ignored")
    args = parser.parse_args(argv)

    def interrupted(_signum, _frame):
        raise InterruptedError("cancelled")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        if args.input.stat().st_size > 64*1024*1024:
            raise InputError("Input exceeds the 64 MiB limit")
        snapshot = json.loads(args.input.read_text(encoding="utf-8"), parse_constant=reject_constant,
                              object_pairs_hook=unique_object)
        result = solve(snapshot, args.glpsol, args.cancel_file)
    except (OSError, ValueError, InterruptedError) as exc:
        result = {"schema_version": SCHEMA_VERSION, "status": "cancelled" if isinstance(exc, InterruptedError) else "error",
                  "success": False, "optimal": False, "message": str(exc), "error": str(exc),
                  "errors": [str(exc)], "steps": [], "totals": {}, "validation": {"valid": False}, "metadata": {}}
    try:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        # Atomic rename prevents the UI reading a partially written result.
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=args.output.parent,
                                         prefix=args.output.name+".", suffix=".tmp", delete=False) as out:
            temporary = Path(out.name)
            json.dump(result, out, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
            out.write("\n")
        os.replace(temporary, args.output)
    except OSError as exc:
        print(f"Cannot write dispatch result: {exc}", file=sys.stderr)
        return 2
    return 0 if result["success"] else (3 if result["status"] in ("timeout", "cancelled") else 2)


if __name__ == "__main__":
    sys.exit(main())
