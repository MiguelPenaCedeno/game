class_name WorldLayout
extends RefCounted
## Plano del mundo: calles, casas, lugares, granjas, bosque, coches y muebles.
## Son solo datos: se calcula entero al arrancar (tarda poco) y sale igual en
## todos los equipos porque usa una semilla fija. world.gd construye cada zona
## de TILE × TILE metros cuando hay alguien cerca y la quita cuando se va.
##
## Norte = -Z. El pueblo está en el centro; de él salen cuatro carreteras hasta
## el borde del mapa, con casas sueltas, gasolineras y granjas. Lo demás es bosque.

const SEED := 1993
const TILE := 80.0
const TILES := 8
const HALF := TILE * TILES / 2.0
## el casco urbano llega hasta aquí (en X y en Z)
const TOWN := 100.0
const STREETS: Array[float] = [-80.0, -40.0, 0.0, 40.0, 80.0]
const ROAD_W := 8.0
const WALK_W := 1.8
const HWY_W := 7.0
const PATH_W := 3.6
const WALL_H := 2.8

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
const C_CONCRETE := Color(0.62, 0.61, 0.57)
const C_FIELD := Color(0.36, 0.3, 0.22)
const C_HAY := Color(0.72, 0.62, 0.36)
const WALL_COLORS: Array[Color] = [
	Color(0.7, 0.66, 0.56), Color(0.56, 0.6, 0.58), Color(0.66, 0.56, 0.48), Color(0.52, 0.55, 0.5), Color(0.74, 0.7, 0.62),
]
const ROOF_COLORS: Array[Color] = [
	Color(0.3, 0.28, 0.27), Color(0.38, 0.24, 0.2), Color(0.25, 0.29, 0.3),
]
const CAR_COLORS: Array[Color] = [
	Color(0.46, 0.27, 0.2), Color(0.24, 0.32, 0.42), Color(0.72, 0.71, 0.66), Color(0.3, 0.36, 0.28), Color(0.62, 0.52, 0.3),
]

## Muebles registrables: tipo -> [tamaño, color]. El botín está en data/containers/.
const FURNITURE := {
	"nevera": [Vector3(0.8, 1.8, 0.7), Color(0.86, 0.86, 0.82)],
	"armario": [Vector3(1.4, 2.0, 0.6), Color(0.4, 0.28, 0.18)],
	"cajonera": [Vector3(1.0, 0.9, 0.5), Color(0.5, 0.36, 0.24)],
	"estanteria": [Vector3(1.2, 1.7, 0.4), Color(0.45, 0.4, 0.32)],
	"estanteria_tienda": [Vector3(3.0, 1.5, 0.8), Color(0.6, 0.6, 0.56)],
	"botiquin": [Vector3(0.9, 1.6, 0.45), Color(0.84, 0.86, 0.82)],
	"taquilla": [Vector3(0.6, 1.9, 0.5), Color(0.38, 0.44, 0.48)],
	"armero": [Vector3(1.2, 1.9, 0.5), Color(0.25, 0.27, 0.28)],
	"caja_herramientas": [Vector3(0.9, 0.5, 0.5), Color(0.62, 0.5, 0.2)],
	"bidon": [Vector3(0.6, 0.9, 0.6), Color(0.3, 0.38, 0.3)],
	"arcon": [Vector3(1.4, 0.7, 0.7), Color(0.42, 0.32, 0.22)],
	"caja_municion": [Vector3(1.0, 0.5, 0.6), Color(0.32, 0.36, 0.26)],
}
const HOME_FURNITURE: Array[String] = ["nevera", "armario", "cajonera", "estanteria"]
## hacia dónde mira la puerta -> giro del edificio (la puerta está en +Z local)
const YAW := {"S": 0.0, "E": PI / 2, "N": PI, "W": -PI / 2}

## Manzanas del pueblo que no son casas.
const SPECIAL_BLOCKS := {
	Vector2(60, -20): "supermercado",
	Vector2(-60, 20): "comisaria",
	Vector2(-20, -60): "hospital",
	Vector2(20, 60): "parque",
	Vector2(-60, -60): "iglesia",
}

## Lugares hechos a mano en el editor (res://lugares/*.tscn): [escena, posición, giro]
const PREFABS := [
	["res://lugares/control_militar.tscn", Vector3(-200, 0, 0), PI / 2],
	["res://lugares/cabana_cazador.tscn", Vector3(-205, 0, -195), 0.4],
]

var rng := RandomNumberGenerator.new()
## {rect: Rect2, kind: calle | acera | carretera | camino | asfalto}
var roads: Array[Dictionary] = []
## casas: {center, w, d, yaw, rect, floors, color, roof, roof_h, side, px, seed, tile, lamp}
var houses: Array[Dictionary] = []
## edificios grandes: {kind, name, center, w, d, h, yaw, rect, color, seed, tile, door_w, walls}
var halls: Array[Dictionary] = []
## muebles registrables, en el mismo orden en todos los equipos:
## {type, pos (centro), rot, size, color, tile, floor_y}
var containers: Array[Dictionary] = []
## coches abandonados: {pos, yaw, color, door, blood, seed, tile, cont}
var cars: Array[Dictionary] = []
## piezas sueltas: {shape: box | cyl, pos, size, color, yaw, collide, tile}
var props: Array[Dictionary] = []
## vallas: {a, b, gap, tile}
var fences: Array[Dictionary] = []
## postes de la luz: {pos, prev (Vector3.INF si no hay cable), tile}
var poles: Array[Dictionary] = []
## Vector2i -> [[pos, vivo, semilla]]
var trees := {}
## lugares hechos en el editor: {scene, pos, yaw, tile, name}
var prefabs: Array[Dictionary] = []
## dónde aparecen los vehículos que se pueden conducir: {pos, yaw, kind}
var vehicles: Array[Dictionary] = []
## nombres para el mapa: {name, pos, kind}
var places: Array[Dictionary] = []
## zonas ocupadas (sin árboles ni basura)
var footprints: Array[Rect2] = []
## Vector2i -> {houses, halls, cars, props, fences, poles, prefabs, roads, conts, foot}: índices
var by_tile := {}


