extends SceneTree

const Squadron = preload("res://scenes/carrier_squadron.tscn")
const Orbit = preload("res://scripts/kepler_orbit.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func legacy_anomaly(mean: float, e: float) -> float:
	var low := -PI
	var high := PI
	for i in range(48):
		var mid := (low + high) * 0.5
		if mid - e * sin(mid) < mean:
			low = mid
		else:
			high = mid
	return (low + high) * 0.5

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var settings := {"orbit_speed_km_s": 5.0, "return_speed_km_s": 8.0, "fade_distance_km": 60.0, "spacing_km": 6.0}
	var mu := 100000.0
	var expected := {"a": 400.0, "e": 0.4, "angle": 0.7}
	var parent := Node2D.new()
	root.add_child(parent)
	var center := Vector2(500, 200)
	var initial := Orbit.state_at(expected, 1.1, 1.0, mu)
	var origin: Vector2 = center + initial.position
	var squads: Array = []
	for direction in [-1.0, 1.0]:
		var squad = Squadron.instantiate()
		parent.add_child(squad)
		squad.launch(origin, center, direction, settings, "player", null, initial.velocity, mu)
		squads.append(squad)
		check(absf(squad.orbit.a - expected.a) < 0.01 and absf(squad.orbit.e - expected.e) < 0.0001, "从状态向量还原椭圆")
		check(squad.position_world.distance_to(origin) < 0.001, "发射起点不跳变")
		check(squad.max_angular_speed() > TAU / squad.orbit_duration, "近心点角速度上界")
		for i in range(1, 9):
			squad.advance(squad.orbit_duration / 8.0, origin + Vector2(100, 0))
			check(Orbit.residual(expected, squad.position_world - center) < 0.0001, "完整飞行遵循原椭圆")
		check(squad.returning and squad.position_world.distance_to(origin) < 0.01, "恰好一圈后返回发射位置并返航")
		squad.advance(100.0, origin + Vector2(100, 0))
		check(squad.finished(origin + Vector2(100, 0)), "返航追踪母舰")
	check(squads[0].direction == -squads[1].direction, "反向编队")
	var fallback = Squadron.instantiate()
	parent.add_child(fallback)
	fallback.launch(origin, center, 1.0, settings, "enemy", null, initial.position.normalized() * 1000.0, mu)
	check(fallback.orbit.e == 0.0 and absf(fallback.orbit.a - origin.distance_to(center)) < 0.001, "非闭合轨道退回发射点圆轨道")
	fallback.advance(1.0, origin)
	check(absf(fallback.position_world.distance_to(center) - fallback.radius) < 0.001, "回退圆轨半径固定")
	var max_error := 0.0
	var max_residual := 0.0
	for e in [0.0, 0.4, 0.9, 0.99, 0.999998, 0.9999999]:
		for i in range(-1000, 1001):
			var mean := PI * float(i) / 1000.0
			var anomaly: float = fallback._solve_anomaly(mean, e)
			max_error = maxf(max_error, absf(anomaly - legacy_anomaly(mean, e)))
			max_residual = maxf(max_residual, absf(anomaly - e * sin(anomaly) - mean))
		for mean in [-0.000001, -0.0000000001, 0.0, 0.0000000001, 0.000001]:
			var anomaly: float = fallback._solve_anomaly(mean, e)
			max_error = maxf(max_error, absf(anomaly - legacy_anomaly(mean, e)))
			max_residual = maxf(max_residual, absf(anomaly - e * sin(anomaly) - mean))
	check(max_error < 0.000000001 and max_residual < 0.00000000000002, "开普勒求解匹配原二分与残差，包括高偏心近心点")
	var original_orbit: Dictionary = fallback.orbit
	var original_mean: float = fallback.start_mean
	fallback.orbit = {"a": 400.0, "e": 0.999998, "angle": 0.7}
	fallback.start_mean = -0.000001
	var before_periapsis: Dictionary = fallback._orbit_state(0.0)
	var after_periapsis: Dictionary = fallback._orbit_state(0.000002 * fallback.orbit_duration / TAU)
	check(before_periapsis.position.is_finite() and after_periapsis.position.is_finite() and before_periapsis.heading.is_finite() and after_periapsis.heading.is_finite(), "高偏心率跨近心点位置和方向有限")
	fallback.orbit = original_orbit
	fallback.start_mean = original_mean
	var bench_inputs: Array[Vector2] = []
	for e in [0.0, 0.4, 0.9, 0.99, 0.999998]:
		for i in range(-500, 500):
			bench_inputs.append(Vector2(PI * float(i) / 500.0, e))
	var checksum := 0.0
	var started := Time.get_ticks_usec()
	for repetition in range(10):
		for input in bench_inputs:
			checksum += legacy_anomaly(input.x, input.y)
	var legacy_us := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	for repetition in range(10):
		for input in bench_inputs:
			checksum += fallback._solve_anomaly(input.x, input.y)
	var optimized_us := Time.get_ticks_usec() - started
	print("CARRIER_SOLVER_BENCH calls=50000 legacy_us=", legacy_us, " optimized_us=", optimized_us, " max_error=", max_error, " max_residual=", max_residual, " checksum=", checksum)
	var elapsed: float = fallback.elapsed
	fallback.advance(4.0, origin)
	fallback.rewind_orbit_to(2.0)
	check(absf(fallback.elapsed - elapsed - 2.0) < 0.001, "狗斗回退保留剩余航程")
	fallback.team = "player"
	var decoy = preload("res://scenes/decoy_satellite.tscn").instantiate()
	parent.add_child(decoy)
	decoy.team = "enemy"
	decoy.attraction_radius = 1.0
	decoy.collision_radius = 0.2
	decoy.global_position = fallback.members[0].current
	fallback.advance_decoys(0.01, [decoy])
	check(not fallback.members[0].alive and decoy.is_inside_tree(), "敌方诱饵撞毁单机且卫星保留")
	check(fallback.members[1].alive and not is_instance_valid(fallback.members[1].get("decoy")), "范围外成员保持原行为")
	var second = fallback.members[1]
	decoy.team = "player"
	decoy.global_position = second.current
	fallback.advance_decoys(0.01, [decoy])
	check(second.alive and not is_instance_valid(second.get("decoy")), "同阵营诱饵不吸引")
	decoy.team = "enemy"
	decoy.global_position = second.current + Vector2(10, 0)
	decoy.attraction_radius = 20.0
	fallback.dogfight = {}
	var before: Vector2 = second.current
	fallback.advance(1.0, origin)
	fallback.advance_decoys(1.0, [decoy])
	check(second.alive and is_instance_valid(second.decoy) and absf(second.current.distance_to(before) - 5.0) < 0.001, "狗斗期间单机以模拟速度追逐诱饵")
	fallback.advance_decoys(1.0, [decoy])
	check(not second.alive and decoy.is_inside_tree(), "追逐接触后只消失舰载机")
	var pursuit = Squadron.instantiate()
	parent.add_child(pursuit)
	pursuit.launch(origin, center, 1.0, settings, "player")
	decoy.attraction_radius = 100.0
	decoy.global_position = origin + Vector2(50, 0)
	pursuit.advance_decoys(0.1, [decoy])
	var chasing := 0
	for member in pursuit.members:
		if is_instance_valid(member.get("decoy")):
			chasing += 1
	check(chasing > 1, "同一敌方诱饵可同时吸引多架飞机")
	pursuit.returning = true
	pursuit.return_distance = 10.0
	pursuit.position_world = origin
	pursuit.advance(0.1, origin)
	check(not pursuit.finished(origin), "母舰返航完成后保留受诱飞机")
	check(pursuit.members[0].node.modulate.a == 1.0, "受诱飞机不因母舰返航而消隐")
	pursuit.advance_decoys(100.0, [decoy])
	check(pursuit.finished(origin) and decoy.is_inside_tree(), "受诱飞机全部撞毁后编队完成且卫星保留")
	var crossing = Squadron.instantiate()
	parent.add_child(crossing)
	crossing.launch(origin, center, 1.0, settings, "player")
	for i in range(1, crossing.members.size()):
		crossing.members[i].alive = false
	var flyer: Dictionary = crossing.members[0]
	flyer.previous = Vector2(-10, 0)
	flyer.current = Vector2(10, 0)
	flyer.node.global_position = flyer.current
	crossing.orbit_end_time = 4.0
	crossing.orbit_sweeps.clear()
	crossing.orbit_sweeps.append({"member": flyer, "start": flyer.previous, "end": flyer.current})
	decoy.global_position = Vector2.ZERO
	decoy.attraction_radius = 2.0
	decoy.collision_radius = 0.1
	crossing.advance_decoys(4.0, [decoy])
	check(not flyer.alive, "单步跨越诱饵范围仍触发撞毁")
	check(absf(crossing.orbit_sweeps[0].end_time - 1.6) < 0.001 and crossing.orbit_sweeps[0].end.distance_to(Vector2(-2, 0)) < 0.001, "轨道扫掠截断在首次进入时刻")
	check(not flyer.alive, "入范围后仅用剩余时间追逐并撞毁")
	crossing.elapsed = 4.0
	crossing.rewind_orbit_to(1.0)
	check(flyer.alive and flyer.node.visible and not is_instance_valid(flyer.get("decoy")), "早于入圈的狗斗回退撤销之后的吸引和撞毁")
	flyer.alive = false
	flyer.node.visible = false
	flyer.decoy = decoy
	flyer.decoy_step = 0.8
	flyer.defense_hit_time = 0.2
	crossing.orbit_end_time = 1.0
	crossing.rewind_orbit_to(0.5)
	check(not flyer.alive and not flyer.node.visible, "狗斗回退不复活更早被近防拦截的飞机")
	flyer.erase("defense_hit_time")
	flyer.decoy_step = 0.2
	flyer.decoy_collision_time = 0.8
	flyer.decoy = null
	flyer.decoy_motion = {"time": 0.2, "duration": 0.8, "start": Vector2.ZERO, "end": Vector2(8, 0), "target": decoy}
	crossing.orbit_end_time = 1.0
	crossing.rewind_orbit_to(0.5)
	check(flyer.alive and flyer.node.visible and flyer.decoy == decoy and flyer.current.distance_to(Vector2(3, 0)) < 0.001, "狗斗回退保留此前受诱并撤销后续撞毁")
	flyer.erase("decoy_collision_time")
	flyer.erase("decoy_motion")
	flyer.erase("defense_hit_time")
	flyer.erase("decoy_step")
	flyer.alive = true
	flyer.decoy = null
	flyer.previous = Vector2(-10, 0)
	flyer.current = Vector2(10, 0)
	crossing.orbit_sweeps.clear()
	crossing.orbit_sweeps.append({"member": flyer, "start": flyer.previous, "end": flyer.current})
	decoy.global_position = Vector2(0, 4)
	decoy.attraction_radius = 4.0
	decoy.collision_radius = 0.01
	crossing.settings = settings.duplicate()
	crossing.settings.orbit_speed_km_s = 1.0
	crossing.advance_decoys(4.0, [decoy])
	check(flyer.alive and flyer.current.distance_to(Vector2(0, 2)) < 0.001, "首次受诱仅用剩余子步时间追逐")
	flyer.decoy = null
	flyer.previous = Vector2.ZERO
	flyer.current = Vector2.ZERO
	crossing.orbit_sweeps.clear()
	decoy.global_position = Vector2(10, 0)
	decoy.attraction_radius = 2.0
	decoy.collision_radius = 0.1
	crossing.advance_decoys(1.0, [decoy], {decoy.get_instance_id(): Vector2(-10, 0)})
	check(not flyer.alive, "移动卫星跨越飞机时相对扫掠触发吸引和碰撞")
	parent.free()
	print("CARRIER_ORBIT_TESTS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
