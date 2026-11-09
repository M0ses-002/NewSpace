extends Node2D

signal impact(bomb: Node2D, world_position: Vector2)

var target: Vector2
var speed: float
var impacted := false

func launch(origin: Vector2, center: Vector2, planet_radius: float, config: Dictionary) -> void:
	global_position = origin
	target = center + (origin - center).normalized() * planet_radius
	speed = float(config.bomb_speed_km_s)
	$Body.scale = Vector2.ONE * float(config.bomb_radius_km)

func advance(dt: float) -> void:
	if impacted or dt <= 0.0:
		return
	var distance := global_position.distance_to(target)
	if speed * dt >= distance:
		global_position = target
		impacted = true
		impact.emit(self, target)
	else:
		global_position = global_position.move_toward(target, speed * dt)
