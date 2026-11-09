class_name KeplerOrbit
extends RefCounted
## 精确二体椭圆运动，引力焦点位于原点。
## 长度为 km、时间为模拟秒、速度为 km/s；正角动量在屏幕上为顺时针。
const Units = preload("res://scripts/game_units.gd")
const Config = preload("res://scripts/simulation_config.gd")
static var MU: float:
	get:
		return Units.EXTERNAL_MU_KM3_S2
# 安全近心点与椭圆编辑边界来自同一份配置，不缓存旧参数。
static var MIN_PERIAPSIS: float:
	get:
		Config.ensure_loaded()
		return Config.planet.min_periapsis_km
static var MAX_A: float:
	get:
		Config.ensure_loaded()
		return Config.planet.max_semi_major_axis_km
static var MAX_E: float:
	get:
		Config.ensure_loaded()
		return Config.planet.max_eccentricity
const CIRCLE_SNAP_ENTER_PX: float = 10.0
const CIRCLE_SNAP_EXIT_PX: float = 18.0

static func make(a: float, e: float, angle: float) -> Dictionary:
	return {"a": a, "e": e, "angle": angle}

static func axes(orbit: Dictionary) -> Array[Vector2]:
	var u: Vector2 = Vector2.from_angle(orbit.angle)
	return [u, Vector2(-u.y, u.x)]

static func point_at(orbit: Dictionary, eccentric_anomaly: float) -> Vector2:
	var basis: Array[Vector2] = axes(orbit)
	var a: float = orbit.a
	var e: float = orbit.e
	return basis[0] * a * (cos(eccentric_anomaly) - e) + basis[1] * a * sqrt(1.0 - e * e) * sin(eccentric_anomaly)

static func endpoint(orbit: Dictionary, index: int) -> Vector2:
	return point_at(orbit, float(index) * PI / 2.0)

static func mean_at(orbit: Dictionary, position: Vector2) -> float:
	var basis: Array[Vector2] = axes(orbit)
	var a: float = orbit.a
	var e: float = orbit.e
	var anomaly: float = atan2(position.dot(basis[1]) / (a * sqrt(1.0 - e * e)), position.dot(basis[0]) / a + e)
	return anomaly - e * sin(anomaly)

static func state_at(orbit: Dictionary, mean_anomaly: float, direction: float = 1.0, mu: float = -1.0) -> Dictionary:
	var e: float = orbit.e
	var m: float = wrapf(mean_anomaly, -PI, PI)
	var anomaly: float = m
	for iteration in range(14):
		var correction: float = (anomaly - e * sin(anomaly) - m) / (1.0 - e * cos(anomaly))
		anomaly -= correction
		if absf(correction) < 1.0e-12:
			break
	var basis: Array[Vector2] = axes(orbit)
	var a: float = orbit.a
	var n: float = sqrt((MU if mu < 0.0 else mu) / (a * a * a))
	var rate: float = direction * n / (1.0 - e * cos(anomaly))
	var velocity: Vector2 = (-basis[0] * a * sin(anomaly) + basis[1] * a * sqrt(1.0 - e * e) * cos(anomaly)) * rate
	return {"position": point_at(orbit, anomaly), "velocity": velocity}

static func velocity_at(orbit: Dictionary, position: Vector2, direction: float = 1.0, mu: float = -1.0) -> Vector2:
	var p: float = orbit.a * (1.0 - orbit.e * orbit.e)
	var eccentricity_vector: Vector2 = Vector2.from_angle(orbit.angle) * float(orbit.e)
	var radial: Vector2 = eccentricity_vector + position.normalized()
	return Vector2(-radial.y, radial.x) * sqrt((MU if mu < 0.0 else mu) / p) * direction

static func from_state(position: Vector2, velocity: Vector2, circle_angle: float = 0.0, mu: float = -1.0) -> Dictionary:
	var gravity: float = MU if mu < 0.0 else mu
	var radius: float = sqrt(float(position.x) * position.x + float(position.y) * position.y)
	var speed_squared: float = float(velocity.x) * velocity.x + float(velocity.y) * velocity.y
	if not is_finite(radius) or not is_finite(speed_squared) or radius <= 0.0:
		return {}
	var energy: float = speed_squared * 0.5 - gravity / radius
	var momentum: float = float(position.x) * velocity.y - float(position.y) * velocity.x
	if energy >= 0.0 or absf(momentum) < 0.000001:
		return {}
	var a: float = -gravity / (2.0 * energy)
	var ex: float = float(velocity.y) * momentum / gravity - float(position.x) / radius
	var ey: float = -float(velocity.x) * momentum / gravity - float(position.y) / radius
	var e: float = sqrt(ex * ex + ey * ey)
	if e > MAX_E + 0.000001 or a > MAX_A + 0.005 or a * (1.0 - e) < MIN_PERIAPSIS - 0.0001:
		return {}
	# 单精度状态向量在约束边界存在舍入；只修正浮点级超界。
	e = minf(e, MAX_E)
	a = minf(a, MAX_A)
	var angle: float = circle_angle if e < 0.000001 else atan2(ey, ex)
	if e < 0.000001:
		e = 0.0
	var recovered: Dictionary = make(a, e, angle)
	return {"orbit": recovered, "mean_anomaly": mean_at(recovered, position), "direction": 1.0 if momentum > 0.0 else -1.0}

