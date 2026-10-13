extends Node3D
## El mundo: un mapa grande (WorldLayout) que se construye por zonas
## alrededor de los jugadores (TileBuilder), el reloj, los muebles registrables,
## los bultos, el fuego y los efectos. Todos los equipos ven el mismo mapa porque
## el plano usa una semilla fija.

## Abriste un mueble: esto es lo que tiene.
signal container_opened(idx: int, loot: Dictionary)
## El mueble que tienes abierto cambió (alguien cogió o dejó algo).
signal container_changed(idx: int, loot: Dictionary)
## El anfitrión te da lo que pediste coger.
signal item_granted(idx: int, item: String, n: int)
## Se construyó o se quitó una zona del mapa.
signal tile_loaded(t: Vector2i)

const HALF := WorldLayout.HALF
const WALL_H := WorldLayout.WALL_H
const PAPER := WorldLayout.PAPER
## se construyen las zonas a menos de esta distancia de un jugador…
const LOAD_R := 75.0
## …y se quitan cuando todos están más lejos que esto
const UNLOAD_R := 110.0

var layout: WorldLayout
## construye las zonas (en un hilo aparte mientras se juega)
var builder: TileBuilder
## piezas sueltas en tiempo real (sangre, estructuras); nunca se usa desde el hilo
var helper: TileBuilder
var _task := -1
var _task_tile := Vector2i.ZERO
var _task_root: Node3D
## zonas construidas: Vector2i -> {root, nav, nav_ready}
var tiles := {}
## tejados de las zonas construidas: {rect, roof, upper, base, tile}
var _roofs: Array[Dictionary] = []
var _roof_state := {}
## Muebles y maleteros registrables, en el mismo orden en todos los equipos:
## {node, mesh, type, name, pos, empty, floor_y} y, solo en el anfitrión, {loot, rolled}.
## node y mesh son null mientras su zona no está construida.
var containers: Array[Dictionary] = []
var _fx: Node3D
var _fx_items: Array[Node3D] = []
var _bags: Node3D
## World/Estructuras: lo que construyen los jugadores
var structures: Node3D
var _sun: DirectionalLight3D
var _env: Environment
## el anfitrión calcula la navegación de cada zona para los zombis
var nav_enabled := false
var _stream_t := 0.0
## milisegundos que tardó en construirse la última zona (para medir)
var last_build_ms := 0.0

# ------------------------------------------------------------------ reloj
## minutos de juego desde el inicio (día 1, 08:00). 1 s real = 4 min de juego:
## un día entero dura 6 minutos, como en la versión web.
const MIN_PER_SEC := 4.0
const START_MINUTES := 8.0 * 60.0
const NIGHT_PAPER := Color(0.12, 0.13, 0.18)
const DUSK := Color(0.62, 0.45, 0.36)
var game_minutes := START_MINUTES
var clock_running := false
## 0 = noche cerrada, 1 = pleno día
var daylight := 1.0
var night := false
var _sync_t := 0.0
signal night_changed(is_night: bool)
## cuántos muebles vienen del mapa; los de después son bultos y mochilas
var _static_count := 0


func _ready() -> void:
	add_to_group("world")
	layout = WorldLayout.new()
	builder = TileBuilder.new(layout, true)
	helper = TileBuilder.new(layout)
	_build_environment()
	_build_ground()
	for c in layout.containers:
		containers.append({
			"node": null, "mesh": null, "type": c.type, "name": Items.CONTAINERS[c.type].name,
			"pos": c.pos, "empty": false, "color": c.color, "corpse": false, "floor_y": c.floor_y,
		})
	_fx = Node3D.new()
	_fx.name = "Fx"
	add_child(_fx)
	_bags = Node3D.new()
	_bags.name = "Bultos"
	add_child(_bags)
	_static_count = containers.size()
	structures = Node3D.new()
	structures.set_script(preload("res://scripts/structures.gd"))
	structures.name = "Estructuras"
	add_child(structures)
	ensure_loaded(stream_points())


func _exit_tree() -> void:
	if _task != -1:
		_wait_task()
		_task_root.free()


## Espera a que acabe la zona que se construye en el otro hilo. Mientras, vacía
## la cola del servidor de render: si el hilo le pidió algo, no se queda colgado.
func _wait_task() -> void:
	while not WorkerThreadPool.is_task_completed(_task):
		RenderingServer.force_sync()
		OS.delay_msec(1)
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1


