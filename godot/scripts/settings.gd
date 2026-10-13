extends Node
## Ajustes del jugador (autoload "Settings"). Se guardan en user://ajustes.cfg
## y se aplican al momento.

signal changed

const PATH := "user://ajustes.cfg"

var mouse_sensitivity := 0.0025
var invert_y := false
var fov := 65.0
var fullscreen := false
var vsync := true
## escala de resolución 3D (más bajo = más rápido)
var render_scale := 1.0
## 0 = sin sombras, 1 = bajas, 2 = altas
var shadows := 2
## grosor de los contornos de tinta
var line_width := 1.3
## intensidad de la trama en las sombras
var hatching := 0.55
## grano del papel
var grain := 0.07
var volume := 0.8
## dificultad elegida para las partidas nuevas
var difficulty := "normal"
## controles táctiles: 0 = automático (si la pantalla es táctil), 1 = siempre, 2 = nunca
var touch_controls := 0
## velocidad de la cámara con el stick derecho del mando
var pad_sensitivity := 2.6
## el filtro de cómic (tinta y papel) por encima de todo
var ink_effect := true
## construir las zonas del mapa en otro hilo (más fluido; desactivar si el móvil se cierra)
var threaded_loading := true

const KEYS := ["mouse_sensitivity", "invert_y", "fov", "fullscreen", "vsync", "render_scale",
	"shadows", "line_width", "hatching", "grain", "volume", "difficulty", "touch_controls", "pad_sensitivity",
	"ink_effect", "threaded_loading"]


func _ready() -> void:
	# en el móvil, valores más ligeros de partida
	if is_mobile():
		render_scale = 0.75
		shadows = 1
		grain = 0.05
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in KEYS:
			set(k, cfg.get_value("ajustes", k, get(k)))
	apply()


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android")


## ¿Se muestran los controles táctiles?
func touch_active() -> bool:
	if touch_controls == 1:
		return true
	if touch_controls == 2:
		return false
	return is_mobile() or DisplayServer.is_touchscreen_available()


## Lo más sencillo para la tarjeta gráfica: para móviles que se cierran solos.
func safe_mode() -> void:
	shadows = 0
	ink_effect = false
	threaded_loading = false
	render_scale = minf(render_scale, 0.6)
	apply()
	save()


func set_value(key: String, value: Variant) -> void:
	set(key, value)
	apply()
	save()


func save() -> void:
	var cfg := ConfigFile.new()
	for k in KEYS:
		cfg.set_value("ajustes", k, get(k))
	cfg.save(PATH)


func apply() -> void:
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	get_viewport().scaling_3d_scale = render_scale
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	changed.emit()
