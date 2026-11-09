extends RefCounted

const SAVE_PATH := "user://level_progress.json"
const LAST_LEVEL := 8

static func load_level() -> int:
	if not FileAccess.file_exists(SAVE_PATH):
		return 0
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return 0
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or not data.has("level") or not (data.level is int or data.level is float):
		return 0
	return clampi(int(data.level), 1, LAST_LEVEL)

static func save_level(level: int) -> bool:
	return _write_level(maxi(load_level(), clampi(level, 1, LAST_LEVEL)))

static func reset_level() -> bool:
	return _write_level(1)

static func _write_level(unlocked: int) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("无法保存关卡进度")
		return false
	file.store_string(JSON.stringify({"level": unlocked}))
	return true

static func scene_path(level: int) -> String:
	return "res://scenes/level_%d.tscn" % level
