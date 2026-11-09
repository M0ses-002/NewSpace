extends "res://scripts/entity_host.gd"

signal bomb_impact(world_position: Vector2, radius_km: float, damage: float)

const BombardmentBehavior = preload("res://scripts/bombardment_satellite_behavior.gd")

@export_range(0, 1, 1) var planet_index: int = 0
var descent_state: String = "ORBIT"
var descent_target: Vector2
var bomb_cooldown: float = 0.0

func initialize(kind: String, fallback: Dictionary) -> bool:
	reset_bombs()
	descent_state = "ORBIT"
	if not super.initialize(kind, fallback):
		return false
	for key in ["bomb_speed_km_s", "bomb_radius_km", "blast_radius_km", "bomb_damage", "bomb_cooldown_real_s"]:
		var value: Variant = entity_config.get(key)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) <= 0.0:
			push_error("轰炸卫星配置无效：" + key)
			config_valid = false
			visible = false
			return false
	behavior = BombardmentBehavior.new()
	return true

func get_planet_body() -> Dictionary:
	var combat: Node = get_parent().get_parent()
	if not is_instance_valid(combat.controller) or planet_index < 0 or planet_index >= combat.controller.bodies.size():
		return {}
	return combat.controller.bodies[planet_index]

func fire_bomb() -> bool:
	if not config_valid or descent_state != "ORBIT" or state.get("owner", "neutral") != "player":
		return false
	var combat: Node = get_parent().get_parent()
	if combat.dead or combat.controller.manually_paused or get_tree().paused or combat.controller.is_orbit_editing():
		return false
	var body: Dictionary = get_planet_body()
	if body.is_empty():
		return false
	var world: Node2D = combat.get_parent()
	var center: Vector2 = world.to_global(body.center)
	if global_position.distance_to(center) <= float(body.radius_km):
		return false
	descent_target = center + (global_position - center).normalized() * float(body.radius_km)
	descent_state = "FALLING"
	get_node("Action").visible = false
	return true

func advance_bomb_cooldown(_delta: float) -> void:
	pass

func advance_bombs(dt: float) -> void:
	if descent_state != "FALLING" or dt <= 0.0:
		return
	var combat: Node = get_parent().get_parent()
	if combat.dead or combat.controller.manually_paused or get_tree().paused or combat.controller.is_orbit_editing():
		return
	var distance: float = global_position.distance_to(descent_target)
	if float(entity_config.bomb_speed_km_s) * dt >= distance:
		global_position = descent_target
		descent_state = "SPENT"
		visible = false
		bomb_impact.emit(global_position, float(entity_config.blast_radius_km), float(entity_config.bomb_damage))
	else:
		global_position = global_position.move_toward(descent_target, float(entity_config.bomb_speed_km_s) * dt)

func reset_bombs() -> void:
	bomb_cooldown = 0.0
	if descent_state == "FALLING":
		descent_state = "SPENT"
		visible = false
