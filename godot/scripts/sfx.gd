extends Node
## Sonidos del juego (autoload "Sfx"). Se sintetizan al arrancar con el mismo
## método que la versión web (ruido filtrado y ondas), así no hay archivos de
## audio que descargar. Más adelante se pueden cambiar por grabaciones: basta
## con poner un .wav/.ogg con el mismo nombre en res://sounds/.
##
##   Sfx.play("pick")                  # sonido de interfaz
##   Sfx.play_at("hit", posicion)      # sonido en el mundo (3D)

const RATE := 22050
const MAX_VOICES := 24

var streams := {}
var _voices: Array[Node] = []
var _wind: AudioStreamPlayer
var _crickets: AudioStreamPlayer
var _heart: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7
	_build_all()
	_wind = _loop_player("wind", -14.0)
	_crickets = _loop_player("crickets", -80.0)
	_heart = _loop_player("heartbeat", -80.0)


## Sonido sin posición (interfaz, el propio jugador).
func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var s: AudioStream = streams.get(name)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	_start(p)


## Sonido en un punto del mundo: se oye más flojo y por el lado que toca.
func play_at(name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, max_distance := 45.0) -> void:
	var s: AudioStream = streams.get(name)
	if s == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(pos) > max_distance:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.92, 1.08)
	p.max_distance = max_distance
	p.unit_size = 6.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.position = pos
	_start(p)


## Ambiente: viento de día, grillos de noche y latido con poca salud.
func set_ambience(night: float, low_health: float) -> void:
	_wind.volume_db = lerpf(-14.0, -20.0, night)
	_crickets.volume_db = linear_to_db(maxf(night * 0.35, 0.0001))
	_heart.volume_db = linear_to_db(maxf(low_health * 0.8, 0.0001))


func _start(p: Node) -> void:
	add_child(p)
	_voices.append(p)
	p.finished.connect(func():
		_voices.erase(p)
		p.queue_free())
	p.play()
	# demasiados sonidos a la vez: corta el más viejo
	while _voices.size() > MAX_VOICES:
		var old: Node = _voices.pop_front()
		old.queue_free()


