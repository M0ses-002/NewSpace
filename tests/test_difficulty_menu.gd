extends SceneTree

const Difficulty = preload("res://scripts/hard_mode.gd")
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
	var file := FileAccess.open(Difficulty.SAVE_PATH, FileAccess.WRITE)
	file.store_string("损坏")
	file.close()
	check(not Difficulty.is_enabled(), "损坏设置回退普通模式")
	file = FileAccess.open(Difficulty.SAVE_PATH, FileAccess.WRITE)
	file.store_string('{"enabled":"true"}')
	file.close()
	check(not Difficulty.is_enabled(), "错误类型回退普通模式")
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var toggle: CheckButton = menu.get_node("Difficulty")
	check(not toggle.button_pressed and toggle.text == "困难模式：关闭", "菜单显示普通模式")
	toggle.button_pressed = true
	check(Difficulty.is_enabled() and toggle.text == "困难模式：开启", "开启并保存困难模式")
	var level = load("res://scenes/level_1.tscn").instantiate()
	root.add_child(level)
	check(level.hard_enabled, "关卡读取菜单开启的困难模式")
	level.queue_free()
	paused = false
	menu.queue_free()
	await process_frame
	menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	toggle = menu.get_node("Difficulty")
	check(toggle.button_pressed and toggle.text == "困难模式：开启", "返回菜单恢复困难模式")
	toggle.button_pressed = false
	check(not Difficulty.is_enabled() and toggle.text == "困难模式：关闭", "关闭并保存困难模式")
	level = load("res://scenes/level_1.tscn").instantiate()
	root.add_child(level)
	check(not level.hard_enabled, "关卡读取菜单关闭的困难模式")
	level.queue_free()
	paused = false
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://difficulty_menu_test.png")
	menu.queue_free()
	await process_frame
	print("DIFFICULTY_MENU_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
