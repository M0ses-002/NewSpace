extends SceneTree

const Progress = preload("res://scripts/level_progress.gd")

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()

func function_body(source: String, signature: String) -> String:
	var start := source.find(signature)
	if start < 0:
		return ""
	var next := source.find("\nfunc ", start + 1)
	if next < 0:
		return source.substr(start)
	return source.substr(start, next - start)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var parsed = JSON.parse_string(read_text("res://data/level_5.json"))
	check(parsed is Dictionary, "level_5.json 可解析")
	if parsed is Dictionary:
		var config: Dictionary = parsed
		check(int(config.get("level", 0)) == 5, "level_5.json 的 level 为 5")
		check(str(config.get("title", "")) != "" and str(config.get("objective", "")) != "", "标题与目标非空")
		var victory: Dictionary = config.get("victory", {})
		check(str(victory.get("type", "")) == "orbit_body", "胜利类型为 orbit_body")
		check(int(victory.get("body_index", 0)) == 1, "胜利目标为第二颗行星（body_index=1）")
		var entities: Dictionary = config.get("entities", {})
		for key in ["Satellites", "Enemies", "InitialDebris"]:
			check(int(entities.get(key, -1)) == 0, "entities.%s 为 0" % key)
		check(not bool(config.get("enemy_fire_enabled", true)), "第五关关闭敌机开火")
		check(not bool(config.get("satellite_defense_enabled", true)), "第五关关闭卫星防御")
		var tutorial: Array = config.get("tutorial", [])
		check(tutorial.size() == 3, "教程共三页")
		for entry in tutorial:
			var image := str(entry.get("image", ""))
			check(str(entry.get("text", "")).length() > 0, "教程文字非空")
			var texture = load(image)
			check(texture is Texture2D, "教程图片可加载：" + image)
	check(Progress.LAST_LEVEL == 8, "LAST_LEVEL 为 8")
	check(Progress.scene_path(5) == "res://scenes/level_5.tscn", "第五关场景路径正确")
	for number in range(1, Progress.LAST_LEVEL + 1):
		check(FileAccess.file_exists(Progress.scene_path(number)), "第 %d 关场景存在" % number)
	var controller := read_text("res://scripts/level_controller.gd")
	var win_body := function_body(controller, "func _win()")
	check(win_body != "", "找到 _win 实现")
	check(not win_body.contains("paused"), "_win 内不再暂停场景树")
	check(win_body.contains("completed = true"), "_win 仍设置 completed 防止重复触发")
	check(win_body.contains("victory_controls.visible = true"), "_win 仍显示顶部操作")
	var fail_body := function_body(controller, "func _fail(")
	check(fail_body.contains("paused = true"), "_fail 仍保留暂停")
	check(controller.contains("elif victory.type == \"orbit_body\""), "存在 orbit_body 胜利分支")
	check(controller.contains("sandbox.focus_index == int(victory.get(\"body_index\", 1))"), "orbit_body 按 body_index 判定")
	var scene_text := read_text("res://scenes/level_5.tscn")
	check(scene_text.contains("res://data/level_5.json"), "第五关场景挂接配置")
	check(scene_text.contains("initial_zoom = 0.55"), "第五关初始缩放为 0.55")
	check(scene_text.contains("[node name=\"PlanetB\" parent=\"Sandbox/World\" instance=ExtResource(\"3\")]"), "第二颗行星挂在 Sandbox/World 下")
	check(scene_text.contains("position = Vector2(860, 0)"), "第二颗行星位于 (860, 0)")
	check(scene_text.contains("body_index = 1"), "第二颗行星 body_index 为 1")
	var level5 = load("res://scenes/level_5.tscn").instantiate()
	root.add_child(level5)
	await process_frame
	for i in range(level5.config.tutorial.size()):
		level5._show_page(i)
	level5._start_level()
	level5._win()
	check(level5.completed, "第五关 _win 设置 completed")
	check(level5.victory_next.visible, "第五关显示下一关按钮")
	check(level5.victory_controls.visible, "第五关显示顶部操作")
	check(not level5.dialog.visible, "通关后不显示教学对话")
	check(not root.get_tree().paused, "胜利后场景树不暂停")
	check(Progress.load_level() == 6, "第五关通关解锁第六关")
	paused = false
	level5.queue_free()
	await process_frame
	var replay = load("res://scenes/level_1.tscn").instantiate()
	root.add_child(replay)
	await process_frame
	for i in range(replay.config.tutorial.size()):
		replay._show_page(i)
	replay._start_level()
	replay._win()
	check(Progress.load_level() == 6, "已解锁第六关后重玩第一关不会回退进度")
	paused = false
	replay.queue_free()
	await process_frame
	# 验证第六关空军与敌机胜利流程。
	var last_level = load("res://scenes/level_6.tscn").instantiate()
	root.add_child(last_level)
	await process_frame
	for i in range(last_level.config.tutorial.size()):
		last_level._show_page(i)
	last_level._start_level()
	last_level.sandbox.set_physics_process(false)
	var force = last_level.get_node("Sandbox/World/AirForces/AirForce1")
	check(force.valid and force.members.size() == 9, "第六关空军编队有效")
	check(last_level.combat.air_forces.has(force), "战斗系统注册第六关编队")
	check(last_level.combat.enemies.size() == 1 and last_level.config.victory.type == "enemy", "第六关注册一个敌机并要求击落")
	last_level._physics_process(0.0)
	check(not last_level.completed, "敌机存活不通关")
	force.triggered = true
	force.elapsed = float(force.config.duration_sim_s)
	last_level._physics_process(0.0)
	check(not last_level.completed, "空军飞行结束不触发通关")
	force.triggered = false
	var enemy: Node2D = last_level.combat.enemies[0].node
	last_level.combat.damage_target(enemy, 1000000.0)
	await process_frame
	check(last_level.completed and not force.triggered, "击落敌机通关，不要求触发空军")
	check(last_level.victory_next.visible, "第六关胜利后显示下一关按钮")
	paused = false
	last_level.queue_free()
	await process_frame
	var crash_level = load("res://scenes/level_6.tscn").instantiate()
	root.add_child(crash_level)
	await process_frame
	for i in range(crash_level.config.tutorial.size()):
		crash_level._show_page(i)
	crash_level._start_level()
	crash_level.combat.enemy_lost.emit(crash_level.combat.enemies[0].node)
	await process_frame
	check(crash_level.completed and paused and crash_level.start_button.text == "重试关卡", "敌机自然坠毁失败并可重试")
	paused = false
	crash_level.queue_free()
	await process_frame
	print("LEVEL_DUAL_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
