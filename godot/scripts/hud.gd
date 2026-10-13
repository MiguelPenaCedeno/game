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
var cont_box: VBoxContainer
var craft_box: VBoxContainer
var craft_list: VBoxContainer
var craft_where: Label
var dismantle_btn: Button
var cont_title: Label
var cont_list: VBoxContainer
## mueble abierto (-1 si solo miras la mochila) y lo que tiene
var cont_idx := -1
var cont_loot := {}
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
	if not world.night_changed.is_connected(_on_night_changed):
		world.night_changed.connect(_on_night_changed)
	p.died.connect(_on_died)
	if not world.container_opened.is_connected(open_container):
		world.container_opened.connect(open_container)
		world.container_changed.connect(_on_container_changed)
		world.item_granted.connect(func(_i, _k, _n):
			if inventory.visible:
				_refresh_inventory.call_deferred())
	death.visible = false
	inventory.visible = false


func _on_night_changed(is_night: bool) -> void:
	if is_night:
		toast("Cae la noche. Los muertos se mueven más rápido. (F: linterna)", true)
	else:
		toast("Amanece. Día %d." % world.day_number())


func set_info(text: String) -> void:
	info_label.text = text


func is_blocking() -> bool:
	return inventory.visible or death.visible


func toggle_inventory() -> void:
	if player == null or player.dead:
		return
	if inventory.visible:
		close_panel()
		return
	cont_idx = -1
	inventory.visible = true
	_refresh_inventory()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Se abrió un mueble: mochila a la derecha, mueble a la izquierda.
func open_container(idx: int, loot: Dictionary) -> void:
	if player == null or player.dead:
		return
	cont_idx = idx
	cont_loot = loot
	inventory.visible = true
	_refresh_inventory()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_panel() -> void:
	if cont_idx >= 0:
		world.request_close.rpc_id(1, cont_idx)
	cont_idx = -1
	inventory.visible = false
	if player and not player.dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_container_open() -> bool:
	return inventory.visible and cont_idx >= 0


