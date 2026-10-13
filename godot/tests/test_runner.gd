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
	check(saved.get("bags", []).size() >= 2, "el guardado incluye bulto y cadáver")
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
	check(await _wait_until(func(): return main.players.get_child_count() >= 2, 20.0), "se une la otra persona")
	check(await _wait_until(func(): return main.world.containers[0].empty, 15.0), "veo vacío el mueble que vació ella")
	await _wait(3.0)
	SaveGame.delete_world()


func _test_client() -> void:
	print("== Invitada ==")
	main.ip_edit.text = "127.0.0.1"
	main._on_join_pressed()
	check(await _wait_until(func(): return _me() != null, 15.0), "me conecto y aparezco")
	check(await _wait_until(func(): return main.zombies.get_child_count() > 0, 15.0), "veo los zombis del anfitrión")
	var host: Node = main.players.get_node_or_null("1")
	check(host != null, "veo al anfitrión")
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
	await _wait(1.0)
