extends CharacterBody3D
## Ciervo o conejo del bosque. Como los zombis, su cerebro corre en el
## anfitrión y los demás reciben posición y giro. Pastan, deambulan y huyen
## en cuanto te ven o te oyen (agachado te acercas más). Muertos, dejan carne.
## Están en el grupo "zombies" para que las armas, los coches y el fuego les
## afecten igual, y en "animals" para distinguirlos.

const GRAVITY := 16.0
const KINDS := {
	"ciervo": {"name": "Ciervo", "hp": 6.0, "run": 7.5, "walk": 1.3, "meat": Vector2i(3, 5), "sight": 26.0, "hear": 1.3},
	"conejo": {"name": "Conejo", "hp": 1.5, "run": 6.0, "walk": 0.8, "meat": Vector2i(1, 1), "sight": 14.0, "hear": 0.8},
}
const FUR := {"ciervo": Color(0.5, 0.37, 0.24), "conejo": Color(0.52, 0.47, 0.4)}

@export var kind := "ciervo"
@export var net_pos := Vector3.ZERO
@export var net_yaw := 0.0
@export var dead := false:
	set(value):
		dead = value
		if is_node_ready() and dead:
			_on_died()

var hp := 3.0
var state := "graze"
var _dir := Vector3.ZERO
var _t := 0.0
var _think := 0.0
var _flee_from := Vector3.ZERO
var _dead_t := 0.0
var _phase := 0.0
var _speed := 0.0
var _last_pos := Vector3.ZERO
var _body: Node3D
var _legs: Array[Node3D] = []
var _world: Node


func _ready() -> void:
	add_to_group("zombies")
	add_to_group("animals")
	collision_layer = 4
	collision_mask = 1
	_world = get_tree().get_first_node_in_group("world")
	_build()
	_last_pos = position
	if multiplayer.is_server():
		hp = KINDS[kind].hp
		_t = randf_range(1.0, 4.0)
	else:
		set_physics_process(false)
		position = net_pos
		rotation.y = net_yaw
	if dead:
		_on_died()


func spec() -> Dictionary:
	return KINDS.get(kind, KINDS.conejo)


func _process(delta: float) -> void:
	if multiplayer.is_server():
		net_pos = position
		net_yaw = rotation.y
	else:
		if position.distance_squared_to(net_pos) > 25.0:
			position = net_pos
		else:
			position = position.lerp(net_pos, 1.0 - exp(-12.0 * delta))
		rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - exp(-12.0 * delta))
	if dead:
		_dead_t += delta
		_body.rotation.z = lerpf(_body.rotation.z, PI / 2, clampf(delta * 6.0, 0.0, 1.0))
		if multiplayer.is_server() and _dead_t > 30.0:
			queue_free()
		return
	var moved := Vector2(position.x - _last_pos.x, position.z - _last_pos.z).length() / maxf(delta, 1e-4)
	_last_pos = position
	# patas: trote o galope según la velocidad; la cabeza baja a pastar
	_phase += delta * (4.0 + moved * 2.2)
	var swing := clampf(moved / 4.0, 0.0, 1.0) * 0.7
	for i in _legs.size():
		_legs[i].rotation.x = sin(_phase + (PI if i % 2 == 0 else 0.0) + (0.0 if i < 2 else PI * 0.5)) * swing
	_body.position.y = absf(sin(_phase)) * 0.06 * swing


func _physics_process(delta: float) -> void:
	if dead:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var s := spec()
	_think -= delta
	if _think <= 0.0:
		_think = 0.3
		_sense()
	_t -= delta
	var spd := 0.0
	match state:
		"flee":
			spd = s.run
			var away := global_position - _flee_from
			away.y = 0
			_dir = _dir.lerp(away.normalized(), clampf(delta * 3.0, 0.0, 1.0)).normalized()
			if _t <= 0.0:
				state = "graze"
				_t = randf_range(2.0, 5.0)
		"walk":
			spd = s.walk
			if _t <= 0.0:
				state = "graze"
				_t = randf_range(3.0, 8.0)
		_:
			if _t <= 0.0:
				state = "walk"
				_t = randf_range(2.0, 5.0)
				var a := randf() * TAU
				_dir = Vector3(cos(a), 0, sin(a))
	velocity.x = move_toward(velocity.x, _dir.x * spd, 20.0 * delta)
	velocity.z = move_toward(velocity.z, _dir.z * spd, 20.0 * delta)
	if spd > 0.1 and _dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-_dir.x, -_dir.z), clampf(delta * 8.0, 0.0, 1.0))
	var before := global_position
	move_and_slide()
	# chocó con un árbol: gira y sigue
	if spd > 0.5 and before.distance_to(global_position) < spd * delta * 0.3:
		_dir = _dir.rotated(Vector3.UP, PI / 2 * (1.0 if randf() < 0.5 else -1.0))
	# que no se salga del mapa
	var lim: float = WorldLayout.HALF - 6.0
	if absf(global_position.x) > lim or absf(global_position.z) > lim:
		_dir = -Vector3(global_position.x, 0, global_position.z).normalized()


