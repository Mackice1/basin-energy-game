extends RefCounted
## Explicit shared natural-gas resource boundary; never an electrical or heat link.
## MW/MWh are lower-heating-value fuel input. Nm3 uses the configured LHV only.
## Price is a CNY/MWh teaching assumption, not a current supplier tariff.
## This is an enabled/rate-limited supply, not a stock tank or pressure/gas network.
const MAX_INPUT_MW: float = 10000.0
const MAX_LHV_KWH_PER_NM3: float = 100.0
const MAX_PRICE_PER_MWH: float = 1000000.0
const MIN_AUXILIARY_RATIO: float = 0.001
const MAX_AUXILIARY_RATIO: float = 0.2
const EPS: float = 0.000001
const ENERGY_KEYS := ["input_mwh", "volume_nm3", "cost", "heat_output_mwhth", "conversion_loss_mwh", "auxiliary_mwh"]

static func defaults() -> Dictionary:
	return {"enabled": false, "max_input_mw": 0.0,
		"lower_heating_value_kwh_per_nm3": 10.0, "price_per_mwh": 300.0}

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

## Complete-record validation for save/config boundaries. Never mutates input.
static func validate(value: Variant) -> String:
	if not value is Dictionary:
		return "Fuel supply must be an object."
	var supported: Dictionary = defaults()
	for key in value:
		if not supported.has(key):
			return "Unknown fuel supply field: %s." % str(key)
	if not value.get("enabled") is bool:
		return "Fuel supply enabled must be a boolean."
	if not _number(value.get("max_input_mw")) or float(value.max_input_mw) < 0.0 or float(value.max_input_mw) > MAX_INPUT_MW:
		return "Fuel supply max_input_mw must be finite and within [0, 10000] MW LHV."
	if not _number(value.get("lower_heating_value_kwh_per_nm3")) or float(value.lower_heating_value_kwh_per_nm3) <= 0.0 or float(value.lower_heating_value_kwh_per_nm3) > MAX_LHV_KWH_PER_NM3:
		return "Fuel lower_heating_value_kwh_per_nm3 must be finite and within (0, 100]."
	if not _number(value.get("price_per_mwh")) or float(value.price_per_mwh) < 0.0 or float(value.price_per_mwh) > MAX_PRICE_PER_MWH:
		return "Fuel price_per_mwh must be finite and within [0, 1000000] CNY/MWh."
	if not is_finite(float(value.max_input_mw) * 1000.0 / float(value.lower_heating_value_kwh_per_nm3)):
		return "Fuel volume conversion must remain finite at the configured input cap."
	return ""

## Runtime partial configuration uses defaults; malformed data fails closed.
## User-facing config and save callers must surface validate() before accepting it.
static func normalized(value: Variant = {}) -> Dictionary:
	var result: Dictionary = defaults()
	if not value is Dictionary:
		return result
	result.merge(value, true)
	return result if validate(result).is_empty() else defaults()

static func initial_energy() -> Dictionary:
	return {"input_mwh": 0.0, "volume_nm3": 0.0, "cost": 0.0,
		"heat_output_mwhth": 0.0, "conversion_loss_mwh": 0.0, "auxiliary_mwh": 0.0}

## Historical volume/cost cannot be reconstructed using today's LHV/price:
## users may have changed those settings, or removed/reconfigured a boiler.
static func validate_energy(value: Variant) -> String:
	if not value is Dictionary:
		return "Fuel energy must be an object."
	for key in ENERGY_KEYS:
		if not _number(value.get(key)) or float(value[key]) < 0.0:
			return "Fuel %s must be finite and nonnegative." % key
	for key in value:
		if not key in ENERGY_KEYS:
			return "Unknown accumulated fuel field: %s." % str(key)
	var input: float = float(value.input_mwh)
	var converted: float = float(value.heat_output_mwhth) + float(value.conversion_loss_mwh)
	if not is_finite(converted) or absf(input - converted) > EPS * maxf(1.0, maxf(input, converted)):
		return "Fuel input must equal heat output + conversion loss; auxiliary electricity is independent."
	var auxiliary: float = float(value.auxiliary_mwh)
	var tolerance: float = EPS * maxf(1.0, input)
	if auxiliary < input * MIN_AUXILIARY_RATIO - tolerance or auxiliary > input * MAX_AUXILIARY_RATIO + tolerance:
		return "Fuel auxiliary electricity must be consistent with the supported positive auxiliary ratio."
	if input == 0.0 and (float(value.volume_nm3) != 0.0 or float(value.cost) != 0.0 or auxiliary != 0.0):
		return "Zero fuel input cannot have accumulated fuel volume, cost or auxiliary electricity."
	if input > 0.0 and float(value.volume_nm3) <= 0.0:
		return "Positive fuel input requires a positive metered natural-gas volume."
	return ""

## Metered quantities remain meaningful after supply is disabled; do not gate
## historical conversion by enabled or silently assume a different LHV/price.
static func volume_nm3(input_mwh: float, supply: Dictionary) -> float:
	if not is_finite(input_mwh) or input_mwh < 0.0 or not validate(supply).is_empty():
		return 0.0
	var volume: float = input_mwh * 1000.0 / float(supply.lower_heating_value_kwh_per_nm3)
	return volume if is_finite(volume) else 0.0

static func cost(input_mwh: float, supply: Dictionary) -> float:
	if not is_finite(input_mwh) or input_mwh < 0.0 or not validate(supply).is_empty():
		return 0.0
	var amount: float = input_mwh * float(supply.price_per_mwh)
	return amount if is_finite(amount) else 0.0
