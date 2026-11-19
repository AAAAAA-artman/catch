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

@export_range(-40.0, 6.0, 0.5) var volume_db := -4.0
@export var voice_enabled := true

## 同时最多几路（避免上一句没播完就被掐断时爆音）
const VOICES := 2

var _players: Array[AudioStreamPlayer] = []
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
	player.play()
	return true


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