func _process(delta: float) -> void:
	_process_fires(delta)
	_stream_t += delta
	if _stream_t > 0.2:
		_stream_t = 0.0
		update_streaming()
	if not clock_running:
		return
	game_minutes += delta * MIN_PER_SEC
	_apply_daylight()
	if multiplayer.is_server():
		_sync_t += delta
		if _sync_t > 5.0:
			_sync_t = 0.0
			_sync_clock.rpc(game_minutes)


@rpc("authority", "call_remote", "unreliable")
func _sync_clock(minutes: float) -> void:
	game_minutes = minutes


func day_number() -> int:
	return int(game_minutes / 1440.0) + 1


func hour() -> float:
	return fmod(game_minutes / 60.0, 24.0)


func clock_text() -> String:
	var h := hour()
	var phase := "Noche" if night else ("Mañana" if h < 12 else ("Tarde" if h < 19 else "Anochecer"))
	return "Día %d · %02d:%02d · %s" % [day_number(), int(h), int(fmod(game_minutes, 60.0)), phase]


func set_time(minutes: float) -> void:
	game_minutes = minutes
	_apply_daylight()


## Luz, cielo, niebla y farolas según la hora. De noche el papel se vuelve tinta.
func _apply_daylight() -> void:
	var h := hour()
	var l := clampf(sin(((h - 5.0) / 16.0) * PI) * 1.5, 0.0, 1.0)
	daylight = l
	var was := night
	night = l < 0.22
	if night != was:
		night_changed.emit(night)
	var dusk := clampf(1.0 - absf(l - 0.35) / 0.25, 0.0, 1.0) * 0.4
	var paper := NIGHT_PAPER.lerp(PAPER, l).lerp(DUSK, dusk)
	_env.background_color = paper
	_env.fog_light_color = paper
	_env.fog_depth_begin = lerpf(4.0, 18.0, l)
	_env.fog_depth_end = lerpf(38.0, 80.0, l)
	_env.ambient_light_color = Color(0.2, 0.24, 0.36).lerp(Color(0.42, 0.46, 0.56), l)
	_env.ambient_light_energy = lerpf(0.7, 0.9, l)
	# de día el sol cruza el cielo; de noche una luna fría y quieta
	var a := ((h - 5.0) / 16.0) * PI
	if l > 0.05:
		_sun.rotation = Vector3(-deg_to_rad(12.0 + 50.0 * absf(sin(a))), deg_to_rad(40.0) + a * 0.4, 0.0)
	else:
		_sun.rotation = Vector3(-deg_to_rad(55.0), deg_to_rad(-30.0), 0.0)
	_sun.light_energy = lerpf(0.35, 1.35, l)
	_sun.light_color = Color(0.55, 0.62, 0.9).lerp(Color(1.0, 0.95, 0.86), smoothstep(0.1, 0.4, l)).lerp(Color(1.0, 0.7, 0.5), dusk)
	var lamp_energy := clampf((0.35 - l) * 6.0, 0.0, 1.6)
	for lamp in get_tree().get_nodes_in_group("night_lights"):
		lamp.light_energy = lamp_energy * (0.85 + 0.15 * sin(game_minutes * 7.0 + lamp.position.x))


func _apply_settings() -> void:
	_sun.shadow_enabled = Settings.shadows > 0
	_sun.directional_shadow_max_distance = 40.0 if Settings.shadows == 1 else 70.0
	RenderingServer.directional_shadow_atlas_set_size(2048 if Settings.shadows == 1 else 4096, true)


## Navegación para los zombis (solo el anfitrión): una malla por zona.
func enable_navigation() -> void:
	nav_enabled = true
	for t in tiles:
		if tiles[t].nav == null:
			_bake_tile(t)


func _bake_tile(t: Vector2i) -> void:
	var entry: Dictionary = tiles[t]
	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	# solo la geometría del mapa: lo que construyen los jugadores no cuenta, así
	# los zombis van en línea recta, chocan con barricadas y muros, y los golpean
	nav.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	nav.geometry_source_group_name = builder.nav_group(t)
	nav.agent_radius = 0.5
	nav.agent_height = 1.75
	nav.agent_max_climb = 0.25
	nav.cell_size = 0.25
	nav.cell_height = 0.25
	# cada zona hornea su trozo y un borde, para que encajen con las de al lado
	var r := WorldLayout.tile_rect(t)
	nav.border_size = 2.0
	nav.filter_baking_aabb = AABB(Vector3(r.position.x - 2.0, -2.0, r.position.y - 2.0), Vector3(r.size.x + 4.0, 12.0, r.size.y + 4.0))
	var region := NavigationRegion3D.new()
	region.name = "Navegacion"
	region.navigation_mesh = nav
	entry.nav = region
	(entry.root as Node3D).add_child(region)
	region.bake_finished.connect(func(): entry.nav_ready = true)
	region.bake_navigation_mesh(true)


