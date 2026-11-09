extends SceneTree

const Progress = preload("res://scripts/level_progress.gd")
const Hard = preload("res://scripts/hard_mode.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func make_level() -> Node:
	var level = load("res://scenes/level_8.tscn").instantiate()
	root.add_child(level)
	level.sandbox.set_physics_process(false)
	for i in range(level.config.tutorial.size()):
		level._show_page(i)
	level._start_level()
	return level

func run() -> void:
	check(Progress.LAST_LEVEL == 8, "第八关为最后一关")
	check(Progress.reset_level() and Progress.save_level(7), "解锁第七关")
	var selector = load("res://scenes/level_select.tscn").instantiate()
	root.add_child(selector)
	check(selector.levels.get_child_count() == 8 and selector.levels.get_child(7).disabled, "第八关未解锁时不可选")
	selector.queue_free()
	await process_frame
	var previous = load("res://scenes/level_7.tscn").instantiate()
	root.add_child(previous)
	for i in range(previous.config.tutorial.size()):
		previous._show_page(i)
	previous._start_level()
	previous._win()
	check(previous.victory_next.visible and Progress.load_level() == 8, "第七关通关显示下一关并解锁第八关")
	previous.queue_free()
	await process_frame
	selector = load("res://scenes/level_select.tscn").instantiate()
	root.add_child(selector)
	check(not selector.levels.get_child(7).disabled, "第八关已解锁")
	selector.queue_free()
	await process_frame
	var level = make_level()
	var battle = level.combat
	check(battle.enemies.size() == 3 and level.all_enemy_targets.size() == 3, "注册三艘目标敌舰")
	if battle.enemies.size() == 3:
		check(battle.enemies[0].weapon == "missile" and battle.enemies[1].weapon == "carrier" and battle.enemies[2].weapon == "satellite_deployer", "三艘敌舰装备不同武器")
	check(battle.air_forces.size() == 2, "注册两支地面空军")
	for force in battle.air_forces:
		check(force.valid and force.members.size() == 9, "地面空军航线和编队有效")
	for entry in level.config.tutorial:
		check(load(entry.image) is Texture2D and not str(entry.text).is_empty(), "教程图片和文字有效")
	if battle.enemies.size() == 3:
		battle.damage_target(battle.enemies[0].node, 10000.0)
		await process_frame
		check(not level.completed, "击毁一艘不通关")
		battle.damage_target(battle.enemies[0].node, 10000.0)
		await process_frame
		check(not level.completed, "击毁两艘不通关")
		battle.damage_target(battle.enemies[0].node, 10000.0)
		await process_frame
		check(level.completed and level.victory_controls.visible and not level.victory_next.visible and not paused, "三舰击毁后通关且末关隐藏下一关")
	level.queue_free()
	await process_frame
	level = make_level()
	if level.combat.enemies.size() == 3:
		level.combat.enemy_lost.emit(level.combat.enemies[0].node)
		await process_frame
		check(level.completed and paused and not level.victory_controls.visible, "敌舰自然坠毁失败")
	paused = false
	level.queue_free()
	await process_frame
	var rule := Hard.get_rule(8)
	check(not rule.is_empty() and rule.get("time_limit_seconds") == null and rule.get("max_slots") == null and rule.get("weapon_limits") == {}, "第八关困难模式规则不限")
	if not rule.is_empty():
		check(Hard.equipment_error(rule, ["missile", "carrier", "carrier", "missile"]) == "", "不限规则允许四个装备")
	check(Hard.set_enabled(true), "开启困难模式")
	level = make_level()
	check(level.hard_started and not level.dialog.visible and not paused, "第八关困难模式可开始")
	level.queue_free()
	await process_frame
	print("LEVEL_EIGHT_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
