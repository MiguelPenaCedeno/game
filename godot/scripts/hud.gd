extends Control
## Interfaz de juego: estadísticas, carga, barra de objetos, aviso para
## registrar, mensajes, inventario (Tab), minimapa y pantalla de muerte.
## Lee el estado del jugador local cada frame.

signal respawn_requested
signal leave_requested

const INK := Color(0.07, 0.065, 0.075)
const PAPER := Color(0.95, 0.92, 0.84)
const ACCENT := Color(0.62, 0.06, 0.04)
const FONT_TITLE := preload("res://fonts/SpecialElite-Regular.ttf")
const MINIMAP := preload("res://scripts/minimap.gd")

var player: Node3D
var world: Node

var bars := {}
var weight_label: Label
var moodles: Label
var clock: Label
var slots := {}
var weapon_slot: Label
var weapon_info: Label
var prompt: Label
var prompt_panel: PanelContainer
var progress: ProgressBar
var log_box: VBoxContainer
var info_label: Label
var hurt: ColorRect
var minimap: Control
var inventory: PanelContainer
var inv_list: VBoxContainer
var inv_summary: Label
var death: CenterContainer
var death_cause: Label
var death_stats: Label


func _ready() -> void:
	add_to_group("hud")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false


func bind_player(p: Node3D) -> void:
	player = p
	world = get_tree().get_first_node_in_group("world")
	minimap.player = p
	minimap.world = world
	p.message.connect(toast)
	p.died.connect(_on_died)
	death.visible = false
	inventory.visible = false


func set_info(text: String) -> void:
	info_label.text = text


func is_blocking() -> bool:
	return inventory.visible or death.visible


func toggle_inventory() -> void:
	if player == null or player.dead:
		return
	inventory.visible = not inventory.visible
	if inventory.visible:
		_refresh_inventory()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if inventory.visible else Input.MOUSE_MODE_CAPTURED