func _init() -> void:
	rng.seed = SEED
	_town_roads()
	_highways()
	# las cuatro manzanas del centro primero: sus muebles son los primeros
	var blocks: Array[Vector2] = []
	for bx in [-20.0, 20.0]:
		for bz in [-20.0, 20.0]:
			blocks.append(Vector2(bx, bz))
	for bx in [-60.0, -20.0, 20.0, 60.0]:
		for bz in [-60.0, -20.0, 20.0, 60.0]:
			if absf(bx) > 30.0 or absf(bz) > 30.0:
				blocks.append(Vector2(bx, bz))
	for b in blocks:
		_town_block(b)
	places.append({"name": "Pueblo", "pos": Vector3(0, 0, 0), "kind": "pueblo"})
	_gas_station("Gasolinera Este", Vector3(200, 0, -(HWY_W / 2 + 12.0)), 0.0)
	_gas_station("Gasolinera Sur", Vector3(HWY_W / 2 + 12.0, 0, 200), -PI / 2)
	_farm("Granja Los Olmos", Vector3(200, 0, 48), PI)
	_farm("Granja El Molino", Vector3(-48, 0, 200), PI / 2)
	_farm("Granja Vieja", Vector3(-200, 0, -48), 0.0)
	_farm("Granja Robles", Vector3(48, 0, -200), -PI / 2)
	for p in PREFABS:
		_prefab(p[0], p[1], p[2])
	_suburbs()
	# coches que todavía arrancan, cerca de la salida
	_vehicle(Vector3(2.2, 0, 24.0), 0.0, "coche")
	_vehicle(Vector3(-26.0, 0, 2.0), PI / 2, "coche")
	_vehicle(Vector3(42.0, 0, -58.0), 0.0, "furgoneta")
	_town_cars()
	_highway_cars()
	_power_lines()
	_index()
	_forest()


# ------------------------------------------------------------------ consultas
static func tile_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(floori((x + HALF) / TILE), 0, TILES - 1), clampi(floori((z + HALF) / TILE), 0, TILES - 1))


static func tile_rect(t: Vector2i) -> Rect2:
	return Rect2(-HALF + t.x * TILE, -HALF + t.y * TILE, TILE, TILE)


func tile_data(t: Vector2i) -> Dictionary:
	return by_tile.get(t, {})


## ¿Hay algo construido (casa, carretera, granja…) en este punto?
func blocked(x: float, z: float, margin := 0.0) -> bool:
	var td: Dictionary = by_tile.get(tile_of(x, z), {})
	var p := Vector2(x, z)
	for i in td.get("foot", []):
		if footprints[i].grow(margin).has_point(p):
			return true
	for i in td.get("roads", []):
		if roads[i].kind != "acera" and (roads[i].rect as Rect2).grow(margin + 1.0).has_point(p):
			return true
	return false


## ¿Cae dentro de una casa, un edificio o una granja?
func in_footprint(x: float, z: float, margin := 0.0) -> bool:
	var td: Dictionary = by_tile.get(tile_of(x, z), {})
	for i in td.get("foot", []):
		if footprints[i].grow(margin).has_point(Vector2(x, z)):
			return true
	return false


## Cuántos zombis hay por la zona (1 = pueblo).
func density_at(p: Vector3) -> float:
	if absf(p.x) < TOWN + 15.0 and absf(p.z) < TOWN + 15.0:
		return 1.0
	for pl in places:
		if pl.kind != "pueblo" and Vector2(pl.pos.x - p.x, pl.pos.z - p.z).length() < 45.0:
			return 0.75
	return 0.45


func place_at(p: Vector3, radius := 40.0) -> String:
	for pl in places:
		if pl.kind != "pueblo" and Vector2(pl.pos.x - p.x, pl.pos.z - p.z).length() < radius:
			return pl.name
	return ""


# ------------------------------------------------------------------ calles y carreteras
func _road(rect: Rect2, kind: String) -> void:
	roads.append({"rect": rect, "kind": kind})


func _town_roads() -> void:
	for s in STREETS:
		_road(Rect2(s - ROAD_W / 2, -TOWN, ROAD_W, TOWN * 2), "calle")
		_road(Rect2(-TOWN, s - ROAD_W / 2, TOWN * 2, ROAD_W), "calle")
		# aceras a ambos lados, cortadas en los cruces
		for side in [-1.0, 1.0]:
			var off: float = s + side * (ROAD_W / 2 + WALK_W / 2)
			var a := -TOWN
			for t in STREETS + [TOWN + ROAD_W / 2]:
				var b: float = t - ROAD_W / 2
				if b - a > 0.5:
					_road(Rect2(off - WALK_W / 2, a, WALK_W, b - a), "acera")
					_road(Rect2(a, off - WALK_W / 2, b - a, WALK_W), "acera")
				a = t + ROAD_W / 2