func _loop_player(name: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = streams[name]
	p.volume_db = db
	add_child(p)
	p.play()
	return p


# ------------------------------------------------------------------ síntesis
func _build_all() -> void:
	# golpe sordo: ruido grave + caída de tono
	streams.hit = _mix([_noise(0.14, 900.0, 0.9), _tone("sine", 110, 50, 0.14, 0.7)])
	streams.hit_heavy = _mix([_noise(0.22, 700.0, 1.0), _tone("sine", 90, 35, 0.22, 0.9), _noise(0.05, 4000.0, 0.4)])
	streams.swing = _mix([_bandnoise(0.16, 700.0, 2200.0, 0.35)])
	streams.shot = _mix([_noise(0.45, 2600.0, 1.0), _tone("square", 140, 40, 0.18, 0.35)])
	streams.empty = _mix([_tone("square", 1800, 1500, 0.03, 0.15)])
	streams.hurt = _mix([_tone("saw", 240, 120, 0.28, 0.3), _noise(0.1, 600.0, 0.4)])
	streams.pick = _mix([_tone("sine", 620, 640, 0.08, 0.25), _delay(_tone("sine", 880, 900, 0.1, 0.25), 0.08)])
	streams.eat = _mix([_bandnoise(0.06, 800.0, 1800.0, 0.3), _delay(_bandnoise(0.06, 800.0, 1800.0, 0.3), 0.12), _delay(_bandnoise(0.06, 800.0, 1800.0, 0.3), 0.24)])
	streams.search = _mix([_bandnoise(0.5, 400.0, 1200.0, 0.18)])
	streams.step = _mix([_noise(0.07, 380.0, 0.5)])
	streams.step_soft = _mix([_noise(0.06, 260.0, 0.25)])
	streams.splat = _mix([_noise(0.18, 500.0, 0.7), _tone("sine", 70, 40, 0.18, 0.5)])
	streams.click = _mix([_tone("square", 1200, 1100, 0.015, 0.12)])
	streams.revive = _mix([_tone("sine", 440, 450, 0.12, 0.25), _delay(_tone("sine", 660, 670, 0.18, 0.25), 0.12)])
	for i in 3:
		streams["groan%d" % i] = _mix([_groan(_rng.randf_range(62, 105), _rng.randf_range(5, 9))])
	streams.wind = _loop(_bandnoise(4.0, 80.0, 500.0, 0.6, true))
	streams.crickets = _loop(_crickets_wave(3.0))
	streams.heartbeat = _loop(_mix([_tone("sine", 60, 45, 0.12, 0.9), _delay(_tone("sine", 55, 40, 0.14, 0.7), 0.28), _silence(0.95)]))
	# si alguien pone grabaciones reales en res://sounds/, se usan en lugar de las sintetizadas
	for name in streams.keys():
		for ext in [".ogg", ".wav"]:
			var path := "res://sounds/%s%s" % [name, ext]
			if ResourceLoader.exists(path):
				streams[name] = load(path)


func _silence(dur: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(dur * RATE))
	return a


## Ruido blanco filtrado (paso bajo) con caída rápida.
func _noise(dur: float, cutoff: float, vol: float, sustain := false) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var a := PackedFloat32Array()
	a.resize(n)
	var k := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	for i in n:
		y += k * (_rng.randf_range(-1.0, 1.0) - y)
		var env := 1.0 if sustain else pow(1.0 - float(i) / n, 2.0)
		a[i] = y * vol * env * 2.0
	return a


## Ruido entre dos frecuencias (paso alto + paso bajo).
func _bandnoise(dur: float, lo: float, hi: float, vol: float, sustain := false) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var a := PackedFloat32Array()
	a.resize(n)
	var kl := 1.0 - exp(-TAU * lo / RATE)
	var kh := 1.0 - exp(-TAU * hi / RATE)
	var low := 0.0
	var high := 0.0
	for i in n:
		var x := _rng.randf_range(-1.0, 1.0)
		high += kh * (x - high)
		low += kl * (high - low)
		var env := 1.0 if sustain else sin(PI * float(i) / n)
		a[i] = (high - low) * vol * env * 2.5
	return a


## Onda con barrido de frecuencia f0 -> f1.
func _tone(kind: String, f0: float, f1: float, dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var a := PackedFloat32Array()
	a.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += lerpf(f0, f1, t) / RATE
		var p := fmod(phase, 1.0)
		var v := 0.0
		match kind:
			"sine": v = sin(TAU * p)
			"square": v = 1.0 if p < 0.5 else -1.0
			"saw": v = p * 2.0 - 1.0
		a[i] = v * vol * pow(1.0 - t, 1.5) * minf(1.0, i / (RATE * 0.004))
	return a


## Gruñido de zombi: diente de sierra que baja, con vibrato, filtrado.
func _groan(f: float, vib: float) -> PackedFloat32Array:
	var dur := 1.3
	var n := int(dur * RATE)
	var a := PackedFloat32Array()
	a.resize(n)
	var phase := 0.0
	var k := 1.0 - exp(-TAU * 520.0 / RATE)
	var y := 0.0
	var y2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var freq := lerpf(f, f * 0.8, t / dur) + sin(TAU * vib * t) * 6.0
		phase += freq / RATE
		var x := fmod(phase, 1.0) * 2.0 - 1.0 + _rng.randf_range(-0.15, 0.15)
		y += k * (x - y)
		y2 += k * (y - y2)
		var env := minf(1.0, t / 0.25) * pow(maxf(0.0, 1.0 - t / dur), 1.2)
		a[i] = y2 * env * 0.8
	return a


func _crickets_wave(dur: float) -> PackedFloat32Array:
	var a := _silence(dur)
	var t := 0.1
	while t < dur - 0.3:
		var f := _rng.randf_range(4200, 5200)
		for pulse in 3:
			var start := int((t + pulse * 0.045) * RATE)
			for i in int(0.03 * RATE):
				if start + i < a.size():
					a[start + i] += sin(TAU * f * i / RATE) * 0.12 * sin(PI * i / (0.03 * RATE))
		t += _rng.randf_range(0.35, 0.8)
	return a


func _delay(a: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var out := _silence(seconds)
	out.append_array(a)
	return out


func _mix(parts: Array) -> AudioStreamWAV:
	var n := 0
	for p in parts:
		n = maxi(n, p.size())
	var a := PackedFloat32Array()
	a.resize(n)
	for p in parts:
		for i in p.size():
			a[i] += p[i]
	return _to_wav(a)


func _loop(src: Variant) -> AudioStreamWAV:
	var w: AudioStreamWAV = src if src is AudioStreamWAV else _to_wav(src)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = w.data.size() / 2
	return w


func _to_wav(a: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(a.size() * 2)
	for i in a.size():
		bytes.encode_s16(i * 2, int(clampf(a[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
