extends SceneTree
## 独立验证（只读，不改生产代码）：第五关能否真的从行星 A 转移到行星 B 并稳定入轨。
## 运行：
##   godot --headless --path <project> --script res://tests/verify_dual_transfer.gd
## 输出完整状态时间线；退出码非 0 表示转移失败。

const Orbit = preload("res://scripts/kepler_orbit.gd")

const SUB_STEP: float = 0.25
const TIME_LIMIT: float = 6000.0

var checks: int = 0
var failures: int = 0
var level: Node
var sandbox: Node

var transitions: Array[Dictionary] = []
var continuity_problems: Array[String] = []
var capture_samples: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)

func snap() -> Dictionary:
	return {
		"t": sandbox.elapsed_simulation,
		"pos": sandbox.ship.position,
		"vel": sandbox.velocity,
		"speed": sandbox.velocity.length(),
		"focus": sandbox.focus_index,
		"mode": sandbox.motion_mode,
		"acquired": sandbox.orbit_acquired,
		"r_local": sandbox.local_position().length(),
	}

func describe(state: Dictionary) -> String:
	var pos: Vector2 = state.pos
	var vel: Vector2 = state.vel
	return "t=%9.3f mode=%-12s focus=%d acquired=%-5s pos=(%9.3f, %8.3f) vel=(%+8.5f, %+8.5f) |v|=%.5f r_local=%.3f" % [
		state.t, state.mode, state.focus, str(state.acquired), pos.x, pos.y, vel.x, vel.y, state.speed, state.r_local]

## a/e 都取关卡允许的上限值；出球点转到 theta 角，使惯性直线以可控瞄准距离穿过 B。
func transfer_orbit(a: float, e: float, theta: float) -> Dictionary:
	var p: float = a * (1.0 - e * e)
	var nu_exit: float = acos(clampf((p / 400.0 - 1.0) / e, -1.0, 1.0))
	return Orbit.make(a, e, theta - nu_exit)

func mean_at_radius(orbit: Dictionary, radius: float) -> float:
	var a: float = float(orbit.a)
	var e: float = float(orbit.e)
	if e < 0.000000001:
		return 0.0
	var eccentric: float = acos(clampf((1.0 - radius / a) / e, -1.0, 1.0))
	return eccentric - e * sin(eccentric)

func place_ship(orbit: Dictionary, radius: float) -> void:
	sandbox.focus_index = 0
	sandbox.gravity_radius = float(sandbox.bodies[0].gravity_radius_km)
	sandbox.motion_mode = "ORBIT"
	sandbox.orbit_acquired = true
	sandbox.orbit = orbit
	sandbox.preview = orbit.duplicate()
	sandbox.orbit_direction = 1.0
	sandbox.mean_anomaly = mean_at_radius(orbit, radius)
	sandbox.velocity = Vector2.ZERO
	sandbox.manually_paused = false
	sandbox.pending_simulation_time = 0.0
	sandbox.capture_remaining = 0.0
	sandbox.capture_elapsed = 0.0
	sandbox.elapsed_simulation = 0.0
	sandbox._refresh_ship()