## Te ve o te oye: sale corriendo.
func _sense() -> void:
	var s := spec()
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var d: float = p.global_position.distance_to(global_position)
		var sight: float = s.sight * (0.45 if p.crouching else 1.0)
		if d < sight or d < p.noise * s.hear:
			if state != "flee":
				Sfx.play_at("step", global_position, 2.0, 0.6, 30.0)
			state = "flee"
			_flee_from = p.global_position
			_t = randf_range(4.0, 6.0)
			return


func slow(_seconds: float) -> void:
	pass


@rpc("any_peer", "call_local", "reliable")
func damage(amount: float, knock: Vector3, _kind := "puños") -> void:
	if not multiplayer.is_server() or dead:
		return
	hp -= amount
	velocity += knock * 2.0
	var sender := multiplayer.get_remote_sender_id()
	var attacker := get_tree().current_scene.get_node_or_null("Players/%d" % (sender if sender != 0 else 1))
	_fx_hit.rpc(global_position, hp <= 0.0)
	if hp > 0.0:
		state = "flee"
		_flee_from = attacker.global_position if attacker else global_position - knock
		_t = 6.0
		return
	dead = true
	var s := spec()
	var meat := randi_range(s.meat.x, s.meat.y)
	_world.request_drop(Vector3(global_position.x, 0, global_position.z), {"carne_cruda": meat}, "%s abatido" % s.name, false)
	if attacker:
		attacker.add_kill.rpc_id(attacker.name.to_int(), true)


@rpc("authority", "call_local", "reliable")
func _fx_hit(pos: Vector3, killed: bool) -> void:
	if _world:
		_world.spawn_blood(pos, 0.8 if killed else 0.4)
	Sfx.play_at("hit", pos, 0.0, 1.3)


func _on_died() -> void:
	collision_layer = 0
	velocity = Vector3.ZERO


# ------------------------------------------------------------------ aspecto
func _build() -> void:
	var w := _world
	_body = Node3D.new()
	add_child(_body)
	var fur: Color = FUR.get(kind, FUR.conejo)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	if kind == "ciervo":
		box.size = Vector3(0.5, 1.1, 1.3)
		shape.position.y = 0.85
		w._box(Vector3(0, 1.05, 0), Vector3(0.42, 0.5, 1.15), fur, false, _body, 0.3, 3.0)
		var neck: Node3D = w._box(Vector3(0, 1.45, -0.55), Vector3(0.18, 0.55, 0.2), fur, false, _body, 0.3, 3.0)
		neck.rotation.x = -0.45
		w._box(Vector3(0, 1.72, -0.78), Vector3(0.18, 0.2, 0.36), fur.darkened(0.08), false, _body, 0.3, 3.0)
		w._box(Vector3(0, 1.7, -0.98), Vector3(0.1, 0.1, 0.06), Color(0.1, 0.09, 0.08), false, _body)
		w._box(Vector3(0, 1.15, 0.6), Vector3(0.12, 0.16, 0.08), Color(0.9, 0.88, 0.82), false, _body)
		# cuernas en algunos
		if absi(hash(String(name))) % 2 == 0:
			for s in [-1.0, 1.0]:
				var a: Node3D = w._box(Vector3(0.1 * s, 1.98, -0.72), Vector3(0.04, 0.38, 0.04), Color(0.75, 0.68, 0.55), false, _body)
				a.rotation.z = -0.4 * s
				var b: Node3D = w._box(Vector3(0.2 * s, 2.08, -0.8), Vector3(0.03, 0.2, 0.03), Color(0.75, 0.68, 0.55), false, _body)
				b.rotation.x = -0.6
		for p in [Vector3(0.14, 0.82, -0.45), Vector3(-0.14, 0.82, -0.45), Vector3(0.14, 0.82, 0.45), Vector3(-0.14, 0.82, 0.45)]:
			var leg := Node3D.new()
			leg.position = p
			_body.add_child(leg)
			w._box(Vector3(0, -0.4, 0), Vector3(0.08, 0.82, 0.09), fur.darkened(0.12), false, leg, 0.3, 3.0)
			_legs.append(leg)
	else:
		box.size = Vector3(0.3, 0.35, 0.45)
		shape.position.y = 0.18
		var body: MeshInstance3D = w._sphere_mesh(Vector3(0, 0.2, 0.02), 0.16, fur, _body)
		body.scale = Vector3(0.85, 0.85, 1.25)
		w._sphere_mesh(Vector3(0, 0.3, -0.17), 0.09, fur, _body)
		for s in [-1.0, 1.0]:
			var ear: Node3D = w._box(Vector3(0.035 * s, 0.44, -0.15), Vector3(0.035, 0.16, 0.02), fur.darkened(0.1), false, _body)
			ear.rotation.z = -0.15 * s
		w._sphere_mesh(Vector3(0, 0.24, 0.21), 0.045, Color(0.92, 0.9, 0.85), _body)
		for p in [Vector3(0.07, 0.1, -0.1), Vector3(-0.07, 0.1, -0.1), Vector3(0.08, 0.1, 0.1), Vector3(-0.08, 0.1, 0.1)]:
			var leg := Node3D.new()
			leg.position = p
			_body.add_child(leg)
			w._box(Vector3(0, -0.05, 0), Vector3(0.04, 0.1, 0.06), fur.darkened(0.12), false, leg)
			_legs.append(leg)
	shape.shape = box
	add_child(shape)
