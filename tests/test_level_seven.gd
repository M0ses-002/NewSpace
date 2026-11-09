extends SceneTree

const Progress = preload("res://scripts/level_progress.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func new_level() -> Node:
	var level = load("res://scenes/level_7.tscn").instantiate()
	root.add_child(level)
	level.sandbox.set_physics_process(false)
	for i in range(level.config.tutorial.size()):
		level._show_page(i)
	level._start_level()
	return level

func run() -> void:
	check(Progress.LAST_LEVEL == 7, "第七关是最后一关")
	check(Progress.reset_level() and Progress.save_level(6), "保存第六关进度")
	var selection = load("res://scenes/level_select.tscn").instantiate()
	root.add_child(selection)
	check(selection.levels.get_child_count() == 7 and selection.levels.get_child(6).disabled, "第七关未解锁时不可选")
	selection.queue_free()
	await process_frame
	for first in range(2):
		var level = new_level()
		var battle = level.combat
		check(battle.enemies.size() == 2 and battle.satellites.is_empty(), "两艘敌舰注册，无卫星")
		check(battle.enemies.size() == 2 and battle.enemies[0].weapon == "missile" and battle.enemies[1].weapon == "carrier", "两艘敌舰分别装备导弹和舰载机")
		check(level.get_node_or_null("Sandbox/World/AntiAirGuns") == null, "场景无高射炮")
		var enemy1 = battle.enemies[first].node
		var enemy2 = battle.enemies[1 - first].node
		battle.damage_target(enemy1, 10000.0)
		await process_frame
		check(not level.completed and battle.enemies.size() == 1, "击毁一艘敌舰不通关")
		battle.damage_target(enemy2, 10000.0)
		await process_frame
		check(level.completed and level.victory_controls.visible and not level.victory_next.visible and not paused, "两艘敌舰被击毁后通关且不暂停")
		check(Progress.load_level() == 7, "第七关通关保存进度")
		level.queue_free()
		await process_frame
	var crash = new_level()
	var lost = crash.combat.enemies[0].node
	crash.combat.enemies.remove_at(0)
	crash.combat.enemy_lost.emit(lost)
	crash.combat.damage_target(crash.combat.enemies[0].node, 10000.0)
	await process_frame
	check(crash.completed and paused and crash.start_button.text == "重试关卡", "敌舰坠毁即失败，另一艘被击毁不应通关")
	paused = false
	crash.queue_free()
	await process_frame
	var reverse_crash = new_level()
	var destroyed = reverse_crash.combat.enemies[0].node
	var late_lost = reverse_crash.combat.enemies[1].node
	reverse_crash.combat.enemies.remove_at(1)
	reverse_crash.combat.damage_target(destroyed, 10000.0)
	reverse_crash.combat.enemy_lost.emit(late_lost)
	await process_frame
	check(reverse_crash.completed and paused and not reverse_crash.victory_controls.visible, "同帧击毁后坠毁不得通关")
	paused = false
	reverse_crash.queue_free()
	await process_frame
	var missing = new_level()
	missing.all_enemy_targets.pop_back()
	missing.combat.damage_target(missing.combat.enemies[0].node, 10000.0)
	missing.combat.damage_target(missing.combat.enemies[0].node, 10000.0)
	await process_frame
	check(not missing.completed, "敌舰注册不完整时不得通关")
	missing.queue_free()
	await process_frame
	selection = load("res://scenes/level_select.tscn").instantiate()
	root.add_child(selection)
	check(not selection.levels.get_child(6).disabled, "解锁后可选第七关")
	selection.queue_free()
	await process_frame
	print("LEVEL_SEVEN_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
