extends Node2D
var battle: Node
var item: Dictionary

func _draw() -> void:
	if not is_instance_valid(battle) or not is_instance_valid(item.node):
		return
	var node: Node2D = item.node
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var body: Polygon2D = node.get_node("Body")
	var points := PackedVector2Array()
	for point in body.polygon:
		points.append(canvas * body.global_transform * point)
	draw_colored_polygon(points, body.color * node.modulate)
	if item.has("owner"):
		var panels: Line2D = node.get_node("Panels")
		var line := PackedVector2Array()
		for point in panels.points:
			line.append(canvas * panels.global_transform * point)
		draw_polyline(line, panels.default_color * node.modulate, panels.width * canvas.get_scale().x)
		if battle.visible_to(battle.controller.ship.position, node.position, node):
			var label: Label = node.get_node("Health")
			var pos: Vector2 = canvas * (node.global_transform * Vector2(-16, -12))
			draw_string(ThemeDB.fallback_font, pos, label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(1, roundi(11 * canvas.get_scale().x)), node.modulate)
