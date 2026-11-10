extends CanvasLayer

const AudioSettings = preload("res://scripts/audio_settings_dialog.gd")
var panel: Control
var paused_by_menu := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	layer = 200
	panel = Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	add_child(panel)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.75)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(320, 240)
	center.add_child(frame)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	frame.add_child(box)
	var title := Label.new()
	title.text = "游戏暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	for entry in [["继续游戏", _resume], ["设置", _settings], ["返回主菜单", _return_menu]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size.y = 42
		button.pressed.connect(entry[1])
		box.add_child(button)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
		return
	if paused_by_menu:
		for child in get_children():
			if child is Window and child.visible:
				return
		_resume()
		get_viewport().set_input_as_handled()
	elif not get_tree().paused:
		var sandbox := get_parent()
		if sandbox.angle_dragging:
			sandbox.finish_angle_drag(false)
			get_viewport().set_input_as_handled()
			return
		elif sandbox.speed_dragging:
			sandbox.finish_speed_drag(false)
			get_viewport().set_input_as_handled()
			return
		elif sandbox.dragging:
			sandbox.finish_drag(false)
			get_viewport().set_input_as_handled()
			return
		elif sandbox.motion_mode == "FREE" and sandbox.flight.has_target:
			sandbox.cancel_free_flight()
			get_viewport().set_input_as_handled()
			return
		paused_by_menu = true
		panel.visible = true
		get_tree().paused = true
		get_viewport().set_input_as_handled()

func _resume() -> void:
	paused_by_menu = false
	panel.visible = false
	get_tree().paused = false

func _settings() -> void:
	AudioSettings.open(self)

func _return_menu() -> void:
	paused_by_menu = false
	get_tree().paused = false
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.stop_level_music()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
