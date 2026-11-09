extends SceneTree
const Orbit = preload("res://scripts/kepler_orbit.gd")
var scene: Node
var frames: int = 0

func _initialize() -> void:
	root.size = Vector2i(1280, 800)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child.call_deferred(scene)

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 8:
		scene.set_physics_process(false)
		scene.manually_paused = true
		scene.camera.zoom = Vector2(0.57, 0.57)
		scene.orbit = Orbit.make(400.0, 0.6, 0.0)
		scene.preview = scene.orbit.duplicate()
		scene.mean_anomaly = 0.4
		scene._refresh_ship()
		scene._refresh_geometry()
		scene._update_hud()
	if frames == 12:
		capture.call_deferred("res://tests/gravity_range_visual.png")
	if frames == 20:
		scene.motion_mode = "FREE"
		scene.ship.position = Vector2(-520, -90)
		scene.velocity = Vector2(-0.3, -0.15)
		scene.flight.set_state(scene.ship.position, scene.velocity)
		scene.set_free_target(Vector2(-850, 190))
		scene._refresh_geometry()
		scene._update_hud()
	if frames == 24:
		capture.call_deferred("res://tests/free_flight_brake_visual.png")
	if frames == 30:
		scene._advance_motion(95.0)
		scene._refresh_navigation()
		scene._update_hud()
	if frames == 34:
		capture.call_deferred("res://tests/free_flight_visual.png")
	if frames == 42:
		scene.ship.position = Vector2(-650, 100)
		scene.velocity = Vector2(-0.1, -0.2)
		scene.flight.set_state(scene.ship.position, scene.velocity)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = root.get_canvas_transform() * Vector2.ZERO
		event.pressed = true
		Input.parse_input_event(event)
	if frames == 46:
		assert(scene.flight.boundary_crossing and absf(scene.flight.target.length() - 400.0) < 0.0001)
		scene._refresh_navigation()
		scene._update_hud()
		capture.call_deferred("res://tests/free_flight_boundary_target.png")
	if frames == 52:
		print("FREE_FLIGHT_WINDOW_CHECK completed; gravity range, brake turn, route and boundary target screenshots saved")
		quit()
	return false

func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(path) == OK)
