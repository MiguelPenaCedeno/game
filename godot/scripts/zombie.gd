extends CharacterBody3D
## Zombi. Su cerebro solo corre en el anfitrión; los demás equipos reciben
## posición, giro y si está muerto por el MultiplayerSynchronizer.
##
## Oyen el ruido que hace cada jugador (correr, golpear, disparar) y ven a
## quien tienen delante. Agachado eres más difícil de ver y no haces ruido.

const GRAVITY := 16.0
const SIGHT := 15.0
const SIGHT_CROUCH := 6.0
const ATTACK_RANGE := 1.35
const LAYER_WORLD := 1

@export var dead := false:
	set(value):
		dead = value
		if is_node_ready() and dead:
			_on_died()

## posición y giro que se envían por red; los demás equipos se acercan a
## ellos suavemente en vez de saltar de golpe
@export var net_pos := Vector3.ZERO
@export var net_yaw := 0.0

var hp := 5.0
var speed := 1.4
var state := "wander"
var target_player: Node3D
var target_pos := Vector3.ZERO
var memory := 0.0
var _think := 0.0
var _attack_cd := 0.0
var _wander_t := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _ground_speed := 0.0
var _dead_t := 0.0
var _path_target := Vector3.INF
var _anim_skip := false

@onready var figure: HumanFigure = $Figure
@onready var agent: NavigationAgent3D = $Agent

const SKINS: Array[Color] = [Color(0.56, 0.6, 0.5), Color(0.5, 0.52, 0.44), Color(0.62, 0.58, 0.5), Color(0.45, 0.48, 0.42)]
const CLOTH: Array[Color] = [Color(0.36, 0.3, 0.26), Color(0.3, 0.34, 0.38), Color(0.42, 0.38, 0.3), Color(0.5, 0.46, 0.42), Color(0.28, 0.3, 0.26)]
const PANTS: Array[Color] = [Color(0.22, 0.24, 0.28), Color(0.3, 0.26, 0.2), Color(0.18, 0.18, 0.2)]


func _enter_tree() -> void:
	# el aspecto sale del nombre del nodo, así es igual en todos los equipos
	var r := RandomNumberGenerator.new()
	r.seed = hash(String(name))
	var fig := $Figure as HumanFigure
	fig.zombie = true
	fig.skin = SKINS[r.randi() % SKINS.size()]
	fig.jacket = CLOTH[r.randi() % CLOTH.size()]
	fig.shirt = CLOTH[r.randi() % CLOTH.size()].lightened(0.15)
	fig.pants = PANTS[r.randi() % PANTS.size()]
	fig.hair = Color(0.15, 0.13, 0.11).lerp(Color(0.4, 0.38, 0.34), r.randf())


func _ready() -> void:
	_last_pos = position
	if multiplayer.is_server():
		hp = randf_range(4.5, 6.2)
		speed = randf_range(1.05, 1.85) * (1.8 if randf() < 0.1 else 1.0)
		target_pos = position
		_think = randf() * 0.3
	else:
		set_physics_process(false)
		position = net_pos
		rotation.y = net_yaw
	if dead:
		_on_died()


func _process(delta: float) -> void:
	if multiplayer.is_server():
		net_pos = position
		net_yaw = rotation.y
	else:
		_net_smooth(delta)
	var moved := Vector2(position.x - _last_pos.x, position.z - _last_pos.z).length() / maxf(delta, 1e-4)
	_last_pos = position
	if dead:
		_dead_t += delta
		# cae de espaldas
		figure.rotation.x = lerpf(figure.rotation.x, PI / 2, clampf(delta * 6.0, 0.0, 1.0))
		figure.position.y = lerpf(figure.position.y, 0.15, clampf(delta * 6.0, 0.0, 1.0))
		if multiplayer.is_server() and _dead_t > 20.0:
			queue_free()
		return
	_ground_speed = lerpf(_ground_speed, minf(moved, 6.0), clampf(delta * 8.0, 0.0, 1.0))
	# lejos de la cámara: sin sombra y animación a medio ritmo
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_squared_to(global_position) > 28.0 * 28.0
	figure.set_shadows(not far)
	_anim_skip = not _anim_skip if far else false
	if not _anim_skip:
		figure.animate(delta * (2.0 if far else 1.0), _ground_speed, false)


