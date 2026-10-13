extends CharacterBody3D
## Coche o furgoneta que se puede conducir. Manda quien conduce (como cada
## jugador manda sobre su personaje): su equipo mueve el coche y envía la
## posición a los demás. Aparcado, manda el anfitrión. El anfitrión decide
## quién se sube (conductor y copiloto) para que nunca haya dos al volante.
##
## Gasta gasolina al moverse (se rellena con bidones de gasolina), hace ruido
## que atrae a los zombis y los atropella. Si se destroza, ya no arranca.

const KINDS := {
	"coche": {"name": "Coche", "len": 4.2, "width": 1.8, "height": 1.45, "max_speed": 19.0, "accel": 7.5, "tank": 40.0},
	"furgoneta": {"name": "Furgoneta", "len": 4.8, "width": 2.0, "height": 2.0, "max_speed": 15.0, "accel": 6.0, "tank": 55.0},
}
const REVERSE_MAX := 6.0
## litros por metro recorrido (40 l dan para unos 3 km)
const FUEL_PER_M := 0.012
## litros que echa un bidón
const CAN_LITERS := 6.0
const TURN_RATE := 1.7
const GRAVITY := 16.0

@export var kind := "coche"
@export var color := Color(0.46, 0.27, 0.2)
@export var net_pos := Vector3.ZERO
@export var net_yaw := 0.0
## velocidad hacia delante (m/s, negativa marcha atrás)
@export var speed := 0.0
@export var steer := 0.0
@export var fuel := 10.0
@export var health := 100.0
@export var lights := false:
	set(value):
		lights = value
		for l in _lights:
			l.visible = value
## ids de red de quien va al volante y de copiloto (0 = nadie)
@export var driver := 0:
	set(value):
		driver = value
		set_multiplayer_authority(value if value != 0 else 1)
		# el sincronizador decide a quién envía al empezar: hay que avisarle del cambio
		if is_node_ready():
			$Sync.update_visibility()
@export var passenger := 0

var _built := false
var _lights: Array[SpotLight3D] = []
var _wheels: Array[Node3D] = []
var _front_wheels: Array[Node3D] = []
var _engine: AudioStreamPlayer3D
var _wheel_spin := 0.0
## zombis atropellados hace poco (para no darles mil veces): nombre -> tiempo
var _hit_cd := {}


func _ready() -> void:
	add_to_group("vehicles")
	collision_layer = 1
	collision_mask = 1
	_build()
	if not is_multiplayer_authority():
		position = net_pos
		rotation.y = net_yaw


func spec() -> Dictionary:
	return KINDS.get(kind, KINDS.coche)


func display_name() -> String:
	return spec().name


## Asientos (local): conductor a la izquierda, copiloto a la derecha.
func seat_offset(seat: int) -> Vector3:
	var s := spec()
	return Vector3(-0.42 if seat == 0 else 0.42, 0.35, -0.1 if s.len < 4.5 else -0.9)


func is_wrecked() -> bool:
	return health <= 0.0


# ------------------------------------------------------------------ subir y bajar (decide el anfitrión)
@rpc("any_peer", "call_local", "reliable")
func request_enter(want_seat: int) -> void:
	if not multiplayer.is_server():
		return
	var who := _sender()
	if who == driver or who == passenger:
		return
	var seat := want_seat
	if seat == 0 and driver != 0:
		seat = 1
	if seat == 1 and passenger != 0:
		seat = 0 if driver == 0 else -1
	if seat < 0:
		return
	if seat == 0:
		_set_seats.rpc(who, passenger)
	else:
		_set_seats.rpc(driver, who)
	_seated.rpc_id(who, seat)


@rpc("any_peer", "call_local", "reliable")
func request_exit() -> void:
	if not multiplayer.is_server():
		return
	var who := _sender()
	if who == driver:
		_set_seats.rpc(0, passenger)
	elif who == passenger:
		_set_seats.rpc(driver, 0)


## Alguien se fue de la partida: libera su asiento.
func forget_peer(peer: int) -> void:
	if peer == driver:
		_set_seats.rpc(0, passenger)
	elif peer == passenger:
		_set_seats.rpc(driver, 0)


## Lo manda siempre el anfitrión (aunque el coche lo lleve otro: por eso "any_peer").
@rpc("any_peer", "call_local", "reliable")
func _set_seats(d: int, p: int) -> void:
	if multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	# el que recibe el volante parte de la última posición conocida
	if d != driver:
		position = net_pos
		rotation.y = net_yaw
		speed = 0.0
	driver = d
	passenger = p
	Sfx.play_at("door", global_position, -2.0)


## Al que se sube: siéntate.
@rpc("any_peer", "call_local", "reliable")
func _seated(seat: int) -> void:
	if multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	var me: Node = get_tree().get_first_node_in_group("main").players.get_node_or_null(str(multiplayer.get_unique_id()))
	if me:
		me.sit_in(self, seat)


