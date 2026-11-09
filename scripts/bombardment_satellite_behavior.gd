extends "res://scripts/satellite_behavior.gd"

func advance(host: Node2D, dt: float) -> void:
	if host.descent_state != "ORBIT":
		return
	var body: Dictionary = host.get_planet_body()
	if body.is_empty():
		return
	var world: Node2D = host.get_parent().get_parent().get_parent()
	var center_world: Vector2 = world.to_global(body.center)
	var center_local: Vector2 = host.get_parent().to_local(center_world)
	if not host.state.has("bombardment_orbit_initialized"):
		host.state.angle = (host.initial_transform.origin - center_local).angle()
		host.state.bombardment_orbit_initialized = true
	host.state.angle += float(host.entity_config.angular_speed_rad_s) * dt
	host.position = center_local + Vector2.from_angle(host.state.angle) * float(host.entity_config.orbit_radius_km)
