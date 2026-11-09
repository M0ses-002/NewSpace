extends RefCounted
## 敌机以有限推力追踪玩家，并通过径向速度和制动距离限制接近危险边界。
const Orbit = preload("res://scripts/kepler_orbit.gd")
const HEADING_TAU: float = 2.0
const APPROACH_GAIN: float = 100.0
const APOAPSIS_GRAVITY_FRACTION: float = 0.9

func advance(host: Node, combat: Node, _target: Dictionary, dt: float) -> bool:
	var enemy: Dictionary = host.state
	var controller: Node = combat.controller
	var player: Node2D = controller.ship
	var has_player: bool = is_instance_valid(player) and not player.is_queued_for_deletion() and not combat.dead
	var player_position: Vector2 = player.position if has_player else Vector2.ZERO
	has_player = has_player and is_finite(player_position.x) and is_finite(player_position.y)
	var p: Vector2 = host.position
	var v: Vector2 = enemy.velocity
	var planet: Dictionary = controller.body_at(0)
	var center: Vector2 = planet.center
	var gravity_radius: float = float(planet.gravity_radius_km)
	var top: float = float(planet.field_top_km)
	var mu: float = float(planet.mu)
	var minimum_radius: float = maxf(top, float(planet.radius_km) + 10.0)
	var maximum_radius: float = gravity_radius * 0.8
	player_position -= center
	var a_max: float = float(enemy.config.acceleration_km_s2)
	var has_target: bool = has_player and player_position.length() > float(planet.radius_km) and player_position.length() < gravity_radius and (p - center).length() < gravity_radius and (p - center).length() > float(planet.radius_km)
	var remaining: float = dt
	while remaining > 0.00000001:
		var local: Vector2 = p - center
		var radius: float = local.length()
		var speed: float = v.length()
		var radial: Vector2 = local / radius if radius > 0.0 else Vector2.RIGHT
		var thrust := Vector2.ZERO
		if has_target and radius < gravity_radius:
			var desired_radius: float = clampf(player_position.length(), minimum_radius * 1.2, maximum_radius)
			var phase_error: float = angle_difference(local.angle(), player_position.angle())
			var max_speed: float = float(enemy.config.max_speed_km_s)
			var tangent_world := Vector2(-radial.y, radial.x)
			var desired_tangent_speed: float = clampf(phase_error * radius / 80.0, -max_speed, max_speed)
			var desired_radial_speed: float = clampf((desired_radius - radius) / 60.0, -max_speed * 0.5, max_speed * 0.5)
			var stopping_accel: float = maxf(a_max * 0.5, 0.000001)
			desired_radial_speed = maxf(desired_radial_speed, -sqrt(2.0 * stopping_accel * maxf(radius - minimum_radius, 0.0)))
			desired_radial_speed = minf(desired_radial_speed, sqrt(2.0 * stopping_accel * maxf(maximum_radius - radius, 0.0)))
			var desired_velocity: Vector2 = (tangent_world * desired_tangent_speed + radial * desired_radial_speed).limit_length(max_speed)
			var gravity_compensation: Vector2 = -controller._gravity(p, 0)
			thrust = ((desired_velocity - v) / 8.0 + gravity_compensation).limit_length(a_max)
		var inside: bool = radius < gravity_radius or (is_equal_approx(radius, gravity_radius) and local.dot(v) < 0.0)
		var gravity: Vector2 = controller._gravity(p, 0) if inside else Vector2.ZERO
		var a: Vector2 = gravity + thrust
		var h := minf(remaining, 0.25)
		var next: Vector2 = p + v * h + 0.5 * a * h * h
		if ((next - center).length() < gravity_radius) != inside:
			var lo := 0.0
			var hi := h
			for i in range(30):
				var mid := (lo + hi) * 0.5
				var point := p + v * mid + 0.5 * a * mid * mid
				if ((point - center).length() < gravity_radius) == inside:
					lo = mid
				else:
					hi = mid
			h = maxf(hi, 0.000001)
			next = p + v * h + 0.5 * a * h * h
		var contact: float = controller._surface_contact_time(p, v, a, h)
		if not is_inf(contact):
			host.position = p + v * contact + 0.5 * a * contact * contact
			enemy.velocity = v + a * contact
			return false
		var end_gravity: Vector2 = controller._gravity(next, 0) if inside else Vector2.ZERO
		v += (gravity + end_gravity + 2.0 * thrust) * (0.5 * h)
		p = next
		remaining -= h
	host.position = p
	enemy.velocity = v
	if v.length_squared() > 0.000000001:
		host.rotation = v.angle()
	return true

func _turn_rate(radius: float, speed: float, mu: float, desired_radius: float, gamma: float, tangential_thrust: float, a_max: float, controller: Node) -> float:
	# 法向加速度预算与切向推力正交合成，总预算不超过 a_max。
	var budget: float = maxf(0.0, a_max - tangential_thrust)
	if budget <= 0.0 or speed <= 0.000001 or mu <= 0.0:
		return 0.0
	var beta: float = 2.0 - radius * speed * speed / mu
	if beta <= 0.000001:
		return 0.0
	var semi_major: float = radius / beta
	# 每步按当前轨道重算：切向推力会改变 a，进而改变可行偏角。
	var e_cap: float = Orbit.heading_eccentricity_limit(semi_major, Orbit.MIN_PERIAPSIS, Orbit.MAX_E, float(controller.body_at(0).gravity_radius_km) * APOAPSIS_GRAVITY_FRACTION)
	var gamma_cap: float = Orbit.heading_limit(radius, semi_major, e_cap)
	if gamma_cap <= 0.0:
		return 0.0
	var radial_reference: float = clampf((desired_radius - radius) / APPROACH_GAIN, -speed * sin(gamma_cap), speed * sin(gamma_cap))
	var gamma_reference: float = asin(clampf(radial_reference / speed, -sin(gamma_cap), sin(gamma_cap)))
	return clampf((gamma_reference - gamma) / HEADING_TAU, -budget / speed, budget / speed)

func steer_velocity(velocity: Vector2, point: Vector2, direction: float, delta_gamma: float) -> Vector2:
	var speed: float = velocity.length()
	var radius: float = point.length()
	if speed <= 0.0 or radius <= 0.0:
		return velocity
	var radial: Vector2 = point / radius
	var tangent: Vector2 = Vector2(-radial.y, radial.x) * direction
	var gamma: float = atan2(velocity.dot(radial), velocity.dot(tangent)) + delta_gamma
	# 单位方向线性组合乘固定速率：转向不改变速率。
	return (tangent * cos(gamma) + radial * sin(gamma)) * speed

func parse(source: Dictionary) -> Dictionary:
	var data: Variant = source.get("data")
	if not data is Dictionary:
		return {}
	for key in ["health", "radius_km", "acceleration_km_s2", "max_speed_km_s"]:
		if not data.has(key) or typeof(data[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(data[key])) or float(data[key]) <= 0.0:
			return {}
	if not data.get("color") is String or not Color.html_is_valid(data.color):
		return {}
	return data.duplicate(true)
