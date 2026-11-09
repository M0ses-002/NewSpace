extends Node2D
## Scene nodes own presentation; this controller owns orbital state and input.
signal reset_completed
const Orbit = preload("res://scripts/kepler_orbit.gd")
const Units = preload("res://scripts/game_units.gd")
const Config = preload("res://scripts/simulation_config.gd")
const FreeFlight = preload("res://scripts/free_flight.gd")
var combat: Node2D
var flight = FreeFlight.new()
var motion_mode: String = "ORBIT"
## 当前焦点天体的影响球半径；始终与 bodies[focus_index].gravity_radius_km 同步。
var gravity_radius: float = 400.0
## 静态天体表：{name, center, radius_km, field_top_km, mu, gravity_radius_km}。
## 0 号为主行星（世界原点），1 号存在时位于 planet_b.center_x_km/center_y_km。
var bodies: Array[Dictionary] = []
var focus_index: int = 0
var navigation_feedback: String = ""
const MAX_NUMERICAL_STEPS: int = 2048
var pending_simulation_time: float = 0.0
const CAPTURE_PREP_SECONDS: float = 5.0
const CAPTURE_TIMEOUT: float = 3600.0
var capture_remaining: float = 0.0
var capture_elapsed: float = 0.0
var capture_direction: float = 1.0
var orbit_acquired: bool = false
@onready var gravity_line: Line2D = $World/GravityBoundary
@onready var route_line: Line2D = $World/FreeFlight/Route
@onready var target_marker: Node2D = $World/FreeFlight/Target
# 速度矢量采用独立示意比例，避免物理速度量级变小后不可见。
const VELOCITY_VISUAL_SCALE: float = 160.0
const SPEED_SNAP_ENTER_PX: float = 8.0
const SPEED_SNAP_EXIT_PX: float = 14.0
const SPEED_KEYBOARD_SNAP: float = 0.0005
const HEADING_SPAN_FLOOR: float = 0.001
const HEADING_KEY_STEP: float = 0.004363323129986
@export_range(100.0, 600.0) var initial_radius: float = 240.0
@export_range(0.1, 600.0) var simulation_speed: float = 60.0
@export_range(0.2, 2.0) var initial_zoom: float = 1.0
@onready var ship: Node2D = $World/Ship
@onready var camera: Camera2D = $World/Ship/Camera2D
@onready var current_line: Line2D = $World/CurrentOrbit
@onready var preview_line: Line2D = $World/PreviewOrbit
@onready var axes_line: Line2D = $World/Axes
@onready var velocity_line: Line2D = $World/Velocity
@onready var new_velocity_line: Line2D = $World/NewVelocity
@onready var anchor_marker: Node2D = $World/Anchor
@onready var handles: Array[Node] = $World/Handles.get_children()
@onready var status_label: Label = $HUD/Layout/Header/Status
@onready var unit_label: Label = $HUD/Layout/Header/Units
@onready var telemetry: Label = $HUD/Layout/Telemetry
@onready var feedback: Label = $HUD/Layout/Feedback
@onready var speed_slider: HSlider = $HUD/Layout/SpeedControl/SpeedSlider
@onready var free_max_control: VBoxContainer = $HUD/Layout/SpeedControl/FreeMaxControl
@onready var free_max_slider: HSlider = $HUD/Layout/SpeedControl/FreeMaxControl/MaxSpeedSlider
@onready var free_max_label: Label = $HUD/Layout/SpeedControl/FreeMaxControl/Value
@onready var speed_label: Label = $HUD/Layout/SpeedControl/SpeedValue
@onready var speed_limits: Label = $HUD/Layout/SpeedControl/SpeedLimits
@onready var circular_label: Label = $HUD/Layout/SpeedControl/CircularSpeed
@onready var circular_marker: Control = $HUD/Layout/SpeedControl/SpeedSlider/CircularMarker
@onready var angle_control: VBoxContainer = $HUD/Layout/AngleControl
@onready var angle_slider: HSlider = $HUD/Layout/AngleControl/AngleSlider
@onready var angle_value: Label = $HUD/Layout/AngleControl/AngleValue
@onready var angle_limits: Label = $HUD/Layout/AngleControl/AngleLimits
@onready var angle_readout: Label = $HUD/Layout/AngleControl/AngleReadout
@onready var angle_base_marker: Control = $HUD/Layout/AngleControl/AngleSlider/BaseMarker
var slider_display_bounds: Vector2 = Vector2.ZERO
var circular_speed: float = 0.0
var circular_available: bool = false
var speed_snapped: bool = false
var speed_ignore_press_value: bool = false
var speed_press_position: Vector2 = Vector2.ZERO
var orbit_direction: float = 1.0
var speed_dragging: bool = false
var speed_start: float = 0.0
var speed_bounds: Vector2 = Vector2.ZERO
var speed_limited: bool = false
var speed_cancelled: bool = false
var angle_dragging: bool = false
var angle_cancelled: bool = false
var angle_limited: bool = false
var angle_available: bool = false
var angle_ignore_press_value: bool = false
var angle_press_position: Vector2 = Vector2.ZERO
var heading_start: float = 0.0
var heading_span: float = 0.0
var heading_request: float = 0.0
var angle_start_speed: float = 0.0
var orbit: Dictionary
var preview: Dictionary
var mean_anomaly: float = 0.0
var velocity: Vector2 = Vector2.ZERO
var dragging: bool = false
var selected_handle: int = -1
var anchor: Vector2 = Vector2.ZERO
var old_velocity: Vector2 = Vector2.ZERO
var drag_offset: Vector2 = Vector2.ZERO
var drag_start: Dictionary
var circle_snapped: bool = false
var manually_paused: bool = false
var last_delta_v: float = 0.0
var elapsed_simulation: float = 0.0
var turnaround_cooldown: float = 0.0

func _ready() -> void:
	Config.ensure_loaded()
	_build_bodies()
	initial_radius = float(Config.ship.initial_orbit_radius_km)
	gravity_radius = float(focus_body().gravity_radius_km)
	flight.max_acceleration = float(Config.ship.max_acceleration_m_s2) / Units.METERS_PER_KM
	flight.max_speed = float(Config.ship.free_flight_max_speed_m_s) / Units.METERS_PER_KM
	free_max_slider.max_value = maxf(flight.max_speed * 2.0, free_max_slider.min_value)
	free_max_slider.set_value_no_signal(flight.max_speed)
	free_max_slider.value_changed.connect(_change_free_max_speed)
	$HUD/Layout/Controls/Pause.pressed.connect(toggle_pause)
	$HUD/Layout/SpeedControl/Turnaround.pressed.connect(turnaround)
	speed_slider.drag_started.connect(func() -> void:
		speed_cancelled = false
		begin_speed_drag())
	speed_slider.value_changed.connect(change_speed)
	speed_slider.resized.connect(_position_circular_marker)
	speed_slider.drag_ended.connect(func(_changed: bool) -> void:
		finish_speed_drag(true)
		speed_cancelled = false)
	angle_slider.drag_started.connect(func() -> void:
		angle_cancelled = false
		begin_angle_drag())
	angle_slider.value_changed.connect(change_angle)
	angle_slider.resized.connect(_position_angle_marker)
	angle_slider.drag_ended.connect(func(_changed: bool) -> void:
		finish_angle_drag(true)
		angle_cancelled = false)
	var captions: Array[String] = ["长轴 + / 近心点", "短轴 +", "长轴 - / 远心点", "短轴 -"]
	for i in range(4):
		handles[i].get_node("Caption").text = captions[i]
	reset()
	combat = $World/Combat
	combat.setup(self)