## ¿Hay malla de navegación lista en ese punto?
func nav_ready_at(p: Vector3) -> bool:
	var t := WorldLayout.tile_of(p.x, p.z)
	return tiles.has(t) and tiles[t].nav_ready


# ------------------------------------------------------------------ zonas (carga por cercanía)
## Dónde hace falta mapa: junto a cada jugador (el anfitrión, junto a todos).
func stream_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var main := get_tree().get_first_node_in_group("main")
	if main and main.in_game:
		for p in main.players.get_children():
			if p.is_inside_tree() and (multiplayer.is_server() or p.is_multiplayer_authority()):
				pts.append(p.global_position)
	if pts.is_empty():
		pts.append(Vector3(10, 0, 12))  # el menú mira al centro del pueblo
	return pts


## Construye la zona que más falta (una cada vez, en otro hilo) y quita las que sobran.
func update_streaming() -> void:
	var pts := stream_points()
	var keep := {}
	var want: Array = []
	for p in pts:
		var a := WorldLayout.tile_of(p.x - UNLOAD_R, p.z - UNLOAD_R)
		var b := WorldLayout.tile_of(p.x + UNLOAD_R, p.z + UNLOAD_R)
		for x in range(a.x, b.x + 1):
			for z in range(a.y, b.y + 1):
				var t := Vector2i(x, z)
				var d := _tile_distance(p, t)
				if d < UNLOAD_R:
					keep[t] = true
				if d < LOAD_R and not tiles.has(t):
					want.append([d, t])
	for t in tiles.keys():
		if not keep.has(t):
			_unload_tile(t)
	if _task != -1:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		_finish_task()
		return
	if want.is_empty():
		return
	want.sort_custom(func(x, y): return x[0] < y[0])
	_task_tile = want[0][1]
	_task = WorkerThreadPool.add_task(func(): _task_root = builder.build(_task_tile), false, "Zona")


func _finish_task() -> void:
	_wait_task()
	if tiles.has(_task_tile):
		_task_root.free()
		return
	_attach_tile(_task_tile, _task_root)


## Construye ya todo lo que hay alrededor de estos puntos (al empezar o al teletransportarse).
func ensure_loaded(pts: Array) -> void:
	if _task != -1:
		_finish_task()
	for p in pts:
		var a := WorldLayout.tile_of(p.x - LOAD_R, p.z - LOAD_R)
		var b := WorldLayout.tile_of(p.x + LOAD_R, p.z + LOAD_R)
		for x in range(a.x, b.x + 1):
			for z in range(a.y, b.y + 1):
				var t := Vector2i(x, z)
				if not tiles.has(t) and _tile_distance(p, t) < LOAD_R:
					_load_tile(t)


func _tile_distance(p: Vector3, t: Vector2i) -> float:
	var r := WorldLayout.tile_rect(t)
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dz := maxf(maxf(r.position.y - p.z, 0.0), p.z - r.end.y)
	return Vector2(dx, dz).length()