func toast(text: String, bad := false) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ACCENT if bad else INK)
	var box := PanelContainer.new()
	box.add_child(l)
	log_box.add_child(box)
	while log_box.get_child_count() > 5:
		log_box.get_child(0).free()
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(box, "modulate:a", 0.0, 1.0)
	tw.tween_callback(box.queue_free)


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	bars.hp.value = player.hp
	bars.stamina.value = player.stamina
	bars.hunger.value = player.hunger
	bars.thirst.value = player.thirst
	bars.weight.max_value = Items.CARRY_MAX
	bars.weight.value = player.weight
	weight_label.text = "%.1f / %d kg" % [player.weight, int(Items.CARRY_MAX)]
	var heavy: bool = player.weight > Items.CARRY_HEAVY
	var loaded: bool = player.weight > Items.CARRY_LIGHT
	(bars.weight.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = ACCENT if heavy else INK

	var m := PackedStringArray()
	if player.bleeding:
		m.append("Sangrando")
	if player.infected:
		m.append("Infectado")
	if heavy:
		m.append("Sobrecargado: no puedes correr")
	elif loaded:
		m.append("Cargado")
	if player.stamina < 12:
		m.append("Agotado")
	if player.hunger <= 0:
		m.append("Muerto de hambre")
	elif player.hunger < 25:
		m.append("Hambriento")
	if player.thirst <= 0:
		m.append("Deshidratado")
	elif player.thirst < 25:
		m.append("Sediento")
	moodles.text = " · ".join(m)
	moodles.visible = not m.is_empty()
	var t := int(player.alive_time)
	clock.text = "Sobrevives %d:%02d" % [t / 60, t % 60]

	slots.comida.text = str(player.inv.comida)
	slots.agua.text = str(player.inv.agua)
	slots.vendas.text = str(player.inv.vendas)
	var w: Dictionary = Items.WEAPONS[player.weapon]
	weapon_slot.text = w.name
	if w.get("gun", false):
		weapon_info.text = "%d balas" % player.inv.balas
	elif player.owned.get(player.weapon, -1) > 0:
		weapon_info.text = "%d golpes" % player.owned[player.weapon]
	else:
		weapon_info.text = "sin desgaste"

	# aviso de registrar
	prompt_panel.visible = false
	progress.visible = not player.search.is_empty()
	if progress.visible:
		progress.value = player.search.t / player.search.dur * 100.0
		prompt.text = "Registrando %s…" % world.containers[player.search.idx].name.to_lower()
		prompt_panel.visible = true
	elif player.interact_idx >= 0 and not player.dead:
		var c: Dictionary = world.containers[player.interact_idx]
		prompt.text = ("%s (vacío)" % c.name) if c.empty else ("[E] Registrar %s" % c.name.to_lower())
		prompt_panel.visible = true

	hurt.color.a = 0.0 if player.dead else minf(0.3, player.hurt_flash()) + (0.1 if player.hp < 25 else 0.0)

	if inventory.visible and Engine.get_process_frames() % 10 == 0:
		_refresh_inventory()


# ------------------------------------------------------------------ inventario
func _refresh_inventory() -> void:
	for c in inv_list.get_children():
		c.queue_free()
	var rows := []
	for k in player.owned:
		if k != "puños":
			rows.append([k, 1])
	for k in player.inv:
		if player.inv[k] > 0:
			rows.append([k, player.inv[k]])
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "La mochila está vacía. Registra muebles y maleteros con E."
		inv_list.add_child(empty)
	for r in rows:
		var k: String = r[0]
		var n: int = r[1]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_l := Label.new()
		name_l.text = Items.ITEMS[k].name + ("  ×%d" % n if n > 1 else "")
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var kg_l := Label.new()
		kg_l.text = "%.2f kg" % (Items.kg(k) * n)
		kg_l.custom_minimum_size.x = 80
		kg_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(kg_l)
		var b := Button.new()
		b.text = "Soltar 1"
		b.pressed.connect(func(): player.drop_item(k); _refresh_inventory())
		row.add_child(b)
		inv_list.add_child(row)
	var f := Items.speed_factor(player.weight)
	var where := ""
	if player.interact_idx >= 0:
		where = "\nLo que sueltes irá a: %s." % world.containers[player.interact_idx].name.to_lower()
	inv_summary.text = "Carga: %.1f kg de %d · Velocidad: %d%%%s%s" % [
		player.weight, int(Items.CARRY_MAX), roundi(f * 100),
		"\nCon más de %d kg no puedes correr." % int(Items.CARRY_HEAVY) if player.weight > Items.CARRY_LIGHT else "",
		where]


# ------------------------------------------------------------------ muerte
func _on_died(cause: String) -> void:
	inventory.visible = false
	var t := int(player.alive_time)
	death_cause.text = cause
	death_stats.text = "Sobreviviste %d:%02d · %d zombis abatidos · %d muebles registrados" % [t / 60, t % 60, player.kills, player.searched]
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(func():
		death.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)


# ------------------------------------------------------------------ construcción
func _build() -> void:
	hurt = ColorRect.new()
	hurt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hurt.color = Color(ACCENT, 0.0)
	hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hurt)

	# estadísticas arriba a la izquierda
	var stats := PanelContainer.new()
	stats.position = Vector2(16, 14)
	stats.custom_minimum_size.x = 270
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stats)
	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 4)
	stats.add_child(sbox)
	clock = Label.new()
	clock.add_theme_font_override("font", FONT_TITLE)
	clock.add_theme_font_size_override("font_size", 18)
	sbox.add_child(clock)
	bars.hp = _bar(sbox, "Salud", ACCENT)
	bars.stamina = _bar(sbox, "Energía", INK)
	bars.hunger = _bar(sbox, "Hambre", INK)
	bars.thirst = _bar(sbox, "Sed", INK)
	bars.weight = _bar(sbox, "Carga", INK)
	weight_label = Label.new()
	weight_label.add_theme_font_size_override("font_size", 16)
	weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sbox.add_child(weight_label)
	moodles = Label.new()
	moodles.add_theme_color_override("font_color", ACCENT)
	moodles.add_theme_font_size_override("font_size", 17)
	moodles.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	moodles.custom_minimum_size.x = 240
	sbox.add_child(moodles)

	# minimapa arriba a la derecha
	var map_holder := Control.new()
	map_holder.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	map_holder.offset_left = -231
	map_holder.offset_right = -21
	map_holder.offset_top = 14
	map_holder.offset_bottom = 224
	map_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map_holder)
	var shadow := ColorRect.new()
	shadow.color = INK
	shadow.position = Vector2(5, 5)
	shadow.size = Vector2(210, 210)
	map_holder.add_child(shadow)
	minimap = MINIMAP.new()
	minimap.size = Vector2(210, 210)
	map_holder.add_child(minimap)

	# barra de objetos abajo
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	slots.comida = _slot(bottom, "1", "Comida")
	slots.agua = _slot(bottom, "2", "Agua")
	slots.vendas = _slot(bottom, "3", "Vendas")
	weapon_slot = _slot(bottom, "Q", "")
	weapon_info = weapon_slot.get_parent().get_child(2)
	_slot(bottom, "Tab", "Mochila")
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 18)

	# mira y aviso en el centro
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 26)
	cross.add_theme_color_override("font_color", PAPER)
	cross.add_theme_color_override("font_outline_color", INK)
	cross.add_theme_constant_override("outline_size", 6)
	cross.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cross.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(cross)
	cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	var center_box := VBoxContainer.new()
	center_box.set_anchors_preset(Control.PRESET_CENTER)
	center_box.offset_left = -200
	center_box.offset_right = 200
	center_box.offset_top = 50
	center_box.offset_bottom = 130
	center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center_box)
	prompt_panel = PanelContainer.new()
	prompt_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center_box.add_child(prompt_panel)
	prompt = Label.new()
	prompt_panel.add_child(prompt)
	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(220, 12)
	progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_bar(progress, INK)
	center_box.add_child(progress)

	# mensajes abajo a la izquierda
	log_box = VBoxContainer.new()
	log_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	log_box.offset_left = 16
	log_box.offset_top = -120
	log_box.offset_bottom = -120
	log_box.alignment = BoxContainer.ALIGNMENT_END
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_box)

	# estado de la red bajo el minimapa
	info_label = Label.new()
	info_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info_label.offset_left = -400
	info_label.offset_right = -18
	info_label.offset_top = 234
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_label.add_theme_font_size_override("font_size", 15)
	info_label.add_theme_color_override("font_color", PAPER)
	info_label.add_theme_color_override("font_outline_color", INK)
	info_label.add_theme_constant_override("outline_size", 5)
	add_child(info_label)

	_build_inventory()
	_build_death()


