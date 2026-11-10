extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var level = load("res://scenes/level_8.tscn").instantiate()
	root.add_child(level)
	level.sandbox.set_physics_process(false)
	for i in range(level.config.tutorial.size()):
		level._show_page(i)
	level._open_equipment()
	level._start_level()
	var battle = level.combat
	var point = level.get_node("Sandbox/World/CarrierSpawnPoint")
	check(battle.carrier_spawn_points.has(point), "发现本关刷新点")
	battle.advance_cooldowns(4.9)
	check(battle.carrier_squadrons.is_empty(), "首组等待五现实秒")
	level.sandbox.manually_paused = true
	battle.advance_cooldowns(10.0)
	check(battle.carrier_squadrons.is_empty(), "暂停冻结")
	level.sandbox.manually_paused = false
	level.sandbox.dragging = true
	battle.advance_cooldowns(10.0)
	check(battle.carrier_squadrons.is_empty(), "轨道编辑冻结")
	level.sandbox.dragging = false
	battle.dead = true
	battle.advance_cooldowns(10.0)
	check(battle.carrier_squadrons.is_empty(), "玩家死亡冻结")
	battle.dead = false
	paused = true
	battle.advance_cooldowns(10.0)
	paused = false
	check(battle.carrier_squadrons.is_empty(), "场景树暂停冻结")
	battle.advance_cooldowns(0.1)
	check(battle.carrier_squadrons.size() == 1, "首次仅生成一组")
	var first = battle.carrier_squadrons[0]
	var anchor = first.mothership
	check(anchor != point and anchor.global_position.is_equal_approx(point.global_position), "固定独立返航锚点")
	check(first.center.is_equal_approx(level.sandbox.ship.get_parent().to_global(level.sandbox.body_at(0).center)), "第一行星为焦点")
	battle.advance_cooldowns(10.0)
	check(battle.carrier_squadrons.size() == 3 and point.dead and not point.visible, "三组后刷新点耗尽")
	battle._advance_carrier_squadrons(0.001, {})
	check(battle.carrier_squadrons.has(first) and is_instance_valid(anchor), "耗尽后在途编队继续")
	battle.reset_battle()
	check(battle.carrier_squadrons.is_empty() and not point.dead and point.visible and point.spawned == 0, "重置编队和刷新点")
	await process_frame
	check(not is_instance_valid(anchor), "重置清理独立锚点")
	level.queue_free()
	await process_frame
	print("CARRIER_SPAWN_COMBAT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
