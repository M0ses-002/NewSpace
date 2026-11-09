extends SceneTree

var checks := 0
var failures := 0
var hits := 0
var damage_total := 0.0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var planet := Node2D.new()
	planet.name = "Planet"
	planet.position = Vector2(30, 60)
	world.add_child(planet)
	var gun = load("res://scenes/anti_air_gun.tscn").instantiate()
	world.add_child(gun)
	gun.planet_path = NodePath("../Planet")
	check(gun.initialize(50.0), "高射炮初始化成功")
	check(gun.global_position.is_equal_approx(planet.global_position + Vector2(0, -50)), "炮固定在指定行星表面")
	var enemy := Node2D.new()
	world.add_child(enemy)
	enemy.global_position = gun.global_position + Vector2(40, 0)
	var enemy_target := {"node": enemy, "team": "enemy", "radius_km": 2.0}
	gun.advance(1.0, [enemy_target])
	check(gun.bullets.is_empty(), "敌方飞船不会触发")
	var player := Node2D.new()
	world.add_child(player)
	player.global_position = gun.global_position + Vector2(200, 0)
	var player_target := {"node": player, "team": "player", "radius_km": 2.0}
	gun.advance(1.0, [player_target])
	check(gun.bullets.is_empty(), "范围外玩家不会触发")
	player.global_position = gun.global_position + Vector2(40, 0)
	gun.projectile_hit.connect(func(_target: Node2D, amount: float) -> void:
		hits += 1
		damage_total += amount)
	gun.advance(0.75, [player_target])
	check(gun.bullets.size() >= 3, "玩家进入范围触发连续射击")
	gun.advance(1.0, [player_target])
	check(hits > 0 and damage_total == hits * float(gun.config.bullet_damage), "弹丸命中玩家并产生低伤害")
	gun.reset_gun()
	player.global_position = gun.global_position + Vector2(40, 20)
	var crossing := {"node": player, "team": "player", "radius_km": 1.0, "previous_position": gun.global_position + Vector2(40, -20)}
	var bullet: Node2D = load("res://scenes/anti_air_bullet.tscn").instantiate()
	gun.get_node("Bullets").add_child(bullet)
	bullet.global_position = gun.global_position + Vector2(40, 0)
	gun.bullets.append({"node": bullet, "velocity": Vector2.ZERO, "life": 1.0})
	gun.cooldown = 10.0
	var before := hits
	gun.advance(0.5, [crossing])
	check(hits == before + 1, "目标跨越子弹时相对扫掠命中")
	gun.reset_gun()
	player.global_position = gun.global_position + Vector2(40, 0)
	player.visible = false
	gun.advance(1.0, [player_target])
	check(gun.bullets.is_empty(), "已隐藏目标不触发射击")
	player.visible = true
	var hide_on_hit := func(node: Node2D, _amount: float) -> void: node.visible = false
	gun.projectile_hit.connect(hide_on_hit)
	before = hits
	gun.advance(2.0, [player_target])
	check(hits == before + 1, "单次推进中已击毁目标不再被子弹命中")
	gun.projectile_hit.disconnect(hide_on_hit)
	player.visible = true
	gun.damage(30.0)
	check(gun.active and gun.health == float(gun.config.health) - 30.0, "炮可受伤")
	gun.damage(10000.0)
	check(not gun.active and not gun.get_node("Body").visible, "炮血量耗尽后失效")
	gun.reset_gun()
	check(gun.active and gun.health == float(gun.config.health) and gun.bullets.is_empty() and gun.get_node("Body").visible, "重置恢复血量并清除子弹")
	gun.advance(0.0, [player_target])
	check(gun.bullets.is_empty(), "零模拟时间不推进")
	world.queue_free()
	await process_frame
	print("ANTI_AIR_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
