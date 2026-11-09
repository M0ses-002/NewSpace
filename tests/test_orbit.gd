extends SceneTree
const Orbit = preload("res://scripts/kepler_orbit.gd")
const Units = preload("res://scripts/game_units.gd")
var checks: int = 0
var failures: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_physical_units()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 61703
	for trial in range(350):
		var e: float = rng.randf_range(0.0, 0.85)
		var a: float = rng.randf_range(76.0 / (1.0 - e), 1000.0)
		var orbit: Dictionary = Orbit.make(a, e, rng.randf_range(-PI, PI))
		var m: float = rng.randf_range(-PI, PI)
		var state: Dictionary = Orbit.state_at(orbit, m)
		var pos: Vector2 = state.position
		var vel: Vector2 = state.velocity
		check(Orbit.residual(orbit, pos) < 2.0e-5, "Position lies on conic")
		check(vel.distance_to(Orbit.velocity_at(orbit, pos)) < 0.000002, "Velocity reconstruction")
		var energy: float = vel.length_squared() / 2.0 - Orbit.MU / pos.length()
		check(absf(energy + Orbit.MU / (2.0 * a)) < 0.000001, "Vis-viva energy")
		check(pos.cross(vel) > 0.0, "Angular momentum direction preserved")
		var restored: Dictionary = Orbit.state_at(orbit, Orbit.mean_at(orbit, pos))
		check(pos.distance_to(restored.position) < 0.005, "Anomaly inversion preserves position")
		var period: float = TAU * sqrt(a * a * a / Orbit.MU)
		var returned: Dictionary = Orbit.state_at(orbit, m + sqrt(Orbit.MU / (a * a * a)) * period * 1000.0)
		check(pos.distance_to(returned.position) < 0.005, "1000 periods without orbit drift")
	var circle: Dictionary = Orbit.make(240.0, 0.0, 0.0)
	var anchor: Vector2 = Orbit.state_at(circle, 0.5).position
	for index in range(4):
		for offset in [Vector2(130, -85), Vector2(-500, 400), Vector2(2000, 0), Vector2.ZERO]:
			var target: Vector2 = Orbit.endpoint(circle, index) + offset
			var fitted: Dictionary = Orbit.fit_endpoint(anchor, target, index, circle)
			check(Orbit.residual(fitted, anchor) < 0.00001, "Dragged conic passes through anchor")
			check(fitted.e >= 0.0 and fitted.e <= Orbit.MAX_E, "Ellipse only")
			check(fitted.a * (1.0 - fitted.e) >= Orbit.MIN_PERIAPSIS - 0.001, "Surface safety")
			check(fitted.a <= Orbit.MAX_A, "Bounded size")
			check(Orbit.endpoint(fitted, index).distance_to(target) <= Orbit.endpoint(circle, index).distance_to(target) + 0.001, "Fit never worsens mouse distance")
			if offset == Vector2.ZERO:
				check(absf(fitted.e) < 0.000001, "Click without motion keeps circle")
	# Reachable targets generated from valid conics must be reached accurately (all four handles).
	for trial in range(40):
		var target_orbit: Dictionary = Orbit.constrained(anchor, rng.randf_range(0.05, 0.65), rng.randf_range(-PI, PI))
		if target_orbit.is_empty():
			continue
		for index in range(4):
			var reachable: Vector2 = Orbit.endpoint(target_orbit, index)
			var fitted: Dictionary = Orbit.fit_endpoint(anchor, reachable, index, circle)
			check(Orbit.endpoint(fitted, index).distance_to(reachable) < 0.03, "Reachable minor endpoint is solved accurately")
	test_axis_drag(rng)
	# Scene-isolated integration, real scene/controller and event dispatch.
	root.size = Vector2i(1280, 800)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	test_physical_scene(scene)
	# 轨道拖拽已取消：四个旧端点均不响应真实鼠标，直接调用也无效。
	for index in range(4):
		scene.reset()
		scene.manually_paused = true
		await process_frame
		var saved_orbit: Dictionary = scene.orbit.duplicate()
		var saved_position: Vector2 = scene.ship.position
		var saved_velocity: Vector2 = scene.velocity
		var screen_point: Vector2 = scene.get_viewport().get_canvas_transform() * Orbit.endpoint(scene.orbit, index)
		check(not scene.handles[index].visible, "旧轨道端点手柄不可见")
		var press: InputEventMouseButton = InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = screen_point
		Input.parse_input_event(press)
		await process_frame
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = screen_point + Vector2(100, -60)
		motion.relative = Vector2(100, -60)
		Input.parse_input_event(motion)
		await process_frame
		var release: InputEventMouseButton = InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = motion.position
		Input.parse_input_event(release)
		await process_frame
		check(not scene.dragging and scene.orbit == saved_orbit, "真实鼠标拖动旧端点不改变轨道")
		check(scene.ship.position == saved_position and scene.velocity == saved_velocity, "无效鼠标拖动保持暂停状态向量")
		scene.begin_drag(index, Orbit.endpoint(scene.orbit, index))
		check(not scene.dragging and scene.orbit == saved_orbit, "直接调用不能启动已取消的拖拽")
	check(scene.speed_slider.editable, "关闭端点拖拽不影响原有速度滑条")
	print("ORBIT_TESTS checks=%d failures=%d" % [checks, failures])
	scene.queue_free()
	quit(0 if failures == 0 else 1)

