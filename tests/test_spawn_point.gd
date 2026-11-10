extends SceneTree

var checks := 0
var failures := 0
var spawns := 0
var deaths := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var point = load("res://scenes/enemy_carrier_spawn_point.tscn").instantiate()
	root.add_child(point)
	point.spawn_requested.connect(func(): spawns += 1)
	point.exhausted.connect(func(): deaths += 1)
	check(point.remaining_real_s == 5.0 and point.spawned == 0 and not point.dead, "首次等待五现实秒")
	point.advance_spawn_clock(4.9)
	check(spawns == 0, "五秒前不刷新")
	point.advance_spawn_clock(100.0, true)
	check(spawns == 0 and is_equal_approx(point.remaining_real_s, 0.1), "暂停或调轨冻结")
	paused = true
	point.advance_spawn_clock(100.0)
	check(spawns == 0 and is_equal_approx(point.remaining_real_s, 0.1), "场景树暂停冻结")
	paused = false
	point.advance_spawn_clock(0.1)
	check(spawns == 1 and point.spawned == 1 and not point.dead, "五秒刷新首组")
	point.advance_spawn_clock(10.0)
	check(spawns == 3 and deaths == 1 and point.dead and not point.visible, "累计三组后死亡")
	point.advance_spawn_clock(100.0)
	check(spawns == 3 and deaths == 1, "死亡后不重复刷新或发出死亡")
	point.interval_real_s = 2.0
	point.spawn_limit = 2
	point.reset_spawn_point()
	point.advance_spawn_clock(4.5)
	check(spawns == 5 and deaths == 2 and point.dead, "参数可配置且大时间步补齐刷新")
	point.reset_spawn_point()
	check(not point.dead and point.visible and point.spawned == 0 and point.remaining_real_s == 2.0, "重置恢复首次等待")
	point.queue_free()
	await process_frame
	for spawn_first in [false, true]:
		var level = load("res://scenes/level_8.tscn").instantiate()
		root.add_child(level)
		level.sandbox.set_physics_process(false)
		for i in range(level.config.tutorial.size()):
			level._show_page(i)
		level._open_equipment()
		level._start_level()
		var spawn_point = level.get_node("Sandbox/World/CarrierSpawnPoint")
		check(level.required_spawn_points.size() == 1 and spawn_point.is_in_group("enemy_carrier_spawn_point"), "第八关注册刷新点")
		if spawn_first:
			spawn_point.advance_spawn_clock(15.0)
			await process_frame
			check(not level.completed, "刷新点先死亡但敌舰仍在时不通关")
		for i in range(3):
			level.combat.damage_target(level.combat.enemies[0].node, 10000.0)
			await process_frame
		if not spawn_first:
			check(not level.completed, "三舰已击毁但刷新点存活时不通关")
			spawn_point.advance_spawn_clock(10.0)
			await process_frame
			check(not level.completed, "仅刷新两次不通关")
			spawn_point.advance_spawn_clock(5.0)
			await process_frame
		check(level.completed and level.victory_controls.visible, "三舰击毁且刷新点死亡后通关")
		level.queue_free()
		await process_frame
	print("SPAWN_POINT_TEST checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
