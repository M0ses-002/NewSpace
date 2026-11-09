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
	await test_transaction()
	await test_keyboard_and_cancel()
	await test_retrograde()
	await test_exclusive_and_empty()
	print("HEADING_SLIDER_TESTS checks=%d failures=%d" % [checks, failures])
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

func press_key(keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)

func angle_point(scene: Node, gamma: float, offset_px: float = 0.0) -> Vector2:
	var slider: HSlider = scene.angle_slider
	var scale_x: float = slider.get_screen_transform().x.length()
	return slider.global_position + Vector2(scene._angle_slider_x(gamma) + offset_px / scale_x, slider.size.y * 0.5)

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

func test_transaction() -> void:
	root.size = Vector2i(1280, 800)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	var slider: HSlider = scene.angle_slider
	var signals: Dictionary = {"start": 0, "change": 0, "end": 0}
	slider.drag_started.connect(func() -> void: signals.start += 1)
	slider.value_changed.connect(func(_value: float) -> void: signals.change += 1)
	slider.drag_ended.connect(func(_changed: bool) -> void: signals.end += 1)
	for paused in [false, true]:
		scene.reset()
		scene.manually_paused = paused
		var frozen: Vector2 = scene.ship.position
		var before_velocity: Vector2 = scene.velocity
		var before_orbit: Dictionary = scene.orbit.duplicate()
		var saved_time: float = scene.elapsed_simulation
		var point: Vector2 = angle_point(scene, 0.0)
		mouse_button(point, true)
		await process_frame
		check(scene.angle_dragging and not scene.speed_dragging and not scene.dragging, "滑条按下进入朝向事务")
		scene._physics_process(0.5)
		check(scene.ship.position == frozen and scene.elapsed_simulation == saved_time, "朝向拖动冻结解析传播")
		check(not scene.speed_slider.editable, "朝向拖动期间速度滑条禁用")
		check(scene.status_label.text.contains("朝向预览"), "状态栏显示朝向预览")
		mouse_motion(point + Vector2(40, 0))
		await process_frame
		check(Orbit.residual(scene.preview, frozen) < 0.00001, "预览轨道经过冻结船")
		check(absf(float(scene.preview.a) - float(before_orbit.a)) / float(before_orbit.a) < 0.0002, "转向预览保持半长轴")
		check(absf(scene._preview_velocity().length() - before_velocity.length()) < 0.00001, "转向预览严格保持速率")
		check(absf(float(scene.preview.e) - float(before_orbit.e)) > 0.0001 or absf(angle_difference(before_velocity.angle(), scene._preview_velocity().angle())) > 0.001, "拖动实际改变轨道形状")
		check(scene.angle_value.text.contains("°") and not scene.angle_value.text.contains("m/s"), "朝向数值仅显示角度")
		check(scene.angle_readout.text.contains("Δv") and scene.angle_readout.text.contains("e"), "结果读数显示Δv与偏心率")
		var preview_before_release: Dictionary = scene.preview.duplicate()
		var gamma_before_release: float = scene.heading_request
		var expected_dv: float = scene._preview_velocity().distance_to(before_velocity)
		mouse_button(point + Vector2(40, 0), false)
		await process_frame
		check(not scene.angle_dragging and scene.ship.position == frozen, "HUD上释放不粘连不跳船")
		check(scene.manually_paused == paused, "朝向释放恢复原手动暂停状态")
		check(scene.orbit == preview_before_release, "释放提交预览轨道")
		check(absf(scene.last_delta_v - expected_dv) < 0.000001 and scene.last_delta_v > 0.001, "Δv等于完整向量差")
		check(absf(scene.mean_anomaly - Orbit.mean_at(scene.orbit, frozen)) < 0.000001, "提交后相位从冻结位置恢复")
		check(absf(Orbit.flight_path_angle(frozen, scene.velocity, scene.orbit_direction) - gamma_before_release) < 0.0001, "提交速度朝向与请求偏角一致")
		check(orbit_direction_sign(frozen, scene.velocity) == scene.orbit_direction, "提交保持绕行方向")
		scene._physics_process(0.1)
		check((scene.ship.position == frozen) == paused, "释放后按原暂停状态传播")
		check(Orbit.residual(scene.orbit, scene.ship.position) < 0.00001, "释放后沿转向轨道传播")
	check(signals.start == 2 and signals.end == 2 and signals.change >= 2, "真实UI完整触发drag_started/value_changed/drag_ended")
	# 拇指零位移按下释放不产生脉冲。
	scene.reset()
	var original: Dictionary = scene.orbit.duplicate()
	var frozen: Vector2 = scene.ship.position
	var thumb: Vector2 = angle_point(scene, scene.heading_start)
	mouse_button(thumb, true)
	await process_frame
	check(scene.angle_dragging and scene.angle_ignore_press_value, "点击拇指标记按下被识别")
	mouse_button(thumb, false)
	await process_frame
	check(scene.orbit == original and scene.ship.position == frozen and scene.last_delta_v < 0.000001, "零位移朝向按压不跳船不产生脉冲")
	# HUD 每帧写滑条不得回环触发 value_changed。
	var loop_count: int = 0
	var spy: Callable = func(_value: float) -> void: loop_count += 1
	slider.value_changed.connect(spy)
	for i in range(5):
		scene._update_hud()
	await process_frame
	check(loop_count == 0, "HUD写入使用set_block_signals且无回环 got=%d" % loop_count)
	slider.value_changed.disconnect(spy)
	scene.queue_free()
	await process_frame