static func flight_path_angle(position: Vector2, velocity: Vector2, direction: float) -> float:
	var radial: Vector2 = position.normalized()
	if radial == Vector2.ZERO:
		return 0.0
	var tangent: Vector2 = Vector2(-radial.y, radial.x) * direction
	return atan2(velocity.dot(radial), velocity.dot(tangent))

static func heading_eccentricity_limit(semi_major: float, periapsis: float, max_eccentricity: float, apoapsis_limit: float) -> float:
	if not is_finite(semi_major) or not is_finite(periapsis) or not is_finite(max_eccentricity) or not is_finite(apoapsis_limit) or semi_major <= 0.0:
		return 0.0
	# 三条上限取最紧者：总偏心率、近心安全距离、远心封顶。
	var limit: float = minf(minf(max_eccentricity, 1.0 - periapsis / semi_major), apoapsis_limit / semi_major - 1.0)
	# 保持 e_cap < 1，使 γ_max < 90° 且角动量不退化。
	return clampf(limit, 0.0, 0.999999)

static func heading_limit(radius: float, semi_major: float, e_cap: float = -1.0) -> float:
	if not is_finite(radius) or not is_finite(semi_major) or radius <= 0.0 or semi_major <= 0.0:
		return 0.0
	var beta: float = radius / semi_major
	if beta <= 0.0 or beta >= 2.0:
		return 0.0
	var cap: float = e_cap
	if cap < 0.0:
		cap = minf(MAX_E, 1.0 - MIN_PERIAPSIS / semi_major)
	if not is_finite(cap) or cap < 0.0:
		return 0.0
	cap = minf(cap, 0.999999)
	var ratio: float = (1.0 - cap * cap) / (beta * (2.0 - beta))
	if ratio >= 1.0:
		return 0.0
	# 边界内收 1e-5：单精度状态向量在精确边界会因舍入被 from_state 拒绝。
	return acos(sqrt(maxf(0.0, ratio))) * (1.0 - 0.00001)

static func heading_velocity(position: Vector2, speed: float, gamma: float, direction: float) -> Vector2:
	var radial: Vector2 = position.normalized()
	if radial == Vector2.ZERO:
		return Vector2.ZERO
	var tangent: Vector2 = Vector2(-radial.y, radial.x) * direction
	# 单位方向线性组合乘速率：避免 Vector2.rotated 在屏幕顺时针约定下静默反向。
	return (tangent * cos(gamma) + radial * sin(gamma)) * maxf(speed, 0.0)

static func speed_interval(position: Vector2, velocity: Vector2, mu: float = -1.0) -> Vector2:
	var gravity: float = MU if mu < 0.0 else mu
	var radius_squared: float = float(position.x) * position.x + float(position.y) * position.y
	var speed_squared: float = float(velocity.x) * velocity.x + float(velocity.y) * velocity.y
	if not is_finite(radius_squared) or not is_finite(speed_squared) or radius_squared <= 0.0 or speed_squared <= 0.0:
		return Vector2.ZERO
	var radius: float = sqrt(radius_squared)
	if radius < MIN_PERIAPSIS - 0.0001:
		return Vector2.ZERO
	var momentum: float = float(position.x) * velocity.y - float(position.y) * velocity.x
	var beta: float = clampf(momentum * momentum / (radius_squared * speed_squared), 0.0, 1.0)
	if beta < 1.0 - MAX_E * MAX_E - 0.0000001:
		return Vector2.ZERO
	# x = r v² / μ，e² = 1 - β x (2 - x)，合法集合是单个闭区间。
	var spread: float = sqrt(maxf(0.0, 1.0 - (1.0 - MAX_E * MAX_E) / beta))
	var low: float = 1.0 - spread
	var high: float = minf(1.0 + spread, 2.0 - radius / MAX_A)
	var k: float = MIN_PERIAPSIS / radius
	if absf(radius - MIN_PERIAPSIS) < 0.0001:
		if beta < 1.0 - 0.0000001:
			return Vector2.ZERO
		low = maxf(low, 1.0)
	else:
		if beta <= k * k:
			return Vector2.ZERO
		low = maxf(low, 2.0 * k * (1.0 - k) / (beta - k * k))
	if high < low - 0.000001:
		return Vector2.ZERO
	# 将可拖范围向内收浮点级余量，避免Vector2舍入把边界推至非法侧。
	var margin: float = minf(0.000002, maxf(0.0, high - low) * 0.01)
	return Vector2(sqrt((low + margin) * gravity / radius), sqrt((maxf(low, high) - margin) * gravity / radius))

