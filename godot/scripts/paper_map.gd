class_name PaperMap
extends Control
## Mapa de papel (M). El plano entero dibujado como en un cuaderno, tapado
## donde todavía no has estado. Las marcas se comparten con los compañeros
## (las guarda el anfitrión) y también salen en el minimapa y en el mundo.
##
##   clic izquierdo: poner una marca · clic derecho: quitarla
##   arrastrar: mover el mapa · rueda: acercar · 1-4: tipo de marca · M: cerrar

const INK := Color(0.07, 0.065, 0.075)
const PAPER := Color(0.95, 0.92, 0.84)
const PAPER_DARK := Color(0.86, 0.82, 0.72)
const ROAD := Color(0.55, 0.53, 0.5)
const HOUSE := Color(0.42, 0.4, 0.38)
const TREE := Color(0.45, 0.5, 0.38)
const FIELD := Color(0.72, 0.62, 0.45)
const FONT := preload("res://fonts/SpecialElite-Regular.ttf")
const FONT_TITLE := preload("res://fonts/Bangers-Regular.ttf")
## píxeles por metro del dibujo base
const PX := 2.0
## la exploración va por cuadros de CELL metros
const CELL := 16.0
const CELLS := int(WorldLayout.HALF * 2 / CELL)
const KINDS := ["Aquí", "Peligro", "Botín", "Base"]

var world: Node
var player: Node3D
var zoom := 1.0
## punto del mundo (x, z) en el centro del mapa
var center := Vector2.ZERO
var kind := 0
var _base: ImageTexture
var _fog_img: Image
var _fog: ImageTexture
var _press := Vector2.INF
var _panned := false
var _fog_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	visible = false


func open() -> void:
	if _base == null:
		_build_base()
	if player:
		center = Vector2(player.global_position.x, player.global_position.z)
	zoom = 2.0
	_clamp_center()
	_update_fog()
	visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	# con el mando: stick izquierdo mueve, stick derecho acerca, A marca en el centro
	if _pad():
		var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		center += mv * _span() * 0.6 * delta
		var z := Input.get_axis("look_down", "look_up")
		if absf(z) > 0.1:
			zoom = clampf(zoom * (1.0 + z * 1.5 * delta), 1.0, 6.0)
		_clamp_center()
		if Input.is_action_just_pressed("jump"):
			_place(center)
	_fog_t += delta
	if _fog_t > 0.5:
		_fog_t = 0.0
		_update_fog()
	queue_redraw()


# ------------------------------------------------------------------ dibujo base (una vez)
func _build_base() -> void:
	var lay: WorldLayout = world.layout
	var n := int(WorldLayout.HALF * 2 * PX)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(PAPER)
	# campos (las piezas grandes de tierra de las granjas)
	for p in lay.props:
		var size: Vector3 = p.size
		if p.shape == "box" and size.x > 10.0 and size.y < 0.1:
			var r := _rot_rect(p.pos, size, p.yaw)
			img.fill_rect(_px(r), FIELD)
	# bosque: un punto por árbol
	for t in lay.trees:
		for tr in lay.trees[t]:
			var q := _to_px(tr[0])
			img.fill_rect(Rect2i(q.x - 1, q.y - 1, 3, 3), TREE if tr[1] else TREE.darkened(0.3))
	for r in lay.roads:
		var col := ROAD
		match r.kind:
			"acera": col = ROAD.lightened(0.3)
			"camino": col = FIELD.darkened(0.1)
			"asfalto": col = ROAD.lightened(0.15)
		img.fill_rect(_px(r.rect), col)
	for h in lay.houses:
		_building(img, h.rect, HOUSE)
	for h in lay.halls:
		_building(img, h.rect, HOUSE.darkened(0.25))
	_base = ImageTexture.create_from_image(img)
	_fog_img = Image.create(CELLS, CELLS, false, Image.FORMAT_RGBA8)
	_fog = ImageTexture.create_from_image(_fog_img)


func _building(img: Image, rect: Rect2, col: Color) -> void:
	var r := _px(rect)
	img.fill_rect(r, col)
	img.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, 2), INK)
	img.fill_rect(Rect2i(r.position.x, r.end.y - 2, r.size.x, 2), INK)
	img.fill_rect(Rect2i(r.position.x, r.position.y, 2, r.size.y), INK)
	img.fill_rect(Rect2i(r.end.x - 2, r.position.y, 2, r.size.y), INK)


func _rot_rect(pos: Vector3, size: Vector3, yaw: float) -> Rect2:
	var turned := absf(sin(yaw)) > 0.7
	var s := Vector2(size.z, size.x) if turned else Vector2(size.x, size.z)
	return Rect2(Vector2(pos.x, pos.z) - s / 2, s)


func _to_px(p: Vector3) -> Vector2i:
	return Vector2i(int((p.x + WorldLayout.HALF) * PX), int((p.z + WorldLayout.HALF) * PX))


func _px(r: Rect2) -> Rect2i:
	return Rect2i(int((r.position.x + WorldLayout.HALF) * PX), int((r.position.y + WorldLayout.HALF) * PX),
		maxi(1, int(r.size.x * PX)), maxi(1, int(r.size.y * PX)))