## 从配置构建静态天体表；planet_b 为空时世界只有一颗行星。
func _build_bodies() -> void:
	bodies.clear()
	bodies.append(_body_from_config("行星A", Config.planet, Vector2.ZERO))
	if not Config.planet_b.is_empty():
		var second: Dictionary = Config.planet_b
		bodies.append(_body_from_config("行星B", second, Vector2(float(second.center_x_km), float(second.center_y_km))))
	focus_index = 0
	gravity_radius = float(bodies[0].gravity_radius_km)

func _body_from_config(label: String, data: Dictionary, center_value: Vector2) -> Dictionary:
	var radius: float = float(data.radius_km)
	var thickness: float = float(data.field_thickness_km)
	var field_top: float = radius + thickness
	var gravity: float = float(data.gravity_m_s2)
	return {
		"name": label,
		"center": center_value,
		"radius_km": radius,
		"field_top_km": field_top,
		"gravity_m_s2": gravity,
		"mu": gravity / Units.METERS_PER_KM * field_top * field_top,
		"gravity_radius_km": float(data.gravity_radius_km),
	}

func body_at(index: int) -> Dictionary:
	if bodies.is_empty():
		return {}
	return bodies[clampi(index, 0, bodies.size() - 1)]

func focus_body() -> Dictionary:
	return body_at(focus_index)

func focus_center() -> Vector2:
	var body: Dictionary = focus_body()
	if body.is_empty():
		return Vector2.ZERO
	var center_value: Vector2 = body.center
	return center_value

func focus_mu() -> float:
	var body: Dictionary = focus_body()
	if body.is_empty():
		return Orbit.MU
	return float(body.mu)

func focus_field_top() -> float:
	var body: Dictionary = focus_body()
	if body.is_empty():
		return Units.FIELD_TOP_RADIUS_KM
	return float(body.field_top_km)

func focus_planet_radius() -> float:
	var body: Dictionary = focus_body()
	if body.is_empty():
		return Units.PLANET_RADIUS_KM
	return float(body.radius_km)

## 飞船相对当前焦点天体中心的位置；轨道元素始终在该局部坐标系内解析。
func local_position() -> Vector2:
	return ship.position - focus_center()

func has_second_planet() -> bool:
	return bodies.size() > 1

func reset() -> void:
	if is_instance_valid(combat):
		combat.reset_battle()
	if speed_dragging:
		speed_cancelled = true
	speed_dragging = false
	speed_limited = false
	speed_snapped = false
	speed_ignore_press_value = false
	angle_cancelled = angle_dragging
	angle_dragging = false
	angle_limited = false
	angle_available = false
	angle_ignore_press_value = false
	heading_start = 0.0
	heading_span = 0.0
	heading_request = 0.0
	angle_start_speed = 0.0
	orbit_direction = 1.0
	dragging = false
	circle_snapped = false
	selected_handle = -1
	manually_paused = false
	motion_mode = "ORBIT"
	focus_index = 0
	gravity_radius = float(focus_body().gravity_radius_km)
	orbit_acquired = true
	capture_remaining = 0.0
	capture_elapsed = 0.0
	pending_simulation_time = 0.0
	flight.cancel()
	navigation_feedback = ""
	orbit = Orbit.make(initial_radius, 0.0, 0.0)
	preview = orbit.duplicate()
	mean_anomaly = 0.5
	elapsed_simulation = 0.0
	last_delta_v = 0.0
	turnaround_cooldown = 0.0
	camera.zoom = Vector2.ONE * initial_zoom
	_refresh_ship()
	_refresh_geometry()
	_update_hud()
	if is_instance_valid(combat):
		combat.refresh_visuals()
	reset_completed.emit()

func _physics_process(delta: float) -> void:
	if not dragging and not speed_dragging and not angle_dragging and not manually_paused and motion_mode != "COLLISION":
		if not get_tree().paused and (not is_instance_valid(combat) or not combat.dead):
			turnaround_cooldown = maxf(0.0, turnaround_cooldown - delta)
		if is_instance_valid(combat) and not combat.dead:
			combat.advance_cooldowns(delta)
		speed_limited = false
		angle_limited = false
		var remaining: float = delta * simulation_speed + pending_simulation_time
		pending_simulation_time = 0.0
		var iterations: int = 0
		while remaining > 0.000000001 and iterations < MAX_NUMERICAL_STEPS and not manually_paused:
			var step: float = minf(remaining, 0.25)
			if is_instance_valid(combat):
				step = minf(step, combat.max_step())
			var previous: Vector2 = ship.position
			_advance_motion(step)
			var consumed: float = step - pending_simulation_time
			pending_simulation_time = 0.0
			remaining -= consumed
			elapsed_simulation += consumed
			if is_instance_valid(combat):
				combat.advance(consumed, previous)
			iterations += 1
			if consumed <= 0.0 or motion_mode == "COLLISION":
				break
		pending_simulation_time = remaining
		if remaining > 0.000000001:
			manually_paused = true
			if motion_mode != "COLLISION" and (not is_instance_valid(combat) or not combat.dead):
				navigation_feedback = "模拟步预算已满，剩余时间已保留；请继续"
		_refresh_navigation()
	_update_hud()
	if is_instance_valid(combat):
		combat._update_hud()

func _advance_motion(step: float) -> void:
	if motion_mode == "COLLISION":
		return
	step += pending_simulation_time
	pending_simulation_time = 0.0
	if motion_mode == "ORBIT":
		_advance_orbit(step)
	elif motion_mode == "FREE":
		_advance_free(step)
	elif motion_mode in ["NUMERICAL", "CAPTURE_PREP", "CAPTURE_BURN", "CAPTURE_FAILED"]:
		_advance_numerical(step)
	ship.rotation = velocity.angle() if velocity.length_squared() > 0.000000001 else ship.rotation

func _advance_orbit(step: float) -> void:
	var n: float = sqrt(focus_mu() / pow(float(orbit.a), 3.0))
	var local: Vector2 = local_position()
	var exit_time: float = INF
	if local.length() > gravity_radius + 0.0001:
		exit_time = 0.0
	elif float(orbit.e) > 0.0 and float(orbit.a) * (1.0 + float(orbit.e)) > gravity_radius:
		var eccentric_exit: float = acos(clampf((1.0 - gravity_radius / float(orbit.a)) / float(orbit.e), -1.0, 1.0)) * orbit_direction
		var exit_mean: float = eccentric_exit - float(orbit.e) * sin(eccentric_exit)
		var phase_distance: float = fposmod((exit_mean - mean_anomaly) * orbit_direction, TAU)
		exit_time = phase_distance / n
		if local.length() >= gravity_radius - 0.0001 and local.dot(velocity) > 0.0:
			exit_time = 0.0
	if exit_time <= step:
		mean_anomaly = wrapf(mean_anomaly + orbit_direction * n * exit_time, -PI, PI)
		_refresh_ship()
		motion_mode = "FREE"
		orbit_acquired = false
		flight.set_state(ship.position, velocity)
		navigation_feedback = "已离开引力范围，保留边界速度惯性飞行"
		_refresh_geometry()
		_advance_free(step - exit_time)
	else:
		mean_anomaly = wrapf(mean_anomaly + orbit_direction * n * step, -PI, PI)
		_refresh_ship()

