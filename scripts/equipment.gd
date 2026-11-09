extends Control

const Loadout = preload("res://scripts/loadout.gd")
const CombatConfig = preload("res://scripts/combat_config.gd")
const Ship = preload("res://ship.glb")

var slots: Array = []
var selected_slot := -1
var weapons: Dictionary = {}

@onready var slot_row: HBoxContainer = $Margin/Layout/Slots
@onready var choice_row: HBoxContainer = $Margin/Layout/Choices
@onready var status: Label = $Margin/Layout/Status
@onready var pivot: Node3D = $Margin/Layout/Preview/Viewport/World/Pivot

func _ready() -> void:
	get_tree().paused = false
	slots = Loadout.get_slots()
	weapons = CombatConfig.load_config().get("weapons", {})
	$Margin/Layout/Header/Back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	var model := Ship.instantiate()
	pivot.add_child(model)
	var camera: Camera3D = $Margin/Layout/Preview/Viewport/World/Camera
	camera.position = Vector3(90, 85, 120)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	for index in range(4):
		var button := Button.new()
		button.name = "Slot%d" % (index + 1)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 50
		button.pressed.connect(_select_slot.bind(index))
		slot_row.add_child(button)
	_refresh()

func _process(delta: float) -> void:
	pivot.rotate_y(delta * 0.18)

func _select_slot(index: int) -> void:
	selected_slot = index
	_refresh()

func _install(id: String) -> void:
	if selected_slot < 0:
		return
	var updated := slots.duplicate()
	updated[selected_slot] = id
	if Loadout.save_slots(updated):
		slots = updated
		status.text = "装备已保存"
		_refresh()
	else:
		$Notice.dialog_text = "无法保存装备，请检查用户目录权限。"
		$Notice.popup_centered()

func _display_name(id: String) -> String:
	if id.is_empty():
		return "空"
	var definition: Variant = weapons.get(id, {})
	return str(definition.get("name", id)) if definition is Dictionary else id

func _refresh() -> void:
	for index in range(4):
		var button: Button = slot_row.get_child(index)
		button.text = "%s槽位 %d\n%s" % ["▶ " if index == selected_slot else "", index + 1, _display_name(slots[index])]
	for child in choice_row.get_children():
		choice_row.remove_child(child)
		child.queue_free()
	if selected_slot < 0:
		status.text = "请选择装备槽"
		return
	for id: String in Loadout.VALID_IDS:
		var button := Button.new()
		button.name = "Empty" if id.is_empty() else id
		button.text = "卸下装备" if id.is_empty() else _display_name(id)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 42
		button.pressed.connect(_install.bind(id))
		choice_row.add_child(button)
