extends RefCounted

const PATH := "res://data/combat.json"
const DEFAULTS := {
	"player": {"health": 100.0, "hit_radius_km": 2.0, "color": "#e2f2ff"},
	"satellite": {"health": 80.0, "radius_km": 5.0, "capture_radius_km": 90.0, "orbit_radius_km": 190.0, "angular_speed_rad_s": 0.002, "color": "#62d6dc"},
	"debris": {"radius_km": 7.0, "damage": 12.0, "cooldown_s": 3.0, "orbit_speed_factor": 1.0, "color": "#a38b78"},
	"radar": {"near_radius_km": 90.0, "far_radius_km": 250.0, "sector_degrees": 32.0, "rotation_rad_s": 0.08, "color": "#4488aa55"},
	"missile": {"speed_km_s": 2.5, "turn_rad_s": 1.5, "damage": 65.0, "lifetime_s": 180.0, "cooldown_real_s": 5.0, "radius_km": 2.0, "color": "#ffb347"},
	"point_defense": {"range_km": 30.0, "duration_sim_s": 30.0, "cooldown_real_s": 5.0},
	"carrier": {"orbit_speed_km_s": 5.0, "return_speed_km_s": 8.0, "fade_distance_km": 60.0, "spacing_km": 6.0, "radius_km": 2.0, "damage": 12.0, "cooldown_real_s": 5.0, "enemy_height_tolerance_km": 20.0, "dogfight_duration_real_s": 2.0, "dogfight_range_km": 12.0, "dogfight_protection_real_s": 1.0, "dogfight_loss_probability": 0.7, "dogfight_loss_min": 1, "dogfight_loss_max": 3},
	"wingman": {"orbit_radius_km": 20.0, "radius_km": 2.0, "angular_speed_rad_s": 1.0, "duration_real_s": 5.0, "cooldown_real_s": 15.0},
	"weapons": {"missile": {"name": "追踪导弹"}, "point_defense": {"name": "近防炮"}, "carrier": {"name": "舰载机"}, "satellite_deployer": {"name": "卫星布置器"}, "wingman": {"name": "僚机"}},
	"enemy": {"health": 100.0, "radius_km": 4.0, "acceleration_km_s2": 0.02, "max_speed_km_s": 0.8, "color": "#ff6666"}
}

static func load_config(path: String = PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("战斗配置无法读取，使用安全默认值")
		return DEFAULTS.duplicate(true)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	parsed = migrate_legacy(parsed)
	if not validate(parsed):
		push_error("战斗配置无效，使用安全默认值")
		return DEFAULTS.duplicate(true)
	return parsed

static func migrate_legacy(data: Variant) -> Variant:
	if data is Dictionary and data.get("missile") is Dictionary and not data.missile.has("cooldown_real_s") and data.missile.has("cooldown_s"):
		data.missile.cooldown_real_s = 5.0
	return data

static func validate(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for group: String in DEFAULTS:
		if not data.has(group) or not data[group] is Dictionary:
			return false
		if group == "weapons":
			for id: String in DEFAULTS.weapons:
				if not data.weapons.get(id) is Dictionary or not data.weapons[id].get("name") is String or data.weapons[id].name.strip_edges().is_empty():
					return false
			continue
		for key: String in DEFAULTS[group]:
			if not data[group].has(key):
				return false
			var value: Variant = data[group][key]
			if key == "color":
				if not value is String or not Color.html_is_valid(value):
					return false
			elif typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) <= 0.0:
				return false
	if float(data.carrier.dogfight_loss_probability) > 1.0 or int(data.carrier.dogfight_loss_min) > int(data.carrier.dogfight_loss_max):
		return false
	if float(data.missile.cooldown_real_s) < 5.0:
		return false
	if data.radar.near_radius_km > data.radar.far_radius_km or data.radar.sector_degrees > 360.0:
		return false
	return true
