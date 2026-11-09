extends Node2D

const PlanetConfig = preload("res://scripts/simulation_config.gd")

@export_file("*.json") var config_path := "res://data/air_force.json"
@export_node_path("Node2D") var planet_path: NodePath
@onready var start_marker: Marker2D = $Start
@onready var apex_marker: Marker2D = $Apex
@onready var end_marker: Marker2D = $End
@onready var members_root: Node2D = $Members

var config: Dictionary = {}
var valid := false
var elapsed := 0.0
var triggered := false
var members: Array[Dictionary] = []
var visual_progress := -1.0
var visual_zoom := -1.0

func _ready() -> void:
	initialize()

func _process(_delta: float) -> void:
	if not valid:
		return
	var camera := get_viewport().get_camera_2d()
	var zoom := camera.zoom.x if camera != null else 1.0
	var progress := elapsed / float(config.duration_sim_s)
	if is_equal_approx(progress, visual_progress) and is_equal_approx(zoom, visual_zoom):
		return
	visual_progress = progress
	visual_zoom = zoom
	for member in members:
		var body: Node2D = member.node.get_node("Body")
		var trail: Line2D = member.node.get_node("Trail")
		body.scale = Vector2.ONE * (2.4 / maxf(zoom, 0.01))
		trail.width = 2.5 / maxf(zoom, 0.01)
		if triggered and elapsed > 0.0 and member.alive:
			_update_trail(member, elapsed / float(config.duration_sim_s), zoom)