func _highways() -> void:
	for s in [-1.0, 1.0]:
		var from: float = TOWN if s > 0 else -HALF
		_road(Rect2(from, -HWY_W / 2, HALF - TOWN, HWY_W), "carretera")
		_road(Rect2(-HWY_W / 2, from, HWY_W, HALF - TOWN), "carretera")
		# barrera militar al final de cada carretera
		for along_x in [true, false]:
			var p := Vector3(s * (HALF - 4.0), 0, 0) if along_x else Vector3(0, 0, s * (HALF - 4.0))
			var xf := Transform3D(Basis(Vector3.UP, PI / 2 if along_x else 0.0), p)
			for k in 4:
				_prop(xf, "box", Vector3(k * 2.2 - 3.3, 0.5, 0), Vector3(2.0, 1.0, 0.7), C_CONCRETE, true)
	# las calles del pueblo que no siguen como carretera acaban en una valla
	for s in STREETS:
		if s == 0.0:
			continue
		for e in [-1.0, 1.0]:
			_prop(Transform3D(Basis(), Vector3(s, 0, e * (TOWN - 0.6))), "box", Vector3(0, 0.55, 0), Vector3(ROAD_W - 1.0, 1.1, 0.3), C_TRIM.darkened(0.2), true)
			_prop(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(e * (TOWN - 0.6), 0, s)), "box", Vector3(0, 0.55, 0), Vector3(ROAD_W - 1.0, 1.1, 0.3), C_TRIM.darkened(0.2), true)


# ------------------------------------------------------------------ pueblo
func _town_block(b: Vector2) -> void:
	var door := "S" if b.y < 0 else "N"
	var kind: String = SPECIAL_BLOCKS.get(b, "casas")
	match kind:
		"supermercado": _supermarket(b)
		"comisaria": _police(b)
		"hospital": _hospital(b)
		"parque": _park(b)
		"iglesia": _church(b)
		_:
			var central := absf(b.x) < 30.0 and absf(b.y) < 30.0
			for dx in [-7.5, 7.5]:
				var w := rng.randf_range(10.0, 12.0)
				var d := rng.randf_range(8.5, 10.0)
				var cz := b.y + rng.randf_range(-2.0, 2.0)
				var floors := 2 if not central and rng.randf() < 0.4 else 1
				_house(Transform3D(Basis(Vector3.UP, YAW[door]), Vector3(b.x + dx, 0, cz)), w, d, floors)
				# valla delante de la casa
				var fz := cz + (d / 2 + 2.2) * (1.0 if door == "S" else -1.0)
				_fence(Vector3(b.x + dx - w / 2 - 0.5, 0, fz), Vector3(b.x + dx + w / 2 + 0.5, 0, fz), true)


## Casa de una o dos plantas con la puerta en +Z local.
func _house(xf: Transform3D, w: float, d: float, floors: int) -> int:
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var h := {
		"center": Vector2(xf.origin.x, xf.origin.z), "w": w, "d": d, "yaw": _yaw_of(xf), "floors": floors,
		"rect": _rect_of(xf, w, d), "color": WALL_COLORS[rng.randi() % WALL_COLORS.size()],
		"roof": ROOF_COLORS[rng.randi() % ROOF_COLORS.size()], "roof_h": rng.randf_range(1.6, 2.2),
		"side": side, "px": side * w * rng.randf_range(0.2, 0.26), "seed": rng.randi(),
		"tile": tile_of(xf.origin.x, xf.origin.z), "lamp": rng.randf() < 0.5,
		# escalera pegada a la pared del lado grande, subiendo hacia el fondo
		"stairs_x": -side * (w / 2 - 0.75),
	}
	houses.append(h)
	footprints.append((h.rect as Rect2).grow(0.8))
	# muebles pegados a la pared del fondo
	for sx in [-w / 2 + 1.2, -1.8, 1.8, w / 2 - 1.2]:
		if absf(sx - h.px) < 1.15:
			continue
		if rng.randf() < 0.85:
			_container(HOME_FURNITURE[rng.randi() % HOME_FURNITURE.size()], xf, Vector3(sx, 0, -d / 2 + 0.5), 0.0, 0.0)
	if floors == 2:
		# arriba: dormitorio con armario y cajonera
		for sx in [side * (w / 2 - 1.2), side * 0.6]:
			var type: String = ["armario", "cajonera", "estanteria"][rng.randi() % 3]
			_container(type, xf, Vector3(sx, 0, -d / 2 + 0.5), 0.0, WALL_H)
		# cama (no se registra)
		_prop(xf, "box", Vector3(side * (w / 2 - 1.3), WALL_H + 0.25, d / 2 - 1.3), Vector3(1.6, 0.5, 2.0), Color(0.55, 0.52, 0.48), true)
	return houses.size() - 1


## Edificio grande de una planta (tienda, comisaría…), puerta ancha en +Z local.
func _hall(kind: String, name: String, xf: Transform3D, w: float, d: float, h: float, color: Color, door_w := 2.6) -> Dictionary:
	var hall := {
		"kind": kind, "name": name, "center": Vector2(xf.origin.x, xf.origin.z), "w": w, "d": d, "h": h,
		"yaw": _yaw_of(xf), "rect": _rect_of(xf, w, d), "color": color, "seed": rng.randi(),
		"tile": tile_of(xf.origin.x, xf.origin.z), "door_w": door_w,
		# tabiques interiores: [desde, hasta, [centros de los huecos]] en coordenadas locales
		"walls": [],
	}
	halls.append(hall)
	footprints.append((hall.rect as Rect2).grow(0.8))
	places.append({"name": name, "pos": xf.origin, "kind": kind})
	return hall


