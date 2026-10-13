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
## en cooperativo, a 0 de salud caes al suelo y tu compañero puede levantarte
@export var downed := false
@export var flashlight := false:
	set(value):
		flashlight = value
		if is_node_ready():
			_torch.visible = value
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
			_attack_fx()
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
## segundos que aguantas en el suelo antes de morir
var bleed_out := 0.0
var _down_cause := ""
## compañero caído al que puedes levantar (null si ninguno)
var revive_target: Node3D
const BLEED_OUT_TIME := 40.0
const REVIVE_TIME := 3.5
var searched := 0
var alive_time := 0.0
var weight := 0.0

## mueble más cercano al que miras (-1 si ninguno)
var interact_idx := -1
## registro en curso: {idx, t, dur, pos}
var search := {}

var pitch := -0.25
var shake := 0.0
var _shake_t := 0.0
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
var _torch: SpotLight3D


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
	_build_torch()
	figure.footstep.connect(func(soft: bool):
		Sfx.play_at("step_soft" if soft else "step", global_position, -4.0 if soft else 0.0, 1.0, 22.0))
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
		_world.item_granted.connect(_on_item_granted)
		_recalc_weight()
		get_tree().call_group("hud", "bind_player", self)
		try_load.call_deferred()
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
	if downed:
		# boca abajo, arrastrándose
		figure.rotation.x = lerpf(figure.rotation.x, -PI / 2 * 0.9, clampf(delta * 6.0, 0.0, 1.0))
		figure.position.y = lerpf(figure.position.y, 0.25, clampf(delta * 6.0, 0.0, 1.0))
	else:
		figure.rotation.x = 0.0
		figure.position.y = 0.0
	_ground_speed = lerpf(_ground_speed, minf(moved, 9.0), clampf(delta * 10.0, 0.0, 1.0))
	var airborne := is_multiplayer_authority() and not is_on_floor() and absf(velocity.y) > 1.0
	figure.animate(delta, _ground_speed, crouching, airborne)
	if is_multiplayer_authority():
		_world.update_roofs(global_position)
		camera.fov = Settings.fov
		# temblor de cámara
		shake = maxf(0.0, shake - delta * 1.8)
		_shake_t += delta * 40.0
		camera.h_offset = sin(_shake_t * 1.3) * shake * 0.35
		camera.v_offset = cos(_shake_t * 1.7) * shake * 0.25


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or dead:
		return
	if not placing.is_empty() and not event is InputEventMouseMotion:
		if event.is_action_pressed("attack"):
			_confirm_placing()
		elif event.is_action_pressed("cancel") or event.is_action_pressed("inventory"):
			_cancel_placing()
		elif event.is_action_pressed("rotate"):
			placing.rot += PI / 4
		return
	if event is InputEventMouseMotion:
		var sens: float = Settings.mouse_sensitivity
		rotate_y(-event.relative.x * sens)
		pitch = clampf(pitch - event.relative.y * sens * (-1.0 if Settings.invert_y else 1.0), PITCH_MIN, PITCH_MAX)
		pivot.rotation.x = pitch
	elif downed:
		return  # en el suelo solo puedes arrastrarte
	elif event.is_action_pressed("crouch"):
		crouching = not crouching
	elif event.is_action_pressed("attack"):
		_attack()
	elif event.is_action_pressed("interact"):
		_start_search()
	elif event.is_action_pressed("throw"):
		_throw_molotov()
	elif event.is_action_pressed("flashlight"):
		flashlight = not flashlight
		Sfx.play("click")
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
	if downed:
		_physics_downed(delta)
		return
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
	revive_target = _find_downed_teammate()
	if not search.is_empty():
		search.t += delta
		if global_position.distance_to(search.pos) > 0.7:
			search = {}
			message.emit("Dejas de registrar.", false)
		elif search.has("craft"):
			if search.t >= search.dur:
				_finish_craft(search.craft)
				search = {}
		elif search.has("dismantle"):
			_noise_spike = maxf(_noise_spike, 10.0)
			if search.t >= search.dur:
				_finish_dismantle(search.dismantle)
				search = {}
		elif search.has("revive"):
			var mate: Node3D = search.revive
			if not is_instance_valid(mate) or not mate.downed:
				search = {}
			elif search.t >= search.dur:
				mate.revive.rpc_id(mate.name.to_int(), display_name)
				Sfx.play("revive")
				search = {}
		elif search.t >= search.dur:
			var c: Dictionary = _world.containers[search.idx]
			if not c.get("seen", false):
				searched += 1
			c.seen = true
			_world.request_open.rpc_id(1, search.idx)
			search = {}

	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	if not placing.is_empty():
		_update_placing()
	# pisar el fuego quema
	if _world.in_fire(global_position):
		hp -= 12.0 * delta
		_hurt_flash = 0.3
		if hp <= 0.0:
			_zero_hp("Te quemaste en tu propio fuego.")


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
		_zero_hp(cause)


