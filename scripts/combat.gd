extends Node2D

signal satellite_pressed(node: Node2D)
signal enemy_destroyed(node: Node2D)
signal enemy_lost(node: Node2D)

@export var enemy_fire_enabled := true
@export var satellite_defense_enabled := false

const Config = preload("res://scripts/combat_config.gd")
const Debris = preload("res://scenes/debris.tscn")
const Missile = preload("res://scenes/missile.tscn")
const Loadout = preload("res://scripts/loadout.gd")
const CarrierSquadron = preload("res://scenes/carrier_squadron.tscn")

var config: Dictionary
var controller: Node
var player_health: float
var enemies: Array[Dictionary] = []
var satellites: Array[Dictionary] = []
var bombardment_satellites: Array[Node2D] = []
var debris: Array[Dictionary] = []
var missiles: Array[Dictionary] = []
var air_forces: Array = []
var carrier_squadrons: Array = []
var dogfights: Array[Dictionary] = []
var dogfight_protection: Dictionary = {}
var player_radar: Node2D
var hud: CanvasLayer
var selected: Node2D
var scan_angle := 0.0
var weapon_slots: Array[Dictionary] = []
var player_cooldown: float:
	get:
		return float(weapon_slots[0].cooldown) if not weapon_slots.is_empty() else 0.0
	set(value):
		if not weapon_slots.is_empty():
			weapon_slots[0].cooldown = value
var contact_cooldowns: Dictionary = {}
var dead := false
var capture_initialized := false
var debris_polygon_cache: Dictionary = {}
var initial_enemy_transform: Transform2D
var initial_satellite_angles: Array[float] = []
var initial_debris_transforms: Array[Transform2D] = []

func setup(owner_controller: Node) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	controller = owner_controller
	config = Config.load_config()
	air_forces.clear()
	var air_container := get_parent().get_node_or_null("AirForces")
	if air_container:
		air_forces = air_container.get_children()
	player_health = config.player.health
	controller.ship.get_node("Hull").color = Color(config.player.color)
	player_radar = $PlayerRadar
	hud = controller.get_node("CombatHUD")
	weapon_slots.clear()
	var equipped: Array = Loadout.get_slots()
	for i in range(4):
		weapon_slots.append({"id": str(equipped[i]), "cooldown": 0.0, "cooldown_started": false, "active": false, "remaining": 0.0, "target": null})
		var button: Button = hud.get_node("Weapons/Slot%d/Fire" % (i + 1))
		var callback := fire_slot.bind(i)
		if not button.pressed.is_connected(callback):
			button.pressed.connect(callback)
	if not hud.get_node("Death/Layout/Restart").pressed.is_connected(_restart_level):
		hud.get_node("Death/Layout/Restart").pressed.connect(_restart_level)
	hud.get_node("Death").visible = false
	var nodes := $Satellites.get_children()
	if initial_satellite_angles.is_empty():
		for node in nodes:
			initial_satellite_angles.append(node.position.angle())
		for node in $InitialDebris.get_children():
			initial_debris_transforms.append(node.transform)
	for i in range(nodes.size()):
		var node: Node2D = nodes[i]
		var capture_range: Node2D = node.get_node_or_null(node.capture_range_path) if not node.capture_range_path.is_empty() else null
		if not node.initialize("satellite", config.satellite):
			if is_instance_valid(capture_range):
				capture_range.visible = false
			continue
		if not is_instance_valid(capture_range):
			push_error("卫星未绑定夺控范围：" + str(node.get_path()))
			node.visible = false
			continue
		if node.has_signal("bomb_impact"):
			bombardment_satellites.append(node)
			var impact_callback := _on_bomb_impact.bind(node)
			if not node.bomb_impact.is_connected(impact_callback):
				node.bomb_impact.connect(impact_callback)
		var action: Button = node.get_node("Action")
		var callback := _use_satellite.bind(node)
		if not action.pressed.is_connected(callback):
			action.pressed.connect(callback)
		node.get_node("Body").color = Color(node.entity_config.color)
		node.state = {"node": node, "config": node.entity_config, "capture_range": capture_range, "angle": node.initial_transform.origin.angle(), "owner": "neutral", "health": float(node.entity_config.health), "type": i % 2}
		satellites.append(node.state)
	var initial_debris := $InitialDebris.get_children()
	for i in range(initial_debris.size()):
		var node: Node2D = initial_debris[i]
		node.transform = initial_debris_transforms[i]
		node.visible = true
		var body: Polygon2D = node.get_node("Body")
		body.color = Color(config.debris.color)
		body.scale = Vector2.ONE * float(config.debris.radius_km) / 7.0
		debris.append({"node": node, "orbit_radius": node.position.length()})
	for enemy in $Enemies.get_children():
		if not enemy.initialize("enemy", config.enemy):
			continue
		if enemies.is_empty():
			initial_enemy_transform = enemy.initial_transform
		enemy.get_node("Body").color = Color(enemy.entity_config.color)
		var radius: float = enemy.position.length()
		var initial_velocity := Vector2.ZERO
		if radius > float(controller.Config.planet.radius_km) and radius <= float(controller.gravity_radius):
			var gravity: float = controller._gravity(enemy.position).length()
			initial_velocity = Vector2(-enemy.position.y, enemy.position.x).normalized() * sqrt(gravity * radius)
		enemy.state = {"node": enemy, "config": enemy.entity_config, "velocity": initial_velocity, "health": float(enemy.entity_config.health), "cooldown": 0.0, "cooldown_started": false, "radar": enemy.get_node_or_null(enemy.radar_path) if not enemy.radar_path.is_empty() else null, "scan_angle": 0.0, "locked": false, "carrier_cooldown": 0.0, "weapon": str(enemy.entity_config.get("weapon", "missile"))}
		enemies.append(enemy.state)
	_update_satellites(0.0)
	_update_point_defense_visual()
	refresh_visuals()
	_update_hud()

func _restart_level() -> void:
	controller.get_tree().reload_current_scene()

func reset_battle() -> void:
	_clear_carrier_squadrons()
	for satellite in bombardment_satellites:
		satellite.reset_bombs()
	bombardment_satellites.clear()
	for item in debris + missiles:
		if item.node.get_parent() != $InitialDebris:
			item.node.queue_free()
	enemies.clear()
	satellites.clear()
	debris.clear()
	missiles.clear()
	contact_cooldowns.clear()
	debris_polygon_cache.clear()
	selected = null
	scan_angle = 0.0
	weapon_slots.clear()
	queue_redraw()
	dead = false
	capture_initialized = false
	_set_lock_audio(false)
	_set_air_raid_audio(false)
	for formation in air_forces:
		formation.reset_force()
	setup(controller)

