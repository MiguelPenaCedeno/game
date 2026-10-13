extends Node3D
## Menú principal, pausa y gestión de jugadores.
## Solo el anfitrión (servidor) crea los personajes; el MultiplayerSpawner
## los copia automáticamente en el equipo de cada jugador.
##
## Desde la línea de comandos (útil para probar):
##   godot -- --solo | --host | --join=IP   [--name=Nombre]

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const HUD_SCRIPT := preload("res://scripts/hud.gd")
const ZOMBIE_COUNT := 26
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
var _zombie_counter := 0
var _zombie_timer: Timer


func _ready() -> void:
	menu_camera.look_at_from_position(Vector3(30, 14, 34), Vector3(4, 0, 6))
	# el menú y la interfaz siguen vivos en pausa; el mundo no
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in [world, players, zombies]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE
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


func _unhandled_input(event: InputEvent) -> void:
	if not in_game:
		return
	if event.is_action_pressed("pause"):
		if hud.inventory.visible:
			hud.close_panel()
		elif not hud.death.visible:
			_set_paused(not pause_panel.visible)
	elif event.is_action_pressed("inventory") and not pause_panel.visible:
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
	for p in players.get_children():
		p.queue_free()
	for z in zombies.get_children():
		z.queue_free()
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
	pbox.add_child(_button("Salir al menú principal", _on_leave_pressed))

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
func _start_zombies() -> void:
	world.bake_navigation()
	var region: NavigationRegion3D = world.get_node("Navegacion")
	if region.is_baking():
		await region.bake_finished
	# espera a que el mapa de navegación incluya la malla nueva
	var map := get_world_3d().navigation_map
	for i in 120:
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_closest_point(map, Vector3(30, 0, 30)) != Vector3.ZERO:
			break
		await get_tree().physics_frame
	if not in_game:
		return
	for i in ZOMBIE_COUNT:
		_spawn_zombie()
	if _zombie_timer == null:
		_zombie_timer = Timer.new()
		_zombie_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
		_zombie_timer.wait_time = 15.0
		_zombie_timer.timeout.connect(_refill_zombies)
		add_child(_zombie_timer)
	_zombie_timer.start()


func _refill_zombies() -> void:
	if not in_game or not multiplayer.is_server():
		return
	var alive := 0
	for z in zombies.get_children():
		if not z.dead:
			alive += 1
	for i in mini(ZOMBIE_COUNT - alive, 3):
		_spawn_zombie()


func _spawn_zombie() -> void:
	var map := get_world_3d().navigation_map
	for attempt in 20:
		var p := Vector3(randf_range(-62, 62), 0, randf_range(-62, 62))
		var on_nav := NavigationServer3D.map_get_closest_point(map, p)
		if on_nav != Vector3.ZERO:
			p = on_nav
		var too_close := p.distance_to(Vector3.ZERO) < ZOMBIE_SPAWN_MIN_DIST
		for pl in players.get_children():
			if pl.global_position.distance_to(p) < ZOMBIE_SPAWN_MIN_DIST:
				too_close = true
		if too_close:
			continue
		var z := ZOMBIE_SCENE.instantiate()
		_zombie_counter += 1
		z.name = "Z%d" % _zombie_counter
		z.position = p + Vector3.UP * 0.1
		z.rotation.y = randf() * TAU
		z.net_pos = z.position
		z.net_yaw = z.rotation.y
		zombies.add_child(z, true)
		return


# ------------------------------------------------------------------ guardado
## Al crear la partida (solo o anfitrión): cargar la guardada o empezar una nueva.
func _prepare_world() -> void:
	var d := {}
	if not new_game_check.button_pressed:
		d = SaveGame.load_world()
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
