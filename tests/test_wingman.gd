extends SceneTree

const Loadout = preload("res://scripts/loadout.gd")

func _initialize() -> void:
	var file := FileAccess.open(Loadout.SAVE_PATH, FileAccess.WRITE)
	file.store_string('{"slots":["wingman","carrier","wingman","missile"]}')
	file.close()
	var slots := Loadout.get_slots()
	var passed := slots == ["", "carrier", "", "missile"] and not Loadout.save_slots(["wingman", "", "", ""])
	print("LEGACY_WINGMAN_TEST passed=%s" % passed)
	quit(0 if passed else 1)