func spawn_debris(pos: Vector2, round_shape: bool) -> void:
	var node: Node2D = Debris.instantiate()
	add_child(node)
	node.position = pos
	var body: Polygon2D = node.get_node("Body")
	body.color = Color(config.debris.color)
	if round_shape:
		var points := PackedVector2Array()
		for i in range(24):
			points.append(Vector2.from_angle(TAU * i / 24.0) * float(config.debris.radius_km))
		body.polygon = points
	else:
		body.scale = Vector2.ONE * float(config.debris.radius_km) / 7.0
	debris.append({"node": node, "orbit_radius": node.position.length()})

func _update_satellites(dt: float) -> void:
	for satellite in satellites:
		if satellite.node.has_method("fire_bomb") and satellite.node.descent_state != "ORBIT":
			continue
		var previous: Vector2 = satellite.node.position
		satellite.node.behavior.advance(satellite.node, dt)
		var orbit_position: Vector2 = satellite.node.position
		var mode: String = satellite.get("intercept_mode", "orbit")
		var target: Node2D = satellite.get("intercept_target")
		if mode == "chase" and (not satellite_defense_enabled or satellite.owner != satellite.get("intercept_owner") or not is_instance_valid(target) or target.is_queued_for_deletion() or not _has_missile(target)):
			mode = "return"
			target = null
		if mode == "orbit" and satellite_defense_enabled and satellite.owner in ["player", "enemy"]:
			var nearest := INF
			for missile in missiles:
				if missile.team == satellite.owner or not is_instance_valid(missile.node) or missile.node.is_queued_for_deletion():
					continue
				var distance: float = previous.distance_to(missile.node.position)
				if distance <= float(satellite.config.capture_radius_km) and distance < nearest:
					nearest = distance
					target = missile.node
			if target != null:
				mode = "chase"
				satellite.intercept_owner = satellite.owner
		if mode != "orbit":
			var destination: Vector2 = target.position if mode == "chase" else orbit_position
			satellite.node.position = previous.move_toward(destination, float(config.missile.speed_km_s) * 2.0 * dt)
			if mode == "return" and satellite.node.position.is_equal_approx(orbit_position):
				mode = "orbit"
		satellite.intercept_mode = mode
		satellite.intercept_target = target
		satellite.node.modulate = Color(0.45, 1.0, 0.7, 0.45 + 0.55 * absf(sin(scan_angle * 4.0))) if satellite.owner == "player" else (Color(1.0, 0.4, 0.4, 1.0) if satellite.owner == "enemy" else Color.WHITE)
		satellite.node.get_node("Health").text = "%d" % ceili(satellite.health)
		var action: Button = satellite.node.get_node("Action")
		action.visible = satellite.owner == "player"
		if satellite.node.has_method("fire_bomb"):
			action.text = "轰炸"

func _has_missile(node: Node2D) -> bool:
	for missile in missiles:
		if missile.node == node:
			return true
	return false

func _debris_angular_speed(radius: float) -> float:
	if radius <= 0.000001:
		return 0.0
	var planet: Dictionary = controller.Config.planet
	var top: float = float(planet.radius_km) + float(planet.field_thickness_km)
	var mu: float = float(planet.gravity_m_s2) / 1000.0 * top * top
	return sqrt(mu / (radius * radius * radius)) * float(config.debris.orbit_speed_factor)

func max_step() -> float:
	var angular: float = 0.0
	for satellite in satellites:
		angular = maxf(angular, absf(float(satellite.config.angular_speed_rad_s)))
	var orbital: float = controller.velocity.length() / maxf(controller.ship.position.length(), 1.0)
	var scanning: float = absf(float(config.radar.rotation_rad_s))
	for item in debris:
		angular = maxf(angular, _debris_angular_speed(float(item.orbit_radius)))
	for enemy in enemies:
		angular = maxf(angular, enemy.velocity.length() / maxf(enemy.node.position.length(), 1.0))
	for squadron in carrier_squadrons:
		if is_instance_valid(squadron) and not squadron.returning:
			angular = maxf(angular, float(config.carrier.orbit_speed_km_s) / squadron.radius)
	return minf(0.25, 0.01 / maxf(maxf(maxf(angular, orbital), scanning), 0.000001))

func advance_cooldowns(real_delta: float) -> void:
	if dead or real_delta <= 0.0 or controller.manually_paused or controller.is_orbit_editing() or get_tree().paused:
		return
	for slot in weapon_slots:
		if slot.cooldown_started:
			slot.cooldown_started = false
		else:
			slot.cooldown = maxf(0.0, float(slot.cooldown) - real_delta)
	for enemy in enemies:
		enemy.carrier_cooldown = maxf(0.0, float(enemy.get("carrier_cooldown", 0.0)) - real_delta)
		if enemy.get("cooldown_started", false):
			enemy.cooldown_started = false
		else:
			enemy.cooldown = maxf(0.0, enemy.cooldown - real_delta)
		enemy.node.get_node("Health").text = "%d · CD %.1f现实秒" % [ceili(enemy.health), enemy.get("carrier_cooldown", 0.0) if enemy.get("weapon", "missile") == "carrier" else enemy.cooldown]
	for key in dogfight_protection.keys():
		dogfight_protection[key] -= real_delta
		if dogfight_protection[key] <= 0.0:
			dogfight_protection.erase(key)
	_advance_dogfights(real_delta)

