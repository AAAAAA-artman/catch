extends Node
## 环境音层。
##
## 分两类：
##
## 【持续层】音量由游戏数值实时驱动
##   1) 切菜声（chopping.mp3）—— 厨房里的日常底噪
##        · 只在第一阶段播放，**压力越大越明显**
##   2) 高音耳鸣（tinnitus.mp3）—— 主观性耳鸣
##        · 全程都在，**麻木上升时逐渐显现**
##
## 【偶发层】随机间隔响一下，不循环、不持续
##   3) 水滴（dripping.mp3）—— 第一、二阶段，偶尔一滴
##   4) 飙车声（racing.mp3）—— 第一、二阶段，远远一辆车过去
##
## 持续层用循环 + 音量平滑；偶发层用 one_shot 单次播放，
## 播完就停，等下一个随机间隔再响。

const CHOPPING_PATH := "res://audio/ambient/chopping.mp3"
const TINNITUS_PATH := "res://audio/ambient/tinnitus.mp3"
const DRIPPING_PATH := "res://audio/ambient/dripping.mp3"
const RACING_PATH := "res://audio/ambient/racing.mp3"

## ---- 切菜声 ----
## 一开始就"清楚能听见"（不是若有若无），压力上升后变得更快更重。
const CHOP_MIN_DB := -13.0
const CHOP_MAX_DB := -4.0

## ---- 耳鸣 ----
const TIN_MIN_DB := -48.0
const TIN_MAX_DB := -9.0

## ---- 偶发：水滴 ----
## 响起时的音量（很轻，只是"屋里有水声"）
const DRIP_DB := -24.0
## 随机间隔（秒）
const DRIP_GAP_MIN := 8.0
const DRIP_GAP_MAX := 22.0

## ---- 偶发：飙车声 ----
## 偶尔"呼"地冲过去一次，声音很大（近似正常音乐音量），
## 间隔约一分钟 —— 是突然的惊吓，不是背景底噪。
const RACE_DB := -3.0
const RACE_GAP_MIN := 55.0
const RACE_GAP_MAX := 75.0

## 持续层音量平滑速度
const FADE_SPEED := 1.6

var _chopping: AudioStreamPlayer
var _tinnitus: AudioStreamPlayer
var _dripping: AudioStreamPlayer
var _racing: AudioStreamPlayer

var _chop_target := CHOP_MIN_DB
var _tin_target := TIN_MIN_DB
var _active := false

## 偶发音的倒计时
var _drip_countdown := 0.0
var _race_countdown := 0.0
## 只有第一、二阶段才允许偶发
var _street_ok := false

## 触发计数（调试 / 测试用）
var _drip_fired := 0
var _race_fired := 0


func _ready() -> void:
	_chopping = _make_player("Chopping", CHOPPING_PATH, true)
	_tinnitus = _make_player("Tinnitus", TINNITUS_PATH, true)
	_dripping = _make_player("Dripping", DRIPPING_PATH, false)
	_racing = _make_player("Racing", RACING_PATH, false)
	if _chopping != null:
		_chopping.volume_db = CHOP_MIN_DB
	if _tinnitus != null:
		_tinnitus.volume_db = TIN_MIN_DB
	_reset_timers()


## loop_audio = true 时强制循环（持续层用）；false 时单次播放（偶发层用）
func _make_player(node_name: String, path: String, loop_audio: bool) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		push_warning("Ambient: 找不到 %s" % path)
		return null
	var stream: AudioStream = load(path)
	if stream == null:
		return null
	if loop_audio:
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		elif stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	else:
		# 偶发音：确保不循环
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = false
		elif stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = false

	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = -60.0
	player.autoplay = false
	add_child(player)
	return player


func _reset_timers() -> void:
	_drip_countdown = randf_range(DRIP_GAP_MIN, DRIP_GAP_MAX)
	_race_countdown = randf_range(RACE_GAP_MIN, RACE_GAP_MAX)