func _build_inventory() -> void:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inventory = PanelContainer.new()
	inventory.custom_minimum_size = Vector2(480, 0)
	inventory.visible = false
	center.add_child(inventory)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	inventory.add_child(box)
	var title := Label.new()
	title.text = "MOCHILA"
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 34)
	box.add_child(title)
	inv_list = VBoxContainer.new()
	box.add_child(inv_list)
	inv_summary = Label.new()
	inv_summary.add_theme_color_override("font_color", Color(INK, 0.75))
	box.add_child(inv_summary)
	var close := Button.new()
	close.text = "Cerrar (Tab)"
	close.pressed.connect(toggle_inventory)
	box.add_child(close)


func _build_death() -> void:
	death = CenterContainer.new()
	death.visible = false
	add_child(death)
	death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	death.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Así es como moriste."
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", ACCENT)
	box.add_child(title)
	death_cause = Label.new()
	death_cause.add_theme_font_override("font", FONT_TITLE)
	death_cause.add_theme_font_size_override("font_size", 19)
	death_cause.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(death_cause)
	death_stats = Label.new()
	death_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(death_stats)
	var again := Button.new()
	again.text = "Intentarlo otra vez"
	again.pressed.connect(func():
		death.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		respawn_requested.emit())
	box.add_child(again)
	var leave := Button.new()
	leave.text = "Salir al menú principal"
	leave.pressed.connect(func(): leave_requested.emit())
	box.add_child(leave)


func _bar(parent: Control, label: String, fill: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = label.to_upper()
	l.custom_minimum_size.x = 70
	l.add_theme_font_size_override("font_size", 15)
	row.add_child(l)
	var b := ProgressBar.new()
	b.show_percentage = false
	b.max_value = 100
	b.custom_minimum_size = Vector2(170, 14)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_bar(b, fill)
	row.add_child(b)
	return b


func _style_bar(b: ProgressBar, fill: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 0.99, 0.95)
	bg.border_color = INK
	bg.set_border_width_all(2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.border_color = INK
	fg.set_border_width_all(2)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)


## Casilla de la barra inferior: tecla, número grande y nombre.
func _slot(parent: Control, key: String, label: String) -> Label:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.custom_minimum_size.x = 64
	panel.add_child(box)
	var k := Label.new()
	k.text = key
	k.add_theme_font_size_override("font_size", 13)
	k.add_theme_color_override("font_color", Color(INK, 0.6))
	box.add_child(k)
	var big := Label.new()
	big.add_theme_font_size_override("font_size", 24)
	box.add_child(big)
	var small := Label.new()
	small.text = label.to_upper()
	small.add_theme_font_size_override("font_size", 13)
	box.add_child(small)
	return big
