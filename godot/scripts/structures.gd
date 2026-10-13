extends Node3D
## Lo que construyen los jugadores: banco, hoguera, caja, barricadas, muros,
## puertas, empalizadas, pinchos y camas. Vive en World/Estructuras para que
## tenga la misma ruta en todos los equipos.
##
## El anfitrión decide: alguien pide colocar algo, el anfitrión le pone un
## número (sid) y avisa a todos para que lo creen igual. La vida de cada pieza
## también la lleva el anfitrión.

## size: caja que ocupa · hp: vida · snap: rejilla al colocar · rot_step: giro con R
## mat: de qué se repara ("tablones" o "chatarra")
const TYPES := {
	"banco": {"name": "Banco de trabajo", "size": Vector3(1.6, 0.95, 0.8), "hp": 400, "mat": "tablones"},
	"hoguera": {"name": "Hoguera", "size": Vector3(1.1, 0.5, 1.1), "hp": 150, "mat": "tablones"},
	"caja": {"name": "Caja de almacenaje", "size": Vector3(1.0, 0.75, 0.6), "hp": 300, "mat": "tablones"},
	"barricada": {"name": "Barricada", "size": Vector3(1.9, 2.3, 0.25), "hp": 250, "mat": "tablones", "snap": 0.5, "rot_step": PI / 2},
	"muro_madera": {"name": "Muro de madera", "size": Vector3(2.0, 2.6, 0.22), "hp": 350, "mat": "tablones", "snap": 1.0, "rot_step": PI / 2},
	"muro_chatarra": {"name": "Muro de chatarra", "size": Vector3(2.0, 2.6, 0.22), "hp": 800, "mat": "chatarra", "snap": 1.0, "rot_step": PI / 2},
	"puerta": {"name": "Puerta de madera", "size": Vector3(2.0, 2.6, 0.22), "hp": 300, "mat": "tablones", "snap": 1.0, "rot_step": PI / 2},
	"empalizada": {"name": "Empalizada", "size": Vector3(2.0, 1.5, 0.35), "hp": 220, "mat": "tablones", "snap": 1.0, "rot_step": PI / 2},
	"pinchos": {"name": "Trampa de pinchos", "size": Vector3(1.2, 0.25, 1.2), "hp": 40, "mat": "clavos", "snap": 0.5, "trap": true},
	"cama": {"name": "Cama", "size": Vector3(1.0, 0.5, 2.0), "hp": 150, "mat": "tablones"},
}
## distancia a la que una estación (banco, hoguera) sirve para fabricar
const STATION_RANGE := 3.0

## sid -> {type, pos, rot, node, hp, open, owner}
var by_id := {}
var _next_id := 1
var _fires: Array[Dictionary] = []
var _trap_tick := 0.0
@onready var world: Node = get_parent()


func _process(delta: float) -> void:
	# las llamas bailan y la luz parpadea
	_fires = _fires.filter(func(f): return is_instance_valid(f.node))
	for f in _fires:
		f.t += delta
		if f.light:
			f.light.light_energy = f.energy * (0.8 + 0.2 * sin(f.t * 13.0) * sin(f.t * 7.3))
		for i in f.flames.size():
			var fl: Node3D = f.flames[i]
			var k := absf(sin(f.t * (6.0 + i * 2.3) + i))
			fl.scale = Vector3(0.9 + 0.2 * k, 0.75 + 0.45 * k, 0.9 + 0.2 * k)
	if multiplayer.is_server():
		_trap_tick += delta
		if _trap_tick >= 0.5:
			_trap_tick = 0.0
			_process_traps()


## ¿Hay una estación de este tipo cerca?
func near(pos: Vector3, type: String, dist := STATION_RANGE) -> bool:
	for sid in by_id:
		var s: Dictionary = by_id[sid]
		if s.type == type and Vector2(s.pos.x - pos.x, s.pos.z - pos.z).length() < dist:
			return true
	return false


## Estructura más cercana a la que miras (para reparar, abrir, dormir…), o -1.
func index_near(pos: Vector3, forward: Vector3, max_dist := 2.4) -> int:
	var best := -1
	var best_score := INF
	for sid in by_id:
		var s: Dictionary = by_id[sid]
		if s.type == "caja":
			continue  # las cajas se abren como muebles
		var to: Vector3 = s.pos - pos
		to.y = 0
		var size: Vector3 = TYPES[s.type].size
		var d := maxf(0.0, to.length() - maxf(size.x, size.z) * 0.45)
		if d > max_dist:
			continue
		var score := d - to.normalized().dot(forward) * 0.8
		if score < best_score:
			best_score = score
			best = sid
	return best


