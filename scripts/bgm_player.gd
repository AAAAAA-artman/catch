extends Node
## BGM 播放器：带淡入淡出地切换背景音乐。
##
## 用法：
##     bgm.play("res://audio/bgm/dream_street.mp3")   # 换曲（自动交叉淡入淡出）
##     bgm.stop()                                     # 淡出停止
##     bgm.set_library({"prologue": "res://..."})     # 用名字换曲：bgm.play_key("prologue")

signal track_changed(path: String)

@export_range(-40.0, 6.0, 0.5) var volume_db := -9.0
@export_range(0.2, 8.0, 0.1) var fade_time := 1.6
@export var bgm_enabled := true

var library := {}

@onready var _current: AudioStreamPlayer = $TrackA
@onready var _next: AudioStreamPlayer = $TrackB
var _tween: Tween
var _current_path := ""
var _cache := {}


func set_library(tracks: Dictionary) -> void:
	library = tracks


## 按名字播放（名字见 set_library 里的 key）。
func play_key(key: String) -> bool:
	if not library.has(key):
		push_warning("BgmPlayer: 没有名为 %s 的曲子" % key)
		return false
	return play(String(library[key]))


## 播放某个路径的 BGM。已经在播同一首时什么都不做（不会从头重播）。
func play(path: String) -> bool:
	if not bgm_enabled:
		return false

	if path == _current_path and _current.playing:
		return true
	var stream := _load(path)
	if stream == null:
		push_warning("BgmPlayer: 加载失败 %s" % path)
		return false
	var old := _current
	_current = _next
	_next = old
	_current.stream = stream
	_current.volume_db = -80.0
	_current.play()
	_current_path = path
	track_changed.emit(path)

	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_current, "volume_db", volume_db, fade_time)
	if _next.playing:
		_tween.tween_property(_next, "volume_db", -80.0, fade_time)
		_tween.chain().tween_callback(_next.stop)
	return true


func stop() -> void:
	_current_path = ""
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	for player in [_current, _next]:
		if player.playing:
			_tween.tween_property(player, "volume_db", -80.0, fade_time)
	_tween.chain().tween_callback(_stop_all_now)


func is_playing() -> bool:
	return _current != null and _current.playing and _current_path != ""


func current_path() -> String:
	return _current_path


func _stop_all_now() -> void:
	_current.stop()
	_next.stop()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	# BGM 一律循环
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_cache[path] = stream
	return stream
