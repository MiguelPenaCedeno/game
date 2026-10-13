extends Node
## Pruebas automáticas del juego. Se lanzan con:
##   godot --headless --path godot -- --test=solo
##   godot --headless --path godot -- --test=host   (y en otra terminal)
##   godot --headless --path godot -- --test=client
## Salen con código 0 si todo va bien y 1 si algo falla.

var mode := ""
var failures := 0
var main: Node


func _ready() -> void:
	main = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FALLO ", what)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _wait_until(cond: Callable, timeout := 10.0) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
	return cond.call()


func _finish() -> void:
	print("RESULTADO %s: %s" % [mode, "OK" if failures == 0 else "%d fallos" % failures])
	get_tree().quit(0 if failures == 0 else 1)


func _run() -> void:
	match mode:
		"solo": await _test_solo()
		"host": await _test_host()
		"client": await _test_client()
		_:
			print("Modo de prueba desconocido: ", mode)
			failures += 1
	_finish()


func _me() -> Node:
	return main.players.get_node_or_null(str(multiplayer.get_unique_id()))


func _goto_container(p: Node, idx: int) -> void:
	var c: Dictionary = main.world.containers[idx]
	var front: Vector3 = Basis(Vector3.UP, main.world.layout.containers[idx].rot) * Vector3(0, 0, 1) if idx < main.world._static_count else Vector3(0, 0, 1)
	p.global_position = Vector3(c.pos.x, float(c.get("floor_y", 0.0)) + 0.05, c.pos.z) + front * 1.3
	p.velocity = Vector3.ZERO
	p.look_at(Vector3(c.pos.x, p.global_position.y, c.pos.z), Vector3.UP)


## Abre el mueble idx con E (registro incluido) y espera a la ventana.
func _open(p: Node, idx: int) -> bool:
	_goto_container(p, idx)
	await _wait(0.3)
	if p.interact_idx != idx:
		var c: Dictionary = main.world.containers[idx]
		print("    (mueble %d: nodo %s, en %s; yo en %s, miro el %d)" % [idx, c.node, c.pos, p.global_position, p.interact_idx])
		return false
	var at: Vector3 = p.global_position
	p._start_search()
	var ok: bool = await _wait_until(func(): return main.hud.is_container_open(), 5.0)
	if not ok:
		print("    (no se abrió: búsqueda %s, me moví %.2f m, vivo %s, hp %d)" % [p.search, p.global_position.distance_to(at), not p.dead, p.hp])
	return ok


# ------------------------------------------------------------------ solo
func _test_solo() -> void:
	print("== Partida en solitario ==")
	SaveGame.delete_world()
	main.new_game_check.button_pressed = true
	main._on_solo_pressed()
	check(await _wait_until(func(): return _me() != null), "aparece el jugador")
	check(await _wait_until(func(): return main.zombies.get_child_count() > 0, 15.0), "aparecen zombis")
	var p := _me()
	var w: Node = main.world
	check(w.containers.size() > 10, "hay muebles registrables (%d)" % w.containers.size())
	var meshes := 0
	for t in w.tiles:
		meshes += w.tiles[t].root.get_node("Geometria").get_child_count()
	check(w.tiles.size() >= 4 and meshes < 120 * w.tiles.size(), "el mapa está fusionado (%d zonas, %d mallas)" % [w.tiles.size(), meshes])

	# registrar y coger
	var idx := -1
	for i in w.containers.size():
		if w.containers[i].type == "nevera":
			idx = i
			break
	check(idx >= 0, "hay una nevera")
	check(await _open(p, idx), "se abre la ventana del mueble")
	main.hud._take_all()
	await _wait(0.3)
	check(main.hud.cont_loot.is_empty() or p.weight > 0.0, "coger todo mete cosas en la mochila")
	# dejar
	p.inv.comida += 2
	p._recalc_weight()
	var before: float = p.weight
	p.put(idx, "comida", 2)
	await _wait(0.2)
	check(int(main.hud.cont_loot.get("comida", 0)) >= 2, "dejar 2 latas en el mueble")
	check(is_equal_approx(p.weight, before - 0.8), "el peso baja al dejar")
	main.hud.close_panel()

	# peso y velocidad
	p.inv.agua = 30
	p._recalc_weight()
	check(p.weight > Items.CARRY_HEAVY, "con 30 botellas vas sobrecargado")
	check(Items.speed_factor(p.weight) < 0.8, "y más lento (%.2f)" % Items.speed_factor(p.weight))
	check(p.fit_count("hacha", 1) == 1 or p.weight + 2.2 > Items.CARRY_MAX, "el hacha solo cabe si hay sitio")

	# soltar crea un bulto
	var n_before: int = w.containers.size()
	p.drop_item("agua")
	await _wait(0.2)
	check(w.containers.size() == n_before + 1, "soltar deja un bulto en el suelo")

	# morir deja la mochila
	p.owned["bate"] = 10
	p._recalc_weight()
	p._die("prueba")
	await _wait(0.2)
	var corpse: Dictionary = w.containers[w.containers.size() - 1]
	check(corpse.corpse and corpse.loot.has("bate"), "al morir la mochila queda en el cadáver")
	check(p.inv.agua == 0 and not p.owned.has("bate"), "y te quedas sin nada")
	p.respawn()

	# guardar y cargar
	main.save_now()
	var saved := SaveGame.load_world()
	check(saved.get("dynamic", []).size() >= 2, "el guardado incluye bulto y cadáver")
	w.reset_containers()
	w.import_state(saved)
	check(w.containers.size() == n_before + 2, "al cargar vuelven los bultos")

	# combate
	var z: Node = main.zombies.get_child(0)
	z.global_position = p.global_position + Vector3(1, 0, 0)
	var hp: float = p.hp
	await _wait(3.0)
	check(p.hp < hp, "un zombi cerca te hace daño")
	z.hp = 5.0
	for i in 5:
		z.damage(3.0, Vector3.ZERO)
	check(z.dead, "el zombi muere a golpes")

	# día y noche
	w.set_time(23.0 * 60.0)
	check(w.night, "a las 23:00 es de noche")
	check(main.zombie_target() > main.ZOMBIE_COUNT, "de noche hay más zombis (%d)" % main.zombie_target())
	p.flashlight = true
	check(p._torch.visible, "la linterna se enciende")
	w.set_time(12.0 * 60.0)
	check(not w.night, "a mediodía es de día")
	check(w.clock_text().begins_with("Día 1 · 12:00"), "el reloj marca la hora (%s)" % w.clock_text())

	# sonido y onomatopeyas
	check(Sfx.streams.size() >= 18 and Sfx.streams.shot is AudioStreamWAV, "los sonidos están generados (%d)" % Sfx.streams.size())
	var words_before: int = w._fx.get_child_count()
	w.spawn_word(p.global_position, "bate")
	check(w._fx.get_child_count() == words_before + 1, "aparece una onomatopeya")

	# en solitario no se cae al suelo: se muere
	check(not p._teammate_alive(), "jugando solo no hay quien te levante")

	await _test_crafting(p, w)
	await _test_building(p, w)
	await _test_big_map(p, w)
	await _test_vehicles(p, w)
	await _test_paper_map(p, w)
	await _test_gear_and_skills(p, w)
	await _test_zombie_types(p, w)
	await _test_hunting_and_garden(p, w)
	await _test_story(p, w)
	await _test_difficulty(p, w)
	await _test_pad_and_touch(p, w)
	await _test_safe_mode(p, w)

	# pausa
	main._set_paused(true)
	check(get_tree().paused, "Esc pausa el juego en solitario")
	main._set_paused(false)
	SaveGame.delete_world()


