extends CharacterBody3D
## Zombi. Su cerebro solo corre en el anfitrión; los demás equipos reciben
## posición, giro y si está muerto por el MultiplayerSynchronizer.
##
## Oyen el ruido que hace cada jugador (correr, golpear, disparar) y ven a
## quien tienen delante. Agachado eres más difícil de ver y no haces ruido.

const GRAVITY := 16.0
## distancia a la que ven: de día, de noche y de noche si llevas linterna.
## Agachado te ven a menos de la mitad.
const SIGHT := 15.0
const SIGHT_NIGHT := 9.0
const SIGHT_TORCH := 17.0
const CROUCH_SIGHT := 0.45
## de noche se mueven más rápido
const NIGHT_SPEED := 1.3
const ATTACK_RANGE := 1.35
const LAYER_WORLD := 1

@export var dead := false:
	set(value):
		dead = value
		if is_node_ready() and dead:
			_on_died()

## tipo de zombi: normal, corredor, bruto, griton o policia (lo elige el anfitrión)
@export var variant := "normal":
	set(value):
		variant = value
		if is_inside_tree():
			_apply_look()

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
var _stagger_t := 0.0
var _slow_t := 0.0
## de una horda: va hacia la base de los jugadores aunque no les oiga
var horde := false
var horde_target := Vector3.ZERO
var _groan_t := randf_range(2.0, 10.0)
var _world: Node

@onready var figure: HumanFigure = $Figure
@onready var agent: NavigationAgent3D = $Agent

## vida, velocidad, tamaño, daño que hace, fuerza contra lo construido y daño que encaja
const VARIANTS := {
	"normal": {"hp": Vector2(4.5, 6.2), "speed": Vector2(1.05, 1.85), "size": 1.0, "dmg": 1.0, "bash": 1.0, "takes": 1.0},
	"corredor": {"hp": Vector2(2.6, 3.4), "speed": Vector2(2.3, 2.7), "size": 0.96, "dmg": 0.8, "bash": 0.6, "takes": 1.0},
	"bruto": {"hp": Vector2(15.0, 18.0), "speed": Vector2(0.85, 1.05), "size": 1.3, "dmg": 1.7, "bash": 3.0, "takes": 1.0},
	"griton": {"hp": Vector2(3.5, 4.5), "speed": Vector2(1.2, 1.6), "size": 0.98, "dmg": 0.8, "bash": 0.8, "takes": 1.0},
	"policia": {"hp": Vector2(6.0, 7.5), "speed": Vector2(1.0, 1.5), "size": 1.0, "dmg": 1.1, "bash": 1.0, "takes": 0.6},
}
var _screamed := 0.0

const SKINS: Array[Color] = [Color(0.56, 0.6, 0.5), Color(0.5, 0.52, 0.44), Color(0.62, 0.58, 0.5), Color(0.45, 0.48, 0.42)]
const CLOTH: Array[Color] = [Color(0.36, 0.3, 0.26), Color(0.3, 0.34, 0.38), Color(0.42, 0.38, 0.3), Color(0.5, 0.46, 0.42), Color(0.28, 0.3, 0.26)]
const PANTS: Array[Color] = [Color(0.22, 0.24, 0.28), Color(0.3, 0.26, 0.2), Color(0.18, 0.18, 0.2)]


func _enter_tree() -> void:
	_apply_look()