func advance(dt: float, old_player: Vector2) -> void:
	if dead or dt <= 0.0 or controller.manually_paused or controller.is_orbit_editing() or get_tree().paused:
		return
	var previous_scan := scan_angle
	var scanning := false
	if not is_instance_valid(selected) or not _is_active_target(selected) or controller.ship.position.distance_to(selected.global_position) > float(config.radar.far_radius_km):
		scanning = true
		selected = null
		scan_angle = fposmod(scan_angle + float(config.radar.rotation_rad_s) * dt, TAU)
	for key in contact_cooldowns.keys():
		contact_cooldowns[key] -= dt
	var active_missiles: Array = missiles.duplicate()
	var previous_targets: Dictionary = {controller.ship.get_instance_id(): old_player}
	for item in satellites:
		previous_targets[item.node.get_instance_id()] = item.node.position
	for item in enemies:
		previous_targets[item.node.get_instance_id()] = item.node.position
	_update_satellites(dt)
	var player: Vector2 = controller.ship.position
	_advance_air_forces(dt, controller.ship.get_parent().to_global(old_player), controller.ship.global_position)
	for satellite in satellites:
		if satellite.node.has_method("fire_bomb") and satellite.node.descent_state != "ORBIT":
			continue
		var old_satellite: Vector2 = previous_targets[satellite.node.get_instance_id()]
		var before_distance: float = old_player.distance_to(old_satellite)
		if (not capture_initialized or before_distance > satellite.config.capture_radius_km) and segment_distance(old_player - old_satellite, player - satellite.node.position, Vector2.ZERO) <= satellite.config.capture_radius_km:
			satellite.owner = "player"
	for enemy in enemies.duplicate():
		var closest: Dictionary = {}
		var best := INF
		for satellite in satellites:
			if satellite.owner != "enemy":
				var d: float = enemy.node.position.distance_squared_to(satellite.node.position)
				if d < best:
					best = d
					closest = satellite
		var old_enemy: Vector2 = previous_targets[enemy.node.get_instance_id()]
		if not enemy.node.behavior.advance(enemy.node, self, closest, dt):
			if selected == enemy.node:
				selected = null
			enemy.node.visible = false
			if is_instance_valid(enemy.radar):
				enemy.radar.visible = false
			enemies.erase(enemy)
			_clear_mothership_squadrons(enemy.node)
			enemy_lost.emit(enemy.node)
			continue
		for satellite in satellites:
			if satellite.node.has_method("fire_bomb") and satellite.node.descent_state != "ORBIT":
				continue
			var old_sat: Vector2 = previous_targets[satellite.node.get_instance_id()]
			if (not capture_initialized or old_enemy.distance_to(old_sat) > satellite.config.capture_radius_km) and segment_distance(old_enemy - old_sat, enemy.node.position - satellite.node.position, Vector2.ZERO) <= satellite.config.capture_radius_km:
				satellite.owner = "enemy"
		if enemy.locked and enemy.node.position.distance_to(player) > float(config.radar.far_radius_km):
			enemy.locked = false
		if not enemy.locked:
			var enemy_scan: float = enemy.scan_angle
			var rotation: float = float(config.radar.rotation_rad_s) * dt
			enemy.scan_angle = fposmod(enemy_scan + rotation, TAU)
			enemy.locked = _sector_swept(enemy.node.position, player, enemy_scan, rotation)
		if enemy.locked:
			enemy.scan_angle = (player - enemy.node.position).angle()
			if enemy_fire_enabled and enemy.get("weapon", "missile") == "missile" and enemy.cooldown <= 0.0 and _launch(enemy.node.position, controller.ship, "enemy"):
				enemy.cooldown = config.missile.cooldown_real_s
				enemy.cooldown_started = true
		if enemy_fire_enabled and enemy.get("weapon", "missile") == "carrier" and enemy.get("carrier_cooldown", 0.0) <= 0.0 and _launch_enemy_carrier(enemy.node):
			enemy.carrier_cooldown = float(config.carrier.cooldown_real_s)
		enemy.node.get_node("Health").text = "%d · CD %.1f现实秒" % [ceili(enemy.health), enemy.get("carrier_cooldown", 0.0) if enemy.get("weapon", "missile") == "carrier" else enemy.cooldown]
	_advance_carrier_squadrons(dt, previous_targets)
	for satellite in bombardment_satellites:
		satellite.advance_bombs(dt)
	capture_initialized = true
	for satellite in satellites:
		satellite.node.get_node("Action").visible = satellite.owner == "player" and (not satellite.node.has_method("fire_bomb") or satellite.node.descent_state == "ORBIT")
	for item in debris:
		var old_debris: Vector2 = item.node.position
		item.node.position = old_debris.rotated(_debris_angular_speed(float(item.orbit_radius)) * dt)
		var id: int = item.node.get_instance_id()
		if _polygon_contact(old_player + item.node.position - old_debris, player, item.node, float(config.player.hit_radius_km)) and contact_cooldowns.get(id, 0.0) <= 0.0:
			damage_player(float(config.debris.damage))
			contact_cooldowns[id] = float(config.debris.cooldown_s)
	for missile in active_missiles:
		if not is_instance_valid(missile.target) or missile.target.is_queued_for_deletion() or (missile.target != controller.ship and not _is_active_target(missile.target)):
			remove_missile(missile)
			continue
		var active_time: float = minf(dt, missile.life)
		if active_time <= 0.0:
			remove_missile(missile)
			continue
		missile.life -= active_time
		var previous: Vector2 = missile.node.position
		var target_end: Vector2 = missile.target.global_position
		var target_start: Vector2 = previous_targets.get(missile.target.get_instance_id(), target_end)
		var target_at_expiry: Vector2 = target_start.lerp(target_end, active_time / dt)
		var wanted: float = (target_at_expiry - previous).angle()
		missile.node.rotation = rotate_toward(missile.node.rotation, wanted, float(config.missile.turn_rad_s) * active_time)
		missile.node.position += Vector2.from_angle(missile.node.rotation) * float(config.missile.speed_km_s) * active_time
		var intercepted := false
		if missile.team == "enemy":
			for slot in weapon_slots:
				if slot.id != "point_defense" or not slot.active:
					continue
				var defense_time: float = minf(active_time, float(slot.remaining))
				var fraction: float = defense_time / active_time
				var defense_missile_end: Vector2 = previous.lerp(missile.node.position, fraction)
				var defense_player_end: Vector2 = old_player.lerp(player, defense_time / dt)
				if segment_distance(previous - old_player, defense_missile_end - defense_player_end, Vector2.ZERO) <= float(config.point_defense.range_km):
					remove_missile(missile)
					intercepted = true
					break
		if intercepted:
			continue
		# 卫星是实体结构：导弹撞上即在撞击点炸开并留下碎片，导弹本身消失。
		var struck_satellite := false
		for satellite in satellites:
			var old_sat: Vector2 = previous_targets.get(satellite.node.get_instance_id(), satellite.node.position)
			var clearance: float = float(satellite.config.radius_km) + float(config.missile.radius_km)
			var end_sat: Vector2 = old_sat.lerp(satellite.node.position, active_time / dt)
			if segment_distance(previous - old_sat, missile.node.position - end_sat, Vector2.ZERO) <= clearance:
				if satellite_defense_enabled and satellite.get("intercept_mode", "orbit") == "chase" and satellite.get("intercept_target") == missile.node and satellite.owner == satellite.get("intercept_owner") and satellite.owner != missile.team:
					satellite.intercept_mode = "return"
					satellite.intercept_target = null
				else:
					spawn_debris(satellite.node.position, true)
				remove_missile(missile)
				struck_satellite = true
				break
		if struck_satellite:
			continue
		var radius: float = float(config.player.hit_radius_km) if missile.team == "enemy" else float(missile.target.entity_config.radius_km)
		if segment_distance(previous - target_start, missile.node.position - target_at_expiry, Vector2.ZERO) <= radius + float(config.missile.radius_km):
			if missile.team == "enemy":
				damage_player(float(config.missile.damage))
			else:
				damage_target(missile.target, float(config.missile.damage))
			# 命中飞船只结算伤害，不生成碎片；碎片只来自命中卫星等实体结构。
			remove_missile(missile)
		elif missile.life <= 0.0:
			remove_missile(missile)
	if is_instance_valid(selected) and (not _is_active_target(selected) or player.distance_to(selected.global_position) > float(config.radar.far_radius_km)):
		selected = null
	if not is_instance_valid(selected):
		var nearest := INF
		for item in enemies:
			var distance: float = player.distance_to(item.node.global_position)
			if distance < nearest and _sector_swept(player, item.node.global_position, previous_scan, float(config.radar.rotation_rad_s) * dt if scanning else 0.0):
				selected = item.node
				nearest = distance
	if is_instance_valid(selected):
		scan_angle = (selected.global_position - player).angle()
	for slot in weapon_slots:
		if not slot.active:
			continue
		if slot.id == "point_defense":
			slot.remaining = maxf(0.0, float(slot.remaining) - dt)
			if slot.remaining <= 0.0:
				_stop_slot(slot)
	queue_redraw()
	_update_point_defense_visual()
	_update_hud()
	_sync_lock_audio()

