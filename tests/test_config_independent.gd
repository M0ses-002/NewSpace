extends SceneTree

const Config = preload("res://scripts/simulation_config.gd")
const Units = preload("res://scripts/game_units.gd")
const Orbit = preload("res://scripts/kepler_orbit.gd")
const Planet = preload("res://scripts/planet.gd")

var checks: int = 0
var failures: int = 0
var expected_load_errors: int = 0
var temporary_files: Array[String] = []
var valid_planet: Dictionary
var valid_ship: Dictionary

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", description)

func expect_fallback(planet_data: Variant, ship_data: Variant, description: String) -> void:
	var before_planet: Dictionary = Config.planet.duplicate(true)
	var before_ship: Dictionary = Config.ship.duplicate(true)
	var result: Dictionary = Config.parse_dictionaries(planet_data, ship_data)
	check(not result.valid, description + "：拒绝非法配置")
	check(result.planet == Config.DEFAULT_PLANET and result.ship == Config.DEFAULT_SHIP, description + "：两组完整回退")
	check(not result.errors.is_empty(), description + "：返回具体错误")
	check(Config.planet == before_planet and Config.ship == before_ship, description + "：纯解析不改全局")

func check_field_inputs() -> void:
	for group: String in ["planet", "ship"]:
		var defaults: Dictionary = Config.DEFAULT_PLANET if group == "planet" else Config.DEFAULT_SHIP
		for key: String in defaults:
			for invalid: Variant in [true, "10", NAN, INF, -INF, -1.0, null]:
				var p: Dictionary = valid_planet.duplicate(true)
				var s: Dictionary = valid_ship.duplicate(true)
				if group == "planet":
					p[key] = invalid
				else:
					s[key] = invalid
				expect_fallback(p, s, "%s.%s=%s" % [group, key, str(invalid)])
			var p: Dictionary = valid_planet.duplicate(true)
			var s: Dictionary = valid_ship.duplicate(true)
			if group == "planet":
				p.erase(key)
			else:
				s.erase(key)
			expect_fallback(p, s, "%s.%s缺字段" % [group, key])
			if key != "max_eccentricity":
				p = valid_planet.duplicate(true)
				s = valid_ship.duplicate(true)
				if group == "planet":
					p[key] = 0.0
				else:
					s[key] = 0.0
				expect_fallback(p, s, "%s.%s为零" % [group, key])
	for invalid: Variant in [null, [], true, "{}", 1.0]:
		expect_fallback(invalid, valid_ship, "行星根对象类型%s" % str(invalid))
		expect_fallback(valid_planet, invalid, "飞船根对象类型%s" % str(invalid))

func check_cross_constraints() -> void:
	var cases: Array[Dictionary] = [
		{"planet": {"max_eccentricity": 1.0}, "name": "偏心率等于一"},
		{"planet": {"max_eccentricity": 1.1}, "name": "偏心率大于一"},
		{"planet": {"gravity_radius_km": 64.0}, "name": "引力范围等于场顶"},
		{"planet": {"gravity_radius_km": 63.0}, "name": "引力范围低于场顶"},
		{"planet": {"min_periapsis_km": 63.0}, "name": "近心点低于场顶"},
		{"planet": {"min_periapsis_km": 500.0}, "name": "近心点等于引力范围"},
		{"planet": {"min_periapsis_km": 501.0}, "name": "近心点超过引力范围"},
		{"planet": {"max_semi_major_axis_km": 89.0}, "name": "最大半长轴低于近心点"},
		{"ship": {"initial_orbit_radius_km": 89.0}, "name": "初轨道低于近心点"},
		{"ship": {"initial_orbit_radius_km": 1201.0}, "name": "初轨道超过最大半长轴"},
		{"ship": {"initial_orbit_radius_km": 500.0}, "name": "初轨道等于引力范围"},
		{"ship": {"initial_orbit_radius_km": 501.0}, "name": "初轨道超过引力范围"},
		{"planet": {"radius_km": 1.0e308, "field_thickness_km": 1.0e308}, "name": "场顶派生值溢出"},
		{"planet": {"gravity_m_s2": 1.0e308}, "name": "MU派生值溢出"},
		{"planet": {"gravity_m_s2": 1.0e-320}, "name": "MU派生值下溢为零"},
		{"ship": {"max_acceleration_m_s2": 1.0e-323}, "name": "加速度换算下溢"},
		{"ship": {"free_flight_max_speed_m_s": 1.0e-323}, "name": "最大速度换算下溢"},
	]
	for test_case: Dictionary in cases:
		var p: Dictionary = valid_planet.duplicate(true)
		var s: Dictionary = valid_ship.duplicate(true)
		p.merge(test_case.get("planet", {}), true)
		s.merge(test_case.get("ship", {}), true)
		expect_fallback(p, s, test_case.name)
	var p: Dictionary = valid_planet.duplicate(true)
	var s: Dictionary = valid_ship.duplicate(true)
	p.min_periapsis_km = 64.0
	p.max_semi_major_axis_km = 64.0
	s.initial_orbit_radius_km = 64.0
	check(Config.parse_dictionaries(p, s).valid, "近心点等于场顶、初轨道等于近心点和最大半长轴均合法")

