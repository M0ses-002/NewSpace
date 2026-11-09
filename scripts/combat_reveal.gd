extends Node2D

const Mask = preload("res://scripts/reveal_mask.gdshader")
var battle: Node
var painters: Dictionary = {}
var previous_signature: Array = []

func update_reveal() -> void:
	if not is_instance_valid(battle):
		return
	var signature: Array = [battle.controller.ship.global_position, battle.scan_angle, battle.fog_overflow, get_viewport().get_canvas_transform(), get_viewport().get_final_transform()]
	for list in [battle.satellites, battle.debris]:
		for item in list:
			var body: Polygon2D = item.node.get_node("Body")
			signature.append([item.node.get_instance_id(), body.global_transform, body.polygon, item.node.modulate, item.get("health", 0.0)])
	if signature == previous_signature:
		return
	previous_signature = signature
	var live: Dictionary = {}
	for list in [battle.satellites, battle.debris]:
		for item in list:
			var node: Node2D = item.node
			var id := node.get_instance_id()
			live[id] = true
			if not painters.has(id):
				var painter := preload("res://scripts/reveal_painter.gd").new()
				var shader := ShaderMaterial.new()
				shader.shader = Mask
				painter.material = shader
				painter.battle = battle
				painter.item = item
				add_child(painter)
				painters[id] = painter
			var painter: Node2D = painters[id]
			var body: Polygon2D = node.get_node("Body")
			var extent: float = 0.0
			for point in body.polygon:
				extent = maxf(extent, (body.global_transform * point).distance_to(node.global_position))
			if item.has("owner"):
				var panels: Line2D = node.get_node("Panels")
				for point in panels.points:
					extent = maxf(extent, (panels.global_transform * point).distance_to(node.global_position) + panels.width)
			if battle.fog_overflow or node.global_position.distance_to(battle.controller.ship.global_position) > float(battle.config.radar.far_radius_km) + extent:
				painter.visible = false
				continue
			var masks: Array = battle.entity_mask(node)
			var near: PackedVector2Array = masks[0]
			var far: PackedVector2Array = masks[1]
			var valid: bool = not battle.fog_overflow and near.size() <= 256 and far.size() <= 256
			painter.visible = valid
			if valid:
				var material: ShaderMaterial = painter.material
				material.set_shader_parameter("near_count", near.size())
				material.set_shader_parameter("far_count", far.size())
				near.resize(256)
				far.resize(256)
				material.set_shader_parameter("near_points", near)
				material.set_shader_parameter("far_points", far)
				painter.queue_redraw()
	for id in painters.keys():
		if not live.has(id):
			painters[id].queue_free()
			painters.erase(id)
