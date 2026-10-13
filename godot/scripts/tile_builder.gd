class_name TileBuilder
extends RefCounted
## Construye una zona del mapa (TILE × TILE metros) a partir del plano.
## Todo se monta fuera del árbol de escena y al final se fusiona: las piezas
## que no cambian van en pocas mallas grandes y en un solo cuerpo de colisión
## por zona. world.gd añade el resultado al mundo y lo quita cuando nadie está cerca.

const TOON := preload("res://shaders/toon.gdshader")
const FONT_SIGN := preload("res://fonts/Bangers-Regular.ttf")
const WALL_H := WorldLayout.WALL_H
const WALL_T := 0.25
const DOOR_W := 1.6
const DOOR_H := 2.2
## trozos de malla fusionada dentro de cada zona (para recortar lo que no se ve)
const CHUNK := 40.0
const STAIR_RUN := 4.4
const STAIR_STEPS := 14

var layout: WorldLayout
var rng := RandomNumberGenerator.new()
var _materials := {}
var _batch_mats := {}
## zona en construcción
var root: Node3D
var tile := Vector2i.ZERO
## resultados para world.gd
## [[índice del mueble, cuerpo, malla]]
var out_containers: Array = []
## [{rect, roof, upper, base}] tejados (y plantas de arriba) que se ocultan al entrar
var out_roofs: Array[Dictionary] = []
## plantas de arriba de esta zona: [[rect, nodo]] para colgar de ellas lo que va arriba
var _uppers: Array = []


## false en el constructor del hilo: las piezas que se van a fusionar no
## necesitan malla propia, solo su forma (que se fusiona desde formas unidad)
var real_meshes := true
## formas unidad calculadas en el hilo principal: caja, prisma, esfera, cilindros
var _units := {}


func _init(l: WorldLayout, threaded := false) -> void:
	layout = l
	real_meshes = not threaded
	_units["box"] = BoxMesh.new().get_mesh_arrays()
	_units["prism"] = PrismMesh.new().get_mesh_arrays()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 5
	_units["sphere"] = sm.get_mesh_arrays()
	for k in 11:
		var cm := CylinderMesh.new()
		cm.top_radius = k / 10.0
		cm.bottom_radius = 1.0
		cm.height = 1.0
		cm.radial_segments = 10
		cm.rings = 1
		_units["cyl%d" % k] = cm.get_mesh_arrays()


## Monta la zona t. Devuelve su nodo raíz, todavía fuera del árbol.
func build(t: Vector2i) -> Node3D:
	tile = t
	root = Node3D.new()
	root.name = "Zona_%d_%d" % [t.x, t.y]
	out_containers = []
	out_roofs = []
	_uppers = []
	var td: Dictionary = layout.by_tile[t]
	rng.seed = hash(t) ^ WorldLayout.SEED
	_ground_details()
	for i in td.roads:
		_road(i)
	for i in td.houses:
		_house(layout.houses[i])
	for i in td.halls:
		_hall(layout.halls[i])
	for i in td.cars:
		_car(layout.cars[i])
	for i in td.props:
		_prop(layout.props[i])
	for i in td.fences:
		_fence(layout.fences[i])
	for i in td.poles:
		_pole(layout.poles[i])
	for i in td.prefabs:
		_prefab(layout.prefabs[i])
	for i in td.conts:
		_container(i)
	for tr in layout.trees.get(t, []):
		rng.seed = tr[2]
		if tr[1]:
			_tree(tr[0])
		else:
			_dead_tree(tr[0])
	rng.seed = hash(t) ^ (WorldLayout.SEED + 7)
	_debris()
	_batch()
	return root


func nav_group(t: Vector2i) -> StringName:
	return StringName("nav_%d_%d" % [t.x, t.y])


# ------------------------------------------------------------------ suelo y calles
func _ground_details() -> void:
	var r := WorldLayout.tile_rect(tile)
	var town := r.intersects(Rect2(-WorldLayout.TOWN, -WorldLayout.TOWN, WorldLayout.TOWN * 2, WorldLayout.TOWN * 2))
	for i in (14 if town else 22):
		var p := Vector3(rng.randf_range(r.position.x, r.end.x), 0.004, rng.randf_range(r.position.y, r.end.y))
		var col := WorldLayout.C_DIRT if town or rng.randf() < 0.5 else WorldLayout.C_GRASS.darkened(0.18)
		_disc(p, rng.randf_range(1.5, 5.5), col, rng.randf_range(0.5, 1.0), root)


func _road(i: int) -> void:
	var road: Dictionary = layout.roads[i]
	var r: Rect2 = (road.rect as Rect2).intersection(WorldLayout.tile_rect(tile))
	if r.size.x < 0.01 or r.size.y < 0.01:
		return
	var along_x: bool = (road.rect as Rect2).size.x > (road.rect as Rect2).size.y
	var c := r.get_center()
	match road.kind:
		"acera":
			_box(Vector3(c.x, 0.03, c.y), Vector3(r.size.x, 0.06, r.size.y), WorldLayout.C_WALK, false, root, 0.35, 1.2)
		"camino":
			_box(Vector3(c.x, 0.006, c.y), Vector3(r.size.x, 0.012, r.size.y), WorldLayout.C_DIRT.lightened(0.05), false, root, 0.6, 1.0)
		"asfalto":
			_box(Vector3(c.x, 0.008, c.y), Vector3(r.size.x, 0.02, r.size.y), WorldLayout.C_ROAD.lightened(0.06), false, root, 0.5, 0.8)
		_:
			# calles a lo largo de X un pelín más altas: no parpadean en los cruces
			var y := 0.012 if along_x else 0.01
			_box(Vector3(c.x, y, c.y), Vector3(r.size.x, 0.02, r.size.y), WorldLayout.C_ROAD, false, root, 0.5, 0.8)
			_road_lines(r, along_x, road.kind == "carretera")


## Línea discontinua en el centro (y bordes en la carretera), sin pintar los cruces.
func _road_lines(r: Rect2, along_x: bool, edges: bool) -> void:
	var c := r.get_center()
	var a := r.position.x if along_x else r.position.y
	var b := r.end.x if along_x else r.end.y
	var t := ceilf((a - 2.0) / 4.5) * 4.5 + 2.0
	while t < b:
		var p := Vector2(t, c.y) if along_x else Vector2(c.x, t)
		if not _in_crossing(p, along_x):
			_box(Vector3(p.x, 0.025, p.y), Vector3(1.8, 0.01, 0.14) if along_x else Vector3(0.14, 0.01, 1.8), WorldLayout.C_LINE, false, root)
		t += 4.5
	if edges:
		var half := (r.size.y if along_x else r.size.x) / 2 - 0.35
		for s in [-1.0, 1.0]:
			var off: float = s * half
			if along_x:
				_box(Vector3(c.x, 0.024, c.y + off), Vector3(r.size.x, 0.01, 0.1), WorldLayout.C_TRIM.darkened(0.1), false, root)
			else:
				_box(Vector3(c.x + off, 0.024, c.y), Vector3(0.1, 0.01, r.size.y), WorldLayout.C_TRIM.darkened(0.1), false, root)