## El aspecto sale del nombre del nodo y del tipo, así es igual en todos los equipos.
func _apply_look() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash(String(name))
	var fig := $Figure as HumanFigure
	fig.zombie = true
	fig.skin = SKINS[r.randi() % SKINS.size()]
	fig.jacket = CLOTH[r.randi() % CLOTH.size()]
	fig.shirt = CLOTH[r.randi() % CLOTH.size()].lightened(0.15)
	fig.pants = PANTS[r.randi() % PANTS.size()]
	fig.hair = Color(0.15, 0.13, 0.11).lerp(Color(0.4, 0.38, 0.34), r.randf())
	fig.gear = {}
	var size: float = VARIANTS.get(variant, VARIANTS.normal).size
	fig.scale = Vector3.ONE * size
	match variant:
		"corredor":
			# flaco y pálido, en ropa de deporte
			fig.scale = Vector3(0.86, 1.0, 0.86) * size
			fig.skin = fig.skin.lightened(0.12)
			fig.jacket = Color(0.55, 0.52, 0.48)
		"bruto":
			fig.scale = Vector3(1.22, 1.08, 1.22) * size
			fig.jacket = Color(0.3, 0.26, 0.22)
			fig.skin = fig.skin.darkened(0.08)
		"griton":
			fig.skin = Color(0.72, 0.74, 0.66)
			fig.hair = Color(0.62, 0.6, 0.55)
			fig.jacket = Color(0.62, 0.62, 0.6)
		"policia":
			fig.jacket = Color(0.16, 0.2, 0.3)
			fig.pants = Color(0.14, 0.16, 0.22)
			fig.gear = {"torso": ["chaleco", Color(0.14, 0.15, 0.17)], "cabeza": ["gorra", Color(0.14, 0.17, 0.27)]}
	var shape := $Collision.shape as CapsuleShape3D
	if variant == "bruto" and shape.radius < 0.4:
		shape = shape.duplicate()
		shape.radius = 0.46
		shape.height = 2.0
		$Collision.shape = shape
		$Collision.position.y = 1.0
	if fig.hips != null:
		fig.rebuild()


func _ready() -> void:
	_world = get_tree().get_first_node_in_group("world")
	_last_pos = position
	figure.footstep.connect(func(_soft): Sfx.play_at("step_soft", global_position, -6.0, 0.8, 18.0))
	if multiplayer.is_server():
		var v: Dictionary = VARIANTS.get(variant, VARIANTS.normal)
		hp = randf_range(v.hp.x, v.hp.y)
		speed = randf_range(v.speed.x, v.speed.y)
		target_pos = position
		_think = randf() * 0.3
		if horde:
			state = "horde"
			target_pos = horde_target
			speed = maxf(speed, 1.5)
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
	# gruñidos: cada equipo los genera por su cuenta, no hace falta enviarlos
	_groan_t -= delta
	if _groan_t <= 0.0:
		_groan_t = randf_range(3.0, 6.0) if _ground_speed > 2.0 else randf_range(6.0, 14.0)
		Sfx.play_at("groan%d" % (randi() % 3), global_position + Vector3.UP * 1.6, -2.0, 1.0, 28.0)
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
	var night_k := NIGHT_SPEED if _world and _world.night else 1.0
	var spd := speed * 0.45 * night_k
	_stagger_t -= delta
	_slow_t -= delta
	if state == "horde":
		spd = speed * 1.15 * night_k
		dest = target_pos
		if global_position.distance_to(target_pos) < 3.0:
			# llegó a la base: se queda rondando por aquí
			state = "wander"
			horde = false
	elif state == "chase":
		spd = speed * (1.6 if memory > 0 else 1.1) * night_k
		if _stagger_t > 0.0:
			spd = 0.0
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
	if _slow_t > 0.0:
		spd *= 0.4
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

	# algo construido le corta el paso: lo golpea hasta romperlo
	if (state == "chase" or state == "horde") and spd > 0.3 and before.distance_to(global_position) < spd * delta * 0.5:
		var sid := _structure_ahead()
		if sid >= 0:
			_stuck_t = 0.0
			if _attack_cd <= 0.0:
				_attack_cd = randf_range(1.0, 1.4)
				var structures: Node = _world.structures
				var stype: String = structures.by_id[sid].type
				structures.damage(sid, randf_range(10.0, 16.0) * VARIANTS[variant].bash)
				if variant == "bruto":
					_world.spawn_word(global_position + Vector3.UP, "derribo", Color(0.98, 0.95, 0.85), 1.0)
				if stype == "empalizada":
					damage(0.6, global_transform.basis.z * 0.5, "fuego")
			return
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


## ¿Hay una barricada, muro o puerta justo delante?
func _structure_ahead() -> int:
	var fwd := -global_transform.basis.z
	var from := global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 1.3, LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not hit.collider.has_meta("sid"):
		return -1
	return hit.collider.get_meta("sid")


