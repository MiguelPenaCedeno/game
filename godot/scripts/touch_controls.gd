class_name TouchControls
extends Control
## Controles en pantalla para el móvil.
## - Mitad izquierda: un joystick que aparece donde pones el dedo (moverte).
## - Mitad derecha: arrastra para mirar.
## - Botones: cada uno "pulsa" una acción del juego (golpear, usar, saltar…),
##   así el resto del juego no sabe si vienes del teclado, del mando o del dedo.

const INK := Color(0.07, 0.065, 0.075)
const PAPER := Color(0.95, 0.92, 0.84)
const ACCENT := Color(0.62, 0.06, 0.04)
const FONT := preload("res://fonts/BarlowCondensed-SemiBold.ttf")
const STICK_RADIUS := 85.0
## radianes por píxel al arrastrar para mirar
const LOOK_SPEED := 0.006

## [acción, texto, centro (en 1280x720), radio, mantener]
const BUTTONS := [
	["attack", "GOLPE", Vector2(1160, 575), 66.0, true],
	["interact", "USAR", Vector2(1035, 610), 46.0, false],
	["jump", "SALTO", Vector2(1185, 435), 40.0, false],
	["crouch", "AGACH.", Vector2(1080, 480), 38.0, false],
	["next_weapon", "ARMA", Vector2(1210, 330), 32.0, false],
	["flashlight", "LUZ", Vector2(1130, 360), 30.0, false],
	["eat", "1", Vector2(430, 52), 26.0, false],
	["drink", "2", Vector2(488, 52), 26.0, false],
	["bandage", "3", Vector2(546, 52), 26.0, false],
	["throw", "4", Vector2(604, 52), 26.0, false],
	["inventory", "MOCHILA", Vector2(690, 52), 36.0, false],
	["map", "MAPA", Vector2(782, 52), 32.0, false],
	["pause", "II", Vector2(860, 52), 26.0, false],
]

var player: Node3D
## dedo -> "stick" | "look" | acción del botón
var _touches := {}
var _stick_center := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_on := false
var _run := false
var _pressed := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func active() -> bool:
	var hud := get_parent() as Control
	return Settings.touch_active() and hud.visible and not hud.is_blocking() and player != null and not player.dead


func _process(_delta: float) -> void:
	var on := active()
	if on != visible:
		visible = on
		queue_redraw()
	if not visible and (_stick_on or not _touches.is_empty()):
		_release_all()


## Las coordenadas de los botones están pensadas para 1280x720; se ajustan al tamaño real.
func _scale() -> Vector2:
	return size / Vector2(1280, 720)


func _button_at(p: Vector2) -> int:
	var sc := _scale()
	for i in BUTTONS.size():
		var b: Array = BUTTONS[i]
		var c: Vector2 = b[2] * sc
		if p.distance_to(c) < float(b[3]) * minf(sc.x, sc.y) * 1.15:
			return i
	return -1


func _input(event: InputEvent) -> void:
	if not active():
		return
	# solo se redibuja cuando cambia algo (un dedo que entra, se mueve o sale)
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		queue_redraw()
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var p := t.position
		if t.pressed:
			var bi := _button_at(p)
			if bi >= 0:
				_touches[t.index] = BUTTONS[bi][0]
				_press(BUTTONS[bi][0], true)
			elif p.x < size.x * 0.45:
				_touches[t.index] = "stick"
				_stick_on = true
				_stick_center = p
				_stick_pos = p
				# doble función: el botón de correr va pegado al joystick
			else:
				_touches[t.index] = "look"
			get_viewport().set_input_as_handled()
		elif _touches.has(t.index):
			var role: String = _touches[t.index]
			_touches.erase(t.index)
			if role == "stick":
				_stick_on = false
				_set_move(Vector2.ZERO)
			elif role != "look":
				_press(role, false)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		var role: String = _touches.get(d.index, "")
		if role == "stick":
			_stick_pos = d.position
			var v := (_stick_pos - _stick_center) / (STICK_RADIUS * minf(_scale().x, _scale().y))
			if v.length() > 1.0:
				v = v.normalized()
			_set_move(v)
			get_viewport().set_input_as_handled()
		elif role == "look":
			if player:
				player.look(d.relative * LOOK_SPEED)
			get_viewport().set_input_as_handled()


## Lleva el joystick a las acciones de moverse (con fuerza, como un stick de mando).
## Empujado del todo hacia delante, corre.
func _set_move(v: Vector2) -> void:
	_axis("move_left", "move_right", v.x)
	_axis("move_forward", "move_back", v.y)
	var run := v.y < -0.92
	if run != _run:
		_run = run
		_press("sprint", run)


func _axis(neg: String, pos: String, value: float) -> void:
	if value < -0.15:
		Input.action_press(neg, -value)
		Input.action_release(pos)
	elif value > 0.15:
		Input.action_press(pos, value)
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


## Pulsa o suelta una acción como si fuera una tecla (llega a _unhandled_input de todos).
func _press(action: String, pressed: bool) -> void:
	_pressed[action] = pressed
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _release_all() -> void:
	for role in _touches.values():
		if role != "stick" and role != "look":
			_press(role, false)
	_touches.clear()
	_stick_on = false
	_set_move(Vector2.ZERO)


func _draw() -> void:
	var sc := _scale()
	var k := minf(sc.x, sc.y)
	# joystick: base y botón
	if _stick_on:
		draw_circle(_stick_center, STICK_RADIUS * k, Color(PAPER, 0.25))
		draw_arc(_stick_center, STICK_RADIUS * k, 0, TAU, 40, Color(INK, 0.7), 3.0)
		var knob := _stick_center + (_stick_pos - _stick_center).limit_length(STICK_RADIUS * k)
		draw_circle(knob, 34.0 * k, Color(PAPER, 0.7))
		draw_arc(knob, 34.0 * k, 0, TAU, 32, INK, 3.0)
	else:
		var hint := Vector2(170, 560) * sc
		draw_arc(hint, STICK_RADIUS * k, 0, TAU, 40, Color(INK, 0.25), 2.0)
		draw_string(FONT, hint + Vector2(-38, 6) * k, "MOVERTE", HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * k), Color(INK, 0.4))
	for b in BUTTONS:
		var c: Vector2 = b[2] * sc
		var r: float = b[3] * k
		var on: bool = _pressed.get(b[0], false)
		draw_circle(c + Vector2(3, 3) * k, r, Color(INK, 0.5))
		draw_circle(c, r, Color(ACCENT, 0.85) if on else Color(PAPER, 0.72))
		draw_arc(c, r, 0, TAU, 32, INK, 3.0)
		var fs := int((22.0 if r > 40.0 else 16.0) * k)
		var w := FONT.get_string_size(b[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(FONT, c + Vector2(-w / 2, fs * 0.35), b[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PAPER if on else INK)