func initialize() -> void:
	valid = false
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		push_error("空军配置无法读取：" + config_path)
		visible = false
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		push_error("空军配置必须是 JSON 对象：" + config_path)
		visible = false
		return
	for key in ["duration_sim_s", "member_spacing_km", "member_radius_km", "member_health", "trigger_distance_km", "collision_damage", "trail_points"]:
		if not data.has(key) or typeof(data[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(data[key])) or float(data[key]) <= 0.0:
			push_error("空军配置数值无效：" + key)
			visible = false
			return
	if int(data.trail_points) != data.trail_points or int(data.trail_points) < 2:
		push_error("空军拖尾点数必须为不小于 2 的整数")
		visible = false
		return
	if not _snap_endpoints():
		push_error("空军航线无效：行星缺失或端点位于行星中心")
		visible = false
		return
	var s := start_marker.position
	var a := apex_marker.position
	var e := end_marker.position
	if not s.is_finite() or not a.is_finite() or not e.is_finite() or (a.x - s.x) * (e.x - a.x) <= 0.0 or a.y >= minf(s.y, e.y):
		push_error("空军航线无效：最高点必须位于两端横坐标之间且高于两端")
		visible = false
		return
	config = data
	valid = true
	visible = true
	reset_force()

func _snap_endpoints() -> bool:
	var planet := get_node_or_null(planet_path) as Node2D
	if planet == null or not "body_index" in planet:
		return false
	PlanetConfig.ensure_loaded()
	var body: Dictionary = PlanetConfig.planet if planet.body_index == 0 else PlanetConfig.planet_b if planet.body_index == 1 else {}
	if body.is_empty():
		return false
	var radius := float(body.radius_km)
	var snapped: Array[Vector2] = []
	for marker in [start_marker, end_marker]:
		var relative := planet.to_local(marker.global_position)
		if not relative.is_finite() or relative.length_squared() < 0.000000000001:
			return false
		snapped.append(to_local(planet.to_global(relative.normalized() * radius)))
	start_marker.position = snapped[0]
	end_marker.position = snapped[1]
	return true

func _planet_route_valid() -> bool:
	var planet := get_node_or_null(planet_path) as Node2D
	if planet == null or not "body_index" in planet:
		return false
	PlanetConfig.ensure_loaded()
	var body: Dictionary = PlanetConfig.planet if planet.body_index == 0 else PlanetConfig.planet_b if planet.body_index == 1 else {}
	if body.is_empty():
		return false
	var radius := float(body.radius_km)
	var s := planet.to_local(to_global(start_marker.position))
	var a := planet.to_local(to_global(apex_marker.position))
	var e := planet.to_local(to_global(end_marker.position))
	if absf(s.length() - radius) > 0.01 or absf(e.length() - radius) > 0.01:
		return false
	return _segment_outside_planet(planet, start_marker.position, s, a, radius) and _segment_outside_planet(planet, end_marker.position, e, a, radius)

func _segment_outside_planet(planet: Node2D, endpoint_local: Vector2, endpoint: Vector2, apex: Vector2, radius: float) -> bool:
	# P(t) = apex + linear*t + quadratic*t²，t 从顶点走向端点。
	var midpoint_local := Vector2((apex_marker.position.x + endpoint_local.x) * 0.5, apex_marker.position.y + (endpoint_local.y - apex_marker.position.y) * 0.25)
	var midpoint: Vector2 = planet.to_local(to_global(midpoint_local))
	var quadratic := 2.0 * (endpoint + apex - 2.0 * midpoint)
	var linear := endpoint - apex - quadratic
	var c3 := 2.0 * quadratic.dot(quadratic)
	var c2 := 3.0 * linear.dot(quadratic)
	var c1 := linear.dot(linear) + 2.0 * apex.dot(quadratic)
	var c0 := apex.dot(linear)
	var breaks: Array[float] = [0.0, 1.0]
	var discriminant := 4.0 * c2 * c2 - 12.0 * c3 * c1
	if c3 > 0.000000001 and discriminant >= 0.0:
		var root := sqrt(discriminant)
		for value in [(-2.0 * c2 - root) / (6.0 * c3), (-2.0 * c2 + root) / (6.0 * c3)]:
			if value > 0.0 and value < 1.0:
				breaks.append(value)
	elif absf(c2) > 0.000000001:
		var value := -c1 / (2.0 * c2)
		if value > 0.0 and value < 1.0:
			breaks.append(value)
	breaks.sort()
	var candidates: Array[float] = breaks.duplicate()
	for i in range(breaks.size() - 1):
		var left := breaks[i]
		var right := breaks[i + 1]
		var f_left := ((c3 * left + c2) * left + c1) * left + c0
		var f_right := ((c3 * right + c2) * right + c1) * right + c0
		if f_left * f_right < 0.0:
			for j in range(40):
				var middle := (left + right) * 0.5
				var f_middle := ((c3 * middle + c2) * middle + c1) * middle + c0
				if f_left * f_middle <= 0.0:
					right = middle
				else:
					left = middle
					f_left = f_middle
			candidates.append((left + right) * 0.5)
	for t in candidates:
		if (apex + linear * t + quadratic * t * t).length() < radius - 0.01:
			return false
	return true

func point_at(progress: float) -> Vector2:
	var s := start_marker.position
	var a := apex_marker.position
	var e := end_marker.position
	# 两段顶点式二次曲线拼接，顶点切线连续；并非单条抛物线。
	var x := lerpf(s.x, e.x, clampf(progress, 0.0, 1.0))
	var endpoint := s if (x - a.x) * (s.x - a.x) >= 0.0 else e
	var ratio := (x - a.x) / (endpoint.x - a.x)
	return Vector2(x, a.y + (endpoint.y - a.y) * ratio * ratio)

func apex_progress() -> float:
	return (apex_marker.position.x - start_marker.position.x) / (end_marker.position.x - start_marker.position.x)

func sample_path(segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not valid or segments < 1:
		return points
	var apex := apex_progress()
	for i in range(segments + 1):
		var p := float(i) / segments
		if i > 0 and float(i - 1) / segments < apex and p > apex:
			points.append(to_global(point_at(apex)))
		points.append(to_global(point_at(p)))
	return points

func member_point_at(progress: float, offset: Vector2) -> Vector2:
	var p := clampf(progress, 0.0, 1.0)
	var center := point_at(p)
	var s := start_marker.position
	var a := apex_marker.position
	var e := end_marker.position
	var x := lerpf(s.x, e.x, p)
	var endpoint := s if (x - a.x) * (s.x - a.x) >= 0.0 else e
	var slope := 2.0 * (endpoint.y - a.y) * (x - a.x) / pow(endpoint.x - a.x, 2.0)
	var direction := signf(e.x - s.x)
	var tangent := Vector2(direction, direction * slope).normalized()
	return center + (tangent * offset.x + tangent.orthogonal() * offset.y) * sin(PI * p)

func member_direction_at(progress: float, offset: Vector2) -> Vector2:
	var before := maxf(0.0, progress - 0.0001)
	var after := minf(1.0, progress + 0.0001)
	return member_point_at(after, offset) - member_point_at(before, offset)

func reset_force() -> void:
	if not valid:
		return
	elapsed = 0.0
	triggered = false
	visual_progress = -1.0
	members.clear()
	var spacing := float(config.member_spacing_km)
	for i in range(9):
		var node: Node2D = members_root.get_child(i)
		var row := (i + 1) / 2
		var side := 0 if i == 0 else (-1 if i % 2 == 1 else 1)
		var offset := Vector2(-float(row) * spacing, float(side * row) * spacing)
		node.position = member_point_at(0.0, offset)
		var body: Node2D = node.get_node("Body")
		var heading := member_direction_at(0.0, offset)
		if heading.length_squared() > 0.000000001:
			body.rotation = heading.angle()
		node.visible = true
		var position_world := node.global_position
		members.append({"node": node, "offset": offset, "health": float(config.member_health), "alive": true, "previous": position_world, "current": position_world})
		var trail: Line2D = node.get_node("Trail")
		trail.clear_points()

func _update_trail(member: Dictionary, progress: float, zoom: float) -> void:
	var trail: Line2D = member.node.get_node("Trail")
	var heading := member_direction_at(progress, member.offset)
	trail.clear_points()
	var trail_span := minf(progress, 0.15)
	for i in range(int(config.trail_points)):
		var trail_progress := progress - trail_span * (1.0 - float(i) / float(int(config.trail_points) - 1))
		var trail_world := to_global(member_point_at(trail_progress, member.offset))
		trail.add_point(trail.to_local(trail_world))
	var tail := -heading.normalized() * (4.8 / maxf(zoom, 0.01))
	for i in range(trail.get_point_count()):
		trail.set_point_position(i, trail.get_point_position(i) + tail)
	var first := trail.get_point_position(0)
	if first.distance_to(tail) < 18.0 / maxf(zoom, 0.01):
		var rear := (first - tail).normalized()
		if rear.length_squared() < 0.000001:
			rear = -heading.normalized()
		trail.add_point(tail + rear * (18.0 / maxf(zoom, 0.01)), 0)

func advance(dt: float) -> void:
	if not valid or not triggered or dt <= 0.0:
		return
	elapsed = minf(float(config.duration_sim_s), elapsed + dt)
	var progress := elapsed / float(config.duration_sim_s)
	for member in members:
		if not member.alive:
			continue
		member.previous = member.node.global_position
		member.node.position = member_point_at(progress, member.offset)
		var heading := member_direction_at(progress, member.offset)
		if heading.length_squared() > 0.000000001:
			member.node.get_node("Body").rotation = heading.angle()
		member.current = member.node.global_position
		if elapsed >= float(config.duration_sim_s):
			member.node.visible = false

func damage_member(index: int, amount: float) -> void:
	if index < 0 or index >= members.size() or not members[index].alive or amount <= 0.0:
		return
	var member := members[index]
	member.health -= amount
	if member.health <= 0.0:
		member.alive = false
		member.node.visible = false
