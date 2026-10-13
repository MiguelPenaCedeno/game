extends Node3D
## Pueblo provisional generado por código.
## Se genera con una semilla fija para que todos los jugadores vean el mismo
## mapa. Más adelante muchas piezas se sustituirán por modelos .glb.

const TOON := preload("res://shaders/toon.gdshader")

const SEED := 1993
const HALF := 70.0
const ROADS: Array[float] = [-40.0, 0.0, 40.0]
const ROAD_W := 8.0
const WALK_W := 1.8
const WALL_H := 2.8
const WALL_T := 0.25
const DOOR_W := 1.6
const DOOR_H := 2.2

# Paleta: grises verdosos y ocres apagados; el rojo se reserva para la sangre.
const PAPER := Color(0.93, 0.9, 0.82)
const C_GRASS := Color(0.42, 0.45, 0.33)
const C_DIRT := Color(0.42, 0.37, 0.29)
const C_ROAD := Color(0.27, 0.27, 0.28)
const C_WALK := Color(0.58, 0.57, 0.53)
const C_LINE := Color(0.82, 0.76, 0.5)
const C_FLOOR := Color(0.5, 0.4, 0.3)
const C_TRIM := Color(0.85, 0.83, 0.76)
const C_GLASS := Color(0.16, 0.19, 0.22)
const C_WOOD := Color(0.36, 0.26, 0.18)
const C_DARK_WOOD := Color(0.22, 0.16, 0.12)
const C_BLOOD := Color(0.5, 0.03, 0.02)
const C_METAL := Color(0.4, 0.42, 0.44)
const WALL_COLORS: Array[Color] = [
	Color(0.7, 0.66, 0.56), Color(0.56, 0.6, 0.58), Color(0.66, 0.56, 0.48), Color(0.52, 0.55, 0.5), Color(0.74, 0.7, 0.62),
]
const ROOF_COLORS: Array[Color] = [
	Color(0.3, 0.28, 0.27), Color(0.38, 0.24, 0.2), Color(0.25, 0.29, 0.3),
]
const CAR_COLORS: Array[Color] = [
	Color(0.46, 0.27, 0.2), Color(0.24, 0.32, 0.42), Color(0.72, 0.71, 0.66), Color(0.3, 0.36, 0.28), Color(0.62, 0.52, 0.3),
]

## Muebles que se podrán registrar: [tipo, tamaño, color]
const FURNITURE := [
	["nevera", Vector3(0.8, 1.8, 0.7), Color(0.86, 0.86, 0.82)],
	["armario", Vector3(1.4, 2.0, 0.6), Color(0.4, 0.28, 0.18)],
	["cajonera", Vector3(1.0, 0.9, 0.5), Color(0.5, 0.36, 0.24)],
	["estanteria", Vector3(1.2, 1.7, 0.4), Color(0.45, 0.4, 0.32)],
]

var rng := RandomNumberGenerator.new()
var _materials := {}
## [{rect: Rect2 (planta), roof: Node3D}] para ocultar el tejado al entrar
var houses: Array[Dictionary] = []
var _roof_hidden: Node3D


func _ready() -> void:
	add_to_group("world")
	rng.seed = SEED
	_build_environment()
	_build_ground()
	for bx in [-20.0, 20.0]:
		for bz in [-20.0, 20.0]:
			_build_block(bx, bz)
	_build_power_lines()
	_build_cars()
	_build_trees()
	_build_debris()
	_build_bounds()


## Oculta el tejado de la casa en la que está el jugador local.
## El tejado sigue proyectando sombra, así el interior queda en penumbra.
func update_roofs(pos: Vector3) -> void:
	var inside: Node3D = null
	for h in houses:
		if (h.rect as Rect2).has_point(Vector2(pos.x, pos.z)):
			inside = h.roof
			break
	if inside == _roof_hidden:
		return
	if _roof_hidden:
		_set_roof_hidden(_roof_hidden, false)
	if inside:
		_set_roof_hidden(inside, true)
	_roof_hidden = inside


func _set_roof_hidden(roof: Node3D, hidden: bool) -> void:
	for mi in roof.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if hidden
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


