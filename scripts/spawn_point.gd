extends Node2D

signal spawn_requested
signal exhausted

@export_range(0.01, 3600.0, 0.01, "or_greater") var interval_real_s := 5.0
@export_range(1, 1000, 1, "or_greater") var spawn_limit := 3

var remaining_real_s := 0.0
var spawned := 0
var dead := false

func _ready() -> void:
	reset_spawn_point()

func reset_spawn_point() -> void:
	remaining_real_s = interval_real_s
	spawned = 0
	dead = false
	visible = true

func advance_spawn_clock(real_delta: float, frozen: bool = false) -> void:
	if dead or frozen or get_tree().paused or real_delta <= 0.0 or interval_real_s <= 0.0 or spawn_limit <= 0:
		return
	remaining_real_s -= real_delta
	while not dead and remaining_real_s <= 0.0:
		spawned += 1
		spawn_requested.emit()
		if spawned >= spawn_limit:
			dead = true
			visible = false
			exhausted.emit()
		else:
			remaining_real_s += interval_real_s