static func constrained(position: Vector2, e: float, angle: float) -> Dictionary:
	if e < 0.0 or e > MAX_E:
		return {}
	var p: float = position.length() + e * Vector2.from_angle(angle).dot(position)
	var a: float = p / (1.0 - e * e)
	if a > MAX_A or a * (1.0 - e) < MIN_PERIAPSIS or a <= 0.0:
		return {}
	return make(a, e, angle)

static func residual(orbit: Dictionary, position: Vector2) -> float:
	var basis: Array[Vector2] = axes(orbit)
	var x: float = position.dot(basis[0]) / float(orbit.a) + float(orbit.e)
	var y: float = position.dot(basis[1]) / (float(orbit.a) * sqrt(1.0 - orbit.e * orbit.e))
	return absf(x * x + y * y - 1.0)

static func fit_axis(position: Vector2, target: Vector2, index: int, drag_start: Dictionary, previous: Dictionary, snapped: bool, zoom: float = 1.0) -> Dictionary:
	var radius: float = sqrt(float(position.x) * position.x + float(position.y) * position.y)
	var start_a: float = drag_start.a
	var start_b: float = start_a * sqrt(1.0 - drag_start.e * drag_start.e)
	var major: bool = index == 0 or index == 2
	var basis: Array[Vector2] = axes(drag_start)
	var outward: Vector2 = basis[0] if major else basis[1]
	if index >= 2:
		outward = -outward
	# 始终相对于按下时的轴和端点求位移，旋转和吸附不会累计鼠标误差。
	var displacement: float = (target - endpoint(drag_start, index)).dot(outward)
	if absf(displacement) < 0.0001 and not snapped and previous == drag_start:
		return {"orbit": drag_start.duplicate(), "snapped": false}
	var requested_a: float = start_a + displacement if major else start_a
	var requested_b: float = start_b if major else start_b + displacement
	var snap_limit: float = CIRCLE_SNAP_EXIT_PX if snapped else CIRCLE_SNAP_ENTER_PX
	var circle_distance: float = maxf(absf(requested_a - radius), absf(requested_b - radius))
	var axis_gap: float = absf(requested_a - requested_b)
	if radius >= MIN_PERIAPSIS and radius <= MAX_A and maxf(circle_distance, axis_gap) * zoom <= snap_limit:
		return {"orbit": make(radius, 0.0, previous.angle), "snapped": true}
	var a: float = start_a
	var b: float = start_b
	if major:
		# q <= r <= Q 给出下界；偏心率和近心点安全距离给出上界。
		var low: float = maxf(b, (b * b + radius * radius) / (2.0 * radius))
		var high: float = minf(MAX_A, minf(b / sqrt(1.0 - MAX_E * MAX_E), (b * b + MIN_PERIAPSIS * MIN_PERIAPSIS) / (2.0 * MIN_PERIAPSIS)))
		a = clampf(requested_a, low, maxf(low, high))
	else:
		var low: float = sqrt(maxf(a * a * (1.0 - MAX_E * MAX_E), 2.0 * a * MIN_PERIAPSIS - MIN_PERIAPSIS * MIN_PERIAPSIS))
		var high: float = minf(a, sqrt(maxf(0.0, 2.0 * a * radius - radius * radius)))
		b = clampf(requested_b, minf(low, high), high)
	var e: float = sqrt(maxf(0.0, 1.0 - b * b / (a * a)))
	var angle: float = previous.angle
	if e > 1.0e-8:
		var turn: float = acos(clampf((b * b / a - radius) / (radius * e), -1.0, 1.0))
		var positive: float = position.angle() + turn
		var negative: float = position.angle() - turn
		angle += angle_difference(angle, positive) if absf(angle_difference(angle, positive)) < absf(angle_difference(angle, negative)) else angle_difference(angle, negative)
	return {"orbit": make(a, e, angle), "snapped": false}