func _launch_carrier_squadrons() -> bool:
	var origin: Vector2 = controller.ship.global_position
	if controller.focus_index < 0 or controller.focus_index >= controller.bodies.size():
		controller.feedback.text = "无法释放舰载机：没有焦点行星"
		return false
	var orbit_center: Vector2 = controller.ship.get_parent().to_global(controller.focus_center())
	if origin.distance_to(orbit_center) < 0.001:
		controller.feedback.text = "无法释放舰载机：飞船位于行星中心"
		return false
	for direction in [-1.0, 1.0]:
		var squadron = CarrierSquadron.instantiate()
		add_child(squadron)
		squadron.launch(origin, orbit_center, direction, config.carrier)
		carrier_squadrons.append(squadron)
	return true

func _clear_carrier_squadrons() -> void:
	for squadron in carrier_squadrons:
		if is_instance_valid(squadron):
			squadron.queue_free()
	carrier_squadrons.clear()
	dogfights.clear()
	dogfight_protection.clear()

func _advance_carrier_squadrons(dt: float, previous_targets: Dictionary) -> void:
	var player: Vector2 = controller.ship.global_position
	for squadron in carrier_squadrons.duplicate():
		if squadron.team == "enemy" and (not is_instance_valid(squadron.mothership) or not squadron.mothership.visible):
			_clear_squadron(squadron)
			continue
		squadron.advance(dt, player if squadron.team == "player" else squadron.mothership.global_position)
	var encounters: Array[Dictionary] = []
	for squadron in carrier_squadrons:
		if squadron.team != "player" or squadron.dogfight != null:
			continue
		for other in carrier_squadrons:
			if other.team != "enemy" or other.dogfight != null or _dogfight_protected(squadron, other):
				continue
			var encounter_time := INF
			var encounter_center := Vector2.ZERO
			var overlap: float = minf(squadron.orbit_end_time, other.orbit_end_time)
			for sweep in squadron.orbit_sweeps:
				for other_sweep in other.orbit_sweeps:
					var end_a: Vector2 = sweep.start.lerp(sweep.end, overlap / squadron.orbit_end_time)
					var end_b: Vector2 = other_sweep.start.lerp(other_sweep.end, overlap / other.orbit_end_time)
					var relative: Vector2 = sweep.start - other_sweep.start
					var movement: Vector2 = (end_a - sweep.start) - (end_b - other_sweep.start)
					var c: float = relative.length_squared() - pow(float(config.carrier.dogfight_range_km), 2)
					var fraction := 0.0
					if c > 0.0:
						var a: float = movement.length_squared()
						var b: float = 2.0 * relative.dot(movement)
						var discriminant: float = b * b - 4.0 * a * c
						if a <= 0.000000000001 or discriminant < 0.0:
							continue
						fraction = (-b - sqrt(discriminant)) / (2.0 * a)
						if fraction < 0.0 or fraction > 1.0:
							continue
					var time: float = overlap * fraction
					if time < encounter_time:
						encounter_time = time
						encounter_center = (sweep.start.lerp(end_a, fraction) + other_sweep.start.lerp(end_b, fraction)) * 0.5
			if not is_inf(encounter_time):
				encounters.append({"a": squadron, "b": other, "time": encounter_time, "center": encounter_center})
	encounters.sort_custom(func(a, b): return a.time < b.time)
	for encounter in encounters:
		var a = encounter.a
		var b = encounter.b
		if a.dogfight != null or b.dogfight != null:
			continue
		for squadron in [a, b]:
			var fraction: float = encounter.time / squadron.orbit_end_time
			for sweep in squadron.orbit_sweeps:
				sweep.end = sweep.start.lerp(sweep.end, fraction)
			squadron.rewind_orbit_to(encounter.time)
			squadron.orbit_end_time = encounter.time
		_start_dogfight(a, b, encounter.center)
	for squadron in carrier_squadrons.duplicate():
		if not carrier_squadrons.has(squadron):
			continue
		for sweep in squadron.orbit_sweeps:
			var member: Dictionary = sweep.member
			if not member.alive:
				continue
			if squadron.team == "enemy":
				var player_id: int = controller.ship.get_instance_id()
				var old_world: Vector2 = controller.ship.get_parent().to_global(previous_targets.get(player_id, controller.ship.position))
				if not member.hit_targets.has(player_id) and segment_distance(sweep.start - old_world, sweep.end - old_world.lerp(player, squadron.orbit_end_time / dt), Vector2.ZERO) <= float(config.carrier.radius_km) + float(config.player.hit_radius_km):
					member.hit_targets[player_id] = true
					damage_player(float(config.carrier.damage))
					if dead:
						return
				continue
			for enemy in enemies.duplicate():
				var enemy_id: int = enemy.node.get_instance_id()
				if member.hit_targets.has(enemy_id):
					continue
				var enemy_end: Vector2 = enemy.node.global_position
				var enemy_start: Vector2 = enemy.node.get_parent().to_global(previous_targets.get(enemy.node.get_instance_id(), enemy.node.position))
				var end_at_orbit: Vector2 = enemy_start.lerp(enemy_end, squadron.orbit_end_time / dt)
				if segment_distance(sweep.start - enemy_start, sweep.end - end_at_orbit, Vector2.ZERO) <= float(config.carrier.radius_km) + float(enemy.config.radius_km):
					member.hit_targets[enemy_id] = true
					damage_target(enemy.node, float(config.carrier.damage))
		if squadron.dogfight == null and squadron.finished(player if squadron.team == "player" else squadron.mothership.global_position):
			_clear_squadron(squadron)