# ------------------------------------------------------------------ red
func _test_host() -> void:
	print("== Anfitrión ==")
	SaveGame.delete_world()
	main.new_game_check.button_pressed = true
	main._on_host_pressed()
	# antes de que llegue: construyo un banco y desmonto un mueble
	await _wait(0.5)
	main.world.structures.request_place("banco", Vector3(6, 0, 10), 0.0)
	main.world.structures.request_place("puerta", Vector3(12, 0, 10), 0.0)
	await _wait(0.1)
	for sid in main.world.structures.by_id:
		if main.world.structures.by_id[sid].type == "puerta":
			main.world.structures.request_toggle(sid)
	main.world.request_dismantle(5)
	check(main.world.containers[5].get("gone", false), "desmonto el mueble 5")
	check(await _wait_until(func(): return main.players.get_child_count() >= 2, 20.0), "se une la otra persona")
	check(await _wait_until(func(): return main.world.containers[0].empty, 15.0), "veo vacío el mueble que vació ella")
	check(await _wait_until(func():
		for c in main.world.containers:
			if c.type == "caja":
				return true
		return false, 10.0), "veo la caja que construyó ella")
	var driven: Array = [null]
	check(await _wait_until(func():
		for v in main.vehicles.get_children():
			if v.driver > 1:
				driven[0] = v
				return true
		return false, 20.0), "veo que ella se sube a un coche")
	if driven[0]:
		var dv: Node3D = driven[0]
		var p0: Vector3 = dv.global_position
		check(await _wait_until(func(): return dv.global_position.distance_to(p0) > 2.0, 10.0), "y lo veo moverse (%.1f m)" % dv.global_position.distance_to(p0))
		check(await _wait_until(func(): return dv.driver == 0, 15.0), "y bajarse")
	check(await _wait_until(func(): return main.world.markers.size() > 0, 15.0), "veo la marca que puso en el mapa")
	# Fase 5: un bruto que ella ve, su mochila y la historia compartida
	var zb: Node = null
	for z in main.zombies.get_children():
		if not z.dead:
			zb = z
	if zb:
		zb.variant = "bruto"
	check(await _wait_until(func():
		for pl in main.players.get_children():
			if pl.name != "1" and pl.outfit.contains("mochila_escolar") and pl.figure.gear.has("espalda"):
				return true
		return false, 15.0), "veo la mochila que se puso")
	main.world.story.read("nota_comisaria")
	# ella cae al suelo: voy y la levanto (sin zombis alrededor que la vuelvan a tumbar)
	main._zombie_timer.stop()
	for z in main.zombies.get_children():
		z.queue_free()
	var guest: Node = null
	for pl in main.players.get_children():
		if pl.name != "1":
			guest = pl
	check(await _wait_until(func(): return guest != null and guest.downed, 15.0), "veo a mi compañera en el suelo")
	var me := _me()
	me.global_position = guest.global_position + Vector3(0, 0.2, 1.0)
	await _wait(0.5)
	check(me.revive_target == guest, "puedo levantarla")
	var start: Vector3 = me.global_position
	me._start_search()
	check(await _wait_until(func(): return not guest.downed, 8.0), "la levanto (me moví %.2f m)" % me.global_position.distance_to(start))
	check(main.world._fx != null, "el reloj sigue: %s" % main.world.clock_text())
	await _wait(2.0)
	SaveGame.delete_world()


func _test_client() -> void:
	print("== Invitada ==")
	main.ip_edit.text = "127.0.0.1"
	main._on_join_pressed()
	check(await _wait_until(func(): return _me() != null, 15.0), "me conecto y aparezco")
	check(await _wait_until(func(): return main.zombies.get_child_count() > 0, 15.0), "veo los zombis del anfitrión")
	var host: Node = main.players.get_node_or_null("1")
	check(host != null, "veo al anfitrión")
	var banco_ok := false
	for sid in main.world.structures.by_id:
		if main.world.structures.by_id[sid].type == "banco":
			banco_ok = true
	check(banco_ok, "veo el banco que ya había construido")
	var door_open := false
	for sid in main.world.structures.by_id:
		var st: Dictionary = main.world.structures.by_id[sid]
		if st.type == "puerta" and st.open:
			door_open = true
	check(door_open, "y la puerta que dejó abierta")
	check(main.world.containers[5].get("gone", false), "y el mueble que ya había desmontado")
	main.world.structures.request_place.rpc_id(1, "caja", Vector3(8, 0, 10), 0.0)
	var p := _me()
	check(await _open(p, 0), "abro un mueble")
	await _wait(0.3)
	var loot: Dictionary = main.hud.cont_loot.duplicate()
	main.hud._take_all()
	await _wait(0.5)
	# vaciarlo del todo dejando sitio
	p.inv = {"comida": 0, "agua": 0, "vendas": 0, "balas": 0}
	p._recalc_weight()
	main.hud._take_all()
	await _wait(0.5)
	check(main.hud.cont_loot.is_empty(), "lo vacío (tenía %s)" % str(loot))
	main.hud.close_panel()
	# conducir un coche del anfitrión
	check(await _wait_until(func(): return main.vehicles.get_child_count() > 0, 10.0), "veo los coches")
	var v := _nearest_vehicle(p.global_position)
	main.world.ensure_loaded([v.global_position])
	p.global_position = v.global_transform * Vector3(-2.0, 0.2, 0.0)
	p.look_at(v.global_position + Vector3.UP * 0.2, Vector3.UP)
	await _wait(0.4)
	check(p.vehicle_target == v, "me acerco a un coche")
	p._start_search()
	check(await _wait_until(func(): return p.riding == String(v.name), 4.0), "me subo al volante")
	check(v.is_multiplayer_authority(), "y el coche me hace caso a mí")
	v.fuel = maxf(v.fuel, 5.0)
	var start: Vector3 = v.global_position
	await _drive(2.0)
	check(v.global_position.distance_to(start) > 4.0, "conduzco (%.1f m)" % v.global_position.distance_to(start))
	Input.action_press("jump")
	await _wait_until(func(): return absf(v.speed) < 1.0, 4.0)
	Input.action_release("jump")
	await _wait(1.0)
	p.leave_vehicle()
	check(await _wait_until(func(): return v.driver == 0 and not v.is_multiplayer_authority(), 4.0), "me bajo y el coche vuelve al anfitrión")
	main.world.request_marker.rpc_id(1, Vector2(30, 30), 2, "Invitada", Color.RED)
	check(await _wait_until(func(): return main.world.markers.size() > 0, 5.0), "marco un sitio en el mapa")
	p.inv["mochila_escolar"] = 1
	p.equip("mochila_escolar")
	check(await _wait_until(func():
		for z in main.zombies.get_children():
			if z.variant == "bruto" and z.figure.scale.x > 1.2:
				return true
		return false, 15.0), "veo un zombi bruto")
	check(await _wait_until(func(): return main.world.story.stage >= 1, 15.0), "y la historia avanza para los dos")
	# me tumban: caigo al suelo (no muero) porque el anfitrión sigue en pie
	for z in main.zombies.get_children():
		z.set_process(false)
	p.take_hit(500.0, p.global_position + Vector3(1, 0, 0))
	check(p.downed and not p.dead, "con 0 de salud caigo al suelo en vez de morir")
	check(await _wait_until(func(): return not p.downed, 15.0), "mi compañero me levanta")
	check(p.hp > 0 and not p.dead, "vuelvo con algo de salud (%d)" % p.hp)
	await _wait(1.0)


