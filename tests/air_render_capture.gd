extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 800)
	var level = load("res://scenes/level_6.tscn").instantiate()
	root.add_child(level)
	await process_frame
	level.dialog.visible = false
	paused = false
	var sandbox = level.get_node("Sandbox")
	var force = level.get_node("Sandbox/World/AirForces/AirForce1")
	sandbox.manually_paused = true
	force.triggered = true
	var step: float = level.combat.max_step()
	for i in range(int(60.0 / step)):
		force.advance(step)
	var minimum := INF
	for i in range(force.members.size()):
		for j in range(i + 1, force.members.size()):
			minimum = minf(minimum, force.members[i].current.distance_to(force.members[j].current))
	print("AIR_MIN_PAIR_DISTANCE_MIDPOINT ", minimum)
	sandbox.camera.position = sandbox.ship.to_local(force.members[0].node.global_position)
	sandbox.camera.zoom = Vector2.ONE
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://air_render_default.png")
	sandbox.camera.zoom = Vector2.ONE * 0.22
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://air_render_small.png")
	print("AIR_CAPTURE ", OS.get_user_data_dir())
	quit()