# ------------------------------------------------------------------ mochila y peso
func _recalc_weight() -> void:
	var w := 0.0
	for k in inv:
		w += inv[k] * Items.kg(k)
	for k in owned:
		if k != "puños":
			w += Items.kg(k)
	weight = w


## Teclas 1, 2 y 3: comer lo mejor que tengas, beber, vendarte.
func use_item(slot: String) -> void:
	if dead or downed:
		return
	var options: Array = {"comida": ["guiso", "comida"], "agua": ["agua"], "vendas": ["vendas"]}.get(slot, [slot])
	for k in options:
		if inv.get(k, 0) > 0:
			consume(k)
			return
	message.emit({"comida": "No tienes comida.", "agua": "No tienes agua.", "vendas": "No tienes vendas."}.get(slot, "No tienes eso."), true)


## Usa una unidad de algo según sus datos (hambre, sed, curación…).
func consume(k: String) -> void:
	var it: ItemData = Items.ITEMS[k]
	if it.hunger > 0 and it.thirst <= 0 and hunger > 95:
		message.emit("No tienes hambre.", false)
		return
	if it.thirst > 0 and it.hunger <= 0 and thirst > 95:
		message.emit("No tienes sed.", false)
		return
	inv[k] -= 1
	hunger = minf(100.0, hunger + it.hunger)
	thirst = minf(100.0, thirst + it.thirst)
	hp = minf(100.0, hp + it.heal)
	var was := bleeding
	if it.stops_bleeding:
		bleeding = false
	if it.leaves != "":
		inv[it.leaves] = inv.get(it.leaves, 0) + 1
	match k:
		"comida": message.emit("Comes una lata fría de alubias.", false)
		"guiso": message.emit("Comes un guiso caliente. Sienta de maravilla.", false)
		"agua": message.emit("Bebes media botella de un trago.", false)
		"vendas": message.emit("Te vendas la herida. Deja de sangrar." if was else "Te cambias las vendas.", false)
		_: message.emit("Usas %s." % it.name.to_lower(), false)
	if it.category == "medicina":
		Sfx.play("pick", 0.0, 0.7)
	else:
		Sfx.play("eat", 0.0, 1.3 if it.thirst > it.hunger else 1.0)
	_recalc_weight()


## Quita `n` unidades de la mochila (un arma cuenta como 1). Devuelve cuántas quitó.
func _remove_item(k: String, n: int) -> int:
	var removed := 0
	if owned.has(k) and k != "puños":
		owned.erase(k)
		if weapon == k:
			weapon = "puños"
		removed = 1
	elif inv.get(k, 0) > 0:
		removed = mini(n, inv[k])
		inv[k] -= removed
	_recalc_weight()
	return removed


## Cuántas unidades de `k` te caben ahora mismo.
func fit_count(k: String, n: int) -> int:
	if Items.WEAPONS.has(k):
		return 1 if owned.has(k) or weight + Items.kg(k) <= Items.CARRY_MAX + 0.001 else 0
	return clampi(int(floor((Items.CARRY_MAX - weight) / Items.kg(k) + 0.001)), 0, n)


## Pide coger del mueble abierto lo que te quepa.
func take(idx: int, k: String, n: int) -> void:
	var fit := fit_count(k, n)
	if fit <= 0:
		message.emit("No te cabe en la mochila: %s." % Items.ITEMS[k].name.to_lower(), true)
		return
	_world.request_take.rpc_id(1, idx, k, fit)


## Deja cosas en el mueble abierto.
func put(idx: int, k: String, n: int) -> void:
	var removed := _remove_item(k, n)
	if removed > 0:
		_world.return_loot.rpc_id(1, idx, {k: removed})