func _clear_mothership_squadrons(mothership: Node2D) -> void:
	for squadron in carrier_squadrons.duplicate():
		if squadron.team == "enemy" and squadron.mothership == mothership:
			_clear_squadron(squadron)

func _clear_squadron(squadron: Node2D) -> void:
	if squadron.dogfight != null:
		var fight: Dictionary = squadron.dogfight
		for participant in [fight.a, fight.b]:
			if is_instance_valid(participant):
				participant.dogfight = null
		dogfights.erase(fight)
	carrier_squadrons.erase(squadron)
	squadron.queue_free()

func _launch_enemy_carrier(mothership: Node2D) -> bool:
	if controller.focus_index < 0 or controller.focus_index >= controller.bodies.size():
		return false
	# 敌舰当前始终围绕第一个天体运行，不能把它当作其他焦点天体的舰载母舰。
	if controller.focus_index != 0:
		return false
	var body: Dictionary = controller.body_at(controller.focus_index)
	var center: Vector2 = controller.ship.get_parent().to_global(controller.focus_center())
	var player_radius: float = controller.ship.global_position.distance_to(center)
	var enemy_radius: float = mothership.global_position.distance_to(center)
	if player_radius >= float(body.gravity_radius_km) or enemy_radius >= float(body.gravity_radius_km) or enemy_radius < 0.001 or absf(enemy_radius - player_radius) > float(config.carrier.enemy_height_tolerance_km):
		return false
	for direction in [-1.0, 1.0]:
		var squadron = CarrierSquadron.instantiate()
		add_child(squadron)
		squadron.launch(mothership.global_position, center, direction, config.carrier, "enemy", mothership)
		carrier_squadrons.append(squadron)
	return true

func _dogfight_key(a: Node2D, b: Node2D) -> String:
	return "%d:%d" % [mini(a.get_instance_id(), b.get_instance_id()), maxi(a.get_instance_id(), b.get_instance_id())]

func _dogfight_protected(a: Node2D, b: Node2D) -> bool:
	return dogfight_protection.has(_dogfight_key(a, b))

func _start_dogfight(a: Node2D, b: Node2D, encounter_center: Variant = null) -> void:
	var fight := {"a": a, "b": b, "elapsed": 0.0, "center": encounter_center if encounter_center != null else (a.position_world + b.position_world) * 0.5, "phase": randf() * TAU, "aspect": randf_range(0.5, 1.0)}
	a.dogfight = fight
	b.dogfight = fight
	dogfights.append(fight)

func _advance_dogfights(real_delta: float) -> void:
	for fight in dogfights.duplicate():
		var a = fight.a
		var b = fight.b
		if not is_instance_valid(a) or not is_instance_valid(b) or a.is_queued_for_deletion() or b.is_queued_for_deletion():
			if is_instance_valid(a) and not a.is_queued_for_deletion():
				a.dogfight = null
			if is_instance_valid(b) and not b.is_queued_for_deletion():
				b.dogfight = null
			dogfights.erase(fight)
			continue
		fight.elapsed += real_delta
		if fight.elapsed < float(config.carrier.dogfight_duration_real_s):
			var phase: float = fight.phase + fight.elapsed * TAU / float(config.carrier.dogfight_duration_real_s)
			for squadron in [a, b]:
				for i in range(squadron.members.size()):
					var member: Dictionary = squadron.members[i]
					if member.alive:
						var angle: float = phase + TAU * i / squadron.members.size() + (PI if squadron == b else 0.0)
						var offset := Vector2(cos(angle), sin(angle) * float(fight.aspect)) * (8.0 + i * 2.0)
						member.node.global_position = fight.center + offset
						member.node.get_node("Body").global_rotation = Vector2(-sin(angle), cos(angle) * float(fight.aspect)).angle()
			continue
		for squadron in [a, b]:
			if randf() < float(config.carrier.dogfight_loss_probability):
				var alive: Array = squadron.members.filter(func(member): return member.alive)
				alive.shuffle()
				var count := mini(alive.size(), randi_range(int(config.carrier.dogfight_loss_min), int(config.carrier.dogfight_loss_max)))
				for i in range(count):
					alive[i].alive = false
					alive[i].node.visible = false
			squadron.dogfight = null
		dogfight_protection[_dogfight_key(a, b)] = float(config.carrier.dogfight_protection_real_s)
		dogfights.erase(fight)

