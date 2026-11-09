extends RefCounted

const SAVE_PATH := "user://hard_mode.json"
const RULES_PATH := "res://data/hard_mode.json"

static func is_enabled() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return false
	var data: Variant = parser.data
	if not data is Dictionary:
		return false
	var enabled: Variant = data.get("enabled")
	return enabled if enabled is bool else false

static func set_enabled(enabled: bool) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"enabled": enabled}))
	file.flush()
	return file.get_error() == OK

static func get_rule(level: int) -> Dictionary:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null:
		return {}
	var rules: Variant = JSON.parse_string(file.get_as_text())
	if not rules is Dictionary or not rules.get(str(level)) is Dictionary:
		return {}
	var rule: Dictionary = rules[str(level)]
	return rule if valid_rule(level, rule) else {}

static func valid_rule(level: int, rule: Dictionary) -> bool:
	if level not in range(1, 9):
		return false
	if not rule.has_all(["time_limit_seconds", "max_slots", "weapon_limits"]) or not rule.weapon_limits is Dictionary:
		return false
	var seconds: Variant = rule.time_limit_seconds
	if seconds != null and (typeof(seconds) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(seconds)) or float(seconds) <= 0.0):
		return false
	var slots: Variant = rule.max_slots
	if slots != null and (typeof(slots) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(slots)) or float(slots) != floor(float(slots)) or float(slots) < 0.0 or float(slots) > 4.0):
		return false
	for limit in rule.weapon_limits.values():
		if typeof(limit) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(limit)) or float(limit) != floor(float(limit)) or float(limit) < 0.0 or float(limit) > 4.0:
			return false
	return true

static func equipment_error(rule: Dictionary, slots: Array) -> String:
	var equipped := 0
	for slot in slots:
		if slot != "":
			equipped += 1
	if rule.max_slots != null and equipped > int(rule.max_slots):
		return "困难模式：本关最多装备 %d 个非空槽位，请返回菜单调整装备。" % int(rule.max_slots)
	for weapon in rule.get("weapon_limits", {}):
		var limit := int(rule.weapon_limits[weapon])
		if slots.count(weapon) > limit:
			var name := "导弹" if weapon == "missile" else str(weapon)
			return "困难模式：本关最多装备 %d 个%s，请返回菜单调整装备。" % [limit, name]
	return ""
