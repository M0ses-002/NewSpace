extends SceneTree
const Orbit = preload("res://scripts/kepler_orbit.gd")
var checks: int = 0
var failures: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func analytic_e(beta: float, gamma: float) -> float:
	return sqrt(maxf(0.0, 1.0 - beta * (2.0 - beta) * cos(gamma) * cos(gamma)))

func run() -> void:
	# 黄金值：闭式可行偏角。
	check(absf(Orbit.heading_limit(240.0, 240.0) - 0.75235) < 0.0001, "黄金值 heading_limit(240,240) got=%s" % Orbit.heading_limit(240.0, 240.0))
	check(Orbit.heading_limit(76.0, 240.0) == 0.0, "黄金值 heading_limit(76,240) 为空可行域")
	check(absf(Orbit.heading_limit(240.0, 1000.0) - 0.62573) < 0.0001, "黄金值 heading_limit(240,1000) 由闭式重算 got=%s" % Orbit.heading_limit(240.0, 1000.0))
	check(absf(Orbit.heading_limit(225.61, 225.61) - 0.72499) < 0.0001, "高近心边界处余量由闭式重算 got=%s" % Orbit.heading_limit(225.61, 225.61))
	# 无效定义域与病态输入。
	for invalid in [Vector2.ZERO, Vector2(-10.0, 0.0)]:
		check(Orbit.heading_limit(invalid.x, 240.0) == 0.0, "非正半径返回0")
	check(Orbit.heading_limit(240.0, 0.0) == 0.0 and Orbit.heading_limit(240.0, -5.0) == 0.0, "非正半长轴返回0")
	check(Orbit.heading_limit(240.0, 100.0) == 0.0, "beta>=2 返回0")
	check(Orbit.heading_limit(240.0, 1000.0, 0.999999) >= 0.0 and Orbit.heading_limit(240.0, 480.0, 0.0) == 0.0, "零偏心率上限无可行域")
	check(Orbit.heading_limit(INF, 240.0) == 0.0 and Orbit.heading_limit(240.0, NAN) == 0.0, "非有限输入返回0")
	# e_cap 三条上限取最紧。
	check(absf(Orbit.heading_eccentricity_limit(240.0, 76.0, 0.85, 1000.0) - (1.0 - 76.0 / 240.0)) < 0.000001, "偏心率上限受近心约束")
	check(absf(Orbit.heading_eccentricity_limit(300.0, 76.0, 0.85, 360.0) - 0.2) < 0.000001, "偏心率上限受远心约束")
	check(absf(Orbit.heading_eccentricity_limit(200.0, 76.0, 0.5, 1000.0) - 0.5) < 0.000001, "偏心率上限受总e约束")
	check(Orbit.heading_eccentricity_limit(0.0, 76.0, 0.85, 1000.0) == 0.0, "半长轴非正时偏心率上限为0")
	check(Orbit.heading_eccentricity_limit(400.0, 76.0, 0.85, 360.0) == 0.0, "远心低于当前半长轴时上限为0")
	# 600 组随机真实轨道状态。
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261107
	var tested: int = 0
	for trial in range(600):
		var e: float = rng.randf_range(0.0, Orbit.MAX_E)
		var a: float = rng.randf_range(Orbit.MIN_PERIAPSIS / (1.0 - e), Orbit.MAX_A)
		var source: Dictionary = Orbit.make(a, e, rng.randf_range(-PI, PI))
		var direction: float = 1.0 if trial % 2 == 0 else -1.0
		var state: Dictionary = Orbit.state_at(source, rng.randf_range(-PI, PI), direction)
		var position: Vector2 = state.position
		var velocity: Vector2 = state.velocity
		var speed: float = velocity.length()
		var radius: float = position.length()
		var beta: float = 2.0 - radius * speed * speed / Orbit.MU
		var osculating: float = radius / beta
		var gamma_max: float = Orbit.heading_limit(radius, osculating)
		check(gamma_max >= 0.0 and gamma_max < PI / 2.0, "可行偏角在[0,90°)内")
		if gamma_max <= 0.0:
			continue
		tested += 1
		var base_velocity: Vector2 = Orbit.heading_velocity(position, speed, 0.0, direction)
		check(absf(base_velocity.length() - speed) < 0.000001, "零偏角构造保持速率")
		var base_state: Dictionary = Orbit.from_state(position, base_velocity, source.angle)
		check(not base_state.is_empty(), "零偏角可行")
		for fraction in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var gamma: float = gamma_max * fraction
			var turned: Vector2 = Orbit.heading_velocity(position, speed, gamma, direction)
			check(absf(turned.length() - speed) < 0.000001, "转向构造严格保持速率")
			check(absf(Orbit.flight_path_angle(position, turned, direction) - gamma) < 0.00001, "偏角构造与反读一致")
			var recovered: Dictionary = Orbit.from_state(position, turned, source.angle)
			# 边界处必须可反解，这是滑块不空转的关键。
			check(not recovered.is_empty(), "可行域内状态可反解 gamma=%s" % gamma)
			if recovered.is_empty():
				continue
			check(absf(float(recovered.orbit.a) - osculating) / osculating < 0.0002, "转向保持半长轴 a=%s osc=%s" % [recovered.orbit.a, osculating])
			var expected_e: float = analytic_e(beta, gamma)
			check(absf(float(recovered.orbit.e) - expected_e) < 0.00002, "偏心率与解析式一致 e=%s expected=%s" % [recovered.orbit.e, expected_e])
			check(float(recovered.orbit.e) <= Orbit.MAX_E + 0.000001 and float(recovered.orbit.a) * (1.0 - float(recovered.orbit.e)) >= Orbit.MIN_PERIAPSIS - 0.0001, "转向轨道满足偏心率与近心边界")
			check(Orbit.residual(recovered.orbit, position) < 0.00002, "转向轨道经过固定位置")
			check(recovered.direction == direction, "转向不改绕行方向")
			var analytic_dv: float = 2.0 * speed * sin(absf(gamma) * 0.5)
			check(absf(base_velocity.distance_to(turned) - analytic_dv) < 0.00001, "Δv 等于 2v sin(Δγ/2)")
		# 闭式 γ_max 与数值求解近心/偏心率边界一致。
		var cap: float = minf(Orbit.MAX_E, 1.0 - Orbit.MIN_PERIAPSIS / osculating)
		if cap < Orbit.MAX_E - 0.000001:
			var low: float = 0.0
			var high: float = PI * 0.4999
			for i in range(48):
				var middle: float = (low + high) * 0.5
				if analytic_e(beta, middle) <= cap:
					low = middle
				else:
					high = middle
			check(absf(low - gamma_max) < 0.0001, "γ_max 与近心边界数值解一致 closed=%s numeric=%s" % [gamma_max, low])
		else:
			var low_e: float = 0.0
			var high_e: float = PI * 0.4999
			for i in range(48):
				var middle_e: float = (low_e + high_e) * 0.5
				if analytic_e(beta, middle_e) <= Orbit.MAX_E:
					low_e = middle_e
				else:
					high_e = middle_e
			check(absf(low_e - gamma_max) < 0.0001, "γ_max 与总偏心率边界数值解一致 closed=%s numeric=%s" % [gamma_max, low_e])
	check(tested > 400, "随机样本多数存在旋转余量 tested=%d" % tested)
	# 空可行域：当前位置已贴在近心安全半径上。
	for orbit in [Orbit.make(240.0, 0.0, 0.3), Orbit.make(76.0, 0.0, 0.0), Orbit.make(400.0, 0.8, 1.0)]:
		for anomaly in [0.0, 0.4, PI, -1.2]:
			var boundary: Dictionary = Orbit.state_at(orbit, anomaly)
			var boundary_radius: float = boundary.position.length()
			var boundary_beta: float = 2.0 - boundary_radius * boundary.velocity.length_squared() / Orbit.MU
			var boundary_a: float = boundary_radius / boundary_beta
			var limit: float = Orbit.heading_limit(boundary_radius, boundary_a)
			check(limit >= 0.0 and limit < PI * 0.5, "边界状态可行域有限")
			if limit > 0.0:
				check(not Orbit.from_state(boundary.position, Orbit.heading_velocity(boundary.position, boundary.velocity.length(), limit, 1.0), orbit.angle).is_empty(), "边界偏角状态可反解")
	# 近心安全半径处没有余量。
	var surface: Dictionary = Orbit.state_at(Orbit.make(76.0, 0.0, 0.0), 0.0)
	var surface_beta: float = 2.0 - 76.0 * surface.velocity.length_squared() / Orbit.MU
	check(Orbit.heading_limit(76.0, 76.0 / surface_beta) == 0.0, "最小近心半径处零余量")
	print("ORBIT_HEADING_TESTS checks=%d failures=%d tested=%d" % [checks, failures, tested])
	quit(0 if failures == 0 else 1)