# ------------------------------------------------------------------ fabricación (Fase 2)
func _wait_search(p: Node) -> void:
	await _wait_until(func(): return p.search.is_empty(), 10.0)


func _test_crafting(p: Node, w: Node) -> void:
	print("-- fabricación --")
	# que los zombis no molesten
	for z in main.zombies.get_children():
		z.set_physics_process(false)
		z.global_position = Vector3(60, 0, 60)
	p.global_position = Vector3(0, 0.2, 4)
	p.rotation.y = 0.0
	p.hp = 100.0
	p.inv = {"comida": 0, "agua": 0, "vendas": 0, "balas": 0}
	p.owned = {"puños": -1}
	p.weapon = "puños"
	p._recalc_weight()
	check(Items.RECIPES.size() >= 12, "hay recetas (%d)" % Items.RECIPES.size())

	# a mano: vendas de trapos
	p.inv.trapos = 4
	p.start_craft("vendas_trapos")
	await _wait_search(p)
	check(p.inv.vendas == 1 and p.inv.trapos == 2, "vendas de trapos (vendas %d, trapos %d)" % [p.inv.vendas, p.inv.trapos])

	# sin banco no se puede hacer un bate con clavos
	p.owned["bate"] = 30
	p.inv.clavos = 20
	p.start_craft("bate_clavos")
	check(p.search.is_empty(), "sin banco de trabajo no se fabrica el bate con clavos")

	# colocar un banco
	p.inv.tablones = 12
	p._recalc_weight()
	p.start_craft("banco")
	check(not p.placing.is_empty(), "entra en modo colocar")
	await _wait(0.3)
	check(p.placing.ok, "el sitio está libre")
	p._confirm_placing()
	check(await _wait_until(func(): return w.structures.by_id.size() == 1, 3.0), "el banco aparece en el mundo")
	check(p.inv.tablones == 8 and p.inv.clavos == 10, "cuesta 4 tablones y 10 clavos")
	check("banco" in p.stations(), "estoy junto al banco")

	# bate con clavos y reparar
	p.start_craft("bate_clavos")
	await _wait_search(p)
	check(p.owned.has("bate_clavos") and not p.owned.has("bate"), "fabrico el bate con clavos (gasta el bate)")
	p.weapon = "bate_clavos"
	p.owned.bate_clavos = 5
	p.inv.cinta = 1
	p.inv.chatarra = 1
	p.start_craft("reparar")
	await _wait_search(p)
	check(p.owned.bate_clavos > 5, "reparar le devuelve golpes (%d)" % p.owned.bate_clavos)

	# caja de almacenaje
	p.rotation.y = PI / 2
	await _wait(0.2)
	var n_cont: int = w.containers.size()
	p.inv.clavos = 8
	p.start_craft("caja")
	await _wait(0.3)
	p._confirm_placing()
	check(await _wait_until(func(): return w.containers.size() == n_cont + 1, 3.0), "la caja es un contenedor más")
	var caja_idx: int = w.containers.size() - 1
	check(w.containers[caja_idx].type == "caja", "de tipo caja")
	p.inv.comida = 3
	p.put(caja_idx, "comida", 3)
	await _wait(0.2)
	check(int(w.containers[caja_idx].loot.get("comida", 0)) == 3, "guardo 3 latas en la caja")

	# guardado: estructuras y caja con su contenido
	main.save_now()
	var saved := SaveGame.load_world()
	w.reset_containers()
	check(w.structures.by_id.is_empty(), "al reiniciar no quedan estructuras")
	w.import_state(saved)
	check(w.structures.by_id.size() == 2, "al cargar vuelven el banco y la caja")
	var caja_ok := false
	for c in w.containers:
		if c.type == "caja" and int(c.loot.get("comida", 0)) == 3:
			caja_ok = true
	check(caja_ok, "y la caja conserva lo que tenía")

	# hoguera y guiso
	p.inv.trapos = 2
	p.rotation.y = PI
	await _wait(0.2)
	p.start_craft("hoguera")
	await _wait(0.3)
	p._confirm_placing()
	await _wait(0.3)
	check("hoguera" in p.stations(), "hay hoguera cerca")
	p.inv.comida = 2
	p.inv.agua = 1
	p.start_craft("guiso")
	await _wait_search(p)
	check(p.inv.get("guiso", 0) == 2, "cocino 2 guisos")
	p.hunger = 20.0
	p.use_item("comida")
	check(p.hunger >= 84.0, "el guiso llena mucho (hambre %d)" % p.hunger)

	# desmontar un armario
	var idx := -1
	for i in w._static_count:
		if w.containers[i].type == "armario" and not w.containers[i].get("gone", false):
			idx = i
			break
	p.owned["martillo"] = 80
	var bags_before: int = w.containers.size()
	p.start_dismantle(idx)
	check(not p.search.is_empty(), "empiezo a desmontar con el martillo")
	await _wait_search(p)
	await _wait(0.3)
	check(w.containers[idx].get("gone", false), "el armario desaparece")
	var restos: Dictionary = w.containers[w.containers.size() - 1]
	check(w.containers.size() == bags_before + 1 and int(restos.loot.get("tablones", 0)) >= 3, "deja tablones en el suelo (%s)" % str(restos.loot))
	check(p.owned.martillo < 80, "el martillo se desgasta")

	# molotov
	p.inv.molotov = 1
	p._throw_molotov()
	check(p.inv.molotov == 0, "lanzo el molotov")
	var z: Node = main.zombies.get_child(1)
	var land: Vector3 = p.global_position + Vector3(0, 0, 8)
	z.global_position = land
	w.request_fire(p.global_position, land, 0.1)
	check(await _wait_until(func(): return z.dead, 8.0), "el fuego mata al zombi")