func _supermarket(b: Vector2) -> void:
	var xf := Transform3D(Basis(), Vector3(b.x, 0, b.y - 5.5))
	_hall("supermercado", "Supermercado", xf, 24.0, 15.0, 3.8, Color(0.66, 0.64, 0.58), 3.2)
	for row in 3:
		for col in 3:
			_container("estanteria_tienda", xf, Vector3(-6.5 + col * 6.5, 0, -4.3 + row * 3.1), 0.0, 0.0)
	for k in 5:
		_container("nevera", xf, Vector3(-9.6 + k * 1.0, 0, -7.0), 0.0, 0.0)
	# cajas registradoras
	for x in [-5.0, 5.0]:
		_prop(xf, "box", Vector3(x, 0.45, 4.6), Vector3(2.2, 0.9, 0.7), C_TRIM.darkened(0.3), true)
		_prop(xf, "box", Vector3(x + 0.5, 1.0, 4.6), Vector3(0.45, 0.2, 0.4), C_METAL.darkened(0.3), false)
	# aparcamiento
	_road(Rect2(b.x - 13.0, b.y + 2.0, 26.0, 12.0), "asfalto")
	for k in 3:
		_car(Vector3(b.x - 8.0 + k * 7.0 + rng.randf_range(-0.5, 0.5), 0, b.y + 7.5), PI / 2 + rng.randf_range(-0.2, 0.2))


func _police(b: Vector2) -> void:
	var xf := Transform3D(Basis(Vector3.UP, PI), Vector3(b.x, 0, b.y + 2.0))
	var hall := _hall("comisaria", "Comisaría", xf, 18.0, 13.0, 3.4, Color(0.55, 0.58, 0.6))
	hall.walls.append([Vector2(-9.0, -1.5), Vector2(9.0, -1.5), [-4.0, 6.0]])
	hall.walls.append([Vector2(3.0, -6.5), Vector2(3.0, -1.5), []])
	_prop(xf, "box", Vector3(0, 0.55, 3.0), Vector3(5.0, 1.1, 0.8), C_DARK_WOOD, true)
	for x in [-6.0, 5.5]:
		_container("cajonera", xf, Vector3(x, 0, 5.8), PI, 0.0)
	for k in 3:
		_container("taquilla", xf, Vector3(-8.0 + k * 0.7, 0, -6.0), 0.0, 0.0)
	_container("armero", xf, Vector3(-2.5, 0, -6.0), 0.0, 0.0)
	_container("caja_herramientas", xf, Vector3(0.5, 0, -6.0), 0.0, 0.0)
	# calabozo con barrotes
	for k in 9:
		if k == 4 or k == 5:
			continue  # la celda está abierta
		_prop(xf, "box", Vector3(3.6 + k * 0.6, 1.2, -3.8), Vector3(0.06, 2.4, 0.06), C_METAL.darkened(0.3), true)
	_car(xf * Vector3(5.0, 0, 9.2), 0.0, Color(0.85, 0.85, 0.82))


func _hospital(b: Vector2) -> void:
	var xf := Transform3D(Basis(), Vector3(b.x, 0, b.y - 3.0))
	var hall := _hall("hospital", "Hospital", xf, 26.0, 16.0, 3.6, Color(0.8, 0.8, 0.76), 3.0)
	hall.walls.append([Vector2(-13.0, -1.5), Vector2(13.0, -1.5), [-7.0, 7.0]])
	hall.walls.append([Vector2(0.0, -8.0), Vector2(0.0, -1.5), []])
	for k in 3:
		for s in [-1.0, 1.0]:
			_prop(xf, "box", Vector3(s * (3.0 + k * 3.2), 0.4, -6.4), Vector3(1.0, 0.5, 2.0), Color(0.82, 0.83, 0.8), true)
	for s in [-1.0, 1.0]:
		_container("botiquin", xf, Vector3(s * 12.4, 0, -4.5), s * -PI / 2, 0.0)
		_container("botiquin", xf, Vector3(s * 1.0, 0, -2.2), PI, 0.0)
	_container("estanteria", xf, Vector3(-12.4, 0, 3.0), PI / 2, 0.0)
	_container("cajonera", xf, Vector3(8.0, 0, 6.0), PI, 0.0)
	_prop(xf, "box", Vector3(5.0, 0.55, 3.5), Vector3(4.0, 1.1, 0.8), C_TRIM.darkened(0.2), true)
	_road(Rect2(b.x - 10.0, b.y + 5.5, 20.0, 7.0), "asfalto")
	_car(Vector3(b.x + 6.0, 0, b.y + 9.0), 0.1, Color(0.88, 0.88, 0.84))


