extends CharacterBody3D
## Superviviente en tercera persona.
## Cada jugador controla solo su propio personaje (es su "autoridad")
## y el MultiplayerSynchronizer envía a los demás lo que necesitan ver:
## posición, giro, nombre, si va agachado o muerto, el arma, el ruido que hace
## (los zombis del anfitrión lo usan para oírle) y cuándo golpea.
## Las estadísticas y la mochila solo existen en el equipo de su dueño.

signal message(text: String, bad: bool)
signal died(cause: String)

const WALK_SPEED := 3.4
const RUN_SPEED := 6.2
const CROUCH_SPEED := 1.7
const ACCEL := 14.0
const JUMP_VELOCITY := 5.2
const GRAVITY := 16.0
const MOUSE_SENSITIVITY := 0.0025
const PITCH_MIN := -1.2
const PITCH_MAX := 0.6
const SPAWN_POINT := Vector3(0, 0.2, 4)
const LAYER_WORLD := 1
const LAYER_ZOMBIES := 4

const SKINS: Array[Color] = [Color(0.86, 0.66, 0.52), Color(0.68, 0.48, 0.34), Color(0.45, 0.31, 0.22), Color(0.92, 0.75, 0.62)]
const HAIRS: Array[Color] = [Color(0.18, 0.12, 0.08), Color(0.08, 0.07, 0.07), Color(0.45, 0.3, 0.16), Color(0.6, 0.5, 0.35)]

@export var display_name := "":
	set(value):
		display_name = value
		if is_node_ready():
			name_label.text = value
@export var crouching := false:
	set(value):
		crouching = value
		if is_node_ready():
			_apply_crouch()
## posición y giro que se envían por red; los demás equipos se acercan a
## ellos suavemente en vez de saltar de golpe
@export var net_pos := Vector3.ZERO
@export var net_yaw := 0.0
@export var dead := false
@export var weapon := "puños":
	set(value):
		weapon = value
		if is_node_ready():
			figure.set_weapon(value)
## radio en metros en el que los zombis te oyen
@export var noise := 0.0
## sube cada vez que golpeas; los demás equipos lo usan para animarte
@export var attack_count := 0:
	set(value):
		if is_node_ready() and value != attack_count and not is_multiplayer_authority():
			figure.play_attack(Items.WEAPONS[weapon].cd)
		attack_count = value

# --- estadísticas (solo en el equipo del dueño)
var hp := 100.0
var stamina := 100.0
var hunger := 82.0
var thirst := 78.0
var bleeding := false
var infected := false
## mochila: comida, agua, vendas, balas
var inv := {"comida": 0, "agua": 0, "vendas": 0, "balas": 0}
## armas que llevas y sus golpes restantes (-1 = no se gasta)
var owned := {"puños": -1}
var kills := 0
var searched := 0
var alive_time := 0.0
var weight := 0.0

## mueble más cercano al que miras (-1 si ninguno)
var interact_idx := -1
## registro en curso: {idx, t, dur, pos}
var search := {}

var pitch := -0.25
var _last_pos := Vector3.ZERO
var _ground_speed := 0.0
var _attack_cd := 0.0
var _pending_hit := -1.0
var _noise_spike := 0.0
var _hurt_flash := 0.0
var _world: Node

@onready var figure: HumanFigure = $Figure
@onready var name_label: Label3D = $NameLabel
@onready var pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm
@onready var camera: Camera3D = $CameraPivot/SpringArm/Camera


func _enter_tree() -> void:
	# El nodo se llama como el id de red de su dueño.
	set_multiplayer_authority(name.to_int())
	add_to_group("players")
	# aspecto fijo por jugador; la chaqueta lleva su color
	var id := name.to_int()
	var fig := $Figure as HumanFigure
	fig.jacket = Network.color_for(id).darkened(0.25)
	fig.skin = SKINS[absi(hash(id)) % SKINS.size()]
	fig.hair = HAIRS[absi(hash(id * 7)) % HAIRS.size()]


func _ready() -> void:
	name_label.text = display_name
	_apply_crouch()
	figure.set_weapon(weapon)
	_world = get_tree().get_first_node_in_group("world")

	if is_multiplayer_authority():
		display_name = Network.player_name
		# cada uno coloca su propio personaje (el orden de llegada evita solaparse)
		position = SPAWN_POINT + Vector3((get_index() % 4) * 1.5 - 2.25, 0, 0)
		name_label.visible = false
		camera.current = true
		spring_arm.add_excluded_object(get_rid())
		pivot.rotation.x = pitch
		_world.loot_received.connect(_on_loot_received)
		_recalc_weight()
		get_tree().call_group("hud", "bind_player", self)
	else:
		set_physics_process(false)
		set_process_unhandled_input(false)
		position = net_pos
	_last_pos = position