func max_hp(sid: int) -> int:
	return TYPES[by_id[sid].type].hp


## Receta con la que se fabrica una estructura (para devolver material al desmontarla).
static func recipe_for(type: String) -> RecipeData:
	for rid in Items.RECIPES:
		if Items.RECIPES[rid].result == "estructura:" + type:
			return Items.RECIPES[rid]
	return null


# ------------------------------------------------------------------ red
@rpc("any_peer", "call_local", "reliable")
func request_place(type: String, pos: Vector3, rot: float, owner_name := "") -> void:
	if not multiplayer.is_server() or not TYPES.has(type):
		return
	var sid := _next_id
	_next_id += 1
	var cont_idx: int = world.containers.size() if type == "caja" else -1
	_add.rpc(sid, type, pos, rot, cont_idx, owner_name)


@rpc("authority", "call_local", "reliable")
func _add(sid: int, type: String, pos: Vector3, rot: float, cont_idx: int, owner_name := "") -> void:
	if by_id.has(sid):
		return
	var node := _build(type)
	node.name = "%s_%d" % [type, sid]
	node.position = pos
	node.rotation.y = rot
	node.set_meta("sid", sid)
	add_child(node)
	by_id[sid] = {"type": type, "pos": pos, "rot": rot, "node": node, "hp": TYPES[type].hp,
		"open": false, "owner": owner_name}
	_next_id = maxi(_next_id, sid + 1)
	if type == "caja":
		world.add_box_container(node, cont_idx, sid)
	Sfx.play_at("hit", pos, -6.0, 0.7)


## Daño (zombis, fuego). Solo en el anfitrión.
func damage(sid: int, amount: float) -> void:
	if not multiplayer.is_server() or not by_id.has(sid):
		return
	var s: Dictionary = by_id[sid]
	if s.type == "caja":
		return
	var hp: int = int(s.hp - amount)
	if hp <= 0:
		_destroy.rpc(sid)
		# deja algo de material entre los restos
		var r := recipe_for(s.type)
		if r:
			var bits := {}
			for k in r.ingredients:
				var n := int(r.ingredients[k] / 3)
				if n > 0:
					bits[k] = n
			if not bits.is_empty():
				world.request_drop(s.pos, bits, "Restos de %s" % TYPES[s.type].name.to_lower(), false)
	else:
		_set_hp.rpc(sid, hp, true)


@rpc("authority", "call_local", "reliable")
func _set_hp(sid: int, hp: int, hit: bool) -> void:
	if not by_id.has(sid):
		return
	by_id[sid].hp = hp
	_paint_damage(sid)
	if hit:
		Sfx.play_at("hit_heavy", by_id[sid].pos, -2.0, 0.8)
		if randf() < 0.5:
			world.spawn_word(by_id[sid].pos + Vector3.DOWN * 0.6, "desmontar", Color(0.98, 0.95, 0.85), 0.9)


@rpc("authority", "call_local", "reliable")
func _destroy(sid: int) -> void:
	if not by_id.has(sid):
		return
	var s: Dictionary = by_id[sid]
	Sfx.play_at("hit_heavy", s.pos, 4.0, 0.5)
	world.spawn_word(s.pos, "derribo", Color(0.98, 0.95, 0.85), 1.4)
	s.node.queue_free()
	by_id.erase(sid)


@rpc("any_peer", "call_local", "reliable")
func request_repair(sid: int) -> void:
	if not multiplayer.is_server() or not by_id.has(sid):
		return
	var top := max_hp(sid)
	_set_hp.rpc(sid, mini(top, int(by_id[sid].hp + top * 0.35)), false)


@rpc("any_peer", "call_local", "reliable")
func request_toggle(sid: int) -> void:
	if not multiplayer.is_server() or not by_id.has(sid) or by_id[sid].type != "puerta":
		return
	_set_open.rpc(sid, not by_id[sid].open)


@rpc("authority", "call_local", "reliable")
func _set_open(sid: int, open: bool) -> void:
	if not by_id.has(sid):
		return
	var s: Dictionary = by_id[sid]
	s.open = open
	var leaf: Node3D = s.node.get_node("Hoja")
	leaf.rotation.y = -PI / 2 * 0.95 if open else 0.0
	(s.node.get_node("HojaColision") as CollisionShape3D).disabled = open
	Sfx.play_at("search", s.pos, -4.0, 1.6)


