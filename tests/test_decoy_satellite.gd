extends SceneTree

const Decoy = preload("res://scenes/decoy_satellite.tscn")
const Orbit = preload("res://scripts/kepler_orbit.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var settings := {"attraction_radius_km": 90.0, "radius_km": 3.0}
	var node = Decoy.instantiate()
	root.add_child(node)
	var mu := 1000.0
	var source_orbit := Orbit.make(200.0, 0.3, 0.4)
	var source = Orbit.state_at(source_orbit, 1.1, -1.0, mu)
	check(node.initialize(source.position, source.velocity, Vector2.ZERO, mu, "player", settings), "初始化椭圆诱饵")
	check(absf(node.orbit.a - 200.0) < 0.02 and absf(node.orbit.e - 0.3) < 0.001 and node.direction == -1.0, "保持部署时闭合椭圆及方向")
	var origin: Vector2 = node.global_position
	var period := TAU * sqrt(pow(200.0, 3) / mu)
	node.advance(period)
	check(node.global_position.distance_to(origin) < 0.01, "椭圆一周期返回")
	check(node.initialize(Vector2(200, 0), Vector2(0, 10), Vector2.ZERO, mu, "enemy", settings), "非闭合状态初始化")
	check(node.orbit.e == 0.0 and absf(node.orbit.a - 200.0) < 0.01 and node.team == "enemy", "非闭合状态退化为当前位置圆轨")
	node.queue_free()
	await process_frame
	print("DECOY_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