## 遍历全部天体，返回最早的入球时刻与天体下标；无入球时为 {time: INF, index: -1}。
func _entry_time(p: Vector2, v: Vector2, limit: float) -> Dictionary:
	var best_time: float = INF
	var best_index: int = -1
	for index in range(bodies.size()):
		var body: Dictionary = bodies[index]
		var center_point: Vector2 = body.center
		var candidate: float = _body_entry_time(p - center_point, v, float(body.gravity_radius_km), limit)
		if candidate < best_time:
			best_time = candidate
			best_index = index
	return {"time": best_time, "index": best_index}

func _body_entry_time(p: Vector2, v: Vector2, radius: float, limit: float) -> float:
	var vv: float = float(v.x) * v.x + float(v.y) * v.y
	if vv <= 0.0:
		return INF
	var pv: float = float(p.x) * v.x + float(p.y) * v.y
	var cross: float = float(p.x) * v.y - float(p.y) * v.x
	var rr_vv: float = radius * radius * vv
	var discriminant: float = rr_vv - cross * cross
	var tolerance: float = 0.000000000001 * maxf(rr_vv, cross * cross)
	if discriminant <= tolerance or pv >= 0.0:
		return INF
	var t: float = (-pv - sqrt(discriminant)) / vv
	return maxf(0.0, t) if t >= -0.0001 and t <= limit else INF

func _advance_free(step: float) -> void:
	if flight.phase != "INERTIAL":
		var remaining: float = flight.advance(step)
		ship.position = flight.position
		velocity = flight.velocity
		if flight.phase == "BOUNDARY":
			_enter_gravity(remaining, flight.entry_body_index)
		return
	var entry: Dictionary = _entry_time(flight.position, flight.velocity, step)
	var entry_time: float = float(entry.time)
	if is_inf(entry_time):
		flight.advance(step)
		ship.position = flight.position
		velocity = flight.velocity
		return
	flight.advance(entry_time)
	ship.position = flight.position
	velocity = flight.velocity
	_enter_gravity(step - entry_time, int(entry.index))

## body_index < 0 时保持当前焦点；跨球交接只切换焦点与影响球半径，速度不变。
func _enter_gravity(remaining: float, body_index: int = -1) -> void:
	flight.cancel()
	if body_index >= 0 and body_index < bodies.size():
		focus_index = body_index
	gravity_radius = float(focus_body().gravity_radius_km)
	motion_mode = "CAPTURE_PREP"
	orbit_acquired = false
	capture_remaining = CAPTURE_PREP_SECONDS
	capture_elapsed = 0.0
	var local: Vector2 = local_position()
	capture_direction = -1.0 if local.cross(velocity) < 0.0 else 1.0
	navigation_feedback = "入轨预备：引力飞行后开始有限推力圆化"
	_refresh_geometry()
	_advance_numerical(remaining)

## 引力指向指定天体（默认当前焦点）的中心；场顶以内按恒强场。
func _gravity(p: Vector2, body_index: int = -1) -> Vector2:
	var body: Dictionary = body_at(focus_index if body_index < 0 else body_index)
	if body.is_empty():
		return Vector2.ZERO
	var center_point: Vector2 = body.center
	var offset: Vector2 = p - center_point
	var radius: float = offset.length()
	if radius <= 0.000001:
		return Vector2.ZERO
	var top: float = float(body.field_top_km)
	var magnitude: float = float(body.mu) / maxf(radius * radius, top * top)
	return -offset / radius * magnitude

func _advance_numerical(step: float) -> void:
	var remaining: float = step
	var count: int = 0
	while remaining > 0.000000001 and count < MAX_NUMERICAL_STEPS:
		count += 1
		var h: float = minf(remaining, minf(0.25, maxf(0.0001, local_position().length() / maxf(velocity.length(), 0.001) * 0.01)))
		if motion_mode == "CAPTURE_PREP":
			h = minf(h, capture_remaining)
		var p: Vector2 = ship.position
		var thrust: Vector2 = Vector2.ZERO
		if motion_mode == "CAPTURE_BURN":
			var local: Vector2 = p - focus_center()
			var r: float = local.length()
			var tangent: Vector2 = Vector2(-local.y, local.x).normalized() * capture_direction
			var desired: Vector2 = tangent * sqrt(focus_mu() / maxf(r, focus_field_top()))
			var correction: Vector2 = desired - velocity
			thrust = correction.limit_length(flight.max_acceleration * h) / h
		var a: Vector2 = _gravity(p) + thrust
		var next: Vector2 = p + velocity * h + a * (0.5 * h * h)
		var contact: float = _surface_contact_time(p, velocity, a, h)
		if not is_inf(contact):
			ship.position = p + velocity * contact + a * (0.5 * contact * contact)
			velocity = Vector2.ZERO
			motion_mode = "COLLISION"
			manually_paused = true
			pending_simulation_time = remaining - contact
			flight.cancel()
			navigation_feedback = "飞船撞击行星表面，模拟已停止；按 R 重置"
			_refresh_geometry()
			return
		var next_local: Vector2 = next - focus_center()
		if next_local.length() > gravity_radius and next_local.dot(velocity) > 0.0:
			var lo: float = 0.0
			var hi: float = h
			for i in range(30):
				var mid: float = (lo + hi) * 0.5
				if (p + velocity * mid + a * (0.5 * mid * mid) - focus_center()).length() > gravity_radius:
					hi = mid
				else:
					lo = mid
			h = (lo + hi) * 0.5
			next = p + velocity * h + a * (0.5 * h * h)
			velocity += (a + _gravity(next) + thrust) * (0.5 * h)
			ship.position = next
			var capture_was_active: bool = motion_mode in ["CAPTURE_PREP", "CAPTURE_BURN"]
			motion_mode = "FREE"
			orbit_acquired = false
			if capture_was_active:
				navigation_feedback = "自动入轨失败：飞船脱离引力范围"
			flight.set_state(next, velocity)
			_refresh_geometry()
			_advance_free(remaining - h)
			return
		velocity += (a + _gravity(next) + thrust) * (0.5 * h)
		ship.position = next
		remaining -= h
		if motion_mode == "CAPTURE_PREP":
			capture_remaining = maxf(0.0, capture_remaining - h)
			if capture_remaining <= 0.000000001:
				motion_mode = "CAPTURE_BURN"
				navigation_feedback = "入轨调整：有限推力持续圆化"
		elif motion_mode == "CAPTURE_BURN":
			capture_elapsed += h
			if _try_finish_capture():
				_advance_orbit(remaining)
				return
			if capture_elapsed >= CAPTURE_TIMEOUT:
				motion_mode = "CAPTURE_FAILED"
				navigation_feedback = "自动入轨失败：在允许时间内未达到可行圆轨道"
	pending_simulation_time += remaining
	if remaining > 0.000000001:
		manually_paused = true
		navigation_feedback = "数值推进达到单帧预算，安全暂停；空格继续消化剩余时间"

func _try_finish_capture() -> bool:
	var local: Vector2 = local_position()
	var recovered: Dictionary = Orbit.from_state(local, velocity, local.angle(), focus_mu())
	if recovered.is_empty() or float(recovered.orbit.e) > 0.000001:
		return false
	var radius: float = local.length()
	if radius < Orbit.MIN_PERIAPSIS or radius > minf(Orbit.MAX_A, gravity_radius):
		return false
	var tangent: Vector2 = Vector2(-local.y, local.x).normalized() * capture_direction
	var desired: Vector2 = tangent * sqrt(focus_mu() / radius)
	if velocity.distance_to(desired) > 0.0000005:
		return false
	# 仅在状态已达到浮点精度圆轨道时衔接解析运动。
	orbit = Orbit.make(radius, 0.0, local.angle())
	preview = orbit.duplicate()
	mean_anomaly = 0.0
	orbit_direction = capture_direction
	motion_mode = "ORBIT"
	orbit_acquired = true
	navigation_feedback = "自动入轨完成：已进入圆轨道"
	_refresh_geometry()
	return true

