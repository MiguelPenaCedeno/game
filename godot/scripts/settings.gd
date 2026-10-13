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

const KEYS := ["mouse_sensitivity", "invert_y", "fov", "fullscreen", "vsync", "render_scale",
	"shadows", "line_width", "hatching", "grain", "volume"]


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in KEYS:
			set(k, cfg.get_value("ajustes", k, get(k)))
	apply()


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