func write_temporary(path: String, content: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "创建独立临时文件：" + path)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	temporary_files.append(path)
	return true

func expect_file_fallback(planet_path: String, ship_path: String, description: String) -> void:
	expected_load_errors += 1
	check(not Config.load_files(planet_path, ship_path), description + "：load_files失败")
	check(Config.planet == Config.DEFAULT_PLANET and Config.ship == Config.DEFAULT_SHIP, description + "：两组完整回退")
	check(not Config.last_errors.is_empty(), description + "：保留错误")

func check_file_loading() -> void:
	var prefix: String = "user://config_independent_%s_%s_" % [OS.get_process_id(), Time.get_ticks_usec()]
	var planet_path: String = prefix + "planet.json"
	var ship_path: String = prefix + "ship.json"
	var malformed_path: String = prefix + "malformed.json"
	var array_path: String = prefix + "array.json"
	var invalid_path: String = prefix + "invalid.json"
	var missing_path: String = prefix + "missing.json"
	if not write_temporary(planet_path, JSON.stringify(valid_planet)):
		return
	if not write_temporary(ship_path, JSON.stringify(valid_ship)):
		return
	if not write_temporary(malformed_path, "{ invalid JSON"):
		return
	if not write_temporary(array_path, "[]"):
		return
	var invalid_ship: Dictionary = valid_ship.duplicate(true)
	invalid_ship.max_acceleration_m_s2 = 0.0
	if not write_temporary(invalid_path, JSON.stringify(invalid_ship)):
		return
	check(Config.load_files(planet_path, ship_path), "临时有效JSON完整加载")
	check(Config.planet == valid_planet and Config.ship == valid_ship, "临时JSON真实替换两组配置")
	check(Config.last_errors.is_empty(), "有效JSON清空错误")
	check(not FileAccess.file_exists(missing_path), "缺失文件测试路径确实不存在")
	expect_file_fallback(missing_path, ship_path, "行星文件缺失")
	expect_file_fallback(planet_path, missing_path, "飞船文件缺失")
	expect_file_fallback(malformed_path, ship_path, "行星JSON非法")
	expect_file_fallback(planet_path, malformed_path, "飞船JSON非法")
	expect_file_fallback(array_path, ship_path, "行星JSON根类型非法")
	expect_file_fallback(planet_path, array_path, "飞船JSON根类型非法")
	expect_file_fallback(planet_path, invalid_path, "真实文件加速度非正")
	check(Config.load_files(planet_path, ship_path), "错误之后可重新加载有效文件")
	check(Config.last_errors.is_empty(), "成功加载清除之前错误")

func check_dynamic_units_and_planet() -> void:
	Config.planet = valid_planet.duplicate(true)
	Config.ship = valid_ship.duplicate(true)
	Config.ensure_loaded()
	check(Config.planet == valid_planet and Config.ship == valid_ship, "ensure_loaded保留已加载后的内存配置")
	check(Units.PLANET_RADIUS_KM == 60.0 and Units.FIELD_THICKNESS_KM == 4.0 and Units.FIELD_TOP_RADIUS_KM == 64.0, "单位getter即时反映尺寸")
	check(Units.FIELD_GRAVITY_M_S2 == 12.0 and Units.GRAVITY_RADIUS_KM == 500.0, "单位getter即时反映重力及范围")
	var expected_mu: float = 12.0 / 1000.0 * 64.0 * 64.0
	check(absf(Units.EXTERNAL_MU_KM3_S2 - expected_mu) < 1.0e-10, "单位MU即时计算")
	check(absf(Orbit.MU - expected_mu) < 1.0e-10, "实际Orbit.MU随配置改变")
	check(Orbit.MIN_PERIAPSIS == 90.0 and Orbit.MAX_A == 1200.0 and Orbit.MAX_E == 0.7, "轨道约束getter即时改变")
	var planet_node: Node2D = Planet.new()
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	planet_node.add_child(sprite)
	var surface := Polygon2D.new()
	surface.name = "Surface"
	planet_node.add_child(surface)
	var atmosphere := Polygon2D.new()
	atmosphere.name = "Atmosphere"
	planet_node.add_child(atmosphere)
	var label := Label.new()
	label.name = "Name"
	planet_node.add_child(label)
	root.add_child(planet_node)
	planet_node.refresh_from_config()
	check(surface.polygon.size() == 64 and atmosphere.polygon.size() == 64, "刷新生成完整行星与场顶多边形")
	var geometry_ok: bool = true
	for index in range(surface.polygon.size()):
		geometry_ok = geometry_ok and absf(surface.polygon[index].length() - 60.0) < 0.0001
		geometry_ok = geometry_ok and absf(atmosphere.polygon[index].length() - 64.0) < 0.0001
	check(geometry_ok, "所有地表和场顶顶点反映新尺寸")
	check(surface.texture_scale.is_equal_approx(Vector2.ONE * 1.2), "表面纹理随尺寸缩放")
	check(surface.texture_offset.is_equal_approx(Vector2.ONE * 76.8), "表面纹理偏移随尺寸改变")
	check(label.position.y == 71.0 and label.text.contains("500.0 km"), "名称位置和引力范围文字刷新")
	Config.planet.radius_km = 70.0
	Config.planet.field_thickness_km = 5.0
	planet_node.refresh_from_config()
	check(absf(surface.polygon[0].length() - 70.0) < 0.0001 and absf(atmosphere.polygon[0].length() - 75.0) < 0.0001, "同一节点二次刷新实际改变尺寸")
	check(absf(Orbit.MU - 12.0 / 1000.0 * 75.0 * 75.0) < 1.0e-10, "内存再次修改后MU无旧值缓存")
	planet_node.free()

