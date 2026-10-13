extends CharacterBody3D
## Superviviente en tercera persona.
## Cada jugador controla solo su propio personaje (es su "autoridad")
## y el MultiplayerSynchronizer envía posición, giro, nombre y si va agachado.

const WALK_SPEED := 3.4
const RUN_SPEED := 6.2
const CROUCH_SPEED := 1.7
const ACCEL := 14.0
const JUMP_VELOCITY := 5.2
const GRAVITY := 16.0
const MOUSE_SENSITIVITY := 0.0025
const PITCH_MIN := -1.2
const PITCH_MAX := 0.6
const SPAWN_POINT := Vector3(0, 0.2, 4)

@export var display_name := "":
	set(value):
		display_name = value
		if is_node_ready():
			name_label.text = value

@export var crouching := false:
	set(value):
		crouching = value
		if is_node_ready():
			_apply_crouch()

const SKINS: Array[Color] = [Color(0.86, 0.66, 0.52), Color(0.68, 0.48, 0.34), Color(0.45, 0.31, 0.22), Color(0.92, 0.75, 0.62)]
const HAIRS: Array[Color] = [Color(0.18, 0.12, 0.08), Color(0.08, 0.07, 0.07), Color(0.45, 0.3, 0.16), Color(0.6, 0.5, 0.35)]

var pitch := -0.25
var _last_pos := Vector3.ZERO
var _ground_speed := 0.0

@onready var figure: HumanFigure = $Figure
@onready var name_label: Label3D = $NameLabel
@onready var pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm
@onready var camera: Camera3D = $CameraPivot/SpringArm/Camera


func _enter_tree() -> void:
	# El nodo se llama como el id de red de su dueño.
	set_multiplayer_authority(name.to_int())
	# aspecto fijo por jugador; la chaqueta lleva su color
	var id := name.to_int()
	var fig := $Figure as HumanFigure
	fig.jacket = Network.color_for(id).darkened(0.25)
	fig.skin = SKINS[absi(hash(id)) % SKINS.size()]
	fig.hair = HAIRS[absi(hash(id * 7)) % HAIRS.size()]


func _ready() -> void:
	name_label.text = display_name
	_apply_crouch()

	if is_multiplayer_authority():
		display_name = Network.player_name
		# cada uno coloca su propio personaje (el orden de llegada evita solaparse)
		position = SPAWN_POINT + Vector3((get_index() % 4) * 1.5 - 2.25, 0, 0)
		name_label.visible = false
		camera.current = true
		spring_arm.add_excluded_object(get_rid())
		pivot.rotation.x = pitch
	else:
		set_physics_process(false)
		set_process_unhandled_input(false)
	_last_pos = position


func _process(delta: float) -> void:
	# la velocidad se mide por el desplazamiento, así también anima a los remotos
	var moved := Vector2(position.x - _last_pos.x, position.z - _last_pos.z).length() / maxf(delta, 1e-4)
	_last_pos = position
	_ground_speed = lerpf(_ground_speed, minf(moved, 9.0), clampf(delta * 10.0, 0.0, 1.0))
	var airborne := is_multiplayer_authority() and not is_on_floor() and absf(velocity.y) > 1.0
	figure.animate(delta, _ground_speed, crouching, airborne)
	if is_multiplayer_authority():
		var world := get_tree().get_first_node_in_group("world")
		if world:
			world.update_roofs(global_position)


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		pitch = clampf(pitch - event.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
		pivot.rotation.x = pitch
	elif event.is_action_pressed("crouch"):
		crouching = not crouching


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if captured else Vector2.ZERO
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()

	if captured and Input.is_action_just_pressed("jump") and is_on_floor() and not crouching:
		velocity.y = JUMP_VELOCITY

	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint") and input.y < 0:
		speed = RUN_SPEED

	var target := dir * speed
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	move_and_slide()

	if position.y < -20:
		position = SPAWN_POINT + Vector3.UP * 2
		velocity = Vector3.ZERO


func _apply_crouch() -> void:
	pivot.position.y = 1.15 if crouching else 1.55
	name_label.position.y = 1.75 if crouching else 2.15