func _advance_air_forces(dt: float, old_player: Vector2, player: Vector2) -> void:
	for formation in air_forces:
		if not is_instance_valid(formation) or not formation.valid:
			continue
		if not formation.triggered:
			var path: PackedVector2Array = formation.sample_path(64)
			for i in range(1, path.size()):
				var a := path[i - 1]
				var b := path[i]
				var distance := 0.0 if Geometry2D.segment_intersects_segment(old_player, player, a, b) != null else minf(minf(segment_distance(old_player, player, a), segment_distance(old_player, player, b)), minf(segment_distance(a, b, old_player), segment_distance(a, b, player)))
				if distance <= float(formation.config.trigger_distance_km):
					formation.triggered = true
					var audio := get_node_or_null("/root/AudioManager")
					if audio:
						audio.play_air_force_launch()
					break
		if not formation.triggered or formation.elapsed >= float(formation.config.duration_sim_s):
			continue
		var active_time: float = minf(dt, float(formation.config.duration_sim_s) - formation.elapsed)
		formation.advance(active_time)
		var player_end := old_player.lerp(player, active_time / dt)
		for i in range(formation.members.size()):
			var member: Dictionary = formation.members[i]
			if not member.alive:
				continue
			var start: Vector2 = member.previous
			var end: Vector2 = member.current
			var intercepted := false
			for slot in weapon_slots:
				if slot.id != "point_defense" or not slot.active or float(slot.remaining) <= 0.0:
					continue
				var fraction := minf(active_time, float(slot.remaining)) / active_time
				if segment_distance(start - old_player, start.lerp(end, fraction) - old_player.lerp(player_end, fraction), Vector2.ZERO) <= float(config.point_defense.range_km):
					formation.damage_member(i, float(member.health))
					intercepted = true
					break
			if not intercepted and not dead and segment_distance(start - old_player, end - player_end, Vector2.ZERO) <= float(formation.config.member_radius_km) + float(config.player.hit_radius_km):
				formation.damage_member(i, float(member.health))
				damage_player(float(formation.config.collision_damage))

func _on_bomb_impact(world_position: Vector2, radius: float, damage: float, source: Node2D) -> void:
	for satellite in satellites.duplicate():
		if satellite.node == source:
			satellite.capture_range.visible = false
			satellites.erase(satellite)
			break
	for enemy in enemies.duplicate():
		if enemy.node.global_position.distance_to(world_position) <= radius + float(enemy.config.radius_km):
			damage_target(enemy.node, damage)

## 任一敌机锁定玩家时保持警报；全部失去锁定后淡出。
func _sync_lock_audio() -> void:
	var locked := false
	for enemy in enemies:
		if bool(enemy.get("locked", false)):
			locked = true
			break
	_set_lock_audio(locked)

func _set_lock_audio(locked: bool) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.set_enemy_locked(locked)

func _set_air_raid_audio(active: bool) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.set_air_raid(active)

func _exit_tree() -> void:
	_set_lock_audio(false)
	_set_air_raid_audio(false)

func _process(_delta: float) -> void:
	if is_instance_valid(hud) and is_instance_valid(player_radar):
		refresh_visuals()
		_update_hud()
		_update_lock_warning()
		_update_air_raid_warning()
		_update_point_defense_visual()

func _update_point_defense_visual() -> void:
	var glow: Polygon2D = controller.ship.get_node("PointDefenseGlow")
	var active := false
	if not dead and not controller.manually_paused and not controller.is_orbit_editing() and not get_tree().paused and controller.motion_mode != "COLLISION":
		for slot in weapon_slots:
			if slot.id == "point_defense" and slot.active and float(slot.remaining) > 0.0:
				active = true
				break
	glow.visible = active
	if active:
		glow.scale = Vector2.ONE * maxf(1.0, 0.5 / controller.camera.zoom.x)
		glow.modulate.a = 0.3 + 0.7 * (0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.008))

func _update_lock_warning() -> void:
	var locked := false
	if not dead and not controller.manually_paused and not controller.is_orbit_editing() and not get_tree().paused and controller.motion_mode != "COLLISION":
		for enemy in enemies:
			if bool(enemy.get("locked", false)):
				locked = true
				break
	var edges: Control = hud.get_node("LockEdges")
	var warning: Label = hud.get_node("LockWarning")
	edges.visible = locked
	warning.visible = locked
	if locked:
		var pulse: float = 0.35 + 0.65 * (0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006))
		edges.modulate.a = pulse
		warning.modulate.a = pulse

func _update_air_raid_warning() -> void:
	var active := false
	if not dead and not controller.manually_paused and not controller.is_orbit_editing() and not get_tree().paused and controller.motion_mode != "COLLISION":
		for formation in air_forces:
			if not is_instance_valid(formation) or not formation.valid or not formation.triggered or formation.elapsed >= float(formation.config.duration_sim_s):
				continue
			for member in formation.members:
				if member.alive:
					active = true
					break
			if active:
				break
	var warning: Label = hud.get_node("AirRaidWarning")
	warning.visible = active
	if active:
		warning.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006))
	_set_air_raid_audio(active)

func refresh_visuals() -> void:
	var player: Vector2 = controller.ship.position
	_draw_indicator(player_radar, player)
	for item in satellites:
		item.node.visible = true
		item.capture_range.visible = not item.node.has_method("fire_bomb") or item.node.descent_state == "ORBIT"
		item.capture_range.modulate = item.node.modulate
		item.capture_range.position = item.node.position
		var circle := PackedVector2Array()
		for i in range(65):
			circle.append(Vector2.from_angle(TAU * i / 64.0) * float(item.config.capture_radius_km))
		item.capture_range.get_node("Boundary").points = circle
	for item in enemies:
		item.node.visible = true
		if is_instance_valid(item.radar):
			item.radar.visible = false
	for item in debris:
		item.node.visible = true
	for item in missiles:
		item.node.visible = true
	_update_hud()

static func segment_distance(a: Vector2, b: Vector2, p: Vector2) -> float:
	var delta := b - a
	var t := clampf((p - a).dot(delta) / delta.length_squared(), 0.0, 1.0) if delta.length_squared() > 0.0 else 0.0
	return p.distance_to(a + t * delta)

func visible_to(origin: Vector2, target: Vector2, _target_node: Node2D, _observer: Node2D = null) -> bool:
	return origin.distance_to(target) <= float(config.radar.near_radius_km) or _in_sector(origin, target, scan_angle)

func _in_sector(origin: Vector2, target: Vector2, angle: float) -> bool:
	var delta := target - origin
	return delta.length() <= float(config.radar.far_radius_km) and absf(angle_difference(angle, delta.angle())) <= deg_to_rad(float(config.radar.sector_degrees)) * 0.5

func _sector_swept(origin: Vector2, target: Vector2, start: float, rotation: float) -> bool:
	var delta := target - origin
	if delta.length() > float(config.radar.far_radius_km):
		return false
	var half := deg_to_rad(float(config.radar.sector_degrees)) * 0.5
	if absf(rotation) + 2.0 * half >= TAU:
		return true
	var direction := 1.0 if rotation >= 0.0 else -1.0
	return fposmod(direction * (delta.angle() - start) + half, TAU) <= absf(rotation) + 2.0 * half

