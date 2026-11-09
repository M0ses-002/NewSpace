extends RefCounted

const SAVE_PATH := "user://equipment.json"
const DEFAULT_SLOTS := ["missile", "", "", ""]
const VALID_IDS := ["", "missile", "point_defense", "carrier", "satellite_deployer"]

static func get_slots() -> Array:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return DEFAULT_SLOTS.duplicate()
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return DEFAULT_SLOTS.duplicate()
	var data: Variant = parser.data
	if not data is Dictionary or not data.get("slots") is Array:
		return DEFAULT_SLOTS.duplicate()
	var slots: Array = data.slots
	if slots.size() != 4:
		return DEFAULT_SLOTS.duplicate()
	var result := slots.duplicate()
	for index in range(result.size()):
		var item: Variant = result[index]
		if item is String and item == "laser":
			result[index] = ""
		elif not item is String or item not in VALID_IDS:
			return DEFAULT_SLOTS.duplicate()
	return result

static func save_slots(slots: Array) -> bool:
	if slots.size() != 4:
		return false
	for item: Variant in slots:
		if not item is String or item not in VALID_IDS:
			return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"slots": slots}))
	file.flush()
	return file.get_error() == OK
