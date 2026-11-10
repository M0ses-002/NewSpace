extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)

func run() -> void:
	change_scene_to_file("res://scenes/level_6.tscn")
	await process_frame
	await process_frame
	var level = current_scene
	var menu = level.get_node("Sandbox/PauseMenu")
	check(paused and level.dialog.visible, "教程已暂停")
	escape()
	await process_frame
	check(paused and not menu.paused_by_menu and level.dialog.visible, "教程 ESC 不解锁教程")
	for i in range(level.config.tutorial.size()):
		level._show_page(i)
	level._open_equipment()
	check(is_instance_valid(level.equipment_screen) and paused, "关卡装备界面保持暂停")
	escape()
	await process_frame
	check(paused and not menu.paused_by_menu and is_instance_valid(level.equipment_screen), "装备界面 ESC 不打开暂停菜单")
	level._start_level()
	await process_frame
	check(not paused, "关卡已开始")
	var sandbox = level.sandbox
	var combat = level.combat
	combat.weapon_slots[0].cooldown = 10.0
	sandbox.begin_speed_drag()
	check(sandbox.speed_dragging, "开始速度拖拽")
	var original_orbit: Dictionary = sandbox.orbit.duplicate()
	var original_velocity: Vector2 = sandbox.velocity
	sandbox.change_speed(sandbox.speed_start * 1.05)
	escape()
	check(sandbox.orbit == original_orbit and sandbox.velocity == original_velocity, "取消速度预览保留原轨道和速度")
	await process_frame
	check(not sandbox.speed_dragging and not paused and not menu.panel.visible, "ESC 优先取消速度拖拽")
	escape()
	await process_frame
	check(paused and menu.panel.visible, "取消速度拖拽后第二次 ESC 暂停")
	escape()
	await process_frame
	check(not paused, "取消速度拖拽后恢复游戏")
	sandbox.begin_angle_drag()
	check(sandbox.angle_dragging, "开始角度拖拽")
	original_orbit = sandbox.orbit.duplicate()
	original_velocity = sandbox.velocity
	sandbox.change_angle(sandbox.heading_start + sandbox.heading_span * 0.25)
	escape()
	check(sandbox.orbit == original_orbit and sandbox.velocity == original_velocity, "取消角度预览保留原轨道和速度")
	await process_frame
	check(not sandbox.angle_dragging and not paused and not menu.panel.visible, "ESC 优先取消角度拖拽")
	escape()
	await process_frame
	check(paused and menu.panel.visible, "取消角度拖拽后第二次 ESC 暂停")
	escape()
	await process_frame
	check(not paused, "取消角度拖拽后恢复游戏")
	sandbox.motion_mode = "FREE"
	sandbox.flight.has_target = true
	escape()
	await process_frame
	check(not sandbox.flight.has_target and not paused and not menu.panel.visible, "ESC 优先取消自由航线")
	escape()
	await process_frame
	check(paused and menu.paused_by_menu and menu.panel.visible, "无活动航线时 ESC 打开暂停菜单")
	var elapsed: float = sandbox.elapsed_simulation
	var cooldown: float = combat.weapon_slots[0].cooldown
	await create_timer(0.1, true, false, true).timeout
	check(is_equal_approx(sandbox.elapsed_simulation, elapsed), "暂停时模拟冻结")
	check(is_equal_approx(float(combat.weapon_slots[0].cooldown), cooldown), "暂停时冷却冻结")
	menu._settings()
	await process_frame
	var dialog: Window
	for child in menu.get_children():
		if child is Window:
			dialog = child
	check(dialog != null and dialog.visible and paused, "暂停菜单打开共享设置")
	if dialog:
		dialog.queue_free()
	await process_frame
	escape()
	await process_frame
	check(not paused and not menu.panel.visible, "ESC 恢复游戏")
	check(float(combat.weapon_slots[0].cooldown) <= cooldown, "恢复后冷却可推进")
	escape()
	await process_frame
	menu._return_menu()
	await process_frame
	await process_frame
	check(not paused and current_scene.scene_file_path == "res://scenes/menu.tscn", "返回菜单并解除暂停")
	current_scene._open_settings()
	await process_frame
	var settings_found := false
	for child in current_scene.get_children():
		if child is Window and child.title == "音效设置":
			settings_found = true
	check(settings_found, "主菜单复用音效设置")
	change_scene_to_file("res://scenes/level_6.tscn")
	await process_frame
	await process_frame
	level = current_scene
	menu = level.get_node("Sandbox/PauseMenu")
	for i in range(level.config.tutorial.size()):
		level._show_page(i)
	level._open_equipment()
	var header: Control = level.equipment_screen.get_node("Margin/Layout/Header")
	for button in header.get_children():
		if button is Button and button.text == "返回主菜单":
			button.pressed.emit()
			break
	await process_frame
	await process_frame
	check(not paused and current_scene.scene_file_path == "res://scenes/menu.tscn", "装备界面返回菜单恢复暂停状态")
	print("PAUSE_MENU_TEST checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
