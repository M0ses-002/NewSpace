extends Control

const Progress = preload("res://scripts/level_progress.gd")
const Difficulty = preload("res://scripts/hard_mode.gd")
const AudioSettings = preload("res://scripts/audio_settings_dialog.gd")

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
	AudioSettings.open(self)
