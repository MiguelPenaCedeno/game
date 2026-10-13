extends Node
## Diagnóstico (autoload "Diag"). Apunta en user://diagnostico.txt lo que va
## haciendo el juego (y lo guarda en el momento), para que si el móvil lo cierra
## de golpe, la próxima vez que se abra se sepa en qué estaba y en qué aparato.

const PATH := "user://diagnostico.txt"
const PREV_PATH := "user://diagnostico_anterior.txt"
## líneas con las que la última sesión terminó bien (cerrada o en segundo plano)
const CLEAN := ["== FIN ==", "== EN SEGUNDO PLANO =="]
const MAX_LINES := 400

## la sesión anterior se cerró de golpe (sin pasar por FIN)
var crashed_last_time := false
## lo que se apuntó en la sesión anterior
var previous := PackedStringArray()
## final del registro del motor de la sesión anterior (errores de Godot)
var previous_engine_log := PackedStringArray()

var _file: FileAccess
var _lines := 0
var _t0 := 0
var _beat := 0.0
var _frames := 0
var _mutex := Mutex.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_t0 = Time.get_ticks_msec()
	if FileAccess.file_exists(PATH):
		previous = FileAccess.get_file_as_string(PATH).strip_edges().split("\n")
		crashed_last_time = previous.size() > 0 and not previous[previous.size() - 1].strip_edges() in CLEAN \
			and not "--test=" in " ".join(OS.get_cmdline_user_args())
		DirAccess.rename_absolute(PATH, PREV_PATH)
	previous_engine_log = _previous_engine_log()
	_open()
	for l in device_info():
		mark(l)


func _open() -> void:
	_file = FileAccess.open(PATH, FileAccess.WRITE)
	_lines = 0


## Apunta una línea (desde cualquier hilo) y la guarda ya en el disco.
func mark(text: String) -> void:
	_mutex.lock()
	if _file:
		if _lines > MAX_LINES:
			# no crece sin fin: se empieza otra vez con la ficha del aparato
			_file.close()
			_open()
			for l in device_info():
				_write(l)
		_write(text)
	_mutex.unlock()


func _write(text: String) -> void:
	var s := (Time.get_ticks_msec() - _t0) / 1000.0
	_file.store_line("[%7.1f] %s" % [s, text])
	_file.flush()
	_lines += 1


func _process(delta: float) -> void:
	_frames += 1
	if _frames == 3:
		mark("ya dibuja (primeros fotogramas hechos)")
	# un latido cada pocos segundos: si se cierra, se ve hasta cuándo iba bien
	_beat += delta
	if _beat >= 2.0:
		_beat = 0.0
		var mem: Dictionary = OS.get_memory_info()
		mark("vivo  fps=%d  memoria=%d MB  gpu=%d MB  objetos=%d" % [
			Engine.get_frames_per_second(),
			int(OS.get_static_memory_usage() / 1048576.0),
			int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
			int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		] + ("  libre=%d MB" % int(mem.get("available", 0) / 1048576.0) if mem.get("available", -1) > 0 else ""))


func _exit_tree() -> void:
	mark("== FIN ==")
	_mutex.lock()
	_file = null
	_mutex.unlock()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			mark("== EN SEGUNDO PLANO ==")
		NOTIFICATION_APPLICATION_RESUMED:
			mark("vuelve al primer plano")
		NOTIFICATION_CRASH:
			mark("== EL MOTOR SE HA ROTO ==")


## La ficha del aparato: modelo, sistema, gráficos y ajustes.
func device_info() -> PackedStringArray:
	var v: Dictionary = Engine.get_version_info()
	var out := PackedStringArray()
	out.append("Pueblo Muerto %s  ·  Godot %s" % [ProjectSettings.get_setting("application/config/version", "?"), v.string])
	out.append("Aparato: %s  ·  %s %s  ·  %d núcleos" % [OS.get_model_name(), OS.get_name(), OS.get_version(), OS.get_processor_count()])
	out.append("Gráficos: %s  ·  %s %s  ·  driver %s" % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_vendor(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])
	out.append("Pantalla: %s  ·  ventana %s" % [DisplayServer.screen_get_size(), DisplayServer.window_get_size()])
	var s := get_node_or_null("/root/Settings")
	if s:
		out.append("Ajustes: sombras=%d  tinta=%s  hilos=%s  resolución=%d%%" % [
			s.shadows, s.ink_effect, s.threaded_loading, roundi(s.render_scale * 100)])
	return out


## El registro del motor de la vez anterior (Godot lo renombra con la fecha al arrancar).
func _previous_engine_log() -> PackedStringArray:
	var dir := DirAccess.open("user://logs")
	if dir == null:
		return PackedStringArray()
	var best := ""
	for f in dir.get_files():
		if f.ends_with(".log") and f != "godot.log" and f > best:
			best = f
	if best == "":
		return PackedStringArray()
	var lines := FileAccess.get_file_as_string("user://logs/" + best).strip_edges().split("\n")
	return lines.slice(maxi(0, lines.size() - 40))


## Texto para copiar y mandar: la ficha de ahora, lo último de la vez anterior y los errores del motor.
func report() -> String:
	var parts := PackedStringArray()
	parts.append("=== ESTE APARATO ===")
	parts.append_array(device_info())
	parts.append("")
	parts.append("=== LA VEZ ANTERIOR %s ===" % ("(se cerró de golpe)" if crashed_last_time else ""))
	parts.append_array(previous.slice(maxi(0, previous.size() - 45)))
	if not previous_engine_log.is_empty():
		parts.append("")
		parts.append("=== MOTOR (la vez anterior) ===")
		parts.append_array(previous_engine_log)
	return "\n".join(parts)
