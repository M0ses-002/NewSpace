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

func run() -> void:
	check(Progress.load_level() == 0, "隔离存档初始为空")
	change_scene_to_file("res://scenes/menu.tscn")
	await process_frame
	await process_frame
	var menu = current_scene
	check(menu.continue_button.disabled, "无存档时继续按钮禁用")
	menu._continue_game()
	await process_frame
	check(current_scene == menu, "无存档不能直接进入选关")
	check(Progress.save_level(3), "保存第三关解锁进度")
	change_scene_to_file("res://scenes/menu.tscn")
	await process_frame
	await process_frame
	menu = current_scene
	check(not menu.continue_button.disabled, "有存档时继续按钮可用")
	menu.continue_button.pressed.emit()
	await process_frame
	await process_frame
	var selector = current_scene
	check(selector.scene_file_path == "res://scenes/level_select.tscn", "继续游戏进入选关界面")
	for i in range(8):
		check(selector.levels.get_child(i).disabled == (i >= 3), "第三关进度下关卡 %d 可用状态" % (i + 1))
		var file := FileAccess.open("res://data/level_%d.json" % (i + 1), FileAccess.READ)
		var data = JSON.parse_string(file.get_as_text())
		check(selector.levels.get_child(i).text == data.title, "关卡 %d 显示配置名称" % (i + 1))
	check(selector._level_title(999, "备用名称") == "备用名称", "配置缺失时使用备用名称")
	selector._select_level(4)
	await process_frame
	check(current_scene == selector, "直接调用也不能进入未解锁关卡")
	selector.get_node("Center/Panel/Layout/Back").pressed.emit()
	await process_frame
	await process_frame
	check(current_scene.scene_file_path == "res://scenes/menu.tscn", "返回主菜单")
	current_scene.continue_button.pressed.emit()
	await process_frame
	await process_frame
	selector = current_scene
	selector.levels.get_child(0).pressed.emit()
	await process_frame
	await process_frame
	check(current_scene.scene_file_path == "res://scenes/level_1.tscn", "可进入已通关关卡")
	paused = false
	change_scene_to_file("res://scenes/level_select.tscn")
	await process_frame
	await process_frame
	selector = current_scene
	selector.levels.get_child(2).pressed.emit()
	await process_frame
	await process_frame
	check(current_scene.scene_file_path == "res://scenes/level_3.tscn", "可进入当前解锁关卡")
	paused = false
	check(Progress.save_level(6), "解锁第六关")
	change_scene_to_file("res://scenes/level_select.tscn")
	await process_frame
	await process_frame
	selector = current_scene
	for i in range(8):
		check(selector.levels.get_child(i).disabled == (i >= 6), "第六关解锁后关卡 %d 可用状态" % (i + 1))
	selector.levels.get_child(5).pressed.emit()
	await process_frame
	await process_frame
	check(current_scene.scene_file_path == "res://scenes/level_6.tscn", "可进入第六关")
	current_scene._win()
	check(Progress.load_level() == 7, "第六关通关后解锁第七关")
	paused = false
	change_scene_to_file("res://scenes/menu.tscn")
	await process_frame
	await process_frame
	current_scene._start_new()
	await process_frame
	await process_frame
	check(Progress.load_level() == 1, "确认新游戏可重置已解锁进度")
	check(current_scene.scene_file_path == "res://scenes/level_1.tscn", "新游戏进入第一关")
	paused = false
	print("LEVEL_SELECT_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
