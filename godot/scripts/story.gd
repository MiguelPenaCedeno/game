extends Node3D
## La historia: unas notas, una radio sin batería y un helicóptero.
## Vive en World/Historia; el anfitrión decide en qué punto está y se lo
## cuenta a todos. Se guarda con el mundo.
##
##   0 registrar la comisaría  → nota del sargento
##   1 ir al control militar   → orden de evacuación
##   2 batería en el hospital  → batería de emergencia
##   3 llevarla a la radio     → la radio da el día del rescate
##   4 esa noche, hoguera en la Granja Vieja y llegar allí
##   5 aguantar la horda hasta que llegue el helicóptero
##   6 subir al helicóptero
##   7 rescatados (se puede seguir jugando)

signal changed

const OBJECTIVES := [
	"Averigua qué pasó: registra la comisaría del pueblo.",
	"Ve al control militar de la carretera del oeste.",
	"Busca una batería de emergencia en el hospital.",
	"Lleva la batería a la radio del control militar.",
	"Noche del día %d: enciende una hoguera en la Granja Vieja y espera allí.",
	"¡Aguantad hasta que llegue el helicóptero!",
	"¡El helicóptero ha aterrizado en el campo! Subid (E).",
	"Rescatados. El condado sigue ahí, si queréis volver.",
]
const PLACES := ["Comisaría", "Control militar", "Hospital", "Control militar", "Granja Vieja", "Granja Vieja", "Granja Vieja", ""]
const INTRO := "La radio del coche crepita entre la estática:\n\n«…repetimos: no salgan de sus casas… los afectados no responden… la comisaría del pueblo coordina… »\n\nDespués, nada. Solo el viento y algo que gruñe al otro lado de la calle.\n\n(Tu objetivo aparece debajo del reloj. M abre el mapa.)"
const RADIO_CALL := "«…aquí HALCÓN-2… os recibimos…»\n\n«Recogida en el claro de la Granja Vieja, al oeste, la noche del día %d. Encended una hoguera para que os veamos desde el aire. Si hay muertos alrededor, aguantad: no podemos bajar en caliente.»\n\n«HALCÓN-2, corto.»"
const RADIO_STATIC := "La radio está muerta. Sin batería no hay nada que hacer."
const RESCUE_WAIT := 75.0

var stage := 0
var rescue_day := 0
var heli: Node3D
var _check := 0.0
var _rescue_t := 0.0
var _marker_id := 0
var _rotor: Node3D
var _rotor_sound: AudioStreamPlayer3D
var _heli_tween: Tween
@onready var world: Node = get_parent()


func objective_text() -> String:
	var t: String = OBJECTIVES[clampi(stage, 0, OBJECTIVES.size() - 1)]
	return t % rescue_day if stage == 4 else t


func place_pos(name: String) -> Vector3:
	for pl in world.layout.places:
		if pl.name == name:
			return pl.pos
	return Vector3.INF


## Donde aterriza: el campo arado de la Granja Vieja.
func landing_pos() -> Vector3:
	return place_pos("Granja Vieja") + Vector3(0, 0, -22)


func radio_pos() -> Vector3:
	return world.layout.specials.get("radio", Vector3.INF)


# ------------------------------------------------------------------ red
## Alguien leyó una nota.
@rpc("any_peer", "call_local", "reliable")
func read(item: String) -> void:
	if not multiplayer.is_server():
		return
	if item == "nota_comisaria" and stage < 1:
		_advance(1)
	elif item == "nota_control" and stage < 2:
		_advance(2)


## Alguien cogió algo importante.
@rpc("any_peer", "call_local", "reliable")
func event(what: String) -> void:
	if multiplayer.is_server() and what == "bateria" and stage == 2:
		_advance(3)