# ------------------------------------------------------------------ ambiente
func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# sol bajo de tarde: sombras largas, muy de viñeta de cómic
	sun.rotation_degrees = Vector3(-32, 40, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = PAPER
	# la sombra es el ambiente: azul grisáceo, como tinta aguada
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.56)
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# a lo lejos todo se funde con el papel, como en una viñeta
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = PAPER
	env.fog_depth_begin = 18.0
	env.fog_depth_end = 85.0
	env.fog_depth_curve = 1.4
	env.fog_sky_affect = 0.0

	var world_env := WorldEnvironment.new()
	world_env.name = "Environment"
	world_env.environment = env
	add_child(world_env)


# ------------------------------------------------------------------ suelo y calles
func _build_ground() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(HALF * 2, 1, HALF * 2), C_GRASS, true, self, 0.55, 0.35)
	# manchas de tierra para romper el verde
	for i in 40:
		var p := Vector3(rng.randf_range(-HALF, HALF), 0.004, rng.randf_range(-HALF, HALF))
		_disc(p, rng.randf_range(1.5, 4.5), C_DIRT, rng.randf_range(0.5, 1.0))
	for r in ROADS:
		_box(Vector3(r, 0.01, 0), Vector3(ROAD_W, 0.02, HALF * 2), C_ROAD, false, self, 0.5, 0.8)
		_box(Vector3(0, 0.012, r), Vector3(HALF * 2, 0.02, ROAD_W), C_ROAD, false, self, 0.5, 0.8)
		# aceras
		for s in [-1.0, 1.0]:
			var off: float = s * (ROAD_W / 2 + WALK_W / 2)
			_box(Vector3(r + off, 0.03, 0), Vector3(WALK_W, 0.06, HALF * 2), C_WALK, false, self, 0.35, 1.2)
			_box(Vector3(0, 0.031, r + off), Vector3(HALF * 2, 0.06, WALK_W), C_WALK, false, self, 0.35, 1.2)
		var t := -HALF + 2.0
		while t < HALF:
			if not _near_crossing(t):
				_box(Vector3(r, 0.025, t), Vector3(0.14, 0.01, 1.8), C_LINE, false)
				_box(Vector3(t, 0.025, r), Vector3(1.8, 0.01, 0.14), C_LINE, false)
			t += 4.5


func _near_crossing(t: float) -> bool:
	for r in ROADS:
		if absf(t - r) < ROAD_W / 2 + WALK_W:
			return true
	return false


# ------------------------------------------------------------------ casas
func _build_block(bx: float, bz: float) -> void:
	# dos casas por manzana, con la puerta mirando a la calle central
	var door_side := "S" if bz < 0 else "N"
	for dx in [-7.5, 7.5]:
		var w := rng.randf_range(10.0, 12.0)
		var d := rng.randf_range(8.5, 10.0)
		var cz := bz + rng.randf_range(-2.0, 2.0)
		_build_house(bx + dx, cz, w, d, door_side)
		# valla delante de la casa
		var fz := cz + (d / 2 + 2.2) * (1.0 if door_side == "S" else -1.0)
		_build_fence(bx + dx - w / 2 - 0.5, bx + dx + w / 2 + 0.5, fz)