func test_physical_units() -> void:
	var mu_si: float = 9.81 * 53000.0 * 53000.0
	check(absf(Orbit.MU - 27.55629) < 1.0e-10, "外部引力参数为27.55629 km³/s²")
	check(absf(Orbit.MU * 1.0e9 - mu_si) < 0.0001, "km和SI引力参数换算一致")
	check(Units.PLANET_RADIUS_KM == 50.0 and Units.FIELD_THICKNESS_KM == 3.0 and Units.FIELD_TOP_RADIUS_KM == 53.0, "行星50km及3km恒强场设定")
	check(absf(Orbit.MU / pow(53.0, 2.0) * 1000.0 - 9.81) < 1.0e-10, "外部逆平方引力在53km与恒强场9.81m/s²衔接")
	var top_orbit: Dictionary = Orbit.make(53.0, 0.0, 0.0)
	var top_state: Dictionary = Orbit.state_at(top_orbit, 0.0)
	var speed_si: float = Units.speed_to_m_s(top_state.velocity.length())
	var period_min: float = Units.seconds_to_minutes(TAU * sqrt(pow(53.0, 3.0) / Orbit.MU))
	check(absf(speed_si - 721.061717192) < 0.001, "场顶圆轨道速度约721m/s")
	check(absf(period_min - 7.697187202) < 0.000001, "场顶圆轨道周期约7.7min")
	check(absf(Units.speed_to_m_s(sqrt(Orbit.MU / 240.0)) - 338.848) < 0.01, "初始240km圆轨道速度使用真实量级")
	check(Orbit.MIN_PERIAPSIS - Units.PLANET_RADIUS_KM == 26.0 and Orbit.MIN_PERIAPSIS > Units.FIELD_TOP_RADIUS_KM, "26km近心安全高度独立于3km场顶")
	print("PHYSICAL_UNITS mu=%.8f km³/s² top_speed=%.6f m/s top_period=%.6f min" % [Orbit.MU, speed_si, period_min])

