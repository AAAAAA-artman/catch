extends Node
## 音效播放器：打字循环音 + 各种一次性音效。
##
## 文件在 audio/sfx/：
##   key_0.mp3 ~ key_7.mp3 打字击键声（从打字机素材里切出的 8 个独立击键，
##                         每次敲字随机取一个，避免机械重复）
##   accept_normal.mp3     接受普通句子
##   accept_positive.mp3   接受正面（好）句子
##   accept_negative_1.mp3 接受负面句子（压力 < 50%）
##   accept_negative_2.mp3 接受负面句子（压力 >= 50%）
##   sentence_complete.mp3 一句话输入完成（回车）
##   stage_complete.mp3    某阶段好感度满、要进剧情时
##   resist.mp3            按住 Alt 抵抗时（循环，松手停）
##   mistake.mp3           输入途中误触（打错字）
##   sentence_fail.mp3     一整句话输入失败（超时 / 打错）——只用前半段
##   game_over.mp3         游戏失败（压力或麻木满）
##   tension.mp3           剩余时间不多时的紧张背景音（循环，时间恢复或换句时停）
##
## 用法：
##     sfx.play_typing()                         # 敲一个字
##     sfx.play_accept("neutral")                # 根据句子类型播接受音
##     sfx.play_sentence_complete()
##     sfx.play_stage_complete()

signal one_shot_finished

const DIR := "res://audio/sfx/"

## 负面句子在压力超过这个比例后换用更重的音效
const PRESSURE_HEAVY := 0.5

const KEYS := {
	"accept_normal": "accept_normal.mp3",
	"accept_positive": "accept_positive.mp3",
	"accept_negative_1": "accept_negative_1.mp3",
	"accept_negative_2": "accept_negative_2.mp3",
	"sentence_complete": "sentence_complete.mp3",
	"stage_complete": "stage_complete.mp3",
	"resist": "resist.mp3",
	"mistake": "mistake.mp3",
	"sentence_fail": "sentence_fail.mp3",
	"game_over": "game_over.mp3",
	"tension": "tension.mp3",
}

@export var sfx_enabled := true
@export_range(-40.0, 6.0, 0.5) var volume_db := -6.0
@export_range(-40.0, 6.0, 0.5) var typing_volume_db := -13.0
@export_range(-40.0, 6.0, 0.5) var tension_volume_db := -16.0
## 两个打字音之间至少隔多久（秒），避免长按 / 输入法一次上屏连发爆音
@export_range(0.0, 0.2, 0.005) var typing_min_interval := 0.028
## 击键声通道数（重叠时不会互相打断）
const KEY_VOICES := 4

## 一次性音效用几个复用通道
const ONESHOT_VOICES := 6

var _cache := {}
var _key_streams: Array[AudioStream] = []
var _keys: Array[AudioStreamPlayer] = []
var _resist_player: AudioStreamPlayer
var _resisting := false
var _tension_player: AudioStreamPlayer
var _tension_on := false
var _key_index := 0
var _oneshots: Array[AudioStreamPlayer] = []
var _index := 0
var _last_typing := -99.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load_keys()
	for i in KEY_VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		player.volume_db = typing_volume_db
		add_child(player)
		_keys.append(player)

	# 抵抗音：单独的循环通道，按住时响、松手停
	_resist_player = AudioStreamPlayer.new()
	_resist_player.bus = "Master"
	_resist_player.volume_db = volume_db
	add_child(_resist_player)

	# 紧张音：时间快到时循环，恢复正常或换句时淡出
	_tension_player = AudioStreamPlayer.new()
	_tension_player.bus = "Master"
	_tension_player.volume_db = tension_volume_db
	_tension_player.volume_db = -60.0
	add_child(_tension_player)

	for i in ONESHOT_VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		player.volume_db = volume_db
		add_child(player)
		_oneshots.append(player)


# ================================================================ 打字
## 玩家敲了一个字（或输入法上屏了一个字）。
## 从 8 个击键样本里随机取一个，用 4 个通道轮转播放，所以快速连打不会互相掐断。
func play_typing() -> void:
	if not sfx_enabled or _key_streams.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_typing < typing_min_interval:
		return
	_last_typing = now
	var player := _keys[_key_index]
	_key_index = (_key_index + 1) % _keys.size()
	if player.playing:
		player.stop()
	player.stream = _key_streams[_rng.randi_range(0, _key_streams.size() - 1)]
	player.volume_db = typing_volume_db + _rng.randf_range(-2.0, 1.0)
	player.pitch_scale = _rng.randf_range(0.94, 1.06)
	player.play()