func _load_tile(t: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	_attach_tile(t, builder.build(t))
	last_build_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Mete en el mundo una zona recién construida y engancha sus muebles y tejados.
func _attach_tile(t: Vector2i, node: Node3D) -> void:
	# lo que el hilo dejó en la cola del render tiene que estar hecho antes de meterlo
	RenderingServer.force_sync()
	helper.finalize(node)
	add_child(node)
	tiles[t] = {"root": node, "nav": null, "nav_ready": false}
	for oc in builder.out_containers:
		var c: Dictionary = containers[oc[0]]
		c.node = oc[1]
		c.mesh = oc[2]
		_apply_container_look(oc[0])
	for r in builder.out_roofs:
		r.tile = t
		_roofs.append(r)
	if nav_enabled:
		_bake_tile(t)
	tile_loaded.emit(t)


func _unload_tile(t: Vector2i) -> void:
	var entry: Dictionary = tiles[t]
	tiles.erase(t)
	var td: Dictionary = layout.by_tile[t]
	for i in td.conts:
		containers[i].node = null
		containers[i].mesh = null
	for ci in td.cars:
		var idx: int = layout.cars[ci].cont
		containers[idx].node = null
		containers[idx].mesh = null
	_roofs = _roofs.filter(func(r): return r.tile != t)
	if _roof_state.get("tile", Vector2i(-1, -1)) == t:
		_roof_state = {}
	var root: Node3D = entry.root
	var region: NavigationRegion3D = entry.nav
	if region and region.is_baking():
		# que termine de hornear antes de borrarla
		root.visible = false
		root.process_mode = Node.PROCESS_MODE_DISABLED
		region.bake_finished.connect(root.queue_free)
	else:
		root.queue_free()


# ------------------------------------------------------------------ registrar muebles (red)
func container_index_near(pos: Vector3, forward: Vector3, max_dist := 2.2) -> int:
	var best := -1
	var best_score := INF
	for i in containers.size():
		var c: Dictionary = containers[i]
		if (c.type == "mochila" and c.empty) or c.get("gone", false) or c.node == null:
			continue
		if absf(pos.y - float(c.get("floor_y", 0.0))) > 1.7:
			continue  # está en otra planta
		var to: Vector3 = c.pos - pos
		to.y = 0
		var d := to.length() - (1.0 if c.type == "coche" else 0.4)
		if d > max_dist:
			continue
		var facing := to.normalized().dot(forward)
		var score := d - facing * 0.8
		if score < best_score and _reachable(pos, c):
			best_score = score
			best = i
	return best


## Sin paredes entre el jugador y el mueble.
func _reachable(pos: Vector3, c: Dictionary) -> bool:
	var target: Vector3 = c.pos
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.0, Vector3(target.x, pos.y + 0.6, target.z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.collider == c.node


# Modelo: el contenido de cada mueble vive en el anfitrión. Al abrirlo, quien
# lo abre recibe la lista y queda "mirando"; cada vez que alguien coge o deja
# algo, el anfitrión manda la lista nueva a todos los que lo miran.

@rpc("any_peer", "call_local", "reliable")
func request_open(idx: int) -> void:
	if not multiplayer.is_server() or idx < 0 or idx >= containers.size():
		return
	var sender := _sender()
	var c: Dictionary = containers[idx]
	_ensure_rolled(c)
	var viewers: Array = c.get("viewers", [])
	if sender not in viewers:
		viewers.append(sender)
	c.viewers = viewers
	_container_contents.rpc_id(sender, idx, c.loot.duplicate(), true)
	_update_empty(idx)


@rpc("any_peer", "call_local", "reliable")
func request_close(idx: int) -> void:
	if not multiplayer.is_server() or idx < 0 or idx >= containers.size():
		return
	var viewers: Array = containers[idx].get("viewers", [])
	viewers.erase(_sender())


@rpc("any_peer", "call_local", "reliable")
func request_take(idx: int, item: String, n: int) -> void:
	if not multiplayer.is_server() or idx < 0 or idx >= containers.size():
		return
	var c: Dictionary = containers[idx]
	_ensure_rolled(c)
	var got := mini(n, int(c.loot.get(item, 0)))
	if got > 0:
		c.loot[item] -= got
		if c.loot[item] <= 0:
			c.loot.erase(item)
		_grant.rpc_id(_sender(), idx, item, got)
	_notify(idx)


## Dejar cosas en un mueble (o devolver lo que no cabe).
@rpc("any_peer", "call_local", "reliable")
func return_loot(idx: int, items: Dictionary) -> void:
	if not multiplayer.is_server() or idx < 0 or idx >= containers.size() or items.is_empty():
		return
	var c: Dictionary = containers[idx]
	_ensure_rolled(c)
	for k in items:
		c.loot[k] = int(c.loot.get(k, 0)) + int(items[k])
	_notify(idx)


## Soltar en el suelo o morir: crea un bulto (o la mochila del cadáver) con esas cosas.
## Si ya hay un bulto al lado, se añade a ese.
@rpc("any_peer", "call_local", "reliable")
func request_drop(pos: Vector3, items: Dictionary, label: String, corpse: bool) -> void:
	if not multiplayer.is_server() or items.is_empty():
		return
	if not corpse:
		for i in range(_static_count, containers.size()):
			var c: Dictionary = containers[i]
			if not c.corpse and Vector2(c.pos.x - pos.x, c.pos.z - pos.z).length() < 1.6:
				return_loot(i, items)
				return
	var idx := containers.size()
	_add_bag.rpc(idx, pos, label, corpse)
	var c: Dictionary = containers[idx]
	c.loot = items.duplicate()
	c.rolled = true
	_update_empty(idx)


@rpc("authority", "call_local", "reliable")
func _container_contents(idx: int, loot: Dictionary, opened: bool) -> void:
	if opened:
		container_opened.emit(idx, loot)
	else:
		container_changed.emit(idx, loot)


@rpc("authority", "call_local", "reliable")
func _grant(idx: int, item: String, n: int) -> void:
	item_granted.emit(idx, item, n)


func _notify(idx: int) -> void:
	var c: Dictionary = containers[idx]
	for v in c.get("viewers", []):
		if v == 1 or v in multiplayer.get_peers():
			_container_contents.rpc_id(v, idx, c.loot.duplicate(), false)
	_update_empty(idx)


func _update_empty(idx: int) -> void:
	var empty: bool = containers[idx].loot.is_empty()
	if empty != containers[idx].empty:
		set_container_empty.rpc(idx, empty)


func _ensure_rolled(c: Dictionary) -> void:
	if not c.get("rolled", false):
		c.loot = Items.roll_loot(c.type)
		c.rolled = true


func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return s if s != 0 else 1


## Un jugador se fue: deja de "mirar" muebles.
func forget_peer(peer: int) -> void:
	for c in containers:
		c.get("viewers", []).erase(peer)


@rpc("authority", "call_local", "reliable")
func set_container_empty(idx: int, empty: bool) -> void:
	containers[idx].empty = empty
	_apply_container_look(idx)


## Pinta el mueble según su estado (vacío = más oscuro, desmontado = no está).
## Si su zona no está construida no hace nada: se aplica al construirla.
func _apply_container_look(idx: int) -> void:
	var c: Dictionary = containers[idx]
	if c.node == null or not is_instance_valid(c.node):
		return
	var node: Node3D = c.node
	if c.get("gone", false):
		# un coche desmontado se va entero, no solo su carrocería
		var target: Node3D = node.get_parent() if c.type == "coche" else node
		target.visible = false
		(node as StaticBody3D).collision_layer = 0
		return
	if c.type == "mochila":
		# los bultos vacíos desaparecen; si alguien deja algo, vuelven
		node.visible = not c.empty
		return
	var mesh: MeshInstance3D = c.mesh
	var base: Color = c.color
	mesh.material_override = _mat(base.darkened(0.45) if c.empty else base, 0.2, 3.0)


## Bulto en el suelo o mochila de un cadáver.
@rpc("authority", "call_local", "reliable")
func _add_bag(idx: int, pos: Vector3, label: String, corpse: bool) -> void:
	if idx != containers.size():
		push_warning("Índice de bulto desincronizado: %d vs %d" % [idx, containers.size()])
		return
	var body := StaticBody3D.new()
	body.name = "Bulto%d" % idx
	# capa propia: no choca con nada, solo sirve para identificarlo
	body.collision_layer = 8
	body.collision_mask = 0
	body.position = Vector3(pos.x, 0.0, pos.z)
	body.rotation.y = randf() * TAU
	_bags.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.5, 0.45)
	shape.shape = box
	shape.position.y = 0.25
	body.add_child(shape)
	var color := Color(0.36, 0.38, 0.26) if corpse else Color(0.45, 0.38, 0.28)
	var bag := _box(Vector3(0, 0.22, 0), Vector3(0.55, 0.42, 0.35), color, false, body, 0.2, 3.0)
	_box(Vector3(0, 0.38, 0.05), Vector3(0.5, 0.12, 0.3), color.darkened(0.25), false, body, 0.2, 3.0)
	if corpse:
		_blood(body.position, 1.2, body)
	containers.append({
		"node": body, "mesh": bag, "type": "mochila", "name": label,
		"pos": body.global_position, "empty": false, "color": color, "corpse": corpse,
	})


## Al unirse alguien, el anfitrión le pasa los bultos, cajas, estructuras,
## muebles desmontados y vacíos, y la hora. Los contenedores nuevos van en el
## mismo orden que en el anfitrión para que los números coincidan.
func send_state_to(peer: int) -> void:
	structures.send_state_to(peer)
	var dyn := []
	for i in range(_static_count, containers.size()):
		var c: Dictionary = containers[i]
		if c.type == "caja":
			var st: Dictionary = structures.by_id[c.sid]
			dyn.append(["caja", i, c.sid, st.pos, st.rot])
		else:
			dyn.append(["bolsa", i, c.pos, c.name, c.corpse])
	var empties := PackedInt32Array()
	var gone := PackedInt32Array()
	for i in containers.size():
		if containers[i].empty:
			empties.append(i)
		if containers[i].get("gone", false):
			gone.append(i)
	_sync_state.rpc_id(peer, dyn, empties, gone, game_minutes)


@rpc("authority", "call_remote", "reliable")
func _sync_state(dyn: Array, empties: PackedInt32Array, gone: PackedInt32Array, minutes: float) -> void:
	set_time(minutes)
	for d in dyn:
		if d[1] != containers.size():
			continue
		if d[0] == "caja":
			structures._add(d[2], "caja", d[3], d[4], d[1])
		else:
			_add_bag(d[1], d[2], d[3], d[4])
	for i in empties:
		set_container_empty(i, true)
	for i in gone:
		_set_gone(i)


## Estado del mundo para el guardado (solo en el anfitrión).
func export_state() -> Dictionary:
	var conts := {}
	var gone := []
	for i in _static_count:
		var c: Dictionary = containers[i]
		if c.get("rolled", false):
			conts[i] = c.loot.duplicate()
		if c.get("gone", false):
			gone.append(i)
	var dyn := []
	for i in range(_static_count, containers.size()):
		var c: Dictionary = containers[i]
		if c.type == "caja":
			var st: Dictionary = structures.by_id[c.sid]
			dyn.append({"kind": "caja", "sid": c.sid, "pos": st.pos, "rot": st.rot, "loot": c.loot.duplicate()})
		elif not c.loot.is_empty():
			dyn.append({"kind": "bolsa", "pos": c.pos, "name": c.name, "corpse": c.corpse, "loot": c.loot.duplicate()})
	return {"containers": conts, "dynamic": dyn, "gone": gone, "structures": structures.export_state(),
		"minutes": game_minutes}


func import_state(d: Dictionary) -> void:
	reset_containers()
	set_time(d.get("minutes", START_MINUTES))
	var conts: Dictionary = d.get("containers", {})
	for i in conts:
		if i < _static_count:
			var c: Dictionary = containers[i]
			c.loot = conts[i]
			c.rolled = true
			if c.loot.is_empty():
				set_container_empty(i, true)
	for i in d.get("gone", []):
		if i < _static_count:
			_set_gone(i)
	structures.import_state(d.get("structures", []))
	# "bags" es el formato de antes de la Fase 2
	var dyn: Array = d.get("dynamic", [])
	for b in d.get("bags", []):
		dyn.append({"kind": "bolsa", "pos": b.pos, "name": b.name, "corpse": b.corpse, "loot": b.loot})
	for e in dyn:
		var idx := containers.size()
		if e.kind == "caja":
			structures._add(e.sid, "caja", e.pos, e.rot, idx)
		else:
			_add_bag(idx, e.pos, e.name, e.corpse)
		containers[idx].loot = e.loot
		containers[idx].rolled = true
		set_container_empty(idx, e.loot.is_empty())


func reset_containers() -> void:
	set_time(START_MINUTES)
	if structures:
		structures.clear()
	for c in containers.slice(_static_count):
		if is_instance_valid(c.node):
			c.node.queue_free()
	containers.resize(_static_count)
	for i in containers.size():
		var c: Dictionary = containers[i]
		c.erase("loot")
		c.erase("rolled")
		c.erase("viewers")
		c.erase("seen")
		if c.get("gone", false):
			c.erase("gone")
			if c.node != null and is_instance_valid(c.node):
				var node: Node3D = c.node
				(node.get_parent() if c.type == "coche" else node).visible = true
				(node as StaticBody3D).collision_layer = 1
		if c.empty:
			set_container_empty(i, false)
	fires.clear()


## Caja de almacenaje construida: un contenedor más (vacío al principio).
func add_box_container(node: Node3D, idx: int, sid: int) -> void:
	if idx >= 0 and idx != containers.size():
		push_warning("Índice de caja desincronizado: %d vs %d" % [idx, containers.size()])
	var mesh: MeshInstance3D = node.find_children("*", "MeshInstance3D", false, false)[0]
	containers.append({
		"node": node, "mesh": mesh, "type": "caja", "name": "Caja de almacenaje",
		"pos": node.global_position, "empty": true, "color": Color(0.48, 0.35, 0.22), "corpse": false,
		"sid": sid, "loot": {}, "rolled": true,
	})
	set_container_empty(containers.size() - 1, true)


# ------------------------------------------------------------------ desmontar
## Desmontar un mueble o coche: desaparece y deja sus materiales (y lo que
## tuviera dentro) en un montón en el suelo.
@rpc("any_peer", "call_local", "reliable")
func request_dismantle(idx: int) -> void:
	if not multiplayer.is_server() or idx < 0 or idx >= _static_count:
		return
	var c: Dictionary = containers[idx]
	if c.get("gone", false):
		return
	_ensure_rolled(c)
	var items := Items.roll_dismantle(c.type)
	for k in c.loot:
		items[k] = int(items.get(k, 0)) + int(c.loot[k])
	c.loot = {}
	_set_gone.rpc(idx)
	var drop_pos: Vector3 = c.pos
	drop_pos.y = 0
	request_drop(drop_pos, items, "Restos de %s" % c.name.to_lower(), false)


@rpc("authority", "call_local", "reliable")
func _set_gone(idx: int) -> void:
	var c: Dictionary = containers[idx]
	c.gone = true
	c.empty = true
	c.loot = {}
	_apply_container_look(idx)
	Sfx.play_at("hit_heavy", c.pos, 0.0, 0.6)


# ------------------------------------------------------------------ fuego (molotov)
## Fuegos activos: {pos, until}. Todos los equipos la tienen (para quemarse);
## el anfitrión además quema zombis.
var fires: Array[Dictionary] = []
const FIRE_RADIUS := 2.4
const FIRE_TIME := 7.0
var _fire_tick := 0.0


@rpc("any_peer", "call_local", "reliable")
func request_fire(from: Vector3, land: Vector3, flight: float) -> void:
	if not multiplayer.is_server():
		return
	_throw_fx.rpc(from, land, flight)


@rpc("authority", "call_local", "reliable")
func _throw_fx(from: Vector3, land: Vector3, flight: float) -> void:
	# la botella vuela en arco y al romperse prende el suelo
	var bottle := _box(from, Vector3(0.1, 0.24, 0.1), Color(0.35, 0.45, 0.3), false, _fx)
	var tw := bottle.create_tween()
	tw.tween_method(func(t: float):
		bottle.position = from.lerp(land, t) + Vector3.UP * sin(t * PI) * 2.0
		bottle.rotation.x = t * 12.0, 0.0, 1.0, flight)
	tw.tween_callback(func():
		bottle.queue_free()
		_ignite(land))


func _ignite(pos: Vector3) -> void:
	fires.append({"pos": pos, "until": Time.get_ticks_msec() + int(FIRE_TIME * 1000)})
	structures.spawn_fire_fx(pos, FIRE_TIME)
	Sfx.play_at("shot", pos, -2.0, 0.45)
	Sfx.play_at("search", pos, 4.0, 0.5)
	spawn_word(pos, "fuego", Color(1.0, 0.55, 0.15), 1.4)


## ¿Hay fuego en esta posición? (para quemar a quien lo pise)
func in_fire(pos: Vector3) -> bool:
	for f in fires:
		if Vector2(f.pos.x - pos.x, f.pos.z - pos.z).length() < FIRE_RADIUS:
			return true
	return false


func _process_fires(delta: float) -> void:
	var now := Time.get_ticks_msec()
	fires = fires.filter(func(f): return f.until > now)
	if fires.is_empty() or not multiplayer.is_server():
		return
	_fire_tick += delta
	if _fire_tick < 0.5:
		return
	_fire_tick = 0.0
	for z in get_tree().get_nodes_in_group("zombies"):
		if not z.dead and in_fire(z.global_position):
			z.damage(1.6, Vector3.ZERO, "fuego")


# ------------------------------------------------------------------ efectos en tiempo real
const FONT_WORDS := preload("res://fonts/Bangers-Regular.ttf")
const WORDS := {
	"puños": ["¡PAF!", "¡PUM!", "¡ZAS!"],
	"bate": ["¡CRACK!", "¡PLAF!", "¡TONC!"],
	"hacha": ["¡CHAC!", "¡CRUNCH!", "¡ZAC!"],
	"pistola": ["¡BANG!"],
	"muerte": ["¡CHOF!", "¡PLOF!"],
	"herido": ["¡AGH!", "¡AY!", "¡ARGH!"],
	"fuego": ["¡FUUUSH!", "¡FLAMM!"],
	"desmontar": ["¡CRAC!", "¡ÑIIIC!", "¡CLONC!"],
	"derribo": ["¡CRASH!", "¡CATACROC!"],
	"horda": ["¡GRAAAH!"],
}


## Onomatopeya de cómic que salta en el mundo y se desvanece.
func spawn_word(pos: Vector3, kind: String, color := Color(0.98, 0.95, 0.85), size := 1.0) -> void:
	var options: Array = WORDS.get(kind, [kind])
	var l := Label3D.new()
	l.text = options[randi() % options.size()]
	l.font = FONT_WORDS
	l.font_size = 110
	l.outline_size = 26
	l.modulate = color
	l.outline_modulate = Color(0.07, 0.065, 0.075)
	l.pixel_size = 0.005 * size
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.position = pos + Vector3(randf_range(-0.3, 0.3), 1.6 + randf_range(0.0, 0.3), randf_range(-0.3, 0.3))
	l.scale = Vector3.ONE * 0.3
	_fx.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE * 1.15, 0.08)
	tw.tween_property(l, "scale", Vector3.ONE, 0.06)
	tw.tween_interval(0.55)
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 0.5, 0.35)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(l.queue_free)
## Mancha de sangre (golpes, heridas). Se borran las más viejas.
func spawn_blood(pos: Vector3, size: float) -> void:
	var splat := Node3D.new()
	_fx.add_child(splat)
	_blood(pos, size, splat)
	_fx_items.append(splat)
	while _fx_items.size() > 240:
		_fx_items.pop_front().queue_free()


