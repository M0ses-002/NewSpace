extends RefCounted
## 所有分段使用起点、初速和已过时间解析积分，跨阶段大步长也不越过终点。
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var has_target: bool = false
var phase: String = "INERTIAL"
var max_acceleration: float = 0.01
var max_speed: float = 1.0
var route: PackedVector2Array = PackedVector2Array()
var segments: Array[Dictionary] = []
var segment_elapsed: float = 0.0
var last_error: String = ""
var target_clipped: bool = false
var requested_target: Vector2 = Vector2.ZERO
var boundary_crossing: bool = false
## 由 plan_bodies 记录的最早入球天体下标；-1 表示没有穿界。
var entry_body_index: int = -1

func set_state(p: Vector2, v: Vector2) -> void:
	position = p
	velocity = v
	cancel()

static func segment_clear(a: Vector2, b: Vector2, radius: float, center: Vector2 = Vector2.ZERO) -> bool:
	var ax: float = float(a.x) - float(center.x)
	var ay: float = float(a.y) - float(center.y)
	var dx: float = float(b.x) - float(center.x) - ax
	var dy: float = float(b.y) - float(center.y) - ay
	var dd: float = dx * dx + dy * dy
	var t: float = clampf(-(ax * dx + ay * dy) / dd, 0.0, 1.0) if dd > 0.0 else 0.0
	var x: float = ax + dx * t
	var y: float = ay + dy * t
	# 只容忍 Vector2 边界坐标的单精度量化；接触允许，真正穿圈仍拒绝。
	var tolerance: float = radius * 0.0000002
	return x * x + y * y >= (radius - tolerance) * (radius - tolerance)

static func first_boundary_target(start: Vector2, destination: Vector2, radius: float, center: Vector2 = Vector2.ZERO) -> Vector2:
	var sx: float = float(start.x) - float(center.x)
	var sy: float = float(start.y) - float(center.y)
	var ex: float = float(destination.x) - float(center.x)
	var ey: float = float(destination.y) - float(center.y)
	var dx: float = ex - sx
	var dy: float = ey - sy
	var dd: float = dx * dx + dy * dy
	if dd <= 0.0:
		return destination
	var pd: float = sx * dx + sy * dy
	var start_radius: float = sqrt(sx * sx + sy * sy)
	if absf(start_radius - radius) <= radius * 0.0000002:
		if pd >= 0.0:
			return destination
		return center + Vector2(sx * radius / start_radius, sy * radius / start_radius)
	var cross: float = sx * dy - sy * dx
	var rr_dd: float = radius * radius * dd
	var discriminant: float = rr_dd - cross * cross
	var tolerance: float = 0.000000000001 * maxf(rr_dd, cross * cross)
	if discriminant < -tolerance or pd > 0.0:
		return destination
	var root: float = sqrt(maxf(0.0, discriminant))
	var c: float = sx * sx + sy * sy - radius * radius
	var denominator: float = -pd + root
	var t: float = c / denominator if denominator > 0.0 else -pd / dd
	if t < -0.0000002 or t > 1.0000002:
		return destination
	t = clampf(t, 0.0, 1.0)
	var x: float = sx + dx * t
	var y: float = sy + dy * t
	var length: float = sqrt(x * x + y * y)
	return center + Vector2(x * radius / length, y * radius / length)

## 单一引力圆包装：保留旧签名供既有调用与测试使用。
func plan(destination: Vector2, gravity_radius: float) -> bool:
	return plan_bodies(destination, [{"center": Vector2.ZERO, "radius": gravity_radius, "entry_limit": 0.0}])