func _in_crossing(p: Vector2, along_x: bool) -> bool:
	for i in layout.by_tile[tile].roads:
		var road: Dictionary = layout.roads[i]
		if road.kind == "acera" or road.kind == "camino":
			continue
		var rr: Rect2 = road.rect
		if (rr.size.x > rr.size.y) != along_x and rr.grow(1.5).has_point(p):
			return true
	return false


# ------------------------------------------------------------------ casas
func _house(h: Dictionary) -> void:
	rng.seed = h.seed
	var house := Node3D.new()
	house.name = "Casa"
	house.transform = Transform3D(Basis(Vector3.UP, h.yaw), Vector3(h.center.x, 0, h.center.y))
	root.add_child(house)
	var w: float = h.w
	var d: float = h.d
	var color: Color = h.color
	var x1 := -w / 2
	var x2 := w / 2
	var z1 := -d / 2
	var z2 := d / 2
	var side: float = h.side
	var px: float = h.px

	_box(Vector3(0, 0.015, 0), Vector3(w, 0.03, d), WorldLayout.C_FLOOR, false, house, 0.4, 2.5)
	_wall_x(house, x1, x2, z1, color, false, -1.0, 0.0)
	_wall_x(house, x1, x2, z2, color, true, 1.0, 0.0)
	_wall_z(house, z1, z2, x1, color, false, -1.0, 0.0)
	_wall_z(house, z1, z2, x2, color, false, 1.0, 0.0)
	# tabique interior con hueco de puerta, apartado de la puerta principal
	_wall_z(house, z1, z2, px, color.darkened(0.08), true, 0.0, 0.0)
	# escalón y puerta abierta
	_box(Vector3(0, 0.06, z2 + 0.55), Vector3(2.2, 0.12, 0.9), WorldLayout.C_WALK, false, house)
	var door := _box(Vector3(DOOR_W / 2 - 0.05, DOOR_H / 2, z2 + DOOR_W / 2), Vector3(0.06, DOOR_H - 0.05, DOOR_W - 0.1), WorldLayout.C_DARK_WOOD, false, house)
	door.rotation.y = rng.randf_range(-0.3, 0.2)
	if h.lamp:
		_porch_lamp(house, Vector3(1.3, DOOR_H + 0.2, z2 + 0.35))
	if rng.randf() < 0.5:
		_blood(Vector3(rng.randf_range(-1.0, 1.0), 0, z2 + rng.randf_range(0.8, 2.5)), 1.0, house)
	# mesa y silla volcada en la habitación grande
	var tx := -side * w * 0.12
	_box(Vector3(tx, 0.75, 0), Vector3(1.4, 0.06, 0.9), WorldLayout.C_WOOD, true, house)
	for lx in [-0.6, 0.6]:
		for lz in [-0.38, 0.38]:
			_box(Vector3(tx + lx, 0.36, lz), Vector3(0.06, 0.72, 0.06), WorldLayout.C_WOOD, false, house)
	var chair := _box(Vector3(tx + 0.3, 0.23, 0.9), Vector3(0.45, 0.06, 0.45), WorldLayout.C_WOOD, false, house)
	chair.rotation.z = PI / 2

	var floors: int = h.floors
	var upper: Node3D = null
	if floors == 2:
		upper = _upper_floor(house, h)
	var roof := _roof(house, w, d, h.roof, h.roof_h, WALL_H * floors)
	out_roofs.append({"rect": h.rect, "roof": roof, "upper": upper, "base": WALL_H * floors})


## Segunda planta: forjado con el hueco de la escalera, paredes con ventanas y la escalera.
func _upper_floor(house: Node3D, h: Dictionary) -> Node3D:
	var w: float = h.w
	var d: float = h.d
	var color: Color = (h.color as Color).lightened(0.04)
	var upper := Node3D.new()
	upper.name = "Piso2"
	upper.add_to_group("lote_propio")
	house.add_child(upper)
	var x1 := -w / 2
	var x2 := w / 2
	var z1 := -d / 2
	var z2 := d / 2
	var sx: float = h.stairs_x
	var z_start := z2 - 1.0
	var z_end := z_start - STAIR_RUN
	var hx1 := sx - 0.6
	var hx2 := sx + 0.6
	var y := WALL_H - 0.1
	# forjado en cuatro trozos alrededor del hueco
	_box(Vector3((x1 + hx1) / 2, y, 0), Vector3(hx1 - x1, 0.2, d), WorldLayout.C_FLOOR, true, upper, 0.4, 2.5)
	_box(Vector3((hx2 + x2) / 2, y, 0), Vector3(x2 - hx2, 0.2, d), WorldLayout.C_FLOOR, true, upper, 0.4, 2.5)
	_box(Vector3(sx, y, (z1 + z_end) / 2), Vector3(1.2, 0.2, z_end - z1), WorldLayout.C_FLOOR, true, upper, 0.4, 2.5)
	_box(Vector3(sx, y, (z_start + z2) / 2), Vector3(1.2, 0.2, z2 - z_start), WorldLayout.C_FLOOR, true, upper, 0.4, 2.5)
	_wall_x(upper, x1, x2, z1, color, false, -1.0, WALL_H)
	_wall_x(upper, x1, x2, z2, color, false, 1.0, WALL_H)
	_wall_z(upper, z1, z2, x1, color, false, -1.0, WALL_H)
	_wall_z(upper, z1, z2, x2, color, false, 1.0, WALL_H)
	# barandilla junto al hueco
	var rail_x := hx2 if sx < 0 else hx1
	_box(Vector3(rail_x, WALL_H + 0.5, (z_end + z_start) / 2 - 0.4), Vector3(0.06, 1.0, STAIR_RUN - 0.8), WorldLayout.C_DARK_WOOD, true, upper)
	# escalera: peldaños macizos y una rampa invisible para subir sin saltos
	var sd := STAIR_RUN / STAIR_STEPS
	var rise := WALL_H / STAIR_STEPS
	for i in STAIR_STEPS:
		var top := (i + 1) * rise
		_box(Vector3(sx, top / 2, z_start - (i + 0.5) * sd), Vector3(1.1, top, sd), WorldLayout.C_WOOD.darkened(0.1 * (i % 2)), false, house, 0.3, 2.0)
	var length := Vector2(STAIR_RUN, WALL_H).length()
	var ramp := StaticBody3D.new()
	ramp.position = Vector3(sx, WALL_H / 2 - 0.05, z_start + sd - STAIR_RUN / 2)
	ramp.rotation.x = atan2(WALL_H, STAIR_RUN)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 0.1, length)
	shape.shape = box
	ramp.add_child(shape)
	house.add_child(ramp)
	_collider_in(house, Vector3(sx, WALL_H - 0.1, z_end + sd / 2), Vector3(1.1, 0.2, sd))
	var rect: Rect2 = h.rect
	_uppers.append([rect, upper])
	return upper


