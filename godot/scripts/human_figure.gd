class_name HumanFigure
extends Node3D
## Figura humana articulada hecha con piezas simples y animada por código
## (andar, correr, agacharse, respirar). Sirve para supervivientes y zombis
## hasta que tengamos modelos propios (.glb con esqueleto).
## Mira hacia -Z, como el resto de nodos de Godot.

const TOON := preload("res://shaders/toon.gdshader")

@export var skin := Color(0.82, 0.62, 0.48)
@export var jacket := Color(0.25, 0.36, 0.45)
@export var shirt := Color(0.75, 0.72, 0.65)
@export var pants := Color(0.2, 0.22, 0.26)
@export var hair := Color(0.2, 0.14, 0.1)
@export var shoes := Color(0.12, 0.1, 0.09)
@export var zombie := false

const HIP_HEIGHT := 0.94

var hips: Node3D
var spine: Node3D
var neck: Node3D
var shoulder_l: Node3D
var shoulder_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var hip_l: Node3D
var hip_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
## punto donde irá el arma en la mano derecha
var hand_r: Node3D

var _phase := 0.0
var _breath := 0.0
var _mats := {}
var _attack_t := 0.0
var _attack_dur := 0.4
var _weapon := ""
var _gun := false


func _ready() -> void:
	_build()


func _mat(color: Color, emission := 0.0) -> ShaderMaterial:
	var key := [color, emission]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = TOON
		m.set_shader_parameter("albedo", color)
		m.set_shader_parameter("grit", 0.12)
		m.set_shader_parameter("grit_scale", 9.0)
		m.set_shader_parameter("emission", emission)
		_mats[key] = m
	return _mats[key]


func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, scale_ := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	mi.scale = scale_
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 4
	return m


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 12
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 14
	m.rings = 8
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _build() -> void:
	hips = _joint(self, Vector3(0, HIP_HEIGHT, 0))
	# pelvis y cinturón
	_part(hips, _cyl(0.17, 0.15, 0.2), pants, Vector3(0, 0.02, 0), Vector3(1, 1, 0.72))
	_part(hips, _cyl(0.172, 0.172, 0.05), shoes, Vector3(0, 0.1, 0), Vector3(1, 1, 0.74))

	spine = _joint(hips, Vector3(0, 0.1, 0))
	# torso: camiseta debajo, chaqueta abierta encima
	_part(spine, _cyl(0.2, 0.16, 0.52), shirt, Vector3(0, 0.27, 0), Vector3(1, 1, 0.62))
	var jacket_l := _part(spine, _cyl(0.21, 0.17, 0.54), jacket, Vector3(0.075, 0.28, 0.005), Vector3(0.62, 1, 0.66))
	jacket_l.position.x = 0.085
	_part(spine, _cyl(0.21, 0.17, 0.54), jacket, Vector3(-0.085, 0.28, 0.005), Vector3(0.62, 1, 0.66))
	# cuello de la chaqueta
	_part(spine, _cyl(0.11, 0.15, 0.08), jacket, Vector3(0, 0.55, 0.01), Vector3(1, 1, 0.8))

	neck = _joint(spine, Vector3(0, 0.56, 0))
	_part(neck, _cyl(0.055, 0.06, 0.1), skin, Vector3(0, 0.04, 0))
	var head := _joint(neck, Vector3(0, 0.1, 0))
	_part(head, _sphere(0.115), skin, Vector3(0, 0.1, 0), Vector3(0.92, 1.1, 1.0))
	# mandíbula
	_part(head, _sphere(0.09), skin, Vector3(0, 0.035, -0.03), Vector3(0.95, 0.75, 1.0))
	# nariz y orejas
	_part(head, _box(Vector3(0.03, 0.05, 0.04)), skin.darkened(0.05), Vector3(0, 0.09, -0.115), Vector3.ONE, Vector3(0.25, 0, 0))
	_part(head, _sphere(0.025), skin, Vector3(0.105, 0.1, 0.0), Vector3(0.5, 1, 0.8))
	_part(head, _sphere(0.025), skin, Vector3(-0.105, 0.1, 0.0), Vector3(0.5, 1, 0.8))
	# ojos: oscuros en los vivos, rojos y brillantes en los zombis
	var eye_col := Color(0.85, 0.08, 0.05) if zombie else Color(0.08, 0.07, 0.07)
	for s in [-1.0, 1.0]:
		var eye := _part(head, _sphere(0.018), eye_col, Vector3(0.042 * s, 0.115, -0.1))
		if zombie:
			eye.material_override = _mat(eye_col, 2.5)
		# cejas
		_part(head, _box(Vector3(0.05, 0.012, 0.02)), hair, Vector3(0.045 * s, 0.15, -0.105), Vector3.ONE, Vector3(0, 0, -0.15 * s))
	# pelo: casquete con algo de volumen atrás
	if not zombie or hair.r < 0.33:
		_part(head, _sphere(0.125), hair, Vector3(0, 0.145, 0.015), Vector3(0.95, 0.75, 1.02))
		_part(head, _sphere(0.11), hair, Vector3(0, 0.1, 0.045), Vector3(0.98, 0.9, 0.85))

	# brazos
	shoulder_l = _joint(spine, Vector3(0.235, 0.49, 0))
	shoulder_r = _joint(spine, Vector3(-0.235, 0.49, 0))
	for sh in [shoulder_l, shoulder_r]:
		_part(sh, _sphere(0.075), jacket, Vector3(0, -0.01, 0))
		_part(sh, _capsule(0.065, 0.34), jacket, Vector3(0, -0.15, 0))
		var el := _joint(sh, Vector3(0, -0.3, 0))
		_part(el, _capsule(0.058, 0.3), jacket, Vector3(0, -0.12, 0))
		_part(el, _cyl(0.042, 0.04, 0.05), skin, Vector3(0, -0.27, 0))
		_part(el, _box(Vector3(0.07, 0.1, 0.045)), skin, Vector3(0, -0.33, 0))
		if sh == shoulder_l:
			elbow_l = el
		else:
			elbow_r = el
			hand_r = _joint(el, Vector3(0, -0.34, 0))

	# piernas
	hip_l = _joint(hips, Vector3(0.095, 0, 0))
	hip_r = _joint(hips, Vector3(-0.095, 0, 0))
	for hp in [hip_l, hip_r]:
		_part(hp, _capsule(0.085, 0.5), pants, Vector3(0, -0.22, 0))
		var kn := _joint(hp, Vector3(0, -0.44, 0))
		_part(kn, _capsule(0.07, 0.48), pants, Vector3(0, -0.22, 0))
		# bota
		_part(kn, _box(Vector3(0.11, 0.09, 0.25)), shoes, Vector3(0, -0.46, -0.045))
		if hp == hip_l:
			knee_l = kn
		else:
			knee_r = kn

	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Cambia el objeto que lleva en la mano derecha.