## Oculta el tejado de la casa en la que está el jugador local (y la planta de
## arriba si está abajo). Siguen proyectando sombra: el interior queda en penumbra.
func update_roofs(pos: Vector3) -> void:
	var inside: Dictionary = {}
	for r in _roofs:
		if (r.rect as Rect2).has_point(Vector2(pos.x, pos.z)) and pos.y < r.base + 0.5:
			inside = r
			break
	var upstairs := pos.y > WALL_H - 0.6
	var roof: Node3D = inside.get("roof")
	var upper: Node3D = inside.get("upper") if not upstairs else null
	if roof == _roof_state.get("roof") and upper == _roof_state.get("upper"):
		return
	for key in ["roof", "upper"]:
		var n: Node3D = _roof_state.get(key)
		if n and is_instance_valid(n):
			_set_shadow_only(n, false)
	if roof:
		_set_shadow_only(roof, true)
	if upper:
		_set_shadow_only(upper, true)
	_roof_state = {"roof": roof, "upper": upper, "tile": inside.get("tile", Vector2i(-1, -1))}


func _set_shadow_only(node: Node3D, hidden: bool) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
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
	_sun = sun
	Settings.changed.connect(_apply_settings)
	_apply_settings()

	var env := Environment.new()
	_env = env
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


# ------------------------------------------------------------------ suelo y límites
func _build_ground() -> void:
	# un solo suelo para todo el mapa; cuenta para la navegación de todas las zonas
	helper.rng.randomize()
	var ground := _box(Vector3(0, -0.5, 0), Vector3(HALF * 2 + 40, 1, HALF * 2 + 40), WorldLayout.C_GRASS, true, self, 0.55, 0.35)
	ground.name = "Suelo"
	for x in WorldLayout.TILES:
		for z in WorldLayout.TILES:
			ground.add_to_group(builder.nav_group(Vector2i(x, z)))
	# paredes invisibles en el borde del mapa
	for s in [-1.0, 1.0]:
		_collider(Vector3(s * HALF, 5, 0), Vector3(1, 10, HALF * 2))
		_collider(Vector3(0, 5, s * HALF), Vector3(HALF * 2, 10, 1))


func _collider(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)


# ------------------------------------------------------------------ utilidades (también las usan las estructuras)
func _mat(color: Color, grit := 0.35, grit_scale := 1.6) -> ShaderMaterial:
	return helper._mat(color, grit, grit_scale)


func _box(pos: Vector3, size: Vector3, color: Color, collide := true, parent: Node3D = self, grit := 0.35, grit_scale := 1.6) -> Node3D:
	return helper._box(pos, size, color, collide, parent, grit, grit_scale)


func _cyl_mesh(pos: Vector3, top: float, bottom: float, h: float, color: Color, parent: Node3D = self) -> MeshInstance3D:
	return helper._cyl_mesh(pos, top, bottom, h, color, parent)


func _sphere_mesh(pos: Vector3, r: float, color: Color, parent: Node3D = self) -> MeshInstance3D:
	return helper._sphere_mesh(pos, r, color, parent)


func _disc(pos: Vector3, r: float, color: Color, squash: float, parent: Node3D = self) -> MeshInstance3D:
	return helper._disc(pos, r, color, squash, parent)


func _blood(pos: Vector3, size: float, parent: Node3D = self) -> void:
	helper._blood(pos, size, parent)