func _porch_lamp(parent: Node3D, pos: Vector3) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = pos
	lamp.light_color = Color(1.0, 0.8, 0.5)
	lamp.light_energy = 0.0
	lamp.omni_range = 7.5
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = false
	lamp.add_to_group("night_lights")
	lamp.add_to_group("dynamic")
	parent.add_child(lamp)
	_box(pos + Vector3(0, 0.12, -0.05), Vector3(0.18, 0.22, 0.12), Color(0.2, 0.2, 0.2), false, parent)


func _roof(house: Node3D, w: float, d: float, color: Color, h: float, base: float) -> Node3D:
	var roof := Node3D.new()
	roof.name = "Tejado"
	roof.add_to_group("lote_propio")
	house.add_child(roof)
	var along_x := w >= d
	# el prisma tiene la cumbrera a lo largo de Z; si la casa es más ancha, se gira
	var mi := _shape({"kind": "prism", "size": Vector3((d if along_x else w) + 0.9, h, (w if along_x else d) + 0.9)}, [color, 0.5, 2.0])
	mi.position = Vector3(0, base + h / 2, 0)
	mi.rotation.y = PI / 2 if along_x else 0.0
	roof.add_child(mi)
	# techo plano bajo el tejado para tapar el hueco del muro
	_box(Vector3(0, base + 0.02, 0), Vector3(w + 0.1, 0.04, d + 0.1), color.darkened(0.3), false, roof)
	_box(Vector3(rng.randf_range(-w / 4, w / 4), base + h * 0.75, rng.randf_range(-0.6, 0.6)), Vector3(0.6, h * 1.1, 0.6), Color(0.45, 0.3, 0.26), false, roof)
	return roof


## Pared a lo largo de X en z fija. `out` es hacia dónde mira el exterior (+1/-1).
func _wall_x(parent: Node3D, x1: float, x2: float, z: float, color: Color, door: bool, out: float, y0: float, h := WALL_H, door_w := DOOR_W) -> void:
	for s in _segments(x1, x2, door, door_w):
		_box(Vector3((s.x + s.y) / 2, y0 + h / 2, z), Vector3(s.y - s.x, h, WALL_T), color, true, parent, 0.35, 1.5)
		_windows_along(parent, s.x, s.y, func(a: float) -> Vector3: return Vector3(a, y0, z), true, out)
	if door:
		var c := (x1 + x2) / 2
		_box(Vector3(c, y0 + (DOOR_H + h) / 2, z), Vector3(door_w, h - DOOR_H, WALL_T), color, true, parent)
		if out != 0.0:
			_door_frame(parent, Vector3(c, y0, z), true, door_w)
	if out != 0.0:
		_box(Vector3((x1 + x2) / 2, y0 + h - 0.08, z), Vector3(x2 - x1 + 0.1, 0.16, WALL_T + 0.08), WorldLayout.C_TRIM, false, parent)


func _wall_z(parent: Node3D, z1: float, z2: float, x: float, color: Color, door: bool, out: float, y0: float, h := WALL_H, door_w := DOOR_W) -> void:
	for s in _segments(z1, z2, door, door_w):
		_box(Vector3(x, y0 + h / 2, (s.x + s.y) / 2), Vector3(WALL_T, h, s.y - s.x), color, true, parent, 0.35, 1.5)
		if out != 0.0:
			_windows_along(parent, s.x, s.y, func(a: float) -> Vector3: return Vector3(x, y0, a), false, out)
	if door:
		var c := (z1 + z2) / 2
		_box(Vector3(x, y0 + (DOOR_H + h) / 2, c), Vector3(WALL_T, h - DOOR_H, door_w), color, true, parent)
		if out != 0.0:
			_door_frame(parent, Vector3(x, y0, c), false, door_w)
	if out != 0.0:
		_box(Vector3(x, y0 + h - 0.08, (z1 + z2) / 2), Vector3(WALL_T + 0.08, 0.16, z2 - z1 + 0.1), WorldLayout.C_TRIM, false, parent)


## Tramos de pared, dejando hueco para la puerta en el centro.
func _segments(a: float, b: float, door: bool, door_w := DOOR_W) -> Array[Vector2]:
	if not door:
		return [Vector2(a, b)]
	var c := (a + b) / 2
	return [Vector2(a, c - door_w / 2), Vector2(c + door_w / 2, b)]


## Ventanas pegadas por fuera y por dentro de un tramo de pared.
func _windows_along(parent: Node3D, a: float, b: float, at: Callable, along_x: bool, out: float) -> void:
	var length := b - a
	if length < 2.6 or out == 0.0:
		return
	var count := int(length / 3.2)
	for i in count:
		var center := a + length * (i + 0.5) / count
		var base: Vector3 = at.call(center)
		for side in [out, -out]:
			var off: float = (WALL_T / 2 + 0.02) * side
			var p := base + (Vector3(0, 0, off) if along_x else Vector3(off, 0, 0))
			var glass_size := Vector3(1.0, 1.1, 0.03) if along_x else Vector3(0.03, 1.1, 1.0)
			var frame_size := Vector3(1.2, 1.3, 0.05) if along_x else Vector3(0.05, 1.3, 1.2)
			var sill_size := Vector3(1.35, 0.08, 0.16) if along_x else Vector3(0.16, 0.08, 1.35)
			_box(p + Vector3(0, 1.55, 0), frame_size, WorldLayout.C_TRIM, false, parent)
			_box(p + Vector3(0, 1.55, 0) + (Vector3(0, 0, 0.02 * side) if along_x else Vector3(0.02 * side, 0, 0)), glass_size, WorldLayout.C_GLASS, false, parent, 0.0)
			_box(p + Vector3(0, 0.88, 0), sill_size, WorldLayout.C_TRIM, false, parent)
			# tablones clavados en algunas ventanas exteriores
			if side == out and rng.randf() < 0.35:
				for k in 2:
					var plank := _box(p + Vector3(0, 1.4 + k * 0.35, 0) + (Vector3(0, 0, 0.05 * side) if along_x else Vector3(0.05 * side, 0, 0)),
						Vector3(1.3, 0.14, 0.04) if along_x else Vector3(0.04, 0.14, 1.3), WorldLayout.C_WOOD, false, parent)
					plank.rotation = Vector3(0, 0, rng.randf_range(-0.25, 0.25)) if along_x else Vector3(rng.randf_range(-0.25, 0.25), 0, 0)


