extends Node3D
## Menú principal, pausa y gestión de jugadores.
## Solo el anfitrión (servidor) crea los personajes; el MultiplayerSpawner
## los copia automáticamente en el equipo de cada jugador.
##
## Desde la línea de comandos (útil para probar):
##   godot -- --solo | --host | --join=IP   [--name=Nombre]

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const VEHICLE_SCENE := preload("res://scenes/vehicle.tscn")
const HUD_SCRIPT := preload("res://scripts/hud.gd")
## zombis alrededor de cada jugador (en el pueblo; en el campo hay menos)
const ZOMBIE_COUNT := 22
const ZOMBIE_MAX := 45
## los que se alejan más que esto de todos los jugadores desaparecen
const ZOMBIE_DESPAWN_DIST := 115.0
## cada cuántos días llega una horda (esa noche)
const HORDE_EVERY := 7
var _horde_warned_day := 0
## los zombis nuevos aparecen al menos así de lejos de cualquier jugador
const ZOMBIE_SPAWN_MIN_DIST := 30.0
const INK_SHADER := preload("res://shaders/ink_post.gdshader")
const FONT_TITLE := preload("res://fonts/SpecialElite-Regular.ttf")
const FONT_UI := preload("res://fonts/BarlowCondensed-SemiBold.ttf")
const INK := Color(0.07, 0.065, 0.075)
const PAPER := Color(0.95, 0.92, 0.84)
const ACCENT := Color(0.62, 0.06, 0.04)

@onready var players: Node3D = $Players
@onready var zombies: Node3D = $Zombies
@onready var world: Node3D = $World
@onready var vehicles: Node3D = $Vehicles
## vehículos del guardado, a la espera de crearse al empezar
var _saved_vehicles: Array = []
var _vehicle_counter := 0
@onready var menu_camera: Camera3D = $MenuCamera

var in_game := false
var ui: CanvasLayer
var ui_root: Control
var menu_panel: CenterContainer
var pause_panel: CenterContainer
var name_edit: LineEdit
var ip_edit: LineEdit
var status_label: Label
var hud: Control
var new_game_check: CheckBox
var save_label: Label
var _autosave: Timer
var settings_panel: CenterContainer
var _settings_return: Control
var _ink_mat: ShaderMaterial
var _zombie_counter := 0
var _zombie_timer: Timer


func _ready() -> void:
	add_to_group("main")
	menu_camera.look_at_from_position(Vector3(30, 14, 34), Vector3(4, 0, 6))
	# el menú y la interfaz siguen vivos en pausa; el mundo no
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in [world, players, zombies]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.night_changed.connect(_on_night_changed)
	_add_ink_pass()
	_build_ui()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_handle_cmdline()


func _process(_delta: float) -> void:
	if in_game:
		_update_hud()
		# aviso al atardecer del día de la horda (cada equipo lo calcula con su reloj)
		var day: int = world.day_number()
		if is_horde_day(day) and world.hour() >= 17.0 and _horde_warned_day != day:
			_horde_warned_day = day
			hud.toast("Esta noche llega una HORDA. Fortificad la base: barricadas, muros y trampas.", true)
	_update_ink_daylight()


func _unhandled_input(event: InputEvent) -> void:
	if not in_game:
		return
	if event.is_action_pressed("pause"):
		if settings_panel.visible:
			_close_settings()
		elif hud.paper_map.visible:
			hud.close_map()
		elif hud.inventory.visible:
			hud.close_panel()
		elif not hud.death.visible:
			_set_paused(not pause_panel.visible)
	elif event.is_action_pressed("map") and not pause_panel.visible:
		hud.toggle_map()
	elif event.is_action_pressed("inventory") and not pause_panel.visible:
		if hud.paper_map.visible:
			hud.close_map()
		hud.toggle_inventory()
	elif event.is_action_pressed("interact") and hud.inventory.visible:
		hud.close_panel()
	elif event is InputEventMouseButton and event.pressed and not pause_panel.visible and not hud.is_blocking():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ acciones del menú