## Lo no explorado queda tapado con papel.
func _update_fog() -> void:
	if player == null or _fog_img == null:
		return
	var ex: PackedByteArray = player.explored
	for z in CELLS:
		for x in CELLS:
			var seen := ex.size() == CELLS * CELLS and ex[z * CELLS + x] > 0
			_fog_img.set_pixel(x, z, Color(PAPER_DARK, 0.0) if seen else PAPER_DARK)
	_fog.update(_fog_img)


# ------------------------------------------------------------------ pantalla
## Rectángulo de pantalla donde va el mapa.
func _frame() -> Rect2:
	var side := minf(size.x - 80.0, size.y - 120.0)
	return Rect2(Vector2((size.x - side) / 2, 60.0), Vector2(side, side))


func _span() -> float:
	return WorldLayout.HALF * 2 / zoom


func world_to_screen(p: Vector2) -> Vector2:
	var f := _frame()
	return f.get_center() + (p - center) / _span() * f.size.x


func screen_to_world(s: Vector2) -> Vector2:
	var f := _frame()
	return center + (s - f.get_center()) / f.size.x * _span()


func _explored_at(p: Vector2) -> bool:
	var ex: PackedByteArray = player.explored if player else PackedByteArray()
	var cx := int((p.x + WorldLayout.HALF) / CELL)
	var cz := int((p.y + WorldLayout.HALF) / CELL)
	if cx < 0 or cz < 0 or cx >= CELLS or cz >= CELLS or ex.size() != CELLS * CELLS:
		return false
	return ex[cz * CELLS + cx] > 0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(INK, 0.7))
	var f := _frame()
	# sombra de viñeta y papel
	draw_rect(Rect2(f.position + Vector2(8, 8), f.size), INK)
	draw_rect(f, PAPER)
	var src_pos := (center - Vector2.ONE * _span() / 2 + Vector2.ONE * WorldLayout.HALF)
	draw_texture_rect_region(_base, f, Rect2(src_pos * PX, Vector2.ONE * _span() * PX))
	draw_texture_rect_region(_fog, f, Rect2(src_pos / CELL, Vector2.ONE * _span() / CELL))
	# rejilla de cuaderno
	var step := 80.0
	var g := floorf((center.x - _span() / 2) / step) * step
	while g < center.x + _span() / 2:
		var a := world_to_screen(Vector2(g, 0))
		if a.x > f.position.x and a.x < f.end.x:
			draw_line(Vector2(a.x, f.position.y), Vector2(a.x, f.end.y), Color(INK, 0.08), 1.0)
		g += step
	g = floorf((center.y - _span() / 2) / step) * step
	while g < center.y + _span() / 2:
		var a := world_to_screen(Vector2(0, g))
		if a.y > f.position.y and a.y < f.end.y:
			draw_line(Vector2(f.position.x, a.y), Vector2(f.end.x, a.y), Color(INK, 0.08), 1.0)
		g += step
	# nombres de los sitios que ya conoces (sin pisarse: si no cabe arriba, va debajo)
	var taken: Array[Rect2] = []
	for pl in world.layout.places:
		var p2 := Vector2(pl.pos.x, pl.pos.z)
		if not _explored_at(p2):
			continue
		var s := world_to_screen(p2)
		if not f.has_point(s):
			continue
		var text: String = pl.name
		var fs := 22 if pl.kind == "pueblo" else 15
		var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		for dy in [-10.0, 20.0, -28.0, 38.0]:
			var at := s + Vector2(-w / 2, dy)
			var box := Rect2(at + Vector2(-2, -fs), Vector2(w + 4, fs + 4))
			if taken.any(func(r): return r.intersects(box)):
				continue
			taken.append(box)
			draw_string_outline(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, PAPER)
			draw_string(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
			break
	# marcas compartidas
	for id in world.markers:
		var m: Dictionary = world.markers[id]
		var s := world_to_screen(m.pos)
		if f.has_point(s):
			draw_marker(self, s, m.kind, m.color, 1.0)
	# compañeros y tú
	for p in get_tree().get_nodes_in_group("players"):
		var s := world_to_screen(Vector2(p.global_position.x, p.global_position.z))
		if not f.has_point(s):
			continue
		var col: Color = INK if p == player else Network.color_for(p.name.to_int())
		_arrow(s, p.global_rotation.y, col, 1.4 if p == player else 1.1)
	if _pad():
		var c := f.get_center()
		draw_line(c + Vector2(-14, 0), c + Vector2(14, 0), INK, 2.0)
		draw_line(c + Vector2(0, -14), c + Vector2(0, 14), INK, 2.0)
	draw_rect(f, INK, false, 4.0)
	# título, rosa de los vientos y leyenda
	var title := "MAPA DEL CONDADO"
	draw_string(FONT_TITLE, Vector2(f.position.x, f.position.y - 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, PAPER)
	var nrth := Vector2(f.end.x - 30, f.position.y + 40)
	draw_line(nrth + Vector2(0, 16), nrth + Vector2(0, -16), INK, 3.0)
	draw_colored_polygon(PackedVector2Array([nrth + Vector2(0, -22), nrth + Vector2(-7, -8), nrth + Vector2(7, -8)]), INK)
	draw_string(FONT, nrth + Vector2(-6, 34), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
	var legend := "Clic: marca «%s» (1-4 cambia) · Clic dcho: borrar · Arrastrar: mover · Rueda: zoom · M: cerrar" % KINDS[kind]
	if _pad():
		legend = "A: marca «%s» en la cruz (cruceta cambia) · stick izq.: mover · stick der.: zoom · B: cerrar" % KINDS[kind]
	var lw := FONT.get_string_size(legend, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(FONT, Vector2(f.get_center().x - lw / 2, f.end.y + 32), legend, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, PAPER)


## Dibuja una marca (también la usa el minimapa).
static func draw_marker(ci: CanvasItem, at: Vector2, k: int, col: Color, sc: float) -> void:
	var r := 9.0 * sc
	match k:
		0:  # cruz
			ci.draw_line(at + Vector2(-r, -r), at + Vector2(r, r), INK, 6.0 * sc)
			ci.draw_line(at + Vector2(-r, r), at + Vector2(r, -r), INK, 6.0 * sc)
			ci.draw_line(at + Vector2(-r, -r), at + Vector2(r, r), col, 3.0 * sc)
			ci.draw_line(at + Vector2(-r, r), at + Vector2(r, -r), col, 3.0 * sc)
		1:  # peligro
			var tri := PackedVector2Array([at + Vector2(0, -r * 1.2), at + Vector2(r * 1.1, r * 0.8), at + Vector2(-r * 1.1, r * 0.8)])
			ci.draw_colored_polygon(tri, col)
			tri.append(tri[0])
			ci.draw_polyline(tri, INK, 2.0 * sc)
			ci.draw_line(at + Vector2(0, -r * 0.5), at + Vector2(0, r * 0.2), INK, 2.5 * sc)
			ci.draw_circle(at + Vector2(0, r * 0.5), 1.6 * sc, INK)
		2:  # botín
			ci.draw_circle(at, r, INK)
			ci.draw_circle(at, r - 2.0 * sc, col)
			ci.draw_circle(at, r * 0.35, INK)
		_:  # base
			var house := PackedVector2Array([at + Vector2(-r, r * 0.8), at + Vector2(-r, -r * 0.1), at + Vector2(0, -r),
				at + Vector2(r, -r * 0.1), at + Vector2(r, r * 0.8)])
			ci.draw_colored_polygon(house, col)
			house.append(house[0])
			ci.draw_polyline(house, INK, 2.0 * sc)


func _arrow(at: Vector2, yaw: float, color: Color, sc: float) -> void:
	var pts := PackedVector2Array([Vector2(0, -10), Vector2(7, 8), Vector2(0, 4), Vector2(-7, 8)])
	var t := Transform2D(-yaw, at)
	var out := PackedVector2Array()
	for p in pts:
		out.append(t * (p * sc))
	draw_colored_polygon(out, color)
	out.append(out[0])
	draw_polyline(out, PAPER if color == INK else INK, 2.0)


func _pad() -> bool:
	var main := get_tree().get_first_node_in_group("main")
	return main != null and main.pad_mode


# ------------------------------------------------------------------ manejo
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.25)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 0.8)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = mb.position
				_panned = false
			else:
				if not _panned and _frame().has_point(mb.position):
					_place(screen_to_world(mb.position))
				_press = Vector2.INF
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_remove_near(mb.position)
		accept_event()
	elif event is InputEventMouseMotion and _press != Vector2.INF:
		var mm := event as InputEventMouseMotion
		if _panned or mm.position.distance_to(_press) > 6.0:
			_panned = true
			center -= mm.relative / _frame().size.x * _span()
			_clamp_center()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	for i in 4:
		if event.is_action_pressed(["eat", "drink", "bandage", "throw"][i]):
			kind = i
			get_viewport().set_input_as_handled()


func _zoom_at(screen: Vector2, factor: float) -> void:
	var before := screen_to_world(screen)
	zoom = clampf(zoom * factor, 1.0, 6.0)
	center += before - screen_to_world(screen)
	_clamp_center()


func _clamp_center() -> void:
	var half := _span() / 2
	center.x = clampf(center.x, -WorldLayout.HALF + half, WorldLayout.HALF - half)
	center.y = clampf(center.y, -WorldLayout.HALF + half, WorldLayout.HALF - half)


func _place(p: Vector2) -> void:
	var col := Network.color_for(multiplayer.get_unique_id())
	world.request_marker.rpc_id(1, p, kind, Network.player_name, col)
	Sfx.play("click")


func _remove_near(screen: Vector2) -> void:
	for id in world.markers:
		if world_to_screen(world.markers[id].pos).distance_to(screen) < 14.0:
			world.request_remove_marker.rpc_id(1, id)
			Sfx.play("click", 0.0, 0.8)
			return