# ------------------------------------------------------------------ mapa grande (Fase 4)
func _test_big_map(p: Node, w: Node) -> void:
	print("-- mapa grande --")
	var lay: WorldLayout = w.layout
	check(lay.places.size() >= 12, "hay lugares con nombre (%d)" % lay.places.size())
	var gone := -1
	for i in w._static_count:
		if w.containers[i].get("gone", false):
			gone = i
	# irse lejos: se construye lo de allí (en otro hilo) y se quita lo del centro
	var far := Vector3(200, 0.3, -12)
	var ft := WorldLayout.tile_of(far.x, far.z)
	for z in main.zombies.get_children():
		z.queue_free()
	p.global_position = far
	check(await _wait_until(func(): return w.tiles.has(ft), 15.0), "al llegar a la gasolinera se construye su zona")
	check(not w.tiles.has(Vector2i(3, 3)) and w.containers[0].node == null, "y se quita la del centro del pueblo")
	var bidon := -1
	for i in w._static_count:
		if w.containers[i].type == "bidon" and w.containers[i].pos.distance_to(far) < 30.0:
			bidon = i
	check(bidon >= 0 and w.containers[bidon].node != null, "hay bidones de gasolina en la gasolinera")
	check(await _wait_until(func(): return w.nav_ready_at(far), 10.0), "la zona nueva tiene navegación para los zombis")
	# como el relleno de zombis: si las zonas de alrededor aún no tienen navegación, se reintenta
	var spawned: Node = null
	for i in 20:
		spawned = main._spawn_zombie(far)
		if spawned:
			break
		await _wait(0.5)
	check(spawned != null, "aparecen zombis alrededor (%s)" % (str(spawned.global_position) if spawned else "-"))
	# volver: lo desmontado sigue desmontado
	p.global_position = Vector3(0, 0.2, 4)
	check(await _wait_until(func(): return w.containers[0].node != null, 15.0), "al volver, el centro se construye otra vez")
	if gone >= 0:
		await _wait_until(func(): return w.containers[gone].node != null, 10.0)
		var gn: StaticBody3D = w.containers[gone].node
		check(gn != null and not gn.visible and gn.collision_layer == 0, "y lo desmontado sigue sin estar")
	# tiempos de construcción
	var worst := 0.0
	for t in [Vector2i(3, 3), Vector2i(6, 4), Vector2i(1, 1)]:
		var t0 := Time.get_ticks_usec()
		var n: Node3D = w.helper.build(t)
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		n.free()
	print("    (la zona más cara tarda %.0f ms en construirse)" % worst)

	# casa de dos plantas
	var house: Dictionary = {}
	for h in lay.houses:
		if h.floors == 2:
			house = h
			break
	check(not house.is_empty(), "hay casas de dos plantas")
	var hc := Vector3(house.center.x, 0.2, house.center.y)
	w.ensure_loaded([hc])
	var xf := Transform3D(Basis(Vector3.UP, house.yaw), Vector3(house.center.x, 0, house.center.y))
	var z_mid: float = house.d / 2 - 1.0 + TileBuilder.STAIR_RUN / TileBuilder.STAIR_STEPS - TileBuilder.STAIR_RUN / 2
	var mid: Vector3 = xf * Vector3(house.stairs_x, 0, z_mid)
	await get_tree().physics_frame
	var hit: Dictionary = w.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(mid + Vector3.UP * 2.5, mid + Vector3.DOWN, 1))
	check(not hit.is_empty() and hit.position.y > 0.8 and hit.position.y < 2.2, "la escalera tiene rampa (%.2f m)" % (hit.position.y if hit else -1.0))
	var up := -1
	for i in w._static_count:
		var c: Dictionary = w.containers[i]
		if c.floor_y > 0.0 and (house.rect as Rect2).has_point(Vector2(c.pos.x, c.pos.z)):
			up = i
	check(up >= 0, "hay muebles en el piso de arriba")
	if up >= 0:
		var c: Dictionary = w.containers[up]
		var front: Vector3 = Basis(Vector3.UP, lay.containers[up].rot) * Vector3(0, 0, 1)
		var stand: Vector3 = c.pos + front * 1.2
		stand.y = WorldLayout.WALL_H + 0.05
		check(w.container_index_near(stand, -front) == up, "arriba se puede registrar")
		stand.y = 0.05
		check(w.container_index_near(stand, -front) != up, "desde abajo no")
	w.update_roofs(hc)
	check(w._roof_state.get("upper") != null, "al entrar abajo se oculta el piso de arriba")
	w.update_roofs(hc + Vector3.UP * WorldLayout.WALL_H)
	check(w._roof_state.get("upper") == null and w._roof_state.get("roof") != null, "y arriba solo el tejado")

	# antibióticos
	p.infected = true
	p.inv["antibioticos"] = 1
	p.use_item("vendas")
	check(not p.infected and p.inv.antibioticos == 0, "los antibióticos curan la infección")
	p.global_position = Vector3(0, 0.2, 4)


# ------------------------------------------------------------------ vehículos (Fase 4)
func _nearest_vehicle(pos: Vector3) -> Node3D:
	var best: Node3D = null
	for v in main.vehicles.get_children():
		if best == null or v.global_position.distance_to(pos) < best.global_position.distance_to(pos):
			best = v
	return best


func _drive(seconds: float, action := "move_forward") -> void:
	Input.action_press(action)
	await _wait(seconds)
	Input.action_release(action)


func _test_vehicles(p: Node, w: Node) -> void:
	print("-- vehículos --")
	check(main.vehicles.get_child_count() == w.layout.vehicles.size(), "hay vehículos que arrancan (%d)" % main.vehicles.get_child_count())
	var v := _nearest_vehicle(Vector3(0, 0, 20))
	w.ensure_loaded([v.global_position])
	p.global_position = v.global_transform * Vector3(-2.0, 0.2, 0.0)
	p.look_at(v.global_position + Vector3.UP * 0.2, Vector3.UP)
	await _wait(0.3)
	check(p.vehicle_target == v, "me acerco a un %s" % v.display_name().to_lower())
	v.fuel = 10.0
	p._start_search()
	check(await _wait_until(func(): return p.riding == String(v.name), 3.0), "me subo al volante")
	check(v.driver == 1 and v.is_multiplayer_authority(), "conduzco yo")
	var start: Vector3 = v.global_position
	check(main.gameplay_input(), "los controles van al personaje")
	await _drive(2.0)
	var moved: float = v.global_position.distance_to(start)
	check(moved > 5.0, "acelero y avanzo (%.1f m, %d km/h)" % [moved, roundi(absf(v.speed) * 3.6)])
	check(v.fuel < 10.0, "gasta gasolina (%.2f l)" % v.fuel)
	check(p.global_position.distance_to(v.global_position) < 2.0, "voy dentro")
	await get_tree().physics_frame
	check(p.spring_arm.get_hit_length() > 4.0, "la cámara se aleja para ver el coche (%.1f m)" % p.spring_arm.get_hit_length())
	check(p.noise > 15.0, "el motor hace ruido (%.0f m)" % p.noise)
	# atropellar
	var z: Node = null
	for zz in main.zombies.get_children():
		if not zz.dead:
			z = zz
	if z == null:
		z = main._add_zombie(v.global_position + Vector3(30, 0, 0), 0.0)
		await _wait(0.1)
	z.set_physics_process(false)
	var fwd: Vector3 = -v.global_transform.basis.z
	z.global_position = v.global_position + fwd * 7.0
	var hp_before: float = z.hp
	await _drive(1.2)
	check(z.dead or z.hp < hp_before, "atropello a un zombi")
	# frenar y bajar
	Input.action_press("jump")
	await _wait_until(func(): return absf(v.speed) < 1.0, 4.0)
	Input.action_release("jump")
	p.leave_vehicle()
	await _wait(0.3)
	check(p.riding == "" and v.driver == 0, "me bajo")
	check(not p.get_node("Collision").disabled, "y vuelvo a chocar con las cosas")
	# gasolina
	p.inv["gasolina"] = 1
	var before: float = v.fuel
	p.refuel(v)
	await _wait(0.1)
	check(is_equal_approx(v.fuel, before + v.CAN_LITERS) and p.inv.gasolina == 0, "echo un bidón de gasolina (%.1f -> %.1f l)" % [before, v.fuel])
	# guardado
	main.save_now()
	var saved := SaveGame.load_world()
	var found := false
	for d in saved.get("vehicles", []):
		if (d.pos as Vector3).distance_to(v.global_position) < 1.0 and is_equal_approx(d.fuel, v.fuel):
			found = true
	check(found, "el coche se guarda donde lo dejé y con su gasolina")


