extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", text)

func run() -> void:
	var level: Node = load("res://scenes/level_7.tscn").instantiate()
	root.add_child(level)
	var scene: Node = level.get_node("Sandbox")
	scene.set_physics_process(false)
	await process_frame
	var battle: Node = scene.get_node("World/Combat")
	battle.enemy_fire_enabled = false
	var enemy: Dictionary = battle.enemies[0]
	var start: Vector2 = enemy.node.position
	var initial_momentum: float = start.cross(enemy.velocity)
	var initial_distance: float = start.distance_to(scene.ship.position)
	var minimum_distance := initial_distance
	var reversed := false
	var closest_radius := INF
	var farthest_radius := 0.0
	for i in range(4000):
		var old: Vector2 = enemy.node.position
		var old_velocity: Vector2 = enemy.velocity
		battle.advance(0.25, scene.ship.position)
		if battle.enemies.is_empty():
			break
		check(enemy.node.position.distance_to(old) <= old_velocity.length() * 0.25 + 0.01, "位移连续")
		minimum_distance = minf(minimum_distance, enemy.node.position.distance_to(scene.ship.position))
		reversed = reversed or enemy.node.position.cross(enemy.velocity) * initial_momentum < 0.0
		closest_radius = minf(closest_radius, enemy.node.position.length())
		farthest_radius = maxf(farthest_radius, enemy.node.position.length())
	print("PURSUIT initial=", initial_distance, " nearest=", minimum_distance, " reverse=", reversed, " radii=", closest_radius, "..", farthest_radius)
	check(not battle.enemies.is_empty(), "第七关敌舰追击过程中存活")
	check(reversed, "第七关敌舰实际反向")
	check(minimum_distance < initial_distance * 0.7, "敌舰向玩家明显接近")
	check(closest_radius > float(scene.Config.planet.radius_km) and farthest_radius < scene.gravity_radius, "追击保持安全范围")
	scene.reset()
	enemy = battle.enemies[0]
	var moving_start: float = enemy.node.position.distance_to(scene.ship.position)
	var moving_nearest := moving_start
	for i in range(2400):
		scene._advance_motion(0.25)
		battle.advance(0.25, scene.ship.position)
		if battle.enemies.is_empty():
			break
		moving_nearest = minf(moving_nearest, enemy.node.position.distance_to(scene.ship.position))
	check(not battle.enemies.is_empty() and moving_nearest < moving_start * 0.8, "运动玩家轨道下仍能接近")
	print("PURSUIT_MOVING initial=", moving_start, " nearest=", moving_nearest)
	var paused_position: Vector2 = enemy.node.position
	scene.manually_paused = true
	scene._physics_process(1.0)
	check(enemy.node.position == paused_position, "暂停不推进敌舰")
	scene.manually_paused = false
	battle.dead = true
	battle.advance(1.0, scene.ship.position)
	check(enemy.node.position == paused_position, "玩家死亡后战斗不推进")
	level.queue_free()
	await process_frame
	print("ENEMY_PURSUIT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