func _build_house(cx: float, cz: float, w: float, d: float, door_side: String) -> void:
	var house := Node3D.new()
	house.name = "Casa"
	add_child(house)
	var color: Color = WALL_COLORS[rng.randi() % WALL_COLORS.size()]
	var x1 := cx - w / 2
	var x2 := cx + w / 2
	var z1 := cz - d / 2
	var z2 := cz + d / 2

	_box(Vector3(cx, 0.015, cz), Vector3(w, 0.03, d), C_FLOOR, false, house, 0.4, 2.5)
	_wall_x(house, x1, x2, z1, color, door_side == "N", -1.0)
	_wall_x(house, x1, x2, z2, color, door_side == "S", 1.0)
	_wall_z(house, z1, z2, x1, color, door_side == "W", -1.0)
	_wall_z(house, z1, z2, x2, color, door_side == "E", 1.0)
	# tabique interior con hueco de puerta
	_wall_z(house, z1, z2, cx + rng.randf_range(-1.0, 1.0), color.darkened(0.08), true, 0.0)
	# escalón y puerta abierta
	var front := 1.0 if door_side == "S" else -1.0
	var door_z := z2 if door_side == "S" else z1
	_box(Vector3(cx, 0.06, door_z + front * 0.55), Vector3(2.2, 0.12, 0.9), C_WALK, false, house)
	var door := _box(Vector3(cx + DOOR_W / 2 - 0.05, DOOR_H / 2, door_z + front * (DOOR_W / 2)), Vector3(0.06, DOOR_H - 0.05, DOOR_W - 0.1), C_DARK_WOOD, false, house)
	door.rotation.y = rng.randf_range(-0.3, 0.2)
	# sangre en la entrada de algunas casas
	if rng.randf() < 0.5:
		_blood(Vector3(cx + rng.randf_range(-1.0, 1.0), 0, door_z + front * rng.randf_range(0.8, 2.5)), 1.0)

	# muebles pegados a la pared del fondo
	var back_z := z1 + 0.5 if door_side == "S" else z2 - 0.5
	var slots := [x1 + 1.2, cx - 1.8, cx + 1.8, x2 - 1.2]
	for sx in slots:
		if rng.randf() < 0.8:
			var f: Array = FURNITURE[rng.randi() % FURNITURE.size()]
			var size: Vector3 = f[1]
			var body := _box(Vector3(sx, size.y / 2, back_z), size, f[2], true, house, 0.2, 3.0)
			body.add_to_group("contenedores")
			body.set_meta("tipo", f[0])
	# mesa y sillas en una mitad
	var tx := cx + (w / 4) * (1.0 if rng.randf() < 0.5 else -1.0)
	_box(Vector3(tx, 0.75, cz), Vector3(1.4, 0.06, 0.9), C_WOOD, true, house)
	for lx in [-0.6, 0.6]:
		for lz in [-0.38, 0.38]:
			_box(Vector3(tx + lx, 0.36, cz + lz), Vector3(0.06, 0.72, 0.06), C_WOOD, false, house)
	var chair := _box(Vector3(tx + 0.3, 0.45, cz + 0.9), Vector3(0.45, 0.06, 0.45), C_WOOD, false, house)
	chair.rotation.z = PI / 2  # silla volcada
	chair.position.y = 0.23

	_build_roof(house, cx, cz, w, d)
	houses.append({"rect": Rect2(x1, z1, w, d), "roof": house.get_node("Tejado")})


func _build_roof(house: Node3D, cx: float, cz: float, w: float, d: float) -> void:
	var roof := Node3D.new()
	roof.name = "Tejado"
	house.add_child(roof)
	var color: Color = ROOF_COLORS[rng.randi() % ROOF_COLORS.size()]
	var h := rng.randf_range(1.6, 2.2)
	var along_x := w >= d
	var prism := PrismMesh.new()
	# el prisma tiene la cumbrera a lo largo de Z; si la casa es más ancha, se gira
	prism.size = Vector3((d if along_x else w) + 0.9, h, (w if along_x else d) + 0.9)
	var mi := MeshInstance3D.new()
	mi.mesh = prism
	mi.material_override = _mat(color, 0.5, 2.0)
	mi.position = Vector3(cx, WALL_H + h / 2, cz)
	mi.rotation.y = PI / 2 if along_x else 0.0
	roof.add_child(mi)
	# techo plano bajo el tejado para tapar el hueco del muro
	_box(Vector3(cx, WALL_H + 0.02, cz), Vector3(w + 0.1, 0.04, d + 0.1), color.darkened(0.3), false, roof)
	# chimenea
	var chim := _box(Vector3(cx + rng.randf_range(-w / 4, w / 4), WALL_H + h * 0.75, cz + rng.randf_range(-0.6, 0.6)), Vector3(0.6, h * 1.1, 0.6), Color(0.45, 0.3, 0.26), false, roof)
	chim.name = "Chimenea"


