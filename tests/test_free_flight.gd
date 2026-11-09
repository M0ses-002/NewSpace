extends SceneTree
const Flight = preload("res://scripts/free_flight.gd")
const Orbit = preload("res://scripts/kepler_orbit.gd")
const Config = preload("res://scripts/simulation_config.gd")
const Units = preload("res://scripts/game_units.gd")
var checks: int = 0
var failures: int = 0
var scene: Node

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", description)

func save_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func run() -> void:
	root.size = Vector2i(1280, 800)
	Config.ensure_loaded()
	check(Config.last_errors.is_empty(), "工程JSON实际读取成功")
	check(Config.planet.gravity_radius_km == 400.0 and Config.ship.max_acceleration_m_s2 == 10.0, "默认范围与可调原型参数")
	var p: Dictionary = Config.DEFAULT_PLANET.duplicate(true)
	var s: Dictionary = Config.DEFAULT_SHIP.duplicate(true)
	p.radius_km = 60.0
	p.field_thickness_km = 4.0
	p.min_periapsis_km = 90.0
	p.gravity_radius_km = 500.0
	p.max_semi_major_axis_km = 1200.0
	p.max_eccentricity = 0.75
	s.initial_orbit_radius_km = 260.0
	s.max_acceleration_m_s2 = 20.0
	s.free_flight_max_speed_m_s = 1500.0
	save_json("user://test_free_planet.json", p)
	save_json("user://test_free_ship.json", s)
	check(Config.load_files("user://test_free_planet.json", "user://test_free_ship.json"), "临时JSON文件注入成功")
	check(absf(Orbit.MU - 9.81 / 1000.0 * 64.0 * 64.0) < 0.0000001, "配置驱动数学MU")
	check(Orbit.MIN_PERIAPSIS == 90.0 and Orbit.MAX_A == 1200.0 and Orbit.MAX_E == 0.75, "配置驱动数学边界")
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	await process_frame
	check(scene.initial_radius == 260.0 and scene.gravity_radius == 500.0, "配置驱动场景初轨道与范围")
	check(scene.flight.max_acceleration == 0.02 and scene.flight.max_speed == 1.5, "自由参数转换km/s和km/s²")
	check(absf(scene.get_node("World/Planet/Surface").polygon[0].length() - 60.0) < 0.001, "配置驱动地表图形尺寸")
	check(absf(scene.get_node("World/Planet/Atmosphere").polygon[0].length() - 64.0) < 0.001, "配置驱动恒强场图形尺寸")
	check(scene.simulation_speed == 60.0, "配置不覆盖既有60倍率")
	scene.queue_free()
	await process_frame
	var bad: Dictionary = p.duplicate(true)
	bad.radius_km = "60"
	check(not Config.parse_dictionaries(bad, s).valid, "拒绝字符串类型")
	bad.radius_km = true
	check(not Config.parse_dictionaries(bad, s).valid, "拒绝布尔类型")
	bad.radius_km = INF
	check(not Config.parse_dictionaries(bad, s).valid, "拒绝非有限值")
	bad.radius_km = -5.0
	check(not Config.parse_dictionaries(bad, s).valid, "拒绝负值")
	bad = p.duplicate(true)
	bad.gravity_radius_km = 50.0
	var invalid: Dictionary = Config.parse_dictionaries(bad, s)
	check(not invalid.valid and invalid.planet == Config.DEFAULT_PLANET and invalid.ship == Config.DEFAULT_SHIP, "相互边界错误整体安全默认")
	check(not Config.parse_dictionaries({}, s).valid, "拒绝缺失字段")
	save_json("user://test_free_planet.json", bad)
	check(not Config.load_files("user://test_free_planet.json", "user://test_free_ship.json"), "真实文件非法边界整体回退")
	check(Config.planet == Config.DEFAULT_PLANET and Config.ship == Config.DEFAULT_SHIP and not Config.last_errors.is_empty(), "真实文件回退含明确错误")
	check(Config.load_files(), "恢复真实工程JSON")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_free_planet.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_free_ship.json"))
	for distance in [1.0, 20.0, 100.0, 1000.0]:
		var f = Flight.new()
		f.set_state(Vector2(600, 0), Vector2.ZERO)
		check(f.plan(Vector2(600 + distance, 0), 400.0), "可规划同侧直线")
		var cruise: bool = false
		for segment in f.segments:
			cruise = cruise or segment.phase == "CRUISE"
		check(cruise == (distance > 100.0), "短途三角与长途梯形判定")
		for i in range(5000):
			if f.phase == "ARRIVED":
				break
			var previous_v: Vector2 = f.velocity
			var previous_p: Vector2 = f.position
			f.advance(0.37)
			check(f.velocity.distance_to(previous_v) <= f.max_acceleration * 0.37 + 0.00001, "每步速度变化受最大加速度约束")
			check(f.velocity.length() <= f.max_speed + 0.00001, "速度不超上限")
			check(absf(f.position.y) < 0.0001 and f.position.x >= previous_p.x - 0.0001, "直线前进无过冲")
		check(f.phase == "ARRIVED" and f.velocity == Vector2.ZERO and f.position.distance_to(f.target) < 0.0001, "三段精准停靠")
	var f = Flight.new()
	f.set_state(Vector2(700, 0), Vector2.ZERO)
	check(f.plan(Vector2(700, 0), 400.0) and f.phase == "ARRIVED", "静止位置目标立即抵达")
	f.set_state(Vector2(700, 0), Vector2(0.3, 0.4))
	check(f.plan(Vector2(950, 200), 400.0) and f.phase == "BRAKE", "任意继承方向先有限加速度制动")
	var initial_p: Vector2 = f.position
	var initial_v: Vector2 = f.velocity
	var old_target: Vector2 = f.target
	check(not f.plan(Vector2(NAN, 0), 400.0) and f.target == old_target and f.phase == "BRAKE", "拒绝非有限目标保留旧计划")
	var saved_acc: float = f.max_acceleration
	f.max_acceleration = 0.0
	check(not f.plan(Vector2(900, 100), 400.0), "拒绝零加速度")
	f.max_acceleration = INF
	check(not f.plan(Vector2(900, 100), 400.0), "拒绝非有限加速度")
	f.max_acceleration = saved_acc
	f.max_speed = NAN
	check(not f.plan(Vector2(900, 100), 400.0), "拒绝非有限巡航上限")
	f.max_speed = 1.0
	f.velocity = Vector2(INF, 0)
	check(not f.plan(Vector2(900, 100), 400.0), "拒绝非有限速度状态")
	f.velocity = initial_v
	f.position = Vector2(NAN, 0)
	check(not f.plan(Vector2(900, 100), 400.0), "拒绝非有限位置状态")
	f.position = initial_p
	check(not f.plan(Vector2(-900, 0), NAN) and f.target == old_target and f.phase == "BRAKE", "拒绝非有限引力半径重设保留旧目标和计划")
	f.advance(10.0)
	check(f.position.distance_to(initial_p + initial_v * 10.0 - initial_v.normalized() * 0.5) < 0.0002, "制动位置连续解析积分")
	check(f.velocity.distance_to(initial_v - initial_v.normalized() * 0.1) < 0.00001, "制动速度真实渐变")
	var replan_p: Vector2 = f.position
	var replan_v: Vector2 = f.velocity
	check(f.plan(Vector2(1000, -100), 400.0) and f.position == replan_p and f.velocity == replan_v and f.phase == "BRAKE", "重新指定不重置状态")
	f.advance(60.0)
	check(f.position.distance_to(replan_p) > 0.0, "60倍大步长跨阶段连续推进")
	f.advance(100000.0)
	check(f.position == Vector2(1000, -100) and f.velocity == Vector2.ZERO and f.phase == "ARRIVED", "超大步长精确停靠不瞬移越过")
	f.set_state(Vector2(700, 0), Vector2(-3, 0))
	check(not f.plan(Vector2(800, 100), 400.0) and f.last_error.contains("制动"), "制动段穿引力圆拒绝")
	for destination: Vector2 in [Vector2(300, 0), Vector2.ZERO, Vector2(-700, 0), Vector2(400, 0)]:
		f.set_state(Vector2(700, 0), Vector2.ZERO)
		check(f.plan(destination, 400.0) and f.target.distance_to(Vector2(400, 0)) < 0.0001, "圈内/圆心/穿圆外侧/边界点击截为首次交点")
		check(f.last_error.is_empty() and f.route[-1] == destination, "路线保留点击目标")
		f.advance(100000.0)
		check(f.phase == "BOUNDARY" and f.position == f.target and absf(f.velocity.length() - f.max_speed) < 0.00001, "大dt抵达边界保留可达速度")
	f.set_state(Vector2(401, 0), Vector2.ZERO)
	check(f.plan(Vector2.ZERO, 400.0), "短距离可规划入圈")
	var short_remaining: float = f.advance(1000.0)
	check(f.phase == "BOUNDARY" and absf(f.velocity.length() - sqrt(2.0 * f.max_acceleration)) < 0.00001 and f.velocity.length() < f.max_speed and short_remaining > 0.0, "距离不足时仅以可达速度穿界且保留余时")
	f.set_state(Vector2(400, -300), Vector2.ZERO)
	check(f.plan(Vector2(400, 300), 400.0) and f.target == Vector2(400, 300) and not f.boundary_crossing, "纯切线不穿越引力范围")
	f.set_state(Vector2(700, 0), Vector2.ZERO)
	check(f.plan(Vector2(800, 200), 400.0) and f.target == Vector2(800, 200) and not f.target_clipped, "不相交航段保持原目标")
	check(f.plan(Vector2(700, 0), 400.0) and f.phase == "ARRIVED" and f.target == Vector2(700, 0), "圈外零位移目标正常")
	f.set_state(Vector2(700, 0), Vector2(0, 1))
	var brake_end: Vector2 = Vector2(700, 50)
	check(f.plan(Vector2.ZERO, 400.0) and f.phase == "BRAKE", "非零初速先制动再规划截断目标")
	var expected_boundary: Vector2 = brake_end.normalized() * 400.0
	check(f.target.distance_to(expected_boundary) < 0.0001 and f.route[1] == brake_end, "交点基于制动终点而非当前船位")
	check(f.plan(Vector2(-800, 0), 400.0) and f.target.length() > 399.9999, "有效重新指定穿圆目标更新为新边界点")
	var retained_target: Vector2 = f.target
	var retained_segments: Array = f.segments.duplicate(true)
	f.velocity = Vector2(-3, 0)
	check(not f.plan(Vector2(900, 0), 400.0) and f.target == retained_target and f.segments == retained_segments, "制动穿圈拒绝保留上一个计划")
	f.set_state(Vector2(400, 0), Vector2.ZERO)
	check(f.plan(Vector2(700, 0), 400.0) and f.target == Vector2(700, 0), "从边界静止可重新向外规划")
	for start_x: float in [399.999969482421875, 400.0, 400.000030517578125]:
		for outward: Vector2 in [Vector2(500, 0), Vector2(start_x, 100)]:
			f.set_state(Vector2(start_x, 0), Vector2.ZERO)
			check(f.plan(outward, 400.0) and f.target == outward, "R±ULP边界带允许向外和切向离开")
			f.advance(100000.0)
			check(f.phase == "ARRIVED" and f.position == outward and f.velocity == Vector2.ZERO, "R±ULP边界离开目标可达")
		for inward: Vector2 in [Vector2(399, 0), Vector2.ZERO, Vector2(-500, 0)]:
			f.set_state(Vector2(start_x, 0), Vector2.ZERO)
			check(f.plan(inward, 400.0) and f.target == Vector2(400, 0), "R±ULP边界带向内点击截原边界，不能返回圈内目标")
			f.advance(100000.0)
			check(f.phase == "BOUNDARY" and f.position == Vector2(400, 0), "R±ULP向内目标触边交接引力")
		f.set_state(Vector2(start_x, 0), Vector2(-0.1, 0))
		check(not f.plan(Vector2(500, 0), 400.0) and f.last_error.contains("制动"), "R±ULP边界非零向内速度制动入圈仍拒绝")
	f.set_state(Vector2(400, 0), Vector2.ZERO)
	check(f.plan(Vector2(400, 100), 400.0) and f.target == Vector2(400, 100), "精确边界切向目标不能误截原地")
	f.set_state(Vector2(500, 400), Vector2.ZERO)
	check(f.plan(Vector2(-500, 400), 400.0) and f.target == Vector2(-500, 400) and not f.boundary_crossing, "外部纯切线不发生穿界")
	f.set_state(Vector2(700, 0), Vector2(0.4, 0.2))
	f.plan(Vector2(1000, 100), 400.0)
	f.advance(5.0)
	initial_p = f.position
	initial_v = f.velocity
	f.cancel()
	f.advance(60.0)
	check(not f.has_target and f.phase == "INERTIAL" and f.velocity == initial_v and f.position.distance_to(initial_p + initial_v * 60.0) < 0.0002, "取消保持当前速度惯性漂移")
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	await process_frame
	check(Config.ship.turnaround_cooldown_real_s == 10.0, "调头冷却默认十现实秒")
	var bad_turnaround: Dictionary = Config.DEFAULT_SHIP.duplicate(true)
	bad_turnaround.turnaround_cooldown_real_s = 0.0
	check(not Config.parse_dictionaries(Config.DEFAULT_PLANET, bad_turnaround).valid, "调头冷却必须为正数")
	var turn_button: Button = scene.get_node("HUD/Layout/SpeedControl/Turnaround")
	var start_pos: Vector2 = scene.ship.position
	var start_velocity: Vector2 = scene.velocity
	check(turn_button.visible and not turn_button.disabled, "初始轨道允许调头")
	scene.turnaround()
	check(scene.ship.position == start_pos and scene.velocity.distance_to(-start_velocity) < 0.000001, "调头原地反转速度")
	check(scene.turnaround_cooldown == 10.0 and turn_button.disabled and turn_button.text.contains("10.0"), "调头进入十秒冷却并显示倒计时")
	scene._refresh_ship()
	check(scene.ship.position.distance_to(start_pos) < 0.0001 and scene.velocity.distance_to(-start_velocity) < 0.000001, "反向轨道状态连续")
	scene._advance_motion(0.01)
	check((scene.ship.position - start_pos).dot(-start_velocity) > 0.0, "反向轨道向新速度方向推进")
	scene.simulation_speed = 0.0
	scene._physics_process(1.0)
	check(absf(scene.turnaround_cooldown - 9.0) < 0.00001, "冷却按现实时间递减")
	scene.manually_paused = true
	scene._physics_process(1.0)
	check(scene.turnaround_cooldown == 9.0, "暂停冻结冷却")
	scene.manually_paused = false
	scene.speed_dragging = true
	scene._physics_process(1.0)
	check(scene.turnaround_cooldown == 9.0, "轨道编辑冻结冷却")
	scene.speed_dragging = false
	scene._physics_process(9.0)
	check(scene.turnaround_cooldown == 0.0 and scene._can_turnaround(), "十现实秒后再次可用")
	scene.turnaround()
	scene.reset()
	check(scene.turnaround_cooldown == 0.0 and scene._can_turnaround(), "重置恢复首次可用")
	scene.orbit = Orbit.make(240.0, 0.2, 0.3)
	scene.mean_anomaly = 0.7
	scene._refresh_ship()
	start_pos = scene.ship.position
	start_velocity = scene.velocity
	scene.turnaround()
	scene._refresh_ship()
	check(scene.ship.position.distance_to(start_pos) < 0.0001 and scene.velocity.distance_to(-start_velocity) < 0.000001, "椭圆轨道调头无相位或位置跳变")
	scene.reset()
	scene.motion_mode = "FREE"
	scene.flight.set_state(Vector2(700, 0), Vector2(0.4, 0.2))
	scene.flight.plan(Vector2(1000, 100), 400.0)
	scene.ship.position = scene.flight.position
	scene.velocity = scene.flight.velocity
	var free_pos: Vector2 = scene.ship.position
	var free_velocity: Vector2 = scene.velocity
	var free_target: Vector2 = scene.flight.target
	var free_phase: String = scene.flight.phase
	scene._update_hud()
	check(not turn_button.visible and not scene._can_turnaround(), "自由航行隐藏并禁止调头")
	scene.turnaround()
	check(scene.ship.position == free_pos and scene.velocity == free_velocity and scene.flight.target == free_target and scene.flight.phase == free_phase and scene.flight.has_target and scene.turnaround_cooldown == 0.0, "自由航行直接调用不改变航线")
	scene.reset()
	for mode: String in ["NUMERICAL", "CAPTURE_PREP", "CAPTURE_BURN", "CAPTURE_FAILED"]:
		scene.reset()
		scene.motion_mode = mode
		var before_position: Vector2 = scene.ship.position
		var before_velocity: Vector2 = scene.velocity
		scene.turnaround()
		check(scene.motion_mode == "NUMERICAL" and scene.ship.position == before_position and scene.velocity.distance_to(-before_velocity) < 0.000001, mode + " 调头后保持数值状态")
	scene.reset()
	scene.velocity = Vector2.ZERO
	check(not scene._can_turnaround(), "零速度禁止调头")
	scene.velocity = Vector2(1, 0)
	scene.motion_mode = "COLLISION"
	check(not scene._can_turnaround(), "碰撞状态禁止调头")
	scene.motion_mode = "ORBIT"
	scene.combat.dead = true
	check(not scene._can_turnaround(), "死亡状态禁止调头")
	scene.combat.dead = false
	paused = true
	check(not scene._can_turnaround(), "场景树暂停禁止调头")
	paused = false
	scene.reset()
	scene.simulation_speed = 60.0
	scene.orbit = Orbit.make(400.0, 0.6, 0.0)
	scene.preview = scene.orbit.duplicate()
	scene.mean_anomaly = 0.0
	scene._refresh_ship()
	scene._refresh_geometry()
	check(scene.current_line.gradient.get_point_count() >= 4, "完整轨道包含范围内外异色")
	check(scene.current_line.points.size() >= Orbit.polyline(scene.orbit).size(), "完整旧椭圆保留所有点并插入边界")
	scene.begin_drag(0, scene.handles[0].position)
	check(not scene.dragging and not scene.preview_line.visible, "轨道拖拽和预览已关闭")
	scene.finish_drag(false)
	var eccentric_exit: float = PI * 0.5
	var mean_exit: float = eccentric_exit - 0.6
	var n: float = sqrt(Orbit.MU / pow(400.0, 3.0))
	var boundary: Dictionary = Orbit.state_at(scene.orbit, mean_exit)
	scene._advance_motion(mean_exit / n + 120.0)
	check(scene.motion_mode == "FREE", "大步长不跳过出界")
	check(scene.ship.position.distance_to(boundary.position + boundary.velocity * 120.0) < 0.005, "精确边界相位加余时直线漂移")
	check(scene.velocity.distance_to(boundary.velocity) < 0.00001, "保留边界速度")
	check(not scene.speed_slider.editable or scene.motion_mode == "FREE", "范围外状态禁用轨道编辑")
	scene._update_hud()
	check(not scene.speed_slider.editable and not scene.handles[0].visible and not scene.current_line.visible and not scene.telemetry.text.contains("参考椭圆"), "范围外隐藏轨道与手柄")
	scene.begin_drag(0, Vector2.ZERO)
	scene.begin_speed_drag()
	check(not scene.dragging and not scene.speed_dragging, "直接调用也不能范围外编辑")
	set_free(Vector2(-600, 0), Vector2(0, -0.1))
	scene.camera.zoom = Vector2(0.6, 0.6)
	scene._refresh_geometry()
	await process_frame
	var target: Vector2 = Vector2(-750, -100)
	var screen: Vector2 = root.get_canvas_transform() * target
	check(not scene._over_hud(screen), "真实输入目标位于无HUD地图")
	click(screen)
	await process_frame
	check(scene.flight.has_target and scene.flight.target.distance_to(target) < 0.001, "真实Input范围外点击生成目标")
	var current_target: Vector2 = scene.flight.target
	click(scene.speed_slider.global_position + scene.speed_slider.size * 0.5)
	await process_frame
	check(scene.flight.target == current_target, "HUD点击不误下目标单")
	var interior_screen: Vector2 = root.get_canvas_transform() * Vector2.ZERO
	check(not scene._over_hud(interior_screen), "圈内点击测试点不被HUD遮挡")
	click(interior_screen)
	await process_frame
	check(scene.flight.has_target and scene.flight.boundary_crossing and absf(scene.flight.target.length() - 400.0) < 0.0001, "真实左键圈内目标规划穿越边界")
	check(scene.target_marker.position == Vector2.ZERO and scene.route_line.points[-1] == Vector2.ZERO and scene.feedback.text.contains("连续穿越边界"), "真实目标标记路线保留圈内目标")
	current_target = scene.flight.target
	click(scene.speed_slider.global_position + scene.speed_slider.size * 0.5)
	await process_frame
	check(scene.flight.target == current_target, "截断后HUD点击仍不误下单")
	check(scene.free_max_control.visible and not scene.speed_slider.editable, "自由模式最大速度滑条可见且实际速度只读")
	initial_p = scene.ship.position
	initial_v = scene.velocity
	scene.free_max_slider.value = 0.7
	check(absf(scene.flight.max_speed - 0.7) < 0.0001 and scene.ship.position == initial_p and scene.velocity == initial_v, "调整自由速度上限不瞬间改变位置或速度")
	check(absf(scene.speed_slider.value - scene.velocity.length()) < 0.00001, "实际速度滑条显示当前速度")
	scene._advance_motion(10000.0)
	scene._update_hud()
	check(scene.motion_mode != "FREE" and not scene.free_max_control.visible, "航行穿界后交给引力状态且隐藏自由速度滑条")
	set_free(Vector2(-600, 0), Vector2(0, -0.1))
	scene._refresh_geometry()
	scene._update_hud()
	click(screen)
	await process_frame
	var right := InputEventMouseButton.new()
	right.position = screen
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	Input.parse_input_event(right)
	await process_frame
	check(not scene.flight.has_target, "真实右键取消目标")
	click(screen)
	await process_frame
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	check(not scene.flight.has_target, "真实Esc取消目标")
	click(screen)
	await process_frame
	scene.manually_paused = true
	initial_p = scene.ship.position
	initial_v = scene.velocity
	scene._physics_process(60.0)
	check(scene.ship.position == initial_p and scene.velocity == initial_v, "暂停不推进自由飞行")
	scene.manually_paused = false
	scene.cancel_free_flight()
	check(not scene.flight.has_target and not scene.target_marker.visible, "取消隐藏标记路线")
	set_free(Vector2(500, 0), Vector2.ZERO)
	check(scene.set_free_target(Vector2.ZERO), "规划长距离向内穿界")
	var time_to_boundary: float = 0.0
	for segment in scene.flight.segments:
		time_to_boundary += float(segment.duration)
	scene._advance_motion(time_to_boundary - 0.5)
	var before_boundary_p: Vector2 = scene.ship.position
	var before_boundary_v: Vector2 = scene.velocity
	check(scene.motion_mode == "FREE" and before_boundary_v.length() <= scene.flight.max_speed + 0.00001, "穿界前加速连续且未超过上限")
	scene._advance_motion(1.0)
	check(scene.motion_mode != "FREE" and scene.ship.position.distance_to(before_boundary_p + before_boundary_v) < 0.01 and scene.velocity.distance_to(before_boundary_v) < 0.01, "跨界连续位置速度并消化余时")
	set_free(Vector2(400, -1), Vector2(0, 1))
	scene._advance_motion(2.0)
	check(scene.motion_mode == "FREE" and scene.ship.position == Vector2(400, 1) and scene.velocity == Vector2(0, 1), "纯切线触边保持惯性不误入引力")
	set_free(Vector2(400.001, -1), Vector2(0, 1))
	scene._advance_motion(2.0)
	check(scene.motion_mode == "FREE", "近外切线保持范围外")
	set_free(Vector2(399.999, -1), Vector2(0, 1))
	scene._advance_motion(2.0)
	check(scene.motion_mode == "CAPTURE_PREP", "近真实割线回入引力并进入入轨预备")
	set_free(Vector2(450, 0), Vector2(-2, 0.1))
	scene._advance_motion(60.0)
	check(scene.motion_mode in ["CAPTURE_BURN", "CAPTURE_FAILED", "FREE"] and scene.ship.position.length() < 400.0 and scene.ship.position.x > 320.0, "回入真实状态连续数值推进无捕获瞬移")
	set_free(Vector2(400, 0), Vector2(-0.01, 0.25))
	scene._enter_gravity(0.0)
	check(scene.motion_mode == "CAPTURE_PREP" and scene.capture_remaining == 5.0 and not scene.current_line.visible, "入界开始5秒预备并隐藏轨迹")
	scene._advance_motion(2.0)
	check(scene.motion_mode == "CAPTURE_PREP" and absf(scene.capture_remaining - 3.0) < 0.00001, "预备倒计时使用模拟秒")
	scene._advance_motion(3.0)
	check(scene.motion_mode == "CAPTURE_BURN" and scene.capture_remaining == 0.0, "倒计时结束开始圆化")
	for i in range(400):
		if scene.motion_mode != "CAPTURE_BURN":
			break
		var previous_position: Vector2 = scene.ship.position
		var previous_velocity: Vector2 = scene.velocity
		scene._advance_motion(0.25)
		var gravity_delta: Vector2 = (scene._gravity(previous_position) + scene._gravity(scene.ship.position)) * 0.125
		check((scene.velocity - previous_velocity - gravity_delta).length() <= scene.flight.max_acceleration * 0.25 + 0.000005, "入轨推力不超过最大加速度")
	check(scene.motion_mode == "ORBIT" and scene.orbit.e == 0.0 and scene.current_line.visible, "可行入轨连续圆化并恢复显示圆轨道")
	set_free(Vector2(60, 0), Vector2(-2, 0))
	scene._enter_gravity(0.0)
	scene._advance_motion(10.0)
	check(scene.motion_mode == "COLLISION" and scene.velocity == Vector2.ZERO and scene.navigation_feedback.contains("撞击"), "径向入轨碰撞明确停止不虚报成功")
	set_free(Vector2(400, 0), Vector2(-0.01, 4))
	scene._enter_gravity(0.0)
	scene._advance_motion(100.0)
	check(scene.motion_mode == "FREE" and scene.navigation_feedback.contains("失败") and not scene.current_line.visible, "无法入轨的逃逸显示失败且无虚假轨道")
	set_free(Vector2(200, 0), Vector2(0, 0.3))
	scene.motion_mode = "CAPTURE_BURN"
	scene.capture_elapsed = scene.CAPTURE_TIMEOUT
	scene._advance_motion(0.25)
	check(scene.motion_mode == "CAPTURE_FAILED" and scene.navigation_feedback.contains("失败") and not scene.current_line.visible, "超时无法圆化明确失败且轨道不显示")
	set_free(Vector2(100, 0), Vector2(0, sqrt(Orbit.MU / 100.0)))
	scene.motion_mode = "NUMERICAL"
	scene._advance_motion(1000.0)
	check(scene.pending_simulation_time > 0.0 and scene.manually_paused and scene.ship.position.is_finite() and scene.velocity.is_finite(), "异常大数值dt受预算限制并安全暂停且保留未推进时间")
	scene._advance_motion(0.0)
	check(scene.pending_simulation_time < 0.000001, "后续帧消化预算积压不丢时间")
	set_free(Vector2(50.01, 0), Vector2(-1, 0))
	scene.motion_mode = "NUMERICAL"
	scene._advance_motion(0.1)
	scene._update_hud()
	check(scene.motion_mode == "COLLISION" and absf(scene.ship.position.length() - 50.0) < 0.00001 and scene.velocity == Vector2.ZERO, "数值步首次触及行星表面即碰撞停靠不穿透")
	check(scene.ship.position.is_finite() and scene.velocity.is_finite() and scene.status_label.text.contains("碰撞") and scene.manually_paused, "碰撞保持有限状态并明确HUD暂停")
	initial_p = scene.ship.position
	scene._advance_motion(10000.0)
	check(scene.ship.position == initial_p, "碰撞后不再继续移动")
	scene.queue_free()
	await process_frame
	print("FREE_FLIGHT_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func set_free(p: Vector2, v: Vector2) -> void:
	scene.motion_mode = "FREE"
	scene.pending_simulation_time = 0.0
	scene.manually_paused = false
	scene.ship.position = p
	scene.velocity = v
	scene.flight.set_state(p, v)
	scene._refresh_geometry()
	scene._update_hud()

func click(screen: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = screen
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = screen
	event.pressed = false
	Input.parse_input_event(event)
