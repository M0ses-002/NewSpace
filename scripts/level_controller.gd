extends Node

const Progress = preload("res://scripts/level_progress.gd")
@export_file("*.json") var config_path: String
var config: Dictionary
var sandbox: Node2D
var combat: Node2D
var visited: Array[bool] = []
var page := 0
var completed := false
var satellite_count := 0
var enemy_lost_in_all_enemies := false
var all_enemy_targets: Array[Node2D] = []
var destroyed_enemy_targets: Array[Node2D] = []
var dialog: Control
var page_label: Label
var page_image: TextureRect
var previous_button: Button
var next_button: Button
var start_button: Button
var objective: Label
var victory_controls: HBoxContainer
var victory_next: Button
var victory_menu: Button
var victory_notice: Label

func _enter_tree() -> void:
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		push_error("无法读取关卡配置：" + config_path)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("关卡配置格式错误：" + config_path)
		return
	config = parsed
	sandbox = $Sandbox
	combat = $Sandbox/World/Combat
	combat.set("enemy_fire_enabled", bool(config.enemy_fire_enabled))
	combat.set("satellite_defense_enabled", bool(config.satellite_defense_enabled))

func _ready() -> void:
	if config.is_empty():
		return
	satellite_count = combat.satellites.size()
	if config.victory.type == "all_enemies":
		for enemy in combat.enemies:
			all_enemy_targets.append(enemy.node)
		if all_enemy_targets.size() != int(config.entities.Enemies):
			push_error("敌舰注册数量与关卡配置不一致，无法完成关卡。")
	combat.satellite_pressed.connect(_satellite_pressed)
	combat.enemy_destroyed.connect(_enemy_destroyed)
	combat.enemy_lost.connect(_enemy_lost)
	_create_overlay()
	for _item in config.tutorial:
		visited.append(false)
	_show_page(0)
	dialog.visible = true
	get_tree().paused = true