## Los pinchos le frenan un rato.
func slow(seconds: float) -> void:
	_slow_t = maxf(_slow_t, seconds)


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
		# a los caídos los persiguen menos (prefieren a quien sigue en pie)
		if p.downed:
			d *= 1.8
		var heard: bool = d < p.noise
		var sight := SIGHT
		if _world and _world.night:
			sight = SIGHT_TORCH if p.flashlight else SIGHT_NIGHT
		if p.crouching:
			sight *= CROUCH_SIGHT
		var seen := d < sight and (d < 2.5 or forward.dot(to.normalized()) > 0.3) and _line_of_sight(p.global_position)
		if (heard or seen) and d < best_d:
			best_d = d
			best = p
	_screamed -= 0.25
	if best:
		# el gritón avisa a todos los de alrededor
		if variant == "griton" and state != "chase" and _screamed <= 0.0:
			_screamed = 20.0
			_scream_fx.rpc(global_position)
			for z in get_tree().get_nodes_in_group("zombies"):
				if z != self and not z.dead and not z.is_in_group("animals") and z.global_position.distance_to(global_position) < 45.0:
					z.target_player = best
					z.target_pos = best.global_position
					z.state = "chase"
					z.memory = 8.0
		target_player = best
		target_pos = best.global_position
		state = "chase"
		memory = 6.0
	else:
		memory -= 0.25
		if state == "chase" and memory <= 0.0 and global_position.distance_to(target_pos) < 1.5:
			state = "horde" if horde else "wander"
			if horde:
				target_pos = horde_target
			target_player = null
		# de noche, la luz de una hoguera atrae a los que andan sin rumbo
		if state == "wander" and _world and _world.night and randf() < 0.15:
			for sid in _world.structures.by_id:
				var st: Dictionary = _world.structures.by_id[sid]
				if st.type == "hoguera" and global_position.distance_to(st.pos) < 28.0:
					target_pos = st.pos + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
					_wander_t = 12.0
					break


func _line_of_sight(to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.6, to + Vector3.UP * 1.4, LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _try_attack() -> void:
	if _attack_cd > 0.0 or target_player == null:
		return
	_attack_cd = randf_range(1.0, 1.4)
	var peer := target_player.name.to_int()
	target_player.take_hit.rpc_id(peer, randf_range(7.0, 12.0) * VARIANTS[variant].dmg, global_position)


## Lo llama el jugador que golpea o dispara.
@rpc("any_peer", "call_local", "reliable")
func damage(amount: float, knock: Vector3, kind := "puños") -> void:
	if not multiplayer.is_server() or dead:
		return
	var v: Dictionary = VARIANTS.get(variant, VARIANTS.normal)
	# el chaleco del policía para golpes; las balas lo atraviesan mejor
	hp -= amount * (lerpf(v.takes, 1.0, 0.5) if kind == "pistola" else v.takes)
	velocity += knock * (0.8 if variant == "bruto" else 3.0)
	_stagger_t = 0.0 if kind == "fuego" else (0.45 if kind != "puños" else 0.25)
	if hp > 0.0:
		_fx_hit.rpc(global_position, false, kind)
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
		_fx_hit.rpc(global_position, true, kind)
		# los policías llevan algo encima
		if variant == "policia" and randf() < 0.5:
			_world.request_drop(Vector3(global_position.x, 0, global_position.z), {"balas": randi_range(2, 6)}, "Cinturón del policía", false)
		if attacker:
			attacker.add_kill.rpc_id(attacker.name.to_int())


## El grito del gritón: lo oyen todos.
@rpc("authority", "call_local", "reliable")
func _scream_fx(pos: Vector3) -> void:
	Sfx.play_at("scream", pos, 6.0, 1.0, 70.0)
	if _world:
		_world.spawn_word(pos + Vector3.UP * 0.4, "grito", Color(0.98, 0.95, 0.85), 1.6)
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(pos) < 25.0:
		get_tree().call_group("main", "impact", 0.35)


## Golpe visto por todos: sangre, sonido y onomatopeya.
@rpc("authority", "call_local", "reliable")
func _fx_hit(pos: Vector3, big: bool, kind: String) -> void:
	if _world == null:
		return
	_world.spawn_blood(pos, 1.5 if big else 0.7)
	if big:
		Sfx.play_at("splat", pos, 2.0)
		_world.spawn_word(pos, "muerte", Color(0.75, 0.08, 0.05), 1.3)
		var cam := get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_to(pos) < 12.0:
			get_tree().call_group("main", "impact", 0.55)
	if kind != "pistola" and kind != "fuego":
		Sfx.play_at("hit" if kind == "puños" else "hit_heavy", pos, 0.0 if kind == "puños" else 3.0)
		if not big:
			_world.spawn_word(pos, kind, Color(0.98, 0.95, 0.85), 0.9 if kind == "puños" else 1.1)


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