## 每帧由 main.gd 调用
##   stage      当前剧情阶段（1/2/3）
##   pressure   压力 0~100
##   numbness   麻木 0~100
##   in_game    是否在对局中（标题页要停）
func update_state(stage: int, pressure: float, numbness: float, in_game: bool) -> void:
	var want_chopping := in_game and stage <= 1
	var want_tinnitus := in_game

	# ---- 切菜声：第一阶段 + 压力驱动 ----
	if _chopping != null:
		if want_chopping:
			if not _chopping.playing:
				_chopping.play()
			_chop_target = lerpf(CHOP_MIN_DB, CHOP_MAX_DB,
				clampf(pressure / 100.0, 0.0, 1.0))
		else:
			_chop_target = -60.0
			if _chopping.playing and _chopping.volume_db < -44.0:
				_chopping.stop()

	# ---- 耳鸣：全程循环 + 麻木驱动 ----
	if _tinnitus != null:
		if want_tinnitus:
			if not _tinnitus.playing:
				_tinnitus.play()
			_tin_target = lerpf(TIN_MIN_DB, TIN_MAX_DB,
				clampf(numbness / 100.0, 0.0, 1.0))
		else:
			_tin_target = -60.0
			if _tinnitus.playing and _tinnitus.volume_db < -44.0:
				_tinnitus.stop()

	# ---- 偶发层：第一、二阶段允许 ----
	_street_ok = in_game and stage <= 2
	_active = in_game


func _process(delta: float) -> void:
	# 持续层音量平滑
	var t := clampf(delta * FADE_SPEED, 0.0, 1.0)
	if _chopping != null and _chopping.playing:
		_chopping.volume_db = lerpf(_chopping.volume_db, _chop_target, t)
	if _tinnitus != null and _tinnitus.playing:
		_tinnitus.volume_db = lerpf(_tinnitus.volume_db, _tin_target, t)

	# 偶发层倒计时
	if not _active or not _street_ok:
		return

	_drip_countdown -= delta
	if _drip_countdown <= 0.0:
		_reset_drip()
		_play_once(_dripping, DRIP_DB)
		_drip_fired += 1

	_race_countdown -= delta
	if _race_countdown <= 0.0:
		_reset_race()
		_play_once(_racing, RACE_DB)
		_race_fired += 1


## 重置水滴的随机间隔
func _reset_drip() -> void:
	_drip_countdown = randf_range(DRIP_GAP_MIN, DRIP_GAP_MAX)


## 重置飙车声的随机间隔
func _reset_race() -> void:
	_race_countdown = randf_range(RACE_GAP_MIN, RACE_GAP_MAX)


## 单次播放（不循环，播完自然停）
func _play_once(player: AudioStreamPlayer, db: float) -> void:
	if player == null or player.stream == null:
		return
	player.stop()
	player.volume_db = db
	player.play()


## 立刻停掉所有环境音（结算 / 重开时用）
func stop_all() -> void:
	if _chopping != null:
		_chopping.stop()
		_chopping.volume_db = CHOP_MIN_DB
	if _tinnitus != null:
		_tinnitus.stop()
		_tinnitus.volume_db = TIN_MIN_DB
	if _dripping != null:
		_dripping.stop()
	if _racing != null:
		_racing.stop()
	_chop_target = CHOP_MIN_DB
	_tin_target = TIN_MIN_DB
	_street_ok = false
	_active = false
	_drip_fired = 0
	_race_fired = 0
	_reset_timers()


## 当前状态（调试用）
func debug_levels() -> Dictionary:
	return {
		"chopping": snappedf(_chopping.volume_db, 0.1) if _chopping != null else 0.0,
		"chopping_playing": _chopping.playing if _chopping != null else false,
		"tinnitus": snappedf(_tinnitus.volume_db, 0.1) if _tinnitus != null else 0.0,
		"tinnitus_playing": _tinnitus.playing if _tinnitus != null else false,
		"dripping_playing": _dripping.playing if _dripping != null else false,
		"drip_in": snappedf(_drip_countdown, 0.1),
		"racing_playing": _racing.playing if _racing != null else false,
		"race_in": snappedf(_race_countdown, 0.1),
		"street_ok": _street_ok,
		"drip_fired": _drip_fired,
		"race_fired": _race_fired,
	}
