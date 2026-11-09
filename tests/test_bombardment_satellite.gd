extends SceneTree

var checks := 0
var failures := 0
var impacts: Array = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func on_impact(position_world: Vector2, radius: float, damage: float) -> void:
	impacts.append([position_world, radius, damage])

func run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	await process_frame
	var satellites: Node = scene.get_node("World/Combat/Satellites")
	var satellite: Node2D = load("res://scenes/bombardment_satellite.tscn").instantiate()
	satellite.position = Vector2(190, 0)
	satellites.add_child(satellite)
	check(satellite.initialize("satellite", {}), "轰炸卫星配置加载")
	satellite.state = {"angle": 0.0, "owner": "neutral"}
	satellite.bomb_impact.connect(on_impact)
	check(not satellite.fire_bomb(), "未夺控不能使用")
	satellite.state.owner = "player"
	check(satellite.fire_bomb() and satellite.descent_state == "FALLING", "夺控后本体开始坠落")
	check(not satellite.fire_bomb(), "坠落期间不能重复使用")
	var start: Vector2 = satellite.global_position
	satellite.behavior.advance(satellite, 1.0)
	check(satellite.global_position == start, "坠落时公转不覆盖位置")
	scene.manually_paused = true
	satellite.advance_bombs(1.0)
	check(satellite.global_position == start, "暂停冻结坠落")
	scene.manually_paused = false
	scene.speed_dragging = true
	satellite.advance_bombs(1.0)
	check(satellite.global_position == start, "编辑冻结坠落")
	scene.speed_dragging = false
	satellite.advance_bombs(1.0)
	check(satellite.global_position.distance_to(Vector2(178, 0)) < 0.001, "卫星本体朝地心坠落")
	satellite.advance_bombs(100.0)
	check(impacts.size() == 1 and impacts[0][0].distance_to(Vector2(50, 0)) < 0.001, "大步精确落在行星表面")
	check(impacts.size() == 1 and impacts[0][1] == 35.0 and impacts[0][2] == 40.0, "范围和伤害从配置传出")
	check(satellite.descent_state == "SPENT" and not satellite.visible and not satellite.fire_bomb(), "撞地后消耗不可再使用")
	satellite.advance_bombs(100.0)
	check(impacts.size() == 1, "爆炸只结算一次")
	check(satellite.initialize("satellite", {}), "重置后重新初始化")
	satellite.state = {"angle": 0.0, "owner": "player"}
	check(satellite.visible and satellite.descent_state == "ORBIT" and satellite.fire_bomb(), "重置恢复卫星")
	satellite.reset_bombs()
	check(satellite.descent_state == "SPENT" and not satellite.visible, "中止坠落不回轨")
	var second: Node2D = load("res://scenes/bombardment_satellite.tscn").instantiate()
	second.position = Vector2(190, 0)
	second.planet_index = 1
	satellites.add_child(second)
	check(second.initialize("satellite", {}), "第二颗卫星配置加载")
	second.state = {"angle": 0.0, "owner": "player"}
	if scene.bodies.size() > 1:
		second.behavior.advance(second, 0.0)
		var center: Vector2 = scene.bodies[1].center
		check(absf(second.position.distance_to(center) - 190.0) < 0.001, "围绕指定行星公转")
		second.bomb_impact.connect(on_impact)
		check(second.fire_bomb(), "第二行星卫星可坠落")
		second.advance_bombs(100.0)
		check(absf(impacts.back()[0].distance_to(center) - float(scene.bodies[1].radius_km)) < 0.001, "落在绑定行星表面")
	scene.queue_free()
	await process_frame
	print("BOMBARDMENT_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