func _on_solo_pressed() -> void:
	Network.player_name = _chosen_name()
	Network.play_solo()
	_prepare_world()
	_start_game()
	_add_player(1)
	_spawn_vehicles()
	_start_zombies()


func _on_host_pressed() -> void:
	Network.player_name = _chosen_name()
	var err := Network.host()
	if err != OK:
		status_label.text = "No se pudo crear la partida (¿el puerto %d está ocupado?)." % Network.PORT
		return
	_prepare_world()
	_start_game()
	_add_player(1)
	_spawn_vehicles()
	_start_zombies()


func _on_join_pressed() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		status_label.text = "Escribe la IP del anfitrión."
		return
	Network.player_name = _chosen_name()
	var err := Network.join(ip)
	if err != OK:
		status_label.text = "Dirección no válida."
		return
	status_label.text = "Conectando con %s…" % ip


func _on_leave_pressed() -> void:
	save_now()
	Network.leave()
	_back_to_menu("")


# ------------------------------------------------------------------ red
func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_receive_world_id.rpc_id(id, Network.world_id)
		_add_player(id)
		world.send_state_to(id)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		var p := players.get_node_or_null(str(id))
		if p:
			p.queue_free()
		world.forget_peer(id)
		for v in vehicles.get_children():
			v.forget_peer(id)


func _on_connected_to_server() -> void:
	_start_game()  # el anfitrión nos creará el personaje


func _on_connection_failed() -> void:
	Network.leave()
	status_label.text = "No se pudo conectar. Revisa la IP y que la partida esté creada."


func _on_server_disconnected() -> void:
	save_now()
	Network.leave()
	_back_to_menu("El anfitrión cerró la partida.")


func _add_player(id: int) -> void:
	var p := PLAYER_SCENE.instantiate()
	p.name = str(id)
	players.add_child(p, true)


# ------------------------------------------------------------------ estados
func _start_game() -> void:
	in_game = true
	world.clock_running = true
	if _autosave == null:
		_autosave = Timer.new()
		_autosave.wait_time = 60.0
		_autosave.timeout.connect(save_now)
		add_child(_autosave)
	_autosave.start()
	menu_panel.visible = false
	hud.visible = true
	status_label.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _back_to_menu(message: String) -> void:
	in_game = false
	world.clock_running = false
	for p in players.get_children():
		p.queue_free()
	for z in zombies.get_children():
		z.queue_free()
	for v in vehicles.get_children():
		v.queue_free()
	if _zombie_timer:
		_zombie_timer.stop()
	if _autosave:
		_autosave.stop()
	Network.world_id = ""
	world.reset_containers()
	menu_camera.current = true
	get_tree().paused = false
	pause_panel.visible = false
	hud.visible = false
	hud.player = null
	menu_panel.visible = true
	status_label.text = message
	_refresh_save_info()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_paused(open: bool) -> void:
	# jugando solo se detiene todo; con otra persona conectada el mundo sigue
	pause_panel.visible = open
	get_tree().paused = open and not Network.is_online()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func _chosen_name() -> String:
	var n := name_edit.text.strip_edges()
	return n if not n.is_empty() else "Superviviente"


func _update_hud() -> void:
	var lines := PackedStringArray()
	if not Network.is_online():
		lines.append("Partida en solitario")
	elif multiplayer.is_server():
		lines.append("Anfitrión · puerto %d · tus IPs: %s" % [Network.PORT, ", ".join(Network.local_addresses())])
	else:
		lines.append("Conectado a la partida")
	lines.append("Jugadores: %d" % players.get_child_count())
	hud.set_info("\n".join(lines))


