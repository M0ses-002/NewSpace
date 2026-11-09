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

func run() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 971603
	for trial in range(600):
		var e: float = rng.randf_range(0.0, Orbit.MAX_E)
		var a: float = rng.randf_range(Orbit.MIN_PERIAPSIS / (1.0 - e), Orbit.MAX_A)
		var source: Dictionary = Orbit.make(a, e, rng.randf_range(-PI, PI))
		var direction: float = 1.0 if trial % 2 == 0 else -1.0
		var state: Dictionary = Orbit.state_at(source, rng.randf_range(-PI, PI), direction)
		var recovered: Dictionary = Orbit.from_state(state.position, state.velocity, source.angle)
		check(not recovered.is_empty(), "合法状态可反解")
		if recovered.is_empty():
			continue
		check(absf(recovered.orbit.a - a) < 0.004 and absf(recovered.orbit.e - e) < 0.000004, "状态反解恢复半长轴与偏心率")
		check(recovered.direction == direction, "状态反解保留顺逆时针方向")
		var restored: Dictionary = Orbit.state_at(recovered.orbit, recovered.mean_anomaly, recovered.direction)
		check(restored.position.distance_to(state.position) < 0.005 and restored.velocity.distance_to(state.velocity) < 0.000002, "状态反解位置速度闭环")
		var bounds: Vector2 = Orbit.speed_interval(state.position, state.velocity)
		check(bounds.x > 0.0 and bounds.y >= bounds.x, "当前方向存在有界合法速率区间")
		check(state.velocity.length() >= bounds.x - 0.000001 and state.velocity.length() <= bounds.y + 0.000001, "合法速率区间包含当前速率")
		for fraction in [0.0, 0.1, 0.5, 0.9, 1.0]:
			var requested: float = lerpf(bounds.x, bounds.y, fraction)
			var changed: Vector2 = state.velocity.normalized() * requested
			var fitted: Dictionary = Orbit.from_state(state.position, changed, source.angle)
			check(not fitted.is_empty(), "区间所有采样速率均可反解")
			if fitted.is_empty():
				continue
			check(fitted.orbit.e <= Orbit.MAX_E and fitted.orbit.a <= Orbit.MAX_A and fitted.orbit.a * (1.0 - fitted.orbit.e) >= Orbit.MIN_PERIAPSIS - 0.0001, "调速椭圆满足全部边界")
			check(Orbit.residual(fitted.orbit, state.position) < 0.00001, "调速轨道始终经过原位置")
			var fitted_velocity: Vector2 = Orbit.velocity_at(fitted.orbit, state.position, direction)
			check(fitted_velocity.distance_to(changed) < 0.000002 and fitted_velocity.normalized().dot(state.velocity.normalized()) > 0.999999, "调速只改变速率不改变方向")
		for outside in [bounds.x * 0.999, bounds.y * 1.001]:
			check(Orbit.from_state(state.position, state.velocity.normalized() * outside, source.angle).is_empty(), "合法区间外速率被拒绝")
	for boundary_orbit in [Orbit.make(76.0, 0.0, 0.8), Orbit.make(1000.0, 0.0, -0.4), Orbit.make(1000.0, 0.85, 1.1), Orbit.make(76.0 / 0.15, 0.85, -1.6)]:
		for anomaly in [0.0, 0.000001, 0.7, PI * 0.5, PI - 0.000001, PI]:
			var boundary_state: Dictionary = Orbit.state_at(boundary_orbit, anomaly)
			check(not Orbit.from_state(boundary_state.position, boundary_state.velocity, boundary_orbit.angle).is_empty(), "精确约束边界状态可反解 %s M=%s" % [boundary_orbit, anomaly])
			var boundary_range: Vector2 = Orbit.speed_interval(boundary_state.position, boundary_state.velocity)
			check(boundary_range.x > 0.0 and boundary_range.y >= boundary_range.x, "精确约束边界存在连续速率范围")
	var circle: Dictionary = Orbit.make(240.0, 0.0, 1.2)
	var circle_state: Dictionary = Orbit.state_at(circle, 0.7)
	var circle_fit: Dictionary = Orbit.from_state(circle_state.position, circle_state.velocity, circle.angle)
	check(circle_fit.orbit.e == 0.0 and circle_fit.orbit.angle == circle.angle, "圆反解保留旧轴角")
	for invalid in [Vector2.ZERO, Vector2(10, 0), Vector2(1000, 1000), Vector2(INF, 0), Vector2(NAN, 1)]:
		check(Orbit.from_state(Vector2(240, 0), invalid).is_empty(), "拒绝静止径向逃逸及非有限速度")
	check(Orbit.speed_interval(Vector2(240, 0), Vector2(100, 0)) == Vector2.ZERO, "径向方向没有合法低偏心率椭圆")
	check(Orbit.from_state(Vector2.ZERO, Vector2(10, 20)).is_empty(), "拒绝中心奇点")
	var surface_bounds: Vector2 = Orbit.speed_interval(Vector2(76, 0), Vector2(0, sqrt(Orbit.MU / 76.0)))
	check(surface_bounds.x >= sqrt(Orbit.MU / 76.0) - 0.000001, "安全半径处只允许近心点或圆速率")
	await test_ui()
	await test_circle_speed_ui()
	print("SPEED_SLIDER_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func mouse_button(position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)

func mouse_motion(position: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	Input.parse_input_event(event)

func test_ui() -> void:
	root.size = Vector2i(1280, 800)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	var slider: HSlider = scene.speed_slider
	var signals: Dictionary = {"start": 0, "change": 0, "end": 0}
	slider.drag_started.connect(func() -> void: signals.start += 1)
	slider.value_changed.connect(func(_value: float) -> void: signals.change += 1)
	slider.drag_ended.connect(func(_changed: bool) -> void: signals.end += 1)
	for paused in [false, true]:
		scene.reset()
		scene.manually_paused = paused
		var frozen: Vector2 = scene.ship.position
		var before_velocity: Vector2 = scene.velocity
		var saved_time: float = scene.elapsed_simulation
		var rect: Rect2 = slider.get_global_rect()
		mouse_button(rect.get_center(), true)
		await process_frame
		check(scene.speed_dragging and not scene.dragging, "真实滑块按下进入调速模式")
		scene._physics_process(0.5)
		check(scene.ship.position == frozen and scene.elapsed_simulation == saved_time, "真实滑块拖动暂停解析传播")
		scene.begin_drag(0, Orbit.endpoint(scene.orbit, 0))
		check(not scene.dragging, "调速期间禁止轨道拖拽")
		mouse_motion(rect.position + Vector2(rect.size.x + 300.0, rect.size.y * 0.5))
		await process_frame
		check(scene.speed_limited and scene.speed_label.text.contains("已夹限"), "滑块超出边界显示夹限反馈")
		check(scene.speed_label.text.contains("m/s") and not scene.speed_label.text.contains("px/s") and not scene.speed_label.text.contains("×"), "滑块简洁显示实际速率")
		check(Orbit.residual(scene.preview, frozen) < 0.00001, "真实滑块预览轨道经过冻结船")
		mouse_button(Vector2(1170, 150), false)
		await process_frame
		check(not scene.speed_dragging and scene.ship.position == frozen, "HUD上释放滑块不粘连不跳船")
		check(scene.manually_paused == paused, "滑块释放恢复原手动暂停状态")
		check(scene.velocity.normalized().dot(before_velocity.normalized()) > 0.999999, "真实滑块提交保留速度方向")
		check(scene.last_delta_v > 0.001, "真实滑块提交实际速率变化")
		scene._physics_process(0.1)
		check((scene.ship.position == frozen) == paused, "滑块释放后按原暂停状态传播")
		check(Orbit.residual(scene.orbit, scene.ship.position) < 0.00001, "释放后继续沿新轨道传播")
	check(signals.start == 2 and signals.end == 2 and signals.change >= 2, "真实UI完整触发drag_started/value_changed/drag_ended")
	# Esc取消后继续移动与最终释放不能重新提交。
	scene.reset()
	var original: Dictionary = scene.orbit.duplicate()
	var rect: Rect2 = slider.get_global_rect()
	mouse_button(rect.get_center(), true)
	await process_frame
	mouse_motion(rect.end)
	await process_frame
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	mouse_motion(rect.position)
	await process_frame
	mouse_button(rect.position, false)
	await process_frame
	check(not scene.speed_dragging and scene.orbit == original, "Esc取消后拖动余波不提交速率")
	# 已取消轨道拖拽，尝试拖拽不得阻断速度调节。
	scene.begin_drag(0, Orbit.endpoint(scene.orbit, 0))
	check(not scene.dragging and slider.editable, "轨道拖拽已禁用且速度滑块仍可编辑")
	scene.finish_drag(false)
	check(slider.editable, "无效轨道拖拽后速度滑块仍可编辑")
	# 键盘调速是完整的单次编辑，不能使模拟一直暂停。
	scene.reset()
	slider.grab_focus()
	var before_key: float = scene.velocity.length()
	var arrow: InputEventKey = InputEventKey.new()
	arrow.keycode = KEY_RIGHT
	arrow.pressed = true
	Input.parse_input_event(arrow)
	await process_frame
	check(not scene.speed_dragging and scene.velocity.length() > before_key, "键盘箭头调整实际速率且不留下暂停状态 before=%s after=%s cancelled=%s focus=%s" % [before_key, scene.velocity.length(), scene.speed_cancelled, slider.has_focus()])
	check(absf(scene.velocity.length() - before_key - 0.001) < 0.000001, "键盘每次增加1m/s即0.001km/s")
	check(not scene.speed_limited, "合法1m/s键盘微调不被误报为边界夹限")
	# R在拖动期间重置，不接受滑块释放时的剩余输入。
	mouse_button(rect.get_center(), true)
	await process_frame
	var reset_key: InputEventKey = InputEventKey.new()
	reset_key.keycode = KEY_R
	reset_key.pressed = true
	Input.parse_input_event(reset_key)
	await process_frame
	mouse_motion(rect.end)
	await process_frame
	mouse_button(rect.end, false)
	await process_frame
	check(scene.orbit.e == 0.0 and scene.orbit.a == scene.initial_radius and not scene.speed_dragging, "调速期间R重置后鼠标余波不会覆盖圆轨道")
	# 程序越界输入同样夹至当前连通区间。
	scene.begin_speed_drag()
	scene.change_speed(1000000.0)
	check(scene.speed_limited and not scene.preview.is_empty(), "极大请求夹限为有效椭圆")
	check(Orbit.residual(scene.preview, scene.ship.position) < 0.00001, "极大请求夹限不跳船")
	scene.finish_speed_drag(true)
	scene.begin_speed_drag()
	scene.change_speed(-1000000.0)
	check(scene.speed_limited and scene.preview.e <= Orbit.MAX_E, "极小请求夹限为有效椭圆")
	scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not scene.speed_dragging, "失焦取消速度编辑")
	scene.queue_free()
	await process_frame

func set_orbit(scene: Node, source: Dictionary, anomaly: float, direction: float = 1.0) -> void:
	scene.reset()
	scene.manually_paused = true
	scene.orbit = source.duplicate()
	scene.preview = source.duplicate()
	scene.orbit_direction = direction
	scene.mean_anomaly = anomaly
	scene._refresh_ship()
	scene._refresh_geometry()
	scene._update_hud()

func slider_point(scene: Node, value: float, offset_px: float = 0.0) -> Vector2:
	var slider: HSlider = scene.speed_slider
	var scale_x: float = slider.get_screen_transform().x.length()
	return slider.global_position + Vector2(scene._slider_x(value) + offset_px / scale_x, slider.size.y * 0.5)

func press_key(keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)

func test_circle_speed_ui() -> void:
	root.size = Vector2i(1280, 800)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	scene.reset()
	var slider: HSlider = scene.speed_slider
	var marker: Control = scene.circular_marker
	check(scene.circular_available and marker.visible, "初始圆轨道显示可用圆速标记")
	check(absf(scene.circular_speed - sqrt(Orbit.MU / scene.ship.position.length())) < 0.000001, "圆速标记由当前半径sqrt(MU/r)更新")
	check(scene.circular_label.text.contains("m/s") and scene.circular_label.text.contains("圆速"), "圆速说明简洁显示物理单位")
	check(marker.mouse_filter == Control.MOUSE_FILTER_IGNORE and marker.get_node("Tick").mouse_filter == Control.MOUSE_FILTER_IGNORE, "圆速标记及刻度不拦截鼠标")
	var grabber_width: float = slider.get_theme_icon("grabber").get_width()
	var expected_x: float = grabber_width * 0.5 + slider.ratio * (slider.size.x - grabber_width)
	check(absf(marker.position.x - expected_x) < 0.001, "圆轨道拇指与标记按主题grabber轨道对齐")
	var frozen: Vector2 = scene.ship.position
	var original: Dictionary = scene.orbit.duplicate()
	var point: Vector2 = slider_point(scene, scene.circular_speed)
	mouse_button(point, true)
	await process_frame
	check(scene.speed_dragging and scene.speed_snapped, "点击圆轨道拇指进入吸附且标记不挡输入")
	mouse_button(point, false)
	await process_frame
	check(scene.orbit == original and scene.ship.position == frozen and scene.last_delta_v < 0.000001, "圆轨道零移动按下释放不跳船不产生脉冲")
	# 同一次原生HSlider拖动中验证8/14px滞回与设回value后的继续拖动。
	mouse_button(point, true)
	await process_frame
	mouse_motion(point + Vector2(24, 0))
	await process_frame
	check(not scene.speed_snapped and scene.preview.e > 0.001, "从圆速拖远超过14px可离开吸附")
	mouse_motion(point + Vector2(9, 0))
	await process_frame
	check(not scene.speed_snapped, "未吸附时9px不会提前进入8px阈值")
	mouse_motion(point + Vector2(7, 0))
	await process_frame
	check(scene.speed_snapped and scene.preview.e == 0.0, "真实鼠标进入7px吸附精确e0")
	check(absf(slider.value - scene.circular_speed) < 0.0000001, "吸附后拇指值反映精确圆速")
	mouse_motion(point + Vector2(12, 0))
	await process_frame
	check(scene.speed_snapped and scene.preview.e == 0.0, "已吸附时12px保持14px滞回")
	mouse_motion(point + Vector2(15, 0))
	await process_frame
	check(not scene.speed_snapped, "原生HSlider吸附设值后仍能拖过15px退出")
	mouse_motion(point + Vector2(3, 0))
	await process_frame
	check(scene.speed_snapped, "离开后返回标记可再次吸附")
	mouse_button(point + Vector2(3, 0), false)
	await process_frame
	check(scene.orbit.e == 0.0 and scene.ship.position == frozen and not scene.speed_snapped, "吸附释放提交精确圆且清理事务状态")
	# a=r但径向分量非零：同速零拖动保留椭圆，拖离再回才执行切向圆化。
	set_orbit(scene, Orbit.make(400.0, 0.7, 0.2), PI * 0.5 - 0.7)
	original = scene.orbit.duplicate()
	frozen = scene.ship.position
	var old_velocity: Vector2 = scene.velocity
	point = slider_point(scene, scene.velocity.length())
	check(absf(scene.velocity.length() - scene.circular_speed) < 0.000001 and absf(frozen.dot(old_velocity)) > 1.0, "同圆速椭圆夹具具有非零径向分量")
	mouse_button(point, true)
	await process_frame
	check(not scene.speed_snapped and scene.preview == original, "非切向同圆速椭圆按下不自动圆化")
	mouse_motion(point + Vector2(0, 15))
	await process_frame
	check(not scene.speed_snapped and scene.preview == original, "拇指仅竖向移动不改变速度和方向")
	mouse_button(point, false)
	await process_frame
	check(scene.orbit == original and scene.last_delta_v < 0.000001, "非切向同圆速椭圆零拖动保留原轨道和零Δv")
	mouse_button(point, true)
	await process_frame
	mouse_motion(point + Vector2(26, 0))
	await process_frame
	mouse_motion(point + Vector2(2, 0))
	await process_frame
	check(scene.speed_snapped and scene.preview.e == 0.0, "非切向椭圆真实鼠标返回圆速标记形成精确圆")
	var tangent: Vector2 = Vector2(-frozen.y, frozen.x).normalized() * scene.circular_speed
	var expected_dv: float = tangent.distance_to(old_velocity)
	check(scene._preview_velocity().distance_to(tangent) < 0.000001, "圆化速度为当前位置切线且保持原绕行方向")
	check(expected_dv > absf(tangent.length() - old_velocity.length()) + 0.1, "圆化完整向量Δv大于单纯速率差")
	mouse_button(point + Vector2(2, 0), false)
	await process_frame
	check(scene.ship.position == frozen and scene.orbit.e == 0.0, "非切向圆化提交不瞬移")
	check(scene.manually_paused, "圆速吸附提交保留原手动暂停状态")
	check(absf(scene.last_delta_v - expected_dv) < 0.000001, "圆化提交使用完整向量差计算Δv")
	check(absf(scene.mean_anomaly - Orbit.mean_at(scene.orbit, frozen)) < 0.000001, "圆化后解析相位从冻结船位置恢复")
	scene.manually_paused = false
	scene._physics_process(0.1)
	check(absf(scene.ship.position.length() - frozen.length()) < 0.001 and scene.orbit.e == 0.0, "松开后持续沿新圆轨道传播")
	# 圆速位于旧方向合法范围之外仍可达；离开吸附恢复冻结原方向。
	set_orbit(scene, Orbit.make(400.0, 0.8, 0.4), 0.2)
	frozen = scene.ship.position
	old_velocity = scene.velocity
	check(scene.circular_speed < scene.speed_bounds.x, "偏径向椭圆夹具圆速低于旧方向合法速率下界")
	check(slider.min_value <= scene.circular_speed and marker.visible, "显示范围合并圆速使额外可达标记可见")
	point = slider_point(scene, scene.velocity.length())
	var circle_point: Vector2 = slider_point(scene, scene.circular_speed)
	mouse_button(point, true)
	await process_frame
	mouse_motion(circle_point + Vector2(2, 0))
	await process_frame
	check(scene.speed_snapped and scene.preview.e == 0.0, "旧方向合法范围外圆速仍可真实鼠标吸附")
	mouse_motion(circle_point + Vector2(18, 0))
	await process_frame
	check(not scene.speed_snapped and scene._preview_velocity().normalized().dot(old_velocity.normalized()) > 0.999999, "离开圆速吸附恢复冻结旧方向重建")
	mouse_motion(circle_point)
	await process_frame
	mouse_button(circle_point, false)
	await process_frame
	check(scene.orbit.e == 0.0 and scene.ship.position == frozen, "旧范围外圆速提交仍不瞬移")
	# 逆时针输入必须在圆化、恢复相位、后续传播中保留方向。
	set_orbit(scene, Orbit.make(400.0, 0.7, 0.2), PI * 0.5 - 0.7, -1.0)
	frozen = scene.ship.position
	point = slider_point(scene, scene.velocity.length())
	mouse_button(point, true)
	await process_frame
	mouse_motion(point + Vector2(25, 0))
	await process_frame
	mouse_motion(point)
	await process_frame
	mouse_button(point, false)
	await process_frame
	check(scene.orbit.e == 0.0 and scene.orbit_direction == -1.0 and frozen.cross(scene.velocity) < 0.0, "圆化保留逆时针绕行方向")
	var old_mean: float = scene.mean_anomaly
	scene.manually_paused = false
	scene._physics_process(0.1)
	check(angle_difference(old_mean, scene.mean_anomaly) < 0.0 and scene.ship.position.cross(scene.velocity) < 0.0, "逆时针圆化后的相位与速度传播方向一致")
	# r>MAX_A时隐藏标记且普通调速仍正常。
	set_orbit(scene, Orbit.make(900.0, 0.5, 0.1), PI)
	check(not scene.circular_available and not marker.visible and scene.circular_label.text.contains("不可用"), "当前位置超出1000km圆轨道范围隐藏标记并说明不可用")
	scene.begin_speed_drag()
	scene.change_speed(scene.circular_speed)
	check(not scene.speed_snapped and scene.preview.e > 0.0, "不可用圆半径不会吸附非法圆轨道")
	scene.finish_speed_drag(false)
	# 当前半径和窗口布局改变时标记随之更新，主题拇指轨道两端保留半宽。
	set_orbit(scene, Orbit.make(400.0, 0.5, 0.0), 0.2)
	var first_circle_speed: float = scene.circular_speed
	var first_marker_x: float = marker.position.x
	scene.mean_anomaly = 2.4
	scene._refresh_ship()
	scene._update_hud()
	check(absf(scene.circular_speed - first_circle_speed) > 0.001 and absf(marker.position.x - first_marker_x) > 0.01, "圆速和标记随椭圆实时半径变化更新")
	var original_slider_size: Vector2 = slider.size
	slider.size = Vector2(original_slider_size.x + 80.0, original_slider_size.y)
	check(absf(marker.position.x - scene._slider_x(scene.circular_speed)) < 0.001, "滑块resized信号立即重定位圆速标记")
	root.size = Vector2i(1536, 960)
	await process_frame
	check(absf(marker.position.x - scene._slider_x(scene.circular_speed)) < 0.001 and marker.visible, "窗口尺寸变化后圆速标记仍对齐轨道")
	root.size = Vector2i(1280, 800)
	await process_frame
	# 取消、重置、失焦后的原生拖动余波不能提交圆化。
	for cancel_key in [KEY_ESCAPE, KEY_R, KEY_NONE]:
		set_orbit(scene, Orbit.make(400.0, 0.7, 0.2), PI * 0.5 - 0.7)
		original = scene.orbit.duplicate()
		point = slider_point(scene, scene.velocity.length())
		mouse_button(point, true)
		await process_frame
		mouse_motion(point + Vector2(25, 0))
		await process_frame
		mouse_motion(point)
		await process_frame
		check(scene.speed_snapped, "取消场景先通过真实鼠标进入圆速吸附")
		if cancel_key == KEY_NONE:
			scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		else:
			press_key(cancel_key)
		await process_frame
		mouse_motion(point + Vector2(22, 0))
		await process_frame
		mouse_button(point + Vector2(22, 0), false)
		await process_frame
		check(not scene.speed_dragging and not scene.speed_snapped, "取消/重置/失焦均清理吸附状态")
		check((scene.orbit.e == 0.0 and scene.orbit.a == scene.initial_radius) if cancel_key == KEY_R else scene.orbit == original, "取消/重置/失焦后的移动与释放余波不覆盖轨道")
	# 键盘只接受<=0.5m/s吸附，保留旧1m/s步进；Home/End保持旧方向端点语义。
	scene.reset()
	slider.grab_focus()
	var circle_speed: float = scene.velocity.length()
	press_key(KEY_RIGHT)
	await process_frame
	check(absf(scene.velocity.length() - circle_speed - 0.001) < 0.000001 and scene.orbit.e > 0.0, "圆速旁键盘+1m/s不被鼠标吸附区吞掉")
	press_key(KEY_LEFT)
	await process_frame
	check(scene.orbit.e == 0.0 and absf(scene.velocity.length() - circle_speed) < 0.000001, "键盘精确返回圆速时吸附精确圆")
	for keycode in [KEY_HOME, KEY_END]:
		var expected_speed: float = scene.speed_bounds.x if keycode == KEY_HOME else scene.speed_bounds.y
		press_key(keycode)
		await process_frame
		check(absf(scene.velocity.length() - expected_speed) < 0.000002 and not scene.speed_dragging, "Home/End到当前旧方向合法端点且不留下编辑事务")
	# 极端请求不能因圆速位于显示端点而被距离夹限误吸附。
	set_orbit(scene, Orbit.make(400.0, 0.8, 0.4), 0.2)
	scene.begin_speed_drag()
	scene.change_speed(-1000000.0)
	check(not scene.speed_snapped and scene.speed_limited, "圆速位于显示下端点时极小请求仍正常夹限而不吸附")
	scene.finish_speed_drag(false)
	for radius in [Orbit.MIN_PERIAPSIS, Orbit.MAX_A]:
		set_orbit(scene, Orbit.make(radius, 0.0, 0.4), 0.37)
		check(scene.circular_available and marker.visible, "圆轨道精确编辑边界不因单精度半径误差隐藏标记")
	scene.queue_free()
	await process_frame