## Suelta una unidad en el suelo (queda un bulto que se puede recoger).
func drop_item(k: String) -> void:
	if dead:
		return
	var removed := _remove_item(k, 1)
	if removed > 0:
		_world.request_drop.rpc_id(1, global_position - global_transform.basis.z * 0.6, {k: removed}, "Bulto en el suelo", false)
		message.emit("Sueltas %s en el suelo." % Items.ITEMS[k].name.to_lower(), false)


func _start_search() -> void:
	if not search.is_empty():
		return
	# levantar a un compañero va antes que registrar
	if revive_target:
		search = {"revive": revive_target, "t": 0.0, "dur": REVIVE_TIME, "pos": global_position}
		message.emit("Levantando a %s… no te muevas." % revive_target.display_name, false)
		return
	if interact_idx < 0:
		return
	var c: Dictionary = _world.containers[interact_idx]
	# la primera vez se registra; después se abre al momento
	var dur: float = 0.25 if c.get("seen", false) else Items.CONTAINERS[c.type].time
	search = {"idx": interact_idx, "t": 0.0, "dur": dur, "pos": global_position}
	if dur > 0.5:
		Sfx.play_at("search", c.pos, -4.0)
	_noise_spike = 3.0


## El anfitrión te da algo que pediste coger.
func _on_item_granted(_idx: int, k: String, n: int) -> void:
	if Items.WEAPONS.has(k):
		owned[k] = Items.WEAPONS[k].dur  # si ya tenías una, cambias la vieja por esta
		if Items.WEAPON_ORDER.find(k) > Items.WEAPON_ORDER.find(weapon) and k != "pistola":
			weapon = k
	else:
		inv[k] = inv.get(k, 0) + n
	Sfx.play("pick")
	_recalc_weight()


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
			Sfx.play("empty")
			message.emit("No te quedan balas.", true)
			return
		inv.balas -= 1
		_recalc_weight()
		_attack_cd = w.cd
		attack_count += 1
		figure.play_attack(w.cd)
		_attack_fx()
		shake = maxf(shake, 0.5)
		get_tree().call_group("main", "impact", 0.35)
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
	_attack_fx()


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
		hits[i][1].damage.rpc_id(1, w.dmg * randf_range(0.85, 1.2), hits[i][2], weapon)
	if n > 0:
		_noise_spike = w.noise
		shake = maxf(shake, 0.25 if weapon == "puños" else 0.4)
		if weapon == "hacha":
			get_tree().call_group("main", "impact", 0.3)
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
		col.damage.rpc_id(1, dmg, dir, "pistola")


# ------------------------------------------------------------------ daño y muerte
## Lo llama el zombi (desde el anfitrión) en el equipo del dueño.
@rpc("any_peer", "call_local", "reliable")
func take_hit(dmg: float, from: Vector3) -> void:
	if dead or multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	if downed:
		# te siguen mordiendo en el suelo: aguantas menos
		bleed_out -= 8.0
		Sfx.play("hurt")
		shake = maxf(shake, 0.5)
		return
	hp -= dmg
	_hurt_flash = 0.35
	shake = maxf(shake, 0.6)
	Sfx.play("hurt")
	_world.spawn_word(global_position, "herido", Color(0.8, 0.1, 0.06), 0.9)
	get_tree().call_group("main", "impact", 0.25)
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
		_zero_hp("Te devoraron con la mordida todavía fresca." if infected else "Te rodearon y te arrastraron al suelo.")


@rpc("any_peer", "call_local", "reliable")
func add_kill() -> void:
	kills += 1


## Salud a cero: en cooperativo caes al suelo; jugando solo, mueres.
func _zero_hp(cause: String) -> void:
	if downed or dead:
		return
	if _teammate_alive():
		hp = 0.0
		downed = true
		bleed_out = BLEED_OUT_TIME
		_down_cause = cause
		search = {}
		crouching = false
		Sfx.play("hurt", 0.0, 0.7)
		get_tree().call_group("main", "impact", 0.6)
		message.emit("¡Has caído! Tu compañero puede levantarte con E. Arrástrate hacia él.", true)
	else:
		_die(cause)