func _door_frame(parent: Node3D, base: Vector3, along_x: bool, door_w := DOOR_W) -> void:
	var t := WALL_T + 0.1
	for s in [-1.0, 1.0]:
		var p := base + (Vector3(s * (door_w / 2 + 0.05), DOOR_H / 2, 0) if along_x else Vector3(0, DOOR_H / 2, s * (door_w / 2 + 0.05)))
		_box(p, Vector3(0.1, DOOR_H, t) if along_x else Vector3(t, DOOR_H, 0.1), WorldLayout.C_TRIM, false, parent)
	_box(base + Vector3(0, DOOR_H + 0.05, 0), Vector3(door_w + 0.2, 0.1, t) if along_x else Vector3(t, 0.1, door_w + 0.2), WorldLayout.C_TRIM, false, parent)


# ------------------------------------------------------------------ edificios grandes
func _hall(h: Dictionary) -> void:
	rng.seed = h.seed
	var node := Node3D.new()
	node.name = String(h.kind).capitalize()
	node.transform = Transform3D(Basis(Vector3.UP, h.yaw), Vector3(h.center.x, 0, h.center.y))
	root.add_child(node)
	var w: float = h.w
	var d: float = h.d
	var hh: float = h.h
	var color: Color = h.color
	var door_w: float = h.door_w
	_box(Vector3(0, 0.015, 0), Vector3(w, 0.03, d), WorldLayout.C_CONCRETE.darkened(0.15), false, node, 0.3, 2.5)
	_wall_x(node, -w / 2, w / 2, -d / 2, color, false, -1.0, 0.0, hh)
	_wall_z(node, -d / 2, d / 2, -w / 2, color, false, -1.0, 0.0, hh)
	_wall_z(node, -d / 2, d / 2, w / 2, color, false, 1.0, 0.0, hh)
	if h.kind == "supermercado" or h.kind == "tienda":
		_shop_front(node, w, d, hh, color, door_w)
	else:
		_wall_x(node, -w / 2, w / 2, d / 2, color, true, 1.0, 0.0, hh, door_w)
	for wall in h.walls:
		_partition(node, wall[0], wall[1], wall[2], hh, color.darkened(0.1))
	# rótulo sobre la puerta
	if h.kind != "granero":
		_box(Vector3(0, hh - 0.45, d / 2 + 0.2), Vector3(minf(w * 0.6, 9.0), 0.75, 0.12), WorldLayout.C_TRIM, false, node)
		var sign := Node3D.new()
		sign.name = "Rotulo"
		sign.set_meta("sign_text", String(h.name).to_upper())
		sign.position = Vector3(0, hh - 0.45, d / 2 + 0.27)
		node.add_child(sign)
		if real_meshes:
			_make_sign(sign)
	if rng.randf() < 0.7:
		_blood(Vector3(rng.randf_range(-2.0, 2.0), 0, d / 2 + rng.randf_range(0.8, 3.0)), 1.2, node)
	var roof: Node3D
	if h.kind == "granero":
		roof = _roof(node, w, d, Color(0.3, 0.26, 0.24), 2.6, hh)
	else:
		roof = Node3D.new()
		roof.name = "Tejado"
		roof.add_to_group("lote_propio")
		node.add_child(roof)
		_box(Vector3(0, hh + 0.1, 0), Vector3(w + 0.3, 0.2, d + 0.3), color.darkened(0.35), false, roof)
		for s in [-1.0, 1.0]:
			_box(Vector3(0, hh + 0.45, s * (d / 2 + 0.1)), Vector3(w + 0.3, 0.5, 0.15), color.darkened(0.1), false, roof)
			_box(Vector3(s * (w / 2 + 0.1), hh + 0.45, 0), Vector3(0.15, 0.5, d + 0.3), color.darkened(0.1), false, roof)
		# aparatos en la azotea
		_box(Vector3(rng.randf_range(-w / 4, w / 4), hh + 0.6, rng.randf_range(-d / 4, d / 4)), Vector3(1.6, 0.8, 1.0), WorldLayout.C_METAL, false, roof)
	out_roofs.append({"rect": h.rect, "roof": roof, "upper": null, "base": hh})


## Fachada de tienda: cristaleras grandes a los lados de la puerta.
func _shop_front(node: Node3D, w: float, d: float, hh: float, color: Color, door_w: float) -> void:
	var z := d / 2
	for s in [-1.0, 1.0]:
		var a: float = door_w / 2 if s > 0 else -w / 2
		var b: float = w / 2 if s > 0 else -door_w / 2
		var cx := (a + b) / 2
		var span := b - a
		# murete, cristal y dintel
		_box(Vector3(cx, 0.35, z), Vector3(span, 0.7, WALL_T), color, true, node)
		_box(Vector3(cx, 1.6, z), Vector3(span - 0.2, 1.8, 0.06), WorldLayout.C_GLASS, true, node, 0.0)
		_box(Vector3(cx, (2.5 + hh) / 2, z), Vector3(span, hh - 2.5, WALL_T), color, true, node)
		var n := int(span / 2.5)
		for k in n + 1:
			_box(Vector3(a + span * k / maxf(n, 1), 1.6, z), Vector3(0.12, 1.8, WALL_T + 0.04), WorldLayout.C_TRIM, false, node)
		# cristales rotos en el suelo
		if rng.randf() < 0.6:
			_box(Vector3(cx + rng.randf_range(-1, 1), 0.02, z + 0.8), Vector3(1.2, 0.02, 0.8), WorldLayout.C_GLASS.lightened(0.2), false, node)
	_box(Vector3(0, (DOOR_H + hh) / 2, z), Vector3(door_w, hh - DOOR_H, WALL_T), color, true, node)
	_door_frame(node, Vector3(0, 0, z), true, door_w)


