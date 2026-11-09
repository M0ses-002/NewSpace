extends Node2D

var members: Array[Dictionary] = []
var settings: Dictionary
var center: Vector2
var radius: float
var start_angle: float
var direction: float
var elapsed := 0.0
var returning := false
var orbit_end_time := 0.0
var orbit_sweeps: Array[Dictionary] = []
var return_origin: Vector2
var return_distance := 0.0
var position_world: Vector2
var team := "player"
var mothership: Node2D
var dogfight = null

func launch(origin: Vector2, orbit_center: Vector2, sign_direction: float, parameters: Dictionary, faction: String = "player", carrier: Node2D = null) -> void:
	team = faction
	mothership = carrier
	settings = parameters
	center = orbit_center
	radius = origin.distance_to(center)
	start_angle = (origin - center).angle()
	direction = sign_direction
	position_world = origin
	var root: Node2D = $Members
	for i in range(9):
		var node: Node2D = root.get_child(i)
		node.get_node("Body").modulate = Color("#ff6666") if team == "enemy" else Color("#66ccff")
		node.get_node("Trail").modulate = Color("#ff6666") if team == "enemy" else Color("#66ccff")
		var row := (i + 1) / 2
		var side := 0 if i == 0 else (-1 if i % 2 == 1 else 1)
		var offset := Vector2(-float(row), float(side * row)) * float(settings.spacing_km)
		members.append({"node": node, "offset": offset, "alive": true, "previous": origin, "current": origin, "hit_targets": {}})
		_update_member(members.back(), origin, -direction * Vector2.from_angle(start_angle).orthogonal())
		members.back().previous = members.back().current

func _update_member(member: Dictionary, center_position: Vector2, heading: Vector2) -> void:
	var node: Node2D = member.node
	var tangent := heading.normalized()
	node.global_position = center_position + tangent * member.offset.x + tangent.orthogonal() * member.offset.y
	var member_heading := tangent
	if not returning:
		var radial := (center_position - center).normalized()
		member_heading = tangent * (radius + direction * float(member.offset.y)) - radial * float(member.offset.x)
	if member_heading.length_squared() > 0.000001:
		node.get_node("Body").global_rotation = member_heading.angle()
	member.current = node.global_position

func advance(dt: float, player: Vector2) -> void:
	if dt <= 0.0:
		return
	orbit_sweeps.clear()
	if dogfight != null:
		return
	var orbit_duration: float = TAU * radius / float(settings.orbit_speed_km_s)
	var orbit_time: float = minf(dt, maxf(0.0, orbit_duration - elapsed)) if not returning else 0.0
	for member in members:
		member.previous = member.current
	if orbit_time > 0.0:
		elapsed += orbit_time
		var angle := start_angle + direction * TAU * minf(elapsed / orbit_duration, 1.0)
		position_world = center + Vector2.from_angle(angle) * radius
		for member in members:
			if member.alive:
				_update_member(member, position_world, -direction * Vector2.from_angle(angle).orthogonal())
				orbit_sweeps.append({"member": member, "start": member.previous, "end": member.current})
	orbit_end_time = orbit_time
	if not returning and elapsed >= orbit_duration:
		returning = true
		return_origin = position_world
		return_distance = return_origin.distance_to(player)
	var return_time := dt - orbit_time
	if returning and return_time > 0.0:
		var heading := player - position_world
		position_world = position_world.move_toward(player, float(settings.return_speed_km_s) * return_time)
		for member in members:
			if member.alive:
				_update_member(member, position_world, heading if heading.length_squared() > 0.000001 else Vector2.RIGHT)
		modulate.a = clampf(position_world.distance_to(player) / maxf(return_distance, float(settings.fade_distance_km)), 0.0, 1.0)

func rewind_orbit_to(time_in_step: float) -> void:
	elapsed -= orbit_end_time - time_in_step
	returning = false
	modulate.a = 1.0
	var duration: float = TAU * radius / float(settings.orbit_speed_km_s)
	var angle := start_angle + direction * TAU * elapsed / duration
	position_world = center + Vector2.from_angle(angle) * radius
	for member in members:
		if member.alive:
			_update_member(member, position_world, -direction * Vector2.from_angle(angle).orthogonal())
			member.previous = member.current

func finished(player: Vector2) -> bool:
	if returning and position_world.distance_to(player) <= 0.001:
		return true
	for member in members:
		if member.alive:
			return false
	return true

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	var zoom := camera.zoom.x if camera != null else 1.0
	for member in members:
		var node: Node2D = member.node
		var body: Node2D = node.get_node("Body")
		var trail: Line2D = node.get_node("Trail")
		body.scale = Vector2.ONE * (2.4 / maxf(zoom, 0.01))
		trail.width = 2.5 / maxf(zoom, 0.01)
		trail.clear_points()
		trail.add_point(Vector2(-22.8 / maxf(zoom, 0.01), 0).rotated(body.rotation))
		trail.add_point(Vector2(-4.8 / maxf(zoom, 0.01), 0).rotated(body.rotation))
