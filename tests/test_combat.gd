extends SceneTree
const Config = preload("res://scripts/combat_config.gd")
const Loadout = preload("res://scripts/loadout.gd")

class LaunchAudioSpy extends Node:
	var launches := 0
	func play_air_force_launch() -> void:
		launches += 1
	func set_enemy_locked(_active: bool) -> void:
		pass
	func set_air_raid(_active: bool) -> void:
		pass

var scene: Node
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child.call_deferred(scene)
	run.call_deferred()

func send_shortcut(key: int, pressed := true, echo := false, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = pressed
	event.echo = echo
	event.shift_pressed = shift
	root.push_input(event)

func test_weapon_shortcuts(battle: Node) -> void:
	var saved: Array[Dictionary] = battle.weapon_slots.duplicate(true)
	for slot in battle.weapon_slots:
		slot.id = "point_defense"
		slot.cooldown = 0.0
		slot.active = false
	for i in range(4):
		send_shortcut(KEY_1 + i)
		check(battle.weapon_slots[i].active, "数字键启动对应装备槽 %d" % (i + 1))
	for i in range(4):
		send_shortcut(KEY_1 + i)
		check(not battle.weapon_slots[i].active and battle.weapon_slots[i].cooldown > 0.0, "数字键停止装备并进入冷却 %d" % (i + 1))
	send_shortcut(KEY_1)
	check(not battle.weapon_slots[0].active, "数字键遵守冷却")
	battle.weapon_slots[0].cooldown = 0.0
	send_shortcut(KEY_1, false)
	send_shortcut(KEY_1, true, true)
	send_shortcut(KEY_1, true, false, true)
	check(not battle.weapon_slots[0].active, "释放、重复和组合键不触发")
	scene.manually_paused = true
	send_shortcut(KEY_1)
	scene.manually_paused = false
	paused = true
	send_shortcut(KEY_1)
	paused = false
	scene.dragging = true
	send_shortcut(KEY_1)
	scene.dragging = false
	check(not battle.weapon_slots[0].active, "手动暂停、场景暂停或调轨时不触发")
	var edit := LineEdit.new()
	scene.get_node("CombatHUD").add_child(edit)
	edit.grab_focus()
	await process_frame
	send_shortcut(KEY_1)
	check(not battle.weapon_slots[0].active, "文本输入焦点时不触发")
	edit.free()
	battle.weapon_slots.assign(saved)
	battle._update_hud()

func run() -> void:
	scene.set_physics_process(false)
	var battle = scene.combat
	await test_weapon_shortcuts(battle)
	var packed: PackedScene = load("res://scenes/main.tscn")
	var edited_scene: Node = packed.instantiate()
	edited_scene.get_node("World/Combat/Enemies/Enemy1").position = Vector2(-245, 72)
	edited_scene.get_node("World/Combat/Satellites/Satellite1").position = Vector2(0, 200)
	root.add_child(edited_scene)
	check(edited_scene.combat.enemies[0].node.position == Vector2(-245, 72), "编辑器敌机位置初始化生效")
	check(absf(edited_scene.combat.satellites[0].angle - PI / 2.0) < 0.00001, "编辑器卫星位置控制初始相位")
	edited_scene.combat.enemies[0].node.position = Vector2.ZERO
	edited_scene.reset()
	check(edited_scene.combat.enemies[0].node.position == Vector2(-245, 72), "重置恢复编辑器敌机位置")
	check(absf(edited_scene.combat.satellites[0].angle - PI / 2.0) < 0.00001, "重置恢复编辑器卫星相位")
	edited_scene.free()
	var preview: Node = packed.instantiate()
	check(preview.has_node("World/Combat/Satellites/Satellite1") and preview.has_node("World/Combat/Satellites/Satellite2") and preview.has_node("World/Combat/Satellites/Satellite3"), "主场景编辑器包含三个卫星实例")
	check(preview.has_node("World/Combat/Enemies/Enemy1") and preview.has_node("CombatHUD"), "主场景编辑器包含敌机与战斗HUD")
	check(preview.get_node("HUD").scene_file_path == "res://scenes/orbit_hud.tscn" and preview.has_node("HUD/Layout/Controls/Pause") and preview.has_node("HUD/Layout/SpeedControl/SpeedSlider"), "轨道HUD为独立场景且保持节点路径")
	check(preview.has_node("World/Ship/PlayerHitPoint") and preview.get_node("World/Combat/InitialDebris").get_child_count() == 3, "主场景包含玩家判定点及三块初始碎片")
	preview.free()
	var original_satellite: Node2D = battle.satellites[0].node
	var original_enemy: Node2D = battle.enemies[0].node
	var original_hud: CanvasLayer = battle.hud
	var original_debris: Node2D = battle.debris[0].node
	var initial_enemy_position: Vector2 = battle.initial_enemy_transform.origin
	var initial_phase: float = battle.initial_satellite_angles[0]
	check(original_satellite == scene.get_node("World/Combat/Satellites/Satellite1") and original_enemy == scene.get_node("World/Combat/Enemies/Enemy1") and original_hud == scene.get_node("CombatHUD"), "运行时复用场景实例")
	check(original_satellite.get_node("Body").color == Color(battle.config.satellite.color) and original_enemy.get_node("Body").color == Color(battle.config.enemy.color), "初始实体应用JSON颜色")
	check(Config.validate(Config.DEFAULTS), "默认战斗配置有效")
	check(battle.config.weapons.missile.name == "追踪导弹" and battle.config.weapons.point_defense.name == "近防炮" and battle.config.weapons.carrier.name == "舰载机" and not battle.config.weapons.has("laser"), "武器名称读取统一配置且不含激光")
	var invalid_weapon: Dictionary = Config.DEFAULTS.duplicate(true)
	invalid_weapon.weapons.carrier.name = ""
	check(not Config.validate(invalid_weapon), "拒绝空武器名称")
	var invalid: Dictionary = Config.DEFAULTS.duplicate(true)
	invalid.radar.far_radius_km = -1
	check(not Config.validate(invalid), "无效参数拒绝")
	check(battle.satellites.size() == 3 and battle.enemies.size() == 1 and battle.debris.size() == 3, "初始实体")
	var sat: Dictionary = battle.satellites[0]
	var a: float = sat.angle
	battle.advance(1.0, scene.ship.position)
	check(sat.angle > a, "卫星按模拟秒运行")
	var old_health: float = battle.player_health
	battle.damage_player(10.0)
	check(battle.player_health == old_health - 10.0, "玩家伤害")
	battle.damage_player(1000.0)
	check(battle.dead and scene.manually_paused and battle.hud.get_node("Death").visible, "死亡界面与暂停")
	scene.reset()
	check(not battle.dead and battle.player_health == battle.config.player.health and battle.satellites.size() == 3, "重置战斗")
	check(battle.satellites[0].node == original_satellite and battle.enemies[0].node == original_enemy and battle.hud == original_hud and battle.debris[0].node == original_debris, "重置复用原静态实例")
	check(original_enemy.position == initial_enemy_position and absf(battle.satellites[0].angle - initial_phase) < 0.00001, "重置恢复敌机位置及卫星相位")
	check(scene.get_node("World/Combat/Satellites").get_child_count() == 3 and scene.get_node("World/Combat/Enemies").get_child_count() == 1, "重置不重复生成实体")
	check(battle.hud.get_node("Weapons/Slot1/Fire").pressed.get_connections().size() == 1 and battle.hud.get_node("Death/Layout/Restart").pressed.get_connections().size() == 1, "重置不重复连接信号")
	check(not battle.hud.has_node("Panel/EnemyVisibility"), "敌船可见开关已移除")
	var audio: Node = root.get_node("AudioManager")
	var audio_before: int = audio.get_child_count()
	check(not battle._launch(scene.ship.position, null, "player") and audio.get_child_count() == audio_before, "发射失败不播放音效")
	check(battle._launch(scene.ship.position, original_enemy, "player") and audio.get_child_count() == audio_before + 1, "玩家成功发射播放音效")
	check(battle._launch(original_enemy.position, scene.ship, "enemy") and audio.get_child_count() == audio_before + 2, "敌方成功发射播放音效且可重叠")
	battle.remove_missile(battle.missiles.back())
	battle.damage_target(original_enemy, 1000.0)
	battle.advance(0.01, scene.ship.position)
	check(battle.missiles.is_empty(), "静态目标销毁后追踪导弹失效")
	check(not original_enemy.visible and battle.enemies.is_empty(), "静态敌机销毁时隐藏并移除战斗")
	scene.reset()
	check(battle.enemies[0].node == original_enemy and battle.enemies[0].health == battle.config.enemy.health, "重置恢复销毁的静态敌机")
	battle.damage_target(original_satellite, 1000.0)
	check(not original_satellite.visible and battle.satellites.size() == 2, "静态卫星销毁时隐藏")
	scene.reset()
	check(battle.satellites[0].node == original_satellite and original_satellite.visible and battle.satellites.size() == 3, "重置恢复销毁的静态卫星")
	check(battle.segment_distance(Vector2(0, 0), Vector2(10, 0), Vector2(5, 1)) == 1.0, "扫掠距离")
	check(battle.visible_to(Vector2(-100, 0), Vector2(100, 0), null), "行星不阻挡雷达")
	var target: Dictionary = battle.satellites[0]
	scene.ship.position = target.node.position + Vector2(10, 0)
	battle.advance(0.01, target.node.position + Vector2(100, 0))
	check(target.owner == "player", "进入卫星判定夺控")
	battle.player_health = 50.0
	check(battle.click(target.node.position), "玩家卫星点击")
	check(battle.player_health == 50.0, "卫星点击不改变生命值")
	battle.player_cooldown = 0.0
	target.owner = "neutral"
	battle.scan_angle = PI
	check(battle.click(target.node.position), "目标点击锁定")
	check(battle.selected != target.node, "卫星点击不锁定")
	battle.fire_player()
	check(battle.missiles.is_empty(), "卫星不可发射导弹")
	var before: float = target.health
	battle.damage_target(target.node, 5.0)
	check(target.health == before - 5.0, "卫星受伤")
	var angle_before: float = target.angle
	scene.manually_paused = true
	scene._physics_process(1.0)
	check(target.angle == angle_before, "暂停冻结战斗")
	battle.damage_player(1000.0)
	scene.toggle_pause()
	check(scene.manually_paused, "死亡后无法恢复模拟")
	scene.reset()
	var s: Dictionary = battle.satellites[0]
	var p: Vector2 = s.node.position + Vector2(10, 0)
	scene.ship.position = p
	battle.advance(0.01, s.node.position + Vector2(100, 0))
	check(s.owner == "player", "玩家夺取卫星")
	var enemy: Dictionary = battle.enemies[0]
	enemy.node.position = s.node.position + Vector2(90.001, 0)
	enemy.velocity = Vector2(-0.8, 0)
	battle.advance(0.25, p)
	check(s.owner == "enemy", "敌机可再次夺取卫星")
	var n: int = battle.missiles.size()
	scene.ship.position = Vector2(320, 80)
	enemy.node.position = Vector2(345, 80)
	enemy.locked = false
	enemy.scan_angle = PI
	enemy.cooldown = 0.0
	battle.advance(0.01, scene.ship.position)
	check(battle.missiles.size() > n, "敌机探测玩家后发射")
	scene.reset()
	var item: Dictionary = battle.debris[0]
	scene.ship.position = item.node.position + Vector2(1, 0)
	var hp: float = battle.player_health
	battle.advance(0.01, scene.ship.position)
	check(battle.player_health < hp, "碎片接触扣血")
	var after_hit: float = battle.player_health
	battle.advance(0.01, scene.ship.position)
	check(battle.player_health == after_hit, "碎片接触冷却")
	scene.reset()
	var enemy_test: Dictionary = battle.enemies[0]
	scene.ship.position = Vector2(300, 0)
	enemy_test.node.position = Vector2(260, 0)
	battle.spawn_debris(Vector2(280, 0), false)
	enemy_test.cooldown = 0.0
	battle.advance(0.01, scene.ship.position)
	check(not battle.missiles.is_empty(), "碎片不阻挡敌机开火")
	scene.reset()
	var missile_target: Dictionary = battle.enemies[0]
	scene.ship.position = missile_target.node.position + Vector2(10, 0)
	battle.selected = missile_target.node
	battle.fire_player()
	var health_before: float = missile_target.health
	for i in range(30):
		battle.advance(0.25, scene.ship.position)
		if missile_target.health < health_before:
			break
	check(missile_target.health < health_before, "导弹实际命中造成伤害")
	check(battle.debris.size() == 3, "命中飞船不生成碎片")
	scene.reset()
	var blocker: Dictionary = battle.satellites[0]
	var blocked_ship: Dictionary = battle.enemies[0]
	var satellite_center: Vector2 = blocker.node.position
	blocked_ship.node.position = satellite_center + Vector2(120, 0)
	blocked_ship.health = 100.0
	scene.ship.position = Vector2(10000, 10000)
	var launch_from: Vector2 = satellite_center + Vector2(-12, 0)
	check(battle._launch(launch_from, blocked_ship.node, "player"), "构造撞卫星的导弹")
	var blocker_missile: Dictionary = battle.missiles.back()
	blocker_missile.node.position = launch_from
	blocker_missile.node.rotation = 0.0
	var debris_before_satellite: int = battle.debris.size()
	for i in range(40):
		battle.advance(0.25, scene.ship.position)
		if battle.debris.size() > debris_before_satellite:
			break
	check(battle.debris.size() == debris_before_satellite + 1, "命中卫星生成碎片")
	check(not battle.missiles.has(blocker_missile), "命中卫星后导弹消失")
	check(is_equal_approx(blocked_ship.health, 100.0), "命中卫星不改飞船血量")
	scene.reset()
	battle.spawn_debris(Vector2(300, 0), false)
	check(not battle._clear_ray(Vector2(300, 0), Vector2(350, 0), null), "观察者位于其他障碍内不透视")
	var observer: Node2D = battle.satellites[0].node
	check(battle._clear_ray(observer.position, observer.position + Vector2(20, 0), null, observer), "观察者自身排除")
	var angles: Array[float] = battle._sample_angles(Vector2(250, 0), -PI, TAU, 64, null)
	check(angles.size() > 65, "障碍边缘补充采样射线")
	scene.reset()
	var crossing: Dictionary = battle.satellites[0]
	scene.ship.position = crossing.node.position + Vector2(100, 0)
	battle.advance(0.001, crossing.node.position - Vector2(100, 0))
	check(crossing.owner == "player", "高速扫掠卫星判定范围夺控")
	scene.reset()
	var hostile: Dictionary = battle.enemies[0]
	scene.ship.position = Vector2(320, 80)
	hostile.node.position = Vector2(345, 80)
	hostile.scan_angle = PI
	hostile.cooldown = 0.0
	battle.advance(0.25, scene.ship.position)
	var spawned: Dictionary = battle.missiles.back()
	check(spawned.life == battle.config.missile.lifetime_s, "本步新敌弹尚未推进")
	scene.reset()
	var start_angle: float = battle.satellites[0].angle
	scene.manually_paused = false
	scene._physics_process(0.01)
	check(absf(battle.satellites[0].angle - start_angle - battle.config.satellite.angular_speed_rad_s * 0.6) < 0.00001, "主循环与战斗使用相同模拟秒")
	var frozen_angle: float = battle.satellites[0].angle
	scene.manually_paused = true
	scene._physics_process(10.0)
	check(battle.satellites[0].angle == frozen_angle, "主循环暂停冻结雷达及卫星")
	var locked: Node2D = battle.satellites[0].node
	scene.ship.position = locked.position + Vector2(20, 0)
	battle.selected = locked
	battle.player_cooldown = 0.0
	var paused_count: int = battle.missiles.size()
	battle.fire_player()
	check(battle.missiles.size() == paused_count, "暂停无法发射")
	scene.reset()
	scene.motion_mode = "FREE"
	scene.ship.position = battle.satellites[0].node.position + Vector2(10, 0)
	scene.flight.set_state(scene.ship.position, Vector2.ZERO)
	battle.scan_angle = PI
	battle.refresh_visuals()
	var pos: Vector2 = root.get_canvas_transform() * battle.satellites[0].node.position
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = pos
	scene._unhandled_input(click)
	check(not scene.flight.has_target and battle.selected != battle.satellites[0].node, "卫星点击优先于自由航点且不锁定")
	scene.reset()
	var inside: Dictionary = battle.satellites[0]
	var inside_pos: Vector2 = inside.node.position + Vector2(20, 0)
	scene.ship.position = inside_pos
	battle.advance(0.01, inside_pos)
	check(inside.owner == "player", "初始卫星判定范围内获得控制")
	scene.reset()
	var victim: Dictionary = battle.enemies[0]
	victim.node.position = Vector2(320, 80)
	victim.velocity = Vector2.ZERO
	victim.cooldown = 100.0
	battle.satellites.clear()
	battle._launch(Vector2(313.8, 80), victim.node, "player")
	var expiring: Dictionary = battle.missiles.back()
	expiring.life = 0.15
	var victim_hp: float = victim.health
	battle.advance(1.0, scene.ship.position)
	check(victim.health < victim_hp, "寿命剩余区间内导弹仍可命中")
	scene.reset()
	battle.spawn_debris(Vector2(300, 0), false)
	var polygon_debris: Node2D = battle.debris.back().node
	check(battle._polygon_blocks(Vector2(280, -6.5), Vector2(320, -6.5), polygon_debris), "真实碎片多边形突出部分遮挡")
	check(not battle._polygon_blocks(Vector2(280, 6.5), Vector2(320, 6.5), polygon_debris), "多边形外空白不被圆形误挡")
	check(battle._polygon_blocks(Vector2(290, -7), Vector2(300, -7), polygon_debris), "顶点相切遮挡")
	check(battle._polygon_contact(Vector2(280, -8), Vector2(320, -8), polygon_debris, 2.0), "多边形边缘擦碰")
	check(not battle._polygon_contact(Vector2(280, 10), Vector2(320, 10), polygon_debris, 2.0), "多边形外无接触")
	var ray: float = battle._ray_length(Vector2(280, 0), Vector2.RIGHT, 100.0)
	check(ray > 12.0 and ray < 20.0, "射线解析命中多边形前表面")
	var excluded_ray: float = battle._ray_length(Vector2(280, 0), Vector2.RIGHT, 30.0, null, polygon_debris)
	check(excluded_ray > ray, "逐实体射线排除目标本体")
	scene.reset()
	battle.spawn_debris(Vector2(300, 0), false)
	var edge_node: Node2D = battle.debris.back().node
	var edge_body: Polygon2D = edge_node.get_node("Body")
	edge_body.scale = Vector2.ONE
	edge_body.polygon = PackedVector2Array([Vector2(5, 0), Vector2(10, 0), Vector2(10, 4), Vector2(5, 4)])
	check(absf(battle._ray_length(Vector2(300, 0), Vector2.RIGHT, 20.0) - 5.0) < 0.001, "共线边首交")
	check(absf(battle._ray_length(Vector2(312, 0), Vector2.LEFT, 20.0) - 2.0) < 0.001, "反向共线边首交")
	check(battle._ray_length(Vector2(305, 0), Vector2.RIGHT, 20.0) == 0.0, "射线起点位于边界")
	check(absf(battle._ray_length(Vector2(300, 0), Vector2.LEFT, 2.0) - 2.0) < 0.001, "共线边位于射线外")
	edge_body.polygon = PackedVector2Array([Vector2(5, 0.0000005), Vector2(4, 1), Vector2(6, 1)])
	check(not battle._clear_ray(Vector2(300, 0), Vector2(310, 0), null), "近擦顶点 LOS 阻挡")
	check(absf(battle._ray_length(Vector2(300, 0), Vector2.RIGHT, 10.0) - 5.0) < 0.001, "近擦顶点射线与 LOS 一致")
	scene.reset()
	scene.ship.position = Vector2(300, 0)
	var display_enemy: Node2D = battle.enemies[0].node
	display_enemy.position = Vector2(340, 0)
	battle.refresh_visuals()
	check(display_enemy.visible, "近圆内无遮挡敌船可见")
	battle.spawn_debris(Vector2(320, 0), false)
	battle.refresh_visuals()
	check(display_enemy.visible, "碎片不遮挡敌船显示")
	check(battle.click(display_enemy.position), "碎片不阻挡敌船点击")
	battle.selected = display_enemy
	scene.manually_paused = false
	var missile_count: int = battle.missiles.size()
	battle.fire_player()
	check(battle.missiles.size() == missile_count + 1, "碎片不阻挡发射")
	scene.ship.position = Vector2(300, 100)
	display_enemy.position = Vector2(480, 100)
	battle.scan_angle = 0.0
	battle.refresh_visuals()
	check(display_enemy.visible, "远扇内无遮挡敌船可见")
	battle.scan_angle = PI / 2.0
	battle.refresh_visuals()
	check(display_enemy.visible, "远扇外敌船可见")
	display_enemy.position = Vector2(600, 0)
	battle.scan_angle = 0.0
	battle.refresh_visuals()
	check(display_enemy.visible, "远雷达范围外敌船可见")
	check(battle.satellites[0].node.visible and battle.debris[0].node.visible, "卫星与碎片仍可见")
	scene.manually_paused = true
	display_enemy.position = Vector2(-300, 100)
	battle.refresh_visuals()
	check(display_enemy.visible, "暂停时范围外敌船可见")
	battle.selected = display_enemy
	battle.refresh_visuals()
	check(battle.hud.get_node("Weapons/Slot1/Fire").disabled and "暂停" in battle.hud.get_node("Weapons/Slot1/Fire").text, "暂停禁发并显示原因")
	scene.reset()
	battle.satellites[0].config.capture_radius_km = 20.0
	battle.config.radar.near_radius_km = 90.0
	var separate: Dictionary = battle.satellites[0]
	scene.ship.position = separate.node.position + Vector2(50, 0)
	battle.advance(0.01, scene.ship.position)
	check(separate.owner == "neutral", "玩家雷达范围内但卫星范围外不夺控")
	scene.ship.position = separate.node.position + Vector2(10, 0)
	battle.advance(0.01, separate.node.position + Vector2(50, 0))
	check(separate.owner == "player", "进入卫星独立半径夺控")
	battle.refresh_visuals()
	check(absf(separate.capture_range.get_node("Boundary").points[0].length() - 20.0) < 0.001, "卫星显示半径与夺控半径一致")
	check(absf(battle.player_radar.get_node("NearBoundary").points[0].length() - 90.0) < 0.001, "玩家雷达半径独立")
	check(separate.capture_range.scene_file_path == "res://scenes/capture_range.tscn" and separate.capture_range.get_child_count() == 1 and not separate.capture_range.has_node("SectorBoundary"), "卫星范围为独立圆形场景且无扇形")
	check(battle.player_radar.get_node("SectorBoundary").points.size() > 2, "玩家雷达保留扫描扇形")
	var capture_range_node: Node2D = separate.capture_range
	battle.damage_target(separate.node, 1000.0)
	check(not capture_range_node.visible, "卫星销毁隐藏判定圆")
	scene.reset()
	check(battle.satellites[0].capture_range == capture_range_node and capture_range_node.visible, "重置复用并恢复判定圆")
	scene.reset()
	battle.satellites.clear()
	var automatic: Dictionary = battle.enemies[0]
	scene.ship.position = Vector2(300, 100)
	automatic.node.position = Vector2(340, 100)
	automatic.cooldown = 100.0
	battle.scan_angle = PI / 2.0
	battle.advance(0.01, scene.ship.position)
	check(battle.selected == null, "近圆扇外不会自动锁定")
	battle.scan_angle = 0.0
	battle.spawn_debris(Vector2(320, 100), false)
	battle.advance(0.01, scene.ship.position)
	check(battle.selected == automatic.node, "扇区无点击自动锁定且不受碎片遮挡")
	var shot_count: int = battle.missiles.size()
	battle.fire_player()
	check(battle.missiles.size() == shot_count + 1, "自动锁定后无点击发射")
	automatic.node.position = Vector2(300, 160)
	battle.advance(0.01, scene.ship.position)
	check(battle.selected == automatic.node and absf(angle_difference(battle.scan_angle, PI / 2.0)) < 0.01, "锁定后扫描跟踪目标")
	automatic.node.position = Vector2(600, 100)
	battle.advance(0.01, scene.ship.position)
	check(battle.selected == null, "目标超出距离失锁")
	automatic.node.position = Vector2(340, 100)
	battle.scan_angle = 0.0
	battle.advance(0.01, scene.ship.position)
	battle.damage_target(automatic.node, 10000.0)
	check(battle.selected == null, "目标销毁立即失锁")
	scene.reset()
	battle.satellites.clear()
	var attacker: Dictionary = battle.enemies[0]
	scene.ship.position = Vector2(340, 100)
	attacker.node.position = Vector2(300, 100)
	attacker.scan_angle = PI / 2.0
	attacker.cooldown = 0.0
	battle.advance(0.01, scene.ship.position)
	check(not attacker.locked and battle.missiles.is_empty(), "敌机近圆扇外不锁定")
	attacker.scan_angle = 0.0
	battle.spawn_debris(Vector2(320, 100), false)
	battle.advance(0.01, scene.ship.position)
	check(attacker.locked and not battle.missiles.is_empty(), "敌机扇区无遮挡限制并自动开火")
	battle._update_lock_warning()
	check(battle.hud.get_node("LockWarning").visible and audio.is_enemy_locked_requested(), "导弹敌舰触发锁定警告与音效")
	for weapon in ["carrier", "satellite_deployer"]:
		attacker.weapon = weapon
		attacker.locked = true
		attacker.scan_angle = 0.0
		battle._sync_lock_audio()
		battle._update_lock_warning()
		check(not audio.is_enemy_locked_requested() and not battle.hud.get_node("LockWarning").visible, weapon + " 残留锁定不触发警告及音效")
		battle.enemy_fire_enabled = false
		battle.advance(0.01, scene.ship.position)
		check(not attacker.locked and attacker.scan_angle == 0.0, weapon + " 不扫描、不锁定")
		battle.refresh_visuals()
		check(not attacker.radar.visible, weapon + " 不显示雷达锁定图形")
	battle.enemy_fire_enabled = true
	attacker.weapon = "missile"
	attacker.scan_angle = 0.0
	battle.advance(0.01, scene.ship.position)
	check(attacker.locked and audio.is_enemy_locked_requested(), "切回导弹敌舰后正常锁定和警报")
	var original_enemy_config_path: String = original_enemy.config_path
	for weapon in ["carrier", "satellite_deployer"]:
		original_enemy.config_path = "res://data/enemy_carrier.json" if weapon == "carrier" else "res://data/enemy_deployer.json"
		scene.reset()
		attacker = battle.enemies[0]
		check(attacker.weapon == weapon and not attacker.locked and not audio.is_enemy_locked_requested(), weapon + " 配置重置后不锁定且警报关闭")
		battle.satellites.clear()
		scene.ship.position = Vector2(340, 100)
		attacker.node.position = Vector2(300, 100)
		attacker.scan_angle = 0.0
		battle.enemy_fire_enabled = false
		battle.advance(0.01, scene.ship.position)
		battle._update_lock_warning()
		check(not attacker.locked and not battle.hud.get_node("LockWarning").visible and not audio.is_enemy_locked_requested(), weapon + " 配置实际战斗路径不触发锁定")
	original_enemy.config_path = original_enemy_config_path
	scene.reset()
	battle.enemy_fire_enabled = true
	attacker = battle.enemies[0]
	scene.manually_paused = true
	var frozen_scan: float = battle.scan_angle
	var frozen_enemy_scan: float = attacker.scan_angle
	battle._update_hud()
	scene._physics_process(1.0)
	check(battle.scan_angle == frozen_scan and attacker.scan_angle == frozen_enemy_scan, "暂停冻结双方扫描")
	check("暂停" in battle.hud.get_node("Weapons/Slot1/Fire").text, "暂停显示禁发原因")
	scene.reset()
	battle.satellites.clear()
	var swept: Dictionary = battle.enemies[0]
	scene.ship.position = Vector2(300, 100)
	swept.node.position = Vector2(340, 100)
	swept.cooldown = 100.0
	battle.scan_angle = -PI / 2.0
	battle.config.radar.rotation_rad_s = PI
	battle.advance(1.0, scene.ship.position)
	check(battle.selected == swept.node, "玩家扫描跨越目标时捕获")
	scene.reset()
	battle.satellites.clear()
	swept = battle.enemies[0]
	scene.ship.position = Vector2(340, 100)
	swept.node.position = Vector2(300, 100)
	swept.scan_angle = -PI / 2.0
	battle.config.radar.rotation_rad_s = PI
	battle.advance(1.0, scene.ship.position)
	check(swept.locked, "敌机扫描跨越玩家时捕获")
	check(battle.max_step() <= 0.01 / PI + 0.000001, "高扫描速度限制模拟子步")
	scene.reset()
	var button_sat: Dictionary = battle.satellites[0]
	scene.ship.position = button_sat.node.position + Vector2(15, 0)
	battle.enemies[0].node.position = Vector2(900, 900)
	battle.scan_angle = PI
	battle.advance(0.01, scene.ship.position)
	check(battle.selected == null, "扇形不自动锁定卫星")
	check(button_sat.owner == "player", "进入圆形范围控制卫星")
	battle.refresh_visuals()
	battle._update_satellites(0.0)
	check(button_sat.node.get_node("Action").visible, "我方卫星显示按钮")
	battle.player_health = 50.0
	battle.player_cooldown = 7.0
	for i in range(3):
		button_sat.node.get_node("Action").pressed.emit()
		battle.click(button_sat.node.position)
	check(battle.player_health == 50.0 and battle.player_cooldown == 7.0, "反复点击卫星不改变生命值或绕过冷却")
	var prior_count: int = battle.missiles.size()
	battle._launch(scene.ship.position, button_sat.node, "player")
	battle._launch(scene.ship.position, button_sat.node, "enemy")
	check(battle.missiles.size() == prior_count, "双方导弹均禁止瞄准卫星")
	scene.reset()
	var cd_enemy: Dictionary = battle.enemies[0]
	cd_enemy.node.position = scene.ship.position + Vector2(40, 0)
	cd_enemy.cooldown = 100.0
	battle.selected = cd_enemy.node
	battle.config.missile.cooldown_real_s = 12.0
	battle.fire_player()
	check(is_equal_approx(battle.player_cooldown, 12.0), "玩家冷却使用配置")
	check("12.0" in battle.hud.get_node("Weapons/Slot1/Cooldown").text, "HUD显示冷却剩余")
	var shots: int = battle.missiles.size()
	battle.fire_player()
	check(battle.missiles.size() == shots, "冷却期间不能再次发射")
	battle.advance(2.0, scene.ship.position)
	check(is_equal_approx(battle.player_cooldown, 12.0), "模拟子步不推进现实冷却")
	battle.advance_cooldowns(0.01)
	battle.advance_cooldowns(2.0)
	check(is_equal_approx(battle.player_cooldown, 10.0), "冷却按现实帧时间推进")
	scene.manually_paused = true
	scene._physics_process(1.0)
	check(is_equal_approx(battle.player_cooldown, 10.0), "暂停冻结冷却")
	scene.reset()
	var orbiting: Dictionary = battle.debris[0]
	var start_pos: Vector2 = orbiting.node.position
	var orbit_radius: float = start_pos.length()
	scene.ship.position = Vector2(800, 800)
	battle.advance(1.0, scene.ship.position)
	check(orbiting.node.position.distance_to(start_pos) > 0.001 and absf(orbiting.node.position.length() - orbit_radius) < 0.001, "初始碎片圆周公转")
	battle.spawn_debris(Vector2(250, 0), true)
	var generated: Dictionary = battle.debris.back()
	battle.advance(1.0, scene.ship.position)
	check(generated.node.position.distance_to(Vector2(250, 0)) > 0.001 and absf(generated.node.position.length() - 250.0) < 0.001, "生成碎片圆周公转")
	var original_debris_node: Node2D = orbiting.node
	scene.reset()
	check(battle.debris[0].node == original_debris_node and original_debris_node.position.distance_to(start_pos) < 0.001, "重置复用并恢复初始碎片位置")
	check(battle.debris.size() == 3, "重置移除生成碎片")
	scene.reset()
	scene.ship.position = Vector2(200, 0)
	battle.spawn_debris(Vector2(200, -15), true)
	var moving: Dictionary = battle.debris.back()
	battle.config.debris.orbit_speed_factor = 100.0
	var health_at_crossing: float = battle.player_health
	battle.advance(2.0, scene.ship.position)
	check(battle.player_health < health_at_crossing, "移动碎片相对扫掠可命中静止玩家")
	scene.manually_paused = true
	var frozen_debris: Vector2 = moving.node.position
	scene._physics_process(1.0)
	check(moving.node.position == frozen_debris, "暂停冻结碎片公转")
	scene.reset()
	battle.satellites.clear()
	scene.ship.position = Vector2(340, 100)
	var cooldown_enemy: Dictionary = battle.enemies[0]
	cooldown_enemy.node.position = Vector2(300, 100)
	cooldown_enemy.scan_angle = 0.0
	battle.advance(0.01, scene.ship.position)
	check(battle.missiles.size() == 1 and is_equal_approx(cooldown_enemy.cooldown, 5.0), "敌机发射后启动5现实秒冷却")
	check("CD 5.0" in cooldown_enemy.node.get_node("Health").text, "敌机显示剩余冷却")
	battle.advance_cooldowns(0.01)
	battle.advance_cooldowns(4.5)
	battle.advance(0.01, scene.ship.position)
	check(battle.missiles.size() == 1 and is_equal_approx(cooldown_enemy.cooldown, 0.5), "冷却未结束不再次发射")
	scene.manually_paused = true
	scene._physics_process(1.0)
	check(is_equal_approx(cooldown_enemy.cooldown, 0.5), "暂停冻结敌机冷却")
	scene.manually_paused = false
	scene.speed_dragging = true
	scene._physics_process(1.0)
	check(is_equal_approx(cooldown_enemy.cooldown, 0.5), "调速预览冻结敌机冷却")
	scene.speed_dragging = false
	scene.dragging = true
	scene._physics_process(1.0)
	check(is_equal_approx(cooldown_enemy.cooldown, 0.5), "轨道调整冻结敌机冷却")
	scene.dragging = false
	battle.advance_cooldowns(0.5)
	battle.advance(0.01, scene.ship.position)
	check(battle.missiles.size() == 2 and is_equal_approx(cooldown_enemy.cooldown, 5.0), "冷却结束后再次发射")
	var other_node: Node2D = load("res://scenes/enemy.tscn").instantiate()
	battle.get_node("Enemies").add_child(other_node)
	other_node.position = Vector2(310, 100)
	other_node.initialize("enemy", battle.config.enemy)
	var other_enemy := {"node": other_node, "config": other_node.entity_config, "velocity": Vector2.ZERO, "health": 100.0, "cooldown": 0.0, "radar": other_node.get_node("Radar"), "scan_angle": 0.0, "locked": false}
	other_node.state = other_enemy
	battle.enemies.append(other_enemy)
	battle.advance_cooldowns(0.01)
	battle.advance_cooldowns(0.01)
	battle.advance(0.01, scene.ship.position)
	check(is_equal_approx(other_enemy.cooldown, 5.0) and cooldown_enemy.cooldown < 5.0, "每艘敌机独立冷却")
	battle.enemies.erase(other_enemy)
	other_node.free()
	scene.reset()
	check(battle.enemies[0].cooldown == 0.0, "重置清零敌机冷却")
	var legacy: Dictionary = Config.DEFAULTS.duplicate(true)
	legacy.missile.erase("cooldown_real_s")
	legacy.missile.cooldown_s = 8.0
	legacy = Config.migrate_legacy(legacy)
	check(Config.validate(legacy) and legacy.missile.cooldown_real_s == 5.0, "旧模拟冷却字段迁移为5现实秒")
	legacy.missile.cooldown_real_s = 4.9
	check(not Config.validate(legacy), "配置拒绝低于5现实秒")
	for rate in [1.0, 60.0]:
		scene.reset()
		scene.simulation_speed = rate
		battle.enemies[0].cooldown = 5.0
		battle.player_cooldown = 5.0
		scene._physics_process(0.1)
		check(is_equal_approx(battle.player_cooldown, 4.9) and is_equal_approx(battle.enemies[0].cooldown, 4.9), "不同模拟倍率按相同现实时间冷却")
	scene.simulation_speed = 1.0
	scene._physics_process(0.1)
	check(is_equal_approx(battle.player_cooldown, 4.8), "运行中切换倍率不改变现实计时")
	scene.reset()
	scene.simulation_speed = 60.0
	battle.satellites.clear()
	scene.ship.position = Vector2(340, 100)
	var boundary_enemy: Dictionary = battle.enemies[0]
	boundary_enemy.node.position = Vector2(300, 100)
	boundary_enemy.scan_angle = 0.0
	battle.advance(0.01, scene.ship.position)
	scene._physics_process(0.1)
	check(is_equal_approx(boundary_enemy.cooldown, 5.0), "发射后第一帧保守处理避免提前冷却")
	scene.reset()
	var physics_enemy: Dictionary = battle.enemies[0]
	var initial_position: Vector2 = physics_enemy.node.position
	var initial_velocity: Vector2 = physics_enemy.velocity
	var expected_speed: float = sqrt(scene._gravity(initial_position).length() * initial_position.length())
	check(absf(initial_velocity.length() - expected_speed) < 0.00001 and absf(initial_velocity.dot(initial_position)) < 0.001, "敌机初始切向圆速")
	battle.satellites.clear()
	var gravity_start: Vector2 = scene._gravity(initial_position)
	battle.dead = true
	physics_enemy.node.behavior.advance(physics_enemy.node, battle, {}, 0.1)
	battle.dead = false
	check(physics_enemy.node.position.distance_to(initial_position) > 0.001 and physics_enemy.velocity.distance_to(initial_velocity + gravity_start * 0.1) < 0.0001, "玩家死亡时按引力滑行")
	var coasting_position: Vector2 = physics_enemy.node.position
	var coasting_velocity: Vector2 = physics_enemy.velocity
	scene.ship.position = coasting_position.normalized() * (coasting_position.length() + 30.0)
	check(physics_enemy.node.behavior.advance(physics_enemy.node, battle, {}, 0.1), "忽略空卫星目标并追踪玩家")
	var velocity_change: Vector2 = physics_enemy.velocity - coasting_velocity - scene._gravity(coasting_position) * 0.1
	check(velocity_change.length() <= float(battle.config.enemy.acceleration_km_s2) * 0.1 + 0.0001, "推力导致的速度变化受加速度限制")
	check(physics_enemy.node.position.distance_to(coasting_position) < coasting_velocity.length() * 0.1 + 0.01, "推力推进位置连续")
	physics_enemy.node.position = Vector2(scene.gravity_radius + 50.0, 0)
	physics_enemy.velocity = Vector2(1, 0.2)
	var outside: Vector2 = physics_enemy.node.position
	battle.dead = true
	physics_enemy.node.behavior.advance(physics_enemy.node, battle, {}, 0.25)
	battle.dead = false
	check(physics_enemy.node.position.distance_to(outside + Vector2(1, 0.2) * 0.25) < 0.0001 and physics_enemy.velocity == Vector2(1, 0.2), "玩家死亡且圈外时惯性飞行")
	physics_enemy.node.position = Vector2(scene.Config.planet.radius_km + 1.0, 0)
	physics_enemy.velocity = Vector2(-2, 0)
	battle.advance(1.0, scene.ship.position)
	check(battle.enemies.is_empty() and not physics_enemy.node.visible, "敌机碰撞行星销毁")
	scene.reset()
	check(battle.enemies[0].node == physics_enemy.node and physics_enemy.node.position.distance_to(initial_position) < 0.001 and battle.enemies[0].velocity.distance_to(initial_velocity) < 0.00001, "重置恢复敌机位置及初速度")
	for phase in [0.0, PI / 2.0, PI]:
		scene.reset()
		scene.ship.position = Vector2(10000, 10000)
		var orbital_enemy: Dictionary = battle.enemies[0]
		orbital_enemy.node.position = battle.initial_enemy_transform.origin.rotated(phase)
		orbital_enemy.velocity = Vector2(-orbital_enemy.node.position.y, orbital_enemy.node.position.x).normalized() * sqrt(scene._gravity(orbital_enemy.node.position).length() * orbital_enemy.node.position.length())
		var minimum := INF
		var maximum := 0.0
		var captured := 0
		for i in range(16000):
			battle.advance(0.125, scene.ship.position)
			if battle.enemies.is_empty():
				break
			var r: float = orbital_enemy.node.position.length()
			minimum = minf(minimum, r)
			maximum = maxf(maximum, r)
		for sat_item in battle.satellites:
			if sat_item.owner == "enemy":
				captured += 1
		print("ENEMY_LONG phase=", phase, " min=", minimum, " max=", maximum, " captured=", captured, " alive=", not battle.enemies.is_empty())
		check(not battle.enemies.is_empty() and maximum < scene.gravity_radius and minimum > scene.Config.planet.radius_km, "长期运行不逃逸或撞行星")
		check(is_finite(minimum) and is_finite(maximum), "玩家不在同一引力域时长期滑行状态有限")
	scene.reset()
	var contact_sat: Dictionary = battle.satellites[0]
	var contact_enemy: Dictionary = battle.enemies[0]
	scene.ship.position = Vector2(10000, 10000)
	contact_enemy.node.position = contact_sat.node.position
	battle.advance(0.001, scene.ship.position)
	check(contact_sat.owner == "enemy", "敌机接触卫星仍可夺控")
	scene.reset()
	var first_sat: Dictionary = battle.satellites[0]
	var second_sat: Dictionary = battle.satellites[1]
	check(first_sat.node.config_path == "res://data/satellite_default.json" and battle.enemies[0].node.config_path == "res://data/enemy_default.json", "主场景实例显式配置路径")
	first_sat.config.capture_radius_km = 37.0
	first_sat.config.angular_speed_rad_s = 0.01
	first_sat.config.orbit_radius_km = 220.0
	battle._update_satellites(0.5)
	battle.refresh_visuals()
	check(absf(first_sat.node.position.length() - 220.0) < 0.001 and absf(first_sat.capture_range.get_node("Boundary").points[0].length() - 37.0) < 0.001, "卫星实例轨道和范围读取各自配置")
	check(absf(second_sat.config.capture_radius_km - 90.0) < 0.001 and absf(second_sat.node.position.length() - 190.0) < 0.001, "卫星配置互相独立")
	var nested_enemy = load("res://scripts/enemy_nested_behavior.gd").new()
	var nested_sat = load("res://scripts/satellite_nested_behavior.gd").new()
	check(not nested_enemy.parse({"properties": {"flight": battle.config.enemy}}).is_empty(), "嵌套敌机类型解析自身结构")
	check(not nested_sat.parse({"properties": {"orbit": battle.config.satellite}}).is_empty(), "嵌套卫星类型解析自身结构")
	check(nested_enemy.parse({"properties": 1}).is_empty() and nested_sat.parse({"properties": []}).is_empty(), "不同类型拒绝错误结构")
	var sat_identity: Node2D = first_sat.node
	scene.reset()
	check(battle.satellites[0].node == sat_identity and is_equal_approx(battle.satellites[0].config.capture_radius_km, 90.0), "重置重新加载配置并复用节点")
	var multi_scene: Node = packed.instantiate()
	var extra_enemy: Node2D = load("res://scenes/enemy.tscn").instantiate()
	extra_enemy.config_path = "res://tests/entity_enemy_nested.json"
	extra_enemy.position = Vector2(-200, -40)
	multi_scene.get_node("World/Combat/Enemies").add_child(extra_enemy)
	var second_sat_node: Node2D = multi_scene.get_node("World/Combat/Satellites/Satellite2")
	second_sat_node.config_path = "res://tests/entity_satellite_nested.json"
	root.add_child(multi_scene)
	multi_scene.set_physics_process(false)
	var multi = multi_scene.combat
	check(multi.enemies.size() == 2 and multi.enemies[1].health == 45.0 and multi.enemies[1].config.radius_km == 12.0, "不同JSON敌机按各自数据初始化")
	check(multi.enemies[0].radar != multi.enemies[1].radar and multi.enemies[1].radar == extra_enemy.get_node("Radar"), "每艘敌机拥有独立雷达")
	check(absf(multi.satellites[1].node.position.length() - 230.0) < 0.001 and multi.satellites[1].config.capture_radius_km == 35.0, "不同JSON卫星按各自轨道及范围初始化")
	check(multi.enemies[1].node.behavior.get_script().resource_path.ends_with("enemy_nested_behavior.gd") and second_sat_node.behavior.get_script().resource_path.ends_with("satellite_nested_behavior.gd"), "JSON类型实际分派不同策略")
	multi_scene.reset()
	check(multi.enemies.size() == 2 and multi.enemies[1].node == extra_enemy and multi.enemies[1].health == 45.0, "多实例重置复用并恢复数据")
	multi_scene.free()
	var bad_node: Node2D = load("res://scenes/enemy.tscn").instantiate()
	bad_node.config_path = "res://tests/entity_unknown.json"
	check(not bad_node.initialize("enemy", battle.config.enemy) and not bad_node.visible, "未知类型拒绝并禁用实例")
	bad_node.config_path = "res://tests/entity_invalid.json"
	check(not bad_node.initialize("enemy", battle.config.enemy) and not bad_node.visible, "无效结构拒绝并禁用实例")
	bad_node.config_path = "res://tests/nonexistent.json"
	check(not bad_node.initialize("enemy", battle.config.enemy) and not bad_node.visible, "不可读取配置拒绝并禁用实例")
	bad_node.config_path = ""
	check(bad_node.initialize("enemy", battle.config.enemy) and bad_node.entity_config.health == battle.config.enemy.health, "空路径兼容全局配置")
	bad_node.free()
	scene.reset()
	battle.satellites.clear()
	battle.enemy_fire_enabled = false
	scene.ship.position = Vector2(340, 100)
	var weapon_enemy: Dictionary = battle.enemies[0]
	weapon_enemy.node.position = Vector2(300, 100)
	weapon_enemy.cooldown = 100.0
	battle.selected = weapon_enemy.node
	battle.weapon_slots[0].id = "missile"
	battle.weapon_slots[1].id = "missile"
	battle.weapon_slots[2].id = "point_defense"
	battle.weapon_slots[3].id = ""
	battle.fire_slot(0)
	battle.fire_slot(1)
	check(battle.missiles.size() == 2 and battle.weapon_slots[0].cooldown > 0.0 and battle.weapon_slots[1].cooldown > 0.0, "同类导弹槽独立发射并冷却")
	battle.weapon_slots[0].cooldown = 0.0
	check(battle.weapon_slots[1].cooldown > 0.0, "同类槽冷却互相独立")
	battle.fire_slot(2)
	battle.fire_slot(3)
	check(battle.weapon_slots[2].active and not battle.weapon_slots[3].active, "近防启动且空槽不激活")
	battle._launch(Vector2(380, 100), scene.ship, "enemy")
	var hostile_missile: Dictionary = battle.missiles.back()
	hostile_missile.node.rotation = PI
	battle.advance(5.0, scene.ship.position)
	check(not battle.missiles.has(hostile_missile) and battle.player_health == battle.config.player.health, "近防扫掠拦截敌弹")
	battle.weapon_slots[2].remaining = 0.1
	battle.advance(0.2, scene.ship.position)
	check(not battle.weapon_slots[2].active and battle.weapon_slots[2].cooldown > 0.0, "近防结束进入冷却")
	var remaining_cd: float = battle.weapon_slots[2].cooldown
	scene.manually_paused = true
	scene._physics_process(1.0)
	check(battle.weapon_slots[2].cooldown == remaining_cd, "暂停冻结武器冷却")
	scene.reset()
	check(battle.weapon_slots.size() == 4 and not battle.weapon_slots[2].active, "重置恢复四槽状态")
	var glow: Polygon2D = scene.ship.get_node("PointDefenseGlow")
	var hull: Polygon2D = scene.ship.get_node("Hull")
	var original_hull_color: Color = hull.color
	battle.weapon_slots[1].id = "point_defense"
	battle.weapon_slots[2].id = "point_defense"
	check(not glow.visible and glow.get_parent() == scene.ship, "近防光环默认隐藏且跟随飞船")
	battle.fire_slot(1)
	check(glow.visible and hull.color == original_hull_color, "近防启动显示蓝色光环且不改变船体")
	scene.camera.zoom = Vector2.ONE * 0.22
	battle._update_point_defense_visual()
	check(is_equal_approx(glow.scale.x * scene.camera.zoom.x, 0.5), "最低缩放时保障光环屏幕尺寸")
	scene.camera.zoom = Vector2.ONE * 2.0
	battle._update_point_defense_visual()
	check(glow.scale == Vector2.ONE, "放大时光环随摄像机正常缩放")
	battle.fire_slot(2)
	battle.fire_slot(1)
	check(glow.visible and battle.weapon_slots[2].active, "一个近防槽停止时另一槽仍显示")
	scene.manually_paused = true
	battle._process(0.0)
	check(not glow.visible and battle.weapon_slots[2].active, "暂停隐藏光环并保留近防状态")
	scene.manually_paused = false
	battle._process(0.0)
	check(glow.visible, "恢复运行后光环重新显示")
	scene.speed_dragging = true
	battle._process(0.0)
	check(not glow.visible, "轨道预览隐藏光环")
	scene.speed_dragging = false
	paused = true
	battle._process(0.0)
	check(not glow.visible, "场景树暂停隐藏光环")
	paused = false
	battle.weapon_slots[2].remaining = 0.01
	battle.advance(0.02, scene.ship.position)
	check(not glow.visible and not battle.weapon_slots[2].active, "最后近防到期光环立即隐藏")
	battle.weapon_slots[1].cooldown = 0.0
	battle.fire_slot(1)
	battle.damage_player(1000.0)
	check(not glow.visible and hull.color == original_hull_color, "死亡时隐藏光环且不改变船体颜色")
	scene.reset()
	check(not glow.visible, "重置后隐藏光环")
	var level = load("res://scenes/level_4.tscn").instantiate()
	var air_container := Node2D.new()
	air_container.name = "AirForces"
	level.get_node("Sandbox/World").add_child(air_container)
	var force = load("res://scenes/air_force.tscn").instantiate()
	force.planet_path = NodePath("../../Planet")
	air_container.add_child(force)
	root.add_child(level)
	var sandbox = level.get_node("Sandbox")
	sandbox.set_physics_process(false)
	sandbox.manually_paused = false
	var air_battle = sandbox.combat
	check(air_battle.air_forces.has(force) and force.valid and not force.triggered, "战斗发现独立空军并未触发")
	var path: PackedVector2Array = force.sample_path(64)
	var midpoint: Vector2 = path[path.size() / 2]
	audio.name = "OriginalAudioManager"
	var launch_spy := LaunchAudioSpy.new()
	launch_spy.name = "AudioManager"
	root.add_child(launch_spy)
	air_battle._advance_air_forces(0.1, midpoint + Vector2(100000, 100000), midpoint + Vector2(100000, 100000))
	check(not force.triggered and launch_spy.launches == 0, "远离航线不播放出动音效")
	air_battle._advance_air_forces(0.1, midpoint + Vector2(0, 500), midpoint + Vector2(0, -500))
	check(force.triggered and force.elapsed > 0.0 and launch_spy.launches == 1, "玩家扫掠穿过航线触发一次出动音效")
	air_battle._advance_air_forces(0.1, midpoint, midpoint)
	check(launch_spy.launches == 1, "已出动的空军不重复播放出动音效")
	air_battle.reset_battle()
	check(not force.triggered and launch_spy.launches == 1, "战斗重置不播放出动音效")
	air_battle._advance_air_forces(0.1, midpoint, midpoint)
	check(force.triggered and launch_spy.launches == 2, "重置后再次出动播放一次音效")
	launch_spy.free()
	audio.name = "AudioManager"
	force.reset_force()
	force.triggered = true
	paused = false
	air_battle.dead = false
	sandbox.manually_paused = false
	air_battle._update_air_raid_warning()
	check(air_battle.hud.get_node("AirRaidWarning").visible and audio.is_air_raid_requested(), "来袭期间独立警报：visible=%s audio=%s paused=%s edit=%s motion=%s" % [air_battle.hud.get_node("AirRaidWarning").visible, audio.is_air_raid_requested(), paused, sandbox.is_orbit_editing(), sandbox.motion_mode])
	audio.set_enemy_locked(true)
	air_battle._set_air_raid_audio(false)
	check(audio.is_enemy_locked_requested(), "关闭空军警报不影响敌方锁定")
	sandbox.manually_paused = true
	air_battle._update_air_raid_warning()
	check(not audio.is_air_raid_requested() and not air_battle.hud.get_node("AirRaidWarning").visible, "暂停隐藏来袭警报")
	sandbox.manually_paused = false
	air_battle._update_air_raid_warning()
	check(audio.is_air_raid_requested(), "恢复后继续来袭警报")
	force.reset_force()
	force.triggered = true
	var member_pos: Vector2 = force.members[0].current
	for i in range(1, force.members.size()):
		force.damage_member(i, 1000.0)
	air_battle.weapon_slots[0].id = "point_defense"
	air_battle.weapon_slots[0].active = true
	air_battle.weapon_slots[0].remaining = 1.0
	var air_hp: float = air_battle.player_health
	air_battle._advance_air_forces(0.1, member_pos, member_pos)
	check(not force.members[0].alive and air_battle.player_health == air_hp, "近防优先拦截空军成员")
	air_battle._update_air_raid_warning()
	check(not audio.is_air_raid_requested(), "全灭后停止来袭警报")
	force.reset_force()
	force.triggered = true
	member_pos = force.members[0].current
	for i in range(1, force.members.size()):
		force.damage_member(i, 1000.0)
	air_battle.weapon_slots[0].active = false
	air_battle._advance_air_forces(0.1, member_pos, member_pos)
	check(not force.members[0].alive and air_battle.player_health == air_hp - float(force.config.collision_damage), "空军碰撞独立结算伤害")
	force.reset_force()
	force.triggered = true
	for i in range(1, force.members.size()):
		force.damage_member(i, 1000.0)
	member_pos = force.members[0].current
	air_battle.weapon_slots[0].active = true
	air_battle.weapon_slots[0].remaining = 0.01
	air_battle._advance_air_forces(1.0, member_pos + Vector2(100, 0), member_pos)
	check(force.members[0].alive == false and air_battle.player_health == air_hp - 2.0 * float(force.config.collision_damage), "近防末帧仅在剩余时长内拦截")
	force.reset_force()
	force.triggered = true
	for i in range(1, force.members.size()):
		force.damage_member(i, 1000.0)
	force.advance(float(force.config.duration_sim_s) - 0.1)
	var endpoint: Vector2 = force.to_global(force.point_at(1.0))
	air_battle.weapon_slots[0].active = false
	var before_final_hit: float = air_battle.player_health
	air_battle._advance_air_forces(0.2, endpoint, endpoint)
	check(force.elapsed >= float(force.config.duration_sim_s) and not force.members[0].alive and air_battle.player_health == before_final_hit - float(force.config.collision_damage), "终点子步仍结算碰撞")
	force.reset_force()
	force.triggered = true
	for i in range(1, force.members.size()):
		force.damage_member(i, 1000.0)
	force.advance(float(force.config.duration_sim_s) - 0.1)
	air_battle.weapon_slots[0].active = true
	air_battle.weapon_slots[0].remaining = 1.0
	var before_final_defense: float = air_battle.player_health
	air_battle._advance_air_forces(0.2, endpoint, endpoint)
	check(force.elapsed >= float(force.config.duration_sim_s) and not force.members[0].alive and air_battle.player_health == before_final_defense, "终点子步近防先于碰撞")
	sandbox.reset()
	check(not force.triggered and force.members[0].alive, "重置恢复空军")
	level.free()
	scene.reset()
	scene.manually_paused = false
	battle.weapon_slots[0].id = "carrier"
	check(Loadout.VALID_IDS.has("carrier") and battle.config.weapons.carrier.name == "舰载机", "舰载机装备与名称")
	var carrier_audio: AudioStreamPlayer = root.get_node("AudioManager")._carrier_launch_player
	carrier_audio.stop()
	var initial_focus: int = scene.focus_index
	scene.focus_index = -1
	battle.fire_slot(0)
	check(not carrier_audio.playing and battle.carrier_squadrons.is_empty(), "无焦点发射失败不播放音效")
	scene.focus_index = initial_focus
	scene.manually_paused = true
	battle.fire_slot(0)
	check(not carrier_audio.playing and battle.carrier_squadrons.is_empty(), "手动暂停不发射或播放音效")
	scene.manually_paused = false
	paused = true
	battle.fire_slot(0)
	check(not carrier_audio.playing and battle.carrier_squadrons.is_empty(), "场景树暂停不发射或播放音效")
	paused = false
	battle.fire_slot(0)
	check(battle.carrier_squadrons.size() == 2 and battle.weapon_slots[0].cooldown > 0.0 and carrier_audio.playing, "释放两组编队并进入冷却，只播放一次音效")
	carrier_audio.stop()
	battle.fire_slot(0)
	check(not carrier_audio.playing and battle.carrier_squadrons.size() == 2, "冷却期间不发射或播放音效")
	var left = battle.carrier_squadrons[0]
	var right = battle.carrier_squadrons[1]
	check(left.members.size() == 9 and right.members.size() == 9 and left.direction == -right.direction, "双编队各九机反向公转")
	var before_paused_elapsed: float = left.elapsed
	scene.manually_paused = true
	scene._physics_process(1.0)
	check(left.elapsed == before_paused_elapsed, "暂停冻结舰载机运动")
	scene.manually_paused = false
	var origin: Vector2 = scene.ship.global_position
	var center: Vector2 = left.center
	var previous_positions := {}
	for carrier_enemy in battle.enemies:
		previous_positions[carrier_enemy.node.get_instance_id()] = carrier_enemy.node.position
	battle.enemies.clear()
	for phase in range(3):
		for squadron in [left, right]:
			squadron.advance(10.0, origin)
			squadron.advance(0.01, origin)
			squadron._process(0.0)
			var leader: Dictionary = squadron.members[0]
			var velocity: Vector2 = (leader.current - leader.previous).normalized()
			for member in squadron.members:
				var movement: Vector2 = (member.current - member.previous).normalized()
				var body: Node2D = member.node.get_node("Body")
				var nose := Vector2.RIGHT.rotated(body.global_rotation)
				var trail: Line2D = member.node.get_node("Trail")
				var tail: Vector2 = trail.to_global(trail.get_point_position(0)) - member.node.global_position
				check(nose.dot(movement) > 0.999 and tail.dot(movement) < 0.0, "舰载机机首和尾迹跟随实际运动 phase=%d dir=%s movement=%s nose=%s tail=%s elapsed=%s radius=%s" % [phase, squadron.direction, movement, nose, tail, squadron.elapsed, squadron.radius])
				if member != leader:
					check((leader.current - member.current).dot(velocity) > 0.0, "舰载机队首领先 phase=%d dir=%s" % [phase, squadron.direction])
	battle._clear_carrier_squadrons()
	battle._launch_carrier_squadrons()
	left = battle.carrier_squadrons[0]
	right = battle.carrier_squadrons[1]
	battle._advance_carrier_squadrons(1.0, previous_positions)
	check(preload("res://scripts/kepler_orbit.gd").residual(left.orbit, left.position_world - center) < 0.0001 and left.position_world.distance_to(right.position_world) > 0.1, "沿母舰轨道反向公转")
	var orbit_duration: float = left.orbit_duration
	scene.ship.global_position = origin + Vector2(50, 0)
	battle._advance_carrier_squadrons(orbit_duration - 1.0, previous_positions)
	check(left.returning and right.returning and left.position_world.distance_to(origin) < 0.01, "完成一圈后转为返航")
	scene.ship.global_position = origin + Vector2(50, 0)
	battle._advance_carrier_squadrons(1.0, previous_positions)
	for squadron in [left, right]:
		squadron._process(0.0)
		var heading: Vector2 = (scene.ship.global_position - squadron.position_world).normalized()
		var leader: Dictionary = squadron.members[0]
		for member in squadron.members:
			var body: Node2D = member.node.get_node("Body")
			var trail: Line2D = member.node.get_node("Trail")
			check(Vector2.RIGHT.rotated(body.global_rotation).dot(heading) > 0.999 and (trail.to_global(trail.get_point_position(0)) - member.node.global_position).dot(heading) < 0.0, "返航机首尾迹朝向正确")
			if member != leader:
				check((leader.current - member.current).dot(heading) > 0.0, "返航队首领先")
	check(left.position_world.distance_to(scene.ship.global_position) < 50.0 and left.modulate.a < 1.0, "返航追随玩家并淡出 distance=%s alpha=%s" % [left.position_world.distance_to(scene.ship.global_position), left.modulate.a])
	battle._advance_carrier_squadrons(20.0, previous_positions)
	check(battle.carrier_squadrons.is_empty(), "返航到玩家后回收")
	scene.reset()
	battle.weapon_slots[0].id = "carrier"
	battle.fire_slot(0)
	left = battle.carrier_squadrons[0]
	var target_enemy: Dictionary = battle.enemies[0]
	target_enemy.node.global_position = left.members[0].current
	var before_carrier_damage: float = target_enemy.health
	battle._advance_carrier_squadrons(0.01, {target_enemy.node.get_instance_id(): target_enemy.node.position})
	check(target_enemy.health < before_carrier_damage and left.members[0].alive and left.members[0].node.visible, "公转成员命中敌船但不消失")
	var after_carrier_damage: float = target_enemy.health
	battle._advance_carrier_squadrons(0.01, {target_enemy.node.get_instance_id(): target_enemy.node.position})
	check(target_enemy.health == after_carrier_damage, "同成员对同敌船仅造成一次伤害")
	left.returning = true
	left.position_world = target_enemy.node.global_position
	battle._advance_carrier_squadrons(0.01, {target_enemy.node.get_instance_id(): target_enemy.node.position})
	check(target_enemy.health == after_carrier_damage, "返航阶段不伤害敌船")
	scene.reset()
	check(battle.carrier_squadrons.is_empty(), "重置清除舰载机")
	var saved_focus: int = scene.focus_index
	scene.focus_index = -1
	check(not battle._launch_carrier_squadrons() and battle.carrier_squadrons.is_empty() and not scene.feedback.text.is_empty(), "没有焦点时拒绝释放并提示")
	scene.focus_index = saved_focus
	if scene.bodies.size() > 1:
		scene.focus_index = 1
		scene.ship.position = scene.focus_center() + Vector2(200, 0)
		check(battle._launch_carrier_squadrons() and battle.carrier_squadrons[0].center.is_equal_approx(scene.ship.get_parent().to_global(scene.focus_center())) and absf(battle.carrier_squadrons[0].radius - 200.0) < 0.001, "舰载机围绕第二行星焦点发射")
		battle._clear_carrier_squadrons()
		scene.focus_index = saved_focus
	scene.reset()
	scene.manually_paused = false
	battle.enemy_fire_enabled = true
	var carrier_enemy: Dictionary = battle.enemies[0]
	carrier_enemy.weapon = "carrier"
	carrier_enemy.cooldown = 1.0
	carrier_enemy.carrier_cooldown = 4.0
	battle.advance_cooldowns(0.1)
	check(carrier_enemy.node.get_node("Health").text.contains("3.9"), "航母显示自身舰载机冷却而非导弹冷却")
	carrier_enemy.node.position = scene.ship.position.rotated(0.5)
	check(battle._launch_enemy_carrier(carrier_enemy.node), "同天体相近高度可发射敌方舰载机")
	check(battle.carrier_squadrons.size() == 2 and battle.carrier_squadrons[0].team == "enemy" and battle.carrier_squadrons[0].members.size() == 9, "敌方发射两队各九架")
	var enemy_squad = battle.carrier_squadrons[0]
	battle._launch_carrier_squadrons()
	var defense_player = battle.carrier_squadrons[2]
	battle.enemy_fire_enabled = false
	battle.weapon_slots[0].id = "point_defense"
	battle.weapon_slots[0].active = true
	battle.weapon_slots[0].remaining = 10.0
	var near_player: Vector2 = scene.ship.global_position
	for member in enemy_squad.members:
		member.current = near_player
		member.node.global_position = near_player
	for member in defense_player.members:
		member.current = near_player
		member.node.global_position = near_player
	scene.manually_paused = true
	battle.advance(0.01, scene.ship.position)
	check(enemy_squad.members[0].alive, "暂停时近防不拦截舰载机")
	scene.manually_paused = false
	battle.advance(0.01, scene.ship.position)
	check(not enemy_squad.members[0].alive and not battle.carrier_squadrons.has(enemy_squad), "近防逐机拦截并清理敌编队")
	check(defense_player.members[0].alive, "近防不拦截友方舰载机")
	battle._clear_carrier_squadrons()
	battle._launch_enemy_carrier(carrier_enemy.node)
	enemy_squad = battle.carrier_squadrons[0]
	battle._launch_carrier_squadrons()
	defense_player = battle.carrier_squadrons[2]
	battle._start_dogfight(defense_player, enemy_squad, near_player)
	for member in enemy_squad.members:
		member.current = near_player
		member.node.global_position = near_player
	battle.advance(0.01, scene.ship.position)
	check(not battle.carrier_squadrons.has(enemy_squad) and defense_player.dogfight == null and battle.dogfights.is_empty(), "狗斗中拦截敌机后解除狗斗")
	battle._clear_carrier_squadrons()
	battle._launch_enemy_carrier(carrier_enemy.node)
	enemy_squad = battle.carrier_squadrons[0]
	var lure = preload("res://scenes/decoy_satellite.tscn").instantiate()
	battle.add_child(lure)
	lure.initialize(near_player + Vector2(40, 0), Vector2.ZERO, Vector2.ZERO, 100000.0, "player", {"attraction_radius_km": 100.0, "radius_km": 0.01})
	battle.decoy_satellites.append(lure)
	for member in enemy_squad.members:
		member.current = near_player
		member.node.global_position = near_player
		member.decoy = lure
	battle.advance(0.01, scene.ship.position)
	check(not enemy_squad.members[0].alive and is_instance_valid(lure), "近防可拦截追逐诱饵的敌机且不摧毁卫星")
	battle.decoy_satellites.erase(lure)
	lure.queue_free()
	battle._clear_carrier_squadrons()
	var saved_defense_range: float = battle.config.point_defense.range_km
	battle.config.point_defense.range_km = 25.0
	var bend_segments: Array[Dictionary] = [{"start": Vector2(-40, 50), "end": Vector2(0, 50), "t0": 0.0, "t1": 0.5}, {"start": Vector2(0, 50), "end": Vector2(40, 0), "t0": 0.5, "t1": 1.0}]
	check(is_inf(battle._carrier_defense_time(enemy_squad, bend_segments, Vector2.ZERO, Vector2.ZERO, 1.0, 1.0)), "受诱折线不以首尾弦误判近防命中")
	for defense_radius in [30.0, 5.0]:
		battle._launch_enemy_carrier(carrier_enemy.node)
		enemy_squad = battle.carrier_squadrons[0]
		battle._launch_carrier_squadrons()
		defense_player = battle.carrier_squadrons[2]
		battle._start_dogfight(defense_player, enemy_squad, near_player + Vector2(500, 0))
		var moving_lure = preload("res://scenes/decoy_satellite.tscn").instantiate()
		battle.add_child(moving_lure)
		moving_lure.initialize(near_player, Vector2.ZERO, Vector2.ZERO, 0.000001, "player", {"attraction_radius_km": 100.0, "radius_km": 10.0})
		battle.decoy_satellites.append(moving_lure)
		for i in range(enemy_squad.members.size()):
			var member: Dictionary = enemy_squad.members[i]
			member.alive = i == 0
			member.current = near_player + Vector2(40, 0)
			member.node.global_position = member.current
			member.decoy = moving_lure
		battle.config.point_defense.range_km = defense_radius
		battle.weapon_slots[0].active = true
		battle.weapon_slots[0].remaining = 10.0
		battle.advance(10.0, scene.ship.position)
		check(not enemy_squad.members[0].alive and enemy_squad.members[0].has("defense_hit_time") == (defense_radius > 10.0), "近防和诱饵撞毁按首次事件时刻结算")
		battle.decoy_satellites.erase(moving_lure)
		moving_lure.queue_free()
		battle._clear_carrier_squadrons()
	battle.config.point_defense.range_km = saved_defense_range
	for defense_remaining in [0.25, 1.0]:
		battle._launch_enemy_carrier(carrier_enemy.node)
		enemy_squad = battle.carrier_squadrons[0]
		battle._launch_carrier_squadrons()
		defense_player = battle.carrier_squadrons[2]
		battle._start_dogfight(defense_player, enemy_squad, near_player + Vector2(500, 0))
		for i in range(enemy_squad.members.size()):
			var member: Dictionary = enemy_squad.members[i]
			member.alive = i == 0
			member.current = near_player + Vector2(100, 0)
			member.node.global_position = member.current
		var defense_range: float = battle.config.point_defense.range_km
		var old_position: Vector2 = scene.ship.position
		scene.ship.position += Vector2(100, 0)
		battle.weapon_slots[0].active = true
		battle.weapon_slots[0].remaining = defense_remaining
		battle.advance(1.0, old_position)
		if defense_range < 75.0:
			check(enemy_squad.members[0].alive == (defense_remaining < 1.0), "玩家移动相对扫掠尊重近防到期时间")
		scene.ship.position = old_position
		battle._clear_carrier_squadrons()
	battle.weapon_slots[0].active = false
	battle.enemy_fire_enabled = true
	battle._launch_enemy_carrier(carrier_enemy.node)
	enemy_squad = battle.carrier_squadrons[0]
	battle._launch_carrier_squadrons()
	var player_squad = battle.carrier_squadrons[2]
	battle._start_dogfight(player_squad, enemy_squad)
	var old_probability: float = battle.config.carrier.dogfight_loss_probability
	battle.config.carrier.dogfight_loss_probability = 1.0
	scene.manually_paused = true
	battle.advance_cooldowns(3.0)
	check(not battle.dogfights.is_empty() and battle.dogfights[0].elapsed == 0.0, "暂停冻结狗斗现实计时")
	scene.manually_paused = false
	battle.advance_cooldowns(2.0)
	check(battle.dogfights.is_empty() and player_squad.dogfight == null and enemy_squad.dogfight == null, "两现实秒后结束狗斗")
	for squadron in [player_squad, enemy_squad]:
		var survivors: int = squadron.members.filter(func(member): return member.alive).size()
		check(survivors >= 6 and survivors <= 8, "狗斗每方损失一至三架")
	battle.config.carrier.dogfight_loss_probability = old_probability
	carrier_enemy.node.position = scene.ship.position * 2.0
	check(not battle._launch_enemy_carrier(carrier_enemy.node), "轨道高度差过大不能发射")
	battle._clear_carrier_squadrons()
	scene.velocity = Vector2.ZERO
	carrier_enemy.velocity = Vector2.ZERO
	carrier_enemy.node.position = scene.ship.position
	battle._launch_enemy_carrier(carrier_enemy.node)
	battle._launch_carrier_squadrons()
	enemy_squad = battle.carrier_squadrons[0]
	player_squad = battle.carrier_squadrons[2]
	battle._clear_squadron(battle.carrier_squadrons[3])
	battle._clear_squadron(battle.carrier_squadrons[1])
	var old_range: float = battle.config.carrier.dogfight_range_km
	battle.config.carrier.dogfight_range_km = 0.01
	var speed: float = float(battle.config.carrier.orbit_speed_km_s)
	var duration: float = TAU * enemy_squad.radius / speed
	enemy_squad.elapsed = duration - 0.1
	enemy_squad.start_angle = -enemy_squad.direction * TAU * enemy_squad.elapsed / duration
	player_squad.start_angle = enemy_squad.direction * speed * 1.1 / enemy_squad.radius
	enemy_squad.orbit.angle = enemy_squad.start_angle
	player_squad.orbit.angle = player_squad.start_angle
	for squadron in [enemy_squad, player_squad]:
		squadron.position_world = squadron.center + Vector2.from_angle(0.0 if squadron == enemy_squad else player_squad.start_angle) * squadron.radius
		for member in squadron.members:
			member.offset = Vector2.ZERO
			squadron._update_member(member, squadron.position_world, Vector2.RIGHT)
			member.previous = member.current
	# 两段轨迹末点重合，但敌方在 0.1 秒已结束公转，不能与 1 秒时刻比较。
	battle._advance_carrier_squadrons(1.0, {})
	check(battle.dogfights.is_empty(), "一方中途结束公转后不能与另一方不同时刻误判相遇")
	battle._clear_carrier_squadrons()
	battle._launch_enemy_carrier(carrier_enemy.node)
	battle._launch_carrier_squadrons()
	enemy_squad = battle.carrier_squadrons[0]
	player_squad = battle.carrier_squadrons[3]
	battle._clear_squadron(battle.carrier_squadrons[2])
	battle._clear_squadron(battle.carrier_squadrons[1])
	duration = TAU * enemy_squad.radius / speed
	enemy_squad.elapsed = duration - 0.1
	enemy_squad.start_angle = -enemy_squad.direction * TAU * enemy_squad.elapsed / duration
	player_squad.start_angle = enemy_squad.direction * speed * 0.1 / enemy_squad.radius
	enemy_squad.orbit.angle = enemy_squad.start_angle
	player_squad.orbit.angle = player_squad.start_angle
	for squadron in [enemy_squad, player_squad]:
		squadron.position_world = squadron.center + Vector2.from_angle(0.0 if squadron == enemy_squad else player_squad.start_angle) * squadron.radius
		for member in squadron.members:
			member.offset = Vector2.ZERO
			squadron._update_member(member, squadron.position_world, Vector2.RIGHT)
			member.previous = member.current
	battle._advance_carrier_squadrons(1.0, {})
	check(battle.dogfights.size() == 1, "一队中途结束时共同公转区间内真实相遇触发狗斗")
	if not battle.dogfights.is_empty():
		check(not enemy_squad.returning and enemy_squad.elapsed < duration and player_squad.elapsed < 0.1, "相遇时回退两队轨道进度并保留剩余航程")
		check(battle.dogfights[0].center.distance_to(enemy_squad.position_world) < 0.1 and battle.dogfights[0].center.distance_to(player_squad.position_world) < 0.1, "狗斗中心位于实际相遇位置")
		var paused_elapsed: float = enemy_squad.elapsed
		battle.advance_cooldowns(2.0)
		check(is_equal_approx(enemy_squad.elapsed, paused_elapsed) and not enemy_squad.returning, "狗斗结束后保留相遇时公转进度")
		battle._advance_carrier_squadrons(0.2, {})
		check(enemy_squad.returning, "恢复后继续剩余轨道再返航")
	battle._clear_carrier_squadrons()
	var old_carrier_radius: float = battle.config.carrier.radius_km
	var old_enemy_radius: float = carrier_enemy.config.radius_km
	var old_player_radius: float = battle.config.player.hit_radius_km
	battle.config.carrier.radius_km = 0.5
	carrier_enemy.config.radius_km = 0.5
	battle.config.player.hit_radius_km = 0.5
	battle.config.carrier.dogfight_range_km = 0.1
	for reverse_order in [false, true]:
		for target_after in [false, true]:
			scene.ship.position = scene.focus_center() + Vector2(200, 0)
			carrier_enemy.node.position = scene.ship.position
			carrier_enemy.health = 1000.0
			battle.player_health = 1000.0
			battle._launch_enemy_carrier(carrier_enemy.node)
			battle._launch_carrier_squadrons()
			enemy_squad = battle.carrier_squadrons[0]
			player_squad = battle.carrier_squadrons[3]
			battle._clear_squadron(battle.carrier_squadrons[2])
			battle._clear_squadron(battle.carrier_squadrons[1])
			player_squad.start_angle = -0.15
			enemy_squad.orbit.angle = 0.0
			player_squad.orbit.angle = player_squad.start_angle
			for squadron in [enemy_squad, player_squad]:
				squadron.position_world = squadron.center + Vector2.from_angle(0.0 if squadron == enemy_squad else player_squad.start_angle) * squadron.radius
				for i in range(squadron.members.size()):
					var member: Dictionary = squadron.members[i]
					member.alive = i == 0
					member.offset = Vector2.ZERO
					squadron._update_member(member, squadron.position_world, Vector2.RIGHT)
					member.previous = member.current
			var target_time := 5.0 if target_after else 1.0
			var enemy_target: Vector2 = player_squad.center + Vector2.from_angle(player_squad.start_angle + player_squad.direction * speed * target_time / player_squad.radius) * player_squad.radius
			var player_target: Vector2 = enemy_squad.center + Vector2.from_angle(enemy_squad.start_angle + enemy_squad.direction * speed * target_time / enemy_squad.radius) * enemy_squad.radius
			carrier_enemy.node.global_position = enemy_target
			scene.ship.global_position = player_target
			if reverse_order:
				battle.carrier_squadrons.reverse()
			battle._advance_carrier_squadrons(6.0, {})
			check(battle.dogfights.size() == 1, "伤害时序场景自动相遇")
			check((carrier_enemy.health < 1000.0) == not target_after and (battle.player_health < 1000.0) == not target_after, "相遇前后双方舰船伤害且与队列顺序无关")
			battle._clear_carrier_squadrons()
	# 两个敌队先后相遇：即使较晚的排在前面，也必须选择较早者。
	scene.ship.position = scene.focus_center() + Vector2(200, 0)
	carrier_enemy.node.position = scene.ship.position
	battle._launch_enemy_carrier(carrier_enemy.node)
	battle._launch_carrier_squadrons()
	var late_squad = battle.carrier_squadrons[0]
	var early_squad = battle.carrier_squadrons[1]
	player_squad = battle.carrier_squadrons[3]
	battle._clear_squadron(battle.carrier_squadrons[2])
	for squadron in [late_squad, early_squad, player_squad]:
		squadron.start_angle = 0.0 if squadron == player_squad else (0.20 if squadron == late_squad else 0.10)
		squadron.orbit.angle = squadron.start_angle
		squadron.direction = -1.0 if squadron != player_squad else 1.0
		squadron.position_world = squadron.center + Vector2.from_angle(squadron.start_angle) * squadron.radius
		for i in range(squadron.members.size()):
			var member: Dictionary = squadron.members[i]
			member.alive = i == 0
			member.offset = Vector2.ZERO
			squadron._update_member(member, squadron.position_world, Vector2.RIGHT)
			member.previous = member.current
	battle._advance_carrier_squadrons(5.0, {})
	check(player_squad.dogfight != null and early_squad.dogfight == player_squad.dogfight and late_squad.dogfight == null, "多个对手选择最早遭遇而非数组首个")
	battle._clear_carrier_squadrons()
	# 敌方母舰被击毁后立即解除狗斗、移除其编队。
	scene.ship.position = scene.focus_center() + Vector2(200, 0)
	carrier_enemy.node.position = scene.ship.position
	carrier_enemy.health = 1.0
	battle._launch_enemy_carrier(carrier_enemy.node)
	battle._launch_carrier_squadrons()
	enemy_squad = battle.carrier_squadrons[0]
	player_squad = battle.carrier_squadrons[2]
	battle._start_dogfight(enemy_squad, player_squad)
	battle._advance_carrier_squadrons(0.01, {})
	# 另一个玩家编队在起点击中敌母舰。
	check(not carrier_enemy.node.visible and not battle.carrier_squadrons.has(enemy_squad) and battle.dogfights.is_empty() and player_squad.dogfight == null, "母舰击毁时立即清理敌编队和狗斗")
	battle._clear_carrier_squadrons()
	scene.reset()
	scene.manually_paused = false
	carrier_enemy = battle.enemies[0]
	carrier_enemy.node.position = scene.ship.position
	battle._launch_enemy_carrier(carrier_enemy.node)
	battle._launch_carrier_squadrons()
	enemy_squad = battle.carrier_squadrons[0]
	player_squad = battle.carrier_squadrons[2]
	battle._start_dogfight(enemy_squad, player_squad)
	battle.damage_target(carrier_enemy.node, carrier_enemy.health + 1.0)
	check(not battle.carrier_squadrons.has(enemy_squad) and battle.dogfights.is_empty() and player_squad.dogfight == null, "公共伤害销毁母舰即清理编队和狗斗，无需推进下一子步")
	battle._clear_carrier_squadrons()
	scene.reset()
	scene.manually_paused = false
	carrier_enemy = battle.enemies[0]
	carrier_enemy.node.position = scene.ship.position
	battle._launch_enemy_carrier(carrier_enemy.node)
	battle._launch_carrier_squadrons()
	battle.player_health = 1.0
	carrier_enemy.health = 1000.0
	battle._advance_carrier_squadrons(0.01, {})
	check(battle.dead and battle.carrier_squadrons.is_empty() and carrier_enemy.health == 1000.0, "玩家死亡后立即停止后续编队伤害")
	battle.config.carrier.radius_km = old_carrier_radius
	carrier_enemy.config.radius_km = old_enemy_radius
	battle.config.player.hit_radius_km = old_player_radius
	battle.config.carrier.dogfight_range_km = old_range
	print("COMBAT_TESTS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
