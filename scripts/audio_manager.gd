extends Node
## 全局音效管理（Autoload：/root/AudioManager）。
## 负责总线、按钮悬停音、敌方锁定警报以及音量设置的持久化。
## 音频不受场景树暂停影响，锁定警报在暂停时淡出。

const UI_HOVER_PATH := "res://audio/ui_hover.mp3"
const ENEMY_LOCKED_PATH := "res://audio/enemy_locked.wav"
const AIR_FORCE_PATH := "res://audio/air_force.mp3"
const LEVEL_MUSIC_PATH := "res://audio/level_music.mp3"
const MISSILE_LAUNCH_PATH := "res://audio/missile_launch.mp3"
const CARRIER_LAUNCH_PATH := "res://audio/carrier_launch.mp3"
const LEVEL_COMPLETE_PATH := "res://audio/level_complete_compatible.wav"
const BUS_UI := "AudioUI"
const BUS_SFX := "AudioSFX"
const BUS_MUSIC := "AudioMusic"
const HOVER_MIN_INTERVAL_MS := 60
const LOCKED_FADE_SECONDS := 0.18
const SETTINGS_PATH := "user://audio_settings.json"

var master_volume: float = 0.9
var ui_volume: float = 0.55
var sfx_volume: float = 0.8
var music_volume: float = 0.6
var muted: bool = false

