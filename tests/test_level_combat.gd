extends SceneTree

var scene: Node
var battle: Node
var failures := 0
var checks := 0
var destroyed: Array[Node2D] = []
var lost: Array[Node2D] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child.call_deferred(scene)
	run.call_deferred()

func test_defense(owner: String, team: String, enabled: bool, expected: bool) -> void:
	scene.reset()
	battle.enemy_fire_enabled = false
	battle.satellite_defense_enabled = enabled
	var satellite: Dictionary = battle.satellites[0]
	battle.satellites.clear()
	battle.satellites.append(satellite)
	satellite.owner = owner
	satellite.config.angular_speed_rad_s = 0.0
	satellite.config.capture_radius_km = 50.0
	battle.capture_initialized = true
	battle.config.missile.speed_km_s = 300.0
	var enemy: Dictionary = battle.enemies[0]
	enemy.node.position = Vector2(500, 40)
	enemy.velocity = Vector2.ZERO
	scene.ship.position = Vector2(500, 40)
	var target: Node2D = scene.ship if team == "enemy" else enemy.node
	var debris_count: int = battle.debris.size()
	check(battle._launch(Vector2(40, 40), target, team), "测试导弹成功发射")
	battle.advance(1.0, scene.ship.position)
	check(battle.missiles.is_empty() == expected, "防御判定 owner=%s team=%s enabled=%s" % [owner, team, enabled])
	check(battle.debris.size() == debris_count, "范围拦截和非碰撞不产生碎片")

func run() -> void:
	scene.set_physics_process(false)
	battle = scene.combat
	check(battle.enemy_fire_enabled and not battle.satellite_defense_enabled, "默认保持原有行为")
	test_defense("player", "enemy", true, true)
	test_defense("enemy", "player", true, true)
	test_defense("player", "player", true, false)
	test_defense("enemy", "enemy", true, false)
	test_defense("neutral", "player", true, false)
	test_defense("neutral", "enemy", true, false)
	test_defense("player", "enemy", false, false)
	scene.reset()
	battle.enemy_fire_enabled = false
	battle.satellite_defense_enabled = true
	var moving: Dictionary = battle.satellites[0]
	battle.satellites.clear()
	battle.satellites.append(moving)
	battle.enemies.clear()
	moving.owner = "player"
	moving.config.capture_radius_km = 20.0
	moving.config.angular_speed_rad_s = PI / 2.0
	battle.capture_initialized = true
	scene.ship.position = Vector2(75, 130)
	battle.config.missile.speed_km_s = 0.0
	battle._launch(scene.ship.position, scene.ship, "enemy")
	battle.missiles[0].life = 0.25
	battle.advance(1.0, scene.ship.position)
	check(battle.player_health < battle.config.player.health, "卫星扫掠截止导弹有效期而非完整步长")
	scene.reset()
	battle.enemy_fire_enabled = false
	battle.satellite_defense_enabled = false
	var enemy: Dictionary = battle.enemies[0]
	scene.ship.position = Vector2(300, 0)
	enemy.node.position = Vector2(310, 0)
	enemy.velocity = Vector2.ZERO
	enemy.locked = true
	enemy.cooldown = 0.0
	battle.advance(0.01, scene.ship.position)
	check(battle.missiles.is_empty() and enemy.locked and enemy.cooldown == 0.0, "禁火保留锁定并阻止发射")
	battle.enemy_fire_enabled = true
	battle.advance(0.01, scene.ship.position)
	check(battle.missiles.size() == 1, "重新启用后敌机发射")
	scene.reset()
	battle.enemy_destroyed.connect(func(node: Node2D): destroyed.append(node))
	battle.enemy_lost.connect(func(node: Node2D): lost.append(node))
	enemy = battle.enemies[0]
	var satellite: Node2D = battle.satellites[0].node
	battle.damage_target(satellite, 1000.0)
	battle.damage_target(enemy.node, 1.0)
	check(destroyed.is_empty(), "卫星销毁和敌机未致死不发击毁信号")
	battle.damage_target(enemy.node, 1000.0)
	battle.damage_target(enemy.node, 1000.0)
	check(destroyed.size() == 1 and destroyed[0] == enemy.node and lost.is_empty(), "敌机致死仅发送击毁信号")
	scene.reset()
	enemy = battle.enemies[0]
	enemy.node.position = Vector2(1, 0)
	enemy.velocity = Vector2.ZERO
	battle.advance(0.01, scene.ship.position)
	check(battle.enemies.is_empty() and destroyed.size() == 1 and lost.size() == 1 and lost[0] == enemy.node, "敌机坠毁仅发送一次坠毁信号")
	battle.advance(0.01, scene.ship.position)
	check(lost.size() == 1, "已移除敌机不重复发送坠毁信号")
	scene.reset()
	var lock_enemy: Dictionary = battle.enemies[0]
	var edges: Control = battle.hud.get_node("LockEdges")
	var warning: Label = battle.hud.get_node("LockWarning")
	battle.selected = lock_enemy.node
	lock_enemy.locked = false
	battle._update_lock_warning()
	check(not edges.visible and not warning.visible, "我方锁定不触发被锁定警告")
	lock_enemy.locked = true
	battle._update_lock_warning()
	check(edges.visible and warning.visible and warning.text == "被锁定", "敌方锁定显示四边与警告")
	check(edges.mouse_filter == Control.MOUSE_FILTER_IGNORE and warning.mouse_filter == Control.MOUSE_FILTER_IGNORE, "警告不拦截点击")
	var other := {"locked": true}
	battle.enemies.append(other)
	lock_enemy.locked = false
	battle._update_lock_warning()
	check(edges.visible, "多敌机任一锁定显示")
	battle.enemies.erase(other)
	battle._update_lock_warning()
	check(not edges.visible and not warning.visible, "全部失锁立即隐藏")
	lock_enemy.locked = true
	scene.manually_paused = true
	battle._update_lock_warning()
	check(not edges.visible, "手动暂停隐藏警告")
	scene.manually_paused = false
	scene.speed_dragging = true
	battle._update_lock_warning()
	check(not edges.visible, "轨道编辑隐藏警告")
	scene.speed_dragging = false
	paused = true
	battle._process(0.0)
	check(not edges.visible, "场景暂停仍处理并隐藏警告")
	paused = false
	battle.damage_player(1000.0)
	battle._update_lock_warning()
	check(not edges.visible and not warning.visible, "玩家死亡隐藏警告")
	print("LEVEL_COMBAT_TESTS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
