extends SceneTree

const Loadout = preload("res://scripts/loadout.gd")
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
	var file := FileAccess.open(Loadout.SAVE_PATH, FileAccess.WRITE)
	file.store_string("not json")
	file.close()
	check(Loadout.get_slots() == ["missile", "", "", ""], "损坏存档回退默认")
	check(not Loadout.save_slots(["missile"]), "拒绝错误槽位数量")
	check(not Loadout.save_slots(["missile", "bad", "", ""]), "拒绝未知装备")
	check(Loadout.save_slots(["carrier", "carrier", "point_defense", ""]), "允许重复装备和空槽")
	check(Loadout.get_slots() == ["carrier", "carrier", "point_defense", ""], "保存后读回装备")
	check(Loadout.save_slots(["satellite_deployer", "satellite_deployer", "", "missile"]), "允许多个卫星布置器装备槽")
	check(Loadout.get_slots() == ["satellite_deployer", "satellite_deployer", "", "missile"], "卫星布置器存档读回")
	check(Loadout.save_slots(["wingman", "wingman", "wingman", "wingman"]), "允许四槽重复安装僚机")
	check(Loadout.get_slots() == ["wingman", "wingman", "wingman", "wingman"], "重复僚机存档读回")
	check(not Loadout.save_slots(["laser", "", "", ""]), "不能保存已移除的激光")
	file = FileAccess.open(Loadout.SAVE_PATH, FileAccess.WRITE)
	file.store_string('{"slots":["laser","carrier","laser","missile"]}')
	file.close()
	check(Loadout.get_slots() == ["", "carrier", "", "missile"], "旧激光槽迁移为空并保留其他槽")
	file = FileAccess.open(Loadout.SAVE_PATH, FileAccess.WRITE)
	file.store_string('{"slots":["missile",42,"",""]}')
	file.close()
	check(Loadout.get_slots() == ["missile", "", "", ""], "异常槽值回退默认")
	var scene: Control = load("res://scenes/equipment.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var row: HBoxContainer = scene.get_node("Margin/Layout/Slots")
	var choices: HBoxContainer = scene.get_node("Margin/Layout/Choices")
	check(row.get_child_count() == 4 and choices.get_child_count() == 0, "界面显示四槽且初始未选中")
	row.get_child(1).pressed.emit()
	check(choices.get_child_count() == 6 and choices.has_node("wingman") and not choices.has_node("laser"), "选择槽位显示僚机且不显示激光")
	var combat_config = preload("res://scripts/combat_config.gd")
	var config: Dictionary = combat_config.load_config()
	check(combat_config.DEFAULTS.weapons.satellite_deployer.name == "卫星布置器", "默认配置包含布置器名称")
	check(config.wingman.duration_real_s == 5.0 and config.wingman.cooldown_real_s == 15.0 and config.wingman.orbit_radius_km > 0.0 and config.wingman.radius_km > 0.0 and config.wingman.angular_speed_rad_s > 0.0, "僚机时长、冷却和轨道参数可配置")
	var invalid_wingman: Dictionary = config.duplicate(true)
	invalid_wingman.wingman.radius_km = 0.0
	check(not combat_config.validate(invalid_wingman), "僚机参数非法时配置校验失败")
	var invalid_config: Dictionary = config.duplicate(true)
	invalid_config.weapons.erase("satellite_deployer")
	check(not combat_config.validate(invalid_config), "缺失布置器名称时配置校验失败")
	for id: String in ["missile", "point_defense", "carrier", "satellite_deployer", "wingman"]:
		var definition: Dictionary = config.weapons.get(id, {})
		check(not definition.is_empty() and choices.get_node(id).text == definition.get("name"), "装备名称使用战斗配置：" + id)
	choices.get_node("wingman").pressed.emit()
	check(Loadout.get_slots()[1] == "wingman" and row.get_child(1).text.contains("僚机"), "界面安装僚机并保存")
	row.get_child(2).pressed.emit()
	choices.get_node("wingman").pressed.emit()
	check(Loadout.get_slots().slice(1, 3) == ["wingman", "wingman"], "界面允许多个槽安装僚机")
	row.get_child(1).pressed.emit()
	choices.get_node("satellite_deployer").pressed.emit()
	check(Loadout.get_slots()[1] == "satellite_deployer" and row.get_child(1).text.contains("卫星布置器"), "卫星布置器安装、显示并持久化")
	choices.get_node("carrier").pressed.emit()
	check(Loadout.get_slots()[1] == "carrier", "舰载机安装并持久化")
	choices.get_node("missile").pressed.emit()
	check(Loadout.get_slots()[1] == "missile", "点击武器安装并持久化")
	choices.get_node("Empty").pressed.emit()
	check(Loadout.get_slots()[1] == "", "点击卸下允许空槽")
	check(scene.get_node("Margin/Layout/Preview/Viewport/World/Pivot").get_child_count() == 1, "飞船模型已实例化")
	var pivot: Node3D = scene.get_node("Margin/Layout/Preview/Viewport/World/Pivot")
	var angle := pivot.rotation.y
	await process_frame
	check(pivot.rotation.y != angle, "模型自动旋转")
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	check(menu.has_node("Center/Panel/Layout/Equipment"), "主菜单包含飞船改造入口")
	menu.queue_free()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://equipment_test.png")
	scene.queue_free()
	await process_frame
	print("EQUIPMENT_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