func _surface_contact_time(p: Vector2, v: Vector2, a: Vector2, h: float) -> float:
	var earliest: float = INF
	for body: Dictionary in bodies:
		var center_point: Vector2 = body.center
		var contact: float = _body_surface_contact_time(p - center_point, v, a, h, float(body.radius_km))
		earliest = minf(earliest, contact)
	return earliest

func _body_surface_contact_time(p: Vector2, v: Vector2, a: Vector2, h: float, radius: float) -> float:
	if p.length() <= radius:
		return 0.0
	var end: Vector2 = p + v * h + a * (0.5 * h * h)
	if is_inf(_body_surface_contact_fraction(p, end, radius)) and end.length() > radius:
		return INF
	# 小步轨迹在表面附近的半径先减后增；先定位最小半径，再二分首次接触。
	var left: float = 0.0
	var right: float = h
	for i in range(36):
		var t1: float = (left * 2.0 + right) / 3.0
		var t2: float = (left + right * 2.0) / 3.0
		if (p + v * t1 + a * (0.5 * t1 * t1)).length_squared() < (p + v * t2 + a * (0.5 * t2 * t2)).length_squared():
			right = t2
		else:
			left = t1
	var minimum_time: float = h if end.length() <= radius else (left + right) * 0.5
	if (p + v * minimum_time + a * (0.5 * minimum_time * minimum_time)).length() > radius:
		return INF
	left = 0.0
	right = minimum_time
	for i in range(40):
		var middle: float = (left + right) * 0.5
		if (p + v * middle + a * (0.5 * middle * middle)).length() <= radius:
			right = middle
		else:
			left = middle
	return (left + right) * 0.5

func _surface_contact_fraction(p: Vector2, next: Vector2) -> float:
	var earliest: float = INF
	for body: Dictionary in bodies:
		var center_point: Vector2 = body.center
		var fraction: float = _body_surface_contact_fraction(p - center_point, next - center_point, float(body.radius_km))
		earliest = minf(earliest, fraction)
	return earliest

func _body_surface_contact_fraction(p: Vector2, next: Vector2, radius: float) -> float:
	var pp: float = float(p.x) * p.x + float(p.y) * p.y
	if pp <= radius * radius:
		return 0.0
	var d: Vector2 = next - p
	var dd: float = float(d.x) * d.x + float(d.y) * d.y
	if dd <= 0.0:
		return INF
	var pd: float = float(p.x) * d.x + float(p.y) * d.y
	var discriminant: float = pd * pd - dd * (pp - radius * radius)
	if discriminant < 0.0:
		return INF
	var fraction: float = (-pd - sqrt(discriminant)) / dd
	return fraction if fraction >= 0.0 and fraction <= 1.0 else INF

func _change_free_max_speed(value: float) -> void:
	if motion_mode != "FREE" or not is_finite(value) or value <= 0.0:
		return
	var previous: float = flight.max_speed
	flight.max_speed = value
	if flight.has_target and flight.phase != "ARRIVED":
		if not _plan_flight(flight.requested_target):
			flight.max_speed = previous
			free_max_slider.set_value_no_signal(previous)
			navigation_feedback = flight.last_error
		else:
			navigation_feedback = "速度上限已调整，从当前速度重新制动规划"
	_update_hud()

## 把全部天体转成避让数据：影响球边界逃逸速度的 0.9 倍作为入球峰值上限。
func _plan_flight(destination: Vector2) -> bool:
	var payload: Array[Dictionary] = []
	for body: Dictionary in bodies:
		var radius: float = float(body.gravity_radius_km)
		var mu: float = float(body.mu)
		var limit: float = 0.9 * sqrt(2.0 * mu / radius) if radius > 0.0 and mu > 0.0 else 0.0
		payload.append({"center": body.center, "radius": radius, "entry_limit": limit})
	return flight.plan_bodies(destination, payload)

func set_free_target(world_position: Vector2) -> bool:
	if motion_mode != "FREE" or local_position().length() < gravity_radius - gravity_radius * 0.0000002:
		return false
	var accepted: bool = _plan_flight(world_position)
	navigation_feedback = ("航线进入引力圈，将以可达速度连续穿越边界" if flight.boundary_crossing else "") if accepted else flight.last_error
	_refresh_navigation()
	_update_hud()
	return accepted

func cancel_free_flight() -> void:
	if motion_mode != "FREE":
		return
	flight.cancel()
	navigation_feedback = "已取消目标，保持当前速度惯性飞行"
	_refresh_navigation()
	_update_hud()

func _over_hud(screen_position: Vector2) -> bool:
	for child in $HUD/Layout.get_children():
		if child is Control and child.visible and child.get_global_rect().has_point(screen_position):
			return true
	return false

func _refresh_navigation() -> void:
	target_marker.visible = motion_mode == "FREE" and flight.has_target
	route_line.visible = target_marker.visible
	if target_marker.visible:
		target_marker.position = flight.requested_target
		target_marker.scale = Vector2.ONE / camera.zoom.x
		route_line.points = flight.route
		route_line.width = 2.0 / camera.zoom.x

func _color_orbit(line: Line2D, elements: Dictionary, inside: Color, offset: Vector2 = Vector2.ZERO) -> void:
	var original: PackedVector2Array = Orbit.polyline(elements)
	var local_points := PackedVector2Array([original[0]])
	for i in range(1, original.size()):
		var p: Vector2 = original[i - 1]
		var d: Vector2 = original[i] - p
		var dd: float = d.length_squared()
		var pd: float = p.dot(d)
		var discriminant: float = pd * pd - dd * (p.length_squared() - gravity_radius * gravity_radius)
		if discriminant >= 0.0 and dd > 0.0:
			for root in [(-pd - sqrt(discriminant)) / dd, (-pd + sqrt(discriminant)) / dd]:
				if root > 0.0000001 and root < 0.9999999:
					local_points.append(p + d * root)
		local_points.append(original[i])
	var points := PackedVector2Array()
	points.resize(local_points.size())
	for i in range(local_points.size()):
		points[i] = local_points[i] + offset
	line.points = points
	var total: float = 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var outside := Color(0.75, 0.45, 0.85, inside.a)
	var colors := PackedColorArray()
	var offsets := PackedFloat32Array()
	var distance: float = 0.0
	var previous := Color.TRANSPARENT
	for i in range(1, points.size()):
		var color: Color = inside if ((points[i] + points[i - 1]) * 0.5 - offset).length() <= gravity_radius else outside
		if color != previous:
			offsets.append(distance / maxf(total, 0.000001))
			colors.append(color)
			previous = color
		distance += points[i].distance_to(points[i - 1])
	offsets.append(1.0)
	colors.append(previous)
	gradient.offsets = offsets
	gradient.colors = colors
	line.gradient = gradient

func _refresh_ship() -> void:
	var state: Dictionary = Orbit.state_at(orbit, mean_anomaly, orbit_direction, focus_mu())
	ship.position = state.position + focus_center()
	velocity = state.velocity
	ship.rotation = velocity.angle()

