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
var orbit: Dictionary = {}
var start_mean := 0.0
var orbit_duration := 0.0

func launch(origin: Vector2, orbit_center: Vector2, sign_direction: float, parameters: Dictionary, faction: String = "player", carrier: Node2D = null, velocity_world: Vector2 = Vector2.ZERO, mu: float = 0.0) -> void:
	team = faction
	mothership = carrier
	settings = parameters
	center = orbit_center
	radius = origin.distance_to(center)
	start_angle = (origin - center).angle()
	direction = sign_direction
	position_world = origin
	var local := origin - center
	var energy: float = velocity_world.length_squared() * 0.5 - mu / radius if mu > 0.0 and radius > 0.0 else 0.0
	var momentum: float = local.cross(velocity_world)
	if energy < 0.0 and absf(momentum) > 0.000001:
		var semi_major := -mu / (2.0 * energy)
		var eccentricity_vector := Vector2(velocity_world.y, -velocity_world.x) * momentum / mu - local / radius
		var eccentricity := eccentricity_vector.length()
		if is_finite(semi_major) and is_finite(eccentricity) and semi_major > 0.0 and eccentricity < 0.999999:
			orbit = {"a": semi_major, "e": eccentricity, "angle": eccentricity_vector.angle() if eccentricity > 0.000001 else start_angle}
	if orbit.is_empty():
		orbit = {"a": radius, "e": 0.0, "angle": start_angle}
	var relative := local.rotated(-float(orbit.angle))
	var anomaly := atan2(relative.y / (float(orbit.a) * sqrt(1.0 - float(orbit.e) * float(orbit.e))), relative.x / float(orbit.a) + float(orbit.e))
	start_mean = anomaly - float(orbit.e) * sin(anomaly)
	orbit_duration = TAU * float(orbit.a) / float(settings.orbit_speed_km_s)
	var root: Node2D = $Members
	for i in range(9):
		var node: Node2D = root.get_child(i)
		node.get_node("Body").modulate = Color("#ff6666") if team == "enemy" else Color("#66ccff")
		node.get_node("Trail").modulate = Color("#ff6666") if team == "enemy" else Color("#66ccff")
		var row := (i + 1) / 2
		var side := 0 if i == 0 else (-1 if i % 2 == 1 else 1)
		var offset := Vector2(-float(row), float(side * row)) * float(settings.spacing_km)
		members.append({"node": node, "offset": offset, "alive": true, "previous": origin, "current": origin, "hit_targets": {}})
		_update_member(members.back(), origin, _orbit_state(0.0).heading)
		members.back().previous = members.back().current

func _update_member(member: Dictionary, center_position: Vector2, heading: Vector2) -> void:
	var node: Node2D = member.node
	var tangent := heading.normalized()
	node.global_position = center_position + tangent * member.offset.x + tangent.orthogonal() * member.offset.y
	var movement: Vector2 = node.global_position - member.previous
	var heading_actual := movement.normalized() if not returning and elapsed > 0.0 and movement.length_squared() > 0.0000000001 else tangent
	if heading_actual.length_squared() > 0.000001:
		node.get_node("Body").global_rotation = heading_actual.angle()
	member.current = node.global_position

func _solve_anomaly(mean: float, e: float) -> float:
	var anomaly := mean
	if e > 0.0:
		var low := -PI
		var high := PI
		for i in range(60):
			var residual := anomaly - e * sin(anomaly) - mean
			var derivative := 1.0 - e * cos(anomaly)
			if residual == 0.0 or (absf(residual) <= 0.00000000000001 and absf(residual / derivative) <= 0.0000000000001):
				break
			if residual < 0.0:
				low = anomaly
			else:
				high = anomaly
			if i < 12:
				var next := anomaly - residual / derivative
				anomaly = next if next > low and next < high else (low + high) * 0.5
			else:
				anomaly = (low + high) * 0.5
	return anomaly

func _orbit_state(time: float) -> Dictionary:
	var e: float = float(orbit.e)
	var mean := wrapf(start_mean + direction * TAU * time / orbit_duration, -PI, PI)
	var anomaly := _solve_anomaly(mean, e)
	var minor := sqrt(1.0 - e * e)
	var local := Vector2(cos(anomaly) - e, minor * sin(anomaly)) * float(orbit.a)
	var tangent := Vector2(-sin(anomaly), minor * cos(anomaly)).rotated(float(orbit.angle)) * direction
	return {"position": center + local.rotated(float(orbit.angle)), "heading": tangent}

func max_angular_speed() -> float:
	var e: float = float(orbit.e)
	return TAU / orbit_duration * sqrt(1.0 - e * e) / pow(1.0 - e, 2.0)

func advance(dt: float, player: Vector2) -> void:
	if dt <= 0.0:
		return
	orbit_sweeps.clear()
	for member in members:
		member.erase("decoy_step")
		member.erase("decoy_collision_time")
		member.erase("decoy_motion")
	if dogfight != null:
		return
	var orbit_time: float = minf(dt, maxf(0.0, orbit_duration - elapsed)) if not returning else 0.0
	for member in members:
		member.previous = member.current
	if orbit_time > 0.0:
		elapsed += orbit_time
		var state := _orbit_state(elapsed)
		position_world = state.position
		for member in members:
			if member.alive and not is_instance_valid(member.get("decoy")):
				_update_member(member, position_world, state.heading)
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
			if member.alive and not is_instance_valid(member.get("decoy")):
				_update_member(member, position_world, heading if heading.length_squared() > 0.000001 else Vector2.RIGHT)
		var fade := clampf(position_world.distance_to(player) / maxf(return_distance, float(settings.fade_distance_km)), 0.0, 1.0)
		var has_pursuit := members.any(func(member): return member.alive and is_instance_valid(member.get("decoy")))
		modulate.a = 1.0 if has_pursuit else fade
		for member in members:
			member.node.modulate.a = fade if has_pursuit and not is_instance_valid(member.get("decoy")) else 1.0

