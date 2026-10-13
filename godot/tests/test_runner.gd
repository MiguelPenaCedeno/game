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
	p.global_position = c.pos + Vector3(0, 0.2, 1.3)
	p.look_at(Vector3(c.pos.x, p.global_position.y, c.pos.z), Vector3.UP)


## Abre el mueble idx con E (registro incluido) y espera a la ventana.
func _open(p: Node, idx: int) -> bool:
	_goto_container(p, idx)
	await _wait(0.3)
	if p.interact_idx != idx:
		return false
	p._start_search()
	return await _wait_until(func(): return main.hud.is_container_open(), 5.0)


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
	check(w.get_node("Geometria").get_child_count() < 400, "el mapa está fusionado (%d mallas)" % w.get_node("Geometria").get_child_count())

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
	main.world.request_dismantle(5)
	check(main.world.containers[5].get("gone", false), "desmonto el mueble 5")
	check(await _wait_until(func(): return main.players.get_child_count() >= 2, 20.0), "se une la otra persona")
	check(await _wait_until(func(): return main.world.containers[0].empty, 15.0), "veo vacío el mueble que vació ella")
	check(await _wait_until(func():
		for c in main.world.containers:
			if c.type == "caja":
				return true
		return false, 10.0), "veo la caja que construyó ella")
	# ella cae al suelo: voy y la levanto
	var guest: Node = null
	for pl in main.players.get_children():
		if pl.name != "1":
			guest = pl
	check(await _wait_until(func(): return guest.downed, 15.0), "veo a mi compañera en el suelo")
	var me := _me()
	me.global_position = guest.global_position + Vector3(1.0, 0.2, 0)
	await _wait(0.3)
	check(me.revive_target == guest, "puedo levantarla")
	me._start_search()
	check(await _wait_until(func(): return not guest.downed, 8.0), "la levanto")
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