func _can_turnaround() -> bool:
	return turnaround_cooldown <= 0.0 and not manually_paused and not get_tree().paused and not is_orbit_editing() and motion_mode in ["ORBIT", "NUMERICAL", "CAPTURE_PREP", "CAPTURE_BURN", "CAPTURE_FAILED"] and velocity.is_finite() and velocity.length_squared() > 0.000000000001 and (not is_instance_valid(combat) or not combat.dead)

func turnaround() -> void:
	if not _can_turnaround():
		return
	velocity = -velocity
	last_delta_v = 2.0 * velocity.length()
	if motion_mode == "ORBIT":
		orbit_direction = -orbit_direction
	else:
		motion_mode = "NUMERICAL"
		capture_remaining = 0.0
		capture_elapsed = 0.0
		orbit_acquired = false
		navigation_feedback = "已调头，自动入轨取消"
	ship.rotation = velocity.angle()
	turnaround_cooldown = float(Config.ship.turnaround_cooldown_real_s)
	_refresh_geometry()
	_refresh_navigation()
	_update_hud()

func begin_speed_drag() -> void:
	if motion_mode != "ORBIT" or dragging or speed_dragging or angle_dragging:
		return
	speed_dragging = true
	speed_cancelled = false
	speed_limited = false
	speed_snapped = orbit.e == 0.0
	speed_ignore_press_value = false
	anchor = local_position()
	old_velocity = velocity
	speed_start = velocity.length()
	speed_bounds = Orbit.speed_interval(anchor, old_velocity, focus_mu())
	# 包含当前合法边界速率，按下不产生微小脉冲。
	speed_bounds.x = minf(speed_bounds.x, speed_start)
	speed_bounds.y = maxf(speed_bounds.y, speed_start)
	preview = orbit.duplicate()
	anchor_marker.position = anchor + focus_center()
	_refresh_geometry()
	_update_hud()

func change_speed(requested: float) -> void:
	if motion_mode != "ORBIT" or dragging or speed_cancelled or angle_dragging:
		return
	var keyboard_edit: bool = not speed_dragging
	if keyboard_edit:
		begin_speed_drag()
	# 原生滑块按下时会把坐标取整；点击拇指且尚未移动不能改速度方向。
	if speed_ignore_press_value or (absf(requested - speed_start) < 0.0000001 and preview == orbit):
		_update_hud()
		if keyboard_edit:
			finish_speed_drag(true)
		return
	# 必须先按原始请求判定吸附；圆速可能位于旧方向合法区间之外。
	var distance_px: float = absf(_slider_x(requested) - _slider_x(circular_speed)) * speed_slider.get_screen_transform().x.length()
	var snap_limit: float = SPEED_SNAP_EXIT_PX if speed_snapped else SPEED_SNAP_ENTER_PX
	speed_snapped = circular_available and (absf(requested - circular_speed) <= SPEED_KEYBOARD_SNAP if keyboard_edit else distance_px <= snap_limit)
	if speed_snapped:
		preview = Orbit.make(clampf(anchor.length(), Orbit.MIN_PERIAPSIS, Orbit.MAX_A), 0.0, orbit.angle)
		speed_limited = false
	else:
		var actual: float = clampf(requested, speed_bounds.x, speed_bounds.y)
		speed_limited = absf(actual - requested) > 0.0000001 or absf(actual - speed_bounds.x) < 0.000001 or absf(actual - speed_bounds.y) < 0.000001
		var recovered: Dictionary = Orbit.from_state(anchor, old_velocity.normalized() * actual, orbit.angle, focus_mu())
		if not recovered.is_empty():
			preview = recovered.orbit
		else:
			speed_limited = true
	_refresh_geometry()
	_update_hud()
	if keyboard_edit:
		finish_speed_drag(true)

func finish_speed_drag(commit: bool) -> void:
	if not speed_dragging:
		return
	if commit:
		velocity = _preview_velocity()
		last_delta_v = velocity.distance_to(old_velocity)
		orbit = preview.duplicate()
		orbit_direction = 1.0 if anchor.cross(old_velocity) >= 0.0 else -1.0
		mean_anomaly = Orbit.mean_at(orbit, anchor)
		ship.position = anchor + focus_center()
		ship.rotation = velocity.angle()
	if not commit:
		speed_cancelled = true
		speed_limited = false
	speed_dragging = false
	speed_snapped = false
	speed_ignore_press_value = false
	_refresh_geometry()
	_update_hud()

func is_orbit_editing() -> bool:
	return dragging or speed_dragging or angle_dragging

func begin_angle_drag() -> void:
	if motion_mode != "ORBIT" or dragging or speed_dragging or angle_dragging:
		return
	anchor = local_position()
	old_velocity = velocity
	angle_start_speed = old_velocity.length()
	# flight_path_angle 已按 direction 构造切向，返回带符号航迹角，不能再乘方向。
	heading_start = Orbit.flight_path_angle(anchor, old_velocity, orbit_direction)
	_refresh_angle_bounds()
	if heading_span <= 0.0:
		angle_limited = true
		_update_hud()
		return
	angle_dragging = true
	angle_cancelled = false
	angle_limited = false
	angle_ignore_press_value = false
	preview = orbit.duplicate()
	heading_request = heading_start
	anchor_marker.position = anchor + focus_center()
	_refresh_geometry()
	_update_hud()

func change_angle(requested: float) -> void:
	if motion_mode != "ORBIT" or dragging or angle_cancelled or not is_finite(requested):
		return
	var keyboard_edit: bool = not angle_dragging
	if keyboard_edit:
		begin_angle_drag()
		if not angle_dragging:
			return
	if heading_span <= 0.0:
		angle_limited = true
		_update_hud()
		if keyboard_edit:
			finish_angle_drag(false)
		return
	if angle_ignore_press_value or (absf(requested - heading_start) < 0.0000001 and preview == orbit):
		_update_hud()
		if keyboard_edit:
			finish_angle_drag(true)
		return
	_angle_preview(requested)
	_refresh_geometry()
	_update_hud()
	if keyboard_edit:
		finish_angle_drag(true)

func _angle_preview(gamma: float) -> void:
	var bounded: float = clampf(gamma, -heading_span, heading_span)
	angle_limited = absf(bounded - gamma) > 0.0000001
	var recovered: Dictionary = _heading_state(bounded)
	if recovered.is_empty():
		# 解析夹限后仍不可解：以当前偏角为基准向请求值二分回退。
		# 基准点自身对应原轨道必然合法，逆行时也不会退到镜像解。
		angle_limited = true
		var low: float = 0.0
		var high: float = 1.0
		var best: Dictionary = _heading_state(heading_start)
		for i in range(9):
			var middle: float = (low + high) * 0.5
			var candidate: Dictionary = _heading_state(lerpf(heading_start, bounded, middle))
			if candidate.is_empty():
				high = middle
			else:
				low = middle
				best = candidate
		if best.is_empty():
			heading_request = heading_start
			return
		bounded = lerpf(heading_start, bounded, low)
		recovered = best
	heading_request = bounded
	preview = recovered.orbit

func _heading_state(gamma: float) -> Dictionary:
	var direction: float = 1.0 if anchor.cross(old_velocity) >= 0.0 else -1.0
	var rotated: Vector2 = Orbit.heading_velocity(anchor, angle_start_speed, gamma, direction)
	if rotated.length_squared() <= 0.0:
		return {}
	return Orbit.from_state(anchor, rotated, orbit.angle, focus_mu())