## Pared a lo largo de X en z fija. `out` es hacia dónde mira el exterior (+1/-1).
func _wall_x(parent: Node3D, x1: float, x2: float, z: float, color: Color, door: bool, out: float) -> void:
	var segs := _segments(x1, x2, door)
	for s in segs:
		_box(Vector3((s.x + s.y) / 2, WALL_H / 2, z), Vector3(s.y - s.x, WALL_H, WALL_T), color, true, parent, 0.35, 1.5)
		_windows_along(parent, s.x, s.y, func(a: float) -> Vector3: return Vector3(a, 0, z), true, out)
	if door:
		var c := (x1 + x2) / 2
		_box(Vector3(c, (DOOR_H + WALL_H) / 2, z), Vector3(DOOR_W, WALL_H - DOOR_H, WALL_T), color, true, parent)
		_door_frame(parent, Vector3(c, 0, z), true)
	# alero / remate superior
	_box(Vector3((x1 + x2) / 2, WALL_H - 0.08, z), Vector3(x2 - x1 + 0.1, 0.16, WALL_T + 0.08), C_TRIM, false, parent)


func _wall_z(parent: Node3D, z1: float, z2: float, x: float, color: Color, door: bool, out: float) -> void:
	var segs := _segments(z1, z2, door)
	for s in segs:
		_box(Vector3(x, WALL_H / 2, (s.x + s.y) / 2), Vector3(WALL_T, WALL_H, s.y - s.x), color, true, parent, 0.35, 1.5)
		if out != 0.0:
			_windows_along(parent, s.x, s.y, func(a: float) -> Vector3: return Vector3(x, 0, a), false, out)
	if door:
		var c := (z1 + z2) / 2
		_box(Vector3(x, (DOOR_H + WALL_H) / 2, c), Vector3(WALL_T, WALL_H - DOOR_H, DOOR_W), color, true, parent)
		if out != 0.0:
			_door_frame(parent, Vector3(x, 0, c), false)
	if out != 0.0:
		_box(Vector3(x, WALL_H - 0.08, (z1 + z2) / 2), Vector3(WALL_T + 0.08, 0.16, z2 - z1 + 0.1), C_TRIM, false, parent)


## Tramos de pared, dejando hueco para la puerta en el centro.
func _segments(a: float, b: float, door: bool) -> Array[Vector2]:
	if not door:
		return [Vector2(a, b)]
	var c := (a + b) / 2
	return [Vector2(a, c - DOOR_W / 2), Vector2(c + DOOR_W / 2, b)]


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
			_box(p + Vector3(0, 1.55, 0), frame_size, C_TRIM, false, parent)
			_box(p + Vector3(0, 1.55, 0) + (Vector3(0, 0, 0.02 * side) if along_x else Vector3(0.02 * side, 0, 0)), glass_size, C_GLASS, false, parent, 0.0)
			_box(p + Vector3(0, 0.88, 0), sill_size, C_TRIM, false, parent)
			# tablones clavados en algunas ventanas exteriores
			if side == out and rng.randf() < 0.35:
				for k in 2:
					var plank := _box(p + Vector3(0, 1.4 + k * 0.35, 0) + (Vector3(0, 0, 0.05 * side) if along_x else Vector3(0.05 * side, 0, 0)),
						Vector3(1.3, 0.14, 0.04) if along_x else Vector3(0.04, 0.14, 1.3), C_WOOD, false, parent)
					plank.rotation = Vector3(0, 0, rng.randf_range(-0.25, 0.25)) if along_x else Vector3(rng.randf_range(-0.25, 0.25), 0, 0)


func _door_frame(parent: Node3D, base: Vector3, along_x: bool) -> void:
	var t := WALL_T + 0.1
	for s in [-1.0, 1.0]:
		var p := base + (Vector3(s * (DOOR_W / 2 + 0.05), DOOR_H / 2, 0) if along_x else Vector3(0, DOOR_H / 2, s * (DOOR_W / 2 + 0.05)))
		_box(p, Vector3(0.1, DOOR_H, t) if along_x else Vector3(t, DOOR_H, 0.1), C_TRIM, false, parent)
	_box(base + Vector3(0, DOOR_H + 0.05, 0), Vector3(DOOR_W + 0.2, 0.1, t) if along_x else Vector3(t, 0.1, DOOR_W + 0.2), C_TRIM, false, parent)


