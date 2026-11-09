extends Control

const Progress = preload("res://scripts/level_progress.gd")

@onready var levels: GridContainer = $Center/Panel/Layout/Levels

func _ready() -> void:
	var unlocked := Progress.load_level()
	for index in range(levels.get_child_count()):
		var button: Button = levels.get_child(index)
		var number := index + 1
		button.text = _level_title(number, button.text)
		button.disabled = number > unlocked or number > Progress.LAST_LEVEL
		button.pressed.connect(_select_level.bind(number))
	$Center/Panel/Layout/Back.pressed.connect(_return_menu)

func _level_title(number: int, fallback: String) -> String:
	var file := FileAccess.open("res://data/level_%d.json" % number, FileAccess.READ)
	if file == null:
		return fallback
	var data = JSON.parse_string(file.get_as_text())
	if data is Dictionary and data.get("title") is String and not data.title.strip_edges().is_empty():
		return data.title
	return fallback

func _select_level(number: int) -> void:
	if number >= 1 and number <= Progress.load_level() and number <= Progress.LAST_LEVEL:
		get_tree().change_scene_to_file(Progress.scene_path(number))

func _return_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