func _church(b: Vector2) -> void:
	var xf := Transform3D(Basis(), Vector3(b.x + 3.0, 0, b.y - 2.0))
	_hall("iglesia", "Iglesia", xf, 12.0, 20.0, 6.5, Color(0.68, 0.64, 0.56), 2.4)
	for row in 6:
		for s in [-1.0, 1.0]:
			_prop(xf, "box", Vector3(s * 2.8, 0.45, -5.0 + row * 2.0), Vector3(3.6, 0.9, 0.5), C_WOOD, true)
	_prop(xf, "box", Vector3(0, 0.6, -8.4), Vector3(3.0, 1.2, 1.2), C_TRIM, true)
	_container("armario", xf, Vector3(4.8, 0, -9.4), 0.0, 0.0)
	_container("arcon", xf, Vector3(-4.6, 0, -9.3), 0.0, 0.0)
	# campanario
	var tower := Vector3(-8.5, 0, 7.0)
	_prop(xf, "box", tower + Vector3(0, 6.0, 0), Vector3(4.0, 12.0, 4.0), Color(0.6, 0.57, 0.5), true)
	_prop(xf, "box", tower + Vector3(0, 13.4, 0), Vector3(0.25, 2.8, 0.25), C_DARK_WOOD, false)
	_prop(xf, "box", tower + Vector3(0, 13.9, 0), Vector3(1.4, 0.25, 0.25), C_DARK_WOOD, false)
	footprints.append(Rect2(b.x + 3.0 - 10.5, b.y - 2.0 + 5.0, 4.0, 4.0).grow(1.0))


func _park(b: Vector2) -> void:
	places.append({"name": "Parque", "pos": Vector3(b.x, 0, b.y), "kind": "parque"})
	var xf := Transform3D(Basis(), Vector3(b.x, 0, b.y))
	_road(Rect2(b.x - 1.5, b.y - 14.0, 3.0, 28.0), "camino")
	_road(Rect2(b.x - 14.0, b.y - 1.5, 28.0, 3.0), "camino")
	# fuente en el centro
	_prop(xf, "cyl", Vector3(0, 0.35, 0), Vector3(2.4, 0.7, 2.4), C_CONCRETE, true)
	_prop(xf, "cyl", Vector3(0, 0.75, 0), Vector3(2.1, 0.1, 2.1), Color(0.2, 0.24, 0.26), false)
	_prop(xf, "cyl", Vector3(0, 1.3, 0), Vector3(0.3, 1.3, 0.3), C_CONCRETE, true)
	footprints.append(Rect2(b.x - 3.0, b.y - 3.0, 6.0, 6.0))
	# bancos
	for k in 6:
		var a := k * TAU / 6 + 0.5
		var p := Vector3(cos(a) * 7.0, 0, sin(a) * 7.0)
		var bxf := Transform3D(Basis(Vector3.UP, -a + PI / 2), xf * p)
		_prop(bxf, "box", Vector3(0, 0.42, 0), Vector3(1.8, 0.08, 0.5), C_WOOD, true)
		_prop(bxf, "box", Vector3(0, 0.75, -0.24), Vector3(1.8, 0.5, 0.06), C_WOOD, false)
	# árboles del parque
	var list: Array = []
	for k in 14:
		var p := Vector3(b.x + rng.randf_range(-13, 13), 0, b.y + rng.randf_range(-13, 13))
		if absf(p.x - b.x) < 3.5 or absf(p.z - b.y) < 3.5:
			continue
		list.append([p, rng.randf() < 0.7, rng.randi()])
	_extra_trees(list)
	_fence(Vector3(b.x - 14, 0, b.y - 14), Vector3(b.x + 14, 0, b.y - 14), true)
	_fence(Vector3(b.x - 14, 0, b.y + 14), Vector3(b.x + 14, 0, b.y + 14), true)
	_fence(Vector3(b.x - 14, 0, b.y - 14), Vector3(b.x - 14, 0, b.y + 14), true)
	_fence(Vector3(b.x + 14, 0, b.y - 14), Vector3(b.x + 14, 0, b.y + 14), true)


var _extra := []


func _extra_trees(list: Array) -> void:
	_extra.append_array(list)


# ------------------------------------------------------------------ afueras
## Casas sueltas a los lados de las carreteras, al salir del pueblo.
func _suburbs() -> void:
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var t := TOWN + 12.0
		while t < 156.0:
			for s in [-1.0, 1.0]:
				if rng.randf() > 0.75:
					continue
				var w := rng.randf_range(9.5, 12.0)
				var d := rng.randf_range(8.5, 10.0)
				var dist := HWY_W / 2 + 8.0 + d / 2
				var side: Vector3 = Vector3(-dir.z, 0, dir.x) * s
				var c: Vector3 = dir * t + side * dist
				# la puerta mira a la carretera
				var yaw := atan2(-side.x, -side.z)
				var xf := Transform3D(Basis(Vector3.UP, yaw), c)
				var r := _rect_of(xf, w + 3.0, d + 3.0)
				if _crosses_tile(r) or _overlaps(r):
					continue
				_house(xf, w, d, 2 if rng.randf() < 0.45 else 1)
				var fa: Vector3 = xf * Vector3(-w / 2 - 1.0, 0, d / 2 + 2.4)
				var fb: Vector3 = xf * Vector3(w / 2 + 1.0, 0, d / 2 + 2.4)
				_fence(fa, fb, true)
				if rng.randf() < 0.4:
					_car(xf * Vector3(w / 2 + 2.5, 0, d / 2 + 0.5), yaw + PI / 2 + rng.randf_range(-0.3, 0.3))
			t += rng.randf_range(22.0, 30.0)


