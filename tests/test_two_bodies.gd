extends SceneTree
## 双行星引力核心：可选 mu 参数、第二行星局部轨道、跨球交接、出球与多圆避让。
const Config = preload("res://scripts/simulation_config.gd")
const Orbit = preload("res://scripts/kepler_orbit.gd")
const Units = preload("res://scripts/game_units.gd")
const Flight = preload("res://scripts/free_flight.gd")
const CENTER_B: Vector2 = Vector2(860.0, 0.0)

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", description)

func mu_of(data: Dictionary) -> float:
	var field_top: float = float(data.radius_km) + float(data.field_thickness_km)
	return float(data.gravity_m_s2) / Units.METERS_PER_KM * field_top * field_top

func run() -> void:
	root.size = Vector2i(1280, 800)
	Config.ensure_loaded()
	check(Config.last_errors.is_empty(), "默认配置加载成功")
	check(not Config.planet_b.is_empty(), "第二行星配置已加载")
	if Config.planet_b.is_empty():
		print("TWO_BODIES_TESTS checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	check(absf(float(Config.planet_b.center_x_km) - 860.0) < 1.0e-9 and absf(float(Config.planet_b.center_y_km)) < 1.0e-9, "第二行星中心位于 (860, 0)")
	var mu: float = Units.EXTERNAL_MU_KM3_S2
	check(absf(mu - 27.55629) < 1.0e-5, "默认 MU 为 27.55629 km³/s²")
	check(absf(mu_of(Config.planet_b) - mu) < 1.0e-9, "两颗行星引力常数相同")
	test_mu_parameter(mu)
	test_second_body_orbit()
	test_plan_bodies()
	await test_cross_body_handoff()
	await test_exit_from_first_body()
	print("TWO_BODIES_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_mu_parameter(mu: float) -> void:
	for semi in [160.0, 240.0, 400.0]:
		for e in [0.0, 0.1, 0.45]:
			var orbit: Dictionary = Orbit.make(semi, e, 0.37)
			for anomaly in [-2.1, 0.0, 0.8]:
				var base: Dictionary = Orbit.state_at(orbit, anomaly, 1.0)
				var explicit: Dictionary = Orbit.state_at(orbit, anomaly, 1.0, mu)
				check(base.position.distance_to(explicit.position) < 1.0e-6, "state_at 显式 mu 位置一致 a=%s e=%s" % [semi, e])
				check(base.velocity.distance_to(explicit.velocity) < 1.0e-6, "state_at 显式 mu 速度一致 a=%s e=%s" % [semi, e])
				var implicit_velocity: Vector2 = Orbit.velocity_at(orbit, base.position, 1.0)
				var explicit_velocity: Vector2 = Orbit.velocity_at(orbit, base.position, 1.0, mu)
				check(implicit_velocity.distance_to(explicit_velocity) < 1.0e-6, "velocity_at 显式 mu 一致 a=%s e=%s" % [semi, e])
			var state: Dictionary = Orbit.state_at(orbit, 0.4, 1.0)
			var implicit_orbit: Dictionary = Orbit.from_state(state.position, state.velocity, 0.37)
			var explicit_orbit: Dictionary = Orbit.from_state(state.position, state.velocity, 0.37, mu)
			check(not implicit_orbit.is_empty() and not explicit_orbit.is_empty(), "from_state 两种调用均有效 a=%s e=%s" % [semi, e])
			if not implicit_orbit.is_empty() and not explicit_orbit.is_empty():
				check(absf(float(implicit_orbit.orbit.a) - float(explicit_orbit.orbit.a)) < 1.0e-6, "from_state 显式 mu 半长轴一致")
				check(absf(float(implicit_orbit.orbit.e) - float(explicit_orbit.orbit.e)) < 1.0e-6, "from_state 显式 mu 偏心率一致")
			var implicit_interval: Vector2 = Orbit.speed_interval(state.position, state.velocity)
			var explicit_interval: Vector2 = Orbit.speed_interval(state.position, state.velocity, mu)
			check(implicit_interval.distance_to(explicit_interval) < 1.0e-6, "speed_interval 显式 mu 一致 a=%s e=%s" % [semi, e])

func test_second_body_orbit() -> void:
	var mu: float = mu_of(Config.planet_b)
	var local: Dictionary = Orbit.state_at(Orbit.make(240.0, 0.0, 0.3), 0.6, 1.0, mu)
	var recovered: Dictionary = Orbit.from_state(local.position, local.velocity, 0.3, mu)
	check(not recovered.is_empty(), "绕第二行星的局部状态可反解")
	if not recovered.is_empty():
		check(absf(float(recovered.orbit.a) - 240.0) < 0.005, "绕第二行星的局部半长轴正确")
		check(float(recovered.orbit.e) < 0.000001, "绕第二行星的局部轨道为圆")
		check(absf(float(recovered.mean_anomaly) - 0.6) < 0.0001, "绕第二行星的局部相位正确")
	var world: Vector2 = local.position + CENTER_B
	check(absf(world.distance_to(CENTER_B) - 240.0) < 0.001, "加回中心后世界半径 240 km")
	check(absf(local.position.length() - 240.0) < 0.001, "局部坐标以第二行星中心为原点")
	# 局部速度用错引力常数时能量为正，必须被拒绝，证明焦点参数确实参与运算。
	var wrong: Dictionary = Orbit.from_state(local.position, local.velocity, 0.3, mu * 0.25)
	check(wrong.is_empty(), "错误引力常数无法反解同一局部状态")

func test_plan_bodies() -> void:
	var mu: float = mu_of(Config.planet_b)
	var entry_limit: float = 0.9 * sqrt(2.0 * mu / 400.0)
	var f = Flight.new()
	f.max_acceleration = 0.01
	f.max_speed = 1.0
	f.set_state(Vector2(430.0, 0.0), Vector2(0.25, 0.0))
	var accepted: bool = f.plan_bodies(Vector2(860.0, 0.0), [
		{"center": Vector2.ZERO, "radius": 400.0, "entry_limit": entry_limit},
		{"center": CENTER_B, "radius": 400.0, "entry_limit": entry_limit},
	])
	check(accepted, "前往第二行星的多圆规划成功")
	check(f.boundary_crossing, "目标在第二行星球内时标记穿界")
	check(f.entry_body_index == 1, "记录最早的入球天体为第二行星")
	check(f.target.distance_to(Vector2(460.0, 0.0)) < 0.001, "目标截断到第二行星影响球边界")
	var peak: float = 0.0
	for segment: Dictionary in f.segments:
		peak = maxf(peak, (segment.velocity + segment.acceleration * float(segment.duration)).length())
	check(peak > 0.0 and peak <= entry_limit + 1.0e-6, "入球峰值不超过入球速度上限 peak=%s limit=%s" % [peak, entry_limit])
	check(f.route[-1] == Vector2(860.0, 0.0), "路线保留原始点击目标")
	# 制动段穿过任一天体影响球时必须拒绝。
	var blocked = Flight.new()
	blocked.max_acceleration = 0.01
	blocked.max_speed = 1.0
	blocked.set_state(Vector2(400.0, 0.0), Vector2(2.0, 0.0))
	check(not blocked.plan_bodies(Vector2(1000.0, 0.0), [
		{"center": Vector2.ZERO, "radius": 400.0, "entry_limit": 0.0},
		{"center": CENTER_B, "radius": 400.0, "entry_limit": 0.0},
	]), "制动段穿过第二行星影响球时拒绝")
	check(blocked.last_error.contains("制动"), "拒绝原因指明制动段")
	# 起点已在某个球内时忽略该球，保持单球行为可规划。
	var inside = Flight.new()
	inside.max_acceleration = 0.01
	inside.max_speed = 1.0
	inside.set_state(Vector2(500.0, 0.0), Vector2.ZERO)
	check(inside.plan_bodies(Vector2.ZERO, [
		{"center": Vector2.ZERO, "radius": 400.0, "entry_limit": 0.0},
		{"center": CENTER_B, "radius": 400.0, "entry_limit": 0.0},
	]), "起点已在第二行星球内时仍可规划回第一行星")
	check(inside.boundary_crossing and inside.entry_body_index == 0, "仍记录第一行星为入球天体")
	check(inside.target.distance_to(Vector2(400.0, 0.0)) < 0.001, "仍截断在第一行星影响球边界")

func test_cross_body_handoff() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	await process_frame
	check(scene.bodies.size() == 2 and scene.has_second_planet(), "沙盒构建两颗静态天体")
	check(scene.focus_index == 0 and absf(scene.gravity_radius - 400.0) < 0.001, "初始焦点为第一颗行星")
	check(absf(float(scene.bodies[1].center.x) - 860.0) < 1.0e-6 and absf(float(scene.bodies[1].mu) - mu_of(Config.planet_b)) < 1.0e-9, "第二颗天体中心与引力常数正确")
	scene.motion_mode = "FREE"
	scene.pending_simulation_time = 0.0
	scene.manually_paused = false
	scene.ship.position = Vector2(430.0, 0.0)
	scene.velocity = Vector2(0.25, 0.0)
	scene.flight.set_state(scene.ship.position, scene.velocity)
	scene._advance_motion(200.0)
	check(scene.focus_index == 1, "跨球后焦点切换到第二颗行星")
	check(scene.motion_mode in ["CAPTURE_PREP", "CAPTURE_BURN", "ORBIT"], "跨球后进入入轨流程")
	var local: Vector2 = scene.ship.position - CENTER_B
	check(local.length() <= 400.0 + 0.001, "交接后飞船位于第二行星影响球内")
	check(absf(scene.gravity_radius - float(scene.bodies[1].gravity_radius_km)) < 1.0e-6, "影响球半径随焦点同步")
	check(scene.local_position().distance_to(local) < 1.0e-6, "局部坐标相对第二行星中心")
	scene.queue_free()
	await process_frame

func test_exit_from_first_body() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	await process_frame
	scene.focus_index = 0
	scene.gravity_radius = float(scene.bodies[0].gravity_radius_km)
	scene.motion_mode = "ORBIT"
	scene.orbit_acquired = true
	scene.orbit = Orbit.make(400.0, 0.05, 0.0)
	scene.preview = scene.orbit.duplicate()
	scene.mean_anomaly = 0.4
	scene.orbit_direction = 1.0
	scene._refresh_ship()
	check(scene.local_position().length() < 400.0, "出球前位于第一行星影响球内")
	for iteration in range(400):
		if scene.motion_mode != "ORBIT":
			break
		scene._advance_orbit(30.0)
	check(scene.motion_mode == "FREE", "远心点超过影响球后转入惯性飞行")
	check(scene.focus_index == 0, "离开第一行星不切换焦点")
	check(scene.local_position().length() >= 400.0 - 0.01, "出球点位于影响球边界")
	check(scene.velocity.length() > 0.0, "出球保留边界速度")
	scene.queue_free()
	await process_frame