func _physics_downed(delta: float) -> void:
	bleed_out -= delta
	if bleed_out <= 0.0 or not _teammate_alive():
		downed = false
		_die(_down_cause if bleed_out > 0.0 else "Te desangraste esperando ayuda.")
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if captured else Vector2.ZERO
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = move_toward(velocity.x, dir.x * 0.6, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z * 0.6, ACCEL * delta)
	move_and_slide()
	var new_noise := 1.0 if input.length() > 0.1 else 0.0
	if new_noise != noise:
		noise = new_noise


## ¿Queda alguien en pie que pueda levantarte?
func _teammate_alive() -> bool:
	if not Network.is_online():
		return false
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and not p.dead and not p.downed:
			return true
	return false


func _find_downed_teammate() -> Node3D:
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p.downed and not p.dead and p.global_position.distance_to(global_position) < 2.2:
			return p
	return null


## Te levanta un compañero (se ejecuta en tu equipo).
@rpc("any_peer", "call_local", "reliable")
func revive(by: String) -> void:
	if not downed:
		return
	downed = false
	hp = 30.0
	bleed_out = 0.0
	Sfx.play("revive")
	message.emit("¡%s te ha levantado!" % by, false)


func _die(cause: String) -> void:
	if dead:
		return
	downed = false
	_cancel_placing()
	hp = 0.0
	dead = true
	search = {}
	crouching = false
	# la mochila se queda junto al cadáver; puedes volver a por ella
	var items := {}
	for k in inv:
		if inv[k] > 0:
			items[k] = inv[k]
	for k in owned:
		if k != "puños":
			items[k] = 1
	if not items.is_empty():
		_world.request_drop.rpc_id(1, global_position, items, "Mochila de %s" % display_name, true)
	inv = {"comida": 0, "agua": 0, "vendas": 0, "balas": 0}
	owned = {"puños": -1}
	weapon = "puños"
	_recalc_weight()
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
	downed = false
	_recalc_weight()
	position = SPAWN_POINT + Vector3(randf_range(-2, 2), 0.5, 0)
	velocity = Vector3.ZERO
	dead = false


# ------------------------------------------------------------------ guardado
var _loaded := false


func export_state() -> Dictionary:
	return {
		"pos": global_position, "yaw": rotation.y, "dead": dead,
		"hp": hp, "stamina": stamina, "hunger": hunger, "thirst": thirst,
		"bleeding": bleeding, "infected": infected,
		"inv": inv.duplicate(), "owned": owned.duplicate(), "weapon": weapon,
		"kills": kills, "searched": searched, "alive_time": alive_time,
	}


## Recupera tu personaje si esta partida ya la habías jugado.
func try_load() -> void:
	if _loaded or not is_multiplayer_authority() or Network.world_id.is_empty():
		return
	_loaded = true
	var d := SaveGame.load_character(Network.world_id, Network.player_name)
	if d.is_empty() or d.get("dead", false):
		return  # nuevo, o habías muerto: tu mochila te espera en el cadáver
	global_position = d.pos
	rotation.y = d.yaw
	hp = d.hp
	stamina = d.stamina
	hunger = d.hunger
	thirst = d.thirst
	bleeding = d.bleeding
	infected = d.infected
	inv = d.inv
	owned = d.owned
	weapon = d.weapon
	kills = d.kills
	searched = d.searched
	alive_time = d.alive_time
	_recalc_weight()
	message.emit("Continúas donde lo dejaste.", false)


func save_state() -> void:
	if is_multiplayer_authority() and _loaded:
		SaveGame.save_character(Network.world_id, Network.player_name, export_state())


## Linterna: cuelga de la cámara para alumbrar donde miras. Solo la tuya
## proyecta sombras (las de los demás serían caras y casi no se notan).
func _build_torch() -> void:
	_torch = SpotLight3D.new()
	_torch.light_color = Color(1.0, 0.93, 0.8)
	_torch.light_energy = 4.0
	_torch.spot_range = 24.0
	_torch.spot_angle = 26.0
	_torch.spot_attenuation = 0.7
	_torch.shadow_enabled = is_multiplayer_authority()
	_torch.position = Vector3(0.25, -0.1, -0.4)
	_torch.visible = flashlight
	pivot.add_child(_torch)