func _gas_station(name: String, c: Vector3, yaw: float) -> void:
	# local: la carretera queda en +Z
	var xf := Transform3D(Basis(Vector3.UP, yaw), c)
	places.append({"name": name, "pos": c, "kind": "gasolinera"})
	var lot := _rect_of(xf, 26.0, 22.0)
	_road(_rect_of(xf * Transform3D(Basis(), Vector3(0, 0, 4.0)), 24.0, 16.0), "asfalto")
	footprints.append(lot)
	# marquesina sobre los surtidores
	for x in [-5.0, 5.0]:
		for z in [3.0, 9.0]:
			_prop(xf, "box", Vector3(x, 2.1, z), Vector3(0.35, 4.2, 0.35), C_TRIM.darkened(0.15), true)
	_prop(xf, "box", Vector3(0, 4.35, 6.0), Vector3(13.0, 0.4, 9.0), Color(0.72, 0.68, 0.55), false)
	for x in [-2.5, 2.5]:
		_prop(xf, "box", Vector3(x, 0.15, 6.0), Vector3(1.2, 0.3, 3.0), C_CONCRETE, true)
		_prop(xf, "box", Vector3(x, 1.0, 6.0), Vector3(0.7, 1.5, 0.5), Color(0.62, 0.55, 0.35), true)
		_prop(xf, "box", Vector3(x, 1.4, 6.26), Vector3(0.4, 0.3, 0.03), C_GLASS, false)
	# tienda
	var shop := xf * Transform3D(Basis(), Vector3(0, 0, -6.0))
	_hall("tienda", name, shop, 10.0, 8.0, 3.2, Color(0.7, 0.68, 0.6), 1.8)
	places.pop_back()
	_container("estanteria_tienda", shop, Vector3(-1.5, 0, -1.0), 0.0, 0.0)
	_container("estanteria_tienda", shop, Vector3(-1.5, 0, 1.4), 0.0, 0.0)
	_container("nevera", shop, Vector3(4.2, 0, -3.3), 0.0, 0.0)
	_prop(shop, "box", Vector3(3.2, 0.5, 2.0), Vector3(2.0, 1.0, 0.7), C_TRIM.darkened(0.3), true)
	for k in 2:
		_container("bidon", xf, Vector3(6.4 + k * 0.8, 0, -3.0), 0.0, 0.0)
	_car(xf * Vector3(2.5, 0, 9.6), yaw + PI / 2 + 0.1)
	_vehicle(xf * Vector3(-6.0, 0, 9.0), yaw + PI / 2, "coche")


func _farm(name: String, c: Vector3, yaw: float) -> void:
	# local: la carretera queda en +Z, a unos 45 m
	var xf := Transform3D(Basis(Vector3.UP, yaw), c)
	places.append({"name": name, "pos": c, "kind": "granja"})
	# era de tierra y camino hasta la carretera
	_road(_rect_of(xf * Transform3D(Basis(), Vector3(0, 0, 4.0)), 34.0, 22.0), "camino")
	var road_end: Vector3 = xf * Vector3(0, 0, 48.0 - HWY_W / 2 + 0.5)
	var start: Vector3 = xf * Vector3(0, 0, 14.5)
	var r := Rect2(Vector2(minf(start.x, road_end.x), minf(start.z, road_end.z)), Vector2.ZERO).expand(Vector2(maxf(start.x, road_end.x), maxf(start.z, road_end.z)))
	_road(r.grow(PATH_W / 2), "camino")
	# casa de labranza
	var house_xf := xf * Transform3D(Basis(), Vector3(-10.0, 0, 3.0))
	_house(house_xf, 11.0, 9.0, 2 if rng.randf() < 0.5 else 1)
	# granero
	var barn := xf * Transform3D(Basis(), Vector3(11.0, 0, -2.0))
	_hall("granero", "Granero", barn, 12.0, 14.0, 4.6, Color(0.42, 0.3, 0.24), 3.6)
	places.pop_back()
	_container("arcon", barn, Vector3(-4.0, 0, -6.2), 0.0, 0.0)
	_container("arcon", barn, Vector3(3.8, 0, -6.2), 0.0, 0.0)
	_container("caja_herramientas", barn, Vector3(5.2, 0, -2.0), -PI / 2, 0.0)
	_container("bidon", barn, Vector3(5.3, 0, 2.5), 0.0, 0.0)
	for k in 4:
		_prop(barn, "cyl", Vector3(-4.0 + (k % 2) * 1.5, 0.6 + (k / 2) * 1.2, 1.0), Vector3(1.2, 1.2, 1.2), C_HAY, true, PI / 2)
	# campo arado detrás
	var field := xf * Transform3D(Basis(), Vector3(0, 0, -21.0))
	_prop(field, "box", Vector3(0, 0.02, 0), Vector3(40.0, 0.04, 14.0), C_FIELD, false)
	for k in 7:
		_prop(field, "box", Vector3(0, 0.08, -6.0 + k * 2.0), Vector3(38.0, 0.16, 0.5), C_FIELD.darkened(0.2), false)
	footprints.append(_rect_of(field, 42.0, 16.0))
	_fence(field * Vector3(-21, 0, -8), field * Vector3(21, 0, -8), false)
	_fence(field * Vector3(-21, 0, -8), field * Vector3(-21, 0, 8), false)
	_fence(field * Vector3(21, 0, -8), field * Vector3(21, 0, 8), false)
	# pacas de paja sueltas por el campo
	for k in 5:
		_prop(field, "cyl", Vector3(rng.randf_range(-16, 16), 0.6, rng.randf_range(-5, 5)), Vector3(1.2, 1.2, 1.2), C_HAY, true, PI / 2)
	_vehicle(xf * Vector3(2.0, 0, 9.0), yaw + PI / 2, "furgoneta")


