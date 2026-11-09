extends SceneTree
## 实窗验证：按钮悬停真正进入播放、设置面板可打开并截图。

var checks: int = 0
var failures: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var manager: Node = root.get_node_or_null("AudioManager")
	check(manager != null, "AudioManager 存在")
	var menu: Node = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var button: Button = menu.get_node("Center/Panel/Layout/New")
	check(button.has_meta("audio_hover_hooked"), "主菜单按钮已挂接悬停音")
	OS.delay_msec(80)
	manager._hover_last_ms = 0
	button.mouse_entered.emit()
	await process_frame
	check(manager._hover_player.playing, "按钮悬停后音效进入播放状态")
	menu._open_settings()
	await process_frame
	await process_frame
	var dialog: AcceptDialog = null
	for child in menu.get_children():
		if child is AcceptDialog and str(child.title) == "音效设置":
			dialog = child
	check(dialog != null, "设置面板已创建")
	if dialog != null:
		check(dialog.visible, "设置面板已显示")
		check(dialog.get_child_count() > 0, "设置面板包含内容")
	var image: Image = root.get_texture().get_image()
	check(image != null, "取得窗口画面")
	if image != null:
		image.save_png("res://tests/audio_settings_panel.png")
	print("AUDIO_VISUAL checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
