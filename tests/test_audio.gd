extends SceneTree
## 音效系统回归：资源、循环导入、悬停节流、锁定状态机、暂停淡出、设置持久化。

const AUDIO := preload("res://scripts/audio_manager.gd")
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
	check(manager != null, "AudioManager 作为 Autoload 挂载")
	if manager == null:
		print("AUDIO_TESTS checks=%d failures=%d" % [checks, failures])
		quit(1)
		return
	check(ResourceLoader.exists("res://audio/ui_hover.mp3"), "悬停音效资源存在")
	check(ResourceLoader.exists("res://audio/enemy_locked.wav"), "锁定音效资源存在")
	var hover: AudioStream = load("res://audio/ui_hover.mp3") if ResourceLoader.exists("res://audio/ui_hover.mp3") else null
	check(hover != null, "悬停音效可加载")
	var locked: AudioStream = load("res://audio/enemy_locked.wav") if ResourceLoader.exists("res://audio/enemy_locked.wav") else null
	check(locked is AudioStreamWAV, "锁定音效为 WAV 流")
	check(manager.is_enemy_locked_looping(), "锁定音效运行时已设为循环")
	check(AudioServer.get_bus_index("AudioUI") != -1, "UI 总线已创建")
	check(AudioServer.get_bus_index("AudioSFX") != -1, "SFX 总线已创建")
	check(AudioServer.get_bus_index("AudioMusic") != -1, "音乐总线已创建")
	check(ResourceLoader.exists("res://audio/level_music.mp3"), "背景音乐资源存在")
	check(manager._music_player != null, "背景音乐播放器已创建")
	check(manager._music_player.stream != null, "背景音乐可加载")
	check(manager._missile_stream is AudioStreamMP3, "导弹发射音效可加载")
	check(manager._carrier_launch_player != null and manager._carrier_launch_player.stream is AudioStreamMP3 and not manager._carrier_launch_player.stream.loop and manager._carrier_launch_player.bus == "AudioSFX", "舰载机音效已导入并使用 SFX 总线且不循环")
	manager.play_carrier_launch()
	check(manager._carrier_launch_player.playing, "舰载机音效开始播放")
	manager._carrier_launch_player.stop()
	manager.play_carrier_launch()
	check(manager._carrier_launch_player.playing, "舰载机音效可以再次播放")
	manager._carrier_launch_player.stop()
	manager.set_muted(true)
	manager.play_carrier_launch()
	check(not manager._carrier_launch_player.playing, "静音时舰载机音效不播放")
	manager.set_muted(false)
	paused = true
	manager.play_carrier_launch()
	check(not manager._carrier_launch_player.playing, "暂停时舰载机音效不播放")
	paused = false
	check(manager._complete_player != null and manager._complete_player.stream is AudioStreamWAV and manager._complete_player.stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "通关音效已导入且不循环")
	check(manager._complete_player.bus == "AudioSFX", "通关音效使用 SFX 总线")
	manager.play_level_complete()
	check(manager._complete_player.playing, "通关音效开始播放")
	manager._complete_player.stop()
	manager.set_muted(true)
	manager.play_level_complete()
	check(not manager._complete_player.playing, "静音时通关音效不播放")
	manager.set_muted(false)
	manager.play_missile_launch()
	manager.play_missile_launch()
	var missile_players: Array[Node] = []
	for child in manager.get_children():
		if child is AudioStreamPlayer and child.stream == manager._missile_stream:
			missile_players.append(child)
	check(missile_players.size() == 2, "连续发射音效可重叠")
	for player in missile_players:
		check(player.playing and player.bus == "AudioSFX", "发射音效播放并使用 SFX 总线")
	manager.set_muted(true)
	var count: int = manager.get_child_count()
	manager.play_missile_launch()
	check(manager.get_child_count() == count and AudioServer.is_bus_mute(0), "静音时不触发发射音效且总线静音")
	manager.set_muted(false)
	for player in missile_players:
		player.free()

	OS.delay_msec(80)
	manager._hover_last_ms = 0
	var before: int = manager.hover_play_count()
	manager.play_ui_hover()
	manager.play_ui_hover()
	check(manager.hover_play_count() == before + 1, "同一间隔内重复悬停只触发一次")
	OS.delay_msec(80)
	manager.play_ui_hover()
	check(manager.hover_play_count() == before + 2, "超过最小间隔后可再次触发")

	manager.set_enemy_locked(true)
	check(manager.is_enemy_locked_requested(), "敌机锁定时请求警报")
	manager.set_enemy_locked(true)
	check(manager.is_enemy_locked_requested(), "重复锁定请求保持稳定")
	manager.set_enemy_locked(false)
	check(not manager.is_enemy_locked_requested(), "失去锁定后解除警报")

	manager.set_enemy_locked(true)
	manager._lock_gain = 1.0
	paused = true
	manager._process(0.5)
	check(manager._lock_gain < 0.001, "场景树暂停时警报淡出")
	paused = false
	manager.set_enemy_locked(false)

	check(manager._air_raid_player.stream is AudioStreamMP3 and manager._air_raid_player.stream.loop, "空袭锁定使用独立循环 MP3")
	check(manager._air_launch_player.stream is AudioStreamMP3 and not manager._air_launch_player.stream.loop, "空军出动使用非循环 MP3")
	check(manager._air_raid_player.bus == "AudioSFX" and manager._air_launch_player.bus == "AudioSFX", "空军音效使用 SFX 总线")
	manager.set_air_raid(true)
	manager.set_enemy_locked(true)
	manager._process(0.5)
	check(manager._air_raid_player.playing and manager.is_enemy_locked_audible(), "空袭和普通锁定警报可以同时播放")
	manager.set_air_raid(false)
	manager._process(0.5)
	check(not manager._air_raid_player.playing and manager.is_enemy_locked_audible(), "空袭解除不影响普通锁定")
	manager.set_air_raid(true)
	manager.play_air_force_launch()
	check(manager._air_launch_player.playing and not manager._air_raid_player.playing, "出动音立即停止正在播放的空袭循环")
	manager._process(0.5)
	check(manager._air_launch_player.playing and not manager._air_raid_player.playing and manager.is_enemy_locked_audible(), "出动期间延后空袭循环但不影响普通锁定")
	await create_timer(manager._air_launch_player.stream.get_length() + 0.5).timeout
	manager._process(0.5)
	check(not manager._air_launch_player.playing and manager._air_raid_player.playing, "出动音自然结束后持续空袭开始循环")
	manager.play_air_force_launch()
	manager.set_air_raid(false)
	manager._air_launch_player.stop()
	manager._process(0.5)
	check(not manager._air_raid_player.playing, "空袭提前结束后出动音结束不会启动循环")
	manager.set_air_raid(true)
	manager.play_air_force_launch()
	paused = true
	manager._process(0.5)
	check(not manager._air_raid_player.playing and not manager._air_launch_player.playing and not manager.is_enemy_locked_audible(), "暂停时停止空军音效并淡出普通警报")
	paused = false
	manager._process(0.5)
	check(manager._air_raid_player.playing and manager.is_enemy_locked_audible(), "恢复后持续锁定音效重新播放")
	manager.play_air_force_launch()
	manager.set_muted(true)
	manager._process(0.5)
	check(not manager._air_raid_player.playing and not manager._air_launch_player.playing and AudioServer.is_bus_mute(0), "静音时停止出动音与空袭循环并静音总线")
	manager.play_air_force_launch()
	check(not manager._air_launch_player.playing, "静音时不触发空军出动音效")
	manager.set_muted(false)
	manager._process(0.5)
	check(manager._air_raid_player.playing, "解除静音后持续空袭重新播放")
	manager.play_air_force_launch()
	var temporary_scene := Node.new()
	root.add_child(temporary_scene)
	current_scene = temporary_scene
	manager._process(0.5)
	check(not manager._air_launch_player.playing and not manager._air_raid_player.playing and not manager.is_air_raid_requested(), "切换场景后停止音效并清除旧空袭状态")
	current_scene = null
	temporary_scene.free()
	manager.set_air_raid(false)
	manager.set_enemy_locked(false)
	manager._process(0.5)

	manager.set_sfx_volume(0.33)
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(manager._carrier_launch_player.bus))) - 0.33) < 0.001, "舰载机音效跟随 SFX 音量")
	var file: FileAccess = FileAccess.open("user://audio_settings.json", FileAccess.READ)
	check(file != null, "音效设置已写入磁盘")
	if file != null:
		var data: Variant = JSON.parse_string(file.get_as_text())
		check(data is Dictionary and absf(float(data.get("sfx", -1.0)) - 0.33) < 0.001, "音效音量已持久化")
		file = null
	manager.set_sfx_volume(0.8)

	manager.start_level_music()
	check(manager.is_level_music_playing(), "进入关卡后背景音乐播放")
	manager.start_level_music()
	check(manager.is_level_music_playing(), "重复开始不会打断播放")
	manager.stop_level_music()
	check(not manager.is_level_music_playing(), "返回主菜单后背景音乐停止")

	var button := Button.new()
	root.add_child(button)
	await process_frame
	check(button.has_meta("audio_hover_hooked"), "运行期新增按钮自动挂接悬停音")
	button.queue_free()
	await process_frame

	print("AUDIO_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