## Tabique interior de a a b (local, alineado con un eje) con huecos de puerta.
func _partition(node: Node3D, a: Vector2, b: Vector2, doors: Array, hh: float, color: Color) -> void:
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var from := minf(a.x, b.x) if along_x else minf(a.y, b.y)
	var to := maxf(a.x, b.x) if along_x else maxf(a.y, b.y)
	var cuts: Array[float] = []
	for dc in doors:
		cuts.append(float(dc))
	cuts.sort()
	var pieces: Array[Vector2] = []
	var start := from
	for dc in cuts:
		pieces.append(Vector2(start, dc - DOOR_W / 2))
		start = dc + DOOR_W / 2
	pieces.append(Vector2(start, to))
	for p in pieces:
		if p.y - p.x < 0.05:
			continue
		var c := (p.x + p.y) / 2
		if along_x:
			_box(Vector3(c, hh / 2, a.y), Vector3(p.y - p.x, hh, WALL_T * 0.8), color, true, node, 0.35, 1.5)
		else:
			_box(Vector3(a.x, hh / 2, c), Vector3(WALL_T * 0.8, hh, p.y - p.x), color, true, node, 0.35, 1.5)
	for dc in cuts:
		if along_x:
			_box(Vector3(dc, (DOOR_H + hh) / 2, a.y), Vector3(DOOR_W, hh - DOOR_H, WALL_T * 0.8), color, true, node)
		else:
			_box(Vector3(a.x, (DOOR_H + hh) / 2, dc), Vector3(WALL_T * 0.8, hh - DOOR_H, DOOR_W), color, true, node)


func _make_sign(at: Node3D) -> void:
	var label := Label3D.new()
	label.text = at.get_meta("sign_text")
	label.font = FONT_SIGN
	label.font_size = 96
	label.outline_size = 0
	label.modulate = Color(0.12, 0.11, 0.12)
	label.pixel_size = 0.005
	at.remove_meta("sign_text")
	at.add_child(label)


# ------------------------------------------------------------------ muebles
func _container(idx: int) -> void:
	var c: Dictionary = layout.containers[idx]
	var size: Vector3 = c.size
	var color: Color = c.color
	var parent := _parent_for(c.pos)
	var body := StaticBody3D.new()
	body.name = "Mueble%d" % idx
	body.transform = _local_in(parent, Transform3D(Basis(Vector3.UP, c.rot), c.pos))
	body.add_to_group("dynamic")
	body.add_to_group(nav_group(tile))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh: MeshInstance3D
	if c.type == "bidon":
		mesh = _cyl_mesh(Vector3.ZERO, size.x / 2, size.x / 2, size.y, color, body)
		_cyl_mesh(Vector3(0, size.y / 2 + 0.02, 0), size.x / 2 - 0.05, size.x / 2 - 0.05, 0.04, color.darkened(0.3), body)
	else:
		mesh = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mesh.mesh = bm
		_set_look(mesh, [color, 0.2, 3.0])
		body.add_child(mesh)
		# detalles: tiradores, baldas
		if c.type in ["armario", "taquilla", "armero", "nevera", "botiquin"]:
			_box(Vector3(size.x * 0.25, 0, size.z / 2 + 0.02), Vector3(0.05, 0.25, 0.03), WorldLayout.C_METAL.darkened(0.4), false, body)
		elif c.type == "estanteria_tienda" or c.type == "estanteria":
			for k in 3:
				_box(Vector3(0, -size.y / 2 + 0.35 + k * size.y / 3.2, size.z / 2 + 0.01), Vector3(size.x * 0.9, 0.18, 0.04), Color(0.55, 0.45, 0.3).lerp(Color(0.4, 0.45, 0.5), k / 2.0), false, body)
	parent.add_child(body)
	out_containers.append([idx, body, mesh])


## Lo que va en el piso de arriba cuelga de esa planta (así se oculta con ella).
func _parent_for(p: Vector3) -> Node3D:
	if p.y > WALL_H - 0.3:
		for u in _uppers:
			if (u[0] as Rect2).has_point(Vector2(p.x, p.z)):
				return u[1]
	return root


func _local_in(parent: Node3D, xf: Transform3D) -> Transform3D:
	if parent == root:
		return xf
	return _rel(parent).affine_inverse() * xf


func _prop(p: Dictionary) -> void:
	var color: Color = p.color
	var size: Vector3 = p.size
	var parent := _parent_for(p.pos)
	var xf := _local_in(parent, Transform3D(Basis.from_euler(Vector3(p.tilt, p.yaw, 0)), p.pos))
	if p.shape == "cyl":
		var mi := _cyl_mesh(Vector3.ZERO, size.x / 2, size.z / 2, size.y, color, parent)
		mi.transform = xf
		if p.collide:
			var body := StaticBody3D.new()
			body.transform = xf
			var shape := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = size.x / 2
			cyl.height = size.y
			shape.shape = cyl
			body.add_child(shape)
			parent.add_child(body)
	else:
		var n := _box(Vector3.ZERO, size, color, p.collide, parent)
		n.transform = xf


func _fence(f: Dictionary) -> void:
	var a: Vector3 = f.a
	var b: Vector3 = f.b
	var length := a.distance_to(b)
	var dir := (b - a) / maxf(length, 0.01)
	var yaw := atan2(-dir.z, dir.x)
	var gap := length / 2 if f.gap else -100.0
	rng.seed = hash(a)
	var t := 0.0
	while t <= length:
		if absf(t - gap) > 1.3 and rng.randf() < 0.92:
			var post := _box(a + dir * t + Vector3(0, 0.5, 0), Vector3(0.09, 1.0, 0.09), WorldLayout.C_TRIM.darkened(0.15), true, root)
			post.rotation = Vector3(0, yaw, rng.randf_range(-0.08, 0.08))
		t += 0.45
	var spans: Array[Vector2] = []
	if f.gap:
		spans.append(Vector2(0, gap - 1.3))
		spans.append(Vector2(gap + 1.3, length))
	else:
		spans.append(Vector2(0, length))
	for s in spans:
		if s.y - s.x < 0.2:
			continue
		for y in [0.35, 0.8]:
			var rail := _box(a + dir * (s.x + s.y) / 2 + Vector3(0, y, 0), Vector3(s.y - s.x, 0.07, 0.04), WorldLayout.C_TRIM.darkened(0.2), false, root)
			rail.rotation.y = yaw


