extends Node3D
## Menú principal, pausa y gestión de jugadores.
## Solo el anfitrión (servidor) crea los personajes; el MultiplayerSpawner
## los copia automáticamente en el equipo de cada jugador.
##
## Desde la línea de comandos (útil para probar):
##   godot -- --solo | --host | --join=IP   [--name=Nombre]

const PLAYER_SCENE := preload("res://scenes/player.tscn")

@onready var players: Node3D = $Players
@onready var menu_camera: Camera3D = $MenuCamera

var in_game := false
var ui: CanvasLayer
var menu_panel: CenterContainer
var pause_panel: CenterContainer
var name_edit: LineEdit
var ip_edit: LineEdit
var status_label: Label
var hud_label: Label


func _ready() -> void:
	menu_camera.look_at_from_position(Vector3(42, 34, 42), Vector3.ZERO)
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
		_set_paused(not pause_panel.visible)
	elif event is InputEventMouseButton and event.pressed and not pause_panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ acciones del menú
func _on_solo_pressed() -> void:
	Network.player_name = _chosen_name()
	Network.play_solo()
	_start_game()
	_add_player(1)


func _on_host_pressed() -> void:
	Network.player_name = _chosen_name()
	var err := Network.host()
	if err != OK:
		status_label.text = "No se pudo crear la partida (¿el puerto %d está ocupado?)." % Network.PORT
		return
	_start_game()
	_add_player(1)


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
	Network.leave()
	_back_to_menu("")


# ------------------------------------------------------------------ red
func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_add_player(id)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		var p := players.get_node_or_null(str(id))
		if p:
			p.queue_free()


func _on_connected_to_server() -> void:
	_start_game()  # el anfitrión nos creará el personaje


func _on_connection_failed() -> void:
	Network.leave()
	status_label.text = "No se pudo conectar. Revisa la IP y que la partida esté creada."


func _on_server_disconnected() -> void:
	Network.leave()
	_back_to_menu("El anfitrión cerró la partida.")


func _add_player(id: int) -> void:
	var p := PLAYER_SCENE.instantiate()
	p.name = str(id)
	players.add_child(p, true)


# ------------------------------------------------------------------ estados
func _start_game() -> void:
	in_game = true
	menu_panel.visible = false
	hud_label.visible = true
	status_label.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _back_to_menu(message: String) -> void:
	in_game = false
	for p in players.get_children():
		p.queue_free()
	menu_camera.current = true
	pause_panel.visible = false
	hud_label.visible = false
	menu_panel.visible = true
	status_label.text = message
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_paused(open: bool) -> void:
	# la partida no se detiene: con otra persona conectada el mundo sigue
	pause_panel.visible = open
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
	lines.append("WASD moverte · Ratón mirar · Shift correr · C agacharte · Espacio saltar · Esc menú")
	hud_label.text = "\n".join(lines)


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

	# menú principal
	menu_panel = _centered_panel()
	var box := menu_panel.get_child(0).get_child(0) as VBoxContainer
	var title := Label.new()
	title.text = "Pueblo Muerto"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var lede := Label.new()
	lede.text = "Registra las casas, come, bebe y aguanta otra noche. Mejor en compañía."
	lede.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lede.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lede)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Tu nombre"
	name_edit.max_length = 20
	box.add_child(name_edit)

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
	status_label.modulate = Color(1, 0.8, 0.5)
	box.add_child(status_label)

	# pausa
	pause_panel = _centered_panel()
	pause_panel.visible = false
	var pbox := pause_panel.get_child(0).get_child(0) as VBoxContainer
	var ptitle := Label.new()
	ptitle.text = "Menú"
	ptitle.add_theme_font_size_override("font_size", 36)
	ptitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pbox.add_child(ptitle)
	pbox.add_child(_button("Seguir jugando", func(): _set_paused(false)))
	pbox.add_child(_button("Salir al menú principal", _on_leave_pressed))

	# HUD
	hud_label = Label.new()
	hud_label.position = Vector2(16, 12)
	hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_label.add_theme_constant_override("outline_size", 6)
	hud_label.visible = false
	ui.add_child(hud_label)


func _centered_panel() -> CenterContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return center


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	return b