func _handle_cmdline() -> void:
	var mode := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--name="):
			name_edit.text = arg.trim_prefix("--name=")
		elif arg == "--solo" or arg == "--host":
			mode = arg
		elif arg.begins_with("--test="):
			var runner: Node = load("res://tests/test_runner.gd").new()
			runner.mode = arg.trim_prefix("--test=")
			runner.name = "Pruebas"
			add_child(runner)
			return
		elif arg.begins_with("--join="):
			ip_edit.text = arg.trim_prefix("--join=")
			mode = "--join"
	match mode:
		"--solo": _on_solo_pressed()
		"--host": _on_host_pressed()
		"--join": _on_join_pressed()


# ------------------------------------------------------------------ interfaz
func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = _comic_theme()
	ui.add_child(ui_root)

	# menú principal
	menu_panel = _centered_panel()
	var box := menu_panel.get_child(0).get_child(0) as VBoxContainer
	var title := Label.new()
	title.text = "PUEBLO MUERTO"
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var lede := Label.new()
	lede.text = "Registra las casas, come, bebe y aguanta otra noche. Mejor en compañía."
	lede.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lede.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lede.add_theme_font_override("font", FONT_TITLE)
	lede.add_theme_font_size_override("font_size", 18)
	box.add_child(lede)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Tu nombre"
	name_edit.max_length = 20
	box.add_child(name_edit)

	save_label = Label.new()
	save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_label.add_theme_font_size_override("font_size", 17)
	box.add_child(save_label)
	new_game_check = CheckBox.new()
	new_game_check.text = "Empezar de cero (borra la partida guardada)"
	new_game_check.add_theme_color_override("font_color", INK)
	new_game_check.add_theme_color_override("font_hover_color", ACCENT)
	new_game_check.add_theme_color_override("font_pressed_color", ACCENT)
	box.add_child(new_game_check)
	_refresh_save_info()
	box.add_child(_button("Jugar solo", _on_solo_pressed))
	box.add_child(_button("Crear partida (anfitrión)", _on_host_pressed))

	var join_row := HBoxContainer.new()
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "IP del anfitrión (p. ej. 100.64.0.2)"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_edit.text_submitted.connect(func(_t): _on_join_pressed())
	join_row.add_child(ip_edit)
	join_row.add_child(_button("Unirse", _on_join_pressed))
	box.add_child(join_row)

	box.add_child(_button("Ajustes", func(): _open_settings(menu_panel)))

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", ACCENT)
	box.add_child(status_label)

	# pausa
	pause_panel = _centered_panel()
	pause_panel.visible = false
	var pbox := pause_panel.get_child(0).get_child(0) as VBoxContainer
	var ptitle := Label.new()
	ptitle.text = "EN PAUSA"
	ptitle.add_theme_font_override("font", FONT_TITLE)
	ptitle.add_theme_font_size_override("font_size", 40)
	ptitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pbox.add_child(ptitle)
	var keys := Label.new()
	keys.text = "WASD moverte · Shift correr · C agacharte · Espacio saltar\nClic golpear o disparar · E registrar · Q cambiar arma\n1 comer · 2 beber · 3 vendarte · Tab mochila"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pbox.add_child(keys)
	pbox.add_child(_button("Seguir jugando", func(): _set_paused(false)))
	pbox.add_child(_button("Ajustes", func(): _open_settings(pause_panel)))
	pbox.add_child(_button("Salir al menú principal", _on_leave_pressed))
	_build_settings()

	# HUD
	# interfaz de juego
	hud = HUD_SCRIPT.new()
	ui_root.add_child(hud)
	ui_root.move_child(hud, 0)
	hud.respawn_requested.connect(func():
		var me := players.get_node_or_null(str(multiplayer.get_unique_id()))
		if me:
			me.respawn())
	hud.leave_requested.connect(_on_leave_pressed)


func _centered_panel() -> CenterContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	return center


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	return b


## Plano a pantalla completa con el postproceso de tinta y papel.
func _add_ink_pass() -> void:
	var quad := MeshInstance3D.new()
	quad.name = "InkPass"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	quad.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = INK_SHADER
	mat.render_priority = -100  # antes que los textos 3D (nombres)
	quad.material_override = mat
	_ink_mat = mat
	Settings.changed.connect(_apply_ink_settings)
	_apply_ink_settings()
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)