func check_zero_eccentricity() -> void:
	var p: Dictionary = valid_planet.duplicate(true)
	p.max_eccentricity = 0.0
	var result: Dictionary = Config.parse_dictionaries(p, valid_ship)
	check(result.valid and result.errors.is_empty(), "max_eccentricity=0配置合法")
	Config.planet = result.planet
	Config.ship = result.ship
	check(Orbit.MAX_E == 0.0, "真实轨道读取零偏心率上限")
	for radius: float in [90.0, 240.0, 499.0, 1200.0]:
		for angle: float in [0.0, 0.37, 1.6, 3.1]:
			for direction: float in [-1.0, 1.0]:
				var circular: Dictionary = Orbit.make(radius, 0.0, angle)
				var state: Dictionary = Orbit.state_at(circular, 0.73, direction)
				var interval: Vector2 = Orbit.speed_interval(state.position, state.velocity)
				var speed: float = sqrt(Orbit.MU / radius)
				var description: String = "零偏心率r=%s角=%s方向=%s" % [radius, angle, direction]
				check(interval.is_finite() and interval.x > 0.0, description + "：区间有限非空")
				check(absf(interval.x - speed) < 0.00001 and absf(interval.y - speed) < 0.00001, description + "：上下限退化为圆速")
				var recovered: Dictionary = Orbit.from_state(state.position, state.velocity, angle)
				check(not recovered.is_empty(), description + "：状态反解不为空")
				if recovered.is_empty():
					continue
				check(recovered.orbit.e == 0.0 and is_finite(recovered.orbit.a) and absf(recovered.orbit.a - radius) < 0.005, description + "：反解圆轨道无除零")
				check(is_finite(recovered.mean_anomaly) and recovered.direction == direction, description + "：反解相位与方向有效")
	check(Orbit.speed_interval(Vector2(240.0, 0.0), Vector2(1.0, 0.0)) == Vector2.ZERO, "零偏心率拒绝径向速度且无除零")
	check(Orbit.from_state(Vector2(240.0, 0.0), Vector2.ZERO).is_empty(), "零偏心率拒绝零速度且无除零")

func run() -> void:
	Config.ensure_loaded()
	check(Config.last_errors.is_empty(), "默认工程JSON加载成功")
	check(Config.planet == Config.DEFAULT_PLANET and Config.ship == Config.DEFAULT_SHIP, "真实默认JSON与安全默认完全一致")
	check(Config.parse_dictionaries(Config.DEFAULT_PLANET, Config.DEFAULT_SHIP).valid, "安全默认通过纯校验")
	valid_planet = Config.DEFAULT_PLANET.duplicate(true)
	valid_planet.merge({"radius_km": 60.0, "field_thickness_km": 4.0, "gravity_m_s2": 12.0, "gravity_radius_km": 500.0, "min_periapsis_km": 90.0, "max_semi_major_axis_km": 1200.0, "max_eccentricity": 0.7}, true)
	valid_ship = {"initial_orbit_radius_km": 260.0, "max_acceleration_m_s2": 20.0, "free_flight_max_speed_m_s": 1500.0, "turnaround_cooldown_real_s": 10.0}
	check(Config.parse_dictionaries(valid_planet, valid_ship).valid, "自定义非默认配置有效")
	check_field_inputs()
	check_cross_constraints()
	check_file_loading()
	check_dynamic_units_and_planet()
	check_zero_eccentricity()
	check(Config.load_files(), "末尾恢复真实默认配置")
	check(Config.planet == Config.DEFAULT_PLANET and Config.ship == Config.DEFAULT_SHIP and Config.last_errors.is_empty(), "恢复后无内存配置污染")
	for path: String in temporary_files:
		check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "删除自己的临时文件：" + path)
		check(not FileAccess.file_exists(path), "确认临时文件已删除：" + path)
	print("CONFIG_INDEPENDENT checks=%d failures=%d expected_load_errors=%d" % [checks, failures, expected_load_errors])
	quit(0 if failures == 0 else 1)