func test_physical_scene(scene: Node) -> void:
	scene.reset()
	check(scene.simulation_speed == 60.0, "默认1现实秒对应60模拟秒")
	check(scene.unit_label.text.contains("60.0 模拟秒") and scene.unit_label.text.contains("场顶半径 53 km"), "HUD明确时间倍率和场顶半径")
	check(scene.telemetry.text.contains("中心距离   240.00 km") and scene.telemetry.text.contains("当前高度   190.00 km"), "HUD区分中心距离与地表高度")
	check(scene.telemetry.text.contains("近心高度   190.00 km") and scene.telemetry.text.contains("远心高度   190.00 km"), "HUD近远心点显示地表高度")
	check(scene.telemetry.text.contains("m/s") and scene.telemetry.text.contains("min") and not scene.telemetry.text.contains("px"), "HUD速度时间采用物理单位")
	check(scene.speed_label.text.contains("338.85 m/s") and not scene.speed_limits.text.contains("px"), "滑块显示m/s且内部速度保持km/s")
	for vertex in scene.get_node("World/Planet/Surface").polygon:
		check(absf(vertex.length() - 50.0) < 0.00001, "行星表面顶点半径精确为50km")
	for vertex in scene.get_node("World/Planet/Atmosphere").polygon:
		check(absf(vertex.length() - 53.0) < 0.00001, "场顶视觉顶点半径精确为53km")
	var start_m: float = scene.mean_anomaly
	scene._physics_process(1.0)
	check(absf(scene.elapsed_simulation - 60.0) < 0.000001, "1现实秒推进60模拟秒")
	check(absf(scene.mean_anomaly - start_m - sqrt(Orbit.MU / pow(240.0, 3.0)) * 60.0) < 0.000001, "时间倍率仅影响解析相位推进")
	check(scene.telemetry.text.contains("已过模拟     1.00 min"), "HUD将已过模拟秒换算为分钟")
	scene.reset()
	scene.begin_speed_drag()
	var vector_length: float = scene.velocity_line.points[1].distance_to(scene.velocity_line.points[0])
	check(vector_length > 40.0 and vector_length < 80.0, "真实速度量级下箭头仍清晰可见")
	scene.finish_speed_drag(false)
	# 最慢合法远心速率在缩小视图中仍维持屏幕长度与相同比例。
	scene.orbit = Orbit.make(1000.0, 0.85, 0.0)
	scene.mean_anomaly = PI
	scene._refresh_ship()
	var physical_velocity: Vector2 = scene.velocity
	scene.begin_speed_drag()
	var frozen: Vector2 = scene.ship.position
	for zoom_value in [0.22, 1.0, 2.0]:
		scene.camera.zoom = Vector2.ONE * zoom_value
		scene._refresh_geometry()
		var old_screen_length: float = scene.velocity_line.points[1].distance_to(scene.velocity_line.points[0]) * zoom_value
		var new_screen_length: float = scene.new_velocity_line.points[1].distance_to(scene.new_velocity_line.points[0]) * zoom_value
		check(absf(old_screen_length - physical_velocity.length() * scene.VELOCITY_VISUAL_SCALE) < 0.001 and old_screen_length > 7.0, "远心点速度线屏幕长度不随相机缩小")
		check(absf(new_screen_length - old_screen_length) < 0.001, "原新速度线采用同一示意比例")
		check(absf(scene.velocity_line.width * zoom_value - 2.0) < 0.000001 and absf(scene.new_velocity_line.width * zoom_value - 2.0) < 0.000001, "速度线在所有缩放下保持2px线宽")
		check(scene.velocity == physical_velocity and scene.ship.position == frozen, "箭头缩放不影响物理速度和船位置")
	scene.finish_speed_drag(false)
	scene.reset()

