extends Node
## 压力驱动音频层：心跳 + 呼吸。
##
## 两部分都**只由压力驱动**，压力越高越明显。
##
## 一、心跳三档（随压力切换，交叉淡入）
##   · 正常心跳  压力 0 ~ 35
##   · 稍快心跳  压力 30 ~ 70
##   · 极快心跳  压力 65 ~ 100
##   档位之间有重叠区间做交叉淡入，避免硬切。
##
## 二、呼吸三档（同样随压力渐显）
##   · 软呼吸    压力 10 起
##   · 冻得发抖  压力 35 起
##   · 沉重呼吸  压力 65 起
##
## 为什么分层而不是单个循环：
##   心跳的"越来越快"靠换音频实现（三档本身速度不同），
##   硬切会听出断点，所以用重叠区间 + 音量交叉。

## ---- 心跳三档：路径 + 生效压力区间 + 最大音量 ----
const HEARTBEATS := [
	{
		"path": "res://audio/heartbeat/hb_normal.mp3",
		"from": 0.0, "to": 45.0, "db": -1.0,
	},
	{
		"path": "res://audio/heartbeat/hb_fast.mp3",
		"from": 40.0, "to": 80.0, "db": 2.0,
	},
	{
		"path": "res://audio/heartbeat/hb_rapid.mp3",
		"from": 72.0, "to": 100.0, "db": 5.0,
	},
]

## ---- 呼吸三档：路径 + 起始压力 + 满压力时的音量 ----
const BREATHS := [
	{
		"path": "res://audio/heartbeat/br_soft.mp3",
		"from": 8.0, "db": -11.0,
	},
	{
		"path": "res://audio/heartbeat/br_cold.mp3",
		"from": 30.0, "db": -6.0,
	},
	{
		"path": "res://audio/heartbeat/br_heavy.mp3",
		"from": 58.0, "db": 0.0,
	},
]

## 静音阈值（低于这个就视为听不见）
const SILENT_DB := -50.0
## 音量平滑速度
const FADE_SPEED := 2.2

var _hb_players: Array[AudioStreamPlayer] = []
var _br_players: Array[AudioStreamPlayer] = []
var _hb_target: Array[float] = []
var _br_target: Array[float] = []
var _active := false


func _ready() -> void:
	for cfg in HEARTBEATS:
		var p := _make_player("Hb_%s" % String(cfg["path"]).get_file().get_basename(), String(cfg["path"]))
		_hb_players.append(p)
		_hb_target.append(SILENT_DB)
	for cfg in BREATHS:
		var p := _make_player("Br_%s" % String(cfg["path"]).get_file().get_basename(), String(cfg["path"]))
		_br_players.append(p)
		_br_target.append(SILENT_DB)


func _make_player(node_name: String, path: String) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		push_warning("StressAudio: 找不到 %s" % path)
		var dummy := AudioStreamPlayer.new()
		dummy.name = node_name
		dummy.volume_db = SILENT_DB
		add_child(dummy)
		return dummy
	var stream: AudioStream = load(path)
	if stream != null:
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		elif stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = SILENT_DB
	add_child(player)
	return player


## 每帧由 main.gd 调用
##   pressure  压力 0~100
##   in_game   是否在对局中
func update_state(pressure: float, in_game: bool) -> void:
	_active = in_game
	var p := clampf(pressure, 0.0, 100.0)

	# ---- 心跳：三档互斥，按压力选一档 ----
	var hb_idx := _pick_tier(HEARTBEATS, p)
	for i in HEARTBEATS.size():
		var cfg: Dictionary = HEARTBEATS[i]
		var db_max := float(cfg["db"])
		if i == hb_idx:
			# 选中档：按该档区间内的进度爬到满档音量
			var from := float(cfg.get("from", 0.0))
			var to := float(cfg.get("to", 100.0))
			var w := clampf((p - from) / maxf(to - from, 1.0), 0.35, 1.0)
			_hb_target[i] = lerpf(SILENT_DB, db_max, w)
		else:
			_hb_target[i] = SILENT_DB

	# ---- 呼吸：三档互斥，按压力选一档 ----
	var br_idx := _pick_tier(BREATHS, p)
	for i in BREATHS.size():
		var cfg: Dictionary = BREATHS[i]
		var db_max := float(cfg["db"])
		if i == br_idx:
			var from := float(cfg.get("from", 0.0))
			var w := clampf((p - from) / maxf(100.0 - from, 1.0), 0.3, 1.0)
			_br_target[i] = lerpf(SILENT_DB, db_max, w)
		else:
			_br_target[i] = SILENT_DB

	_apply_playback(_hb_players, _hb_target)
	_apply_playback(_br_players, _br_target)


## 按压力值挑一个档位（返回下标）。
## 规则：取"from 最大且 <= 压力"的那一档；都不满足就返回 -1（全静音）。
func _pick_tier(tiers: Array, p: float) -> int:
	var best := -1
	var best_from := -1.0
	for i in tiers.size():
		var cfg: Dictionary = tiers[i]
		var from := float(cfg.get("from", 0.0))
		if p >= from and from >= best_from:
			best_from = from
			best = i
	return best


func _apply_playback(players: Array[AudioStreamPlayer], targets: Array[float]) -> void:
	for i in players.size():
		var player := players[i]
		if player == null:
			continue
		if targets[i] > SILENT_DB + 1.0:
			if not player.playing:
				player.play()
		elif player.playing and player.volume_db < SILENT_DB + 4.0:
			player.stop()


func _process(delta: float) -> void:
	var t := clampf(delta * FADE_SPEED, 0.0, 1.0)
	for i in _hb_players.size():
		var p := _hb_players[i]
		if p != null and p.playing:
			p.volume_db = lerpf(p.volume_db, _hb_target[i], t)
	for i in _br_players.size():
		var p := _br_players[i]
		if p != null and p.playing:
			p.volume_db = lerpf(p.volume_db, _br_target[i], t)


## 全停（结算 / 重开）
func stop_all() -> void:
	for p in _hb_players:
		if p != null:
			p.stop()
			p.volume_db = SILENT_DB
	for p in _br_players:
		if p != null:
			p.stop()
			p.volume_db = SILENT_DB
	for i in _hb_target.size():
		_hb_target[i] = SILENT_DB
	for i in _br_target.size():
		_br_target[i] = SILENT_DB
	_active = false


## 调试用
func debug_levels() -> Dictionary:
	var out := {}
	for i in _hb_players.size():
		out["hb%d" % i] = snappedf(_hb_players[i].volume_db, 0.1) if _hb_players[i] != null else 0.0
	for i in _br_players.size():
		out["br%d" % i] = snappedf(_br_players[i].volume_db, 0.1) if _br_players[i] != null else 0.0
	return out