func _on_container_changed(idx: int, loot: Dictionary) -> void:
	if idx == cont_idx:
		cont_loot = loot
		_refresh_inventory()


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
	var main_node := get_tree().get_first_node_in_group("main")
	var to_horde: int = main_node.days_to_horde() if main_node else 99
	clock.text = world.clock_text()
	if to_horde == 0:
		clock.text += " · ¡HORDA!" if world.night or world.hour() >= 17.0 else " · horda esta noche"
	else:
		clock.text += " · horda en %d d" % to_horde
	Sfx.set_ambience(1.0 - world.daylight, clampf((30.0 - player.hp) / 30.0, 0.0, 1.0) if not player.dead else 0.0)

	slots.comida.text = str(player.inv.comida)
	slots.agua.text = str(player.inv.agua)
	slots.vendas.text = str(player.inv.vendas)
	slots.molotov.text = str(player.inv.get("molotov", 0))
	slots.comida.text = str(player.inv.comida + player.inv.get("guiso", 0))
	var w: ItemData = Items.WEAPONS[player.weapon]
	weapon_slot.text = w.name
	if w.gun:
		weapon_info.text = "%d balas" % player.inv.balas
	elif player.owned.get(player.weapon, -1) > 0:
		weapon_info.text = "%d golpes" % player.owned[player.weapon]
	else:
		weapon_info.text = "sin desgaste"

	# aviso de registrar
	prompt_panel.visible = false
	progress.visible = not player.search.is_empty()
	var riding: Node3D = player._vehicle() if player.riding != "" else null
	if riding:
		var tank: float = riding.spec().tank
		if player.seat == 0:
			prompt.text = "%s · %d km/h · gasolina %.1f/%d l · chapa %d%%   [E] Bajar  [F] Faros  [Espacio] Freno" % [
				riding.display_name(), roundi(absf(riding.speed) * 3.6), riding.fuel, roundi(tank), roundi(riding.health)]
			if riding.fuel <= 0.0:
				prompt.text = "Sin gasolina · echa un bidón con R desde fuera   [E] Bajar"
			elif riding.is_wrecked():
				prompt.text = "El motor está destrozado   [E] Bajar"
		else:
			prompt.text = "De copiloto · %d km/h   [E] Bajar" % roundi(absf(riding.speed) * 3.6)
		prompt_panel.visible = true
	elif player.downed:
		progress.visible = true
		progress.value = player.bleed_out / player.BLEED_OUT_TIME * 100.0
		prompt.text = "EN EL SUELO · %d s · espera a que te levanten" % ceili(player.bleed_out)
		prompt_panel.visible = true
	elif progress.visible:
		progress.value = player.search.t / player.search.dur * 100.0
		if player.search.has("revive"):
			prompt.text = "Levantando a %s…" % player.search.revive.display_name
		elif player.search.has("craft"):
			prompt.text = "Fabricando %s…" % player.search.craft.name.to_lower()
		elif player.search.has("repair"):
			prompt.text = "Reparando…"
		elif player.search.has("remove"):
			prompt.text = "Quitando…"
		elif player.search.has("dismantle"):
			prompt.text = "Desmontando %s…" % world.containers[player.search.dismantle].name.to_lower()
		else:
			prompt.text = "Registrando %s…" % world.containers[player.search.idx].name.to_lower()
		prompt_panel.visible = true
	elif player.struct_target >= 0 and not player.revive_target and not player.dead and world.structures.by_id.has(player.struct_target):
		var st: Dictionary = world.structures.by_id[player.struct_target]
		var info: Dictionary = world.structures.TYPES[st.type]
		var action := ""
		if st.type == "puerta" and st.hp >= info.hp:
			action = "[E] Cerrar" if st.open else "[E] Abrir"
		elif st.type == "cama":
			action = "[E] Dormir aquí (reapareces aquí)"
		elif st.hp < info.hp:
			action = "[E] Reparar (1 %s)" % Items.ITEMS[info.mat].short.to_lower()
		prompt.text = "%s %d/%d  %s  · [R] Quitar" % [info.name, st.hp, info.hp, action]
		prompt_panel.visible = true
	elif player.revive_target and not player.dead:
		prompt.text = "[E] Levantar a %s" % player.revive_target.display_name
		prompt_panel.visible = true
	elif player.vehicle_target and not player.dead:
		var v: Node3D = player.vehicle_target
		var action := "[E] Conducir" if v.driver == 0 else ("[E] Subir de copiloto" if v.passenger == 0 else "Va lleno")
		if v.is_wrecked():
			action = "Destrozado · [E] Subir" if v.driver == 0 else action
		var fuel := "gasolina %.1f l" % v.fuel
		if int(player.inv.get("gasolina", 0)) > 0:
			fuel += " · [R] Echar gasolina"
		prompt.text = "%s · %s · %s" % [v.display_name(), action, fuel]
		prompt_panel.visible = true
	elif player.interact_idx >= 0 and not player.dead:
		var c: Dictionary = world.containers[player.interact_idx]
		prompt.text = ("%s (vacío)" % c.name) if c.empty else ("[E] Registrar %s" % c.name.to_lower())
		prompt_panel.visible = true

	hurt.color.a = 0.0 if player.dead else minf(0.3, player.hurt_flash()) + (0.1 if player.hp < 25 else 0.0) + (0.15 if player.downed else 0.0)

	if is_container_open():
		# te alejaste del mueble: se cierra
		var c: Dictionary = world.containers[cont_idx]
		var to: Vector3 = c.pos - player.global_position
		to.y = 0
		if to.length() > 3.2 or player.dead:
			close_panel()


