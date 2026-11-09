extends Node2D

signal projectile_hit(target: Node2D, damage: float)
signal destroyed(gun: Node2D)

const Bullet = preload("res://scenes/anti_air_bullet.tscn")
@export_file("*.json") var config_path := "res://data/anti_air_gun.json"
@export var planet_path: NodePath
@export var surface_angle_degrees := -90.0

var config: Dictionary = {}
var health := 0.0
var active := false
var cooldown := 0.0
var bullets: Array[Dictionary] = []

func initialize(planet_radius: float) -> bool:
	var planet := get_node_or_null(planet_path) as Node2D
	var file := FileAccess.open(config_path, FileAccess.READ)
	if planet == null or file == null or planet_radius <= 0.0:
		push_error("高射炮需要有效的行星、半径及配置")
		return false
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		push_error("高射炮配置格式无效")
		return false
	for key in ["health", "radius_km", "range_km", "shots_per_sim_s", "bullet_speed_km_s", "bullet_lifetime_sim_s", "bullet_radius_km", "bullet_damage"]:
		if not data.has(key) or typeof(data[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(data[key])) or float(data[key]) <= 0.0:
			push_error("高射炮配置数值无效：" + key)
			return false
	config = data
	var direction := Vector2.from_angle(deg_to_rad(surface_angle_degrees))
	global_position = planet.to_global(direction * planet_radius)
	global_rotation = planet.global_rotation + direction.angle() + PI / 2.0
	reset_gun()
	return true

func reset_gun() -> void:
	for bullet in bullets:
		if is_instance_valid(bullet.node):
			bullet.node.queue_free()
	bullets.clear()
	cooldown = 0.0
	health = float(config.health)
	active = true
	visible = true
	$Body.visible = true
	$Health.visible = true
	$Health.text = str(ceili(health))

func damage(amount: float) -> void:
	if not active or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	$Health.text = str(ceili(health))
	if health <= 0.0:
		active = false
		$Body.visible = false
		$Health.visible = false
		destroyed.emit(self)

func advance(dt: float, targets: Array) -> void:
	if dt <= 0.0:
		return
	var remaining := dt
	while remaining > 0.000001:
		var target: Dictionary = {}
		if active:
			for candidate in targets:
				if candidate.get("team", "") == "player" and is_instance_valid(candidate.get("node")) and candidate.node.visible and not candidate.node.is_queued_for_deletion() and global_position.distance_to(candidate.node.global_position) <= float(config.range_km):
					target = candidate
					break
		if not target.is_empty() and cooldown <= 0.000001:
			var direction: Vector2 = (target.node.global_position - global_position).normalized()
			if direction != Vector2.ZERO:
				var node: Node2D = Bullet.instantiate()
				$Bullets.add_child(node)
				node.global_position = global_position
				node.global_rotation = direction.angle()
				bullets.append({"node": node, "velocity": direction * float(config.bullet_speed_km_s), "life": float(config.bullet_lifetime_sim_s)})
			cooldown = 1.0 / float(config.shots_per_sim_s)
		var step := remaining
		if not target.is_empty():
			step = minf(step, cooldown)
		for bullet in bullets.duplicate():
			var travel := minf(step, float(bullet.life))
			var start: Vector2 = bullet.node.global_position
			var finish: Vector2 = start + bullet.velocity * travel
			var hit := false
			for candidate in targets:
				if candidate.get("team", "") != "player" or not is_instance_valid(candidate.get("node")) or not candidate.node.visible or candidate.node.is_queued_for_deletion():
					continue
				var target_end: Vector2 = candidate.node.global_position
				var target_start: Vector2 = candidate.get("previous_position", target_end)
				var start_fraction := (dt - remaining) / dt
				var end_fraction := (dt - remaining + travel) / dt
				var relative_start := start - target_start.lerp(target_end, start_fraction)
				var relative_end := finish - target_start.lerp(target_end, end_fraction)
				var closest := Geometry2D.get_closest_point_to_segment(Vector2.ZERO, relative_start, relative_end)
				if closest.length() <= float(config.bullet_radius_km) + float(candidate.get("radius_km", 0.0)):
					projectile_hit.emit(candidate.node, float(config.bullet_damage))
					hit = true
					break
			bullet.node.global_position = finish
			bullet.life -= travel
			if hit or bullet.life <= 0.000001:
				bullets.erase(bullet)
				bullet.node.queue_free()
		cooldown = maxf(0.0, cooldown - step)
		remaining -= step
