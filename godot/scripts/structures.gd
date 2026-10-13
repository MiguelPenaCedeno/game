extends Node3D
## Lo que construyen los jugadores: banco de trabajo, hoguera, caja de
## almacenaje… (y en la Fase 3, muros y barricadas). Vive en World/Estructuras
## para que tenga la misma ruta en todos los equipos.
##
## El anfitrión decide: alguien pide colocar algo, el anfitrión le pone un
## número (sid) y avisa a todos para que lo creen igual.

const TYPES := {
	"banco": {"name": "Banco de trabajo", "size": Vector3(1.6, 0.95, 0.8)},
	"hoguera": {"name": "Hoguera", "size": Vector3(1.1, 0.5, 1.1)},
	"caja": {"name": "Caja de almacenaje", "size": Vector3(1.0, 0.75, 0.6)},
}
## distancia a la que una estación (banco, hoguera) sirve para fabricar
const STATION_RANGE := 3.0

## sid -> {type, pos, rot, node}
var by_id := {}
var _next_id := 1
var _fires: Array[Dictionary] = []
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


## ¿Hay una estación de este tipo cerca?
func near(pos: Vector3, type: String, dist := STATION_RANGE) -> bool:
	for sid in by_id:
		var s: Dictionary = by_id[sid]
		if s.type == type and Vector2(s.pos.x - pos.x, s.pos.z - pos.z).length() < dist:
			return true
	return false


# ------------------------------------------------------------------ red
@rpc("any_peer", "call_local", "reliable")
func request_place(type: String, pos: Vector3, rot: float) -> void:
	if not multiplayer.is_server() or not TYPES.has(type):
		return
	var sid := _next_id
	_next_id += 1
	var cont_idx: int = world.containers.size() if type == "caja" else -1
	_add.rpc(sid, type, pos, rot, cont_idx)


@rpc("authority", "call_local", "reliable")
func _add(sid: int, type: String, pos: Vector3, rot: float, cont_idx: int) -> void:
	if by_id.has(sid):
		return
	var node := _build(type)
	node.name = "%s_%d" % [type, sid]
	node.position = pos
	node.rotation.y = rot
	add_child(node)
	by_id[sid] = {"type": type, "pos": pos, "rot": rot, "node": node}
	_next_id = maxi(_next_id, sid + 1)
	if type == "caja":
		world.add_box_container(node, cont_idx, sid)
	Sfx.play_at("hit", pos, -6.0, 0.7)


## Estructuras que no son contenedores (las cajas van con los muebles, por orden).
func send_state_to(peer: int) -> void:
	var list := []
	for sid in by_id:
		var s: Dictionary = by_id[sid]
		if s.type != "caja":
			list.append([sid, s.type, s.pos, s.rot])
	_sync.rpc_id(peer, list)


@rpc("authority", "call_remote", "reliable")
func _sync(list: Array) -> void:
	for e in list:
		_add(e[0], e[1], e[2], e[3], -1)


func export_state() -> Array:
	var out := []
	for sid in by_id:
		var s: Dictionary = by_id[sid]
		if s.type != "caja":
			out.append({"sid": sid, "type": s.type, "pos": s.pos, "rot": s.rot})
	return out


func import_state(list: Array) -> void:
	for e in list:
		_add(e.sid, e.type, e.pos, e.rot, -1)


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