func rewind_orbit_to(time_in_step: float) -> void:
	elapsed -= orbit_end_time - time_in_step
	returning = false
	modulate.a = 1.0
	var state := _orbit_state(elapsed)
	position_world = state.position
	for member in members:
		if member.has("decoy_motion") and float(member.decoy_motion.time) <= time_in_step and (not member.has("decoy_collision_time") or float(member.decoy_collision_time) > time_in_step) and (not member.has("defense_hit_time") or float(member.defense_hit_time) > time_in_step):
			var motion: Dictionary = member.decoy_motion
			var fraction := clampf((time_in_step - float(motion.time)) / maxf(float(motion.duration), 0.000000001), 0.0, 1.0)
			member.current = motion.start.lerp(motion.end, fraction)
			member.previous = member.current
			member.node.global_position = member.current
			member.decoy = motion.target
			member.alive = true
			member.node.visible = true
		if member.has("decoy_step") and float(member.decoy_step) > time_in_step and (not member.has("defense_hit_time") or float(member.defense_hit_time) > time_in_step):
			member.alive = true
			member.node.visible = true
			member.decoy = null
			member.erase("decoy_step")
		if member.alive and not is_instance_valid(member.get("decoy")):
			member.node.modulate.a = 1.0
			_update_member(member, position_world, state.heading)
			member.previous = member.current

func _entry_fraction(start: Vector2, end: Vector2, radius: float) -> float:
	var c := start.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var movement := end - start
	var a := movement.length_squared()
	var b := 2.0 * start.dot(movement)
	var discriminant := b * b - 4.0 * a * c
	if a <= 0.000000000001 or discriminant < 0.0:
		return INF
	var fraction := (-b - sqrt(discriminant)) / (2.0 * a)
	return fraction if fraction >= 0.0 and fraction <= 1.0 else INF

func advance_decoys(dt: float, decoys: Array, previous_decoys: Dictionary = {}) -> void:
	if dt <= 0.0:
		return
	for member in members:
		if not member.alive:
			continue
		var target: Node2D = member.get("decoy")
		var start: Vector2 = member.current if dogfight != null or is_instance_valid(target) else member.previous
		var end: Vector2 = member.current
		var entry := 0.0
		if not is_instance_valid(target) or target.is_queued_for_deletion() or not decoys.has(target):
			target = null
			entry = INF
			for decoy in decoys:
				if not is_instance_valid(decoy) or decoy.is_queued_for_deletion() or decoy.team == team:
					continue
				var decoy_start: Vector2 = previous_decoys.get(decoy.get_instance_id(), decoy.global_position)
				var fraction := _entry_fraction(start - decoy_start, end - decoy.global_position, float(decoy.attraction_radius))
				if fraction < entry:
					entry = fraction
					target = decoy
			member.decoy = target
			if target != null:
				member.decoy_step = entry * dt
		if target == null:
			continue
		for sweep in orbit_sweeps:
			if sweep.member == member:
				var sweep_fraction := minf(1.0, entry * dt / orbit_end_time)
				sweep.end = sweep.start.lerp(sweep.end, sweep_fraction)
				sweep.end_time = orbit_end_time * sweep_fraction
				if sweep.end_time <= 0.000000001:
					orbit_sweeps.erase(sweep)
				break
		if returning and modulate.a < 1.0:
			var fade := modulate.a
			modulate.a = 1.0
			for other in members:
				if not is_instance_valid(other.get("decoy")):
					other.node.modulate.a = fade
		member.node.modulate.a = 1.0
		var origin: Vector2 = start.lerp(end, entry)
		var destination: Vector2 = target.global_position
		var target_start: Vector2 = previous_decoys.get(target.get_instance_id(), destination)
		var target_at_entry := target_start.lerp(destination, entry)
		var heading := target_at_entry - origin
		var next := origin.move_toward(destination, float(settings.orbit_speed_km_s) * dt * (1.0 - entry))
		member.decoy_motion = {"time": entry * dt, "duration": dt * (1.0 - entry), "start": origin, "end": next, "target": target}
		member.previous = origin
		member.current = next
		member.node.global_position = next
		if heading.length_squared() > 0.00000001:
			member.node.get_node("Body").global_rotation = heading.angle()
		var collision_fraction := _entry_fraction(origin - target_at_entry, next - destination, float(target.collision_radius))
		if not is_inf(collision_fraction):
			member.decoy_collision_time = dt * (entry + (1.0 - entry) * collision_fraction)
			member.alive = false
			member.node.visible = false
			member.decoy = null

func finished(player: Vector2) -> bool:
	var arrived := returning and position_world.distance_to(player) <= 0.001
	for member in members:
		if member.alive and (not arrived or is_instance_valid(member.get("decoy"))):
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
