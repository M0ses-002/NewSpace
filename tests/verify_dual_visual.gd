extends SceneTree
## 独立验证（只读）：双天体轨道渲染坐标系、第五关胜利不暂停、第四关“下一关”。
## 运行（必须实窗，不能 headless，否则抓不到截图）：
##   godot --rendering-driver opengl3 --resolution 1280x800 --path <project> --script res://tests/verify_dual_visual.gd

const Orbit = preload("res://scripts/kepler_orbit.gd")
const CENTER_B: Vector2 = Vector2(860.0, 0.0)

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)

func save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(path)
	print("SCREENSHOT ", path, " err=", error, " size=", image.get_size())

func click(button: Button) -> void:
	var center: Vector2 = button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = center
		event.global_position = center
		root.push_input(event)

func centroid(points: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for point: Vector2 in points:
		sum += point
	return sum / float(points.size())

func run() -> void:
	root.size = Vector2i(1280, 800)
	var level: Node = load("res://scenes/level_5.tscn").instantiate()
	root.add_child(level)
	await process_frame
	var sandbox: Node = level.sandbox
	sandbox.set_physics_process(false)
	for index in range(level.config.tutorial.size()):
		level._show_page(index)
	level._start_level()
	await process_frame

	# ---------- B. 绕 B 的圆轨道渲染坐标系 ----------
	check(level.get_node("Sandbox/World/PlanetB").position.distance_to(CENTER_B) < 0.001, "PlanetB 节点位于 (860, 0)")
	sandbox.focus_index = 1
	sandbox.gravity_radius = float(sandbox.bodies[1].gravity_radius_km)
	sandbox.motion_mode = "ORBIT"
	sandbox.orbit_acquired = true
	sandbox.orbit = Orbit.make(240.0, 0.0, 0.0)
	sandbox.preview = sandbox.orbit.duplicate()
	sandbox.orbit_direction = 1.0
	sandbox.mean_anomaly = 0.7
	sandbox._refresh_ship()
	sandbox._refresh_geometry()
	sandbox._update_hud()
	await process_frame

	var orbit_points: PackedVector2Array = sandbox.current_line.points
	var gravity_points: PackedVector2Array = sandbox.gravity_line.points
	var orbit_center: Vector2 = centroid(orbit_points)
	var gravity_center: Vector2 = centroid(gravity_points)
	print("ORBIT centroid=", orbit_center, " points=", orbit_points.size())
	print("GRAVITY centroid=", gravity_center, " points=", gravity_points.size())
	print("SHIP=", sandbox.ship.position, " local=", sandbox.local_position())
	check(orbit_points.size() > 10, "当前轨道线已生成")
	check(orbit_center.distance_to(CENTER_B) < 3.0, "轨道线中心在 B 行星 (860,0) 附近，而不是原点")
	check(orbit_center.distance_to(Vector2.ZERO) > 700.0, "轨道线明显远离世界原点")
	var min_orbit_radius: float = 10000.0
	var max_orbit_radius: float = 0.0
	for point: Vector2 in orbit_points:
		var radius: float = point.distance_to(CENTER_B)
		min_orbit_radius = minf(min_orbit_radius, radius)
		max_orbit_radius = maxf(max_orbit_radius, radius)
	check(absf(min_orbit_radius - 240.0) < 2.0 and absf(max_orbit_radius - 240.0) < 2.0,
		"轨道线每一点到 B 中心距离均为 240 km（min=%.2f max=%.2f）" % [min_orbit_radius, max_orbit_radius])
	check(gravity_center.distance_to(CENTER_B) < 2.0, "绿色引力范围圈圆心在当前焦点 B")
	check(absf(gravity_points[0].distance_to(CENTER_B) - 400.0) < 0.5, "引力范围圈半径为 400 km")
	for index in range(4):
		var handle: Node2D = sandbox.handles[index]
		check(absf(handle.position.distance_to(CENTER_B) - 240.0) < 2.0,
			"轨道端点 handle %d 落在绕 B 的轨道上（距 B %.2f km）" % [index, handle.position.distance_to(CENTER_B)])
	await save_shot("res://tests/verify_dual_render.png")

	# 额外同框取证：临时把相机抬到世界层并置于两行星之间，确认 A/B 与各自引力圈同屏。
	var camera: Camera2D = sandbox.camera
	camera.top_level = true
	camera.global_position = Vector2(430.0, 0.0)
	camera.zoom = Vector2.ONE * 0.32
	await process_frame
	await save_shot("res://tests/verify_dual_both.png")
	camera.top_level = false
	camera.position = Vector2.ZERO
	camera.zoom = Vector2.ONE * sandbox.initial_zoom
	await process_frame

	# ---------- C. 胜利不暂停 ----------
	level._win()
	await process_frame
	check(not paused, "第五关胜利后场景树未暂停")
	check(level.victory_controls.visible, "胜利后顶部操作可见")
	check(not level.victory_next.visible, "最后一关隐藏“下一关”按钮")
	check(not level.dialog.visible, "通关后教学对话框隐藏")
	check(level.completed, "通关后 completed=true")

	var before_position: Vector2 = sandbox.ship.position
	sandbox.set_physics_process(true)
	await create_timer(2.0).timeout
	var after_position: Vector2 = sandbox.ship.position
	var moved: float = before_position.distance_to(after_position)
	print("VICTORY MOTION before=", before_position, " after=", after_position, " moved_km=%.3f" % moved)
	check(moved > 1.0, "胜利后 2 真实秒飞船仍在运动（位移 %.2f km）" % moved)
	await save_shot("res://tests/verify_dual_victory.png")

	# 注入鼠标点击“返回主菜单”（victory_controls 的第二个子按钮）。
	var victory_menu: Button = level.victory_controls.get_child(1)
	check(victory_menu.visible and victory_menu.text == "返回主菜单", "找到返回主菜单按钮")
	click(victory_menu)
	for frame in range(4):
		await process_frame
	var scene_path: String = ""
	if current_scene != null:
		scene_path = current_scene.scene_file_path
	print("AFTER MENU CLICK current_scene=", scene_path)
	check(scene_path == "res://scenes/menu.tscn", "点击返回主菜单后进入 menu.tscn")
	level.queue_free()
	await process_frame

	# ---------- D. 第四关语义变化 ----------
	var level4: Node = load("res://scenes/level_4.tscn").instantiate()
	root.add_child(level4)
	await process_frame
	check(not level4.config.is_empty(), "第四关配置加载成功")
	for index in range(level4.config.tutorial.size()):
		level4._show_page(index)
	level4._start_level()
	level4._win()
	await process_frame
	check(level4.victory_controls.visible, "第四关通关后显示顶部操作")
	check(level4.victory_next.visible, "第四关不再是最后一关，显示“下一关”按钮")
	var next_button: Button = level4.victory_next
	click(next_button)
	for frame in range(4):
		await process_frame
	var next_scene_path: String = ""
	if current_scene != null:
		next_scene_path = current_scene.scene_file_path
	print("AFTER NEXT CLICK current_scene=", next_scene_path)
	check(next_scene_path == "res://scenes/level_5.tscn", "第四关“下一关”进入 level_5.tscn")
	if current_scene != null and current_scene != level4:
		check(int(current_scene.config.get("level", 0)) == 5, "进入的场景确实是第五关")
		current_scene.queue_free()
	level4.queue_free()
	await process_frame

	# 前四关都能加载并正常显示教程。
	for number in range(1, 5):
		var probe: Node = load("res://scenes/level_%d.tscn" % number).instantiate()
		root.add_child(probe)
		await process_frame
		check(not probe.config.is_empty(), "第 %d 关配置加载成功" % number)
		check(probe.dialog != null and probe.dialog.visible, "第 %d 关教程对话框可见" % number)
		check(probe.config.tutorial.size() > 0, "第 %d 关教程页数非零" % number)
		probe.queue_free()
		await process_frame

	print("\nDUAL_VISUAL checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
