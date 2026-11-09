extends CanvasLayer

@export var motion_enabled := true
@export_range(0.0, 3.0, 0.05) var drift_speed := 1.0
@export_range(0.0, 0.2, 0.005) var far_parallax := 0.02
@export_range(0.0, 0.45, 0.005) var near_parallax := 0.08
@export var max_frame_shift := 4000.0
@export var frozen := false

@onready var surface: ColorRect = $Surface
var _material: ShaderMaterial
var _elapsed := 0.0
var _far := Vector2.ZERO
var _near := Vector2.ZERO
var _camera: Camera2D
var _last_camera_position := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material = surface.material.duplicate() as ShaderMaterial
	surface.material = _material
	get_viewport().size_changed.connect(_sync_viewport_size)
	_sync_viewport_size()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera != _camera:
		_camera = camera
		if camera != null:
			_last_camera_position = camera.global_position
	if camera != null:
		var screen_delta := (camera.global_position - _last_camera_position) * camera.zoom
		_last_camera_position = camera.global_position
		if not _is_paused() and motion_enabled and screen_delta.length() <= max_frame_shift:
			_far += screen_delta * far_parallax
			_near += screen_delta * near_parallax
	if not _is_paused() and motion_enabled:
		_elapsed += maxf(delta, 0.0) * drift_speed
	_material.set_shader_parameter("time", _elapsed)
	_material.set_shader_parameter("far_offset", _far)
	_material.set_shader_parameter("near_offset", _near)
	_material.set_shader_parameter("intensity", 1.0 if motion_enabled else 0.0)

func _sync_viewport_size() -> void:
	_material.set_shader_parameter("resolution", get_viewport().get_visible_rect().size)

func _is_paused() -> bool:
	if frozen or get_tree().paused:
		return true
	var parent := get_parent()
	return bool(parent.manually_paused) or parent.is_orbit_editing()