## Estilo de viñeta: papel, borde de tinta grueso y sombra desplazada.
func _comic_theme() -> Theme:
	var th := Theme.new()
	th.default_font = FONT_UI
	th.default_font_size = 21

	var panel := _comic_box(PAPER, 3, 6)
	panel.content_margin_left = 22
	panel.content_margin_right = 22
	panel.content_margin_top = 16
	panel.content_margin_bottom = 18
	th.set_stylebox("panel", "PanelContainer", panel)

	th.set_stylebox("normal", "Button", _comic_box(PAPER, 2, 3))
	th.set_stylebox("hover", "Button", _comic_box(Color(0.98, 0.86, 0.55), 2, 3))
	th.set_stylebox("pressed", "Button", _comic_box(INK, 2, 0))
	th.set_stylebox("focus", "Button", _comic_box(Color(0, 0, 0, 0), 2, 0))
	th.set_color("font_color", "Button", INK)
	th.set_color("font_hover_color", "Button", INK)
	th.set_color("font_focus_color", "Button", INK)
	th.set_color("font_pressed_color", "Button", PAPER)

	th.set_stylebox("normal", "LineEdit", _comic_box(Color(1, 0.99, 0.95), 2, 0))
	th.set_stylebox("focus", "LineEdit", _comic_box(Color(0, 0, 0, 0), 3, 0))
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.45))
	th.set_color("caret_color", "LineEdit", INK)

	th.set_color("font_color", "Label", INK)

	var track := StyleBoxFlat.new()
	track.bg_color = INK
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	th.set_stylebox("slider", "HSlider", track)
	var filled := StyleBoxFlat.new()
	filled.bg_color = ACCENT
	filled.content_margin_top = 2
	filled.content_margin_bottom = 2
	th.set_stylebox("grabber_area", "HSlider", filled)
	th.set_stylebox("grabber_area_highlight", "HSlider", filled)
	th.set_color("font_color", "CheckBox", INK)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		th.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	th.set_color("font_color", "OptionButton", INK)
	th.set_color("font_hover_color", "OptionButton", INK)
	return th


