extends RefCounted

func advance(host: Node2D, dt: float) -> void:
	host.state.angle += float(host.entity_config.angular_speed_rad_s) * dt
	host.position = Vector2.from_angle(host.state.angle) * float(host.entity_config.orbit_radius_km)

func parse(source: Dictionary) -> Dictionary:
	var data: Variant = source.get("data")
	if not data is Dictionary:
		return {}
	for key in ["health", "radius_km", "capture_radius_km", "orbit_radius_km", "angular_speed_rad_s"]:
		if not data.has(key) or typeof(data[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(data[key])) or float(data[key]) <= 0.0:
			return {}
	if not data.get("color") is String or not Color.html_is_valid(data.color):
		return {}
	return data.duplicate(true)
