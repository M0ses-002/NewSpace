extends SceneTree
const Orbit = preload("res://scripts/kepler_orbit.gd")
var speed_circle_point: Vector2 = Vector2.ZERO
var scene: Node
var frames: int = 0
func _initialize() -> void:
	root.size = Vector2i(1280, 800)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child.call_deferred(scene)
func _process(_delta: float) -> bool:
	frames += 1
	if frames == 8:
		scene.manually_paused = true
		scene.mean_anomaly = 0.5
		scene._refresh_ship()
		scene.camera.zoom = Vector2(0.72, 0.72)
		scene._refresh_geometry()
		scene._update_hud()
	if frames == 12:
		capture.call_deferred("res://tests/initial_orbit.png")
	if frames == 20:
		scene.begin_drag(1, scene.handles[1].position)
		scene.update_drag(scene.handles[1].position + Vector2(0, -80))
	if frames == 25:
		capture.call_deferred("res://tests/drag_preview.png")
	if frames == 32:
		scene.finish_drag(true)
		scene.manually_paused = false
	if frames == 40:
		scene.manually_paused = true
		scene.reset()
		scene.manually_paused = true
		scene.begin_drag(0, scene.handles[0].position)
		scene.update_drag(scene.handles[0].position + Vector2(5, 0))
		assert(scene.circle_snapped, "Near-circle gesture must snap")
	if frames == 45:
		capture.call_deferred("res://tests/circle_snap.png")
	if frames == 50:
		scene.finish_drag(false)
		scene.reset()
		scene.manually_paused = true
		scene.camera.zoom = Vector2(0.72, 0.72)
		scene._refresh_geometry()
		scene.speed_slider.drag_started.emit()
		scene.speed_slider.value = scene.velocity.length() * 1.1
	if frames == 55:
		capture.call_deferred("res://tests/speed_slider.png")
	if frames == 60:
		scene.speed_slider.drag_ended.emit(true)
		scene.orbit = Orbit.make(400.0, 0.7, 0.2)
		scene.preview = scene.orbit.duplicate()
		scene.mean_anomaly = PI * 0.5 - 0.7
		scene._refresh_ship()
		scene._refresh_geometry()
		scene._update_hud()
	if frames == 64:
		speed_circle_point = scene.speed_slider.global_position + Vector2(scene._slider_x(scene.circular_speed), scene.speed_slider.size.y * 0.5)
		mouse_button(speed_circle_point, true)
	if frames == 66:
		mouse_motion(speed_circle_point + Vector2(25, 0))
	if frames == 68:
		mouse_motion(speed_circle_point + Vector2(2, 0))
	if frames == 72:
		assert(scene.speed_snapped and scene.preview.e == 0.0, "真实鼠标回到圆速标记后必须精确圆化")
		capture.call_deferred("res://tests/speed_circle_snap.png")
	if frames == 78:
		mouse_button(speed_circle_point + Vector2(2, 0), false)
	if frames == 80:
		print("WINDOW_VISUAL_CHECK completed; initial, locked-axis, circle-snap, speed-slider and real-input speed-circle-snap captures saved")
		quit()
	return false
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

func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(path)
	assert(error == OK)
