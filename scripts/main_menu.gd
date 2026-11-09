extends Control

const Progress = preload("res://scripts/level_progress.gd")
const Difficulty = preload("res://scripts/hard_mode.gd")

@onready var continue_button: Button = $Center/Panel/Layout/Continue
@onready var confirm: ConfirmationDialog = $Confirm
@onready var notice: AcceptDialog = $Notice
@onready var difficulty_button: CheckButton = $Difficulty

func _ready() -> void:
	get_tree().paused = false
	difficulty_button.set_pressed_no_signal(Difficulty.is_enabled())
	_update_difficulty_label()
	difficulty_button.toggled.connect(_set_difficulty)
	continue_button.disabled = Progress.load_level() == 0
	$Center/Panel/Layout/New.pressed.connect(_new_game)
	continue_button.pressed.connect(_continue_game)
	$Center/Panel/Layout/Equipment.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/equipment.tscn"))
	$Center/Panel/Layout/Settings.pressed.connect(_open_settings)
	$Center/Panel/Layout/Quit.pressed.connect(func() -> void: get_tree().quit())
	confirm.confirmed.connect(_start_new)

func _set_difficulty(enabled: bool) -> void:
	if not Difficulty.set_enabled(enabled):
		difficulty_button.set_pressed_no_signal(Difficulty.is_enabled())
		notice.dialog_text = "无法保存困难模式设置，请检查用户目录权限。"
		notice.popup_centered()
	_update_difficulty_label()

func _update_difficulty_label() -> void:
	difficulty_button.text = "困难模式：开启" if difficulty_button.button_pressed else "困难模式：关闭"

func _new_game() -> void:
	if FileAccess.file_exists(Progress.SAVE_PATH):
		confirm.popup_centered()
	else:
		_start_new()

func _start_new() -> void:
	if Progress.reset_level():
		get_tree().change_scene_to_file(Progress.scene_path(1))
	else:
		notice.dialog_text = "无法保存进度，请检查用户目录权限。"
		notice.popup_centered()

func _continue_game() -> void:
	var level := Progress.load_level()
	if level > 0:
		get_tree().change_scene_to_file("res://scenes/level_select.tscn")

## 音效设置：三条音量滑条与静音开关，改动即时生效并写入 user://audio_settings.json。
func _open_settings() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio == null:
		notice.dialog_text = "音效系统未初始化"
		notice.popup_centered()
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
	add_child(dialog)
	dialog.popup_centered()

func _volume_row(label_text: String, value: float, setter: Callable) -> HBoxContainer:
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