func orbit_direction_sign(position: Vector2, velocity: Vector2) -> float:
	return 1.0 if position.cross(velocity) >= 0.0 else -1.0

func test_keyboard_and_cancel() -> void:
	root.size = Vector2i(1280, 800)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	scene.reset()
	var slider: HSlider = scene.angle_slider
	# Esc 取消：后续移动与释放不得提交。
	var original: Dictionary = scene.orbit.duplicate()
	var point: Vector2 = angle_point(scene, 0.0)
	mouse_button(point, true)
	await process_frame
	mouse_motion(point + Vector2(30, 0))
	await process_frame
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	mouse_motion(point + Vector2(60, 0))
	await process_frame
	mouse_button(point + Vector2(60, 0), false)
	await process_frame
	check(not scene.angle_dragging and scene.orbit == original and scene.last_delta_v < 0.000001, "Esc取消后拖动余波不提交朝向")
	# 键盘方向键：每次 0.25°，速率与半长轴不变。
	scene.reset()
	slider.grab_focus()
	var before_gamma: float = Orbit.flight_path_angle(scene.ship.position, scene.velocity, scene.orbit_direction)
	var before_speed: float = scene.velocity.length()
	var before_a: float = float(scene.orbit.a)
	press_key(KEY_RIGHT)
	await process_frame
	var after_gamma: float = Orbit.flight_path_angle(scene.ship.position, scene.velocity, scene.orbit_direction)
	check(absf(angle_difference(before_gamma, after_gamma) - deg_to_rad(0.25)) < 0.0001, "键盘右箭头偏转0.25° before=%s after=%s" % [before_gamma, after_gamma])
	check(not scene.angle_dragging and not scene.angle_cancelled, "键盘微调是完整事务且不留暂停态")
	check(absf(scene.velocity.length() - before_speed) < 0.00001, "键盘微调保持速率")
	check(absf(float(scene.orbit.a) - before_a) / before_a < 0.0002, "键盘微调保持半长轴")
	check(scene.ship.position.length() > 0.0 and Orbit.residual(scene.orbit, scene.ship.position) < 0.00001, "键盘微调不跳位")
	press_key(KEY_LEFT)
	await process_frame
	check(absf(angle_difference(before_gamma, Orbit.flight_path_angle(scene.ship.position, scene.velocity, scene.orbit_direction))) < 0.0001, "键盘左右对称返回原偏角")
	for keycode in [KEY_HOME, KEY_END]:
		var expected: float = -scene.heading_span if keycode == KEY_HOME else scene.heading_span
		press_key(keycode)
		await process_frame
		var measured: float = Orbit.flight_path_angle(scene.ship.position, scene.velocity, scene.orbit_direction)
		check(absf(angle_difference(measured, expected)) < 0.001 and not scene.angle_dragging, "Home/End到可行边界且不留事务 %s measured=%s expected=%s" % [keycode, measured, expected])
	# R 重置后方向键余波不覆盖圆轨道。
	var point2: Vector2 = angle_point(scene, 0.0)
	mouse_button(point2, true)
	await process_frame
	mouse_motion(point2 + Vector2(25, 0))
	await process_frame
	press_key(KEY_R)
	await process_frame
	mouse_motion(point2 + Vector2(50, 0))
	await process_frame
	mouse_button(point2 + Vector2(50, 0), false)
	await process_frame
	check(scene.orbit.e == 0.0 and scene.orbit.a == scene.initial_radius and not scene.angle_dragging, "朝向拖动期间R重置后鼠标余波不覆盖圆轨道")
	# 失焦取消。
	scene.begin_angle_drag()
	check(scene.angle_dragging, "失焦测试先建立朝向事务")
	scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not scene.angle_dragging, "失焦取消朝向编辑")
	check(scene.orbit.e == 0.0 and scene.orbit.a == scene.initial_radius, "失焦不提交朝向")
	scene.queue_free()
	await process_frame

