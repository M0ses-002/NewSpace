extends SceneTree

const Hard = preload("res://scripts/hard_mode.gd")
const Loadout = preload("res://scripts/loadout.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func make_level(number: int) -> Node:
	var level = load("res://scenes/level_%d.tscn" % number).instantiate()
	root.add_child(level)
	level.sandbox.set_physics_process(false)
	for i in range(level.config.tutorial.size()):
		level._show_page(i)
	level._open_equipment()
	return level

func run() -> void:
	for malformed in ["{", "{\"enabled\":\"true\"}", "{\"enabled\":1}", "[]", "{}"]:
		var file := FileAccess.open(Hard.SAVE_PATH, FileAccess.WRITE)
		file.store_string(malformed)
		file.close()
		check(not Hard.is_enabled(), "损坏或非布尔模式设置安全回退")
	check(Hard.set_enabled(true) and Hard.is_enabled(), "困难模式持久启用")
	for number in [1, 2, 5, 6]:
		check(Hard.get_rule(number).get("time_limit_seconds") == 35, "关卡时间限制 %d" % number)
	for number in [3, 4, 6, 7]:
		check(Hard.get_rule(number).get("max_slots") == {3: 1, 4: 2, 6: 2, 7: 3}[number], "槽位限制 %d" % number)
	check(not Hard.valid_rule(6, {"max_slots": 2, "weapon_limits": {}}), "缺少时限字段的规则无效")
	check(not Hard.valid_rule(6, {"time_limit_seconds": 35, "weapon_limits": {}}), "缺少槽位字段的规则无效")
	check(not Hard.valid_rule(7, {"max_slots": 3, "time_limit_seconds": null}), "缺少武器限制字段的规则无效")
	check(not Hard.valid_rule(3, {"max_slots": "1", "time_limit_seconds": null, "weapon_limits": {}}), "类型错误的规则无效")
	check(Hard.valid_rule(1, {"max_slots": 2, "time_limit_seconds": null, "weapon_limits": {"carrier": 1}}), "可调整第一关限制")
	check(Hard.valid_rule(7, {"max_slots": null, "time_limit_seconds": 20, "weapon_limits": {}}), "可调整第七关限制")
	var rule8 := Hard.get_rule(8)
	check(not rule8.is_empty() and rule8.time_limit_seconds == null and rule8.max_slots == null and rule8.weapon_limits == {}, "第八关规则不限")
	check(not Hard.valid_rule(9, {"max_slots": null, "time_limit_seconds": null, "weapon_limits": {}}), "第九关规则无效")
	check(Hard.equipment_error({"max_slots": null, "weapon_limits": {}}, ["missile", "carrier", "carrier", "carrier"]) == "", "空槽位上限表示不限")
	check(Hard.equipment_error({"max_slots": null, "weapon_limits": {"carrier": 1}}, ["carrier", "carrier", "", ""]) != "", "任意关可配置舰载机上限")
	check(Hard.equipment_error(Hard.get_rule(7), ["missile", "missile", "", ""]) != "", "第七关双导弹禁止")
	check(Hard.equipment_error(Hard.get_rule(7), ["carrier", "carrier", "point_defense", ""]) == "", "非导弹装备允许重复")
	check(Hard.equipment_error(Hard.get_rule(7), ["wingman", "wingman", "wingman", ""]) == "", "第七关允许三个僚机槽")
	check(Hard.equipment_error(Hard.get_rule(7), ["wingman", "wingman", "wingman", "wingman"]) != "", "僚机槽计入困难模式装备上限")
	check(Loadout.save_slots(["missile", "carrier", "", ""]), "设置违规装备")
	var level = make_level(3)
	level._start_level()
	check(is_instance_valid(level.equipment_screen) and paused and not level.hard_started and level.equipment_screen.status.text.contains("最多装备"), "违规装备阻止开始并提示")
	paused = false
	level.queue_free()
	await process_frame
	check(Loadout.save_slots(["missile", "", "", ""]), "设置合规装备")
	level = make_level(1)
	check(not level.hard_started and level.hard_elapsed_usec == 0, "教程期间不计时")
	level._start_level()
	level.hard_elapsed_usec = 35000000
	level._win()
	check(level.completed and not level.victory_controls.visible and paused, "超时胜利转为失败")
	paused = false
	level.queue_free()
	await process_frame
	level = make_level(6)
	level._start_level()
	await create_timer(0.05).timeout
	paused = true
	var tree_paused_time: int = level.hard_elapsed_usec
	await create_timer(0.15, true).timeout
	paused = false
	await process_frame
	check(level.hard_elapsed_usec - tree_paused_time < 100000, "场景树暂停期间不计时")
	level.sandbox.manually_paused = true
	level._update_hard_clock()
	var paused_time: int = level.hard_elapsed_usec
	await create_timer(0.05).timeout
	level._update_hard_clock()
	check(level.hard_elapsed_usec == paused_time, "手动暂停不计时")
	level.sandbox.manually_paused = false
	level._update_hard_clock()
	await create_timer(0.05).timeout
	level._update_hard_clock()
	check(level.hard_elapsed_usec > paused_time, "恢复后按现实时间计时")
	level.sandbox.dragging = true
	level._update_hard_clock()
	var editing_time: int = level.hard_elapsed_usec
	await create_timer(0.05).timeout
	level._update_hard_clock()
	check(level.hard_elapsed_usec == editing_time, "调整轨道不计时")
	level.sandbox.dragging = false
	level.hard_elapsed_usec = 35000000
	level._process(0.0)
	check(level.completed and paused and not level.victory_controls.visible, "时间到自动失败")
	paused = false
	level.queue_free()
	await process_frame
	level = make_level(3)
	level._start_level()
	check(Loadout.save_slots(["missile", "carrier", "", ""]), "运行时更改装备")
	level._win()
	check(level.completed and not level.victory_controls.visible and paused, "胜利时复核装备")
	paused = false
	level.queue_free()
	await process_frame
	check(Hard.set_enabled(false), "关闭困难模式")
	level = make_level(3)
	level._start_level()
	check(not level.dialog.visible and not paused, "普通模式不受限制")
	level.queue_free()
	await process_frame
	print("HARD_MODE_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
