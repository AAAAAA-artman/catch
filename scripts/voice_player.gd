extends Node
## 语音播放器：按「句子长度型 + 说话人」播放对应语音。
##
## 语音文件在 audio/voice/，命名 `{pattern}_{speaker}.ogg`：
##   pattern = short / long / long_short / short_long
##   speaker = father（bleep014，父亲）/ mother（bleep023，母亲）
##
## 用法（一般在 main.gd 抽到新句子时调用）：
##     var info := VoiceData.find(current_sentence)
##     voice_player.play(info["pattern"], "mother")

signal playback_finished

## 语音音量
@export_range(-40.0, 12.0, 0.5) var volume_db := 7.0

## 语音加速倍率（1.0 = 原速）。原始语音 6~9 秒太长，压到 2.2 倍速 ≈ 3 秒。
@export_range(1.0, 4.0, 0.05) var speed_scale := 2.2

## 最长播放时长（秒）。超过就自动停 —— 语音只是提示，不该拖住节奏。
@export_range(0.5, 10.0, 0.1) var max_seconds := 2.6
@export var voice_enabled := true

## 同时最多几路（避免上一句没播完就被掐断时爆音）
const VOICES := 2

var _players: Array[AudioStreamPlayer] = []
## 每个播放器的"停止令牌"，防止旧定时器误停新语音
var _stop_tokens := {}
var _cache := {}
var _index := 0


func _ready() -> void:
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		player.finished.connect(_on_player_finished)
		add_child(player)
		_players.append(player)


## 播放「某个长度型 + 某个说话人」的语音。返回是否真的开始播放。
func play(pattern: String, speaker: String) -> bool:
	if not voice_enabled:
		return false
	var stream := _load(pattern, speaker)
	if stream == null:
		push_warning("VoicePlayer: 缺少语音 %s" % VoiceData.voice_path(pattern, speaker))
		return false
	var player := _players[_index]
	_index = (_index + 1) % _players.size()
	player.stop()
	player.stream = stream
	player.volume_db = volume_db
	# pitch_scale 同时改变速度和音调；语音加速后更紧凑
	player.pitch_scale = speed_scale
	player.play()
	# 到点强制停（防止个别长语音拖太久）
	_schedule_stop(player)
	return true


## max_seconds 后停掉这个播放器（若还在播同一段）
func _schedule_stop(player: AudioStreamPlayer) -> void:
	var token := Time.get_ticks_msec()
	_stop_tokens[player.get_instance_id()] = token
	var timer := get_tree().create_timer(max_seconds)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(player):
			return
		var cur = _stop_tokens.get(player.get_instance_id(), -1)
		if cur != token:
			return      # 已经播了新的语音，不要误停
		player.stop()
	)


## 按句子文本播放：自动反查长度型。speaker 由调用方给（father / mother）。
func play_for_sentence(text: String, speaker: String) -> bool:
	var info := VoiceData.find(text)
	if info.is_empty():
		return false
	return play(String(info["pattern"]), speaker)


func stop_all() -> void:
	for player in _players:
		player.stop()


func is_playing() -> bool:
	for player in _players:
		if player.playing:
			return true
	return false


func _load(pattern: String, speaker: String) -> AudioStream:
	var key := "%s_%s" % [pattern, speaker]
	if _cache.has(key):
		return _cache[key]
	var stream := VoiceData.load_voice(pattern, speaker)
	_cache[key] = stream
	return stream


func _on_player_finished() -> void:
	if not is_playing():
		playback_finished.emit()