func _comic_box(bg: Color, border: int, shadow: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = INK
	sb.set_border_width_all(border)
	sb.shadow_color = INK
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(shadow, shadow)
	if shadow > 0:
		sb.shadow_size = 1
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


# ------------------------------------------------------------------ zombis (solo anfitrión)
## Los zombis viven cerca de los jugadores: aparecen a 32-70 m (fuera de la
## vista) en zonas con navegación y desaparecen cuando todos se alejan.
func _start_zombies() -> void:
	world.enable_navigation()
	# espera a que la zona de salida tenga su malla de navegación
	for i in 300:
		var ready := true
		for p in players.get_children():
			if not world.nav_ready_at(p.global_position):
				ready = false
		if ready and players.get_child_count() > 0:
			break
		await get_tree().physics_frame
	for i in 20:
		await get_tree().physics_frame
	if not in_game:
		return
	for p in players.get_children():
		for i in _local_target(p.global_position):
			_spawn_zombie(p.global_position)
	if _zombie_timer == null:
		_zombie_timer = Timer.new()
		_zombie_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
		_zombie_timer.wait_time = 12.0
		_zombie_timer.timeout.connect(_refill_zombies)
		add_child(_zombie_timer)
	_zombie_timer.start()


func _refill_zombies() -> void:
	if not in_game or not multiplayer.is_server():
		return
	var alive: Array[Node] = []
	for z in zombies.get_children():
		if z.dead:
			continue
		# los que se quedaron lejos de todos desaparecen (salvo los que persiguen a alguien)
		var near := INF
		for p in players.get_children():
			near = minf(near, z.global_position.distance_to(p.global_position))
		if near > ZOMBIE_DESPAWN_DIST and not z.horde:
			z.queue_free()
			continue
		alive.append(z)
	for p in players.get_children():
		var around := 0
		for z in alive:
			if z.global_position.distance_to(p.global_position) < 75.0:
				around += 1
		for i in mini(_local_target(p.global_position) - around, 3):
			if alive.size() >= ZOMBIE_MAX * maxi(players.get_child_count(), 1):
				break
			_spawn_zombie(p.global_position)


## Cada día hay más zombis, y de noche más todavía.
func zombie_target() -> int:
	var n: int = ZOMBIE_COUNT + (world.day_number() - 1) * 4
	if world.night:
		n = int(n * 1.4)
	return mini(n, ZOMBIE_MAX)


## Cuántos zombis rondan por aquí (el pueblo está más lleno que el bosque).
func _local_target(pos: Vector3) -> int:
	return int(zombie_target() * world.layout.density_at(pos))


func _spawn_zombie(near: Vector3) -> Node:
	var map := get_world_3d().navigation_map
	for attempt in 24:
		var a := randf() * TAU
		var p := near + Vector3(cos(a), 0, sin(a)) * randf_range(ZOMBIE_SPAWN_MIN_DIST + 2.0, 70.0)
		if absf(p.x) > world.HALF - 3.0 or absf(p.z) > world.HALF - 3.0 or not world.nav_ready_at(p):
			continue
		var on_nav := NavigationServer3D.map_get_closest_point(map, p)
		if on_nav == Vector3.ZERO or Vector2(on_nav.x - p.x, on_nav.z - p.z).length() > 6.0:
			continue
		p = on_nav
		var too_close := false
		for pl in players.get_children():
			if pl.global_position.distance_to(p) < ZOMBIE_SPAWN_MIN_DIST:
				too_close = true
		if too_close:
			continue
		return _add_zombie(p, randf() * TAU)
	return null


func _add_zombie(p: Vector3, yaw: float, horde_target := Vector3.INF) -> Node:
	var z := ZOMBIE_SCENE.instantiate()
	_zombie_counter += 1
	z.name = "Z%d" % _zombie_counter
	z.position = p + Vector3.UP * 0.1
	z.rotation.y = yaw
	z.net_pos = z.position
	z.net_yaw = z.rotation.y
	if horde_target != Vector3.INF:
		z.horde = true
		z.horde_target = horde_target
	zombies.add_child(z, true)
	return z


# ------------------------------------------------------------------ vehículos (solo anfitrión)
## Coches y furgonetas que arrancan: los del guardado o, en partida nueva, los del mapa.
func _spawn_vehicles() -> void:
	for v in vehicles.get_children():
		v.queue_free()
	var list: Array = _saved_vehicles
	if list.is_empty():
		for spot in world.layout.vehicles:
			list.append({"kind": spot.kind, "color": spot.color, "pos": spot.pos, "yaw": spot.yaw,
				"fuel": snappedf(randf_range(3.0, 14.0), 0.1), "health": 100.0})
	for d in list:
		var v := VEHICLE_SCENE.instantiate()
		_vehicle_counter += 1
		v.name = "V%d" % _vehicle_counter
		v.kind = d.kind
		v.color = d.color
		v.position = d.pos + Vector3.UP * 0.2
		v.rotation.y = d.yaw
		v.net_pos = v.position
		v.net_yaw = d.yaw
		v.fuel = d.fuel
		v.health = d.health
		vehicles.add_child(v, true)
	_saved_vehicles = []


# ------------------------------------------------------------------ guardado
## Al crear la partida (solo o anfitrión): cargar la guardada o empezar una nueva.
func _prepare_world() -> void:
	var d := {}
	if not new_game_check.button_pressed:
		d = SaveGame.load_world()
	_saved_vehicles = d.get("vehicles", [])
	if d.is_empty():
		SaveGame.delete_world()
		world.reset_containers()
		Network.world_id = SaveGame.new_world_id()
		SaveGame.save_world({"world_id": Network.world_id})
	else:
		Network.world_id = d.world_id
		world.import_state(d)
	new_game_check.button_pressed = false


@rpc("authority", "call_remote", "reliable")
func _receive_world_id(id: String) -> void:
	Network.world_id = id
	var me := players.get_node_or_null(str(multiplayer.get_unique_id()))
	if me:
		me.try_load()


func save_now() -> void:
	if not in_game:
		return
	if multiplayer.is_server() and not Network.world_id.is_empty():
		var d: Dictionary = world.export_state()
		d.world_id = Network.world_id
		d.vehicles = []
		for v in vehicles.get_children():
			if not v.is_queued_for_deletion():
				d.vehicles.append(v.export_state())
		SaveGame.save_world(d)
	var me := players.get_node_or_null(str(multiplayer.get_unique_id()))
	if me:
		me.save_state()


func _refresh_save_info() -> void:
	if save_label == null:
		return
	var has := SaveGame.has_world()
	save_label.text = "Hay una partida guardada: al jugar solo o crear partida, continúas." if has else ""
	save_label.visible = has
	new_game_check.visible = has


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()


# ------------------------------------------------------------------ ajustes
func _apply_ink_settings() -> void:
	_ink_mat.set_shader_parameter("line_width", Settings.line_width)
	_ink_mat.set_shader_parameter("grain", Settings.grain)


const INK_PAPER_DAY := Color(0.95, 0.91, 0.82)
const INK_PAPER_NIGHT := Color(0.74, 0.8, 0.98)
const INK_LINE_NIGHT := Color(0.42, 0.47, 0.6)


## De noche el cómic pierde el color (salvo el rojo) y la trama se suaviza.
func _update_ink_daylight() -> void:
	var l: float = world.daylight
	_ink_mat.set_shader_parameter("saturation", lerpf(0.05, 0.38, l))
	_ink_mat.set_shader_parameter("paper", INK_PAPER_NIGHT.lerp(INK_PAPER_DAY, l))
	_ink_mat.set_shader_parameter("hatch_strength", Settings.hatching * lerpf(0.5, 1.0, l))
	# de noche las líneas se aclaran (tiza a la luz de la luna) para que se lean sobre lo oscuro
	_ink_mat.set_shader_parameter("line_color", INK_LINE_NIGHT.lerp(INK, smoothstep(0.1, 0.45, l)))
	_impact = maxf(0.0, _impact - get_process_delta_time() * 7.0)
	_ink_mat.set_shader_parameter("impact", _impact)


var _impact := 0.0


## Viñeta de impacto (golpes fuertes, disparos): un instante en blanco y negro puro.
func impact(strength: float) -> void:
	_impact = maxf(_impact, strength)


func _open_settings(from: Control) -> void:
	_settings_return = from
	from.visible = false
	settings_panel.visible = true


func _close_settings() -> void:
	settings_panel.visible = false
	if _settings_return:
		_settings_return.visible = true


func _build_settings() -> void:
	settings_panel = _centered_panel()
	settings_panel.visible = false
	var box := settings_panel.get_child(0).get_child(0) as VBoxContainer
	var title := Label.new()
	title.text = "AJUSTES"
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)

	_slider(grid, "Sensibilidad del ratón", "mouse_sensitivity", 0.0005, 0.006, 0.0001, func(v): return "%d" % roundi(v * 10000))
	_check(grid, "Invertir eje vertical", "invert_y")
	_slider(grid, "Campo de visión", "fov", 50, 95, 1, func(v): return "%d°" % v)
	_slider(grid, "Volumen", "volume", 0, 1, 0.05, func(v): return "%d%%" % roundi(v * 100))
	_check(grid, "Pantalla completa", "fullscreen")
	_check(grid, "Sincronización vertical", "vsync")
	_slider(grid, "Resolución 3D", "render_scale", 0.5, 1.0, 0.05, func(v): return "%d%%" % roundi(v * 100))
	_option(grid, "Sombras", "shadows", ["Sin sombras", "Bajas", "Altas"])
	_slider(grid, "Grosor de la tinta", "line_width", 0.6, 2.5, 0.1, func(v): return "%.1f" % v)
	_slider(grid, "Trama en sombras", "hatching", 0.0, 1.0, 0.05, func(v): return "%d%%" % roundi(v * 100))
	_slider(grid, "Grano del papel", "grain", 0.0, 0.2, 0.01, func(v): return "%d%%" % roundi(v * 500))
	box.add_child(_button("Volver", _close_settings))


