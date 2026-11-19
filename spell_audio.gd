class_name SpellAudio
extends RefCounted

## Процедурный звук магии без внешних сэмплов. Два события на заклинание:
## «сбор» в момент каста и удар снаряда. Звуки синтезируются один раз
## (свип тона + фильтрованный шум с экспоненциальным затуханием) и кэшируются.

static var _streams: Dictionary = {}

static func cast_stream(visual: String) -> AudioStreamWAV:
	return _stream("cast_" + visual)

static func impact_stream(visual: String) -> AudioStreamWAV:
	return _stream("impact_" + visual)

## Тихий циклический звук полёта: короткий фрагмент с петлёй.
static func flight_stream(visual: String) -> AudioStreamWAV:
	var wav := _stream("flight_" + visual)
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		# loop_* считаются в кадрах; без явного конца петля нулевой длины
		# и проигрыватель сразу же сообщает о завершении.
		wav.loop_end = wav.data.size() / 2
	return wav

static func _stream(key: String) -> AudioStreamWAV:
	if _streams.has(key):
		return _streams[key]
	var wav: AudioStreamWAV = null
	match key:
		"cast_fire":
			wav = _synth(0.25, 260.0, 110.0, 0.45, 16.0, 0.55)
		"cast_wind":
			wav = _synth(0.30, 500.0, 1100.0, 0.55, 10.0, 0.70)
		"cast_water":
			wav = _synth(0.18, 300.0, 180.0, 0.75, 18.0, 0.30, 25.0)
		"cast_earth":
			wav = _synth(0.28, 95.0, 45.0, 0.35, 12.0, 0.60)
		"impact_fire":
			wav = _synth(0.45, 160.0, 45.0, 0.60, 9.0, 0.50)
		"impact_wind":
			wav = _synth(0.30, 400.0, 120.0, 0.85, 12.0, 0.65)
		"impact_water":
			wav = _synth(0.35, 350.0, 140.0, 0.80, 13.0, 0.25, 30.0)
		"impact_earth":
			wav = _synth(0.40, 110.0, 38.0, 0.30, 8.0, 0.60)
		"flight_fire":
			wav = _synth(0.16, 120.0, 200.0, 0.85, 0.6, 0.55)
		"flight_wind":
			wav = _synth(0.14, 800.0, 1200.0, 0.7, 0.5, 0.75)
		"flight_water":
			wav = _synth(0.13, 300.0, 260.0, 0.8, 0.7, 0.35)
		"flight_earth":
			wav = _synth(0.18, 70.0, 60.0, 0.55, 0.6, 0.7)
	if wav == null:
		wav = _synth(0.2, 200.0, 100.0, 0.5, 12.0, 0.5)
	_streams[key] = wav
	return wav

## Свип частоты + шум с ФНЧ (smooth) и опциональным тремоло.
static func _synth(duration: float, freq_from: float, freq_to: float,
		noise_amount: float, decay: float, smooth: float,
		tremolo_hz: float = 0.0) -> AudioStreamWAV:
	var sample_rate := 22050
	var length := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(length * 2)
	# Детерминированный сид: один и тот же пресет звучит одинаково между запусками.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(duration * 1000.0) + int(freq_from * 7.0) \
		+ int(freq_to * 13.0) + int(noise_amount * 100.0)
	var prev_noise := 0.0
	var phase := 0.0
	for i in range(length):
		var t := float(i) / sample_rate
		var k := t / duration
		var env := exp(-t * decay)
		phase += lerpf(freq_from, freq_to, k) * TAU / sample_rate
		var tone := sin(phase) * env
		var raw := rng.randf_range(-1.0, 1.0)
		prev_noise = lerpf(raw, prev_noise, smooth)
		var s := tone * (1.0 - noise_amount) * 0.6 + prev_noise * env * noise_amount
		if tremolo_hz > 0.0:
			s *= 0.6 + 0.4 * sin(t * tremolo_hz * TAU)
		data.encode_s16(i * 2, clampi(int(s * 15000.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.data = data
	wav.mix_rate = sample_rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	return wav

## Позиционное проигрывание с лёгким разбросом питча, узел удаляется сам.
static func play_at(parent: Node, position: Vector3, stream: AudioStreamWAV,
		volume_db: float = -6.0, node_name: String = "SpellAudio") -> AudioStreamPlayer3D:
	if parent == null or stream == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(0.92, 1.08)
	player.finished.connect(player.queue_free)
	parent.add_child(player)
	if parent is Node3D and position != Vector3.ZERO:
		player.position = position
	player.play()
	return player