func _build_fence(x1: float, x2: float, z: float) -> void:
	var gap_c := (x1 + x2) / 2
	var x := x1
	while x <= x2:
		if absf(x - gap_c) > 1.3 and rng.randf() < 0.92:
			var post := _box(Vector3(x, 0.5, z), Vector3(0.09, 1.0, 0.09), C_TRIM.darkened(0.15), true, self)
			post.rotation.z = rng.randf_range(-0.08, 0.08)
		x += 0.45
	for y in [0.35, 0.8]:
		_box(Vector3((x1 + gap_c - 1.3) / 2, y, z), Vector3(gap_c - 1.3 - x1, 0.07, 0.04), C_TRIM.darkened(0.2), false)
		_box(Vector3((gap_c + 1.3 + x2) / 2, y, z), Vector3(x2 - gap_c - 1.3, 0.07, 0.04), C_TRIM.darkened(0.2), false)


# ------------------------------------------------------------------ postes, coches, árboles
func _build_power_lines() -> void:
	# una línea de postes junto a cada calle norte-sur, con cables combados
	for r in ROADS:
		var x := r + ROAD_W / 2 + WALK_W - 0.3
		var prev := Vector3.INF
		var z := -HALF + 6.0
		while z < HALF - 4.0:
			if not _near_crossing(z):
				var top := _build_pole(Vector3(x, 0, z))
				if prev != Vector3.INF and z - prev.z < 20.0:
					for k in [-0.7, 0.0, 0.7]:
						_wire(prev + Vector3(k, 0, 0), top + Vector3(k, 0, 0))
				prev = top
			else:
				prev = Vector3.INF
			z += 14.0


func _build_pole(base: Vector3) -> Vector3:
	var h := 7.0
	var pole := _cyl_body(base, 0.11, 0.14, h, C_DARK_WOOD.lightened(0.1))
	pole.rotation.z = rng.randf_range(-0.03, 0.03)
	_box(base + Vector3(0, h - 0.5, 0), Vector3(1.8, 0.12, 0.12), C_DARK_WOOD, false)
	# transformador en algunos
	if rng.randf() < 0.3:
		_cyl_mesh(base + Vector3(0.3, h - 1.4, 0), 0.25, 0.25, 0.7, C_METAL)
	return base + Vector3(0, h - 0.45, 0)


func _wire(a: Vector3, b: Vector3) -> void:
	# dos tramos para que el cable cuelgue
	var mid := (a + b) / 2 + Vector3(0, -0.6, 0)
	for pair in [[a, mid], [mid, b]]:
		var p: Vector3 = pair[0]
		var q: Vector3 = pair[1]
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.025, 0.025, p.distance_to(q))
		mi.mesh = m
		mi.material_override = _mat(Color(0.08, 0.08, 0.08), 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.look_at_from_position((p + q) / 2, q, Vector3.UP)


func _build_cars() -> void:
	for i in 12:
		var r: float = ROADS[rng.randi() % ROADS.size()]
		var t := rng.randf_range(-HALF + 8, HALF - 8)
		if _near_crossing(t) and absf(t) < 8.0:
			continue  # deja libre el cruce donde aparecen los jugadores
		var lane := 2.0 if rng.randf() < 0.5 else -2.0
		var along_x := rng.randf() < 0.5
		var pos := Vector3(t, 0, r + lane) if along_x else Vector3(r + lane, 0, t)
		_build_car(pos, along_x, CAR_COLORS[rng.randi() % CAR_COLORS.size()])


func _build_car(pos: Vector3, along_x: bool, color: Color) -> void:
	var car := Node3D.new()
	car.name = "Coche"
	car.position = pos
	car.rotation.y = (0.0 if along_x else PI / 2) + rng.randf_range(-0.3, 0.3)
	add_child(car)
	var body := _box(Vector3(0, 0.62, 0), Vector3(4.2, 0.62, 1.8), color, true, car, 0.3, 2.0)
	body.add_to_group("contenedores")
	body.set_meta("tipo", "coche")
	# cabina con ventanillas oscuras y techo
	_box(Vector3(-0.25, 1.17, 0), Vector3(2.1, 0.5, 1.62), C_GLASS, false, car, 0.0)
	_box(Vector3(-0.25, 1.44, 0), Vector3(2.0, 0.06, 1.66), color, false, car)
	for s in [-1.0, 1.0]:
		_box(Vector3(-0.25, 1.17, s * 0.8), Vector3(0.08, 0.5, 0.05), color, false, car)
		# faros y pilotos
		_box(Vector3(2.1, 0.72, s * 0.62), Vector3(0.04, 0.16, 0.32), Color(0.95, 0.92, 0.8), false, car, 0.0)
		_box(Vector3(-2.1, 0.72, s * 0.62), Vector3(0.04, 0.14, 0.3), Color(0.6, 0.05, 0.03), false, car, 0.0)
	# parachoques
	_box(Vector3(2.12, 0.45, 0), Vector3(0.12, 0.16, 1.85), C_METAL, false, car)
	_box(Vector3(-2.12, 0.45, 0), Vector3(0.12, 0.16, 1.85), C_METAL, false, car)
	# ruedas
	for wx in [-1.35, 1.35]:
		for wz in [-0.85, 0.85]:
			var wheel := _cyl_mesh(Vector3(wx, 0.36, wz), 0.36, 0.36, 0.26, Color(0.1, 0.1, 0.1), car)
			wheel.rotation.x = PI / 2
	# puerta abierta en algunos
	if rng.randf() < 0.4:
		var door := _box(Vector3(0.35, 0.85, 1.35), Vector3(1.0, 0.9, 0.06), color, false, car)
		door.rotation.y = 0.7
	if rng.randf() < 0.4:
		_blood(pos + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2)), 1.3)


