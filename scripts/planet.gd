@tool
extends Node2D
## 保留场景中的可编辑节点，启动时按 JSON 参数更新视觉比例。
## body_index 为 0 读取主行星；为 1 读取第二行星，缺失时隐藏自身。
const Units = preload("res://scripts/game_units.gd")
const Config = preload("res://scripts/simulation_config.gd")
const PLANET_TEXTURES = [preload("res://planet_assets/planet_a.png"), preload("res://planet_assets/planet_b.png")]
const FRAME_INTERVAL := 0.25
const BODY_DIAMETER_PX := 235.0

var animation_time := 0.0

@export var body_index: int = 0

func _ready() -> void:
	refresh_from_config()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var world := get_parent()
	var sandbox := world.get_parent() if world != null else null
	if sandbox != null and sandbox.has_method("is_orbit_editing") and (sandbox.manually_paused or sandbox.is_orbit_editing()):
		return
	animation_time = fposmod(animation_time + delta, FRAME_INTERVAL * 36.0)
	$Sprite.frame = int(animation_time / FRAME_INTERVAL)

func refresh_from_config() -> void:
	Config.ensure_loaded()
	var data: Dictionary = Config.planet
	var center: Vector2 = Vector2.ZERO
	var label: String = "行星A"
	if body_index == 1:
		if Config.planet_b.is_empty():
			visible = false
			return
		data = Config.planet_b
		center = Vector2(float(data.center_x_km), float(data.center_y_km))
		position = center
		label = "行星B"
	visible = true
	var radius: float = float(data.radius_km)
	$Sprite.texture = PLANET_TEXTURES[clampi(body_index, 0, 1)]
	$Sprite.scale = Vector2.ONE * (2.0 * radius / BODY_DIAMETER_PX)
	var thickness: float = float(data.field_thickness_km)
	var field_top: float = radius + thickness
	var gravity_radius: float = float(data.gravity_radius_km)
	$Surface.polygon = _circle(radius)
	$Atmosphere.polygon = _circle(field_top)
	$Surface.texture_scale = Vector2.ONE * radius / 50.0
	$Surface.texture_offset = Vector2.ONE * 64.0 * radius / 50.0
	$Name.position.y = field_top + 7.0
	$Name.text = "%s\n行星半径 %.1f km\n恒强场厚度 %.1f km / 场顶 %.1f km\n引力范围 %.1f km" % [label, radius, thickness, field_top, gravity_radius]

func _circle(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for index in range(64):
		points.append(Vector2.from_angle(TAU * float(index) / 64.0) * radius)
	return points
