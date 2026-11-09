extends SceneTree

const Loadout = preload("res://scripts/loadout.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(Loadout.save_slots(["satellite_deployer", "satellite_deployer", "", ""]), "装备两个布置器")
	var eighth = load("res://scenes/level_8.tscn").instantiate()
	root.add_child(eighth)
	eighth.sandbox.set_physics_process(false)
	for i in range(eighth.config.tutorial.size()):
		eighth._show_page(i)
	eighth._start_level()
	var deployer: Dictionary = eighth.combat.enemies.filter(func(e): return e.weapon == "satellite_deployer")[0]
	check(is_equal_approx(float(deployer.get("deployer_cooldown", 0.0)), 15.0), "敌方布置器首次冷却为十五现实秒")
	eighth.sandbox.manually_paused = true
	eighth.combat.advance_cooldowns(10.0)
	check(is_equal_approx(float(deployer.deployer_cooldown), 15.0), "首次冷却在暂停期间冻结")
	eighth.sandbox.manually_paused = false
	eighth.combat.advance(0.01, eighth.sandbox.ship.position)
	check(eighth.combat.decoy_satellites.is_empty(), "开始后首次部署不立即触发")
	eighth.combat.advance_cooldowns(14.9)
	eighth.combat.advance(0.01, eighth.sandbox.ship.position)
	check(eighth.combat.decoy_satellites.is_empty(), "十五秒前不部署")
	eighth.combat.advance_cooldowns(0.1)
	eighth.combat.advance(0.01, eighth.sandbox.ship.position)
	check(eighth.combat.decoy_satellites.size() == 1, "首次十五秒后部署")
	eighth.combat.reset_battle()
	deployer = eighth.combat.enemies.filter(func(e): return e.weapon == "satellite_deployer")[0]
	check(is_equal_approx(float(deployer.deployer_cooldown), 15.0) and eighth.combat.decoy_satellites.is_empty(), "重置恢复敌方首次十五秒冷却")
	eighth.queue_free()
	await process_frame
	var level = load("res://scenes/level_7.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	level.sandbox.set_physics_process(false)
	for i in range(level.config.tutorial.size()):
		level._show_page(i)
	level._start_level()
	var battle = level.combat
	battle.fire_slot(0)
	check(battle.player_deployer_used and battle.decoy_satellites.size() == 1, "首次部署")
	battle.fire_slot(1)
	check(battle.decoy_satellites.size() == 1, "多个槽位共享每关一次")
	battle._update_hud()
	check(battle.hud.get_node("Weapons/Slot2/Fire").disabled, "另一个槽位禁用")
	var enemy: Dictionary = battle.enemies[0]
	enemy.weapon = "satellite_deployer"
	check(battle._deploy_decoy(enemy.node, enemy.velocity, 0, "enemy"), "敌舰部署")
	check(battle.decoy_satellites.back().team == "enemy", "敌方阵营")
	enemy.deployer_cooldown = 15.0
	level.sandbox.manually_paused = true
	battle.advance_cooldowns(5.0)
	check(enemy.deployer_cooldown == 15.0, "暂停冻结敌舰冷却")
	level.sandbox.manually_paused = false
	battle.advance_cooldowns(5.0)
	check(enemy.deployer_cooldown == 10.0, "运行时敌舰冷却递减")
	enemy.deployer_cooldown = 0.0
	battle.enemy_fire_enabled = true
	var before_deploy: int = battle.decoy_satellites.size()
	battle.advance(0.01, level.sandbox.ship.position)
	check(battle.decoy_satellites.size() == before_deploy + 1 and enemy.deployer_cooldown == 15.0, "敌舰自动部署并启动十五现实秒冷却")
	battle.advance_cooldowns(15.0)
	battle.advance(0.01, level.sandbox.ship.position)
	check(battle.decoy_satellites.size() == before_deploy + 2, "敌舰冷却完成后重复部署")
	var strike = battle.CarrierSquadron.instantiate()
	battle.add_child(strike)
	var strike_origin: Vector2 = level.sandbox.ship.global_position + Vector2(0, 400)
	var saved_enemy_position: Vector2 = enemy.node.position
	enemy.node.global_position = strike_origin
	var strike_settings: Dictionary = battle.config.carrier.duplicate()
	strike_settings.spacing_km = 0.0
	strike.launch(strike_origin, strike_origin + Vector2(100, 0), 1.0, strike_settings, "player", level.sandbox.ship)
	for i in range(1, strike.members.size()):
		strike.members[i].alive = false
	battle.carrier_squadrons.append(strike)
	var strike_decoy = battle.decoy_satellites[1]
	strike_decoy.global_position = strike_origin
	strike_decoy.attraction_radius = 5.0
	strike_decoy.collision_radius = 5.0
	var health_before: float = enemy.health
	battle._advance_carrier_squadrons(1.0, {}, {strike_decoy.get_instance_id(): strike_origin + Vector2(30, 0)})
	check(not strike.members[0].alive and strike.members[0].has("decoy_step"), "飞机在轨道命中后被诱饵撞毁")
	check(is_equal_approx(float(enemy.health), health_before - float(battle.config.carrier.damage)), "飞机撞毁前的轨道扫掠对敌舰造成伤害")
	enemy.node.position = saved_enemy_position
	strike_decoy.attraction_radius = 90.0
	var early_friendly = battle.CarrierSquadron.instantiate()
	var early_hostile = battle.CarrierSquadron.instantiate()
	battle.add_child(early_friendly)
	battle.add_child(early_hostile)
	var encounter_origin: Vector2 = level.sandbox.ship.global_position + Vector2(0, 400)
	var encounter_center: Vector2 = encounter_origin + Vector2(100, 0)
	var encounter_settings: Dictionary = battle.config.carrier.duplicate()
	encounter_settings.spacing_km = 0.0
	early_friendly.launch(encounter_origin, encounter_center, 1.0, encounter_settings, "player", level.sandbox.ship)
	early_hostile.launch(encounter_origin, encounter_center, 1.0, encounter_settings, "enemy", enemy.node)
	battle.carrier_squadrons.append_array([early_friendly, early_hostile])
	var moving_decoy = battle.decoy_satellites[1]
	moving_decoy.global_position = encounter_origin
	moving_decoy.attraction_radius = 5.0
	moving_decoy.collision_radius = 3.0
	battle._advance_carrier_squadrons(1.0, {}, {moving_decoy.get_instance_id(): encounter_origin + Vector2(30, 0)})
	check(early_friendly.dogfight != null and early_hostile.dogfight != null, "诱饵入圈前的遭遇先触发狗斗")
	check(early_friendly.members.all(func(m): return m.alive and not is_instance_valid(m.get("decoy")) and m.node.visible), "狗斗先发生时撤销后续诱饵碰撞")
	battle._clear_squadron(early_friendly)
	battle._clear_squadron(early_hostile)
	moving_decoy.attraction_radius = 90.0
	var mixed_player = battle.CarrierSquadron.instantiate()
	var mixed_enemy = battle.CarrierSquadron.instantiate()
	battle.add_child(mixed_player)
	battle.add_child(mixed_enemy)
	var mixed_center: Vector2 = encounter_origin + Vector2(100, 0)
	var enemy_origin: Vector2 = mixed_center + (encounter_origin - mixed_center).rotated(0.16)
	mixed_player.launch(encounter_origin, mixed_center, 1.0, encounter_settings, "player", level.sandbox.ship)
	mixed_enemy.launch(enemy_origin, mixed_center, -1.0, encounter_settings, "enemy", enemy.node)
	for i in range(2, 9):
		mixed_player.members[i].alive = false
		mixed_enemy.members[i].alive = false
	mixed_player.members[0].offset = Vector2(0, 50)
	mixed_player._update_member(mixed_player.members[0], encounter_origin, mixed_player._orbit_state(0.0).heading)
	mixed_player.members[0].previous = mixed_player.members[0].current
	var lure_start: Vector2 = mixed_player.members[0].current + Vector2(3, 0)
	moving_decoy.global_position = mixed_player.members[0].current + Vector2(0, 2)
	moving_decoy.attraction_radius = 4.0
	moving_decoy.collision_radius = 0.1
	battle.carrier_squadrons.append_array([mixed_player, mixed_enemy])
	battle._advance_carrier_squadrons(1.0, {}, {moving_decoy.get_instance_id(): lure_start})
	var diverted: Dictionary = mixed_player.members[0]
	check(mixed_player.dogfight != null and diverted.has("decoy_collision_time") and diverted.decoy_step < mixed_player.orbit_end_time and mixed_player.orbit_end_time < diverted.decoy_collision_time, "受诱后遭遇狗斗先于预测撞毁")
	check(diverted.alive and diverted.node.visible and diverted.get("decoy") == moving_decoy and diverted.current.distance_to(diverted.decoy_motion.start) > 0.0001, "狗斗回滚保留受诱飞机及追逐位置")
	var diverted_position: Vector2 = diverted.current
	battle._advance_dogfights(0.01)
	check(diverted.node.global_position == diverted_position, "先受诱飞机不参与狗斗绘制")
	battle._clear_squadron(mixed_player)
	battle._clear_squadron(mixed_enemy)
	moving_decoy.attraction_radius = 90.0
	var friendly = battle.CarrierSquadron.instantiate()
	var hostile = battle.CarrierSquadron.instantiate()
	battle.add_child(friendly)
	battle.add_child(hostile)
	var origin: Vector2 = level.sandbox.ship.global_position
	var center: Vector2 = origin + Vector2(100.0, 0.0)
	friendly.launch(origin, center, 1.0, battle.config.carrier, "player", level.sandbox.ship)
	hostile.launch(origin, center, 1.0, battle.config.carrier, "enemy", enemy.node)
	battle.carrier_squadrons.append_array([friendly, hostile])
	var player_decoy = battle.decoy_satellites[0]
	var enemy_decoy = battle.decoy_satellites[1]
	player_decoy.global_position = origin
	enemy_decoy.global_position = origin + Vector2(10.0, 0.0)
	battle._advance_carrier_squadrons(0.01, {})
	check(friendly.members.any(func(m): return m.alive and m.get("decoy") == enemy_decoy), "玩家飞机仅被敌方卫星吸引")
	check(hostile.members.any(func(m): return m.alive and m.get("decoy") == player_decoy) or hostile.members.all(func(m): return not m.alive), "敌方飞机仅被玩家卫星吸引")
	check(battle.dogfights.is_empty(), "被吸引飞机不触发狗斗")
	var paused_member: Dictionary = friendly.members.filter(func(m): return m.alive)[0]
	var paused_position: Vector2 = paused_member.current
	level.sandbox.manually_paused = true
	battle.advance(1.0, level.sandbox.ship.position)
	check(paused_member.current == paused_position, "暂停时诱饵追逐冻结")
	level.sandbox.manually_paused = false
	var attracted: Dictionary = friendly.members.filter(func(m): return m.alive and m != friendly.members[0])[0]
	var attracted_position: Vector2 = attracted.current
	var free_friendly: Dictionary = friendly.members[0]
	var free_hostile: Dictionary = hostile.members[0]
	free_friendly.alive = true
	free_friendly.decoy = null
	free_hostile.alive = true
	free_hostile.decoy = null
	battle._start_dogfight(friendly, hostile, origin)
	battle._advance_dogfights(0.01)
	check(attracted.node.global_position == attracted_position, "狗斗绘制不覆盖被吸引飞机")
	free_friendly.decoy = enemy_decoy
	battle._advance_dogfights(0.01)
	check(battle.dogfights.is_empty(), "一方没有可参战飞机时结束狗斗")
	battle._advance_carrier_squadrons(1000.0, {})
	check(is_instance_valid(enemy_decoy) and battle.decoy_satellites.has(enemy_decoy), "碰撞后诱饵卫星保留")
	check(friendly.members.all(func(m): return not m.alive), "多架飞机撞向卫星后消失")
	battle.reset_battle()
	battle.setup(level.sandbox)
	check(not battle.player_deployer_used and battle.decoy_satellites.is_empty(), "重置恢复使用次数并移除卫星")
	battle.fire_slot(0)
	check(battle.player_deployer_used, "重置后重新使用布置器")
	level._fail("测试失败")
	check(paused and level.completed, "失败流程暂停关卡")
	level._retry_level()
	await process_frame
	await process_frame
	var retried = current_scene
	check(is_instance_valid(retried) and retried != level and not retried.combat.player_deployer_used and retried.combat.decoy_satellites.is_empty(), "失败重试重新创建关卡并恢复次数")
	for i in range(retried.config.tutorial.size()):
		retried._show_page(i)
	retried._start_level()
	retried.combat.fire_slot(1)
	check(retried.combat.player_deployer_used and retried.combat.decoy_satellites.size() == 1, "重试后的关卡可再次部署")
	retried.queue_free()
	await process_frame
	print("DEPLOYER_COMBAT_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