## Quitar una estructura propia (devuelve la mitad del material).
@rpc("any_peer", "call_local", "reliable")
func request_remove(sid: int) -> void:
	if not multiplayer.is_server() or not by_id.has(sid):
		return
	var s: Dictionary = by_id[sid]
	if s.type == "caja":
		return
	var r := recipe_for(s.type)
	_destroy.rpc(sid)
	if r:
		var back := {}
		for k in r.ingredients:
			var n := int(ceil(r.ingredients[k] / 2.0))
			if n > 0:
				back[k] = n
		world.request_drop(s.pos, back, "Material de %s" % TYPES[s.type].name.to_lower(), false)


## Las piezas dañadas se oscurecen (y la tinta marca grietas).
func _paint_damage(sid: int) -> void:
	var s: Dictionary = by_id[sid]
	var k := clampf(float(s.hp) / TYPES[s.type].hp, 0.0, 1.0)
	s.node.scale = Vector3.ONE
	for mi in s.node.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as ShaderMaterial
		if m == null:
			continue
		if not mi.has_meta("base_color"):
			mi.set_meta("base_color", m.get_shader_parameter("albedo"))
		var base: Color = mi.get_meta("base_color")
		var dm := m.duplicate() as ShaderMaterial
		dm.set_shader_parameter("albedo", base.darkened((1.0 - k) * 0.55))
		dm.set_shader_parameter("grit", lerpf(0.9, m.get_shader_parameter("grit"), k))
		(mi as MeshInstance3D).material_override = dm


## Pinchos: hieren a los zombis que pasan por encima y se desgastan.
func _process_traps() -> void:
	for sid in by_id.keys():
		var s: Dictionary = by_id[sid]
		if s.type != "pinchos":
			continue
		for z in get_tree().get_nodes_in_group("zombies"):
			if z.dead:
				continue
			var d := Vector2(z.global_position.x - s.pos.x, z.global_position.z - s.pos.z).length()
			if d < 0.8:
				z.damage(1.2, Vector3.ZERO, "fuego")
				z.slow(0.6)
				damage(sid, 1.0)
				if not by_id.has(sid):
					break


## Estructuras que no son contenedores (las cajas van con los muebles, por orden).
func send_state_to(peer: int) -> void:
	var list := []
	for sid in by_id:
		var s: Dictionary = by_id[sid]
		if s.type != "caja":
			list.append([sid, s.type, s.pos, s.rot, s.hp, s.open, s.owner])
	_sync.rpc_id(peer, list)


@rpc("authority", "call_remote", "reliable")
func _sync(list: Array) -> void:
	for e in list:
		_add(e[0], e[1], e[2], e[3], -1, e[6])
		_restore(e[0], e[4], e[5])


func _restore(sid: int, hp: int, open: bool) -> void:
	if not by_id.has(sid):
		return
	if hp < TYPES[by_id[sid].type].hp:
		_set_hp(sid, hp, false)
	if open:
		_set_open(sid, true)


func export_state() -> Array:
	var out := []
	for sid in by_id:
		var s: Dictionary = by_id[sid]
		if s.type != "caja":
			out.append({"sid": sid, "type": s.type, "pos": s.pos, "rot": s.rot, "hp": s.hp,
				"open": s.open, "owner": s.owner})
	return out


func import_state(list: Array) -> void:
	for e in list:
		_add(e.sid, e.type, e.pos, e.rot, -1, e.get("owner", ""))
		_restore(e.sid, e.get("hp", TYPES[e.type].hp), e.get("open", false))


func clear() -> void:
	for sid in by_id:
		by_id[sid].node.queue_free()
	by_id.clear()
	_next_id = 1