func _process(delta: float) -> void:
	if is_multiplayer_authority():
		net_pos = position
		net_yaw = rotation.y
	else:
		_net_smooth(delta)
	# la velocidad se mide por el desplazamiento, así también anima a los remotos
	var moved := Vector2(position.x - _last_pos.x, position.z - _last_pos.z).length() / maxf(delta, 1e-4)
	_last_pos = position
	if dead:
		figure.rotation.x = lerpf(figure.rotation.x, PI / 2, clampf(delta * 6.0, 0.0, 1.0))
		figure.position.y = lerpf(figure.position.y, 0.15, clampf(delta * 6.0, 0.0, 1.0))
		return
	figure.rotation.x = 0.0
	figure.position.y = 0.0
	_ground_speed = lerpf(_ground_speed, minf(moved, 9.0), clampf(delta * 10.0, 0.0, 1.0))
	var airborne := is_multiplayer_authority() and not is_on_floor() and absf(velocity.y) > 1.0
	figure.animate(delta, _ground_speed, crouching, airborne)
	if is_multiplayer_authority():
		_world.update_roofs(global_position)


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or dead:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		pitch = clampf(pitch - event.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
		pivot.rotation.x = pitch
	elif event.is_action_pressed("crouch"):
		crouching = not crouching
	elif event.is_action_pressed("attack"):
		_attack()
	elif event.is_action_pressed("interact"):
		_start_search()
	elif event.is_action_pressed("next_weapon"):
		_cycle_weapon()
	elif event.is_action_pressed("eat"):
		use_item("comida")
	elif event.is_action_pressed("drink"):
		use_item("agua")
	elif event.is_action_pressed("bandage"):
		use_item("vendas")


func _physics_process(delta: float) -> void:
	if dead:
		velocity.x = 0
		velocity.z = 0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		noise = 0.0
		return
	alive_time += delta
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if captured else Vector2.ZERO
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var moving := input.length() > 0.1

	if captured and Input.is_action_just_pressed("jump") and is_on_floor() and not crouching and stamina > 8:
		velocity.y = JUMP_VELOCITY
		stamina -= 6

	var can_run := stamina > 2.0 and weight <= Items.CARRY_HEAVY
	var running := captured and Input.is_action_pressed("sprint") and input.y < 0 and not crouching and can_run
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif running:
		speed = RUN_SPEED
	speed *= Items.speed_factor(weight)
	if stamina < 12 and not running:
		speed *= 0.8
	if hp < 25:
		speed *= 0.85
	if hunger <= 0 or thirst <= 0:
		speed *= 0.85

	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	move_and_slide()

	if position.y < -20:
		position = SPAWN_POINT + Vector3.UP * 2
		velocity = Vector3.ZERO

	_update_stats(delta, running and moving)

	# ruido: lo que oyen los zombis
	_noise_spike = maxf(0.0, _noise_spike - delta * 30.0)
	var step_noise := 0.0
	if moving:
		step_noise = 14.0 if running else (1.4 if crouching else 4.5)
	# redondeado para que solo se envíe por red cuando cambia de verdad
	var new_noise := snappedf(maxf(step_noise, _noise_spike), 0.5)
	if new_noise != noise:
		noise = new_noise

	# combate
	_attack_cd -= delta
	if _pending_hit >= 0.0:
		_pending_hit -= delta
		if _pending_hit < 0.0:
			_resolve_melee()

	# registrar
	interact_idx = _world.container_index_near(global_position, -global_transform.basis.z)
	if not search.is_empty():
		search.t += delta
		if global_position.distance_to(search.pos) > 0.7:
			search = {}
			message.emit("Dejas de registrar.", false)
		elif search.t >= search.dur:
			_world.request_search.rpc_id(1, search.idx)
			searched += 1
			search = {}

	_hurt_flash = maxf(0.0, _hurt_flash - delta)


func _update_stats(delta: float, running: bool) -> void:
	var regen := 9.0 if hunger > 25 and thirst > 25 else 4.0
	if weight > Items.CARRY_HEAVY:
		regen *= 0.5
	stamina = clampf(stamina + (-15.0 if running else regen) * delta, 0.0, 100.0)
	# la carga también da hambre y sed
	var load_k := 1.0 + maxf(0.0, weight - Items.CARRY_LIGHT) / Items.CARRY_MAX
	hunger = maxf(0.0, hunger - 0.17 * delta * load_k)
	thirst = maxf(0.0, thirst - 0.24 * delta * load_k)
	if hunger <= 0:
		hp -= 0.6 * delta
	if thirst <= 0:
		hp -= 0.8 * delta
	if bleeding:
		hp -= 0.5 * delta
		if randf() < delta * 1.2:
			_world.spawn_blood(global_position, 0.35)
	if infected:
		hp -= 0.13 * delta
	if not bleeding and not infected and hunger > 45 and thirst > 45:
		hp = minf(100.0, hp + 0.25 * delta)
	if hp <= 0.0:
		var cause := "La sed terminó contigo."
		if infected:
			cause = "La fiebre de la mordida terminó contigo."
		elif bleeding:
			cause = "Te desangraste sin encontrar vendas."
		elif hunger <= 0:
			cause = "El hambre pudo más que los zombis."
		_die(cause)


# ------------------------------------------------------------------ mochila y peso
func _recalc_weight() -> void:
	var w := 0.0
	for k in inv:
		w += inv[k] * Items.kg(k)
	for k in owned:
		if k != "puños":
			w += Items.kg(k)
	weight = w


func use_item(k: String) -> void:
	if dead:
		return
	if k == "comida":
		if inv.comida <= 0:
			message.emit("No tienes comida.", true)
			return
		if hunger > 95:
			message.emit("No tienes hambre.", false)
			return
		inv.comida -= 1
		hunger = minf(100.0, hunger + 38.0)
		message.emit("Comes una lata fría de alubias.", false)
	elif k == "agua":
		if inv.agua <= 0:
			message.emit("No tienes agua.", true)
			return
		if thirst > 95:
			message.emit("No tienes sed.", false)
			return
		inv.agua -= 1
		thirst = minf(100.0, thirst + 42.0)
		message.emit("Bebes media botella de un trago.", false)
	elif k == "vendas":
		if inv.vendas <= 0:
			message.emit("No tienes vendas.", true)
			return
		inv.vendas -= 1
		var was := bleeding
		bleeding = false
		hp = minf(100.0, hp + 18.0)
		message.emit("Te vendas la herida. Deja de sangrar." if was else "Te cambias las vendas.", false)
	_recalc_weight()


## Suelta una unidad: si estás junto a un mueble la dejas dentro, si no, en el suelo.
func drop_item(k: String) -> void:
	if dead:
		return
	var label: String = Items.ITEMS[k].name
	if owned.has(k):
		owned.erase(k)
		if weapon == k:
			weapon = "puños"
	elif inv.get(k, 0) > 0:
		inv[k] -= 1
	else:
		return
	_recalc_weight()
	if interact_idx >= 0:
		_world.return_loot.rpc_id(1, interact_idx, {k: 1})
		message.emit("Dejas %s en %s." % [label.to_lower(), _world.containers[interact_idx].name.to_lower()], false)
	else:
		message.emit("Tiras %s al suelo." % label.to_lower(), false)


func _start_search() -> void:
	if not search.is_empty() or interact_idx < 0:
		return
	var c: Dictionary = _world.containers[interact_idx]
	if c.empty:
		message.emit("%s: ya está vacío." % c.name, false)
		return
	search = {"idx": interact_idx, "t": 0.0, "dur": Items.CONTAINERS[c.type].time, "pos": global_position}
	_noise_spike = 3.0


func _on_loot_received(idx: int, loot: Dictionary) -> void:
	var cname: String = _world.containers[idx].name
	var got := {}
	var leftover := {}
	# la pistola trae su cargador
	if loot.has("pistola"):
		loot["balas"] = loot.get("balas", 0) + 6
	for k in loot:
		var n: int = loot[k]
		if Items.WEAPONS.has(k):
			if owned.has(k):
				owned[k] = Items.WEAPONS[k].dur  # cambias la vieja por esta
				got[k] = 1
			elif weight + Items.kg(k) <= Items.CARRY_MAX:
				owned[k] = Items.WEAPONS[k].dur
				got[k] = 1
				if Items.WEAPON_ORDER.find(k) > Items.WEAPON_ORDER.find(weapon) and k != "pistola":
					weapon = k
			else:
				leftover[k] = 1
		else:
			var fit := mini(n, int(floor((Items.CARRY_MAX - weight) / Items.kg(k) + 0.001)))
			fit = maxi(fit, 0)
			if fit > 0:
				inv[k] += fit
				got[k] = fit
			if n - fit > 0:
				leftover[k] = n - fit
		_recalc_weight()
	if got.is_empty() and leftover.is_empty():
		message.emit("%s: nada útil." % cname, false)
	elif not got.is_empty():
		message.emit("%s: %s." % [cname, Items.describe(got)], false)
	if not leftover.is_empty():
		_world.return_loot.rpc_id(1, idx, leftover)
		message.emit("No te cabe en la mochila: %s. Lo dejas ahí." % Items.describe(leftover), true)


# ------------------------------------------------------------------ armas
func _cycle_weapon() -> void:
	var have: Array[String] = []
	for k in Items.WEAPON_ORDER:
		if owned.has(k):
			have.append(k)
	weapon = have[(have.find(weapon) + 1) % have.size()]


func _attack() -> void:
	if _attack_cd > 0.0 or not search.is_empty():
		return
	var w: ItemData = Items.WEAPONS[weapon]
	if w.gun:
		if inv.balas <= 0:
			_attack_cd = 0.3
			message.emit("No te quedan balas.", true)
			return
		inv.balas -= 1
		_recalc_weight()
		_attack_cd = w.cd
		attack_count += 1
		figure.play_attack(w.cd)
		_shoot()
		return
	if stamina < w.stam * 0.5:
		_attack_cd = 0.3
		message.emit("Estás agotado para golpear.", true)
		return
	stamina -= w.stam
	_attack_cd = w.cd
	_pending_hit = 0.17
	attack_count += 1
	figure.play_attack(w.cd)


func _resolve_melee() -> void:
	var w: ItemData = Items.WEAPONS[weapon]
	var fwd := -global_transform.basis.z
	var hits := []
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.dead:
			continue
		var to: Vector3 = z.global_position - global_position
		to.y = 0
		var d := to.length()
		if d > w.reach + 0.25:
			continue
		if d > 0.8 and fwd.angle_to(to) > 1.05:
			continue
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, z.global_position + Vector3.UP, LAYER_WORLD)
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		hits.append([d, z, to.normalized()])
	hits.sort_custom(func(a, b): return a[0] < b[0])
	var n := mini(hits.size(), w.hits)
	for i in n:
		hits[i][1].damage.rpc_id(1, w.dmg * randf_range(0.85, 1.2), hits[i][2])
	if n > 0:
		_noise_spike = w.noise
		if owned[weapon] > 0:
			owned[weapon] -= 1
			if owned[weapon] <= 0:
				message.emit("Tu %s se rompió." % w.name.to_lower(), true)
				owned.erase(weapon)
				weapon = "puños"
				_recalc_weight()