## Echar gasolina: lo aplica quien manda sobre el coche.
@rpc("any_peer", "call_local", "reliable")
func add_fuel(liters: float) -> void:
	if not is_multiplayer_authority():
		return
	fuel = minf(spec().tank, fuel + liters)


func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return s if s != 0 else 1


# ------------------------------------------------------------------ conducir
func _physics_process(delta: float) -> void:
	if not _built:
		return
	if not is_multiplayer_authority():
		_net_smooth(delta)
		_animate(delta)
		return
	var s := spec()
	var mine := driver != 0 and driver == multiplayer.get_unique_id()
	var main := get_tree().get_first_node_in_group("main")
	var captured: bool = main != null and main.gameplay_input()
	var throttle := 0.0
	var steer_in := 0.0
	var brake := false
	if mine and captured:
		throttle = Input.get_axis("move_back", "move_forward")
		steer_in = Input.get_axis("move_right", "move_left")
		brake = Input.is_action_pressed("jump")
	if fuel <= 0.0 or is_wrecked():
		throttle = 0.0
	# acelerar, frenar y marcha atrás
	if throttle > 0.0:
		speed += (s.accel if speed >= 0.0 else 16.0) * throttle * delta
	elif throttle < 0.0:
		speed += (-16.0 if speed > 0.5 else -s.accel * 0.6) * -throttle * delta
	else:
		speed = move_toward(speed, 0.0, 2.5 * delta)
	if brake:
		speed = move_toward(speed, 0.0, 20.0 * delta)
	speed = clampf(speed, -REVERSE_MAX, s.max_speed * (0.6 if health < 30.0 else 1.0))
	steer = lerpf(steer, steer_in, 1.0 - exp(-7.0 * delta))
	# gira más despacio parado y con el freno de mano derrapa un poco
	var grip := clampf(absf(speed) / 5.0, 0.0, 1.0) * signf(speed)
	rotation.y += steer * grip * TURN_RATE * (1.25 if brake else 1.0) * delta
	var fwd := -global_transform.basis.z
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	var before := global_position
	move_and_slide()
	_collisions(fwd)
	if mine:
		fuel = maxf(0.0, fuel - before.distance_to(global_position) * FUEL_PER_M - (0.0004 * delta if throttle != 0.0 else 0.0))
		_run_over(fwd)
	if position.y < -20.0:
		position = net_pos + Vector3.UP * 2.0
	net_pos = position
	net_yaw = rotation.y
	_animate(delta)


## Choques contra paredes, árboles y coches: frenazo y abolladura.
func _collisions(fwd: Vector3) -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) > 0.6:
			continue
		var impact := absf(speed * fwd.dot(n))
		if impact > 5.0:
			health = maxf(0.0, health - (impact - 5.0) * 3.5)
			Sfx.play_at("crash", global_position, clampf(impact - 8.0, -6.0, 6.0))
			get_tree().call_group("main", "impact", clampf(impact / 30.0, 0.0, 0.5))
			speed *= 0.25
			if is_wrecked():
				_world().spawn_word(global_position, "derribo", Color(0.98, 0.95, 0.85), 1.4)
		else:
			speed *= 0.97
		break


## Atropellar: quien conduce avisa al anfitrión del golpe.
func _run_over(fwd: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if absf(speed) < 3.0:
		return
	var s := spec()
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.dead or _hit_cd.get(z.name, 0) > now:
			continue
		var local: Vector3 = global_transform.affine_inverse() * z.global_position
		var front: float = -local.z if speed > 0.0 else local.z
		if absf(local.x) < s.width / 2 + 0.45 and front > s.len / 2 - 0.8 and front < s.len / 2 + 0.7 and absf(local.y) < 2.0:
			_hit_cd[z.name] = now + 700
			var dmg := absf(speed) * 0.5
			z.damage.rpc_id(1, dmg, fwd * signf(speed) * absf(speed) * 0.4 + Vector3.UP * 2.0, "coche")
			speed *= 0.82
			health = maxf(0.0, health - 1.0)
			get_tree().call_group("main", "impact", 0.25)


func _net_smooth(delta: float) -> void:
	if position.distance_squared_to(net_pos) > 36.0:
		position = net_pos
	else:
		position = position.lerp(net_pos, 1.0 - exp(-12.0 * delta))
	rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - exp(-12.0 * delta))


func _animate(delta: float) -> void:
	_wheel_spin += speed * delta / 0.36
	for w in _wheels:
		w.rotation.x = -_wheel_spin
	for w in _front_wheels:
		w.rotation.y = steer * 0.45
	# motor: suena si hay alguien al volante
	var running := driver != 0 and fuel > 0.0 and not is_wrecked()
	if running and not _engine.playing:
		_engine.play()
	elif not running and _engine.playing:
		_engine.stop()
	_engine.pitch_scale = 0.8 + absf(speed) / spec().max_speed * 1.1