## 一次上屏了好几个字（输入法整句上屏）时，按字数连播几次。
func play_typing_burst(count: int) -> void:
	if count <= 0:
		return
	play_typing()


# ================================================================ 一次性音效
## 按句子类型播放"接受"音。pressure 是当前压力值（0~100）。
##   negative + pressure >= 50% → accept_negative_2
##   negative                  → accept_negative_1
##   positive                  → accept_positive
##   其它                       → accept_normal
func play_accept(kind: String, pressure: float = 0.0, max_pressure: float = 100.0) -> void:
	if not sfx_enabled:
		return
	var key := "accept_normal"
	match kind:
		"negative":
			var ratio := pressure / maxf(max_pressure, 1.0)
			key = "accept_negative_2" if ratio >= PRESSURE_HEAVY else "accept_negative_1"
		"positive":
			key = "accept_positive"
		_:
			key = "accept_normal"
	play(key)


## 一句话输入完成（回车确认）。
func play_sentence_complete() -> void:
	play("sentence_complete")


## 某阶段好感度满、即将进入剧情。
func play_stage_complete() -> void:
	play("stage_complete")


## 输入途中误触（打错一个字）。
func play_mistake() -> void:
	play("mistake")


## 一整句话输入失败（超时 / 打错整句重来）。
func play_sentence_fail() -> void:
	play("sentence_fail")


## 游戏失败。
func play_game_over() -> void:
	play("game_over")


## 开始抵抗：循环播放抵抗音。
func start_resist() -> void:
	if not sfx_enabled or _resisting:
		return
	var stream := _stream("resist")
	if stream == null:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_resisting = true
	_resist_player.stream = stream
	_resist_player.play()


## 结束抵抗：淡出停止。
func stop_resist() -> void:
	if not _resisting:
		return
	_resisting = false
	if _resist_player.playing:
		var tween := create_tween()
		tween.tween_property(_resist_player, "volume_db", -50.0, 0.18)
		tween.tween_callback(_resist_player.stop)


func is_resisting() -> bool:
	return _resisting


## 剩余时间紧张时调用（on = 进入紧张 / 离开紧张）。
## 内部幂等：重复传同一个值不会重播。
func set_tension(on: bool) -> void:
	if not sfx_enabled:
		return
	if on == _tension_on:
		return
	_tension_on = on
	var stream := _stream("tension")
	if stream == null:
		return
	if on:
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		if not _tension_player.playing:
			_tension_player.stream = stream
			_tension_player.play()
		var tween := create_tween()
		tween.tween_property(_tension_player, "volume_db", tension_volume_db, 0.35)
	else:
		var tween := create_tween()
		tween.tween_property(_tension_player, "volume_db", -60.0, 0.45)
		tween.tween_callback(_tension_player.stop)


func is_tension() -> bool:
	return _tension_on


## 播放任意具名音效（键见 KEYS）。
func play(key: String) -> bool:
	if not sfx_enabled:
		return false
	var stream := _stream(key)
	if stream == null:
		push_warning("SfxPlayer: 缺少音效 %s" % key)
		return false
	var player := _oneshots[_index]
	_index = (_index + 1) % _oneshots.size()
	player.stop()
	player.stream = stream
	player.play()
	return true


func stop_all() -> void:
	_resisting = false
	_tension_on = false
	_resist_player.stop()
	_tension_player.stop()
	for player in _keys:
		player.stop()
	for player in _oneshots:
		player.stop()


# ================================================================ 内部
func _load_keys() -> void:
	for i in 8:
		var path := DIR + "key_%d.mp3" % i
		if not ResourceLoader.exists(path):
			continue
		var stream: AudioStream = load(path)
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = false
		_key_streams.append(stream)


func _stream(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	if not KEYS.has(key):
		return null
	var path := DIR + String(KEYS[key])
	if not ResourceLoader.exists(path):
		_cache[key] = null
		return null
	var stream: AudioStream = load(path)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	_cache[key] = stream
	return stream