# ------------------------------------------------------------------ inventario
func _refresh_inventory() -> void:
	for c in inv_list.get_children():
		c.queue_free()
	for c in cont_list.get_children():
		c.queue_free()
	var open := cont_idx >= 0
	cont_box.visible = open

	# mochila
	var rows := []
	for k in player.owned:
		if k != "puños":
			rows.append([k, 1])
	for k in player.inv:
		if player.inv[k] > 0:
			rows.append([k, player.inv[k]])
	if rows.is_empty():
		inv_list.add_child(_note("La mochila está vacía."))
	for r in rows:
		var k: String = r[0]
		var n: int = r[1]
		if open:
			var idx := cont_idx
			inv_list.add_child(_item_row(k, n, [
				["Dejar 1", func(): player.put(idx, k, 1)],
				["Todo", func(): player.put(idx, k, n)]]))
		else:
			inv_list.add_child(_item_row(k, n, [["Soltar 1", func(): player.drop_item(k); _refresh_inventory()]]))

	# mueble
	if open:
		var c: Dictionary = world.containers[cont_idx]
		cont_title.text = c.name.to_upper()
		var can_dismantle: bool = cont_idx < world._static_count and not c.get("gone", false)
		dismantle_btn.visible = can_dismantle
		dismantle_btn.text = "Desmontar (%s)" % ("hacha o martillo" if not player.has_tool() else "%d s, hace ruido" % int(Items.CONTAINERS[c.type].dismantle_time))
		dismantle_btn.disabled = not player.has_tool()
		if cont_loot.is_empty():
			cont_list.add_child(_note("Vacío. Puedes dejar cosas aquí."))
		var idx := cont_idx
		for k in cont_loot:
			var n: int = cont_loot[k]
			cont_list.add_child(_item_row(k, n, [
				["Coger 1", func(): player.take(idx, k, 1)],
				["Todo", func(): player.take(idx, k, n)]]))

	# fabricar (solo mirando la mochila, no con un mueble abierto)
	craft_box.visible = not open
	for c in craft_list.get_children():
		c.queue_free()
	if not open:
		var here: Array[String] = player.stations()
		var names := {"manos": "a mano", "banco": "banco de trabajo", "hoguera": "hoguera"}
		var where := PackedStringArray()
		for st in here:
			where.append(names[st])
		craft_where.text = "Puedes fabricar: " + ", ".join(where)
		for rid in Items.RECIPES:
			var r: RecipeData = Items.RECIPES[rid]
			if r.station not in here:
				continue
			var ok := Items.can_craft(r, player.inv, player.owned)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var info := VBoxContainer.new()
			info.add_theme_constant_override("separation", -4)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var n := Label.new()
			n.text = r.name
			info.add_child(n)
			var ing := Label.new()
			ing.text = Items.ingredients_text(r)
			ing.add_theme_font_size_override("font_size", 15)
			ing.add_theme_color_override("font_color", Color(INK, 0.65) if ok else ACCENT)
			info.add_child(ing)
			row.add_child(info)
			var b := Button.new()
			b.text = "Colocar" if r.result.begins_with("estructura:") else "Fabricar"
			b.disabled = not ok
			b.add_theme_font_size_override("font_size", 17)
			b.pressed.connect(func():
				close_panel()
				player.start_craft(rid))
			row.add_child(b)
			craft_list.add_child(row)

	var f := Items.speed_factor(player.weight)
	inv_summary.text = "Carga: %.1f kg de %d · Velocidad: %d%%%s" % [
		player.weight, int(Items.CARRY_MAX), roundi(f * 100),
		"\nCon más de %d kg no puedes correr." % int(Items.CARRY_HEAVY) if player.weight > Items.CARRY_LIGHT else ""]