# ------------------------------------------------------------------ mapa de papel (Fase 4)
func _test_paper_map(p: Node, w: Node) -> void:
	print("-- mapa de papel --")
	await _wait(0.6)
	var seen := 0
	for b in p.explored:
		seen += b
	check(seen > 10, "lo que he recorrido queda explorado (%d cuadros)" % seen)
	main.hud.toggle_map()
	check(main.hud.paper_map.visible and main.hud.paper_map._base != null, "M abre el mapa de papel")
	await _wait(0.2)
	var before: Array = w.markers.keys()
	main.hud.paper_map._place(Vector2(p.global_position.x + 10, p.global_position.z))
	check(await _wait_until(func(): return w.markers.size() == before.size() + 1, 3.0), "pongo una marca")
	var id := -1
	for k in w.markers:
		if k not in before:
			id = k
	check(w._marker_nodes.has(id), "y se ve en el mundo")
	main.save_now()
	var saved := SaveGame.load_world()
	check(saved.get("markers", []).size() == before.size() + 1, "las marcas se guardan")
	var ch := SaveGame.load_character(Network.world_id, Network.player_name)
	check((ch.get("explored", PackedByteArray()) as PackedByteArray).size() == PaperMap.CELLS * PaperMap.CELLS, "y lo explorado también")
	main.hud.paper_map._remove_near(main.hud.paper_map.world_to_screen(w.markers[id].pos))
	check(await _wait_until(func(): return not w.markers.has(id), 3.0), "clic derecho la quita")
	main.hud.close_map()
	check(not main.hud.paper_map.visible, "y se cierra")


# ------------------------------------------------------------------ Fase 5
func _test_gear_and_skills(p: Node, w: Node) -> void:
	print("-- ropa y habilidades --")
	p.global_position = Vector3(0, 0.2, 4)
	var base: float = p.carry_max()
	p.inv["mochila_montana"] = 1
	p.inv["chaleco_policia"] = 1
	p.inv["casco_moto"] = 1
	for k in ["mochila_montana", "chaleco_policia", "casco_moto"]:
		p.equip(k)
	check(is_equal_approx(p.carry_max(), base + 10.0), "la mochila de montaña da 10 kg más (%d kg)" % int(p.carry_max()))
	check(p.armor() > 0.6, "el chaleco y el casco protegen (%d%%)" % roundi(p.armor() * 100))
	check(p.outfit.contains("espalda:mochila_montana") and p.figure.gear.has("espalda"), "y se ven puestos (%s)" % p.outfit)
	p.hp = 100.0
	p.take_hit(20.0, p.global_position + Vector3(1, 0, 0))
	check(p.hp > 88.0, "un mordisco hace mucho menos daño (%d de salud)" % p.hp)
	p.unequip("espalda")
	check(is_equal_approx(p.carry_max(), base) and p.inv.mochila_montana == 1, "quitarse la mochila la devuelve a la mochila")
	p.equip("mochila_montana")
	# habilidades
	var lvl: int = p.skill_level("combate")
	p.add_xp("combate", 25.0)
	check(p.skill_level("combate") > lvl, "el combate sube de nivel con la experiencia")
	check(p.skills_text().contains("Combate %d" % p.skill_level("combate")), "se ve en la mochila (%s)" % p.skills_text())
	p.save_state()
	var ch := SaveGame.load_character(Network.world_id, Network.player_name)
	check(ch.get("equipped", {}).has("torso") and float(ch.get("skills", {}).get("combate", 0.0)) >= 25.0, "la ropa y las habilidades se guardan")


func _test_zombie_types(p: Node, w: Node) -> void:
	print("-- tipos de zombi --")
	for z in main.zombies.get_children():
		z.queue_free()
	await _wait(0.1)
	var made := {}
	for v in ["bruto", "corredor", "policia", "griton"]:
		var z: Node = main.ZOMBIE_SCENE.instantiate()
		z.name = "Prueba_" + v
		z.variant = v
		z.position = p.global_position + Vector3(30 + made.size() * 3, 0.1, 0)
		z.net_pos = z.position
		main.zombies.add_child(z, true)
		made[v] = z
	await _wait(0.2)
	check(made.bruto.hp >= 15.0 and made.bruto.figure.scale.x > 1.2, "el bruto es grande y aguanta mucho (%d)" % made.bruto.hp)
	check(made.corredor.speed > 2.0, "el corredor es rápido (%.1f)" % made.corredor.speed)
	check(made.policia.figure.gear.has("torso"), "el policía lleva chaleco")
	var hp0: float = made.policia.hp
	made.policia.damage(1.0, Vector3.ZERO, "bate")
	check(made.policia.hp > hp0 - 1.0, "y encaja menos los golpes")
	var cop := 0
	for i in 200:
		if main.pick_variant(w.story.place_pos("Comisaría")) == "policia":
			cop += 1
	check(cop > 60, "en la comisaría casi todos son policías (%d/200)" % cop)
	# el gritón avisa a los demás
	var g: Node = made.griton
	var other: Node = made.corredor
	for z in made.values():
		z.set_physics_process(false)
	g.global_position = p.global_position + Vector3(0, 0, -8)
	g.look_at(p.global_position, Vector3.UP)
	g.state = "wander"
	other.global_position = p.global_position + Vector3(30, 0, 0)
	other.state = "wander"
	p.crouching = false
	g._sense()
	check(other.state == "chase" and other.target_player == p, "el gritón grita y los de alrededor vienen")
	for z in main.zombies.get_children():
		z.queue_free()


