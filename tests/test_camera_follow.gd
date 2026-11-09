extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 800)
	for path in ["res://scenes/main.tscn", "res://scenes/level_1.tscn", "res://scenes/level_2.tscn", "res://scenes/level_3.tscn", "res://scenes/level_4.tscn"]:
		var level = load(path).instantiate()
		root.add_child(level)
		await process_frame
		var sandbox = level if path.ends_with("main.tscn") else level.get_node("Sandbox")
		sandbox.set_physics_process(false)
		var camera: Camera2D = sandbox.camera
		check(camera.get_parent() == sandbox.ship and camera.ignore_rotation, path + " 相机绑定飞船且忽略转向")
		check(camera.global_position.distance_to(sandbox.ship.global_position) < 0.0001, path + " 初始化居中")
		var header_position: Vector2 = sandbox.get_node("HUD/Layout/Header").global_position
		for location in [Vector2(240, 60), Vector2(-400, 700), Vector2(10000, -3000)]:
			sandbox.ship.position = location
			sandbox.ship.rotation = 1.25
			camera.force_update_scroll()
			var screen: Vector2 = root.get_canvas_transform() * sandbox.ship.global_position
			check(screen.distance_to(Vector2(root.size) * 0.5) < 0.01, path + " 世界位置变化后屏幕居中")
			check(sandbox.get_node("HUD/Layout/Header").global_position == header_position, path + " HUD 屏幕位置固定")
		camera.zoom = Vector2(0.5, 0.5)
		camera.force_update_scroll()
		check((root.get_canvas_transform() * sandbox.ship.global_position).distance_to(Vector2(root.size) * 0.5) < 0.01, path + " 缩放不改变居中")
		sandbox.reset()
		camera.force_update_scroll()
		check(camera.zoom == Vector2.ONE and camera.global_position.distance_to(sandbox.ship.global_position) < 0.001, path + " 重置居中并恢复缩放")
		paused = false
		level.queue_free()
		await process_frame
	print("CAMERA_FOLLOW_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