func _clear_ray(origin: Vector2, target: Vector2, excluded: Node2D, observer: Node2D = null) -> bool:
	if segment_distance(origin, target, Vector2.ZERO) <= float(controller.Config.planet.radius_km):
		return false
	for item in debris:
		if item.node != excluded and item.node != observer and _polygon_blocks(origin, target, item.node):
			return false
	for item in satellites:
		if item.node != excluded and item.node != observer and segment_distance(origin, target, item.node.position) <= float(item.config.radius_km):
			return false
	return true

func _debris_polygon(node: Node2D) -> PackedVector2Array:
	var body: Polygon2D = node.get_node("Body")
	var id: int = node.get_instance_id()
	var cached: Dictionary = debris_polygon_cache.get(id, {})
	if not cached.is_empty() and cached.transform == body.global_transform and cached.points == body.polygon:
		return cached.world
	var result := PackedVector2Array()
	for point in body.polygon:
		result.append(body.global_transform * point)
	debris_polygon_cache[id] = {"transform": body.global_transform, "points": body.polygon, "world": result}
	return result

func _polygon_blocks(origin: Vector2, target: Vector2, node: Node2D) -> bool:
	var polygon := _debris_polygon(node)
	if Geometry2D.is_point_in_polygon(origin, polygon) or Geometry2D.is_point_in_polygon(target, polygon):
		return true
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		if Geometry2D.segment_intersects_segment(origin, target, a, b) != null:
			return true
		if minf(minf(segment_distance(origin, target, a), segment_distance(origin, target, b)), minf(segment_distance(a, b, origin), segment_distance(a, b, target))) <= 0.000001:
			return true
	return false

func _polygon_contact(origin: Vector2, target: Vector2, node: Node2D, radius: float) -> bool:
	if _polygon_blocks(origin, target, node):
		return true
	var polygon := _debris_polygon(node)
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		if minf(minf(segment_distance(origin, target, a), segment_distance(origin, target, b)), minf(segment_distance(a, b, origin), segment_distance(a, b, target))) <= radius:
			return true
	return false

func _draw_indicator(node: Node2D, origin: Vector2, radius: float = -1.0) -> void:
	node.position = origin
	var circle_radius: float = float(config.radar.near_radius_km) if radius < 0.0 else radius
	var circle := PackedVector2Array()
	for i in range(65):
		circle.append(Vector2.from_angle(TAU * i / 64.0) * circle_radius)
	node.get_node("NearBoundary").points = circle
	var half := deg_to_rad(float(config.radar.sector_degrees)) * 0.5
	var sector := PackedVector2Array([Vector2.ZERO])
	for i in range(17):
		sector.append(Vector2.from_angle(scan_angle - half + 2.0 * half * i / 16.0) * float(config.radar.far_radius_km))
	sector.append(Vector2.ZERO)
	node.get_node("SectorBoundary").points = sector

func _sample_angles(origin: Vector2, start: float, span: float, count: int, observer: Node2D, excluded: Node2D = null) -> Array[float]:
	var offsets: Array[float] = []
	for i in range(count + 1):
		offsets.append(span * i / count)
	var obstacles: Array = [{"position": Vector2.ZERO, "radius": float(controller.Config.planet.radius_km)}]
	for item in debris:
		if item.node != observer and item.node != excluded:
			for point in _debris_polygon(item.node):
				var boundary: float = (point - origin).angle()
				for epsilon in [-0.0001, 0.0, 0.0001]:
					var offset: float = fposmod(boundary + epsilon - start, TAU)
					if offset <= span:
						offsets.append(offset)
	for item in satellites:
		if item.node != observer and item.node != excluded:
			obstacles.append({"position": item.node.position, "radius": float(item.config.radius_km)})
	for obstacle in obstacles:
		var delta: Vector2 = obstacle.position - origin
		var distance: float = delta.length()
		if distance <= obstacle.radius:
			continue
		var edge: float = asin(clampf(obstacle.radius / distance, 0.0, 1.0))
		for boundary in [delta.angle() - edge, delta.angle() + edge]:
			for epsilon in [-0.0001, 0.0, 0.0001]:
				var offset: float = fposmod(boundary + epsilon - start, TAU)
				if offset <= span:
					offsets.append(offset)
	offsets.sort()
	var angles: Array[float] = []
	for offset in offsets:
		angles.append(start + offset)
	return angles

func _ray_length(origin: Vector2, direction: Vector2, length: float, observer: Node2D = null, excluded: Node2D = null) -> float:
	var nearest := length
	var circles: Array = [{"center": Vector2.ZERO, "radius": float(controller.Config.planet.radius_km)}]
	for item in satellites:
		if item.node != observer and item.node != excluded:
			circles.append({"center": item.node.position, "radius": float(item.config.radius_km)})
	for circle in circles:
		var relative: Vector2 = origin - circle.center
		var radius: float = circle.radius
		var c: float = relative.length_squared() - radius * radius
		if c <= 0.0:
			return 0.0
		var b: float = relative.dot(direction)
		var discriminant: float = b * b - c
		if discriminant >= 0.0:
			var hit: float = -b - sqrt(discriminant)
			if hit >= 0.0:
				nearest = minf(nearest, hit)
	for item in debris:
		if item.node == observer or item.node == excluded:
			continue
		var polygon: PackedVector2Array = _debris_polygon(item.node)
		if Geometry2D.is_point_in_polygon(origin, polygon):
			return 0.0
		for i in range(polygon.size()):
			var a: Vector2 = polygon[i]
			var b: Vector2 = polygon[(i + 1) % polygon.size()]
			if segment_distance(a, b, origin) <= 0.000001:
				return 0.0
			for vertex in [a, b]:
				var projection: float = (vertex - origin).dot(direction)
				if projection >= 0.0 and projection <= nearest and absf((vertex - origin).cross(direction)) <= 0.000001:
					nearest = minf(nearest, projection)
			var hit: Variant = Geometry2D.segment_intersects_segment(origin, origin + direction * nearest, a, b)
			if hit != null:
				nearest = minf(nearest, origin.distance_to(hit))
			elif absf((a - origin).cross(direction)) <= 0.000001 and absf((b - origin).cross(direction)) <= 0.000001:
				var start: float = minf((a - origin).dot(direction), (b - origin).dot(direction))
				var end: float = maxf((a - origin).dot(direction), (b - origin).dot(direction))
				if end >= 0.0:
					nearest = minf(nearest, maxf(0.0, start))
	return nearest

