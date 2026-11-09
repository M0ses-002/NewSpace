extends RefCounted
## 物理计算使用 km、模拟秒和 km/s；1 世界单位对应 1 km。
const Config = preload("res://scripts/simulation_config.gd")
const METERS_PER_KM: float = 1000.0
const SECONDS_PER_MINUTE: float = 60.0
static var PLANET_RADIUS_KM: float:
	get:
		Config.ensure_loaded()
		return Config.planet.radius_km
static var FIELD_THICKNESS_KM: float:
	get:
		Config.ensure_loaded()
		return Config.planet.field_thickness_km
static var FIELD_TOP_RADIUS_KM: float:
	get:
		return PLANET_RADIUS_KM + FIELD_THICKNESS_KM
static var FIELD_GRAVITY_M_S2: float:
	get:
		Config.ensure_loaded()
		return Config.planet.gravity_m_s2
static var GRAVITY_RADIUS_KM: float:
	get:
		Config.ensure_loaded()
		return Config.planet.gravity_radius_km
static var EXTERNAL_MU_KM3_S2: float:
	get:
		return FIELD_GRAVITY_M_S2 / METERS_PER_KM * FIELD_TOP_RADIUS_KM * FIELD_TOP_RADIUS_KM

static func speed_to_m_s(speed_km_s: float) -> float:
	return speed_km_s * METERS_PER_KM

static func seconds_to_minutes(seconds: float) -> float:
	return seconds / SECONDS_PER_MINUTE