func _test_hunting_and_garden(p: Node, w: Node) -> void:
	print("-- caza y huerto --")
	var farm: Vector3 = w.story.place_pos("Granja Vieja")
	var spot := farm + Vector3(30, 0, 30)
	p.global_position = spot + Vector3.UP * 0.2
	w.ensure_loaded([spot])
	var deer: Node = null
	for i in 5:
		deer = main.spawn_animal(spot, "ciervo", Vector2(8.0, 14.0))
		if deer:
			break
	check(deer != null, "aparece un ciervo en el campo")
	if deer:
		await _wait(0.6)
		check(deer.state == "flee", "huye al verte")
		var bags: int = w.containers.size()
		deer.damage(99.0, Vector3.ZERO, "pistola")
		await _wait(0.3)
		var meat: Dictionary = w.containers[w.containers.size() - 1]
		check(deer.dead and w.containers.size() == bags + 1 and int(meat.loot.get("carne_cruda", 0)) >= 3, "abatido deja carne (%s)" % str(meat.loot))
	# asar en la hoguera
	w.structures.request_place("hoguera", p.global_position + Vector3(2, -0.2, 0), 0.0)
	await _wait(0.2)
	p.inv["carne_cruda"] = 1
	p.start_craft("carne_asada")
	await _wait_search(p)
	check(int(p.inv.get("carne_asada", 0)) == 1, "la carne se asa en la hoguera")
	# huerto
	w.structures.request_place("huerto", p.global_position + Vector3(0, -0.2, 3), 0.0)
	await _wait(0.2)
	var sid := -1
	for k in w.structures.by_id:
		if w.structures.by_id[k].type == "huerto":
			sid = k
	check(sid >= 0, "coloco un huerto")
	p.inv["semillas"] = 1
	p.inv["agua"] = 2
	p._use_garden(sid)
	await _wait(0.2)
	check(w.structures.crop_stage(sid) == 1 and p.inv.semillas == 0, "planto las semillas")
	p._use_garden(sid)
	await _wait(0.2)
	check(w.structures.crop_watered(sid), "lo riego")
	w.set_time(w.game_minutes + 1300.0)
	await _wait(1.5)
	p._use_garden(sid)
	await _wait(0.2)
	w.set_time(w.game_minutes + 800.0)
	await _wait(1.5)
	check(w.structures.crop_stage(sid) == 4, "regado cada día, madura")
	var veg: int = int(p.inv.get("verduras", 0))
	p._use_garden(sid)
	check(await _wait_until(func(): return int(p.inv.get("verduras", 0)) > veg, 3.0), "cosecho verduras (%d)" % int(p.inv.get("verduras", 0)))
	main.save_now()
	var saved := SaveGame.load_world()
	var crop_saved := false
	for e in saved.structures:
		if e.type == "huerto" and e.has("crop"):
			crop_saved = true
	check(crop_saved, "el huerto se guarda")


func _test_story(p: Node, w: Node) -> void:
	print("-- historia --")
	var story: Node = w.story
	story.reset()
	story.start_new()
	await _wait(0.1)
	check(story.stage == 0 and main.hud.objective.text.begins_with("Objetivo:"), "hay un objetivo: %s" % story.objective_text())
	# la nota del sargento está en el armero de la comisaría
	var idx := -1
	for i in w.layout.story_loot:
		if "nota_comisaria" in w.layout.story_loot[i]:
			idx = i
	check(idx >= 0, "la comisaría guarda una nota")
	w.containers[idx].erase("rolled")
	w.containers[idx].erase("gone")
	w.ensure_loaded([w.containers[idx].pos])
	p.inv = {"comida": 0, "agua": 0, "vendas": 0, "balas": 0}
	p._recalc_weight()
	check(await _open(p, idx), "abro el armero de la comisaría")
	check(main.hud.cont_loot.has("nota_comisaria"), "y ahí está la nota")
	p.take(idx, "nota_comisaria", 1)
	check(await _wait_until(func(): return main.hud.note_panel.visible, 3.0), "al cogerla se lee")
	check(await _wait_until(func(): return story.stage == 1, 3.0), "y el objetivo avanza: %s" % story.objective_text())
	main.hud.close_note()
	main.hud.close_panel()
	story.read("nota_control")
	story.event("bateria")
	await _wait(0.2)
	check(story.stage == 3, "con la orden y la batería toca ir a la radio")
	# radio
	var radio: Vector3 = story.radio_pos()
	check(radio != Vector3.INF, "el control militar tiene radio")
	w.ensure_loaded([radio])
	p.global_position = radio + Vector3(1.2, 0.2, 1.2)
	p.inv["bateria"] = 1
	await _wait(0.2)
	check(p.near_special() == "radio", "me acerco a la radio")
	p._use_radio()
	check(await _wait_until(func(): return story.stage == 4, 3.0), "la radio da el día del rescate (%d)" % story.rescue_day)
	main.hud.close_note()
	# noche del rescate en la Granja Vieja con una hoguera
	var farm: Vector3 = story.place_pos("Granja Vieja")
	w.ensure_loaded([farm])
	p.global_position = farm + Vector3(4, 0.2, 6)
	w.structures.request_place("hoguera", farm + Vector3(2, 0, 4), 0.0)
	w.set_time((story.rescue_day - 1) * 1440.0 + 22.0 * 60.0)
	check(await _wait_until(func(): return story.stage == 5, 5.0), "de noche, con la hoguera, empieza el rescate")
	for z in main.zombies.get_children():
		z.queue_free()
	story._rescue_t = 1.0
	check(await _wait_until(func(): return story.stage == 6 and story.heli != null, 5.0), "llega el helicóptero")
	story._heli_land(true)
	p.global_position = story.landing_pos() + Vector3(3, 0.2, 0)
	await _wait(0.2)
	check(p.near_special() == "helicoptero", "puedo subir")
	p._start_search()
	check(await _wait_until(func(): return story.stage == 7, 3.0), "¡rescatados!")
	check(main.hud.note_panel.visible and main.hud.note_title.text.contains("RESCATADOS"), "y sale el final")
	main.hud.close_note()
	main.save_now()
	check(SaveGame.load_world().get("story", {}).get("stage", 0) == 7, "la historia se guarda")


# ------------------------------------------------------------------ Fase 6
func _test_difficulty(p: Node, w: Node) -> void:
	print("-- dificultad --")
	w.set_time(12.0 * 60.0)
	var normal_target: int = main.zombie_target()
	w.set_difficulty("facil")
	check(main.zombie_target() < normal_target and main.horde_every() == 9, "en fácil hay menos zombis y hordas cada 9 noches (%d)" % main.zombie_target())
	var found_easy := 0
	var found_hard := 0
	for i in 300:
		found_easy += Items.roll_loot("nevera", w.diff("loot")).size()
	w.set_difficulty("pesadilla")
	check(main.zombie_target() > normal_target and main.horde_every() == 4, "en pesadilla hay más y hordas cada 4 (%d)" % main.zombie_target())
	for i in 300:
		found_hard += Items.roll_loot("nevera", w.diff("loot")).size()
	check(found_easy > found_hard * 1.3, "y el botín cambia (%d frente a %d)" % [found_easy, found_hard])
	main.save_now()
	check(SaveGame.load_world().get("difficulty", "") == "pesadilla", "la dificultad se guarda con la partida")
	w.set_difficulty("normal")