static func fit_endpoint(position: Vector2, target: Vector2, index: int, previous: Dictionary) -> Dictionary:
	# Two degrees of freedom remain after fixing the focus and the ship anchor.
	# Coarse global seeds plus local pattern search avoid circular-orbit singularities.
	if index == 1 or index == 3:
		var exact: Dictionary = exact_minor_endpoint(position, target, index, previous)
		if not exact.is_empty():
			return exact
	elif target.length() > 0.001:
		var radius: float = position.length()
		var distance: float = target.length()
		var axis: Vector2 = target.normalized() * (1.0 if index == 0 else -1.0)
		var projection: float = axis.dot(position)
		var denominator: float = distance - projection if index == 0 else distance + projection
		if absf(denominator) > 0.00001:
			var e: float = (radius - distance) / denominator if index == 0 else (distance - radius) / denominator
			var exact: Dictionary = constrained(position, e, axis.angle())
			if not exact.is_empty() and endpoint(exact, index).distance_to(target) < 0.01:
				return exact
	var best: Dictionary = previous.duplicate()
	var best_cost: float = endpoint(best, index).distance_squared_to(target)
	var seeds: Array[Dictionary] = [previous.duplicate()]
	var angle_origin: float = previous.angle
	for ai in range(24):
		var angle: float = angle_origin + TAU * float(ai) / 24.0
		for ei in range(7):
			var candidate: Dictionary = constrained(position, MAX_E * float(ei) / 6.0, angle)
			if candidate.is_empty():
				continue
			seeds.append(candidate)
	seeds.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return endpoint(left, index).distance_squared_to(target) < endpoint(right, index).distance_squared_to(target))
	for seed_index in range(mini(5, seeds.size())):
		var refined: Dictionary = refine_endpoint(position, target, index, seeds[seed_index])
		var cost: float = endpoint(refined, index).distance_squared_to(target)
		if cost < best_cost:
			best = refined
			best_cost = cost
	return best

static func exact_minor_endpoint(position: Vector2, target: Vector2, index: int, previous: Dictionary) -> Dictionary:
	# At a minor endpoint |target|=a, c=a*e and b=a*sqrt(1-e²).
	# Set e=sin(alpha); the target angle fixes the major-axis orientation.
	var a: float = target.length()
	if a < MIN_PERIAPSIS or a > MAX_A:
		return {}
	var sign_minor: float = 1.0 if index == 1 else -1.0
	var max_e: float = minf(MAX_E, 1.0 - MIN_PERIAPSIS / a)
	var max_alpha: float = asin(max_e)
	var last_alpha: float = 0.0
	var last_value: float = minor_equation(position, target, a, 0.0, sign_minor)
	var best: Dictionary = {}
	var best_turn: float = INF
	for i in range(1, 65):
		var alpha: float = max_alpha * float(i) / 64.0
		var value: float = minor_equation(position, target, a, alpha, sign_minor)
		if last_value * value <= 0.0:
			var lo: float = last_alpha
			var hi: float = alpha
			var low_value: float = last_value
			for iteration in range(32):
				var mid: float = (lo + hi) * 0.5
				var mid_value: float = minor_equation(position, target, a, mid, sign_minor)
				if low_value * mid_value <= 0.0:
					hi = mid
				else:
					lo = mid
					low_value = mid_value
			var solved: float = (lo + hi) * 0.5
			var angle: float = target.angle() - sign_minor * (PI / 2.0 + solved)
			var candidate: Dictionary = make(a, sin(solved), angle)
			var turn: float = absf(angle_difference(previous.angle, angle))
			if residual(candidate, position) < 0.00001 and turn < best_turn:
				best = candidate
				best_turn = turn
		last_alpha = alpha
		last_value = value
	return best

static func minor_equation(position: Vector2, target: Vector2, a: float, alpha: float, sign_minor: float) -> float:
	var e: float = sin(alpha)
	var angle: float = target.angle() - sign_minor * (PI / 2.0 + alpha)
	return a * (1.0 - e * e) - position.length() - e * Vector2.from_angle(angle).dot(position)

static func refine_endpoint(position: Vector2, target: Vector2, index: int, seed_orbit: Dictionary) -> Dictionary:
	var best: Dictionary = seed_orbit.duplicate()
	var best_cost: float = endpoint(best, index).distance_squared_to(target)
	var e_step: float = 0.09
	var angle_step: float = PI / 12.0
	for iteration in range(40):
		var improved: bool = false
		var center_e: float = best.e
		var center_angle: float = best.angle
		for de in [-1.0, 0.0, 1.0]:
			for da in [-1.0, 0.0, 1.0]:
				var candidate: Dictionary = constrained(position, clampf(center_e + de * e_step, 0.0, MAX_E), center_angle + da * angle_step)
				if candidate.is_empty():
					continue
				var cost: float = endpoint(candidate, index).distance_squared_to(target)
				if cost < best_cost - 1.0e-8:
					best = candidate
					best_cost = cost
					improved = true
		if not improved:
			e_step *= 0.5
			angle_step *= 0.5
	return best

static func polyline(orbit: Dictionary, segments: int = 320) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(segments + 1)
	for i in range(segments + 1):
		points[i] = point_at(orbit, TAU * float(i) / float(segments))
	return points
