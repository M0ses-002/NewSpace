extends SceneTree
const Orbit = preload("res://scripts/kepler_orbit.gd")
const EnemyBehavior = preload("res://scripts/enemy_behavior.gd")
var checks: int = 0
var failures: int = 0

class StubController extends Node:
	const Config = preload("res://scripts/simulation_config.gd")
	var gravity_radius: float = 400.0
	var ship: Node2D
	func body_at(_index: int) -> Dictionary:
		var planet: Dictionary = Config.planet
		var top: float = float(planet.radius_km) + float(planet.field_thickness_km)
		return {"center": Vector2.ZERO, "radius_km": planet.radius_km, "field_top_km": top, "mu": float(planet.gravity_m_s2) / 1000.0 * top * top, "gravity_radius_km": gravity_radius}
	func _gravity(_p: Vector2, _index: int = -1) -> Vector2:
		return Vector2.ZERO
	func _surface_contact_time(_p: Vector2, _v: Vector2, _a: Vector2, _h: float) -> float:
		return INF

class StubCombat extends Node:
	var controller: Node
	var dead := false

class StubHost extends Node2D:
	var state: Dictionary = {}

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func field_mu() -> float:
	var planet: Dictionary = StubController.Config.planet
	var top: float = float(planet.radius_km) + float(planet.field_thickness_km)
	return float(planet.gravity_m_s2) / 1000.0 * top * top

func make_running(acceleration: float) -> Dictionary:
	StubController.Config.ensure_loaded()
	var behavior = EnemyBehavior.new()
	var controller: Node = StubController.new()
	var combat: Node = StubCombat.new()
	combat.controller = controller
	var host: StubHost = StubHost.new()
	host.state = {"config": {"acceleration_km_s2": acceleration}, "velocity": Vector2.ZERO}
	var target_node: StubHost = StubHost.new()
	controller.ship = target_node
	return {"behavior": behavior, "controller": controller, "combat": combat, "host": host, "target": target_node, "target_data": {"node": target_node}}

func free_setup(setup: Dictionary) -> void:
	for key in ["host", "target", "combat", "controller"]:
		var node: Node = setup[key]
		if is_instance_valid(node):
			node.free()

