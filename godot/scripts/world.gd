extends Node3D
## Pueblo provisional hecho con cajas grises.
## Se genera con una semilla fija para que todos los jugadores vean el mismo
## mapa. Más adelante estas cajas se sustituirán por modelos .glb.

const SEED := 1993
const HALF := 70.0
const ROADS: Array[float] = [-40.0, 0.0, 40.0]
const ROAD_W := 8.0
const WALL_H := 2.8
const WALL_T := 0.25
const DOOR_W := 1.6
const DOOR_H := 2.2

const C_GRASS := Color(0.36, 0.42, 0.3)
const C_ROAD := Color(0.2, 0.21, 0.22)
const C_LINE := Color(0.75, 0.7, 0.45)
const C_FLOOR := Color(0.45, 0.38, 0.3)
const WALL_COLORS: Array[Color] = [
	Color(0.62, 0.6, 0.55), Color(0.55, 0.5, 0.42), Color(0.5, 0.55, 0.52), Color(0.6, 0.52, 0.48),
]
const CAR_COLORS: Array[Color] = [
	Color(0.55, 0.15, 0.12), Color(0.2, 0.3, 0.45), Color(0.7, 0.7, 0.68), Color(0.25, 0.35, 0.25),
]

## Muebles que se podrán registrar más adelante: [tipo, tamaño, color]
const FURNITURE := [
	["nevera", Vector3(0.8, 1.8, 0.7), Color(0.85, 0.86, 0.84)],
	["armario", Vector3(1.4, 2.0, 0.6), Color(0.4, 0.28, 0.18)],
	["cajonera", Vector3(1.0, 0.9, 0.5), Color(0.5, 0.36, 0.24)],
	["estanteria", Vector3(1.2, 1.7, 0.4), Color(0.45, 0.4, 0.32)],
]

var rng := RandomNumberGenerator.new()
var _materials := {}


func _ready() -> void:
	rng.seed = SEED
	_build_environment()
	_build_ground()
	for bx in [-20.0, 20.0]:
		for bz in [-20.0, 20.0]:
			_build_block(bx, bz)
	_build_cars()
	_build_trees()
	_build_bounds()


# ------------------------------------------------------------------ ambiente
func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.5, 0.58, 0.62)
	sky_mat.sky_horizon_color = Color(0.68, 0.72, 0.72)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.6)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.6, 0.6)
	env.fog_density = 0.008

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


# ------------------------------------------------------------------ suelo y calles
func _build_ground() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(HALF * 2, 1, HALF * 2), C_GRASS)
	for r in ROADS:
		_box(Vector3(r, 0.01, 0), Vector3(ROAD_W, 0.02, HALF * 2), C_ROAD, false)
		_box(Vector3(0, 0.012, r), Vector3(HALF * 2, 0.02, ROAD_W), C_ROAD, false)
		var t := -HALF + 2.0
		while t < HALF:
			_box(Vector3(r, 0.025, t), Vector3(0.15, 0.01, 1.6), C_LINE, false)
			_box(Vector3(t, 0.025, r), Vector3(1.6, 0.01, 0.15), C_LINE, false)
			t += 4.0


# ------------------------------------------------------------------ casas
func _build_block(bx: float, bz: float) -> void:
	# dos casas por manzana, con la puerta mirando a la calle central
	var door_side := "S" if bz < 0 else "N"
	for dx in [-7.5, 7.5]:
		var w := rng.randf_range(10.0, 12.0)
		var d := rng.randf_range(8.5, 10.5)
		_build_house(bx + dx, bz + rng.randf_range(-3.0, 3.0), w, d, door_side)


func _build_house(cx: float, cz: float, w: float, d: float, door_side: String) -> void:
	var house := Node3D.new()
	house.name = "Casa"
	add_child(house)
	var color: Color = WALL_COLORS[rng.randi() % WALL_COLORS.size()]
	var x1 := cx - w / 2
	var x2 := cx + w / 2
	var z1 := cz - d / 2
	var z2 := cz + d / 2

	_box(Vector3(cx, 0.01, cz), Vector3(w, 0.02, d), C_FLOOR, false, house)
	_wall_x(house, x1, x2, z1, color, door_side == "N")
	_wall_x(house, x1, x2, z2, color, door_side == "S")
	_wall_z(house, z1, z2, x1, color, door_side == "W")
	_wall_z(house, z1, z2, x2, color, door_side == "E")
	# tabique interior con hueco de puerta
	_wall_z(house, z1, z2, cx + rng.randf_range(-1.0, 1.0), color, true)

	# muebles pegados a la pared del fondo
	var back_z := z1 + 0.5 if door_side == "S" else z2 - 0.5
	var slots := [x1 + 1.2, cx - 1.6, cx + 1.6, x2 - 1.2]
	for sx in slots:
		if rng.randf() < 0.8:
			var f: Array = FURNITURE[rng.randi() % FURNITURE.size()]
			var size: Vector3 = f[1]
			var body := _box(Vector3(sx, size.y / 2, back_z), size, f[2], true, house)
			body.add_to_group("contenedores")
			body.set_meta("tipo", f[0])