func run() -> void:
	root.size = Vector2i(1280, 800)
	level = load("res://scenes/level_5.tscn").instantiate()
	root.add_child(level)
	await process_frame
	sandbox = level.sandbox
	sandbox.set_physics_process(false)

	for index in range(level.config.tutorial.size()):
		level._show_page(index)
	level._start_level()
	check(not paused, "开始关卡后场景树未暂停")
	check(sandbox.has_second_planet() and sandbox.bodies.size() == 2, "沙盒包含两颗天体")

	# 主用例：a=1000 km、e=0.85（都在 MAX_A/MAX_E 上限内）。
	# 远心点 1850 km >> 400 km 边界，近心点 150 km >= 76 km。
	# 出球真实近点角约 111.1°；把出球点放在 +x 下方 10°，惯性段以约 182 km 瞄准距离穿过 B。
	var orbit: Dictionary = transfer_orbit(1000.0, 0.85, deg_to_rad(-10.0))
	place_ship(orbit, 300.0)

	var start: Dictionary = snap()
	print("INITIAL: ", describe(start))
	check(start.r_local > 299.0 and start.r_local < 301.0, "起始点位于上升段 r=300 km")
	check(float(orbit.a) * (1.0 + float(orbit.e)) > 400.0, "远心点 %.1f km 超出引力边界 400 km" % (float(orbit.a) * (1.0 + float(orbit.e))))
	check(float(orbit.a) * (1.0 - float(orbit.e)) >= Orbit.MIN_PERIAPSIS - 0.0001, "近心点 %.1f km 不小于安全近心点" % (float(orbit.a) * (1.0 - float(orbit.e))))

	var final_state: Dictionary = fly(TIME_LIMIT, true)

	print("\n=== FLIGHT TIMELINE ===")
	for record: Dictionary in transitions:
		print(describe(record.before))
		print("    ==> " + describe(record.after))
		print("    Δpos=%.6f km  Δ|v|=%.9f km/s" % [float(record.jump), float(record.speed_delta)])
	for sample: Dictionary in capture_samples:
		print("CAPTURE t=%8.2f r=%8.3f e=%12.8f |v-vc|=%.8f km/s" % [sample.t, sample.radius, sample.e, sample.dv_to_circular])

	var left_a: bool = false
	var entered_b: bool = false
	var passed_b: bool = false
	var collided: bool = false
	var capture_failed: bool = false
	for record: Dictionary in transitions:
		var before: Dictionary = record.before
		var after: Dictionary = record.after
		if after.mode == "FREE" and after.focus == 0:
			left_a = true
		if after.focus == 1 and before.focus == 0:
			entered_b = true
		if after.mode == "FREE" and after.focus == 1:
			passed_b = true
		if after.mode == "COLLISION":
			collided = true
		if after.mode == "CAPTURE_FAILED":
			capture_failed = true

	print("\n=== FLIGHT SUMMARY ===")
	print("left A into FREE: ", left_a)
	print("entered B sphere (focus 0->1): ", entered_b)
	print("passed through B back to FREE: ", passed_b)
	print("collision: ", collided, " capture_failed: ", capture_failed)
	print("final: ", describe(final_state))
	print("transitions=%d continuity_problems=%d" % [transitions.size(), continuity_problems.size()])
	for problem: String in continuity_problems:
		printerr("CONTINUITY: ", problem)

	check(left_a, "飞船从 A 的引力区以 FREE 惯性状态出球")
	check(entered_b, "惯性段后进入 B 的引力球（focus_index 变为 1）")
	check(not collided, "全程未撞击任一行星表面")
	check(not passed_b, "飞船没有穿过 B 的引力球后重新变为 FREE")
	check(not capture_failed, "自动圆化没有超时失败")
	check(final_state.mode == "ORBIT" and final_state.acquired and final_state.focus == 1,
		"最终稳定在 B 的圆轨道（ORBIT + orbit_acquired + focus_index=1）")
	check(continuity_problems.is_empty(), "跨球前后位置与速度模长连续")

	level._physics_process(0.0)
	check(level.completed, "level_5 的 orbit_body 胜利条件被触发")
	check(level.victory_controls.visible, "通关后显示顶部操作")

	# 参数扫描：验证关卡是否只在极端椭圆下可行，以及哪些出球方向会失败。
	print("\n=== SLIDER-DRIVEN ATTEMPT (真实可用控件：速度滑块拉满) ===")
	slider_attempt()

	print("\n=== PARAMETER SWEEP ===")
	sweep()

	print("\nDUAL_TRANSFER checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

## 推进模拟；record=true 时记录转移事件。返回最后一帧状态。
func fly(limit: float, record: bool) -> Dictionary:
	var previous: Dictionary = snap()
	var elapsed: float = float(sandbox.elapsed_simulation)
	var last_capture_sample: float = -1000.0
	var final_state: Dictionary = previous
	while elapsed < limit:
		var before: Dictionary = snap()
		sandbox._advance_motion(SUB_STEP)
		if sandbox.pending_simulation_time > 0.000000001:
			continuity_problems.append("t=%.3f 数值步预算溢出 pending=%.9f" % [elapsed, sandbox.pending_simulation_time])
			break
		elapsed += SUB_STEP
		sandbox.elapsed_simulation = elapsed
		var after: Dictionary = snap()

		var jump: float = after.pos.distance_to(before.pos)
		var bound: float = maxf(before.speed, after.speed) * SUB_STEP * 1.05 + 0.0001
		if jump > bound:
			continuity_problems.append("t=%.3f 位置跳变 %.5f km > 上界 %.5f km (%s->%s)" % [elapsed, jump, bound, before.mode, after.mode])

		if (after.mode != before.mode or after.focus != before.focus) and record:
			var boundary_handoff: bool = (after.focus != before.focus) or (before.mode == "ORBIT" and after.mode == "FREE")
			transitions.append({"before": before, "after": after, "jump": jump, "speed_delta": absf(after.speed - before.speed)})
			if boundary_handoff and absf(after.speed - before.speed) > 0.0001:
				continuity_problems.append("t=%.3f 跨球速度模长跳变 %.9f km/s" % [elapsed, absf(after.speed - before.speed)])

		if record and after.mode == "CAPTURE_BURN" and elapsed - last_capture_sample >= 30.0:
			last_capture_sample = elapsed
			var local: Vector2 = sandbox.local_position()
			var recovered: Dictionary = Orbit.from_state(local, sandbox.velocity, local.angle(), sandbox.focus_mu())
			var eccentricity: float = float(recovered.get("orbit", {}).get("e", -1.0))
			var radius: float = local.length()
			var tangent: Vector2 = Vector2(-local.y, local.x).normalized() * sandbox.capture_direction
			var desired: Vector2 = tangent * sqrt(sandbox.focus_mu() / maxf(radius, sandbox.focus_field_top()))
			capture_samples.append({"t": elapsed, "e": eccentricity, "radius": radius, "speed": sandbox.velocity.length(), "dv_to_circular": sandbox.velocity.distance_to(desired)})

		if after.mode == "ORBIT" and after.focus == 1 and after.acquired:
			return after
		if after.mode == "COLLISION" or after.mode == "CAPTURE_FAILED":
			return after
		if after.mode == "FREE" and after.focus == 1:
			return after
		previous = after
	return snap()

## 用玩家真实可用的速度滑块把轨道拉到合法上限，验证不依赖注入的达成路径。
func slider_attempt() -> void:
	place_ship(Orbit.make(240.0, 0.0, 0.0), 240.0)
	# 把飞船放到 245° 相位：此处切向加速后出球方向可指向 B。
	sandbox.mean_anomaly = deg_to_rad(245.0)
	sandbox._refresh_ship()
	sandbox._refresh_geometry()
	sandbox._update_hud()
	print("SLIDER START: ", describe(snap()))
	sandbox.begin_speed_drag()
	sandbox.change_speed(1.0)
	sandbox.finish_speed_drag(true)
	print("SLIDER COMMITTED: a=%.3f e=%.4f angle=%.2f° speed=%.5f km/s" % [float(sandbox.orbit.a), float(sandbox.orbit.e), rad_to_deg(float(sandbox.orbit.angle)), sandbox.velocity.length()])
	var state: Dictionary = fly(4000.0, false)
	print("SLIDER RESULT: ", describe(state))
	check(state.mode == "ORBIT" and state.focus == 1 and state.acquired, "只用速度滑块（拉满）也能从 A 转移到 B 并入轨")

func sweep() -> void:
	var cases: Array[Dictionary] = [
		{"a": 1000.0, "e": 0.85, "theta": -20.0},
		{"a": 1000.0, "e": 0.85, "theta": -10.0},
		{"a": 1000.0, "e": 0.85, "theta": 0.0},
		{"a": 1000.0, "e": 0.85, "theta": 5.0},
		{"a": 900.0, "e": 0.80, "theta": -10.0},
		{"a": 900.0, "e": 0.80, "theta": 0.0},
		{"a": 700.0, "e": 0.70, "theta": -10.0},
		{"a": 700.0, "e": 0.70, "theta": 0.0},
		{"a": 500.0, "e": 0.60, "theta": -10.0},
		{"a": 500.0, "e": 0.60, "theta": 0.0},
		{"a": 1000.0, "e": 0.85, "theta": -90.0},
	]
	for item: Dictionary in cases:
		var orbit: Dictionary = transfer_orbit(float(item.a), float(item.e), deg_to_rad(float(item.theta)))
		place_ship(orbit, 300.0)
		var state: Dictionary = fly(1500.0, false)
		var outcome: String = outcome_of(state)
		print("SWEEP a=%6.0f e=%.2f theta=%+4.0f -> %-22s t=%8.2f mode=%-12s focus=%d r=%.1f" % [
			item.a, item.e, item.theta, outcome, state.t, state.mode, state.focus, state.r_local])

func outcome_of(state: Dictionary) -> String:
	if state.mode == "ORBIT" and state.focus == 1 and state.acquired:
		return "SUCCESS(orbit B)"
	if state.mode == "COLLISION":
		return "COLLISION"
	if state.mode == "CAPTURE_FAILED":
		return "CAPTURE_FAILED"
	if state.mode == "FREE":
		return "REMAIN_FREE(missed)"
	return "TIMEOUT_" + str(state.mode)