func _label(grid: GridContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 210
	grid.add_child(l)


func _slider(grid: GridContainer, text: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	_label(grid, text)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = Settings.get(key)
	sl.custom_minimum_size = Vector2(220, 24)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(sl)
	var val := Label.new()
	val.text = fmt.call(sl.value)
	val.custom_minimum_size.x = 56
	grid.add_child(val)
	sl.value_changed.connect(func(v):
		val.text = fmt.call(v)
		Settings.set_value(key, v))


func _check(grid: GridContainer, text: String, key: String) -> void:
	_label(grid, text)
	var cb := CheckBox.new()
	cb.button_pressed = Settings.get(key)
	cb.toggled.connect(func(on): Settings.set_value(key, on))
	grid.add_child(cb)
	grid.add_child(Control.new())


func _option(grid: GridContainer, text: String, key: String, options: Array) -> void:
	_label(grid, text)
	var ob := OptionButton.new()
	for o in options:
		ob.add_item(o)
	ob.selected = Settings.get(key)
	ob.item_selected.connect(func(i): Settings.set_value(key, i))
	grid.add_child(ob)
	grid.add_child(Control.new())


# ------------------------------------------------------------------ hordas
func is_horde_day(day: int) -> bool:
	return day % HORDE_EVERY == 0


## Días que faltan para la próxima horda (0 = esta noche).
func days_to_horde() -> int:
	var day: int = world.day_number()
	return (HORDE_EVERY - day % HORDE_EVERY) % HORDE_EVERY


func _on_night_changed(is_night: bool) -> void:
	if not in_game or not is_night or not is_horde_day(world.day_number()):
		return
	if multiplayer.is_server():
		start_horde()


## La horda sale del bosque y va a por la base (o a por vosotros si estáis lejos de ella).
func start_horde() -> void:
	if not multiplayer.is_server():
		return
	var base := _base_position()
	var anchor := base
	var near_base := false
	for p in players.get_children():
		if p.global_position.distance_to(base) < 90.0:
			near_base = true
	if not near_base and players.get_child_count() > 0:
		anchor = players.get_child(randi() % players.get_child_count()).global_position
		base = anchor
	var count: int = 14 + world.day_number()
	var side := randf() * TAU
	var map := get_world_3d().navigation_map
	for i in count:
		var a := side + randf_range(-0.5, 0.5)
		var p := anchor + Vector3(cos(a), 0, sin(a)) * randf_range(50.0, 62.0)
		p.x = clampf(p.x, -world.HALF + 4.0, world.HALF - 4.0)
		p.z = clampf(p.z, -world.HALF + 4.0, world.HALF - 4.0)
		var on_nav := NavigationServer3D.map_get_closest_point(map, p)
		if on_nav != Vector3.ZERO and Vector2(on_nav.x - p.x, on_nav.z - p.z).length() < 10.0:
			p = on_nav
		_add_zombie(p, 0.0, base + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
	_horde_announce.rpc()


@rpc("authority", "call_local", "reliable")
func _horde_announce() -> void:
	hud.toast("¡La HORDA está aquí! Vienen a por la base.", true)
	for i in 3:
		Sfx.play("groan%d" % i, 4.0, 0.7 + i * 0.1)
	impact(0.5)


## La base: el centro de lo construido; si no hay nada, donde estáis vosotros.
func _base_position() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for sid in world.structures.by_id:
		sum += world.structures.by_id[sid].pos
		n += 1
	if n == 0:
		for p in players.get_children():
			sum += p.global_position
			n += 1
	return sum / maxi(n, 1)