func _build_trees() -> void:
	var placed := 0
	while placed < 70:
		var x := rng.randf_range(-HALF + 3, HALF - 3)
		var z := rng.randf_range(-HALF + 3, HALF - 3)
		if absf(x) < 46 and absf(z) < 46:
			continue  # solo en las afueras
		if rng.randf() < 0.45:
			_build_dead_tree(Vector3(x, 0, z))
		else:
			_build_tree(Vector3(x, 0, z))
		placed += 1
	# algunos árboles secos dentro del pueblo, entre casas
	for i in 10:
		var p := Vector3(rng.randf_range(-36, 36), 0, rng.randf_range(-36, 36))
		if _on_road(p.x) or _on_road(p.z) or _inside_house(p, 2.5):
			continue
		_build_dead_tree(p)


func _on_road(v: float) -> bool:
	for r in ROADS:
		if absf(v - r) < ROAD_W / 2 + WALK_W + 0.8:
			return true
	return false


func _inside_house(p: Vector3, margin: float) -> bool:
	for h in houses:
		if (h.rect as Rect2).grow(margin).has_point(Vector2(p.x, p.z)):
			return true
	return false


func _build_tree(pos: Vector3) -> void:
	var trunk_h := rng.randf_range(2.2, 3.4)
	_cyl_body(pos, 0.16, 0.26, trunk_h, Color(0.3, 0.23, 0.17))
	var crown_col := Color(0.3, 0.36, 0.26).lerp(Color(0.42, 0.4, 0.26), rng.randf())
	for i in 3:
		var r := rng.randf_range(1.0, 1.7)
		var off := Vector3(rng.randf_range(-0.7, 0.7), trunk_h + r * 0.5 + i * 0.35, rng.randf_range(-0.7, 0.7))
		var crown := _sphere_mesh(pos + off, r, crown_col.darkened(i * 0.05))
		crown.scale = Vector3(1, rng.randf_range(0.8, 1.0), 1)


func _build_dead_tree(pos: Vector3) -> void:
	# árbol seco: tronco y ramas sueltas, muy de silueta de cómic
	var h := rng.randf_range(3.0, 4.6)
	_cyl_body(pos, 0.08, 0.2, h, Color(0.22, 0.18, 0.15))
	for i in rng.randi_range(4, 7):
		var y := rng.randf_range(h * 0.45, h * 0.95)
		var length := rng.randf_range(0.8, 1.8) * (1.2 - y / h)
		var branch := _cyl_mesh(Vector3.ZERO, 0.02, 0.06, length, Color(0.22, 0.18, 0.15))
		var yaw := rng.randf_range(0, TAU)
		var tilt := rng.randf_range(0.5, 1.1)
		branch.position = pos + Vector3(0, y, 0) + Vector3(sin(yaw), 0, cos(yaw)) * sin(tilt) * length / 2 + Vector3(0, cos(tilt) * length / 2, 0)
		branch.rotation = Vector3(tilt * cos(yaw), 0, -tilt * sin(yaw))


