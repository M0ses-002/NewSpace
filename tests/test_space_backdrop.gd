extends SceneTree

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for path: String in ["res://scenes/main.tscn", "res://scenes/level_1.tscn", "res://scenes/level_2.tscn", "res://scenes/level_3.tscn", "res://scenes/level_4.tscn", "res://scenes/level_5.tscn"]:
		var packed: PackedScene = load(path)
		var scene: Node = packed.instantiate()
		var backdrop: Node = scene.find_child("SpaceBackdrop", true, false)
		check(backdrop != null and backdrop.layer == -1, path + " 背景位于世界层之下")
		scene.free()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var backdrop: Node = scene.get_node("SpaceBackdrop")
	check(backdrop.surface.mouse_filter == Control.MOUSE_FILTER_IGNORE, "背景不拦截输入")
	check(backdrop._material != null, "着色器材质已独立实例化")
	check(backdrop._material.get_shader_parameter("resolution") == root.get_visible_rect().size, "分辨率匹配视口")
	var start: float = backdrop._elapsed
	backdrop.advance(1.0)
	check(backdrop._elapsed > start, "运行时背景时间推进")
	scene.manually_paused = true
	start = backdrop._elapsed
	backdrop.advance(1.0)
	check(backdrop._elapsed == start, "手动暂停冻结背景")
	scene.manually_paused = false
	paused = true
	backdrop.advance(1.0)
	check(backdrop._elapsed == start, "场景树暂停冻结背景")
	paused = false
	var camera: Camera2D = scene.get_node("World/Ship/Camera2D")
	backdrop.advance(0.0)
	var initial: Vector2 = backdrop._far
	camera.position += Vector2(10, 0)
	backdrop.advance(0.0)
	check(backdrop._far != initial, "相机移动触发视差")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://backdrop_test.png")
	scene.queue_free()
	await process_frame
	print("BACKDROP_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