func _shoot() -> void:
	_noise_spike = Items.WEAPONS["pistola"].noise
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 60.0
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD | LAYER_ZOMBIES, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit.collider
	if col.is_in_group("zombies") and not col.dead:
		var head: bool = hit.position.y - col.global_position.y > 1.5
		var dmg: float = Items.WEAPONS["pistola"].dmg * (2.2 if head else 1.0) * randf_range(0.9, 1.1)
		var dir: Vector3 = (col.global_position - global_position).normalized() * 0.6
		col.damage.rpc_id(1, dmg, dir)


# ------------------------------------------------------------------ daño y muerte
## Lo llama el zombi (desde el anfitrión) en el equipo del dueño.
@rpc("any_peer", "call_local", "reliable")
func take_hit(dmg: float, from: Vector3) -> void:
	if dead or multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	hp -= dmg
	_hurt_flash = 0.35
	var away := global_position - from
	away.y = 0
	velocity += away.normalized() * 3.0
	_world.spawn_blood(global_position, 0.5)
	var r := randf()
	if r < 0.07 and not infected:
		infected = true
		message.emit("Te han mordido. La herida arde y no deja de latir.", true)
	elif r < 0.36 and not bleeding:
		bleeding = true
		message.emit("Un arañazo profundo. Estás sangrando: véndate (3).", true)
	if hp <= 0.0:
		_die("Te devoraron con la mordida todavía fresca." if infected else "Te rodearon y te arrastraron al suelo.")