# ------------------------------------------------------------------ postes, coches, árboles
func _pole(p: Dictionary) -> void:
	rng.seed = hash(p.pos)
	var base: Vector3 = p.pos
	var h := 7.0
	var pole := _cyl_body(base, 0.11, 0.14, h, WorldLayout.C_DARK_WOOD.lightened(0.1))
	pole.rotation.z = rng.randf_range(-0.03, 0.03)
	# travesaño perpendicular a la línea
	var across := Vector3(0, 0, 1) if p.along_x else Vector3(1, 0, 0)
	_box(base + Vector3(0, h - 0.5, 0), Vector3(0.12, 0.12, 1.8) if p.along_x else Vector3(1.8, 0.12, 0.12), WorldLayout.C_DARK_WOOD, false, root)
	if rng.randf() < 0.3:
		_cyl_mesh(base + Vector3(0.3, h - 1.4, 0), 0.25, 0.25, 0.7, WorldLayout.C_METAL, root)
	var top := base + Vector3(0, h - 0.45, 0)
	var prev: Vector3 = p.prev
	if prev != Vector3.INF:
		var prev_top := prev + Vector3(0, h - 0.45, 0)
		for k in [-0.7, 0.0, 0.7]:
			_wire(prev_top + across * k, top + across * k)


func _wire(a: Vector3, b: Vector3) -> void:
	# dos tramos para que el cable cuelgue
	var mid := (a + b) / 2 + Vector3(0, -0.6, 0)
	for pair in [[a, mid], [mid, b]]:
		var p: Vector3 = pair[0]
		var q: Vector3 = pair[1]
		var mi := _shape({"kind": "box", "size": Vector3(0.025, 0.025, p.distance_to(q))}, [Color(0.08, 0.08, 0.08), 0.0, 1.6])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(Basis.looking_at(q - p, Vector3.UP), (p + q) / 2)
		root.add_child(mi)


func _car(spec: Dictionary) -> void:
	rng.seed = spec.seed
	var color: Color = spec.color
	var car := Node3D.new()
	car.name = "Coche"
	# cada coche se fusiona aparte: al desmontarlo desaparece entero
	car.add_to_group("lote_propio")
	car.transform = Transform3D(Basis(Vector3.UP, spec.yaw), spec.pos)
	root.add_child(car)
	var body := _box(Vector3(0, 0.62, 0), Vector3(4.2, 0.62, 1.8), color, true, car, 0.2, 3.0)
	body.add_to_group("dynamic")
	body.add_to_group(nav_group(tile))
	out_containers.append([spec.cont, body, body.get_child(1)])
	# cabina con ventanillas oscuras y techo
	_box(Vector3(-0.25, 1.17, 0), Vector3(2.1, 0.5, 1.62), WorldLayout.C_GLASS, false, car, 0.0)
	_box(Vector3(-0.25, 1.44, 0), Vector3(2.0, 0.06, 1.66), color, false, car)
	for s in [-1.0, 1.0]:
		_box(Vector3(-0.25, 1.17, s * 0.8), Vector3(0.08, 0.5, 0.05), color, false, car)
		_box(Vector3(2.1, 0.72, s * 0.62), Vector3(0.04, 0.16, 0.32), Color(0.95, 0.92, 0.8), false, car, 0.0)
		_box(Vector3(-2.1, 0.72, s * 0.62), Vector3(0.04, 0.14, 0.3), Color(0.6, 0.05, 0.03), false, car, 0.0)
	_box(Vector3(2.12, 0.45, 0), Vector3(0.12, 0.16, 1.85), WorldLayout.C_METAL, false, car)
	_box(Vector3(-2.12, 0.45, 0), Vector3(0.12, 0.16, 1.85), WorldLayout.C_METAL, false, car)
	for wx in [-1.35, 1.35]:
		for wz in [-0.85, 0.85]:
			var wheel := _cyl_mesh(Vector3(wx, 0.36, wz), 0.36, 0.36, 0.26, Color(0.1, 0.1, 0.1), car)
			wheel.rotation.x = PI / 2
	if spec.door:
		# puerta del conductor abierta, girando sobre la bisagra delantera
		var a := 0.9
		var hinge := Vector3(0.85, 0, 0.9)
		var center := hinge + Vector3(-0.5 * cos(a), 0, 0.5 * sin(a))
		var door := _box(center + Vector3(0, 0.66, 0), Vector3(1.0, 0.62, 0.06), color, false, car)
		door.rotation.y = a
		var window := _box(center + Vector3(0, 1.15, 0), Vector3(0.9, 0.36, 0.04), WorldLayout.C_GLASS, false, car, 0.0)
		window.rotation.y = a
	if spec.blood:
		_blood(Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2)), 1.3, car)


func _tree(pos: Vector3) -> void:
	var trunk_h := rng.randf_range(2.2, 3.6)
	_cyl_body(pos, 0.16, 0.26, trunk_h, Color(0.3, 0.23, 0.17))
	var crown_col := Color(0.3, 0.36, 0.26).lerp(Color(0.42, 0.4, 0.26), rng.randf())
	for i in 3:
		var r := rng.randf_range(1.0, 1.8)
		var off := Vector3(rng.randf_range(-0.7, 0.7), trunk_h + r * 0.5 + i * 0.35, rng.randf_range(-0.7, 0.7))
		var crown := _sphere_mesh(pos + off, r, crown_col.darkened(i * 0.05), root)
		crown.scale = Vector3(1, rng.randf_range(0.8, 1.0), 1)


func _dead_tree(pos: Vector3) -> void:
	# árbol seco: tronco y ramas sueltas, muy de silueta de cómic
	var h := rng.randf_range(3.0, 4.8)
	_cyl_body(pos, 0.08, 0.2, h, Color(0.22, 0.18, 0.15))
	for i in rng.randi_range(4, 7):
		var y := rng.randf_range(h * 0.45, h * 0.95)
		var length := rng.randf_range(0.8, 1.8) * (1.2 - y / h)
		var branch := _cyl_mesh(Vector3.ZERO, 0.02, 0.06, length, Color(0.22, 0.18, 0.15), root)
		var yaw := rng.randf_range(0, TAU)
		var tilt := rng.randf_range(0.5, 1.1)
		branch.position = pos + Vector3(0, y, 0) + Vector3(sin(yaw), 0, cos(yaw)) * sin(tilt) * length / 2 + Vector3(0, cos(tilt) * length / 2, 0)
		branch.rotation = Vector3(tilt * cos(yaw), 0, -tilt * sin(yaw))