func _create_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	dialog = Control.new()
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dialog)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 600)
	center.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	panel.add_child(layout)
	var title := Label.new()
	title.text = str(config.title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	layout.add_child(title)
	page_image = TextureRect.new()
	page_image.custom_minimum_size = Vector2(680, 340)
	page_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	page_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layout.add_child(page_image)
	page_label = Label.new()
	page_label.custom_minimum_size = Vector2(700, 80)
	page_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(page_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_child(buttons)
	previous_button = Button.new()
	previous_button.text = "上一页"
	previous_button.pressed.connect(func() -> void: _show_page(page - 1))
	buttons.add_child(previous_button)
	next_button = Button.new()
	next_button.text = "下一页"
	next_button.pressed.connect(func() -> void: _show_page(page + 1))
	buttons.add_child(next_button)
	start_button = Button.new()
	start_button.text = "开始关卡"
	start_button.pressed.connect(_start_level)
	buttons.add_child(start_button)
	var return_button := Button.new()
	return_button.text = "返回菜单"
	return_button.pressed.connect(_return_menu)
	buttons.add_child(return_button)
	victory_controls = HBoxContainer.new()
	victory_controls.name = "VictoryControls"
	victory_controls.visible = false
	victory_controls.anchor_left = 0.5
	victory_controls.anchor_right = 0.5
	victory_controls.offset_left = -190.0
	victory_controls.offset_right = 190.0
	victory_controls.offset_top = 12.0
	victory_controls.offset_bottom = 52.0
	victory_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(victory_controls)
	victory_next = Button.new()
	victory_next.text = "下一关"
	victory_next.custom_minimum_size = Vector2(150, 40)
	victory_next.add_theme_font_size_override("font_size", 20)
	victory_next.pressed.connect(_next_level)
	victory_controls.add_child(victory_next)
	victory_menu = Button.new()
	victory_menu.text = "返回主菜单"
	victory_menu.custom_minimum_size = Vector2(170, 40)
	victory_menu.add_theme_font_size_override("font_size", 20)
	victory_menu.pressed.connect(_return_menu)
	victory_controls.add_child(victory_menu)
	victory_notice = Label.new()
	victory_notice.visible = false
	victory_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_notice.anchor_left = 0.5
	victory_notice.anchor_right = 0.5
	victory_notice.offset_left = -150.0
	victory_notice.offset_right = 150.0
	victory_notice.offset_top = 55.0
	victory_notice.offset_bottom = 80.0
	layer.add_child(victory_notice)
	objective = Label.new()
	objective.position = Vector2(30, 198)
	objective.add_theme_font_size_override("font_size", 18)
	layer.add_child(objective)
	_update_objective()

func _show_page(index: int) -> void:
	page = clampi(index, 0, config.tutorial.size() - 1)
	visited[page] = true
	var entry: Dictionary = config.tutorial[page]
	page_label.text = "%d / %d\n%s" % [page + 1, config.tutorial.size(), entry.text]
	var texture = load(str(entry.image))
	page_image.texture = texture if texture is Texture2D else null
	previous_button.disabled = page == 0
	next_button.disabled = page == config.tutorial.size() - 1
	start_button.disabled = visited.has(false)

func _start_level() -> void:
	if visited.has(false):
		return
	dialog.visible = false
	get_tree().paused = false
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.start_level_music()

func _process(_delta: float) -> void:
	if is_instance_valid(victory_controls) and victory_controls.visible:
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.005)
		var tint := Color(1.0, 0.8 + 0.2 * pulse, 0.45 + 0.55 * pulse)
		victory_next.modulate = tint
		victory_menu.modulate = tint

func _physics_process(_delta: float) -> void:
	if config.is_empty() or completed or combat.dead or get_tree().paused or dialog.visible:
		return
	if sandbox.motion_mode == "COLLISION":
		_fail("飞船撞击行星，任务失败。")
		return
	var victory: Dictionary = config.victory
	if victory.type == "altitude":
		if sandbox.manually_paused or sandbox.is_orbit_editing():
			return
		var altitude: float = sandbox.ship.position.length() - float(sandbox.Config.planet.radius_km)
		if altitude > float(victory.altitude_km):
			_win()
	elif victory.type == "enemy_or_satellites" and satellite_count > 0 and combat.satellites.size() == satellite_count:
		for satellite in combat.satellites:
			if satellite.owner != "player":
				return
		_win()
	elif victory.type == "orbit_body":
		if sandbox.manually_paused or sandbox.is_orbit_editing():
			return
		if sandbox.motion_mode == "ORBIT" and sandbox.orbit_acquired and sandbox.focus_index == int(victory.get("body_index", 1)):
			_win()

func _satellite_pressed(_node: Node2D) -> void:
	if not completed and not combat.dead and config.victory.type == "satellite":
		_win.call_deferred()

func _enemy_destroyed(node: Node2D) -> void:
	if completed or combat.dead:
		return
	if config.victory.type in ["enemy", "enemy_or_satellites"]:
		_win.call_deferred()
	elif config.victory.type == "all_enemies" and all_enemy_targets.has(node) and not destroyed_enemy_targets.has(node):
		destroyed_enemy_targets.append(node)
		if all_enemy_targets.size() > 0 and all_enemy_targets.size() == int(config.entities.Enemies) and destroyed_enemy_targets.size() == all_enemy_targets.size():
			_win_all_enemies.call_deferred()

func _win_all_enemies() -> void:
	if not enemy_lost_in_all_enemies and combat.enemies.is_empty():
		_win()

func _enemy_lost(_node: Node2D) -> void:
	if not completed and not combat.dead and config.victory.type in ["enemy", "all_enemies"]:
		enemy_lost_in_all_enemies = true
		_fail.call_deferred("敌机坠毁，未被击落，任务失败。")

func _fail(message: String) -> void:
	if completed:
		return
	completed = true
	get_tree().paused = true
	dialog.visible = true
	page_image.visible = false
	page_label.text = message
	previous_button.visible = false
	next_button.visible = false
	start_button.visible = true
	start_button.disabled = false
	start_button.text = "重试关卡"
	start_button.pressed.disconnect(_start_level)
	start_button.pressed.connect(_retry_level)

func _retry_level() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _update_objective() -> void:
	if is_instance_valid(objective):
		objective.text = str(config.objective)

func _win() -> void:
	if completed or combat.dead:
		return
	completed = true
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_level_complete()
	var current := int(config.level)
	var saved := Progress.save_level(mini(current + 1, Progress.LAST_LEVEL))
	dialog.visible = false
	victory_controls.visible = true
	victory_next.visible = current < Progress.LAST_LEVEL
	victory_notice.visible = not saved
	victory_notice.text = "进度保存失败" if not saved else ""

func _next_level() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(Progress.scene_path(int(config.level) + 1))

func _return_menu() -> void:
	get_tree().paused = false
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.stop_level_music()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