func test_retrograde() -> void:
	root.size = Vector2i(1280, 800)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	for offset in [0.02, -0.02]:
		set_orbit(scene, Orbit.make(300.0, 0.5, 0.3), 1.1, -1.0)
		var frozen: Vector2 = scene.ship.position
		var before_velocity: Vector2 = scene.velocity
		var before_a: float = float(scene.orbit.a)
		check(scene.ship.position.cross(scene.velocity) < 0.0, "逆行夹具角动量为负")
		scene.begin_angle_drag()
		check(scene.angle_dragging, "逆行夹具可进入朝向事务")
		check(absf(scene.heading_start) > 0.01, "逆行夹具具有非零航迹角")
		var rebuilt: Vector2 = Orbit.heading_velocity(scene.anchor, scene.angle_start_speed, scene.heading_start, -1.0)
		check(rebuilt.distance_to(before_velocity) < 0.00001, "逆行 heading_start 精确重建当前速度 rebuilt=%s before=%s heading=%s" % [rebuilt, before_velocity, scene.heading_start])
		scene.change_angle(scene.heading_start + offset * 0.05)
		check(absf(angle_difference(before_velocity.angle(), scene._preview_velocity().angle())) < 0.01, "逆行首个微小拖动不镜像跳变")
		scene.change_angle(scene.heading_start + offset)
		check(scene.angle_dragging and absf(scene.heading_request - (scene.heading_start + offset)) < 0.0001, "逆行拖动按带符号航迹角更新")
		scene.finish_angle_drag(true)
		check(scene.ship.position == frozen, "逆行提交零位移")
		check(absf(scene.velocity.length() - before_velocity.length()) < 0.00001, "逆行提交保持速率")
		check(scene.orbit_direction == -1.0 and scene.ship.position.cross(scene.velocity) < 0.0, "逆行提交保持绕行方向")
		check(absf(float(scene.orbit.a) - before_a) < 0.001, "逆行转向半长轴变化小于1e-3")
		check(absf(Orbit.flight_path_angle(frozen, scene.velocity, -1.0) - scene.heading_start) < 0.0001, "逆行提交航迹角与请求一致")
	check(scene.angle_value.text.contains("°"), "逆行下朝向数值仍显示")
	scene.queue_free()
	await process_frame

func test_exclusive_and_empty() -> void:
	root.size = Vector2i(1280, 800)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false)
	# 双滑条双向互斥。
	scene.reset()
	scene.begin_speed_drag()
	check(scene.speed_dragging, "速度事务建立")
	var speed_preview: Dictionary = scene.preview.duplicate()
	scene.begin_angle_drag()
	check(not scene.angle_dragging, "调速中禁止开启朝向事务")
	scene.change_angle(0.2)
	check(scene.preview == speed_preview and scene.speed_dragging, "调速中朝向请求不污染预览")
	scene.finish_speed_drag(false)
	scene.reset()
	scene.begin_angle_drag()
	check(scene.angle_dragging, "朝向事务建立")
	var angle_preview: Dictionary = scene.preview.duplicate()
	scene.begin_speed_drag()
	check(not scene.speed_dragging, "朝向中禁止开启调速事务")
	scene.change_speed(scene.velocity.length() + 0.05)
	check(scene.preview == angle_preview, "朝向中调速请求不污染预览")
	check(not scene.speed_slider.editable, "朝向中速度滑条不可编辑")
	scene.finish_angle_drag(false)
	# 真实鼠标：朝向拖动中按到速度滑条不改变事务归属。
	scene.reset()
	var point: Vector2 = angle_point(scene, 0.0)
	mouse_button(point, true)
	await process_frame
	mouse_motion(point + Vector2(30, 0))
	await process_frame
	var speed_rect: Rect2 = scene.speed_slider.get_global_rect()
	mouse_button(speed_rect.get_center(), true)
	await process_frame
	check(scene.angle_dragging and not scene.speed_dragging, "朝向拖动中点击速度滑条不抢占事务")
	mouse_button(speed_rect.get_center(), false)
	await process_frame
	mouse_button(point + Vector2(30, 0), false)
	await process_frame
	check(not scene.angle_dragging, "释放后朝向事务结束")
	# 战斗发射在朝向事务期间被拒绝。
	scene.reset()
	var battle = scene.combat
	battle.selected = battle.enemies[0].node
	var missile_count: int = battle.missiles.size()
	scene.begin_angle_drag()
	battle.fire_player()
	check(battle.missiles.size() == missile_count, "朝向事务期间禁止发射导弹")
	scene.finish_angle_drag(false)
	# FREE 模式禁用。
	scene.reset()
	scene.motion_mode = "FREE"
	scene._update_hud()
	check(not scene.angle_available and not scene.angle_slider.editable, "自由飞行模式禁用朝向滑条")
	check(scene.angle_limits.text.contains("不可调"), "自由飞行模式说明朝向不可用")
	scene.motion_mode = "ORBIT"
	scene.reset()
	# 空可行域：已贴最小近心半径。
	set_orbit(scene, Orbit.make(Orbit.MIN_PERIAPSIS, 0.0, 0.4), 0.3)
	check(scene.heading_span == 0.0, "近心安全半径处可行域为空")
	check(not scene.angle_available and not scene.angle_slider.editable, "空可行域禁用朝向滑条")
	check(scene.angle_limits.text.contains("无可调余量"), "空可行域给出明确文案")
	var original: Dictionary = scene.orbit.duplicate()
	scene.begin_angle_drag()
	check(not scene.angle_dragging, "空可行域不建立朝向事务")
	scene.change_angle(0.1)
	check(scene.orbit == original, "空可行域请求不改变轨道")
	check(scene.angle_slider.min_value < scene.angle_slider.max_value, "空可行域滑条区间仍有非零宽度")
	scene.queue_free()
	await process_frame
