extends SceneTree

var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var level: Node = load("res://scenes/level_5.tscn").instantiate()
	root.add_child(level)
	await process_frame
	for index in range(level.config.tutorial.size()):
		level._show_page(index)
	level._start_level()
	await process_frame
	var sandbox: Node = level.sandbox
	var a: Node2D = sandbox.get_node("World/Planet")
	var b: Node2D = sandbox.get_node("World/PlanetB")
	var sprite_a: Sprite2D = a.get_node("Sprite")
	var sprite_b: Sprite2D = b.get_node("Sprite")
	check(sprite_a.texture.resource_path.ends_with("planet_a.png"), "A 行星使用第一组动画")
	check(sprite_b.texture.resource_path.ends_with("planet_b.png"), "B 行星使用第二组动画")
	check(sprite_a.hframes == 6 and sprite_a.vframes == 6 and sprite_b.hframes == 6 and sprite_b.vframes == 6, "两组均为36帧")
	check(absf(sprite_a.scale.x * a.BODY_DIAMETER_PX - 2.0 * float(sandbox.bodies[0].radius_km)) < 0.01, "A 视觉半径与配置一致")
	check(absf(sprite_b.scale.x * b.BODY_DIAMETER_PX - 2.0 * float(sandbox.bodies[1].radius_km)) < 0.01, "B 视觉半径与配置一致")
	check(b.position.distance_to(Vector2(860, 0)) < 0.01, "B 行星位置未改变")
	var frame: int = sprite_a.frame
	a._process(0.3)
	check(sprite_a.frame != frame, "行星帧推进")
	sandbox.manually_paused = true
	frame = sprite_a.frame
	a._process(1.0)
	check(sprite_a.frame == frame, "暂停冻结动画")
	sandbox.manually_paused = false
	for texture: Texture2D in [sprite_a.texture, sprite_b.texture]:
		var image := texture.get_image()
		check(image.get_pixel(0, 0).a == 0.0, "帧外背景透明")
		check(image.get_pixel(148, 148).a > 0.9, "行星中心不透明")
	if DisplayServer.get_name() != "headless":
		var camera: Camera2D = sandbox.camera
		camera.top_level = true
		camera.global_position = Vector2(430, 0)
		camera.zoom = Vector2.ONE * 0.85
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://planets_dual.png")
		camera.global_position = Vector2.ZERO
		camera.zoom = Vector2.ONE * 2.0
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://planet_a_close.png")
		camera.global_position = Vector2(860, 0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://planet_b_close.png")
	level.queue_free()
	await process_frame
	print("PLANET_ANIMATION_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