func _prefab(path: String, pos: Vector3, yaw: float) -> void:
	if not ResourceLoader.exists(path):
		return
	var scene: PackedScene = load(path)
	var root := scene.instantiate() as Node3D
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	var entry := {"scene": path, "pos": pos, "yaw": yaw, "tile": tile_of(pos.x, pos.z), "name": String(root.name), "conts": []}
	var aabb := AABB(Vector3.ZERO, Vector3.ZERO)
	for n in root.find_children("*", "Node3D", true, false):
		var local := _rel_xform(n, root)
		aabb = aabb.expand(local.origin)
		if n is Marker3D and n.name.begins_with("Mueble_"):
			var type := String(n.name).trim_prefix("Mueble_").rstrip("0123456789")
			if FURNITURE.has(type):
				var lx := xf * local
				entry.conts.append(_container(type, Transform3D(lx.basis, lx.origin), Vector3.ZERO, 0.0, 0.0))
		elif n is Marker3D and n.name.begins_with("Vehiculo"):
			var vx := xf * local
			_vehicle(vx.origin, _yaw_of(vx), "coche")
	root.free()
	prefabs.append(entry)
	places.append({"name": entry.name, "pos": pos, "kind": "lugar"})
	var corners := [aabb.position, aabb.end, Vector3(aabb.position.x, 0, aabb.end.z), Vector3(aabb.end.x, 0, aabb.position.z)]
	var r := Rect2(Vector2(pos.x, pos.z), Vector2.ZERO)
	for k in corners:
		var w: Vector3 = xf * k
		r = r.expand(Vector2(w.x, w.z))
	footprints.append(r.grow(2.0))


# ------------------------------------------------------------------ coches y postes
func _car(pos: Vector3, yaw: float, color := Color(0, 0, 0, 0)) -> void:
	if color.a == 0.0:
		color = CAR_COLORS[rng.randi() % CAR_COLORS.size()]
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	var car := {
		"pos": pos, "yaw": yaw, "color": color, "door": rng.randf() < 0.4, "blood": rng.randf() < 0.4,
		"seed": rng.randi(), "tile": tile_of(pos.x, pos.z),
	}
	car.cont = containers.size()
	containers.append({"type": "coche", "pos": xf * Vector3(0, 0.62, 0), "rot": yaw, "size": Vector3(4.2, 0.62, 1.8),
		"color": color, "tile": car.tile, "floor_y": 0.0})
	cars.append(car)


func _town_cars() -> void:
	var placed := 0
	var tries := 0
	while placed < 26 and tries < 200:
		tries += 1
		var r: float = STREETS[rng.randi() % STREETS.size()]
		var t := rng.randf_range(-TOWN + 6, TOWN - 6)
		if _near_street(t, 6.0) and absf(t) < 10.0:
			continue  # deja libre el cruce donde aparecen los jugadores
		if absf(r) < 1.0 and absf(t) < 12.0:
			continue
		var lane := 2.0 if rng.randf() < 0.5 else -2.0
		var along_x := rng.randf() < 0.5
		var pos := Vector3(t, 0, r + lane) if along_x else Vector3(r + lane, 0, t)
		if _car_near(pos, 6.0):
			continue
		_car(pos, (0.0 if along_x else PI / 2) + rng.randf_range(-0.3, 0.3))
		placed += 1


func _highway_cars() -> void:
	var placed := 0
	var tries := 0
	while placed < 24 and tries < 200:
		tries += 1
		# más atasco a la salida del pueblo
		var t := TOWN + 4.0 + pow(rng.randf(), 1.6) * (HALF - TOWN - 14.0)
		var dir: Vector3 = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][rng.randi() % 4]
		var lane := (1.8 if rng.randf() < 0.5 else -1.8) + rng.randf_range(-0.4, 0.4)
		var pos: Vector3 = dir * t + Vector3(-dir.z, 0, dir.x) * lane
		if _car_near(pos, 6.0) or _overlaps(Rect2(pos.x - 2.5, pos.z - 2.5, 5, 5)):
			continue
		var yaw := atan2(-dir.z, dir.x) + rng.randf_range(-0.4, 0.4)
		_car(pos, yaw)
		placed += 1


func _vehicle(pos: Vector3, yaw: float, kind: String) -> void:
	vehicles.append({"pos": pos, "yaw": yaw, "kind": kind, "color": CAR_COLORS[rng.randi() % CAR_COLORS.size()]})


func _car_near(p: Vector3, dist: float) -> bool:
	for v in vehicles:
		if (v.pos as Vector3).distance_to(p) < dist:
			return true
	for c in cars:
		if (c.pos as Vector3).distance_to(p) < dist:
			return true
	return false


func _near_street(t: float, margin: float) -> bool:
	for r in STREETS:
		if absf(t - r) < ROAD_W / 2 + margin:
			return true
	return false


