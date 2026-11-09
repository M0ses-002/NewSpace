extends Node2D

@export_file("*.json") var config_path := ""
@export var capture_range_path: NodePath
@export var radar_path: NodePath
var entity_config: Dictionary = {}
var state: Dictionary = {}
var behavior: RefCounted
var initial_transform: Transform2D
var initial_cached := false
var config_valid := false

const ENEMY_TYPES := {"orbital_enemy": preload("res://scripts/enemy_behavior.gd"), "orbital_enemy_nested": preload("res://scripts/enemy_nested_behavior.gd")}
const SATELLITE_TYPES := {"orbital_satellite": preload("res://scripts/satellite_behavior.gd"), "orbital_satellite_nested": preload("res://scripts/satellite_nested_behavior.gd")}

func initialize(kind: String, fallback: Dictionary) -> bool:
	if not initial_cached:
		initial_transform = transform
		initial_cached = true
	transform = initial_transform
	config_valid = false
	behavior = null
	entity_config = {}
	state = {}
	var data: Variant
	if config_path.is_empty():
		data = {"type": "orbital_enemy" if kind == "enemy" else "orbital_satellite", "data": fallback.duplicate(true)}
	else:
		var file := FileAccess.open(config_path, FileAccess.READ)
		if file == null:
			push_error("实体配置无法读取：" + config_path)
			visible = false
			return false
		data = JSON.parse_string(file.get_as_text())
	var registry: Dictionary = ENEMY_TYPES if kind == "enemy" else SATELLITE_TYPES
	if not data is Dictionary or not data.get("type") is String or not registry.has(data.type):
		push_error("实体配置无效或未知类型：" + config_path)
		visible = false
		return false
	behavior = registry[data.type].new()
	entity_config = behavior.parse(data)
	if entity_config.is_empty():
		push_error("实体类型数据无效：" + config_path)
		visible = false
		return false
	config_valid = true
	visible = true
	return true
