extends RefCounted
## 启动时整体读取两份配置；任何错误均回退到一组完整安全默认值。
const PLANET_PATH: String = "res://data/planet.json"
const SHIP_PATH: String = "res://data/ship.json"
const SECOND_PLANET_PATH: String = "res://data/planet_b.json"
const CENTER_KEYS: Array[String] = ["center_x_km", "center_y_km"]
const DEFAULT_PLANET: Dictionary = {
	"radius_km": 50.0,
	"field_thickness_km": 3.0,
	"gravity_m_s2": 9.81,
	"gravity_radius_km": 400.0,
	"min_periapsis_km": 76.0,
	"max_semi_major_axis_km": 1000.0,
	"max_eccentricity": 0.85,
}
const DEFAULT_SHIP: Dictionary = {
	"initial_orbit_radius_km": 240.0,
	"max_acceleration_m_s2": 10.0,
	"free_flight_max_speed_m_s": 1000.0,
	"turnaround_cooldown_real_s": 10.0,
}
static var planet: Dictionary = {}
static var ship: Dictionary = {}
## 空字典表示世界中没有第二颗行星；非空时必须同时含七个主字段与中心坐标。
static var planet_b: Dictionary = {}
static var last_errors: Array[String] = []
static var _loaded: bool = false

static func ensure_loaded() -> void:
	if not _loaded:
		load_files()
		load_second_planet()

static func load_files(planet_path: String = PLANET_PATH, ship_path: String = SHIP_PATH) -> bool:
	var read_errors: Array[String] = []
	var planet_data: Variant = _read_json(planet_path, read_errors)
	var ship_data: Variant = _read_json(ship_path, read_errors)
	var result: Dictionary = parse_dictionaries(planet_data, ship_data)
	if not read_errors.is_empty():
		result.valid = false
		result.planet = DEFAULT_PLANET.duplicate(true)
		result.ship = DEFAULT_SHIP.duplicate(true)
		read_errors.append_array(result.errors)
		result.errors = read_errors
	planet = result.planet
	ship = result.ship
	last_errors = result.errors
	_loaded = true
	if not result.valid:
		push_error("模拟配置加载失败，行星与飞船均使用安全默认值：\n" + "\n".join(last_errors))
	return result.valid

## 读取第二颗行星：七个主字段复用同一套数值校验，中心坐标必须为有限数值。
## 文件缺失时静默返回 false（保持单行星世界），文件存在但非法时清空并报错。
static func load_second_planet(path: String = SECOND_PLANET_PATH) -> bool:
	planet_b = {}
	if not FileAccess.file_exists(path):
		return false
	var read_errors: Array[String] = []
	var data: Variant = _read_json(path, read_errors)
	var errors: Array[String] = []
	var parsed: Dictionary = {}
	if read_errors.is_empty():
		parsed = _validate_numbers(data, DEFAULT_PLANET, "planet_b", errors)
		if errors.is_empty():
			for key: String in CENTER_KEYS:
				var raw: Variant = data.get(key) if data is Dictionary else null
				if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
					errors.append("planet_b.%s 必须为数值，不接受布尔值或字符串" % key)
					continue
				var value: float = float(raw)
				if not is_finite(value):
					errors.append("planet_b.%s 必须为有限数值" % key)
					continue
				parsed[key] = value
	if not read_errors.is_empty() or not errors.is_empty():
		planet_b = {}
		push_error("第二行星配置加载失败，世界保持单行星：\n" + "\n".join(read_errors + errors))
		return false
	planet_b = parsed
	return true

## 纯校验接口，不改全局状态或真实 JSON，供测试注入字典。
static func parse_dictionaries(planet_data: Variant, ship_data: Variant) -> Dictionary:
	var errors: Array[String] = []
	var parsed_planet: Dictionary = _validate_numbers(planet_data, DEFAULT_PLANET, "planet", errors)
	var parsed_ship: Dictionary = _validate_numbers(ship_data, DEFAULT_SHIP, "ship", errors)
	if errors.is_empty():
		var field_top: float = parsed_planet.radius_km + parsed_planet.field_thickness_km
		var mu: float = parsed_planet.gravity_m_s2 / 1000.0 * field_top * field_top
		if not is_finite(field_top) or not is_finite(mu) or mu <= 0.0:
			errors.append("planet：场顶半径及派生引力参数必须为有限正数")
		if parsed_planet.max_eccentricity >= 1.0:
			errors.append("planet.max_eccentricity 必须小于 1")
		if parsed_planet.gravity_radius_km <= field_top:
			errors.append("planet.gravity_radius_km 必须大于行星半径与恒强场厚度之和")
		if parsed_planet.min_periapsis_km < field_top:
			errors.append("planet.min_periapsis_km 必须不小于场顶半径")
		if parsed_planet.min_periapsis_km >= parsed_planet.gravity_radius_km:
			errors.append("planet.min_periapsis_km 必须小于引力范围半径")
		if parsed_planet.max_semi_major_axis_km < parsed_planet.min_periapsis_km:
			errors.append("planet.max_semi_major_axis_km 必须不小于近心点安全半径")
		if parsed_ship.initial_orbit_radius_km < parsed_planet.min_periapsis_km or parsed_ship.initial_orbit_radius_km > parsed_planet.max_semi_major_axis_km:
			errors.append("ship.initial_orbit_radius_km 必须位于近心点安全半径与最大半长轴之间")
		if parsed_ship.initial_orbit_radius_km >= parsed_planet.gravity_radius_km:
			errors.append("ship.initial_orbit_radius_km 必须小于引力范围半径")
		for key: String in ["max_acceleration_m_s2", "free_flight_max_speed_m_s"]:
			var converted: float = parsed_ship[key] / 1000.0
			if not is_finite(converted) or converted <= 0.0:
				errors.append("ship.%s 换算为 km 单位后必须是有限正数" % key)
	var valid: bool = errors.is_empty()
	return {
		"valid": valid,
		"planet": parsed_planet if valid else DEFAULT_PLANET.duplicate(true),
		"ship": parsed_ship if valid else DEFAULT_SHIP.duplicate(true),
		"errors": errors,
	}

static func _validate_numbers(data: Variant, defaults: Dictionary, label: String, errors: Array[String]) -> Dictionary:
	var values: Dictionary = {}
	if not data is Dictionary:
		errors.append("%s 必须是 JSON 对象" % label)
		return values
	for key: String in defaults:
		if not data.has(key):
			errors.append("%s.%s 缺少必填字段" % [label, key])
			continue
		var raw: Variant = data[key]
		if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
			errors.append("%s.%s 必须为数值，不接受布尔值或字符串" % [label, key])
			continue
		var value: float = float(raw)
		if not is_finite(value) or value < 0.0 or (value == 0.0 and key != "max_eccentricity"):
			errors.append("%s.%s 必须为有限%s" % [label, key, "非负数" if key == "max_eccentricity" else "正数"])
			continue
		values[key] = value
	return values

static func _read_json(path: String, errors: Array[String]) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("%s 无法读取：%s" % [path, error_string(FileAccess.get_open_error())])
		return null
	var parser: JSON = JSON.new()
	var error: Error = parser.parse(file.get_as_text())
	if error != OK:
		errors.append("%s 第 %d 行 JSON 错误：%s" % [path, parser.get_error_line(), parser.get_error_message()])
		return null
	return parser.data