func _debris() -> void:
	# bolsas de basura, cajas, neumáticos y sangre
	var r := WorldLayout.tile_rect(tile)
	var town := r.intersects(Rect2(-WorldLayout.TOWN, -WorldLayout.TOWN, WorldLayout.TOWN * 2, WorldLayout.TOWN * 2))
	for i in (40 if town else 10):
		var p := Vector3(rng.randf_range(r.position.x + 1, r.end.x - 1), 0, rng.randf_range(r.position.y + 1, r.end.y - 1))
		if layout.in_footprint(p.x, p.z, 0.6):
			continue
		match rng.randi() % 4:
			0:
				var bag := _sphere_mesh(p + Vector3(0, 0.22, 0), 0.32, Color(0.12, 0.13, 0.12), root)
				bag.scale = Vector3(1, 0.75, 0.9)
			1:
				var crate := _box(p + Vector3(0, 0.25, 0), Vector3(0.6, 0.5, 0.6), WorldLayout.C_WOOD.lightened(0.1), true, root, 0.4, 3.0)
				crate.rotation.y = rng.randf_range(0, PI)
			2:
				var tire := _cyl_mesh(p + Vector3(0, 0.12, 0), 0.34, 0.34, 0.22, Color(0.09, 0.09, 0.09), root)
				tire.rotation.x = rng.randf_range(-0.1, 0.1)
			3:
				_blood(p, rng.randf_range(0.6, 1.4), root)


# ------------------------------------------------------------------ lugares hechos a mano
func _prefab(p: Dictionary) -> void:
	var scene: PackedScene = load(p.scene)
	var inst := scene.instantiate() as Node3D
	inst.transform = Transform3D(Basis(Vector3.UP, p.yaw), p.pos)
	root.add_child(inst)
	# los materiales del editor pasan a tinta de cómic
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		var m: Material = mi.material_override
		if m == null and mi.mesh:
			m = mi.get_surface_override_material(0)
			if m == null:
				m = mi.mesh.surface_get_material(0)
		var color := Color(0.6, 0.6, 0.6)
		if m is BaseMaterial3D:
			color = (m as BaseMaterial3D).albedo_color
		if not (m is ShaderMaterial):
			mi.material_override = null
			_set_look(mi, [color, 0.35, 1.6])
	for n in inst.find_children("*", "Marker3D", true, false):
		n.free()
	var roof := inst.get_node_or_null("Tejado") as Node3D
	if roof:
		roof.add_to_group("lote_propio")
		var rect := Rect2()
		var first := true
		for mi: MeshInstance3D in roof.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = _rel(mi) * mi.get_aabb()
			var r2 := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
			rect = r2 if first else rect.merge(r2)
			first = false
		out_roofs.append({"rect": rect.grow(-0.4), "roof": roof, "upper": null, "base": 2.0})


# ------------------------------------------------------------------ fusión de geometría
## Une todas las piezas que no cambian en pocas mallas grandes, y sus colisiones
## en un solo cuerpo por zona. Lo que cambia en juego va aparte:
##   "dynamic": muebles registrables, luces → se quedan tal cual
##   "lote_propio": tejados, plantas de arriba, coches → se fusionan por separado
func _batch() -> void:
	var batcher := MeshBatcher.new()
	var own := {}
	var to_free: Array[Node] = []
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var owner_node := _batch_owner(mi)
		var shape: Dictionary = mi.get_meta("shape", {})
		if shape.is_empty() and mi.mesh is PrimitiveMesh:
			shape = _shape_of(mi.mesh)
		if owner_node == null:
			# no se fusiona: necesita su malla de verdad
			if mi.mesh == null and not shape.is_empty():
				mi.mesh = _make_mesh(shape)
			continue
		var look: Array = mi.get_meta("look", [])
		var mat := mi.material_override as ShaderMaterial
		if look.is_empty() and mat:
			look = [mat.get_shader_parameter("albedo"), mat.get_shader_parameter("grit"), mat.get_shader_parameter("grit_scale")]
		if look.is_empty() or (mi.mesh == null and shape.is_empty()):
			continue
		var albedo: Color = look[0]
		var grit: float = look[1]
		var grit_scale: float = look[2]
		var bmat: Variant = _batch_mat(grit, grit_scale) if real_meshes else Vector2(grit, grit_scale)
		var xf := _rel(mi)
		var arrays: Array
		if shape.is_empty():
			arrays = mi.mesh.surface_get_arrays(0)
		else:
			var unit := _unit(shape)
			arrays = unit[0]
			xf = xf * Transform3D(Basis.from_scale(unit[1]), Vector3.ZERO)
		if owner_node == root:
			var chunk := Vector2i(floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK))
			batcher.add_arrays(arrays, xf, [chunk, grit, grit_scale, mi.cast_shadow], bmat, albedo, mi.cast_shadow)
		else:
			if not own.has(owner_node):
				own[owner_node] = MeshBatcher.new()
			xf = _rel(owner_node).affine_inverse() * xf
			(own[owner_node] as MeshBatcher).add_arrays(arrays, xf, [grit, grit_scale, mi.cast_shadow], bmat, albedo, mi.cast_shadow)
		to_free.append(mi)

	var col := StaticBody3D.new()
	col.name = "Colision"
	col.add_to_group(nav_group(tile))
	for body: StaticBody3D in root.find_children("*", "StaticBody3D", true, false):
		if _is_dynamic(body):
			continue
		var bx := _rel(body)
		for cs in body.get_children():
			if cs is CollisionShape3D:
				var xf: Transform3D = bx * (cs as CollisionShape3D).transform
				body.remove_child(cs)
				cs.owner = null
				col.add_child(cs)
				cs.transform = xf
		to_free.append(body)
	root.add_child(col)

	var geo := Node3D.new()
	geo.name = "Geometria"
	root.add_child(geo)
	batcher.build(geo, "Trozo")
	for n in own:
		(own[n] as MeshBatcher).build(n, "Lote")
	for n in to_free:
		if is_instance_valid(n):
			n.free()


## Quién se queda la malla: la zona (null si es dinámica y no se fusiona).
func _batch_owner(n: Node) -> Node3D:
	while n != null and n != root:
		if n.is_in_group("dynamic"):
			return null
		if n.is_in_group("lote_propio"):
			return n as Node3D
		n = n.get_parent()
	return root


func _is_dynamic(n: Node) -> bool:
	while n != null and n != root:
		if n.is_in_group("dynamic"):
			return true
		n = n.get_parent()
	return false


## Transformación respecto a la raíz de la zona (sirve fuera del árbol).
func _rel(n: Node) -> Transform3D:
	var xf := Transform3D()
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _batch_mat(grit: float, grit_scale: float) -> ShaderMaterial:
	var key := Vector2(grit, grit_scale)
	if not _batch_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = TOON
		m.set_shader_parameter("albedo", Color.WHITE)
		m.set_shader_parameter("grit", grit)
		m.set_shader_parameter("grit_scale", grit_scale)
		_batch_mats[key] = m
	return _batch_mats[key]


