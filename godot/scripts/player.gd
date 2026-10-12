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

var pitch := -0.25

@onready var body_mesh: MeshInstance3D = $Body
@onready var name_label: Label3D = $NameLabel
@onready var pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm
@onready var camera: Camera3D = $CameraPivot/SpringArm/Camera


func _enter_tree() -> void:
	# El nodo se llama como el id de red de su dueño.
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Network.color_for(name.to_int())
	body_mesh.material_override = mat
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
	body_mesh.scale.y = 0.7 if crouching else 1.0
	body_mesh.position.y = 0.63 if crouching else 0.9
	pivot.position.y = 1.15 if crouching else 1.6