## Usar la radio (con la batería ya gastada si tocaba).
@rpc("any_peer", "call_local", "reliable")
func use_radio(with_battery: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := maxi(multiplayer.get_remote_sender_id(), 1)
	if stage == 3 and with_battery:
		rescue_day = world.day_number() + 1
		_advance(4)
		_radio.rpc(RADIO_CALL % rescue_day)
	elif stage >= 4 and stage < 7:
		_radio.rpc_id(sender, RADIO_CALL % rescue_day)
	else:
		_radio.rpc_id(sender, RADIO_STATIC)


@rpc("authority", "call_local", "reliable")
func _radio(text: String) -> void:
	get_tree().call_group("hud", "show_paper", "Radio", text)
	Sfx.play("click", 0.0, 0.6)


## Subir al helicóptero.
@rpc("any_peer", "call_local", "reliable")
func board() -> void:
	if not multiplayer.is_server() or stage != 6:
		return
	_advance(7)
	_ending.rpc(world.day_number())
	get_tree().create_timer(6.0).timeout.connect(func(): _heli_leave.rpc())


func _advance(n: int) -> void:
	_set_stage.rpc(n, rescue_day)
	# marca en el mapa para todos con el sitio del objetivo
	if _marker_id > 0:
		world._remove_marker.rpc(_marker_id)
		_marker_id = 0
	var where: String = PLACES[clampi(n, 0, PLACES.size() - 1)]
	var p := place_pos(where) if where != "" else Vector3.INF
	if p != Vector3.INF:
		world._marker_seq += 1
		_marker_id = world._marker_seq
		world._add_marker.rpc(_marker_id, Vector2(p.x, p.z), 0, "Historia", Color(0.95, 0.75, 0.2))


@rpc("authority", "call_local", "reliable")
func _set_stage(s: int, day: int) -> void:
	var was := stage
	stage = s
	rescue_day = day
	changed.emit()
	if s != was and s > 0:
		get_tree().call_group("hud", "toast", "Objetivo: " + objective_text(), false)


func send_state_to(peer: int) -> void:
	_set_stage.rpc_id(peer, stage, rescue_day)
	if stage == 6:
		_heli_land.rpc_id(peer, true)


func export_state() -> Dictionary:
	return {"stage": stage, "rescue_day": rescue_day, "marker": _marker_id}


func import_state(d: Dictionary) -> void:
	stage = int(d.get("stage", 0))
	rescue_day = int(d.get("rescue_day", 0))
	_marker_id = int(d.get("marker", 0))
	# a medias del rescate: se vuelve a esperar a la noche
	if stage == 5 or stage == 6:
		stage = 4
	changed.emit()


func reset() -> void:
	stage = 0
	rescue_day = 0
	_marker_id = 0
	if heli:
		heli.queue_free()
		heli = null


## La primera marca (la comisaría) al empezar una partida nueva.
func start_new() -> void:
	if multiplayer.is_server() and stage == 0 and _marker_id == 0:
		_advance(0)


# ------------------------------------------------------------------ rescate (anfitrión)
func _process(delta: float) -> void:
	if _rotor:
		_rotor.rotation.y += delta * 22.0
	if not multiplayer.is_server():
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	match stage:
		4:
			if world.night and world.day_number() >= rescue_day and _fire_at_farm() and _player_near(place_pos("Granja Vieja"), 50.0):
				_advance(5)
				_rescue_t = RESCUE_WAIT
				_rescue_start.rpc()
				var main := get_tree().get_first_node_in_group("main")
				if main:
					main.rescue_horde(place_pos("Granja Vieja"))
		5:
			_rescue_t -= 1.0
			if _rescue_t <= 0.0:
				_advance(6)
				_heli_land.rpc(false)


func _fire_at_farm() -> bool:
	var farm := place_pos("Granja Vieja")
	for sid in world.structures.by_id:
		var s: Dictionary = world.structures.by_id[sid]
		if s.type == "hoguera" and Vector2(s.pos.x - farm.x, s.pos.z - farm.z).length() < 40.0:
			return true
	return false


func _player_near(p: Vector3, dist: float) -> bool:
	for pl in get_tree().get_nodes_in_group("players"):
		if not pl.dead and pl.global_position.distance_to(p) < dist:
			return true
	return false


@rpc("authority", "call_local", "reliable")
func _rescue_start() -> void:
	get_tree().call_group("hud", "toast", "Se oye un helicóptero a lo lejos… ¡y los muertos también lo oyen! Aguantad.", true)
	get_tree().call_group("main", "impact", 0.5)
	for i in 3:
		Sfx.play("groan%d" % i, 4.0, 0.7 + i * 0.1)


## El helicóptero llega desde el oeste y se posa en el campo.
@rpc("authority", "call_local", "reliable")
func _heli_land(instant: bool) -> void:
	if heli == null:
		heli = _build_heli()
		add_child(heli)
	var land := landing_pos()
	if _heli_tween:
		_heli_tween.kill()
	if instant:
		heli.position = land
		return
	heli.position = land + Vector3(-140, 55, 30)
	heli.look_at(land + Vector3(0, 55, 0), Vector3.UP)
	var tw := heli.create_tween()
	_heli_tween = tw
	tw.tween_property(heli, "position", land + Vector3(0, 12, 0), 12.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(heli, "position", land, 4.0).set_trans(Tween.TRANS_SINE)
	get_tree().call_group("hud", "toast", "¡HALCÓN-2 está aterrizando! Corred al helicóptero.", false)


@rpc("authority", "call_local", "reliable")
func _heli_leave() -> void:
	if heli == null:
		return
	var h := heli
	heli = null
	var tw := h.create_tween()
	tw.tween_property(h, "position", h.position + Vector3(0, 20, 0), 4.0)
	tw.tween_property(h, "position", h.position + Vector3(160, 70, 60), 10.0)
	tw.tween_callback(func():
		_rotor = null
		h.queue_free())


@rpc("authority", "call_local", "reliable")
func _ending(day: int) -> void:
	var main := get_tree().get_first_node_in_group("main")
	var me: Node = main.players.get_node_or_null(str(multiplayer.get_unique_id())) if main else null
	var stats := ""
	if me:
		stats = "\n\nZombis abatidos: %d · Muebles registrados: %d\nHabilidades: %s" % [me.kills, me.searched, me.skills_text()]
	get_tree().call_group("hud", "show_paper", "¡Rescatados!",
		"El helicóptero se eleva sobre el bosque. Abajo, la hoguera se hace pequeña y los muertos siguen mirando hacia arriba.\n\nSobrevivisteis %d días en el condado.%s\n\n(Puedes cerrar esto y seguir jugando en el mismo mundo.)" % [day, stats])


func _build_heli() -> Node3D:
	var h := Node3D.new()
	h.name = "Helicoptero"
	var olive := Color(0.3, 0.33, 0.24)
	var dark := Color(0.12, 0.13, 0.12)
	world._box(Vector3(0, 1.6, 0), Vector3(2.4, 2.0, 4.6), olive, true, h, 0.3, 3.0)
	world._box(Vector3(0, 1.9, -2.6), Vector3(2.0, 1.4, 1.0), Color(0.16, 0.19, 0.22), false, h, 0.0)
	world._box(Vector3(0, 2.0, 4.6), Vector3(0.5, 0.6, 5.0), olive, false, h)
	world._box(Vector3(0.3, 2.6, 6.9), Vector3(0.1, 1.4, 0.8), olive, false, h)
	for s in [-1.0, 1.0]:
		world._box(Vector3(s * 1.2, 0.15, 0), Vector3(0.12, 0.12, 4.0), dark, false, h)
		world._box(Vector3(s * 1.2, 0.4, -1.0), Vector3(0.08, 0.5, 0.08), dark, false, h)
		world._box(Vector3(s * 1.2, 0.4, 1.0), Vector3(0.08, 0.5, 0.08), dark, false, h)
	_rotor = Node3D.new()
	_rotor.position = Vector3(0, 2.9, 0)
	h.add_child(_rotor)
	world._box(Vector3.ZERO, Vector3(11.0, 0.06, 0.35), dark, false, _rotor)
	world._box(Vector3.ZERO, Vector3(0.35, 0.06, 11.0), dark, false, _rotor)
	var light := SpotLight3D.new()
	light.position = Vector3(0, 0.6, -1.5)
	light.rotation.x = -PI / 2
	light.spot_range = 40.0
	light.spot_angle = 25.0
	light.light_energy = 4.0
	h.add_child(light)
	_rotor_sound = AudioStreamPlayer3D.new()
	_rotor_sound.stream = Sfx.streams.get("rotor")
	_rotor_sound.unit_size = 30.0
	_rotor_sound.max_distance = 400.0
	_rotor_sound.volume_db = 4.0
	_rotor_sound.autoplay = true
	h.add_child(_rotor_sound)
	return h