func _test_safe_mode(p: Node, w: Node) -> void:
	print("-- modo seguro e informe --")
	Diag.mark("prueba del informe")
	var rep: String = Diag.report()
	check("ESTE APARATO" in rep and "Gráficos:" in rep, "el informe dice qué aparato y qué gráficos hay")
	check("prueba del informe" in FileAccess.get_file_as_string(Diag.PATH), "lo que pasa se apunta en el disco al momento")
	var keep := {}
	for k in Settings.KEYS:
		keep[k] = Settings.get(k)
	Settings.safe_mode()
	check(Settings.shadows == 0 and not Settings.threaded_loading and not main._ink_quad.visible,
		"el modo seguro quita sombras, filtro de cómic e hilos")
	# sin hilos el mapa se sigue construyendo al moverse
	var back: Vector3 = p.global_position
	var far := Vector3(-15.5, 0.3, 210)
	var ft := WorldLayout.tile_of(far.x, far.z)
	for z in main.zombies.get_children():
		z.queue_free()
	p.global_position = far
	var threads := [false]
	var ok := await _wait_until(func():
		if w._task != -1:
			threads[0] = true
		return w.tiles.has(ft) and w.nav_ready_at(far), 15.0)
	check(ok and not threads[0], "sin hilos se construye la zona y su navegación")
	for k in keep:
		Settings.set(k, keep[k])
	Settings.apply()
	Settings.save()
	check(main._ink_quad.visible, "y al volver a los ajustes de antes vuelve la tinta")
	p.global_position = back
	await _wait(0.5)