func test_axis_drag(rng: RandomNumberGenerator) -> void:
	for trial in range(100):
		var start_e: float = rng.randf_range(0.1, 0.8)
		var start_a: float = rng.randf_range(Orbit.MIN_PERIAPSIS / (1.0 - start_e) + 1.0, 990.0)
		var start: Dictionary = Orbit.make(start_a, start_e, rng.randf_range(-PI, PI))
		var anchor: Vector2 = Orbit.state_at(start, rng.randf_range(-PI, PI)).position
		var start_b: float = start_a * sqrt(1.0 - start_e * start_e)
		for index in range(4):
			var previous: Dictionary = start
			var basis: Array[Vector2] = Orbit.axes(start)
			var outward: Vector2 = basis[index % 2] * (1.0 if index < 2 else -1.0)
			var perpendicular: Vector2 = Vector2(-outward.y, outward.x)
			for displacement in [0.0, 35.0, 120.0, 1000000.0, -35.0, -120.0, -1000000.0, 0.0]:
				var target: Vector2 = Orbit.endpoint(start, index) + outward * displacement
				var fitted: Dictionary = Orbit.fit_axis(anchor, target, index, start, previous, false)
				var candidate: Dictionary = fitted.orbit
				check(Orbit.residual(candidate, anchor) < 0.00001, "锁轴轨道经过冻结船")
				check(candidate.e >= 0.0 and candidate.e <= Orbit.MAX_E + 0.0000001, "锁轴偏心率满足边界")
				check(candidate.a <= Orbit.MAX_A + 0.0001 and candidate.a * (1.0 - candidate.e) >= Orbit.MIN_PERIAPSIS - 0.0001, "锁轴轨道大小与安全距离满足边界")
				if not fitted.snapped:
					var b: float = candidate.a * sqrt(1.0 - candidate.e * candidate.e)
					check(absf(b - start_b) < 0.0001 if index % 2 == 0 else absf(candidate.a - start_a) < 0.0001, "始终锁定拖拽开始的另一根半轴")
				var lateral: Dictionary = Orbit.fit_axis(anchor, target + perpendicular * 200.0, index, start, previous, false)
				check(absf(lateral.orbit.a - candidate.a) < 0.0001 and absf(lateral.orbit.e - candidate.e) < 0.00001, "横向鼠标位移不改变缩放标量")
				if displacement == 0.0 and not fitted.snapped:
					check(absf(candidate.a - start_a) < 0.0001 and absf(candidate.e - start_e) < 0.00001, "返回按下位置恢复原始两轴")
				previous = candidate
	# 可达缩放量精确到达；越界后停在同一边界，不绕到另一角分支。
	var bounded_start: Dictionary = Orbit.make(400.0, 0.6, 0.3)
	var bounded_anchor: Vector2 = Vector2.from_angle(0.3 + acos(1.0 / 9.0)) * 240.0
	for index in range(4):
		var outward: Vector2 = Orbit.axes(bounded_start)[index % 2] * (1.0 if index < 2 else -1.0)
		var base: Vector2 = Orbit.endpoint(bounded_start, index)
		var previous: Dictionary = bounded_start
		for step in range(1, 101):
			var displacement: float = float(step) * (1.0 if index % 2 == 0 else -0.5)
			var fitted: Dictionary = Orbit.fit_axis(bounded_anchor, base + outward * displacement, index, bounded_start, previous, false)
			var candidate: Dictionary = fitted.orbit
			var scalar: float = candidate.a if index % 2 == 0 else candidate.a * sqrt(1.0 - candidate.e * candidate.e)
			check(absf(scalar - ((400.0 if index % 2 == 0 else 320.0) + displacement)) < 0.0001, "可达的半轴缩放量精确到达")
			check(absf(angle_difference(previous.angle, candidate.angle)) < 0.1, "沿连续可行区间保持相邻角分支")
			previous = candidate
		for direction in [-1.0, 1.0]:
			var boundary: Dictionary = Orbit.fit_axis(bounded_anchor, base + outward * direction * 100000.0, index, bounded_start, previous, false)
			var farther: Dictionary = Orbit.fit_axis(bounded_anchor, base + outward * direction * 200000.0, index, bounded_start, boundary.orbit, false)
			check(absf(boundary.orbit.a - farther.orbit.a) < 0.0001 and absf(boundary.orbit.e - farther.orbit.e) < 0.00001, "越过两侧可行边界后停止")
			check(absf(angle_difference(boundary.orbit.angle, farther.orbit.angle)) < 0.0001, "边界不切换椭圆旋转分支")
	# 近圆时才微调锁定轴；进入和退出阈值随屏幕缩放换算。
	var radius: float = 240.0
	for index in range(4):
		var major: bool = index % 2 == 0
		var start_a: float = 260.0 if major else 244.0
		var start_b: float = 236.0 if major else 220.0
		var start: Dictionary = Orbit.make(start_a, sqrt(1.0 - start_b * start_b / (start_a * start_a)), 0.4)
		var cosine: float = (start_b * start_b / start_a - radius) / (radius * start.e)
		var anchor: Vector2 = Vector2.from_angle(start.angle + acos(cosine)) * radius
		var outward: Vector2 = Orbit.axes(start)[index % 2] * (1.0 if index < 2 else -1.0)
		var base: Vector2 = Orbit.endpoint(start, index)
		var start_scalar: float = start_a if major else start_b
		var near_scalar: float = 244.0 if major else 236.0
		var fitted: Dictionary = Orbit.fit_axis(anchor, base + outward * (near_scalar - start_scalar), index, start, start, false)
		check(fitted.snapped and absf(fitted.orbit.a - radius) < 0.0001 and fitted.orbit.e == 0.0, "四端点接近圆时均吸附到锚点半径")
		check(fitted.orbit.angle == start.angle, "圆吸附保留轴角")
		for zoom in [0.5, 1.0, 2.0]:
			var hold_scalar: float = start_b + 14.0 / zoom if major else start_a - 14.0 / zoom
			var target: Vector2 = base + outward * (hold_scalar - start_scalar)
			var held: Dictionary = Orbit.fit_axis(anchor, target, index, start, fitted.orbit, true, zoom)
			var entered: Dictionary = Orbit.fit_axis(anchor, target, index, start, fitted.orbit, false, zoom)
			check(held.snapped and not entered.snapped, "进入10px与退出18px形成缩放独立滞回")
			var exit_scalar: float = start_b + 30.0 / zoom if major else start_a - 30.0 / zoom
			var exited: Dictionary = Orbit.fit_axis(anchor, base + outward * (exit_scalar - start_scalar), index, start, held.orbit, true, zoom)
			check(not exited.snapped and exited.orbit.e > 0.0, "继续拖拽可以退出圆吸附")
			var exited_b: float = exited.orbit.a * sqrt(1.0 - exited.orbit.e * exited.orbit.e)
			check(absf(exited_b - start_b) < 0.0001 if major else absf(exited.orbit.a - start_a) < 0.0001, "退出吸附后恢复拖拽起始轴锁定")
			check(Orbit.residual(exited.orbit, anchor) < 0.00001, "退出圆吸附仍精确过船")
		var nearby_start: Dictionary = Orbit.make(244.0, sqrt(1.0 - 236.0 * 236.0 / (244.0 * 244.0)), start.angle)
		var nearby_cosine: float = (236.0 * 236.0 / 244.0 - radius) / (radius * nearby_start.e)
		var nearby_anchor: Vector2 = Vector2.from_angle(start.angle + acos(nearby_cosine)) * radius
		var nearby_base: Vector2 = Orbit.endpoint(nearby_start, index)
		var untouched: Dictionary = Orbit.fit_axis(nearby_anchor, nearby_base, index, nearby_start, nearby_start, false)
		check(untouched.orbit == nearby_start and not untouched.snapped, "接近圆的椭圆单击不发生吸附跳变")
		var nearby_fit: Dictionary = Orbit.fit_axis(nearby_anchor, nearby_base + outward * (-4.0 if major else 4.0), index, nearby_start, nearby_start, false)
		var return_fit: Dictionary = Orbit.fit_axis(nearby_anchor, nearby_base, index, nearby_start, nearby_fit.orbit, true)
		check(nearby_fit.snapped and return_fit.snapped, "吸附后返回按下标量仍遵守滞回")
		var far_start: Dictionary = Orbit.make(500.0, 0.6, start.angle)
		var far_anchor: Vector2 = Orbit.point_at(far_start, 0.8)
		var far_base: Vector2 = Orbit.endpoint(far_start, index)
		var far_outward: Vector2 = Orbit.axes(far_start)[index % 2] * (1.0 if index < 2 else -1.0)
		var gap: float = -100.0 if major else 100.0
		var far_fit: Dictionary = Orbit.fit_axis(far_anchor, far_base + far_outward * gap, index, far_start, far_start, false)
		check(not far_fit.snapped, "原始锁定半轴远离锚点圆时不发生远距吸附")