func _take_all() -> void:
	if cont_idx < 0:
		return
	# pide cada cosa calculando el peso como si ya la llevaras
	var w: float = player.weight
	for k in cont_loot.duplicate():
		var n: int = cont_loot[k]
		var fit := 0
		if Items.WEAPONS.has(k):
			fit = 1 if player.owned.has(k) or w + Items.kg(k) <= Items.CARRY_MAX + 0.001 else 0
		else:
			fit = clampi(int(floor((Items.CARRY_MAX - w) / Items.kg(k) + 0.001)), 0, n)
		if fit > 0:
			w += Items.kg(k) * fit
			world.request_take.rpc_id(1, cont_idx, k, fit)
	if w < player.weight + 0.001 and not cont_loot.is_empty():
		toast("No te cabe nada más en la mochila.", true)


func _item_row(k: String, n: int, buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_l := Label.new()
	name_l.text = Items.ITEMS[k].name + ("  ×%d" % n if n > 1 else "")
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.custom_minimum_size.x = 150
	row.add_child(name_l)
	var kg_l := Label.new()
	kg_l.text = "%.2f kg" % (Items.kg(k) * n)
	kg_l.custom_minimum_size.x = 64
	kg_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kg_l.add_theme_color_override("font_color", Color(INK, 0.6))
	row.add_child(kg_l)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.add_theme_font_size_override("font_size", 17)
		btn.pressed.connect(b[1])
		row.add_child(btn)
	return row


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(INK, 0.6))
	return l


# ------------------------------------------------------------------ muerte
func _on_died(cause: String) -> void:
	close_panel()
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
	slots.molotov = _slot(bottom, "4", "Molotov")
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
	inventory.visible = false
	center.add_child(inventory)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	inventory.add_child(outer)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	outer.add_child(cols)

	cont_box = VBoxContainer.new()
	cont_box.add_theme_constant_override("separation", 8)
	cont_box.custom_minimum_size.x = 420
	cols.add_child(cont_box)
	cont_title = Label.new()
	cont_title.add_theme_font_override("font", FONT_TITLE)
	cont_title.add_theme_font_size_override("font_size", 30)
	cont_box.add_child(cont_title)
	cont_list = VBoxContainer.new()
	cont_box.add_child(cont_list)
	var take_all := Button.new()
	take_all.text = "Coger todo lo que quepa"
	take_all.pressed.connect(_take_all)
	cont_box.add_child(take_all)
	dismantle_btn = Button.new()
	dismantle_btn.pressed.connect(func():
		var idx := cont_idx
		close_panel()
		player.start_dismantle(idx))
	cont_box.add_child(dismantle_btn)

	var inv_box := VBoxContainer.new()
	inv_box.add_theme_constant_override("separation", 8)
	inv_box.custom_minimum_size.x = 420
	cols.add_child(inv_box)
	var title := Label.new()
	title.text = "MOCHILA"
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 30)
	inv_box.add_child(title)
	var inv_scroll := ScrollContainer.new()
	inv_scroll.custom_minimum_size = Vector2(420, 380)
	inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inv_box.add_child(inv_scroll)
	inv_list = VBoxContainer.new()
	inv_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_scroll.add_child(inv_list)

	craft_box = VBoxContainer.new()
	craft_box.add_theme_constant_override("separation", 6)
	craft_box.custom_minimum_size.x = 380
	cols.add_child(craft_box)
	var ct := Label.new()
	ct.text = "FABRICAR"
	ct.add_theme_font_override("font", FONT_TITLE)
	ct.add_theme_font_size_override("font_size", 30)
	craft_box.add_child(ct)
	craft_where = Label.new()
	craft_where.add_theme_font_size_override("font_size", 15)
	craft_where.add_theme_color_override("font_color", Color(INK, 0.65))
	craft_box.add_child(craft_where)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	craft_box.add_child(scroll)
	craft_list = VBoxContainer.new()
	craft_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(craft_list)

	inv_summary = Label.new()
	inv_summary.add_theme_color_override("font_color", Color(INK, 0.75))
	outer.add_child(inv_summary)
	var close := Button.new()
	close.text = "Cerrar (Tab / E)"
	close.pressed.connect(close_panel)
	outer.add_child(close)


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