func _joy_axis(axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	main.hud.touch._input(ev)


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = rel
	main.hud.touch._input(ev)


func _test_pad_and_touch(p: Node, w: Node) -> void:
	print("-- mando y táctil --")
	for z in main.zombies.get_children():
		z.queue_free()
	p.global_position = Vector3(0, 0.2, 4)
	p.rotation.y = 0.0
	w.ensure_loaded([p.global_position])
	await _wait(0.3)
	# mando: stick izquierdo para andar, derecho para mirar
	_joy_axis(1, -1.0)
	var start: Vector3 = p.global_position
	await get_tree().process_frame
	check(main.pad_mode, "al tocar el mando se cambia a modo mando")
	await _wait(0.6)
	_joy_axis(1, 0.0)
	check(p.global_position.distance_to(start) > 1.0, "el stick izquierdo te mueve (%.1f m)" % p.global_position.distance_to(start))
	var yaw: float = p.rotation.y
	_joy_axis(2, 1.0)
	await _wait(0.4)
	_joy_axis(2, 0.0)
	check(absf(angle_difference(yaw, p.rotation.y)) > 0.3, "el stick derecho gira la cámara")
	main.hud.toggle_inventory()
	await _wait(0.1)
	var focused: Control = main.get_viewport().gui_get_focus_owner()
	check(focused != null and main.hud.inventory.is_ancestor_of(focused), "con el mando, la mochila se navega con foco")
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	b.pressed = true
	Input.parse_input_event(b)
	await _wait(0.1)
	b = b.duplicate()
	b.pressed = false
	Input.parse_input_event(b)
	check(not main.hud.inventory.visible, "B cierra la mochila")
	# táctil
	var old_touch: int = Settings.touch_controls
	Settings.touch_controls = 1
	main.pad_mode = false
	await _wait(0.1)
	check(main.hud.touch.active() and main.gameplay_input(), "los controles táctiles se activan")
	var sz: Vector2 = main.hud.touch.size
	start = p.global_position
	_touch(0, Vector2(sz.x * 0.15, sz.y * 0.7), true)
	_drag(0, Vector2(sz.x * 0.15, sz.y * 0.7 - 90.0), Vector2(0, -90))
	check(Input.get_action_strength("move_forward") > 0.6, "el joystick de la izquierda empuja hacia delante")
	await _wait(0.6)
	_touch(0, Vector2(sz.x * 0.15, sz.y * 0.7 - 90.0), false)
	check(p.global_position.distance_to(start) > 1.0 and Input.get_action_strength("move_forward") == 0.0, "y al soltar paras (%.1f m)" % p.global_position.distance_to(start))
	yaw = p.rotation.y
	_touch(1, Vector2(sz.x * 0.7, sz.y * 0.4), true)
	_drag(1, Vector2(sz.x * 0.7 + 120, sz.y * 0.4), Vector2(120, 0))
	_touch(1, Vector2(sz.x * 0.7 + 120, sz.y * 0.4), false)
	check(absf(angle_difference(yaw, p.rotation.y)) > 0.3, "arrastrar a la derecha gira la cámara")
	var attacks: int = p.attack_count
	p._attack_cd = 0.0
	p.stamina = 100.0
	var golpe: Vector2 = TouchControls.BUTTONS[0][2] * main.hud.touch._scale()
	_touch(2, golpe, true)
	await _wait(0.05)
	_touch(2, golpe, false)
	check(p.attack_count > attacks, "el botón GOLPE golpea")
	var mapa: Vector2 = TouchControls.BUTTONS[11][2] * main.hud.touch._scale()
	_touch(3, mapa, true)
	_touch(3, mapa, false)
	await _wait(0.1)
	check(main.hud.paper_map.visible, "y el botón MAPA abre el mapa")
	main.hud.close_map()
	Settings.touch_controls = old_touch
	check(load("res://shaders/ink_post_mobile.gdshader") != null and load("res://shaders/ink_post_simple.gdshader") != null, "hay tinta para el móvil y para OpenGL")


# ------------------------------------------------------------------ construcción (Fase 3)
func _place(p: Node, rid: String) -> int:
	var before: Array = main.world.structures.by_id.keys()
	p.start_craft(rid)
	await _wait(0.25)
	if p.placing.is_empty() or not p.placing.ok:
		print("    (no se pudo colocar %s)" % rid)
		p._cancel_placing()
		return -1
	p._confirm_placing()
	await _wait(0.2)
	for sid in main.world.structures.by_id:
		if sid not in before:
			return sid
	return -1


func _test_building(p: Node, w: Node) -> void:
	print("-- construcción --")
	var st: Node = w.structures
	p.global_position = Vector3(-2, 0.2, 30)
	p.rotation.y = 0.0
	p.inv = {"comida": 0, "agua": 0, "vendas": 0, "balas": 0, "tablones": 40, "clavos": 80, "cuerda": 5, "chatarra": 20, "trapos": 6}
	p.owned = {"puños": -1, "martillo": 80}
	p._recalc_weight()

	# barricada delante: un zombi al otro lado que me persigue la golpea
	var bid: int = await _place(p, "barricada")
	check(bid >= 0 and st.by_id[bid].type == "barricada", "coloco una barricada")
	var bpos: Vector3 = st.by_id[bid].pos
	var z: Node = null
	for zz in main.zombies.get_children():
		if not zz.dead:
			z = zz
			break
	z.set_physics_process(true)
	z.global_position = bpos + Vector3(0, 0.1, -2.5)
	z.state = "chase"
	z.target_player = p
	z.target_pos = p.global_position
	z.memory = 30.0
	var full: int = st.max_hp(bid)
	check(await _wait_until(func(): return not st.by_id.has(bid) or st.by_id[bid].hp < full, 12.0), "el zombi golpea la barricada")
	z.set_physics_process(false)
	z.global_position = Vector3(60, 0, 60)
	if st.by_id.has(bid):
		var hp_before: int = st.by_id[bid].hp
		var planks: int = p.inv.tablones
		p.global_position = bpos + Vector3(0, 0.2, 1.6)
		p.look_at(Vector3(bpos.x, p.global_position.y, bpos.z), Vector3.UP)
		await _wait(0.2)
		check(p.struct_target == bid, "miro la barricada")
		p._use_structure(bid)
		await _wait_search(p)
		check(st.by_id[bid].hp > hp_before and p.inv.tablones == planks - 1, "la reparo con un tablón (%d -> %d)" % [hp_before, st.by_id[bid].hp])
		# derribo: deja restos
		var n_cont: int = w.containers.size()
		st.damage(bid, 9999)
		await _wait(0.2)
		check(not st.by_id.has(bid), "si pierde toda la vida, cae")
		check(w.containers.size() == n_cont + 1, "y deja restos en el suelo")

	# puerta
	p.global_position = Vector3(10, 0.2, 30)
	p.rotation.y = 0.0
	st.request_place("banco", p.global_position + Vector3(-2.5, -0.2, 1.0), 0.0)
	await _wait(0.2)
	var did: int = await _place(p, "puerta")
	check(did >= 0, "coloco una puerta")
	if did >= 0:
		p.global_position = st.by_id[did].pos + Vector3(0, 0.2, 1.6)
		p.look_at(st.by_id[did].pos + Vector3(0, 0.2, 0), Vector3.UP)
		await _wait(0.2)
		p._use_structure(did)
		await _wait(0.2)
		check(st.by_id[did].open and st.by_id[did].node.get_node("HojaColision").disabled, "se abre con E y deja pasar")
		p._use_structure(did)
		await _wait(0.2)
		check(not st.by_id[did].open, "y se vuelve a cerrar")

	# muros que encajan cada metro
	p.global_position = Vector3(20, 0.2, 30)
	p.rotation.y = 0.0
	st.request_place("banco", p.global_position + Vector3(-2.5, -0.2, 1.0), 0.0)
	await _wait(0.2)
	var wid: int = await _place(p, "muro_madera")
	check(wid >= 0, "coloco un muro de madera")
	if wid >= 0:
		var wp: Vector3 = st.by_id[wid].pos
		check(is_equal_approx(fmod(absf(wp.x), 1.0), 0.0) and is_equal_approx(fmod(absf(wp.z), 1.0), 0.0), "encaja en la rejilla de 1 m (%s)" % str(wp))
		# quitarlo devuelve la mitad
		var n2: int = w.containers.size()
		st.request_remove(wid)
		await _wait(0.2)
		check(not st.by_id.has(wid) and w.containers.size() == n2 + 1, "al quitarlo devuelve material")

	# cama: punto de reaparición
	p.global_position = Vector3(30, 0.2, 30)
	p.rotation.y = 0.0
	await _wait(0.2)
	var cid: int = await _place(p, "cama")
	check(cid >= 0, "coloco una cama")
	if cid >= 0:
		p._use_structure(cid)
		check(p.spawn_point != Vector3.INF, "duermo en ella")
		p._die("prueba")
		p.respawn()
		check(p.global_position.distance_to(st.by_id[cid].pos) < 3.0, "al morir reaparezco junto a la cama")

	# al morir se quedó todo en el cadáver: material nuevo
	p.inv = {"comida": 0, "agua": 0, "vendas": 0, "balas": 0, "tablones": 20, "clavos": 40, "cuerda": 4}
	p.owned = {"puños": -1, "martillo": 80}
	p._recalc_weight()
	p.global_position = Vector3(40, 0.2, 30)
	p.rotation.y = 0.0
	await _wait(0.2)

	# pinchos: hieren y gastan
	st.request_place("pinchos", Vector3(44, 0, 34), 0.0)
	await _wait(0.1)
	var spikes := -1
	for sid in st.by_id:
		if st.by_id[sid].type == "pinchos":
			spikes = sid
	var victim: Node = null
	for zz in main.zombies.get_children():
		if not zz.dead and not zz.horde:
			victim = zz
			break
	victim.global_position = Vector3(44, 0.1, 34)
	var zhp: float = victim.hp
	await _wait(1.6)
	check(victim.dead or victim.hp < zhp, "los pinchos hieren al zombi que los pisa")
	check(not st.by_id.has(spikes) or st.by_id[spikes].hp < st.max_hp(spikes), "y se desgastan")
	victim.global_position = Vector3(60, 0, 60)

	# guardar la vida y el estado de las piezas
	var pid: int = await _place(p, "empalizada")
	check(pid >= 0, "coloco una empalizada")
	if pid >= 0:
		st.damage(pid, 50)
		main.save_now()
		var saved := SaveGame.load_world()
		w.reset_containers()
		w.import_state(saved)
		var found := false
		for sid in st.by_id:
			if st.by_id[sid].type == "empalizada" and st.by_id[sid].hp == st.max_hp(sid) - 50:
				found = true
		check(found, "la vida de las piezas se guarda")

	# horda
	check(main.days_to_horde() == 6, "el día 1 faltan 6 días para la horda")
	var before: int = main.zombies.get_child_count()
	main.start_horde()
	await _wait(0.2)
	var hordes: Array = main.zombies.get_children().filter(func(zz): return zz.horde)
	check(hordes.size() >= 14, "llega una horda (%d zombis)" % hordes.size())
	var base: Vector3 = main._base_position()
	var start := {}
	for hz in hordes:
		start[hz] = hz.global_position
	await _wait(4.0)
	# cada zombi por separado: uno que se queda atascado o cae no tapa a los demás
	var closer := 0
	var alive := 0
	var odd := ""
	for hz in hordes:
		if not is_instance_valid(hz):
			continue
		alive += 1
		var p0: Vector3 = start[hz]
		if hz.global_position.distance_to(base) < p0.distance_to(base) - 1.0:
			closer += 1
		elif odd == "":
			odd = "%s -> %s" % [p0.snapped(Vector3.ONE * 0.1), hz.global_position.snapped(Vector3.ONE * 0.1)]
	check(alive > 0 and closer * 3 >= alive * 2, "y avanza hacia la base (%d de %d se acercan%s)" % [
		closer, alive, "; uno no: " + odd if odd != "" else ""])
	for hz in hordes:
		if is_instance_valid(hz):
			hz.queue_free()