## Sonido y onomatopeya de un ataque (propio o de otro jugador).
func _attack_fx() -> void:
	var w: ItemData = Items.WEAPONS[weapon]
	if w.gun:
		Sfx.play_at("shot", global_position + Vector3.UP * 1.4, 6.0, 1.0, 80.0)
		_world.spawn_word(global_position + (-global_transform.basis.z * 0.8), "pistola", Color(1.0, 0.85, 0.3), 1.4)
	else:
		Sfx.play_at("swing", global_position + Vector3.UP * 1.2, -2.0)


# ------------------------------------------------------------------ fabricar
## Estaciones que tienes cerca para fabricar.
func stations() -> Array[String]:
	var out: Array[String] = ["manos"]
	for st in ["banco", "hoguera"]:
		if _world.structures.near(global_position, st):
			out.append(st)
	return out


func has_tool() -> bool:
	for k in owned:
		if k != "puños" and Items.WEAPONS[k].is_tool:
			return true
	return false


func start_craft(rid: String) -> void:
	var r: RecipeData = Items.RECIPES[rid]
	if not search.is_empty() or dead or downed:
		return
	if r.station not in stations():
		message.emit("Necesitas estar junto a: %s." % {"banco": "un banco de trabajo", "hoguera": "una hoguera"}[r.station], true)
		return
	if not Items.can_craft(r, inv, owned):
		message.emit("Te falta material: %s." % Items.ingredients_text(r), true)
		return
	if r.result == "reparar":
		var w: ItemData = Items.WEAPONS[weapon]
		if w.dur <= 0 or owned.get(weapon, -1) >= w.dur:
			message.emit("Lleva en la mano un arma gastada para repararla.", true)
			return
	if r.result.begins_with("estructura:"):
		_start_placing(r)
		return
	search = {"craft": r, "t": 0.0, "dur": r.time, "pos": global_position}
	Sfx.play_at("search", global_position, -4.0, 1.3)


func _finish_craft(r: RecipeData) -> void:
	if not Items.can_craft(r, inv, owned):
		return
	_pay(r)
	if r.result == "reparar":
		var w: ItemData = Items.WEAPONS[weapon]
		owned[weapon] = mini(w.dur, owned[weapon] + int(w.dur * 0.5))
		message.emit("Reparas %s (%d golpes)." % [w.name.to_lower(), owned[weapon]], false)
	elif Items.WEAPONS.has(r.result):
		owned[r.result] = Items.WEAPONS[r.result].dur
		weapon = r.result
		message.emit("Fabricas %s." % Items.ITEMS[r.result].name.to_lower(), false)
	else:
		inv[r.result] = inv.get(r.result, 0) + r.result_count
		message.emit("Fabricas %s." % ("%d× %s" % [r.result_count, Items.ITEMS[r.result].name] if r.result_count > 1 else Items.ITEMS[r.result].name).to_lower(), false)
	Sfx.play("pick")
	_recalc_weight()
	# si te pasas de peso, lo que sobra se queda en el suelo
	if weight > Items.CARRY_MAX and not Items.WEAPONS.has(r.result) and r.result != "reparar":
		var extra := mini(inv[r.result], int(ceil((weight - Items.CARRY_MAX) / Items.kg(r.result))))
		if extra > 0:
			_remove_item(r.result, extra)
			_world.request_drop.rpc_id(1, global_position, {r.result: extra}, "Bulto en el suelo", false)
			message.emit("No te cabe todo: dejas %d en el suelo." % extra, true)


## Gasta los ingredientes de una receta.
func _pay(r: RecipeData) -> void:
	for k in r.ingredients:
		_remove_item(k, int(r.ingredients[k]))


# ------------------------------------------------------------------ colocar estructuras
## {recipe, type, ghost, rot} mientras eliges dónde poner algo
var placing := {}


func _start_placing(r: RecipeData) -> void:
	var type := r.result.trim_prefix("estructura:")
	var ghost: Node3D = _world.structures._build(type)
	ghost.collision_layer = 0
	for mi in ghost.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.95, 0.9, 0.75, 0.45)
		(mi as MeshInstance3D).material_override = m
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for l in ghost.find_children("*", "Light3D", true, false):
		l.queue_free()
	get_tree().current_scene.add_child(ghost)
	placing = {"recipe": r, "type": type, "ghost": ghost, "rot": rotation.y, "ok": false}
	message.emit("Colocar %s: clic para poner, R para girar, clic derecho para cancelar." % Items.RECIPES[r.id].name.to_lower(), false)