func set_weapon(kind: String) -> void:
	if kind == _weapon or hand_r == null:
		return
	_weapon = kind
	_gun = kind == "pistola"
	for c in hand_r.get_children():
		c.queue_free()
	var wood := Color(0.55, 0.42, 0.28)
	var metal := Color(0.55, 0.57, 0.6)
	match kind:
		"bate":
			_part(hand_r, _cyl(0.05, 0.025, 0.9), wood, Vector3(0, -0.4 * cos(0.6), -0.4 * sin(0.6)), Vector3.ONE, Vector3(0.6, 0, 0))
		"hacha":
			_part(hand_r, _cyl(0.025, 0.025, 0.8), Color(0.38, 0.27, 0.18), Vector3(0, -0.35 * cos(0.6), -0.35 * sin(0.6)), Vector3.ONE, Vector3(0.6, 0, 0))
			_part(hand_r, _box(Vector3(0.03, 0.14, 0.22)), metal, Vector3(0, -0.72 * cos(0.6), -0.72 * sin(0.6) - 0.06), Vector3.ONE, Vector3(0.6, 0, 0))
		"pistola":
			_part(hand_r, _box(Vector3(0.045, 0.24, 0.08)), Color(0.12, 0.12, 0.13), Vector3(0, -0.1, -0.02))
			_part(hand_r, _box(Vector3(0.04, 0.07, 0.12)), Color(0.18, 0.15, 0.13), Vector3(0, 0.0, 0.05))


func play_attack(duration: float) -> void:
	_attack_dur = maxf(duration, 0.2)
	_attack_t = _attack_dur