# ------------------------------------------------------------------ aspecto
## Malla de la estructura (también la usa la vista previa al colocar).
func _build(type: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	var size: Vector3 = TYPES[type].size
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2
	body.add_child(shape)
	var wood := Color(0.48, 0.35, 0.22)
	var dark := Color(0.28, 0.2, 0.14)
	var metal := Color(0.45, 0.47, 0.5)
	match type:
		"banco":
			world._box(Vector3(0, 0.88, 0), Vector3(1.6, 0.08, 0.8), wood, false, body, 0.3, 3.0)
			for x in [-0.7, 0.7]:
				for z in [-0.32, 0.32]:
					world._box(Vector3(x, 0.42, z), Vector3(0.08, 0.84, 0.08), dark, false, body)
			world._box(Vector3(0, 0.3, 0), Vector3(1.4, 0.05, 0.65), dark, false, body)
			# tornillo de banco y herramientas encima
			world._box(Vector3(0.6, 1.0, 0.25), Vector3(0.2, 0.14, 0.18), metal, false, body)
			world._box(Vector3(-0.3, 0.95, -0.1), Vector3(0.5, 0.03, 0.12), metal, false, body)
			world._box(Vector3(0.05, 0.95, 0.15), Vector3(0.08, 0.05, 0.3), dark, false, body)
		"hoguera":
			shape.position.y = 0.15
			box.size = Vector3(1.0, 0.3, 1.0)
			for i in 9:
				var a := TAU * i / 9.0
				var stone: MeshInstance3D = world._sphere_mesh(Vector3(cos(a) * 0.48, 0.08, sin(a) * 0.48), 0.13, Color(0.45, 0.44, 0.42))
				stone.get_parent().remove_child(stone)
				body.add_child(stone)
			for i in 3:
				var wood_log: MeshInstance3D = world._cyl_mesh(Vector3(0, 0.12, 0), 0.06, 0.06, 0.8, dark, body)
				wood_log.rotation = Vector3(PI / 2, TAU * i / 3.0, 0.25)
			_add_fire(body, Vector3(0, 0.15, 0), 0.8, 3.2, 12.0)
		"barricada":
			# tablones clavados en aspa sobre dos travesaños
			for i in 5:
				var plank: Node3D = world._box(Vector3(0, 0.25 + i * 0.47, 0), Vector3(1.95, 0.32, 0.06), wood if i % 2 == 0 else wood.darkened(0.15), false, body, 0.5, 3.0)
				plank.rotation.z = randf_range(-0.12, 0.12)
			for x in [-0.8, 0.8]:
				world._box(Vector3(x, 1.15, 0.08), Vector3(0.12, 2.3, 0.1), dark, false, body)
			var cross: Node3D = world._box(Vector3(0, 1.15, -0.06), Vector3(2.5, 0.18, 0.06), dark, false, body)
			cross.rotation.z = 0.85
		"muro_madera":
			for i in 7:
				var plank: Node3D = world._box(Vector3(-0.86 + i * 0.287, 1.3, 0), Vector3(0.27, 2.6, 0.2), wood if i % 2 == 0 else wood.darkened(0.12), false, body, 0.5, 3.0)
				plank.scale.y = randf_range(0.96, 1.0)
			for y in [0.5, 2.1]:
				world._box(Vector3(0, y, 0.13), Vector3(2.0, 0.14, 0.06), dark, false, body)
		"muro_chatarra":
			var sheets := [Color(0.45, 0.47, 0.5), Color(0.52, 0.42, 0.36), Color(0.38, 0.42, 0.42)]
			for i in 3:
				var sheet: Node3D = world._box(Vector3(-0.66 + i * 0.66, 1.3, 0), Vector3(0.7, 2.6, 0.18), sheets[i], false, body, 0.6, 2.0)
				sheet.rotation.z = randf_range(-0.03, 0.03)
			for y in [0.4, 1.3, 2.2]:
				world._box(Vector3(0, y, 0.11), Vector3(2.0, 0.1, 0.05), metal.darkened(0.3), false, body)
		"puerta":
			shape.queue_free()
			for x in [-0.8, 0.8]:
				var post := CollisionShape3D.new()
				var pb := BoxShape3D.new()
				pb.size = Vector3(0.4, 2.6, 0.22)
				post.shape = pb
				post.position = Vector3(x, 1.3, 0)
				body.add_child(post)
				world._box(Vector3(x, 1.3, 0), Vector3(0.4, 2.6, 0.22), wood.darkened(0.1), false, body, 0.5, 3.0)
			world._box(Vector3(0, 2.45, 0), Vector3(1.2, 0.3, 0.22), wood.darkened(0.1), false, body)
			var lintel := CollisionShape3D.new()
			var lb := BoxShape3D.new()
			lb.size = Vector3(1.2, 0.3, 0.22)
			lintel.shape = lb
			lintel.position = Vector3(0, 2.45, 0)
			body.add_child(lintel)
			# hoja de la puerta, con la bisagra a la izquierda
			var leaf := Node3D.new()
			leaf.name = "Hoja"
			leaf.position = Vector3(-0.6, 0, 0)
			body.add_child(leaf)
			world._box(Vector3(0.6, 1.15, 0), Vector3(1.18, 2.28, 0.08), wood, false, leaf, 0.4, 3.0)
			world._box(Vector3(1.05, 1.1, 0.07), Vector3(0.08, 0.08, 0.08), metal, false, leaf)
			var leaf_col := CollisionShape3D.new()
			leaf_col.name = "HojaColision"
			var lfb := BoxShape3D.new()
			lfb.size = Vector3(1.2, 2.3, 0.1)
			leaf_col.shape = lfb
			leaf_col.position = Vector3(0, 1.15, 0)
			body.add_child(leaf_col)
		"empalizada":
			for i in 8:
				var stake: MeshInstance3D = world._cyl_mesh(Vector3(-0.88 + i * 0.25, 0.7 + randf_range(-0.1, 0.1), 0), 0.02, 0.1, 1.5, wood.darkened(randf_range(0.0, 0.2)), body)
				stake.rotation.x = randf_range(-0.15, 0.25)
			world._box(Vector3(0, 0.6, 0.08), Vector3(2.0, 0.1, 0.06), dark, false, body)
		"pinchos":
			# no bloquea el paso: es una trampa
			shape.queue_free()
			body.collision_layer = 8
			world._box(Vector3(0, 0.03, 0), Vector3(1.2, 0.06, 1.2), dark, false, body, 0.5, 3.0)
			for i in 16:
				var spike: MeshInstance3D = world._cyl_mesh(Vector3(-0.45 + (i % 4) * 0.3, 0.16, -0.45 + (i / 4) * 0.3), 0.0, 0.035, 0.22, metal, body)
				spike.rotation.x = randf_range(-0.2, 0.2)
		"cama":
			world._box(Vector3(0, 0.2, 0), Vector3(1.0, 0.3, 2.0), dark, false, body)
			world._box(Vector3(0, 0.4, 0.05), Vector3(0.94, 0.14, 1.85), Color(0.6, 0.58, 0.5), false, body, 0.3, 4.0)
			world._box(Vector3(0, 0.5, -0.75), Vector3(0.6, 0.12, 0.35), Color(0.82, 0.8, 0.74), false, body)
			world._box(Vector3(0, 0.49, 0.35), Vector3(0.98, 0.1, 1.1), Color(0.35, 0.38, 0.48), false, body, 0.3, 4.0)
		"caja":
			world._box(Vector3(0, 0.36, 0), Vector3(1.0, 0.72, 0.6), wood, false, body, 0.4, 3.0)
			world._box(Vector3(0, 0.73, 0), Vector3(1.04, 0.05, 0.64), dark, false, body)
			for x in [-0.35, 0.35]:
				world._box(Vector3(x, 0.36, 0), Vector3(0.08, 0.74, 0.64), dark, false, body)
	return body


## Llamas de cómic: lenguas finas, inclinadas y rojas que bailan, con luz cálida.
## Son rojas a propósito: el filtro de tinta solo deja color en los rojos.
func _add_fire(parent: Node3D, at: Vector3, size: float, energy: float, light_range: float) -> void:
	var flames: Array[Node3D] = []
	var colors := [Color(0.95, 0.12, 0.04), Color(1.0, 0.3, 0.08), Color(1.0, 0.75, 0.3)]
	for i in 6:
		var inner := i >= 4
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = (0.07 if inner else 0.11) * size
		cone.height = randf_range(0.35, 0.8) * size * (0.7 if inner else 1.0)
		cone.radial_segments = 6
		cone.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = colors[2] if inner else colors[i % 2]
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = cone.height / 2
		var pivot := Node3D.new()
		var a := randf() * TAU
		pivot.position = at + Vector3(cos(a), 0, sin(a)) * randf_range(0.0, 0.16) * size
		pivot.rotation = Vector3(randf_range(-0.35, 0.35), randf() * TAU, randf_range(-0.35, 0.35))
		pivot.add_child(mi)
		parent.add_child(pivot)
		flames.append(pivot)
	var light: OmniLight3D = null
	if energy > 0.0:
		light = OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.28)
		light.light_energy = energy
		light.omni_range = light_range
		light.omni_attenuation = 1.2
		light.position = at + Vector3.UP * 0.7
		parent.add_child(light)
	_fires.append({"node": parent, "light": light, "flames": flames, "energy": energy, "t": randf() * 10.0})


# ------------------------------------------------------------------ fuego del molotov
## Charco de fuego: se ve en todos los equipos; el daño a zombis lo hace el anfitrión.
func spawn_fire_fx(pos: Vector3, duration: float) -> void:
	var holder := Node3D.new()
	holder.position = pos
	add_child(holder)
	for i in 4:
		var a := TAU * i / 4.0 + randf()
		_add_fire(holder, Vector3(cos(a), 0, sin(a)) * randf_range(0.3, 1.1), randf_range(0.8, 1.3), 1.4 if i == 0 else 0.0, 10.0)
	var scorch: MeshInstance3D = world._disc(Vector3(0, 0.07, 0), 1.6, Color(0.1, 0.09, 0.08), 0.9, holder)
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := holder.create_tween()
	tw.tween_interval(duration)
	tw.tween_callback(holder.queue_free)
