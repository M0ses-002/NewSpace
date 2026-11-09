extends "res://scripts/satellite_behavior.gd"

func parse(source: Dictionary) -> Dictionary:
	var properties: Variant = source.get("properties")
	if not properties is Dictionary:
		return {}
	return super.parse({"data": properties.get("orbit")})