func _world() -> Node:
	return get_tree().get_first_node_in_group("world")


# ------------------------------------------------------------------ aspecto
## Carrocería hecha con cajas, como los coches abandonados, pero mirando a -Z.
func _build() -> void:
	if _built:
		return
	_built = true
	var w := _world()
	var s := spec()
	var length: float = s.len
	var width: float = s.width
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 1.0 if kind == "coche" else 1.5, length)
	shape.shape = box
	shape.position.y = 0.75 if kind == "coche" else 1.0
	add_child(shape)
	var body := Node3D.new()
	body.name = "Carroceria"
	add_child(body)
	var glass := Color(0.16, 0.19, 0.22)
	if kind == "coche":
		w._box(Vector3(0, 0.62, 0), Vector3(width, 0.62, length), color, false, body, 0.2, 3.0)
		w._box(Vector3(0, 1.17, 0.25), Vector3(1.62, 0.5, 2.1), glass, false, body, 0.0)
		w._box(Vector3(0, 1.44, 0.25), Vector3(1.66, 0.06, 2.0), color, false, body)
		for x in [-0.8, 0.8]:
			w._box(Vector3(x, 1.17, 0.25), Vector3(0.05, 0.5, 0.08), color, false, body)
	else:
		w._box(Vector3(0, 1.1, 0.35), Vector3(width, 1.6, length - 0.7), color, false, body, 0.2, 3.0)
		w._box(Vector3(0, 0.75, -length / 2 + 0.35), Vector3(width, 0.9, 0.7), color, false, body, 0.2, 3.0)
		w._box(Vector3(0, 1.45, -length / 2 + 0.72), Vector3(width - 0.1, 0.55, 0.05), glass, false, body, 0.0)
		for x in [-1.0, 1.0]:
			w._box(Vector3(x * width / 2, 1.45, -length / 2 + 1.2), Vector3(0.04, 0.5, 0.8), glass, false, body, 0.0)
	for x in [-1.0, 1.0]:
		w._box(Vector3(x * 0.62, 0.72, -length / 2), Vector3(0.32, 0.16, 0.04), Color(0.95, 0.92, 0.8), false, body, 0.0)
		w._box(Vector3(x * 0.62, 0.72, length / 2), Vector3(0.3, 0.14, 0.04), Color(0.6, 0.05, 0.03), false, body, 0.0)
		var lamp := SpotLight3D.new()
		lamp.position = Vector3(x * 0.62, 0.75, -length / 2 - 0.1)
		lamp.spot_range = 26.0
		lamp.spot_angle = 32.0
		lamp.light_energy = 2.2
		lamp.light_color = Color(1.0, 0.92, 0.75)
		lamp.shadow_enabled = false
		lamp.visible = lights
		add_child(lamp)
		_lights.append(lamp)
	w._box(Vector3(0, 0.45, -length / 2 - 0.04), Vector3(width + 0.05, 0.16, 0.12), Color(0.4, 0.42, 0.44), false, body)
	w._box(Vector3(0, 0.45, length / 2 + 0.04), Vector3(width + 0.05, 0.16, 0.12), Color(0.4, 0.42, 0.44), false, body)
	# todo lo que no se mueve, en una sola malla
	var batcher := MeshBatcher.new()
	for mi in body.get_children():
		var m := (mi as MeshInstance3D).material_override as ShaderMaterial
		var g: float = m.get_shader_parameter("grit")
		var gs: float = m.get_shader_parameter("grit_scale")
		batcher.add(mi.mesh, mi.transform, [g, gs], w.helper._batch_mat(g, gs), m.get_shader_parameter("albedo"))
		mi.free()
	batcher.build(body, "Lote")
	# ruedas (giran y las de delante viran)
	for wz in [-1.0, 1.0]:
		for wx in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(wx * (width / 2 - 0.05), 0.36, wz * (length / 2 - 0.85))
			add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			var tire: MeshInstance3D = w._cyl_mesh(Vector3.ZERO, 0.36, 0.36, 0.26, Color(0.1, 0.1, 0.1), spin)
			tire.rotation.z = PI / 2
			w._box(Vector3(0.14 * wx, 0.18, 0), Vector3(0.03, 0.12, 0.12), Color(0.5, 0.5, 0.5), false, spin)
			_wheels.append(spin)
			if wz < 0:
				_front_wheels.append(pivot)
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = Sfx.streams.get("engine")
	_engine.volume_db = -4.0
	_engine.unit_size = 8.0
	_engine.max_distance = 60.0
	add_child(_engine)


## Para el guardado (solo el anfitrión).
func export_state() -> Dictionary:
	return {"kind": kind, "color": color, "pos": net_pos if net_pos != Vector3.ZERO else position,
		"yaw": net_yaw, "fuel": fuel, "health": health}