@rpc("any_peer", "call_local", "reliable")
func add_kill() -> void:
	kills += 1


func _die(cause: String) -> void:
	if dead:
		return
	hp = 0.0
	dead = true
	search = {}
	crouching = false
	died.emit(cause)


func respawn() -> void:
	hp = 100.0
	stamina = 100.0
	hunger = 82.0
	thirst = 78.0
	bleeding = false
	infected = false
	inv = {"comida": 0, "agua": 0, "vendas": 0, "balas": 0}
	owned = {"puños": -1}
	weapon = "puños"
	kills = 0
	searched = 0
	alive_time = 0.0
	_recalc_weight()
	position = SPAWN_POINT + Vector3(randf_range(-2, 2), 0.5, 0)
	velocity = Vector3.ZERO
	dead = false


func hurt_flash() -> float:
	return _hurt_flash


func _apply_crouch() -> void:
	pivot.position.y = 1.15 if crouching else 1.55
	name_label.position.y = 1.75 if crouching else 2.15


## En los equipos que no mandan sobre este nodo: acercarse suavemente a lo recibido.
func _net_smooth(delta: float) -> void:
	if position.distance_squared_to(net_pos) > 16.0:
		position = net_pos  # teletransporte o reaparición
	else:
		position = position.lerp(net_pos, 1.0 - exp(-14.0 * delta))
	rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - exp(-14.0 * delta))