func _update_placing() -> void:
	var ghost: Node3D = placing.ghost
	var fwd := -global_transform.basis.z
	var p := global_position + fwd * 2.0
	p = Vector3(snappedf(p.x, 0.25), 0.0, snappedf(p.z, 0.25))
	ghost.global_position = p
	ghost.rotation.y = placing.rot
	# ¿choca con algo?
	var size: Vector3 = _world.structures.TYPES[placing.type].size
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = size * 0.95
	q.shape = box
	q.transform = Transform3D(Basis(Vector3.UP, placing.rot), p + Vector3.UP * (size.y / 2 + 0.05))
	q.collision_mask = 1 | 2 | 4
	q.exclude = [get_rid()]
	var ok := get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()
	placing.ok = ok
	var tint := Color(0.95, 0.9, 0.75, 0.45) if ok else Color(0.9, 0.15, 0.1, 0.45)
	for mi in ghost.find_children("*", "MeshInstance3D", true, false):
		((mi as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = tint


func _confirm_placing() -> void:
	if placing.is_empty():
		return
	if not placing.ok:
		message.emit("Ahí no cabe.", true)
		return
	var r: RecipeData = placing.recipe
	if not Items.can_craft(r, inv, owned):
		_cancel_placing()
		return
	_pay(r)
	_recalc_weight()
	_world.structures.request_place.rpc_id(1, placing.type, placing.ghost.global_position, placing.rot)
	_noise_spike = 8.0
	_cancel_placing()


func _cancel_placing() -> void:
	if placing.has("ghost") and is_instance_valid(placing.ghost):
		placing.ghost.queue_free()
	placing = {}


# ------------------------------------------------------------------ desmontar
func start_dismantle(idx: int) -> void:
	if not search.is_empty() or dead or downed:
		return
	if not has_tool():
		message.emit("Necesitas un hacha o un martillo para desmontarlo.", true)
		return
	var c: Dictionary = _world.containers[idx]
	var cd: ContainerData = Items.CONTAINERS[c.type]
	search = {"dismantle": idx, "t": 0.0, "dur": cd.dismantle_time, "pos": global_position}
	message.emit("Desmontando %s… hace ruido." % c.name.to_lower(), false)


func _finish_dismantle(idx: int) -> void:
	_world.request_dismantle.rpc_id(1, idx)
	_world.spawn_word(_world.containers[idx].pos, "desmontar")
	shake = maxf(shake, 0.3)
	# gasta la herramienta (la mejor que lleves)
	for k in ["martillo", "hacha"]:
		if owned.has(k):
			owned[k] -= 3
			if owned[k] <= 0:
				message.emit("Tu %s se rompió." % Items.ITEMS[k].name.to_lower(), true)
				owned.erase(k)
				if weapon == k:
					weapon = "puños"
			break
	_recalc_weight()


# ------------------------------------------------------------------ molotov
func _throw_molotov() -> void:
	if inv.get("molotov", 0) <= 0:
		message.emit("No tienes cócteles molotov (fabrícalos con una botella, alcohol y trapos).", true)
		return
	inv.molotov -= 1
	_recalc_weight()
	var from := global_position + Vector3.UP * 1.6
	var dir := -camera.global_transform.basis.z
	var vel := dir * 13.0 + Vector3.UP * 3.5
	var p := from
	var t := 0.0
	var space := get_world_3d().direct_space_state
	var land := from
	while t < 3.0:
		var nv := vel + Vector3.DOWN * 9.8 * 0.03
		var np := p + nv * 0.03
		var q := PhysicsRayQueryParameters3D.create(p, np, LAYER_WORLD | LAYER_ZOMBIES, [get_rid()])
		var hit := space.intersect_ray(q)
		t += 0.03
		if not hit.is_empty():
			land = hit.position
			break
		if np.y <= 0.0:
			land = Vector3(np.x, 0.0, np.z)
			break
		p = np
		vel = nv
		land = p
	land.y = 0.05
	_noise_spike = 12.0
	attack_count += 1
	figure.play_attack(0.5)
	Sfx.play_at("swing", global_position, 0.0, 0.8)
	_world.request_fire.rpc_id(1, from, land, t)


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
