extends Node

## 纯代码合成音效（无素材）：main.gd 只负责 play(name)
## 新增音效：在 _ready 里 _add 一条即可

var _players := {}


func _ready() -> void:
	_add("shoot", _make_bow_shot(0.15, 0.20, 520.0), -10.0)   # 弓箭式清脆破空声，音量偏低
	_add("crit", _make_bow_shot(0.20, 0.26, 700.0), -8.0)     # 暴击：音高更高更亮
	_add("hit", _make_noise_burst(0.07, 0.30, 220.0, 35.0), -12.0)
	_add("coin", _make_tone(1200.0, 0.10, 0.07), -6.0)
	_add("orb", _make_tone(1500.0, 0.08, 0.05), -8.0)
	_add("item", _make_tone(880.0, 0.18, 0.08), -6.0)
	_add("levelup", _make_tone(660.0, 0.30, 0.09), -6.0)


func play(name: String) -> void:
	if _players.has(name):
		_players[name].play()


func _add(name: String, stream: AudioStreamWAV, volume_db: float = -4.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	add_child(p)
	_players[name] = p


# 弓箭式射击音：高通破空噪声 + 弦振下滑音（参考原神的轻快弓声）
func _make_bow_shot(dur: float, vol: float, base_hz: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var last := 0.0
	for i in range(n):
		var t := float(i) / float(rate)
		var attack := minf(1.0, t * 1200.0)          # 极快起音
		var noise := randf() * 2.0 - 1.0
		var air := (noise - last) * exp(-t * 30.0) * 0.5   # 差分噪声 = 高频破空感
		last = noise
		var string_v := sin(TAU * base_hz * (1.0 + 0.4 * exp(-t * 25.0)) * t) * exp(-t * 45.0) * 0.35
		var s := (air + string_v) * attack * vol
		var v := int(clamp(s, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var s2 := AudioStreamWAV.new()
	s2.format = AudioStreamWAV.FORMAT_16_BITS
	s2.mix_rate = rate
	s2.stereo = false
	s2.data = data
	return s2


# 枪声：噪声 + 低频"砰"包络
func _make_noise_burst(dur: float, vol: float, thump_hz: float, decay: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / float(rate)
		var attack := minf(1.0, t * 150.0)
		var env := attack * exp(-t * decay)
		var noise := randf() * 2.0 - 1.0
		var thump := sin(TAU * thump_hz * (1.0 + 0.5 * exp(-t * 12.0)) * t)
		var s := (noise * 0.5 + thump * 0.8) * env * vol
		var v := int(clamp(s, -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var s2 := AudioStreamWAV.new()
	s2.format = AudioStreamWAV.FORMAT_16_BITS
	s2.mix_rate = rate
	s2.stereo = false
	s2.data = data
	return s2


func _make_tone(freq: float, dur: float, vol: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / float(rate)
		var env := 1.0 - float(i) / float(n)     # 简单衰减包络
		var v := int(sin(TAU * freq * t) * vol * env * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s
