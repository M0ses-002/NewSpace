extends SceneTree
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var level_four = load("res://scenes/level_4.tscn").instantiate()
	root.add_child(level_four)
	await process_frame
	check(level_four.get_node_or_null("Sandbox/World/AirForces") == null, "第四关没有空军")
	level_four.queue_free()
	await process_frame
	var level = load("res://scenes/level_6.tscn").instantiate()
	var force = level.get_node("Sandbox/World/AirForces/AirForce1")
	var saved_start: Vector2 = force.get_node("Start").position
	var saved_apex: Vector2 = force.get_node("Apex").position
	var saved_end: Vector2 = force.get_node("End").position
	root.add_child(level)
	await process_frame
	check(force.valid and force.members.size() == 9, "第六关编队及九成员")
	if not force.valid:
		level.queue_free()
		print("AIR_FORCE_TEST checks=", checks, " failures=", failures)
		quit(1)
		return
	check(level.combat != null and level.combat.has_method("advance"), "战斗脚本已正常加载")
	check(force.apex_marker.position.is_equal_approx(saved_apex), "保留场景中编辑的第六关顶点")
	var trigger_point: Vector2 = force.to_global(force.point_at(force.apex_progress()))
	level.combat._advance_air_forces(0.125, trigger_point, trigger_point)
	check(force.triggered and force.elapsed > 0.0, "用户航线通过战斗距离判定触发")
	force.reset_force()
	var planet: Node2D = level.get_node("Sandbox/World/Planet")
	var radius: float = float(level.get_node("Sandbox").Config.planet.radius_km)
	check(force.start_marker.position.is_equal_approx(saved_start) and force.end_marker.position.is_equal_approx(saved_end), "保留场景中编辑的起点和终点")
	var member_paths_valid := true
	for member in force.members:
		for i in range(1001):
			var p := float(i) / 1000.0
			if (i == 0 and not force.member_point_at(p, member.offset).is_equal_approx(saved_start)) or (i == 1000 and not force.member_point_at(p, member.offset).is_equal_approx(saved_end)):
				member_paths_valid = false
	check(member_paths_valid, "全部九名成员的起终点与编辑点一致")
	var midpoint_spacing: float = force.member_point_at(0.5, force.members[1].offset).distance_to(force.member_point_at(0.5, force.members[2].offset))
	check(midpoint_spacing > 0.1, "人字编队中点保持非零间距")
	var oriented := true
	for i in range(1, 1000):
		var p := float(i) / 1000.0
		var tangent: Vector2 = (force.point_at(minf(1.0, p + 0.0001)) - force.point_at(maxf(0.0, p - 0.0001))).normalized()
		for member in force.members.slice(1):
			var displacement: Vector2 = force.member_point_at(p, member.offset) - force.point_at(p)
			if displacement.dot(tangent) >= 0.0:
				oriented = false
	check(oriented, "整个编队人字尖端始终朝中心航线前方")
	var minimum_forward := 1.0
	for member in force.members:
		for i in range(1, 1000):
			var p := float(i) / 1000.0
			var tangent: Vector2 = (force.point_at(p + 0.0001) - force.point_at(p - 0.0001)).normalized()
			var velocity: Vector2 = force.member_direction_at(p, member.offset)
			if velocity.length_squared() > 0.000000001:
				minimum_forward = minf(minimum_forward, velocity.normalized().dot(tangent))
	check(midpoint_spacing > 10.0, "人字编队中段充分散开")
	print("AIR_MIN_FORWARD ", minimum_forward)
	check(force.point_at(0).is_equal_approx(force.start_marker.position), "起点精确")
	check(force.point_at(force.apex_progress()).is_equal_approx(force.apex_marker.position), "顶点精确")
	check(force.point_at(1).is_equal_approx(force.end_marker.position), "终点精确")
	var points: PackedVector2Array = force.sample_path(7)
	check(points.has(force.to_global(force.apex_marker.position)), "路径采样包含顶点")
	force.triggered = true
	var step: float = level.combat.max_step()
	var start_us := Time.get_ticks_usec()
	for i in range(120):
		force.advance(step)
	force._process(0.0)
	var substep_us := Time.get_ticks_usec() - start_us
	var sampled_trail: Line2D = force.members[0].node.get_node("Trail")
	check(sampled_trail.get_point_count() >= 2 and sampled_trail.get_point_position(0).distance_to(sampled_trail.get_point_position(sampled_trail.get_point_count() - 1)) > 15.0, "实际战斗子步下拖尾具有足够长度")
	print("AIR_SUBSTEP count=120 simulated_s=", step * 120.0, " elapsed_ms=", substep_us / 1000.0)
	force.reset_force()
	var prior: Vector2 = force.members[0].current
	force.advance(10.0)
	check(force.elapsed == 0.0 and force.members[0].current == prior, "未触发不移动")
	force.triggered = true
	force.advance(10.0)
	force._process(0.0)
	check(force.members[0].previous.is_equal_approx(prior) and force.members[0].current.is_equal_approx(force.members[0].node.global_position) and force.members[0].current != prior, "成员世界坐标")
	var headings_valid := true
	for member in force.members:
		var body: Node2D = member.node.get_node("Body")
		var tangent: Vector2 = force.member_direction_at(force.elapsed / float(force.config.duration_sim_s), member.offset)
		if absf(angle_difference(body.rotation, tangent.angle())) > 0.001:
			headings_valid = false
	check(headings_valid, "每个成员沿自身偏移轨迹切线朝向")
	var trail: Line2D = force.members[0].node.get_node("Trail")
	var tail_end := trail.to_global(trail.get_point_position(trail.get_point_count() - 1))
	var heading_world: Vector2 = (force.to_global(force.member_point_at(0.084, force.members[0].offset)) - force.to_global(force.member_point_at(0.083, force.members[0].offset))).normalized()
	check(trail.get_point_count() >= 2 and (tail_end - force.members[0].current).dot(heading_world) < 0.0, "首次推进即有从机尾延伸的拖尾")
	var pause_points := trail.points
	var pause_rotation: float = force.members[0].node.get_node("Body").rotation
	force.advance(0.0)
	check(trail.points == pause_points and force.members[0].node.get_node("Body").rotation == pause_rotation, "暂停不改变拖尾与朝向")
	force.advance(10.0)
	force._process(0.0)
	var trail_start := trail.to_global(trail.get_point_position(0))
	var trail_end := trail.to_global(trail.get_point_position(trail.get_point_count() - 1))
	check(trail_start.distance_to(trail_end) >= 17.0, "拖尾沿历史航线向尾后明显延伸")
	for target in [0.3, 0.5, 0.7]:
		force.advance((target - force.elapsed / float(force.config.duration_sim_s)) * float(force.config.duration_sim_s))
		var all_aligned := true
		for member in force.members:
			var ahead: Vector2 = force.member_point_at(target + 0.0001, member.offset)
			var behind: Vector2 = force.member_point_at(target - 0.0001, member.offset)
			if absf(angle_difference(member.node.get_node("Body").rotation, (ahead - behind).angle())) > 0.002:
				all_aligned = false
		check(all_aligned, "上升、顶点及下降阶段全体机首沿自身实际速度")
	force.advance(1000.0)
	check(force.point_at(1.0).distance_to(force.members[0].node.position) < 0.001 and force.elapsed == float(force.config.duration_sim_s), "跨步准确停在终点")
	check(not force.members[0].node.visible and force.members[0].alive and force.members[0].previous != force.members[0].current, "终点隐藏但保留活体末帧扫掠")
	force.damage_member(0, 1000)
	check(not force.members[0].alive and force.members[1].alive, "独立损毁")
	force.reset_force()
	check(force.elapsed == 0.0 and force.members[0].alive and trail.get_point_count() == 0, "重置恢复并清除拖尾")
	var reset_tangent: Vector2 = force.member_direction_at(0.0, force.members[0].offset)
	check(absf(angle_difference(force.members[0].node.get_node("Body").rotation, reset_tangent.angle())) < 0.001, "重置时恢复起点切线朝向")
	force.start_marker.position = Vector2(40, -30)
	force.apex_marker.position = Vector2(5, -90)
	force.end_marker.position = Vector2(-30, -40)
	force.initialize()
	check(force.valid and force.point_at(force.apex_progress()).is_equal_approx(force.apex_marker.position) and force.point_at(1).is_equal_approx(force.end_marker.position), "反向不等高航线")
	var reverse_oriented := true
	for i in range(1, 1000):
		var p := float(i) / 1000.0
		var tangent: Vector2 = (force.point_at(p + 0.0001) - force.point_at(p - 0.0001)).normalized()
		for member in force.members.slice(1):
			if (force.member_point_at(p, member.offset) - force.point_at(p)).dot(tangent) >= 0.0:
				reverse_oriented = false
	check(reverse_oriented, "反向航线整个人字尖端朝前")
	var reverse_minimum := 1.0
	for member in force.members:
		for i in range(1, 1000):
			var p := float(i) / 1000.0
			var tangent: Vector2 = (force.point_at(p + 0.0001) - force.point_at(p - 0.0001)).normalized()
			var velocity: Vector2 = force.member_direction_at(p, member.offset)
			if velocity.length_squared() > 0.000000001:
				reverse_minimum = minf(reverse_minimum, velocity.normalized().dot(tangent))
	var reverse_spacing: float = force.member_point_at(0.5, force.members[1].offset).distance_to(force.member_point_at(0.5, force.members[2].offset))
	check(reverse_spacing > 10.0, "反向航线人字编队中段充分散开")
	print("AIR_REVERSE_MIN_FORWARD ", reverse_minimum)
	check(force.point_at(0.5).is_equal_approx(force.apex_marker.position), "航线中点经过编辑的中间点")
	check(force.members[1].offset.x < 0.0, "反向航线人字形偏移相对切线向后")
	force.triggered = true
	force.advance(float(force.config.duration_sim_s) * 0.75)
	var reverse_member: Dictionary = force.members[1]
	var reverse_tangent: Vector2 = force.member_point_at(0.7501, reverse_member.offset) - force.member_point_at(0.7499, reverse_member.offset)
	check(absf(angle_difference(reverse_member.node.get_node("Body").rotation, reverse_tangent.angle())) < 0.001, "反向航线偏移成员朝向与真实轨迹一致")
	force.advance(float(force.config.duration_sim_s))
	var landing_tangent: Vector2 = force.member_point_at(1.0, reverse_member.offset) - force.member_point_at(0.9999, reverse_member.offset)
	check(absf(angle_difference(reverse_member.node.get_node("Body").rotation, landing_tangent.angle())) < 0.001, "终点保留最后的降落切线朝向")
	force.start_marker.position = Vector2(-40, -30)
	force.apex_marker.position = Vector2(0, -40)
	force.end_marker.position = Vector2(40, -30)
	force.initialize()
	check(force.valid and planet.to_local(force.to_global(force.point_at(0.5))).length() < radius, "独立夹具允许航线穿越行星")
	force.planet_path = NodePath("../../MissingPlanet")
	for fixture in [
		[Vector2(3, 4), Vector2(3, -20), Vector2(3, 30)],
		[Vector2(0, 0), Vector2(40, 50), Vector2(-20, -10)],
		[Vector2(0, 0), Vector2(0, 0), Vector2(40, 0)],
		[Vector2(0, 0), Vector2(30, 0), Vector2(0, 0)],
		[Vector2(4, 7), Vector2(4, 7), Vector2(4, 7)]]:
		force.start_marker.position = fixture[0]
		force.apex_marker.position = fixture[1]
		force.end_marker.position = fixture[2]
		force.initialize()
		var finite := true
		for i in range(101):
			for member in force.members:
				if not force.member_point_at(float(i) / 100.0, member.offset).is_finite():
					finite = false
		check(force.valid and finite and force.point_at(0.0).is_equal_approx(fixture[0]) and force.point_at(0.5).is_equal_approx(fixture[1]) and force.point_at(1.0).is_equal_approx(fixture[2]), "任意三点与退化夹具均可运行且精确经过各点")
		force.triggered = true
		force.advance(0.125)
		check(force.elapsed > 0.0 and force.members[0].current.is_finite(), "退化航线仍可出动")
	level.queue_free()
	await process_frame
	print("AIR_FORCE_TEST checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