func run() -> void:
	test_steer_helper()
	test_rate_bound()
	test_budget_saturation()
	await test_tracking_bounds()
	await test_player_pursuit()
	print("ENEMY_STEERING_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_steer_helper() -> void:
	var behavior = EnemyBehavior.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 771111
	for trial in range(300):
		var radius: float = rng.randf_range(76.0, 1000.0)
		var point: Vector2 = Vector2.from_angle(rng.randf_range(-PI, PI)) * radius
		var speed: float = rng.randf_range(0.05, 1.5)
		var direction: float = 1.0 if trial % 2 == 0 else -1.0
		var gamma: float = rng.randf_range(-1.2, 1.2)
		var velocity: Vector2 = Orbit.heading_velocity(point, speed, gamma, direction)
		var delta: float = rng.randf_range(-0.6, 0.6)
		var turned: Vector2 = behavior.steer_velocity(velocity, point, direction, delta)
		check(absf(turned.length() - speed) < 0.000001, "转向严格保持速率 speed=%s got=%s" % [speed, turned.length()])
		check(absf(Orbit.flight_path_angle(point, turned, direction) - (gamma + delta)) < 0.00001, "转向角增量与请求一致")
		var back: Vector2 = behavior.steer_velocity(turned, point, direction, -delta)
		check(back.distance_to(velocity) < 0.00001, "正反转向闭合")
	check(behavior.steer_velocity(Vector2.ZERO, Vector2(200, 0), 1.0, 0.3) == Vector2.ZERO, "零速率转向保持为零")
	check(behavior.steer_velocity(Vector2(0.2, 0), Vector2.ZERO, 1.0, 0.3) == Vector2(0.2, 0), "零位置转向保持原速度")

func test_rate_bound() -> void:
	var setup: Dictionary = make_running(0.0005)
	var point: Vector2 = Vector2(300, 0)
	var circular: float = sqrt(field_mu() / 300.0)
	setup.host.position = point
	setup.host.state.velocity = Orbit.heading_velocity(point, circular, 0.3, 1.0)
	setup.target.position = point
	var before: Vector2 = setup.host.state.velocity
	var gamma_before: float = Orbit.flight_path_angle(point, before, 1.0)
	setup.behavior.advance(setup.host, setup.combat, setup.target_data, 0.25)
	var after: Vector2 = setup.host.state.velocity
	var turned: float = absf(angle_difference(before.angle(), after.angle()))
	var omega_cap: float = 0.0005 / before.length()
	check(absf(after.length() - before.length()) < 0.000001, "零推力步进保持速率")
	check(turned <= omega_cap * 0.25 + 0.000001, "每步转角不超过法向预算 limit=%s got=%s" % [omega_cap * 0.25, turned])
	check(turned > omega_cap * 0.25 * 0.9, "大偏角误差下转向达到预算上限 got=%s" % turned)
	var turn_rate: float = setup.behavior._turn_rate(300.0, before.length(), field_mu(), 300.0, gamma_before, 0.0, 0.0005, setup.controller)
	check(absf(turn_rate) <= omega_cap + 0.0000001, "转速受预算上限约束")
	check(turn_rate < 0.0, "高于参考偏角时向内转向")
	free_setup(setup)

func test_budget_saturation() -> void:
	var setup: Dictionary = make_running(0.00001)
	var point: Vector2 = Vector2(300, 0)
	var circular: float = sqrt(field_mu() / 300.0)
	setup.host.position = point
	setup.host.state.velocity = Orbit.heading_velocity(point, circular, 0.25, 1.0)
	setup.target.position = Vector2(320, 0)
	var before: Vector2 = setup.host.state.velocity
	setup.behavior.advance(setup.host, setup.combat, setup.target_data, 0.25)
	var after: Vector2 = setup.host.state.velocity
	var tangent: Vector2 = Vector2(-point.y, point.x).normalized() * 1.0
	var expected: Vector2 = before + tangent * 0.00001 * 0.25
	check(after.distance_to(expected) < 0.0000001, "切向预算饱和时法向转向为零")
	free_setup(setup)

func test_tracking_bounds() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	scene.reset()
	scene.ship.position = scene.combat.satellites[0].node.position
	var battle = scene.combat
	var enemy: Dictionary = battle.enemies[0]
	var mu: float = field_mu()
	enemy.node.position = Vector2(200, 0)
	enemy.velocity = Vector2(0, sqrt(mu / 200.0))
	var target: Dictionary = {"node": battle.satellites[0].node}
	var max_apoapsis: float = 0.0
	var min_periapsis: float = INF
	var max_radius: float = 0.0
	for i in range(4000):
		enemy.node.behavior.advance(enemy.node, battle, target, 0.25)
		var p: Vector2 = enemy.node.position
		var v: Vector2 = enemy.velocity
		max_radius = maxf(max_radius, p.length())
		var energy: float = 0.5 * v.length_squared() - mu / p.length()
		if energy < 0.0:
			var a: float = -mu / (2.0 * energy)
			var h: float = p.cross(v)
			var e: float = sqrt(maxf(0.0, 1.0 - h * h / (mu * a)))
			max_apoapsis = maxf(max_apoapsis, a * (1.0 + e))
			min_periapsis = minf(min_periapsis, a * (1.0 - e))
	check(max_apoapsis < scene.gravity_radius * 0.95, "全称远心不超过0.95R max=%s" % max_apoapsis)
	check(min_periapsis >= Orbit.MIN_PERIAPSIS - 0.01, "全称近心不低于76km min=%s" % min_periapsis)
	check(max_radius < scene.gravity_radius, "追踪过程不逃逸引力范围 max=%s" % max_radius)
	check(enemy.node.position.length() < 320.0, "追踪结束仍受最大工作半径约束")
	scene.queue_free()
	await process_frame

func test_player_pursuit() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	scene.reset()
	var battle = scene.combat
	var enemy: Dictionary = battle.enemies[0]
	var mu: float = field_mu()
	for phase in [0.5, 1.0, -1.0]:
		var radius: float = 200.0
		enemy.node.position = Vector2(radius, 0)
		enemy.velocity = Vector2(0, sqrt(mu / radius))
		var player_phase: float = phase
		var initial: float = enemy.node.position.distance_to(Vector2.from_angle(player_phase) * radius)
		var best: float = initial
		var alive := true
		for i in range(4000):
			player_phase += sqrt(mu / (radius * radius * radius)) * 0.25
			scene.ship.position = Vector2.from_angle(player_phase) * radius
			alive = enemy.node.behavior.advance(enemy.node, battle, {}, 0.25)
			if not alive:
				break
			best = minf(best, enemy.node.position.distance_to(scene.ship.position))
		print("PURSUIT phase=%s initial=%s best=%s final=%s alive=%s" % [phase, initial, best, enemy.node.position.distance_to(scene.ship.position), alive])
		check(alive and best < initial * 0.7, "敌机主动缩短与运动玩家的距离 phase=%s" % phase)
	battle.dead = true
	var setup: Dictionary = make_running(0.0005)
	setup.host.position = Vector2(500, 0)
	setup.host.state.velocity = Vector2(0, 0.2)
	setup.combat.dead = true
	setup.behavior.advance(setup.host, setup.combat, setup.target_data, 0.25)
	check(setup.host.state.velocity == Vector2(0, 0.2), "玩家无效时圈外惯性滑行")
	setup.combat.dead = false
	setup.host.position = Vector2(200, 0)
	setup.host.state.velocity = Vector2(0, sqrt(mu / 200.0))
	setup.target.position = Vector2(1000, 0)
	var before: Vector2 = setup.host.state.velocity
	setup.behavior.advance(setup.host, setup.combat, setup.target_data, 0.25)
	check(setup.host.state.velocity == before, "玩家不在同一引力域时不施加推力")
	setup.host.position = Vector2(500, 0)
	setup.host.state.velocity = Vector2(0, 0.2)
	setup.controller.ship = null
	setup.behavior.advance(setup.host, setup.combat, setup.target_data, 0.25)
	check(setup.host.state.velocity == Vector2(0, 0.2), "玩家缺失时不追踪卫星")
	free_setup(setup)
	scene.queue_free()
	await process_frame