func finish_angle_drag(commit: bool) -> void:
	if not angle_dragging:
		return
	if commit and preview != orbit:
		velocity = _preview_velocity()
		last_delta_v = velocity.distance_to(old_velocity)
		orbit = preview.duplicate()
		orbit_direction = 1.0 if anchor.cross(old_velocity) >= 0.0 else -1.0
		mean_anomaly = Orbit.mean_at(orbit, anchor)
		# a 不变，位置也不跳：只把速度方向交给新拱线。
		ship.position = anchor + focus_center()
		ship.rotation = velocity.angle()
		heading_start = heading_request
	if not commit:
		angle_cancelled = true
		angle_limited = false
		heading_request = heading_start
	angle_dragging = false
	angle_ignore_press_value = false
	_refresh_geometry()
	_update_hud()

func _refresh_angle_bounds() -> void:
	heading_span = 0.0
	if orbit.is_empty() or float(orbit.a) <= 0.0:
		return
	var radius: float = anchor.length() if angle_dragging else local_position().length()
	heading_span = Orbit.heading_limit(radius, float(orbit.a))

func _angle_slider_x(value: float) -> float:
	var grabber_width: float = angle_slider.get_theme_icon("grabber").get_width()
	var half_width: float = grabber_width * 0.5
	var usable_width: float = maxf(1.0, angle_slider.size.x - grabber_width)
	var span: float = maxf(heading_span, HEADING_SPAN_FLOOR)
	return half_width + clampf((value + span) / (span * 2.0), 0.0, 1.0) * usable_width

func _position_angle_marker() -> void:
	if not is_instance_valid(angle_base_marker):
		return
	angle_base_marker.visible = angle_available
	angle_base_marker.position = Vector2(_angle_slider_x(0.0), angle_slider.size.y * 0.5)

func begin_drag(_index: int, _mouse_world: Vector2) -> void:
	return

func update_drag(mouse_world: Vector2) -> void:
	if not dragging:
		return
	var fitted: Dictionary = Orbit.fit_axis(anchor, mouse_world - focus_center() + drag_offset, selected_handle, drag_start, preview, circle_snapped, camera.zoom.x)
	preview = fitted.orbit
	circle_snapped = fitted.snapped
	assert(Orbit.residual(preview, anchor) < 0.00001, "Preview must pass through the frozen ship")
	_refresh_geometry()
	_update_hud()

func finish_drag(commit: bool) -> void:
	if not dragging:
		return
	if commit:
		var new_velocity: Vector2 = _preview_velocity()
		last_delta_v = new_velocity.distance_to(old_velocity)
		orbit = preview.duplicate()
		orbit_direction = 1.0 if anchor.cross(old_velocity) >= 0.0 else -1.0
		mean_anomaly = Orbit.mean_at(orbit, anchor)
		# Preserve position exactly at the impulse. Next tick follows the new conic.
		velocity = new_velocity
		ship.position = anchor + focus_center()
		ship.rotation = velocity.angle()
		assert(Orbit.residual(orbit, ship.position - focus_center()) < 0.00001)
	dragging = false
	selected_handle = -1
	_refresh_geometry()
	_update_hud()

func toggle_pause() -> void:
	if is_instance_valid(combat) and combat.dead:
		return
	if dragging:
		finish_drag(false)
	if speed_dragging:
		finish_speed_drag(false)
	if angle_dragging:
		finish_angle_drag(false)
	manually_paused = not manually_paused
	_update_hud()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if dragging:
			finish_drag(false)
		if speed_dragging:
			finish_speed_drag(false)
		if angle_dragging:
			finish_angle_drag(false)

func _input(event: InputEvent) -> void:
	# 在原生HSlider可能发送value_changed之前冻结状态，区分点击与键盘编辑。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and speed_slider.editable and speed_slider.get_global_rect().has_point(event.position):
		begin_speed_drag()
		speed_press_position = event.position
		var local_x: float = event.position.x - speed_slider.global_position.x
		speed_ignore_press_value = absf(local_x - _slider_x(speed_start)) <= speed_slider.get_theme_icon("grabber").get_width() * 0.5
	elif event is InputEventMouseMotion and speed_dragging and absf(event.position.x - speed_press_position.x) > 0.5:
		speed_ignore_press_value = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and angle_slider.editable and angle_slider.get_global_rect().has_point(event.position):
		begin_angle_drag()
		angle_press_position = event.position
		var angle_local_x: float = event.position.x - angle_slider.global_position.x
		angle_ignore_press_value = absf(angle_local_x - _angle_slider_x(heading_start)) <= angle_slider.get_theme_icon("grabber").get_width() * 0.5
	elif event is InputEventMouseMotion and angle_dragging and absf(event.position.x - angle_press_position.x) > 0.5:
		angle_ignore_press_value = false
	# Release is handled before GUI dispatch so releasing over the HUD cannot stick.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and dragging:
		update_drag(get_viewport().get_canvas_transform().affine_inverse() * event.position)
		finish_drag(true)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and angle_dragging:
		# 原生 HSlider 在指针移出控件后可能不再发出 drag_ended，松开必须在此收尾；
		# 不吞掉事件，让控件自身清理拖动状态。
		finish_angle_drag(true)
	elif event is InputEventMouseMotion and dragging:
		update_drag(get_viewport().get_canvas_transform().affine_inverse() * event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if motion_mode == "ORBIT" and angle_slider.has_focus() and not dragging and not speed_dragging and not angle_dragging and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_END]:
			var current_heading: float = Orbit.flight_path_angle(local_position(), velocity, orbit_direction)
			var requested: float = current_heading + (-HEADING_KEY_STEP if event.keycode == KEY_LEFT else HEADING_KEY_STEP)
			if event.keycode == KEY_HOME:
				requested = -heading_span
			elif event.keycode == KEY_END:
				requested = heading_span
			angle_cancelled = false
			change_angle(clampf(requested, -heading_span, heading_span))
			get_viewport().set_input_as_handled()
		elif motion_mode == "ORBIT" and speed_slider.has_focus() and not dragging and not speed_dragging and not angle_dragging and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_END]:
			var requested: float = velocity.length() + (-1.0 if event.keycode == KEY_LEFT else 1.0) / Units.METERS_PER_KM
			if event.keycode == KEY_HOME:
				requested = speed_bounds.x
			elif event.keycode == KEY_END:
				requested = speed_bounds.y
			speed_cancelled = false
			change_speed(clampf(requested, speed_bounds.x, speed_bounds.y))
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and angle_dragging:
			finish_angle_drag(false)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and speed_dragging:
			finish_speed_drag(false)
		elif event.keycode == KEY_ESCAPE and dragging:
			finish_drag(false)
		elif event.keycode == KEY_ESCAPE and motion_mode == "FREE":
			cancel_free_flight()
		elif event.keycode == KEY_SPACE and (not is_instance_valid(combat) or not combat.dead):
			toggle_pause()
		elif event.keycode == KEY_R:
			reset()

func _unhandled_input(event: InputEvent) -> void:
	if speed_dragging or angle_dragging:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
			if not _over_hud(event.position) and is_instance_valid(combat) and combat.click(mouse):
				get_viewport().set_input_as_handled()
				return
			if motion_mode == "FREE" and not _over_hud(event.position):
				set_free_target(mouse)
				get_viewport().set_input_as_handled()
				return
			return
		elif event.button_index == MOUSE_BUTTON_RIGHT and dragging:
			finish_drag(false)
		elif event.button_index == MOUSE_BUTTON_RIGHT and motion_mode == "FREE":
			cancel_free_flight()
		elif not dragging and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor: float = 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
			var zoom_value: float = clampf(camera.zoom.x * factor, 0.22, 2.0)
			camera.zoom = Vector2.ONE * zoom_value
			_refresh_geometry()
			if is_instance_valid(combat):
				combat.refresh_visuals()

