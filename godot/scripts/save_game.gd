class_name SaveGame
extends RefCounted
## Guardado en la carpeta de usuario de Godot (user://). En Windows es
## %APPDATA%/Godot/app_userdata/Pueblo Muerto/
##
## - El anfitrión guarda el MUNDO: qué hay en cada mueble, bultos y mochilas
##   de cadáveres. Lleva un identificador (world_id).
## - Cada jugador guarda su PERSONAJE en su propio equipo, ligado a ese
##   world_id y a su nombre: así al volver a unirte recuperas tu mochila.

const VERSION := 1
const WORLD_PATH := "user://partida.save"


static func has_world() -> bool:
	return FileAccess.file_exists(WORLD_PATH)


static func save_world(data: Dictionary) -> void:
	data.version = VERSION
	_write(WORLD_PATH, data)


static func load_world() -> Dictionary:
	var d := _read(WORLD_PATH)
	if d.get("version", 0) != VERSION:
		return {}
	return d


static func delete_world() -> void:
	if has_world():
		DirAccess.remove_absolute(WORLD_PATH)


static func save_character(world_id: String, player_name: String, data: Dictionary) -> void:
	if world_id.is_empty():
		return
	DirAccess.make_dir_recursive_absolute("user://personajes")
	data.version = VERSION
	_write(_char_path(world_id, player_name), data)


static func load_character(world_id: String, player_name: String) -> Dictionary:
	if world_id.is_empty():
		return {}
	var d := _read(_char_path(world_id, player_name))
	if d.get("version", 0) != VERSION:
		return {}
	return d


static func new_world_id() -> String:
	return "%08x%08x" % [randi(), Time.get_ticks_usec() & 0xffffffff]


static func _char_path(world_id: String, player_name: String) -> String:
	return "user://personajes/%s_%s.save" % [world_id, player_name.validate_filename()]


static func _write(path: String, data: Dictionary) -> void:
	# primero a un temporal: si el juego se cierra a medias no se corrompe la partida
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("No se pudo guardar en %s" % path)
		return
	f.store_string(var_to_str(data))
	f.close()
	DirAccess.rename_absolute(tmp, path)


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v = str_to_var(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}