var _hover_player: AudioStreamPlayer
var _locked_player: AudioStreamPlayer
var _air_raid_player: AudioStreamPlayer
var _air_launch_player: AudioStreamPlayer
var _air_launch_scene: Node
var _air_raid_requested := false
var _air_raid_scene: Node
var _music_player: AudioStreamPlayer
var _missile_stream: AudioStream
var _carrier_launch_player: AudioStreamPlayer
var _complete_player: AudioStreamPlayer
var _music_enabled: bool = true
var _hover_last_ms: int = 0
var _lock_requested: bool = false
var _lock_gain: float = 0.0
var _hover_played: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	_ensure_bus(BUS_UI)
	_ensure_bus(BUS_SFX)
	_ensure_bus(BUS_MUSIC)
	_hover_player = _make_player(BUS_UI, UI_HOVER_PATH)
	_locked_player = _make_player(BUS_SFX, ENEMY_LOCKED_PATH)
	_air_raid_player = _make_player(BUS_SFX, AIR_FORCE_PATH)
	if is_instance_valid(_air_raid_player) and _air_raid_player.stream is AudioStreamMP3:
		_air_raid_player.stream = _air_raid_player.stream.duplicate()
		(_air_raid_player.stream as AudioStreamMP3).loop = true
	_air_launch_player = _make_player(BUS_SFX, AIR_FORCE_PATH)
	_music_player = _make_player(BUS_MUSIC, LEVEL_MUSIC_PATH)
	_complete_player = _make_player(BUS_SFX, LEVEL_COMPLETE_PATH)
	_carrier_launch_player = _make_player(BUS_SFX, CARRIER_LAUNCH_PATH)
	if ResourceLoader.exists(MISSILE_LAUNCH_PATH):
		_missile_stream = load(MISSILE_LAUNCH_PATH)
	else:
		push_warning("音效资源缺失：" + MISSILE_LAUNCH_PATH)
	if is_instance_valid(_music_player):
		_music_player.finished.connect(_on_music_finished)
	if is_instance_valid(_locked_player) and _locked_player.stream is AudioStreamWAV:
		# Godot 4.7 的 WAV 导入器不保留 edit/loop_mode，循环在运行时设置。
		_locked_player.stream = _make_looping(_locked_player.stream as AudioStreamWAV)
	if is_instance_valid(_locked_player) and _locked_player.stream is AudioStreamWAV and (_locked_player.stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_FORWARD:
		# 兜底：无法写入循环时靠播放结束信号续播，会有一次混音缓冲的间隙。
		_locked_player.finished.connect(_restart_locked_if_needed)
	_apply_volumes()
	get_tree().node_added.connect(_on_node_added)
	_scan_existing(get_tree().root)

func _process(delta: float) -> void:
	if is_instance_valid(_air_launch_player) and _air_launch_player.playing and (muted or get_tree().paused or _air_launch_scene != get_tree().current_scene):
		_air_launch_player.stop()
	if _air_raid_requested and _air_raid_scene != get_tree().current_scene:
		_air_raid_requested = false
	if is_instance_valid(_air_raid_player):
		var launch_playing := is_instance_valid(_air_launch_player) and _air_launch_player.playing
		var air_active := _air_raid_requested and not muted and not get_tree().paused and not launch_playing
		if air_active and not _air_raid_player.playing and _air_raid_player.stream != null:
			_air_raid_player.play()
		elif not air_active and _air_raid_player.playing:
			_air_raid_player.stop()
	if not is_instance_valid(_locked_player):
		return
	var active: bool = _lock_requested and not muted and not get_tree().paused
	_lock_gain = move_toward(_lock_gain, 1.0 if active else 0.0, delta / LOCKED_FADE_SECONDS)
	if _lock_gain <= 0.0001:
		if _locked_player.playing:
			_locked_player.stop()
		_locked_player.volume_db = -80.0
		return
	_locked_player.volume_db = linear_to_db(_lock_gain)
	if active and not _locked_player.playing:
		_locked_player.play()

## 按钮悬停/获得焦点音。带最小间隔，避免鼠标快速划过时连成一片。
func play_ui_hover() -> void:
	if muted or not is_instance_valid(_hover_player) or _hover_player.stream == null:
		return
	var now: int = Time.get_ticks_msec()
	if now - _hover_last_ms < HOVER_MIN_INTERVAL_MS:
		return
	_hover_last_ms = now
	_hover_played += 1
	_hover_player.play()

func play_level_complete() -> void:
	if not muted and is_instance_valid(_complete_player) and _complete_player.stream != null:
		_complete_player.play()

func play_carrier_launch() -> void:
	if not muted and not get_tree().paused and is_instance_valid(_carrier_launch_player) and _carrier_launch_player.stream != null:
		_carrier_launch_player.play()

func play_missile_launch() -> void:
	if muted or _missile_stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.bus = BUS_SFX
	player.stream = _missile_stream
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

## 任一敌机锁定玩家时传 true。重复调用同一值不会重启音频。
func set_enemy_locked(locked: bool) -> void:
	if _lock_requested == locked:
		return
	_lock_requested = locked
	if locked and is_instance_valid(_locked_player) and _locked_player.stream != null and not _locked_player.playing:
		_lock_gain = 0.0
		_locked_player.play()

func play_air_force_launch() -> void:
	if muted or get_tree().paused or not is_instance_valid(_air_launch_player) or _air_launch_player.stream == null:
		return
	_air_launch_scene = get_tree().current_scene
	if is_instance_valid(_air_raid_player):
		_air_raid_player.stop()
	_air_launch_player.play()

func set_air_raid(active: bool) -> void:
	_air_raid_requested = active
	if active:
		_air_raid_scene = get_tree().current_scene
	if not active and is_instance_valid(_air_raid_player):
		_air_raid_player.stop()

func is_air_raid_requested() -> bool:
	return _air_raid_requested

func is_enemy_locked_requested() -> bool:
	return _lock_requested

func is_enemy_locked_looping() -> bool:
	return is_instance_valid(_locked_player) and _locked_player.stream is AudioStreamWAV and (_locked_player.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD

func is_enemy_locked_audible() -> bool:
	return is_instance_valid(_locked_player) and _locked_player.playing and _lock_gain > 0.0001

func hover_play_count() -> int:
	return _hover_played

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()
	_save_settings()

func set_ui_volume(value: float) -> void:
	ui_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()
	_save_settings()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()
	_save_settings()

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()
	_save_settings()

## 进入关卡时开始背景音乐（循环），返回主菜单时停止。重复开始会从头重播。
func start_level_music() -> void:
	if not _music_enabled or not is_instance_valid(_music_player) or _music_player.stream == null:
		return
	if not _music_player.playing:
		_music_player.play()

func stop_level_music() -> void:
	if is_instance_valid(_music_player) and _music_player.playing:
		_music_player.stop()

func is_level_music_playing() -> bool:
	return is_instance_valid(_music_player) and _music_player.playing

func _on_music_finished() -> void:
	if _music_enabled:
		start_level_music()

func set_muted(value: bool) -> void:
	muted = value
	_apply_volumes()
	_save_settings()

func _make_looping(source: AudioStreamWAV) -> AudioStreamWAV:
	var looped: AudioStreamWAV = source.duplicate()
	looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
	looped.loop_begin = 0
	var bytes_per_frame: int = (2 if looped.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if looped.stereo else 1)
	var frames: int = looped.data.size() / maxi(bytes_per_frame, 1)
	if frames <= 0:
		frames = int(round(looped.get_length() * looped.mix_rate))
	looped.loop_end = maxi(frames, 0)
	return looped

func _make_player(bus: String, path: String) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		push_warning("音效资源缺失：" + path)
		return null
	var player := AudioStreamPlayer.new()
	player.name = path.get_file().get_basename()
	player.bus = bus
	player.stream = load(path)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")

func _apply_volumes() -> void:
	AudioServer.set_bus_mute(0, muted)
	AudioServer.set_bus_volume_db(0, _to_db(master_volume))
	for bus_name in [BUS_UI, BUS_SFX, BUS_MUSIC]:
		var index: int = AudioServer.get_bus_index(bus_name)
		if index == -1:
			continue
		var volume: float
		match bus_name:
			BUS_UI:
				volume = ui_volume
			BUS_SFX:
				volume = sfx_volume
			_:
				volume = music_volume
		AudioServer.set_bus_volume_db(index, _to_db(volume))

func _to_db(linear: float) -> float:
	return linear_to_db(clampf(linear, 0.0001, 1.0))

func _restart_locked_if_needed() -> void:
	if _lock_requested and not muted and not get_tree().paused and is_instance_valid(_locked_player):
		_locked_player.play()

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node as BaseButton)

func _scan_existing(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node as BaseButton)
	for child in node.get_children():
		_scan_existing(child)

func _hook_button(button: BaseButton) -> void:
	if button.has_meta("audio_hover_hooked"):
		return
	button.set_meta("audio_hover_hooked", true)
	button.mouse_entered.connect(play_ui_hover)
	button.focus_entered.connect(play_ui_hover)

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		return
	master_volume = clampf(float(data.get("master", master_volume)), 0.0, 1.0)
	ui_volume = clampf(float(data.get("ui", ui_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(data.get("sfx", sfx_volume)), 0.0, 1.0)
	music_volume = clampf(float(data.get("music", music_volume)), 0.0, 1.0)
	muted = bool(data.get("muted", muted))

func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("无法保存音效设置")
		return
	file.store_string(JSON.stringify({
		"master": master_volume,
		"ui": ui_volume,
		"sfx": sfx_volume,
		"music": music_volume,
		"muted": muted,
	}))