## speed en m/s sobre el suelo. Llamar cada frame.
func animate(delta: float, speed: float, crouching: bool, airborne := false) -> void:
	if hips == null:
		return
	var amt := clampf(speed / 3.4, 0.0, 1.9)
	var running := amt > 1.25
	_phase = fmod(_phase + delta * (2.0 + speed * 1.55), TAU * 4.0)
	_breath += delta * 1.7
	var s := sin(_phase)
	var k := clampf(delta * 12.0, 0.0, 1.0)
	var swing := minf(amt, 1.0) * (0.75 if running else 0.5)

	var hip_l_x := s * swing
	var hip_r_x := -s * swing
	var knee_l_x := -maxf(0.0, -sin(_phase - 0.5)) * (1.1 if running else 0.7) * minf(amt, 1.0)
	var knee_r_x := -maxf(0.0, sin(_phase - 0.5)) * (1.1 if running else 0.7) * minf(amt, 1.0)
	var arm_l_x := -s * swing * 0.85
	var arm_r_x := s * swing * 0.85
	var elbow_x := 0.2 + (0.9 if running else 0.25) * minf(amt, 1.0)
	var spine_x := -0.06 - (0.22 if running else 0.04) * minf(amt, 1.0)
	var hip_y := HIP_HEIGHT + absf(cos(_phase)) * 0.035 * minf(amt, 1.0) - (0.02 if amt > 0.05 else 0.0)
	var arm_spread := 0.06

	if crouching:
		hip_y = 0.62 + absf(cos(_phase)) * 0.02 * minf(amt, 1.0)
		hip_l_x = 1.05 + s * swing * 0.5
		hip_r_x = 1.05 - s * swing * 0.5
		knee_l_x = -1.7 + maxf(0.0, s) * 0.3 * minf(amt, 1.0)
		knee_r_x = -1.7 + maxf(0.0, -s) * 0.3 * minf(amt, 1.0)
		spine_x = -0.45
		arm_l_x = 0.35 - s * swing * 0.4
		arm_r_x = 0.35 + s * swing * 0.4
		elbow_x = 0.9

	if airborne:
		hip_l_x = 0.5
		hip_r_x = -0.1
		knee_l_x = -0.9
		knee_r_x = -0.4
		arm_l_x = -0.4
		arm_r_x = 0.6
		arm_spread = 0.35

	if zombie:
		# brazos al frente, encorvado, cojea de la pierna derecha
		arm_l_x = 1.35 + sin(_phase * 0.5) * 0.12
		arm_r_x = 1.2 + sin(_phase * 0.5 + 1.3) * 0.12
		elbow_x = 0.25
		spine_x = -0.3
		hip_r_x *= 0.55
		arm_spread = 0.12

	if _attack_t > 0.0:
		_attack_t -= delta
	var attacking := _attack_t > 0.0
	if _gun and attacking:
		# apuntar con las dos manos
		arm_r_x = 1.55
		arm_l_x = 1.45
		elbow_x = 0.05
	# respirar cuando está quieto
	var breath := sin(_breath) * 0.015 * (1.0 - minf(amt, 1.0))

	hips.position.y = lerpf(hips.position.y, hip_y, k)
	spine.rotation.x = lerpf(spine.rotation.x, spine_x + breath, k)
	neck.rotation.x = lerpf(neck.rotation.x, -spine_x * 0.6 + (0.25 if zombie else 0.0), k)
	neck.rotation.z = lerpf(neck.rotation.z, (0.3 if zombie else 0.0), k)
	hip_l.rotation.x = lerpf(hip_l.rotation.x, hip_l_x, k)
	hip_r.rotation.x = lerpf(hip_r.rotation.x, hip_r_x, k)
	knee_l.rotation.x = lerpf(knee_l.rotation.x, knee_l_x, k)
	knee_r.rotation.x = lerpf(knee_r.rotation.x, knee_r_x, k)
	shoulder_l.rotation.x = lerpf(shoulder_l.rotation.x, arm_l_x, k)
	shoulder_r.rotation.x = lerpf(shoulder_r.rotation.x, arm_r_x, k)
	shoulder_l.rotation.z = lerpf(shoulder_l.rotation.z, arm_spread, k)
	shoulder_r.rotation.z = lerpf(shoulder_r.rotation.z, -arm_spread, k)
	elbow_l.rotation.x = lerpf(elbow_l.rotation.x, elbow_x, k)
	elbow_r.rotation.x = lerpf(elbow_r.rotation.x, elbow_x, k)
	if attacking and not _gun:
		# golpe: levanta el brazo y lo baja de golpe
		var t := 1.0 - _attack_t / _attack_dur
		var arm := lerpf(0.4, 2.8, t / 0.3) if t < 0.3 else lerpf(2.8, 0.1, minf((t - 0.3) / 0.35, 1.0))
		shoulder_r.rotation.x = arm
		elbow_r.rotation.x = 0.35
		spine.rotation.y = lerpf(0.25, -0.3, clampf((t - 0.25) / 0.4, 0.0, 1.0))
	else:
		spine.rotation.y = lerpf(spine.rotation.y, 0.0, k)