func click(world: Vector2) -> bool:
	if dead:
		return false
	for satellite in satellites:
		if world.distance_to(satellite.node.position) <= maxf(10.0, float(satellite.config.radius_km)) and visible_to(controller.ship.position, satellite.node.position, satellite.node):
			_use_satellite(satellite.node)
			_update_hud()
			return true
	for enemy in enemies:
		if world.distance_to(enemy.node.position) <= 10.0 and visible_to(controller.ship.position, enemy.node.position, enemy.node):
			if _in_sector(controller.ship.position, enemy.node.position, scan_angle) and not controller.manually_paused and not controller.is_orbit_editing():
				selected = enemy.node
			_update_hud()
			return true
	return false

func _use_satellite(node: Node2D) -> void:
	if dead or controller.manually_paused or controller.is_orbit_editing() or get_tree().paused:
		return
	for satellite in satellites:
		if satellite.node == node and satellite.owner == "player" and (not node.has_method("fire_bomb") or node.descent_state == "ORBIT") and visible_to(controller.ship.position, node.position, node):
			if node.has_method("fire_bomb") and node.fire_bomb():
				satellite.capture_range.visible = false
				satellites.erase(satellite)
			satellite_pressed.emit(node)
			return

func fire_player() -> void:
	for i in range(weapon_slots.size()):
		if weapon_slots[i].id == "missile":
			fire_slot(i)
			return

func _stop_slot(slot: Dictionary) -> void:
	slot.active = false
	slot.target = null
	slot.remaining = 0.0
	slot.cooldown = float(config[slot.id].cooldown_real_s)
	slot.cooldown_started = true

func fire_slot(index: int) -> void:
	if index < 0 or index >= weapon_slots.size() or dead or controller.manually_paused or get_tree().paused or controller.is_orbit_editing():
		return
	var slot: Dictionary = weapon_slots[index]
	if slot.active:
		_stop_slot(slot)
	elif float(slot.cooldown) <= 0.0:
		match slot.id:
			"missile":
				if is_instance_valid(selected) and _is_active_target(selected) and controller.ship.position.distance_to(selected.global_position) <= float(config.radar.far_radius_km) and _launch(controller.ship.position, selected, "player"):
					_stop_slot(slot)
			"carrier":
				if _launch_carrier_squadrons():
					_stop_slot(slot)
					var audio := get_node_or_null("/root/AudioManager")
					if audio:
						audio.play_carrier_launch()
			"point_defense":
				slot.active = true
				slot.remaining = float(config.point_defense.duration_sim_s)
	queue_redraw()
	_update_point_defense_visual()
	_update_hud()

func _launch(pos: Vector2, target: Node2D, team: String) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion() or (team == "player" and not _is_active_target(target)) or (team == "enemy" and target != controller.ship):
		return false
	var node: Node2D = Missile.instantiate()
	add_child(node)
	node.position = pos
	node.rotation = (target.global_position - pos).angle()
	node.get_node("Body").color = Color(config.missile.color)
	missiles.append({"node": node, "target": target, "team": team, "life": float(config.missile.lifetime_s)})
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_missile_launch()
	return true

func remove_missile(missile: Dictionary) -> void:
	missiles.erase(missile)
	missile.node.queue_free()

func _is_active_target(node: Node2D) -> bool:
	for item in enemies:
		if item.node == node:
			return true
	return false

func damage_target(node: Node2D, amount: float) -> void:
	for list in [satellites, enemies]:
		for item in list.duplicate():
			if item.node == node:
				item.health -= amount
				if item.health <= 0.0:
					if selected == node:
						selected = null
					queue_redraw()
					if item.has("radar") and is_instance_valid(item.radar):
						item.radar.visible = false
					if item.has("capture_range"):
						item.capture_range.visible = false
					var was_enemy: bool = enemies.has(item)
					list.erase(item)
					node.visible = false
					if was_enemy:
						_clear_mothership_squadrons(node)
						enemy_destroyed.emit(node)
				return

func damage_player(amount: float) -> void:
	player_health = maxf(0.0, player_health - amount)
	if player_health <= 0.0:
		dead = true
		for slot in weapon_slots:
			if slot.active:
				_stop_slot(slot)
		queue_redraw()
		controller.manually_paused = true
		hud.get_node("Death").visible = true
		_set_lock_audio(false)
		_set_air_raid_audio(false)
		_clear_carrier_squadrons()
		for satellite in bombardment_satellites:
			satellite.reset_bombs()
		_update_point_defense_visual()
	_update_hud()

func _update_hud() -> void:
	if not is_instance_valid(hud):
		return
	hud.get_node("Panel/Health").text = "生命值 %.0f / %.0f" % [player_health, config.player.health]
	hud.get_node("Panel/Target").text = "目标已锁定" if is_instance_valid(selected) else "未锁定目标"
	var owned := 0
	var visible_count := 0
	for satellite in satellites:
		visible_count += 1
		if satellite.owner == "player":
			owned += 1
	hud.get_node("Panel/State").text = "卫星 %d · 我方 %d" % [visible_count, owned]
	for i in range(weapon_slots.size()):
		var slot: Dictionary = weapon_slots[i]
		var prefix := "Weapons/Slot%d/" % (i + 1)
		var cooldown: Label = hud.get_node(prefix + "Cooldown")
		var fire: Button = hud.get_node(prefix + "Fire")
		var title: String = str(config.weapons[slot.id].name) if config.weapons.has(slot.id) else "空槽"
		cooldown.text = "%d · CD %.1f秒" % [i + 1, slot.cooldown]
		var reason := ""
		if dead:
			reason = "已损毁"
		elif controller.manually_paused:
			reason = "暂停"
		elif controller.is_orbit_editing():
			reason = "调整中"
		elif slot.id == "":
			reason = "未装备"
		elif float(slot.cooldown) > 0.0:
			reason = "冷却中"
		elif not slot.active and slot.id == "missile" and (not is_instance_valid(selected) or not _is_active_target(selected) or controller.ship.position.distance_to(selected.global_position) > float(config.radar.far_radius_km)):
			reason = "未锁定"
		fire.disabled = not reason.is_empty()
		fire.text = title + ("：" + reason if not reason.is_empty() else (" · 停止" if slot.active else " · 启动"))
