extends Control
## Minimapa que gira contigo: arriba es hacia donde miras.
## Calles, casas, muebles (rellenos = sin registrar), zombis cercanos en rojo
## y tus compañeros con su color.

const RANGE := 38.0  # metros desde el centro hasta el borde
const INK := Color(0.07, 0.065, 0.075)
const PAPER := Color(0.95, 0.92, 0.84)
const ROAD := Color(0.62, 0.6, 0.56)
const HOUSE := Color(0.42, 0.4, 0.38)
const ZOMBIE := Color(0.75, 0.06, 0.04)

var player: Node3D
var world: Node


func _ready() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(210, 210)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	if player == null or not is_instance_valid(player) or world == null:
		return
	var center := size / 2
	var scale_ := size.x / 2 / RANGE
	var yaw := player.global_rotation.y
	var c := cos(yaw)
	var s := sin(yaw)
	var origin := Vector2(player.global_position.x, player.global_position.z)
	var to_map := func(x: float, z: float) -> Vector2:
		var d := Vector2(x, z) - origin
		return center + Vector2(d.x * c - d.y * s, d.x * s + d.y * c) * scale_

	# calles
	var half: float = world.HALF
	for r in world.ROADS:
		draw_line(to_map.call(r, -half), to_map.call(r, half), ROAD, world.ROAD_W * scale_)
		draw_line(to_map.call(-half, r), to_map.call(half, r), ROAD, world.ROAD_W * scale_)
	# casas
	for h in world.houses:
		var rect: Rect2 = h.rect
		var pts := PackedVector2Array([
			to_map.call(rect.position.x, rect.position.y), to_map.call(rect.end.x, rect.position.y),
			to_map.call(rect.end.x, rect.end.y), to_map.call(rect.position.x, rect.end.y)])
		draw_colored_polygon(pts, HOUSE)
		pts.append(pts[0])
		draw_polyline(pts, INK, 1.5)
	# lo construido: muros como trazos de tinta, la cama con un cuadro claro
	for sid in world.structures.by_id:
		var st: Dictionary = world.structures.by_id[sid]
		var sz: Vector3 = world.structures.TYPES[st.type].size
		var c0: Vector2 = to_map.call(st.pos.x, st.pos.z)
		var along := Vector2(cos(st.rot), -sin(st.rot)) * sz.x * 0.5
		var a1: Vector2 = to_map.call(st.pos.x + along.x, st.pos.z + along.y)
		var a2: Vector2 = to_map.call(st.pos.x - along.x, st.pos.z - along.y)
		match st.type:
			"cama":
				draw_rect(Rect2(c0 - Vector2(4, 4), Vector2(8, 8)), PAPER)
				draw_rect(Rect2(c0 - Vector2(4, 4), Vector2(8, 8)), INK, false, 2.0)
			"pinchos":
				draw_circle(c0, 2.5, Color(INK, 0.6))
			"banco", "hoguera", "caja":
				draw_circle(c0, 3.0, ZOMBIE if st.type == "hoguera" else INK)
			_:
				draw_line(a1, a2, INK, 3.0)
	# muebles y maleteros
	for ct in world.containers:
		var p: Vector2 = to_map.call(ct.pos.x, ct.pos.z)
		if ct.type == "mochila":
			if ct.empty:
				continue
			# mochila de un cadáver: siempre visible, en el borde si está lejos
			if ct.corpse:
				p = p.clamp(Vector2(7, 7), size - Vector2(7, 7))
			draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), ZOMBIE if ct.corpse else Color(0.98, 0.86, 0.55))
			draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), INK, false, 1.5)
			continue
		if ct.empty:
			draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), Color(INK, 0.35), false, 1.0)
		else:
			draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), Color(0.98, 0.86, 0.55))
			draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), INK, false, 1.0)
	# zombis cercanos
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.dead or z.global_position.distance_to(player.global_position) > RANGE * 0.8:
			continue
		draw_circle(to_map.call(z.global_position.x, z.global_position.z), 3.2, ZOMBIE)
	# compañeros
	for p in get_tree().get_nodes_in_group("players"):
		if p == player:
			continue
		var at: Vector2 = to_map.call(p.global_position.x, p.global_position.z)
		at = at.clamp(Vector2(6, 6), size - Vector2(6, 6))
		_arrow(at, p.global_rotation.y - yaw, Network.color_for(p.name.to_int()))
	# tú, en el centro mirando arriba
	_arrow(center, 0.0, INK)
	draw_rect(Rect2(Vector2.ZERO, size), INK, false, 3.0)


func _arrow(at: Vector2, angle: float, color: Color) -> void:
	var pts := PackedVector2Array([Vector2(0, -8), Vector2(5.5, 6), Vector2(0, 3), Vector2(-5.5, 6)])
	var t := Transform2D(-angle, at)
	var out := PackedVector2Array()
	for p in pts:
		out.append(t * p)
	draw_colored_polygon(out, color)
	out.append(out[0])
	draw_polyline(out, INK, 1.5)
