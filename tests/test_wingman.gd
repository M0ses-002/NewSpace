extends SceneTree
const Loadout = preload("res://scripts/loadout.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", text)
func run() -> void:
	Loadout.save_slots(["wingman", "wingman", "", ""])
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	await process_frame
	var battle: Node = scene.get_node("World/Combat")
	battle.fire_slot(0)
	battle.fire_slot(1)
	check(battle.weapon_slots[0].active and battle.weapon_slots[1].active, "双槽独立启动")
	var first = battle.weapon_slots[0]
	var second = battle.weapon_slots[1]
	check(first.wingman != second.wingman and first.wingman.global_position.distance_to(scene.ship.global_position) > 19.9, "僚机独立围绕飞船")
	check(first.wingman.polygon == scene.ship.get_node("Hull").polygon, "僚机视觉尺寸与玩家船体相同")
	check(float(battle.config.wingman.radius_km) == 2.0, "僚机碰撞半径不随视觉尺寸改变")
	battle.begin_wingman_frame(1.0, 10.0)
	battle.advance(10.0, scene.ship.position)
	check(absf(first.remaining - 4.0) < 0.001, "持续时间使用现实秒")
	var previous: Vector2 = first.wingman.global_position
	scene.manually_paused = true
	battle.begin_wingman_frame(1.0, 10.0)
	battle.advance(10.0, scene.ship.position)
	check(first.wingman.global_position == previous and absf(first.remaining - 4.0) < 0.001, "暂停冻结")
	scene.manually_paused = false
	battle.begin_wingman_frame(5.0, 50.0)
	battle.advance(50.0, scene.ship.position)
	check(not first.active and first.cooldown == 15.0 and not second.active, "到期独立进入冷却")
	scene.reset()
	check(not battle.weapon_slots[0].active and battle.weapon_slots[0].cooldown == 0.0, "重置恢复")
	battle.fire_slot(0)
	var wing = battle.weapon_slots[0]
	var wing_pos: Vector2 = wing.wingman.global_position
	var enemy_scene = load("res://scenes/carrier_squadron.tscn").instantiate()
	battle.add_child(enemy_scene)
	var center: Vector2 = scene.focus_center()
	enemy_scene.launch(scene.ship.global_position, center, 1.0, battle.config.carrier, "enemy", battle.enemies[0].node, Vector2.ZERO, scene.focus_mu())
	battle.carrier_squadrons.append(enemy_scene)
	var member: Dictionary = enemy_scene.members[0]
	member.previous = wing_pos
	member.current = wing_pos
	var wing_sweeps: Array[Dictionary] = [{"start": wing_pos, "end": wing_pos, "fraction": 1.0, "slot": wing}]
	battle._advance_carrier_squadrons(0.00001, {}, {}, wing_sweeps)
	check(not member.alive and wing.active, "敌方舰载机碰撞后僚机存活")
	check(not scene.combat.dead, "僚机击毁飞机不会导致已拦截飞机撞击玩家")
	battle._launch(wing_pos, scene.ship, "enemy")
	var missile: Dictionary = battle.missiles.back()
	missile.node.position = wing_pos
	battle.begin_wingman_frame(0.001, 0.001)
	battle.advance(0.001, scene.ship.position)
	check(not wing.active and not battle.missiles.has(missile), "敌导弹碰撞消耗自身并摧毁僚机")
	scene.queue_free()
	await process_frame
	print("WINGMAN_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