func _build_debris() -> void:
	# bolsas de basura, cajas, neumáticos y sangre por las calles
	for i in 45:
		var p := Vector3(rng.randf_range(-HALF + 8, HALF - 8), 0, rng.randf_range(-HALF + 8, HALF - 8))
		if _inside_house(p, 0.6):
			continue
		match rng.randi() % 4:
			0:
				var bag := _sphere_mesh(p + Vector3(0, 0.22, 0), 0.32, Color(0.12, 0.13, 0.12))
				bag.scale = Vector3(1, 0.75, 0.9)
			1:
				var crate := _box(p + Vector3(0, 0.25, 0), Vector3(0.6, 0.5, 0.6), C_WOOD.lightened(0.1), true, self, 0.4, 3.0)
				crate.rotation.y = rng.randf_range(0, PI)
			2:
				var tire := _cyl_mesh(p + Vector3(0, 0.12, 0), 0.34, 0.34, 0.22, Color(0.09, 0.09, 0.09))
				tire.rotation.x = rng.randf_range(-0.1, 0.1)
			3:
				_blood(p, rng.randf_range(0.6, 1.4))


func _build_bounds() -> void:
	# paredes invisibles en el borde del mapa
	for s in [-1.0, 1.0]:
		_collider(Vector3(s * HALF, 5, 0), Vector3(1, 10, HALF * 2))
		_collider(Vector3(0, 5, s * HALF), Vector3(HALF * 2, 10, 1))


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


## Caja con malla y (opcional) colisión. Devuelve el nodo creado.
func _box(pos: Vector3, size: Vector3, color: Color, collide := true, parent: Node3D = self, grit := 0.35, grit_scale := 1.6) -> Node3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _mat(color, grit, grit_scale)
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


func _cyl_mesh(pos: Vector3, top: float, bottom: float, h: float, color: Color, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 10
	mi.mesh = m
	mi.material_override = _mat(color, 0.3, 4.0)
	mi.position = pos
	parent.add_child(mi)
	return mi


## Cilindro vertical con colisión apoyado en el suelo (troncos, postes).
func _cyl_body(base: Vector3, top: float, bottom: float, h: float, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = base
	add_child(body)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = bottom
	cyl.height = h
	shape.shape = cyl
	shape.position.y = h / 2
	body.add_child(shape)
	_cyl_mesh(Vector3(0, h / 2, 0), top, bottom, h, color, body)
	return body


func _sphere_mesh(pos: Vector3, r: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2
	m.radial_segments = 12
	m.rings = 6
	mi.mesh = m
	mi.material_override = _mat(color, 0.5, 2.5)
	mi.position = pos
	add_child(mi)
	return mi


## Mancha plana en el suelo (tierra, charcos).
func _disc(pos: Vector3, r: float, color: Color, squash: float) -> MeshInstance3D:
	var mi := _cyl_mesh(pos, r, r, 0.008, color)
	mi.scale = Vector3(1, 1, squash)
	mi.rotation.y = rng.randf_range(0, PI)
	mi.material_override = _mat(color, 0.6, 1.2)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Salpicadura de sangre: una mancha grande y gotas alrededor. El único rojo vivo del pueblo.
func _blood(pos: Vector3, size: float) -> void:
	var y := 0.07
	_disc(Vector3(pos.x, y, pos.z), 0.55 * size, C_BLOOD, rng.randf_range(0.5, 0.9))
	for i in rng.randi_range(3, 7):
		var a := rng.randf_range(0, TAU)
		var d := rng.randf_range(0.5, 1.4) * size
		_disc(Vector3(pos.x + cos(a) * d, y + 0.001, pos.z + sin(a) * d), rng.randf_range(0.06, 0.18) * size, C_BLOOD, rng.randf_range(0.6, 1.0))
	# rastro de arrastre
	if rng.randf() < 0.5:
		var a := rng.randf_range(0, TAU)
		var trail := _box(Vector3(pos.x + cos(a) * size, y, pos.z + sin(a) * size), Vector3(0.35 * size, 0.008, 2.0 * size), C_BLOOD, false, self, 0.7, 2.0)
		trail.rotation.y = -a + PI / 2
		(trail as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _collider(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)
