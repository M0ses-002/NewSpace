extends RefCounted

static func open(owner: Node) -> void:
	var audio := owner.get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	var dialog := AcceptDialog.new()
	dialog.title = "音效设置"
	dialog.ok_button_text = "关闭"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(400, 0)
	box.add_theme_constant_override("separation", 10)
	dialog.add_child(box)
	box.add_child(_volume_row("主音量", float(audio.master_volume), Callable(audio, "set_master_volume")))
	box.add_child(_volume_row("背景音乐", float(audio.music_volume), Callable(audio, "set_music_volume")))
	box.add_child(_volume_row("界面音效", float(audio.ui_volume), Callable(audio, "set_ui_volume")))
	box.add_child(_volume_row("战斗音效", float(audio.sfx_volume), Callable(audio, "set_sfx_volume")))
	var mute := CheckButton.new()
	mute.text = "静音"
	mute.button_pressed = bool(audio.muted)
	mute.toggled.connect(Callable(audio, "set_muted"))
	box.add_child(mute)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	owner.add_child(dialog)
	dialog.popup_centered()

static func _volume_row(label_text: String, value: float, setter: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(90, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(240, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(setter)
	row.add_child(slider)
	var readout := Label.new()
	readout.text = "%d%%" % roundi(value * 100.0)
	readout.custom_minimum_size = Vector2(48, 0)
	slider.value_changed.connect(func(changed: float) -> void: readout.text = "%d%%" % roundi(changed * 100.0))
	row.add_child(readout)
	return row