func _refresh_geometry() -> void:
	var offset: Vector2 = focus_center()
	current_line.visible = orbit_acquired and motion_mode == "ORBIT"
	_color_orbit(current_line, orbit, Color(0.25, 0.65, 0.88, 0.85), offset)
	var ring := PackedVector2Array()
	for i in range(257):
		ring.append(Vector2.from_angle(TAU * float(i) / 256.0) * gravity_radius + offset)
	gravity_line.points = ring
	gravity_line.width = 1.5 / camera.zoom.x
	_refresh_navigation()
	var editing: bool = dragging or speed_dragging or angle_dragging
	preview_line.visible = editing
	anchor_marker.visible = editing
	velocity_line.visible = editing
	new_velocity_line.visible = editing
	if editing:
		_color_orbit(preview_line, preview, Color(1.0, 0.7, 0.27, 1.0), offset)
		anchor_marker.position = anchor + offset
		var visual_scale: float = VELOCITY_VISUAL_SCALE / camera.zoom.x
		velocity_line.points = PackedVector2Array([anchor + offset, anchor + offset + old_velocity * visual_scale])
		new_velocity_line.points = PackedVector2Array([anchor + offset, anchor + offset + _preview_velocity() * visual_scale])
		velocity_line.width = 2.0 / camera.zoom.x
		new_velocity_line.width = 2.0 / camera.zoom.x
	var shown: Dictionary = preview if dragging or speed_dragging or angle_dragging else orbit
	for i in range(4):
		handles[i].visible = false
		handles[i].position = Orbit.endpoint(shown, i) + offset
		handles[i].scale = Vector2.ONE / camera.zoom.x
		handles[i].modulate = Color(1.0, 0.76, 0.35) if dragging and selected_handle == i else Color.WHITE
	var ellipse_center: Vector2 = (Orbit.endpoint(shown, 0) + Orbit.endpoint(shown, 2)) * 0.5 + offset
	axes_line.visible = false
	axes_line.points = PackedVector2Array([Orbit.endpoint(shown, 0) + offset, Orbit.endpoint(shown, 2) + offset, ellipse_center, Orbit.endpoint(shown, 1) + offset, Orbit.endpoint(shown, 3) + offset])
	current_line.width = 1.8 / camera.zoom.x
	preview_line.width = 2.2 / camera.zoom.x

func _preview_velocity() -> Vector2:
	var direction: float = 1.0 if anchor.cross(old_velocity) >= 0.0 else -1.0
	return Orbit.velocity_at(preview, anchor, direction, focus_mu())

func _slider_x(value: float) -> float:
	var grabber_width: float = speed_slider.get_theme_icon("grabber").get_width()
	var half_width: float = grabber_width * 0.5
	var usable_width: float = maxf(1.0, speed_slider.size.x - grabber_width)
	var span: float = slider_display_bounds.y - slider_display_bounds.x
	return half_width + ((value - slider_display_bounds.x) / span if span > 0.0 else 0.5) * usable_width

func _position_circular_marker() -> void:
	if not is_instance_valid(circular_marker):
		return
	circular_marker.visible = circular_available
	circular_marker.position = Vector2(_slider_x(circular_speed), speed_slider.size.y * 0.5)
	circular_marker.modulate = Color(1.0, 0.76, 0.35) if speed_snapped else Color(0.35, 0.9, 0.79)

func _update_angle_hud(shown: Dictionary, dv: float, shown_speed: float, _editing: bool) -> void:
	# 事务期间不重算可行域：a 与 |v| 固定，旋转不改变边界。
	if not angle_dragging:
		_refresh_angle_bounds()
	angle_available = motion_mode == "ORBIT" and heading_span > 0.0 and not shown.is_empty()
	var display_span: float = maxf(heading_span, HEADING_SPAN_FLOOR)
	var heading: float = 0.0
	if motion_mode == "ORBIT":
		heading = heading_request if angle_dragging else Orbit.flight_path_angle(local_position(), velocity, orbit_direction)
	angle_slider.editable = angle_available and not dragging and not speed_dragging
	angle_slider.set_block_signals(true)
	angle_slider.min_value = -display_span
	angle_slider.max_value = display_span
	angle_slider.value = clampf(heading, -display_span, display_span)
	angle_slider.set_block_signals(false)
	_position_angle_marker()
	angle_value.text = "%s%.1f°%s" % ["+" if heading >= 0.0 else "", rad_to_deg(heading), " · 已夹限" if angle_limited else ""]
	if motion_mode != "ORBIT":
		angle_limits.text = "轨道外不可调"
	elif not angle_available:
		angle_limits.text = "无可调余量"
	else:
		angle_limits.text = "范围 ±%.1f°" % rad_to_deg(heading_span)
	angle_readout.text = "Δv %.1f m/s · e %.4f\n近心 %.1f km · 远心 %.1f km" % [Units.speed_to_m_s(dv), float(shown.e), float(shown.a) * (1.0 - float(shown.e)), float(shown.a) * (1.0 + float(shown.e))]

