extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for number in range(1, 5):
		var level = load("res://scenes/level_%d.tscn" % number).instantiate()
		root.add_child(level)
		await process_frame
		var expected: Array = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [2, 1, 0]][number - 1]
		var battle: Node = level.get_node("Sandbox/World/Combat")
		check(battle.get_node("Satellites").get_child_count() == expected[0] and battle.satellites.size() == expected[0], "关卡 %d 卫星节点及运行状态数量" % number)
		check(battle.get_node("SatelliteCaptureRanges").get_child_count() == expected[0], "关卡 %d 夺控范围数量" % number)
		check(battle.get_node("Enemies").get_child_count() == expected[1] and battle.enemies.size() == expected[1], "关卡 %d 敌机节点及运行状态数量" % number)
		check(battle.get_node("InitialDebris").get_child_count() == expected[2] and battle.debris.size() == expected[2], "关卡 %d 初始碎片节点及运行状态数量" % number)
		check(paused, "关卡 %d 教学期间暂停" % number)
		check(level.dialog.visible, "关卡 %d 教学可见" % number)
		check(level.config.tutorial.size() == [4, 2, 4, 2][number - 1], "关卡 %d 教程页数" % number)
		if level.config.tutorial.size() > 1:
			check(level.start_button.disabled, "关卡 %d 未读完不能开始" % number)
			level._start_level()
			check(paused and level.dialog.visible, "关卡 %d 不能绕过未读页" % number)
		else:
			check(not level.start_button.disabled, "单页教程展示后即可开始")
		for i in range(level.config.tutorial.size()):
			level._show_page(i)
			check(level.page_image.texture != null, "关卡 %d 第 %d 页图片加载" % [number, i + 1])
		check(not level.start_button.disabled, "关卡 %d 全部页面访问后解锁" % number)
		level._show_page(0)
		check(not level.start_button.disabled, "关卡 %d 返回上一页不丢失阅读状态" % number)
		if number == 1:
			level.sandbox.set_physics_process(false)
			level._start_level()
			var radius: float = float(level.sandbox.Config.planet.radius_km) + float(level.config.victory.altitude_km)
			level.sandbox.ship.position = Vector2(radius - 0.1, 0)
			level._physics_process(0.0)
			check(not level.completed, "不足高度阈值不通关")
			level.sandbox.ship.position = Vector2(radius, 0)
			level._physics_process(0.0)
			check(not level.completed, "恰好等于高度阈值不通关")
			level.sandbox.ship.position = Vector2(radius + 1.0, 0)
			level.sandbox.speed_dragging = true
			level._physics_process(0.0)
			check(not level.completed, "编辑预览不通关")
			level.sandbox.speed_dragging = false
			level.sandbox.manually_paused = true
			level._physics_process(0.0)
			check(not level.completed, "手动暂停不通关")
			level.sandbox.manually_paused = false
			paused = true
			level._physics_process(0.0)
			check(not level.completed, "场景树暂停不通关")
			paused = false
			level.dialog.visible = true
			level._physics_process(0.0)
			check(not level.completed, "对话期间不通关")
			level.dialog.visible = false
			level.sandbox.orbit = {"a": 290.0, "e": 0.2, "angle": 0.0}
			level.sandbox.motion_mode = "ORBIT"
			level._physics_process(0.0)
			check(level.completed and level.victory_controls.visible and level.victory_next.visible and not level.dialog.visible, "椭圆轨道超过高度通关")
		if number == 3:
			level._start_level()
			level._enemy_lost(level.combat.enemies[0].node)
			await process_frame
			check(level.completed and paused and level.start_button.text == "重试关卡", "第三关敌机坠毁显示失败与重试")
		if number == 2:
			level._start_level()
			var audio: Node = root.get_node("AudioManager")
			audio._complete_player.stop()
			level._win()
			check(audio._complete_player.playing, "通关时播放完成音效")
			audio._complete_player.stop()
			level._win()
			check(not audio._complete_player.playing, "重复通关调用不重复播放")
			check(not paused and not level.dialog.visible and level.victory_controls.visible and level.victory_next.visible, "通关不暂停但显示顶部操作")
			check(level.victory_next.custom_minimum_size == Vector2(150, 40) and level.victory_menu.custom_minimum_size == Vector2(170, 40), "通关按钮放大")
			level._process(0.0)
			check(level.victory_next.modulate == level.victory_menu.modulate and level.victory_next.modulate.b < 1.0, "通关按钮同步高亮")
			check(not level.victory_next.disabled and not level.victory_menu.disabled, "高亮不影响按钮点击")
		if number == 4:
			level._start_level()
			level._enemy_lost(level.combat.enemies[0].node)
			await process_frame
			check(not level.completed and not paused, "第四关敌机坠毁不阻止卫星胜利")
			level.sandbox.motion_mode = "COLLISION"
			level._physics_process(0.0)
			check(level.completed and paused and level.start_button.text == "重试关卡", "行星碰撞显示失败与重试")
		paused = false
		level.queue_free()
		await process_frame
	var last = load("res://scenes/level_4.tscn").instantiate()
	root.add_child(last)
	await process_frame
	for i in range(last.config.tutorial.size()):
		last._show_page(i)
	last._start_level()
	last._win()
	check(not paused and last.victory_controls.visible and last.victory_next.visible and not last.dialog.visible, "第四关已非最后一关：通关不暂停且出现下一关按钮")
	paused = false
	last.queue_free()
	await process_frame
	for mode in ["FREE", "COLLISION"]:
		var level = load("res://scenes/level_1.tscn").instantiate()
		root.add_child(level)
		await process_frame
		level.sandbox.set_physics_process(false)
		for i in range(level.config.tutorial.size()):
			level._show_page(i)
		level._start_level()
		level.sandbox.motion_mode = mode
		level.sandbox.orbit_acquired = false
		level.sandbox.ship.position = Vector2(float(level.sandbox.Config.planet.radius_km) + float(level.config.victory.altitude_km) + 1.0, 0)
		level._physics_process(0.0)
		if mode == "FREE":
			check(level.completed and level.victory_controls.visible and level.victory_next.visible and not level.dialog.visible, "自由飞行超过高度通关")
		else:
			check(level.completed and level.start_button.text == "重试关卡", "碰撞失败优先于高度通关")
		paused = false
		level.queue_free()
		await process_frame
	var final_level = load("res://scenes/level_8.tscn").instantiate()
	root.add_child(final_level)
	await process_frame
	for i in range(final_level.config.tutorial.size()):
		final_level._show_page(i)
	final_level._start_level()
	var complete_player: AudioStreamPlayer = root.get_node("AudioManager")._complete_player
	complete_player.stop()
	final_level._win()
	check(complete_player.playing and not final_level.victory_next.visible and final_level.victory_menu.visible, "最后一关也播放完成音并保留菜单按钮")
	final_level.queue_free()
	await process_frame
	var retry_level = load("res://scenes/level_5.tscn").instantiate()
	root.add_child(retry_level)
	await process_frame
	for i in range(retry_level.config.tutorial.size()):
		retry_level._show_page(i)
	retry_level._start_level()
	complete_player.stop()
	retry_level._win()
	check(complete_player.playing, "重进关卡后可再次播放完成音")
	retry_level.queue_free()
	await process_frame
	print("LEVEL_TUTORIAL_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