# ------------------------------------------------------------------ utilidades
func _mat(color: Color, grit := 0.35, grit_scale := 1.6) -> ShaderMaterial:
	var key := [color, grit, grit_scale]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = TOON
		m.set_shader_parameter("albedo", color)
		m.set_shader_parameter("grit", grit)
		m.set_shader_parameter("grit_scale", grit_scale)
		_materials[key] = m
	return _materials[key]


## Pieza con una forma: {kind: box|prism|sphere|cyl, …}. Se apunta la forma para
## fusionarla; la malla de verdad solo se crea si hace falta.
func _shape(shape: Dictionary, look: Array) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.set_meta("shape", shape)
	_set_look(mi, look)
	if real_meshes:
		mi.mesh = _make_mesh(shape)
	return mi


## Aspecto de una pieza: [color, grano, escala del grano]. En el hilo no se crean
## materiales (el servidor de render se bloquearía): se ponen luego en finalize().
func _set_look(mi: MeshInstance3D, look: Array) -> void:
	mi.set_meta("look", look)
	if real_meshes:
		mi.material_override = _mat(look[0], look[1], look[2])


## Ya en el hilo principal: materiales y rótulos de una zona recién construida.
func finalize(node: Node3D) -> void:
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("batch_mat"):
			var k: Vector2 = mi.get_meta("batch_mat")
			mi.material_override = _batch_mat(k.x, k.y)
		elif mi.material_override == null and mi.has_meta("look"):
			var look: Array = mi.get_meta("look")
			mi.material_override = _mat(look[0], look[1], look[2])
	for n in node.find_children("Rotulo*", "Node3D", true, false):
		if n.has_meta("sign_text"):
			_make_sign(n)


func _make_mesh(shape: Dictionary) -> Mesh:
	match shape.kind:
		"prism":
			var m := PrismMesh.new()
			m.size = shape.size
			return m
		"sphere":
			var m := SphereMesh.new()
			m.radius = shape.r
			m.height = shape.r * 2.0
			m.radial_segments = 10
			m.rings = 5
			return m
		"cyl":
			var m := CylinderMesh.new()
			m.top_radius = shape.top
			m.bottom_radius = shape.bottom
			m.height = shape.h
			m.radial_segments = 10
			m.rings = 1
			return m
	var b := BoxMesh.new()
	b.size = shape.size
	return b


## Forma unidad y escala que la convierte en esta pieza.
func _unit(shape: Dictionary) -> Array:
	match shape.kind:
		"prism":
			return [_units.prism, shape.size]
		"sphere":
			return [_units.sphere, Vector3.ONE * shape.r]
		"cyl":
			var bottom: float = maxf(shape.bottom, 0.001)
			var k := clampi(roundi(shape.top / bottom * 10.0), 0, 10)
			return [_units["cyl%d" % k], Vector3(bottom, shape.h, bottom)]
	return [_units.box, shape.size]


## Forma de una malla primitiva hecha en el editor (lugares .tscn).
func _shape_of(m: PrimitiveMesh) -> Dictionary:
	if m is BoxMesh:
		return {"kind": "box", "size": (m as BoxMesh).size}
	if m is PrismMesh and is_equal_approx((m as PrismMesh).left_to_right, 0.5):
		return {"kind": "prism", "size": (m as PrismMesh).size}
	if m is SphereMesh:
		return {"kind": "sphere", "r": (m as SphereMesh).radius}
	if m is CylinderMesh:
		var c := m as CylinderMesh
		if c.top_radius <= c.bottom_radius:
			return {"kind": "cyl", "top": c.top_radius, "bottom": c.bottom_radius, "h": c.height}
	return {}


## Caja con malla y (opcional) colisión. Devuelve el nodo creado.
func _box(pos: Vector3, size: Vector3, color: Color, collide: bool, parent: Node3D, grit := 0.35, grit_scale := 1.6) -> Node3D:
	var mesh := _shape({"kind": "box", "size": size}, [color, grit, grit_scale])
	if not collide:
		mesh.position = pos
		parent.add_child(mesh)
		return mesh
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	body.add_child(mesh)
	parent.add_child(body)
	return body


func _collider_in(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	parent.add_child(body)


func _cyl_mesh(pos: Vector3, top: float, bottom: float, h: float, color: Color, parent: Node3D) -> MeshInstance3D:
	var mi := _shape({"kind": "cyl", "top": top, "bottom": bottom, "h": h}, [color, 0.3, 4.0])
	mi.position = pos
	parent.add_child(mi)
	return mi


## Cilindro vertical con colisión apoyado en el suelo (troncos, postes).
func _cyl_body(base: Vector3, top: float, bottom: float, h: float, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = base
	root.add_child(body)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = bottom
	cyl.height = h
	shape.shape = cyl
	shape.position.y = h / 2
	body.add_child(shape)
	_cyl_mesh(Vector3(0, h / 2, 0), top, bottom, h, color, body)
	return body


func _sphere_mesh(pos: Vector3, r: float, color: Color, parent: Node3D) -> MeshInstance3D:
	var mi := _shape({"kind": "sphere", "r": r}, [color, 0.5, 2.5])
	mi.position = pos
	parent.add_child(mi)
	return mi


## Mancha plana en el suelo (tierra, charcos).
func _disc(pos: Vector3, r: float, color: Color, squash: float, parent: Node3D) -> MeshInstance3D:
	var mi := _cyl_mesh(pos, r, r, 0.008, color, parent)
	mi.scale = Vector3(1, 1, squash)
	mi.rotation.y = rng.randf_range(0, PI)
	_set_look(mi, [color, 0.6, 1.2])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Salpicadura de sangre: una mancha grande y gotas alrededor. El único rojo vivo del pueblo.
func _blood(pos: Vector3, size: float, parent: Node3D) -> void:
	var y := 0.07
	_disc(Vector3(pos.x, y, pos.z), 0.55 * size, WorldLayout.C_BLOOD, rng.randf_range(0.5, 0.9), parent)
	for i in rng.randi_range(3, 7):
		var a := rng.randf_range(0, TAU)
		var d := rng.randf_range(0.5, 1.4) * size
		_disc(Vector3(pos.x + cos(a) * d, y + 0.001, pos.z + sin(a) * d), rng.randf_range(0.06, 0.18) * size, WorldLayout.C_BLOOD, rng.randf_range(0.6, 1.0), parent)
	# rastro de arrastre
	if size >= 0.6 and rng.randf() < 0.5:
		var a := rng.randf_range(0, TAU)
		var trail := _box(Vector3(pos.x + cos(a) * size, y, pos.z + sin(a) * size), Vector3(0.35 * size, 0.008, 2.0 * size), WorldLayout.C_BLOOD, false, parent, 0.7, 2.0)
		trail.rotation.y = -a + PI / 2
		(trail as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
