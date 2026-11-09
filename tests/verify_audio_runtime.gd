extends SceneTree
## 音效运行时验证：实际播放状态、战斗锁定接线、暂停淡出。

var checks: int = 0
var failures: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var manager: Node = root.get_node_or_null("AudioManager")
	check(manager != null, "AudioManager 存在")
	if manager == null:
		print("AUDIO_RUNTIME checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	# 1. 警报真正进入播放状态
	manager.set_enemy_locked(true)
	manager._process(0.4)
	check(manager._locked_player.playing, "锁定警报进入播放状态")
	check(manager._lock_gain > 0.99, "警报音量已淡入到满值")
	check(manager.is_enemy_locked_audible(), "is_enemy_locked_audible 为真")
	# 2. 解除后停止
	manager.set_enemy_locked(false)
	manager._process(0.4)
	check(not manager._locked_player.playing, "解除锁定后警报停止")
	# 3. 战斗接线
	var level: Node = load("res://scenes/level_4.tscn").instantiate()
	root.add_child(level)
	await process_frame
	for i in range(level.config.tutorial.size()):
		level._show_page(i)
	level._start_level()
	level.sandbox.set_physics_process(false)
	var combat: Node = level.sandbox.combat
	check(combat.enemies.size() > 0, "第四关存在敌机")
	if combat.enemies.size() > 0:
		combat.enemies[0].locked = true
		combat._sync_lock_audio()
		check(manager.is_enemy_locked_requested(), "敌机 locked 为真时触发警报")
		combat.enemies[0].locked = false
		combat._sync_lock_audio()
		check(not manager.is_enemy_locked_requested(), "敌机失去锁定时解除警报")
	# 玩家锁定敌机（selected）不应触发警报
	combat.selected = combat.enemies[0].node if combat.enemies.size() > 0 else null
	combat._sync_lock_audio()
	check(not manager.is_enemy_locked_requested(), "玩家锁定敌机不触发警报")
	# 4. 暂停淡出
	manager.set_enemy_locked(true)
	manager._process(0.4)
	paused = true
	manager._process(0.5)
	check(not manager._locked_player.playing, "暂停时警报停止")
	paused = false
	manager.set_enemy_locked(false)
	# 5. 死亡时停止
	combat.damage_player(999.0)
	check(not manager.is_enemy_locked_requested(), "玩家死亡后不再请求警报")
	level.queue_free()
	await process_frame
	await process_frame
	# 6. 关卡背景音乐接线：开始关卡播放，返回主菜单停止
	manager.stop_level_music()
	var level5: Node = load("res://scenes/level_5.tscn").instantiate()
	root.add_child(level5)
	await process_frame
	check(not manager.is_level_music_playing(), "教学期间背景音乐尚未开始")
	for i in range(level5.config.tutorial.size()):
		level5._show_page(i)
	level5._start_level()
	check(manager.is_level_music_playing(), "开始关卡后背景音乐播放")
	level5._return_menu()
	check(not manager.is_level_music_playing(), "返回主菜单后背景音乐停止")
	print("AUDIO_RUNTIME checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