## 多天体规划：制动段必须避让每个球（起点已在球内的天体忽略），
## 目标在航段最早入球点截断，峰值速度受目标天体入球上限约束。
func plan_bodies(destination: Vector2, bodies: Array) -> bool:
	last_error = ""
	if not position.is_finite() or not velocity.is_finite() or not destination.is_finite() or not is_finite(max_acceleration) or not is_finite(max_speed) or max_acceleration <= 0.0 or max_speed <= 0.0:
		last_error = "航行状态、目标、加速度和速度上限必须为有效有限数值"
		return false
	if bodies.is_empty():
		last_error = "至少需要一个引力天体"
		return false
	var circles: Array[Dictionary] = []
	for item: Variant in bodies:
		if not item is Dictionary:
			last_error = "引力天体参数必须是字典"
			return false
		var center_value: Variant = item.get("center", Vector2.ZERO)
		if not center_value is Vector2 or not center_value.is_finite():
			last_error = "引力天体中心必须为有限坐标"
			return false
		var radius_value: Variant = item.get("radius", 0.0)
		if typeof(radius_value) != TYPE_FLOAT and typeof(radius_value) != TYPE_INT:
			last_error = "引力天体半径必须为数值"
			return false
		var radius: float = float(radius_value)
		if not is_finite(radius) or radius <= 0.0:
			last_error = "引力天体半径必须为有限正数"
			return false
		var limit_value: Variant = item.get("entry_limit", 0.0)
		if typeof(limit_value) != TYPE_FLOAT and typeof(limit_value) != TYPE_INT:
			last_error = "入球速度上限必须为数值"
			return false
		var limit: float = float(limit_value)
		if not is_finite(limit) or limit < 0.0:
			last_error = "入球速度上限必须为有限非负数"
			return false
		circles.append({"center": center_value, "radius": radius, "entry_limit": limit, "index": circles.size()})
	var speed: float = velocity.length()
	var brake_duration: float = speed / max_acceleration
	var brake_end: Vector2 = position + velocity * (0.5 * brake_duration)
	if not is_finite(speed) or not is_finite(brake_duration) or not brake_end.is_finite() or not is_finite(brake_end.distance_to(destination)):
		last_error = "航行数值超出可计算范围"
		return false
	var direction_to_target: Vector2 = destination - brake_end
	var segment_length: float = direction_to_target.length()
	var active: Array[Dictionary] = []
	for circle: Dictionary in circles:
		var center_point: Vector2 = circle.center
		var radius: float = circle.radius
		# 起点已经在该影响球内时该球不再参与避让与截断，否则合法航线会被自身球体拒绝。
		if position.distance_to(center_point) < radius - radius * 0.0000002:
			continue
		if not segment_clear(position, brake_end, radius, center_point):
			last_error = "制动段将进入引力范围，无法执行"
			return false
		active.append(circle)
	var effective_target: Vector2 = destination
	var crossing_index: int = -1
	var earliest: float = INF
	for index in range(active.size()):
		var circle: Dictionary = active[index]
		var radius: float = circle.radius
		var center_point: Vector2 = circle.center
		var candidate: Vector2 = first_boundary_target(brake_end, destination, radius, center_point)
		var candidate_local: Vector2 = candidate - center_point
		var radial_dot: float = candidate_local.dot(direction_to_target)
		var intersects: bool = candidate.distance_to(destination) > radius * 0.0000002 or absf(candidate_local.length() - radius) <= radius * 0.0000002
		if not intersects or radial_dot >= -0.0000001:
			continue
		var fraction: float = (candidate - brake_end).length() / segment_length if segment_length > 0.0 else 0.0
		if fraction < earliest:
			earliest = fraction
			effective_target = candidate
			crossing_index = index
	var crosses: bool = crossing_index >= 0
	segments.clear()
	segment_elapsed = 0.0
	requested_target = destination
	boundary_crossing = crosses
	entry_body_index = int(active[crossing_index].index) if crosses else -1
	target = effective_target if crosses else destination
	target_clipped = false
	has_target = true
	route = PackedVector2Array([position, brake_end, destination])
	if brake_duration > 0.000000001:
		_append_segment(position, velocity, -velocity.normalized() * max_acceleration, brake_duration, "BRAKE")
	var displacement: Vector2 = target - brake_end
	var distance: float = displacement.length()
	var direction: Vector2 = displacement.normalized()
	var peak: float = minf(max_speed, sqrt(distance * max_acceleration * (2.0 if boundary_crossing else 1.0)))
	if crosses and float(active[crossing_index].entry_limit) > 0.0:
		peak = minf(peak, float(active[crossing_index].entry_limit))
	var ramp_time: float = peak / max_acceleration
	var ramp_distance: float = 0.5 * max_acceleration * ramp_time * ramp_time
	var cruise_distance: float = maxf(0.0, distance - ramp_distance * (1.0 if boundary_crossing else 2.0))
	if ramp_time > 0.000000001:
		_append_segment(brake_end, Vector2.ZERO, direction * max_acceleration, ramp_time, "ACCEL")
		if cruise_distance > 0.000000001:
			_append_segment(brake_end + direction * ramp_distance, direction * peak, Vector2.ZERO, cruise_distance / peak, "CRUISE")
		if not boundary_crossing:
			_append_segment(target - direction * ramp_distance, direction * peak, -direction * max_acceleration, ramp_time, "DECEL")
	phase = str(segments[0].phase) if not segments.is_empty() else ("BOUNDARY" if boundary_crossing else "ARRIVED")
	return true

func _append_segment(p: Vector2, v: Vector2, acceleration: Vector2, duration: float, label: String) -> void:
	segments.append({"position": p, "velocity": v, "acceleration": acceleration, "duration": duration, "phase": label})

func advance(delta: float) -> float:
	var remaining: float = maxf(0.0, delta)
	while remaining > 0.0 and not segments.is_empty():
		var segment: Dictionary = segments[0]
		var used: float = minf(remaining, float(segment.duration) - segment_elapsed)
		segment_elapsed += used
		remaining -= used
		var t: float = segment_elapsed
		position = segment.position + segment.velocity * t + segment.acceleration * (0.5 * t * t)
		velocity = segment.velocity + segment.acceleration * t
		if segment_elapsed >= float(segment.duration) - 0.000000001:
			segments.pop_front()
			segment_elapsed = 0.0
			if segments.is_empty():
				# 终点由三段的解析边界给出，消除单精度亚毫米残差。
				position = target
				if boundary_crossing:
					phase = "BOUNDARY"
				else:
					velocity = Vector2.ZERO
					phase = "ARRIVED"
			else:
				phase = str(segments[0].phase)
	if phase == "INERTIAL":
		position += velocity * remaining
		remaining = 0.0
	return remaining if phase == "BOUNDARY" else 0.0

func cancel() -> void:
	segments.clear()
	segment_elapsed = 0.0
	has_target = false
	target_clipped = false
	boundary_crossing = false
	entry_body_index = -1
	phase = "INERTIAL"
	route = PackedVector2Array()
	last_error = ""
