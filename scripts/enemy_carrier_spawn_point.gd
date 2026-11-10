extends "res://scripts/spawn_point.gd"

@export var velocity_world := Vector2.ZERO
@export_enum("顺时针:1", "逆时针:-1") var orbit_direction := 1
@export_range(0.0, 10000.0, 1.0, "or_greater") var dive_periapsis_km := 0.0

func launch_velocity_world(center_world: Vector2, mu: float) -> Vector2:
	if dive_periapsis_km <= 0.0:
		return velocity_world
	var radial := global_position - center_world
	var apoapsis := radial.length()
	if mu <= 0.0 or apoapsis <= dive_periapsis_km:
		push_error("舰载机刷新点俯冲轨道参数无效")
		return velocity_world
	var semi_major := (apoapsis + dive_periapsis_km) * 0.5
	var speed := sqrt(mu * (2.0 / apoapsis - 1.0 / semi_major))
	return -radial.normalized().orthogonal() * float(orbit_direction) * speed