func _physics_process(delta: float) -> void:
	if dead:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	_attack_cd -= delta
	_think -= delta
	if _think <= 0.0:
		_think = 0.25
		_sense()

	var dest := target_pos
	var spd := speed * 0.45
	if state == "chase":
		spd = speed * (1.6 if memory > 0 else 1.1)
		if target_player and is_instance_valid(target_player):
			var d := global_position.distance_to(target_player.global_position)
			if d < ATTACK_RANGE:
				_try_attack()
				spd = 0.0
	elif state == "wander":
		_wander_t -= delta
		if _wander_t <= 0.0 or global_position.distance_to(target_pos) < 1.0:
			_wander_t = randf_range(4.0, 9.0)
			target_pos = global_position + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
			if randf() < 0.4:
				spd = 0.0
		dest = target_pos

	# recalcular la ruta solo cuando el destino se mueve de verdad
	if dest.distance_squared_to(_path_target) > 0.6:
		_path_target = dest
		agent.target_position = dest
	var next := agent.get_next_path_position()
	var to := next - global_position
	to.y = 0
	if to.length() > 0.05 and spd > 0.0:
		var dir := to.normalized()
		velocity.x = move_toward(velocity.x, dir.x * spd, 8.0 * delta)
		velocity.z = move_toward(velocity.z, dir.z * spd, 8.0 * delta)
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(delta * 6.0, 0.0, 1.0))
	else:
		velocity.x = move_toward(velocity.x, 0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 10.0 * delta)
	var before := global_position
	move_and_slide()

	# atascado contra algo: date un paso de lado
	if spd > 0.3 and before.distance_to(global_position) < spd * delta * 0.25:
		_stuck_t += delta
		if _stuck_t > 1.0:
			_stuck_t = 0.0
			target_pos = global_position + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
			if state == "chase":
				memory = 0.0
	else:
		_stuck_t = maxf(0.0, _stuck_t - delta)


## Busca jugadores por el oído y la vista.
func _sense() -> void:
	var best: Node3D = null
	var best_d := INF
	var forward := -global_transform.basis.z
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead:
			continue
		var to: Vector3 = p.global_position - global_position
		var d := to.length()
		var heard: bool = d < p.noise
		var sight := SIGHT_CROUCH if p.crouching else SIGHT
		var seen := d < sight and (d < 2.5 or forward.dot(to.normalized()) > 0.3) and _line_of_sight(p.global_position)
		if (heard or seen) and d < best_d:
			best_d = d
			best = p
	if best:
		target_player = best
		target_pos = best.global_position
		state = "chase"
		memory = 6.0
	else:
		memory -= 0.25
		if state == "chase" and memory <= 0.0 and global_position.distance_to(target_pos) < 1.5:
			state = "wander"
			target_player = null


func _line_of_sight(to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.6, to + Vector3.UP * 1.4, LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _try_attack() -> void:
	if _attack_cd > 0.0 or target_player == null:
		return
	_attack_cd = randf_range(1.0, 1.4)
	var peer := target_player.name.to_int()
	target_player.take_hit.rpc_id(peer, randf_range(7.0, 12.0), global_position)


## Lo llama el jugador que golpea o dispara.
@rpc("any_peer", "call_local", "reliable")
func damage(amount: float, knock: Vector3) -> void:
	if not multiplayer.is_server() or dead:
		return
	hp -= amount
	velocity += knock * 3.0
	_fx_hit.rpc(global_position, false)
	# el golpe le hace fijarse en quien le pegó
	var sender := multiplayer.get_remote_sender_id()
	var attacker := get_tree().current_scene.get_node_or_null("Players/%d" % (sender if sender != 0 else 1))
	if attacker:
		target_player = attacker
		target_pos = attacker.global_position
		state = "chase"
		memory = 6.0
	if hp <= 0.0:
		dead = true
		_fx_hit.rpc(global_position, true)
		if attacker:
			attacker.add_kill.rpc_id(attacker.name.to_int())


@rpc("authority", "call_local", "reliable")
func _fx_hit(pos: Vector3, big: bool) -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world:
		world.spawn_blood(pos, 1.5 if big else 0.7)


func _on_died() -> void:
	collision_layer = 0
	collision_mask = LAYER_WORLD
	velocity = Vector3.ZERO


## En los equipos que no mandan sobre este nodo: acercarse suavemente a lo recibido.
func _net_smooth(delta: float) -> void:
	if position.distance_squared_to(net_pos) > 16.0:
		position = net_pos  # teletransporte o reaparición
	else:
		position = position.lerp(net_pos, 1.0 - exp(-14.0 * delta))
	rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - exp(-14.0 * delta))