func _power_lines() -> void:
	# en el pueblo: una línea de postes junto a cada calle norte-sur
	for r in STREETS:
		var x := r + ROAD_W / 2 + WALK_W - 0.3
		var prev := Vector3.INF
		var z := -TOWN + 6.0
		while z < TOWN - 4.0:
			if not _near_street(z, WALK_W):
				var p := Vector3(x, 0, z)
				poles.append({"pos": p, "prev": prev, "along_x": false, "tile": tile_of(p.x, p.z)})
				prev = p
			else:
				prev = Vector3.INF
			z += 14.0
	# por las carreteras, en un lado
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var prev := Vector3.INF
		var t := TOWN + 8.0
		var side: Vector3 = Vector3(-dir.z, 0, dir.x) * (HWY_W / 2 + 1.6)
		while t < HALF - 8.0:
			var p: Vector3 = dir * t + side
			if _overlaps(Rect2(p.x - 0.5, p.z - 0.5, 1, 1)):
				prev = Vector3.INF
			else:
				poles.append({"pos": p, "prev": prev, "along_x": dir.x != 0.0, "tile": tile_of(p.x, p.z)})
				prev = p
			t += 24.0


# ------------------------------------------------------------------ bosque
func _forest() -> void:
	for tx in TILES:
		for tz in TILES:
			var t := Vector2i(tx, tz)
			var r := tile_rect(t)
			var trng := RandomNumberGenerator.new()
			trng.seed = hash(t) ^ SEED
			var list: Array = []
			var town := r.intersects(Rect2(-TOWN, -TOWN, TOWN * 2, TOWN * 2))
			var target := 14 if town else 150
			var tries := 0
			while list.size() < target and tries < target * 3:
				tries += 1
				var x := trng.randf_range(r.position.x + 1.0, r.end.x - 1.0)
				var z := trng.randf_range(r.position.y + 1.0, r.end.y - 1.0)
				var inside := absf(x) < TOWN + 4.0 and absf(z) < TOWN + 4.0
				if town and inside and (_near_street(x, WALK_W + 1.0) or _near_street(z, WALK_W + 1.0) or trng.randf() < 0.5):
					continue
				# claros: menos árboles cerca de las carreteras y en manchas
				if not inside and (absf(x) < 14.0 or absf(z) < 14.0) and trng.randf() < 0.7:
					continue
				if blocked(x, z, 1.5):
					continue
				var alive := trng.randf() < (0.25 if inside else 0.7)
				list.append([Vector3(x, 0, z), alive, trng.randi()])
			trees[t] = list
	for e in _extra:
		var t := tile_of(e[0].x, e[0].z)
		trees[t].append(e)


# ------------------------------------------------------------------ piezas sueltas
func _container(type: String, xf: Transform3D, local: Vector3, rot: float, floor_y: float) -> int:
	var f: Array = FURNITURE[type]
	var size: Vector3 = f[0]
	var p: Vector3 = xf * (local + Vector3(0, floor_y + size.y / 2, 0))
	containers.append({"type": type, "pos": p, "rot": _yaw_of(xf) + rot, "size": size, "color": f[1],
		"tile": tile_of(p.x, p.z), "floor_y": floor_y})
	return containers.size() - 1


func _prop(xf: Transform3D, shape: String, local: Vector3, size: Vector3, color: Color, collide: bool, tilt := 0.0) -> void:
	var p: Vector3 = xf * local
	props.append({"shape": shape, "pos": p, "size": size, "color": color, "yaw": _yaw_of(xf), "tilt": tilt,
		"collide": collide, "tile": tile_of(p.x, p.z)})


func _fence(a: Vector3, b: Vector3, gap: bool) -> void:
	var m := (a + b) / 2
	fences.append({"a": a, "b": b, "gap": gap, "tile": tile_of(m.x, m.z)})


static func _yaw_of(xf: Transform3D) -> float:
	return atan2(xf.basis.z.x, xf.basis.z.z)


## Rectángulo en planta de un edificio w × d colocado con xf (giros de 90°).
static func _rect_of(xf: Transform3D, w: float, d: float) -> Rect2:
	var a: Vector3 = xf * Vector3(-w / 2, 0, -d / 2)
	var b: Vector3 = xf * Vector3(w / 2, 0, d / 2)
	return Rect2(minf(a.x, b.x), minf(a.z, b.z), absf(b.x - a.x), absf(b.z - a.z))


static func _rel_xform(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D()
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## ¿Pisa el borde entre dos zonas? (las casas no se parten entre zonas)
func _crosses_tile(r: Rect2) -> bool:
	return tile_of(r.position.x, r.position.y) != tile_of(r.end.x, r.end.y)


func _overlaps(r: Rect2) -> bool:
	for f in footprints:
		if f.intersects(r):
			return true
	return false


## Reparte todo por zonas para construir solo lo de cada una.
func _index() -> void:
	for tx in TILES:
		for tz in TILES:
			by_tile[Vector2i(tx, tz)] = {"houses": [], "halls": [], "cars": [], "props": [], "fences": [],
				"poles": [], "prefabs": [], "roads": [], "conts": [], "foot": []}
	for key in ["houses", "halls", "cars", "props", "fences", "poles", "prefabs"]:
		var list: Array = get(key)
		for i in list.size():
			by_tile[list[i].tile][key].append(i)
	for i in containers.size():
		if containers[i].type != "coche":
			by_tile[containers[i].tile].conts.append(i)
	for i in roads.size():
		for t in _tiles_of(roads[i].rect):
			by_tile[t].roads.append(i)
	for i in footprints.size():
		for t in _tiles_of(footprints[i]):
			by_tile[t].foot.append(i)


func _tiles_of(r: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var a := tile_of(r.position.x, r.position.y)
	var b := tile_of(r.end.x - 0.001, r.end.y - 0.001)
	for x in range(a.x, b.x + 1):
		for z in range(a.y, b.y + 1):
			out.append(Vector2i(x, z))
	return out