func _wall_x(parent: Node3D, x1: float, x2: float, z: float, color: Color, door: bool) -> void:
	if not door:
		_box(Vector3((x1 + x2) / 2, WALL_H / 2, z), Vector3(x2 - x1, WALL_H, WALL_T), color, true, parent)
		return
	var c := (x1 + x2) / 2
	var a := c - DOOR_W / 2
	var b := c + DOOR_W / 2
	_box(Vector3((x1 + a) / 2, WALL_H / 2, z), Vector3(a - x1, WALL_H, WALL_T), color, true, parent)
	_box(Vector3((b + x2) / 2, WALL_H / 2, z), Vector3(x2 - b, WALL_H, WALL_T), color, true, parent)
	_box(Vector3(c, (DOOR_H + WALL_H) / 2, z), Vector3(DOOR_W, WALL_H - DOOR_H, WALL_T), color, true, parent)


func _wall_z(parent: Node3D, z1: float, z2: float, x: float, color: Color, door: bool) -> void:
	if not door:
		_box(Vector3(x, WALL_H / 2, (z1 + z2) / 2), Vector3(WALL_T, WALL_H, z2 - z1), color, true, parent)
		return
	var c := (z1 + z2) / 2
	var a := c - DOOR_W / 2
	var b := c + DOOR_W / 2
	_box(Vector3(x, WALL_H / 2, (z1 + a) / 2), Vector3(WALL_T, WALL_H, a - z1), color, true, parent)
	_box(Vector3(x, WALL_H / 2, (b + z2) / 2), Vector3(WALL_T, WALL_H, z2 - b), color, true, parent)
	_box(Vector3(x, (DOOR_H + WALL_H) / 2, c), Vector3(WALL_T, WALL_H - DOOR_H, DOOR_W), color, true, parent)


# ------------------------------------------------------------------ coches y árboles
func _build_cars() -> void:
	for i in 10:
		var r: float = ROADS[rng.randi() % ROADS.size()]
		var t := rng.randf_range(-HALF + 8, HALF - 8)
		if absf(t) < 6.0:
			continue  # deja libre el cruce donde aparecen los jugadores
		var lane := 2.0 if rng.randf() < 0.5 else -2.0
		var along_x := rng.randf() < 0.5
		var pos := Vector3(t, 0, r + lane) if along_x else Vector3(r + lane, 0, t)
		_build_car(pos, along_x, CAR_COLORS[rng.randi() % CAR_COLORS.size()])


func _build_car(pos: Vector3, along_x: bool, color: Color) -> void:
	var car := Node3D.new()
	car.name = "Coche"
	car.position = pos
	car.rotation.y = 0.0 if along_x else PI / 2
	car.rotation.y += rng.randf_range(-0.15, 0.15)
	add_child(car)
	var body := _box(Vector3(0, 0.65, 0), Vector3(4.2, 0.9, 1.8), color, true, car)
	body.add_to_group("contenedores")
	body.set_meta("tipo", "coche")
	_box(Vector3(-0.2, 1.4, 0), Vector3(2.2, 0.6, 1.6), color.darkened(0.3), false, car)


func _build_trees() -> void:
	var placed := 0
	while placed < 60:
		var x := rng.randf_range(-HALF + 3, HALF - 3)
		var z := rng.randf_range(-HALF + 3, HALF - 3)
		if absf(x) < 46 and absf(z) < 46:
			continue  # solo en las afueras
		_build_tree(Vector3(x, 0, z))
		placed += 1


func _build_tree(pos: Vector3) -> void:
	var trunk_h := rng.randf_range(2.0, 3.2)
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.25
	cyl.height = trunk_h
	shape.shape = cyl
	shape.position.y = trunk_h / 2
	body.add_child(shape)

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.25
	trunk_mesh.height = trunk_h
	trunk.mesh = trunk_mesh
	trunk.material_override = _mat(Color(0.3, 0.22, 0.15))
	trunk.position.y = trunk_h / 2
	body.add_child(trunk)

	var crown := MeshInstance3D.new()
	var crown_mesh := SphereMesh.new()
	var r := rng.randf_range(1.3, 2.1)
	crown_mesh.radius = r
	crown_mesh.height = r * 1.8
	crown.mesh = crown_mesh
	crown.material_override = _mat(Color(0.22, 0.32, 0.2))
	crown.position.y = trunk_h + r * 0.6
	body.add_child(crown)


func _build_bounds() -> void:
	# paredes invisibles en el borde del mapa
	for s in [-1.0, 1.0]:
		_collider(Vector3(s * HALF, 5, 0), Vector3(1, 10, HALF * 2))
		_collider(Vector3(0, 5, s * HALF), Vector3(HALF * 2, 10, 1))


# ------------------------------------------------------------------ utilidades
func _mat(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_materials[color] = m
	return _materials[color]


## Caja con malla y (opcional) colisión. Devuelve el nodo creado.
func _box(pos: Vector3, size: Vector3, color: Color, collide := true, parent: Node3D = self) -> Node3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _mat(color)
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


func _collider(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)