func _update_hud() -> void:
	if not is_node_ready():
		return
	var turnaround_button: Button = $HUD/Layout/SpeedControl/Turnaround
	turnaround_button.visible = motion_mode != "FREE"
	turnaround_button.disabled = not _can_turnaround()
	turnaround_button.text = "调头 · %.1f秒" % turnaround_cooldown if turnaround_cooldown > 0.0 else "调头"
	var shown: Dictionary = preview if dragging or speed_dragging or angle_dragging else orbit
	var editing: bool = dragging or speed_dragging or angle_dragging
	status_label.text = "朝向预览 · 模拟已暂停" if angle_dragging else ("调速预览 · 模拟已暂停" if speed_dragging else ("规划中 · 模拟已暂停" if dragging else ("已暂停" if manually_paused else "运行中 · 开普勒运动")))
	var dv: float = _preview_velocity().distance_to(old_velocity) if editing else last_delta_v
	var shown_speed: float = _preview_velocity().length() if editing else velocity.length()
	speed_slider.editable = not dragging and not angle_dragging and motion_mode == "ORBIT"
	free_max_control.visible = motion_mode == "FREE"
	free_max_label.text = "%.2f m/s" % Units.speed_to_m_s(flight.max_speed)
	if not speed_dragging and motion_mode == "ORBIT":
		speed_bounds = Orbit.speed_interval(local_position(), velocity, focus_mu())
		speed_bounds.x = minf(speed_bounds.x, velocity.length())
		speed_bounds.y = maxf(speed_bounds.y, velocity.length())
	var circular_radius: float = anchor.length() if speed_dragging else local_position().length()
	circular_available = motion_mode == "ORBIT" and circular_radius >= Orbit.MIN_PERIAPSIS - 0.0001 and circular_radius <= Orbit.MAX_A + 0.0001
	if circular_available:
		circular_radius = clampf(circular_radius, Orbit.MIN_PERIAPSIS, Orbit.MAX_A)
	circular_speed = sqrt(focus_mu() / circular_radius) if circular_radius > 0.0 else 0.0
	slider_display_bounds = speed_bounds
	if motion_mode != "ORBIT":
		slider_display_bounds = Vector2(0.0, maxf(maxf(flight.max_speed, shown_speed), 0.001))
	if circular_available:
		slider_display_bounds.x = minf(slider_display_bounds.x, circular_speed)
		slider_display_bounds.y = maxf(slider_display_bounds.y, circular_speed)
	speed_slider.set_block_signals(true)
	speed_slider.min_value = slider_display_bounds.x
	speed_slider.max_value = slider_display_bounds.y
	speed_slider.value = circular_speed if speed_snapped else shown_speed
	speed_slider.set_block_signals(false)
	_position_circular_marker()
	circular_label.text = ("◆ 圆速 %.2f m/s%s" % [Units.speed_to_m_s(circular_speed), " · 已吸附" if speed_snapped else ""]) if circular_available else "圆速不可用"
	speed_label.text = "%.2f m/s%s" % [Units.speed_to_m_s(shown_speed), " · 已夹限" if speed_limited else ""]
	speed_limits.text = "范围 %.2f – %.2f m/s" % [Units.speed_to_m_s(speed_bounds.x), Units.speed_to_m_s(speed_bounds.y)]
	_update_angle_hud(shown, dv, shown_speed, editing)
	var radius: float = local_position().length()
	var planet_radius: float = focus_planet_radius()
	telemetry.text = "轨道参数  /  ORBIT\na  %7.2f km\nb  %7.2f km\ne  %7.4f\n中心距离  %7.2f km\n当前高度  %7.2f km\n近心高度  %7.2f km\n远心高度  %7.2f km\n速度  %7.2f m/s\n周期  %7.2f min\n已过模拟  %7.2f min\nΔv  %7.2f m/s" % [shown.a, float(shown.a) * sqrt(1.0 - shown.e * shown.e), shown.e, radius, radius - planet_radius, shown.a * (1.0 - shown.e) - planet_radius, shown.a * (1.0 + shown.e) - planet_radius, Units.speed_to_m_s(shown_speed), Units.seconds_to_minutes(TAU * sqrt(pow(float(shown.a), 3.0) / focus_mu())), Units.seconds_to_minutes(elapsed_simulation), Units.speed_to_m_s(dv)]
	var body: Dictionary = focus_body()
	var thickness: float = focus_field_top() - planet_radius
	unit_label.text = "1 世界单位 = 1 km · %s · 行星半径 %.0f km · 恒强场厚度 %.0f km\n场顶半径 %.0f km · 场顶 g = %.2f m/s²\n1 现实秒 = %.1f 模拟秒 · 速度箭头为示意比例\n近心安全高度 %.0f km · 当前仅模拟外部开普勒轨道" % [str(body.get("name", "行星A")), planet_radius, thickness, focus_field_top(), float(body.get("gravity_m_s2", Units.FIELD_GRAVITY_M_S2)), simulation_speed, Orbit.MIN_PERIAPSIS - planet_radius]
	if speed_dragging:
		feedback.text = ("圆速吸附 · 保持位置并校正切向方向" if speed_snapped else "调节飞船实际速度 · 保持位置与速度方向") + "\n橙色：调速后轨道 / 蓝色：原轨道\n接近圆速标记吸附 · 继续拖动可离开\n松手执行完整向量 Δv · Esc 取消"
	elif angle_dragging:
		feedback.text = ("固定位置与速率 · 只旋转速度方向" + (" · 已夹限" if angle_limited else "")) + "\n橙色：转向后轨道 / 蓝色：原轨道\n周期与绕行方向不变 · 松手执行 Δv\n方向键 0.25° · Home/End 到边界 · Esc 取消"
	elif dragging:
		var constraint: String = "圆吸附 · 两轴微调至飞船半径" if circle_snapped else ("调整长轴 a · 锁定起始短轴 b" if selected_handle == 0 or selected_handle == 2 else "调整短轴 b · 锁定起始长轴 a")
		feedback.text = "%s\n自动旋转以经过冻结飞船 · 边界停止\n橙色：目标轨道 / 蓝色：原轨道\n松手执行 Δv · Esc / 右键取消" % constraint
	else:
		feedback.text = "调节速度以改变轨道；入圈后自动圆化\n轨道端点拖拽已关闭\n滚轮缩放 · 空格暂停 · R 重置"
	unit_label.text += "\n引力范围 %.0f km · 入轨完成后显示轨道" % gravity_radius
	if motion_mode != "ORBIT":
		var phases: Dictionary = {"INERTIAL": "惯性漂移", "BRAKE": "制动转向", "ACCEL": "加速", "CRUISE": "巡航", "DECEL": "减速", "ARRIVED": "抵达停靠"}
		var state_text: String = "自由飞行 · " + str(phases.get(flight.phase, flight.phase)) if motion_mode == "FREE" else ("碰撞停止 · 行星表面" if motion_mode == "COLLISION" else "引力飞行 · 连续数值推进")
		if motion_mode == "CAPTURE_PREP":
			state_text = "入轨预备 · %.1f 模拟秒" % capture_remaining
		elif motion_mode == "CAPTURE_BURN":
			state_text = "自动入轨 · 有限推力圆化"
		elif motion_mode == "CAPTURE_FAILED":
			state_text = "自动入轨失败 · 引力飞行"
		status_label.text = state_text + (" · 已暂停" if manually_paused else "")
		telemetry.text = "实际飞船状态\n中心距离  %.2f km\n当前高度  %.2f km\n速度  %.2f m/s\n最大加速度  %.2f m/s²\n最大巡航速度  %.2f m/s\n已过模拟  %.2f min\n\n参考椭圆（非实际航线）\na  %.2f km\ne  %.4f" % [radius, radius - planet_radius, Units.speed_to_m_s(shown_speed), flight.max_acceleration * Units.METERS_PER_KM, Units.speed_to_m_s(flight.max_speed), Units.seconds_to_minutes(elapsed_simulation), shown.a, shown.e]
		telemetry.text = telemetry.text.get_slice("\n\n参考椭圆", 0)
		if flight.has_target and motion_mode == "FREE":
			telemetry.text += "\n目标距离  %.2f km" % ship.position.distance_to(flight.requested_target)
		feedback.text = (navigation_feedback + "\n" if not navigation_feedback.is_empty() else "") + "范围外左键设目标 · 可重新指定\n先制动转向，再沿直线加速 / 巡航 / 减速\n航线入圈时以可达速度穿越 · 右键 / Esc 取消\n轨道已隐藏 · 滚轮缩放 · 空格暂停"
		if motion_mode in ["NUMERICAL", "CAPTURE_PREP", "CAPTURE_BURN", "CAPTURE_FAILED"]:
			feedback.text = navigation_feedback + "\n引力飞行使用当前真实位置 / 速度连续推进\n入轨前不显示轨道 · 滚轮缩放 · 空格暂停"
			if pending_simulation_time > 0.0:
				feedback.text += "\n数值步预算已满，待推进 %.2f 模拟秒" % pending_simulation_time
		elif motion_mode == "COLLISION":
			feedback.text = navigation_feedback + "\n碰撞点已保留，速度因撞击归零 · R 重置"
		elif velocity.length() > flight.max_speed + 0.000001:
			feedback.text += "\n继承速度高于巡航上限，制动阶段逐步降速"
		speed_limits.text = "轨道外不可调"
		circular_label.text = "圆速不可用"
		unit_label.text = unit_label.text.replace("当前仅模拟外部开普勒轨道", "范围外无引力，回入按当前状态推进")
