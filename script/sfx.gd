extends Node

const DIR := "res://assets/audio/"
const MUSIC_DB := -14.0

const SOUNDS := {
	"click": ["interface/click_002.ogg"],
	"hover": ["ui/rollover2.ogg"],
	"back": ["interface/back_002.ogg"],
	"confirm": ["interface/confirmation_002.ogg"],
	"error": ["interface/error_004.ogg"],
	"join": ["interface/drop_002.ogg"],
	"scope_in": ["interface/maximize_003.ogg"],
	"scope_out": ["interface/minimize_003.ogg"],
	"shot_0": ["scifi/laserSmall_000.ogg", "scifi/laserSmall_001.ogg", "scifi/laserSmall_002.ogg", "scifi/laserSmall_003.ogg", "scifi/laserSmall_004.ogg"],
	"shot_1": ["scifi/laserRetro_000.ogg", "scifi/laserRetro_001.ogg", "scifi/laserRetro_002.ogg", "scifi/laserRetro_003.ogg", "scifi/laserRetro_004.ogg"],
	"shot_2": ["scifi/laserLarge_000.ogg", "scifi/laserLarge_001.ogg"],
	"shot_3": ["scifi/laserLarge_002.ogg", "scifi/laserLarge_003.ogg", "scifi/laserLarge_004.ogg"],
	"bounce": ["scifi/impactMetal_000.ogg", "scifi/impactMetal_001.ogg", "scifi/impactMetal_002.ogg", "scifi/impactMetal_003.ogg", "scifi/impactMetal_004.ogg"],
	"slide": ["scifi/forceField_000.ogg"],
	"hit": ["impact/impactPlate_light_000.ogg", "impact/impactPlate_light_001.ogg", "impact/impactPlate_light_002.ogg"],
	"headshot": ["impact/impactBell_heavy_000.ogg"],
	"hurt": ["impact/impactPunch_medium_000.ogg", "impact/impactPunch_medium_001.ogg", "impact/impactPunch_medium_002.ogg"],
	"jump": ["impact/impactSoft_medium_000.ogg"],
	"land": ["impact/impactSoft_heavy_000.ogg"],
	"slam": ["impact/impactMetal_heavy_000.ogg", "impact/impactMetal_heavy_001.ogg"],
	"heal": ["digital/powerUp2.ogg"],
	"boost": ["digital/powerUp7.ogg"],
	"pickup": ["digital/phaserUp3.ogg"],
	"kill": ["digital/highUp.ogg"],
	"out": ["digital/lowDown.ogg"],
	"round_won": ["digital/zapThreeToneUp.ogg"],
	"round_lost": ["digital/zapThreeToneDown.ogg"],
	"ready": ["voice/ready.ogg"],
	"fight": ["voice/fight.ogg"],
	"you_win": ["voice/you_win.ogg"], "you_lose": ["voice/you_lose.ogg"],
	"flawless": ["voice/flawless_victory.ogg"], "multi_kill": ["voice/multi_kill.ogg"],
}
const STEPS := ["concrete", "grass", "snow", "wood"]
const MUSIC := {
	"menu": "music/net_infiltration_loop.mp3",
	"3d": "music/brute_force_loop.mp3",
	"2d": "music/Party_Sector.mp3",
}
const GUNSHOTS := [
	["gunshots/cz.wav", [0.27, 2.82, 4.05, 5.54]],
	["gunshots/mosin.wav", [0.45, 3.57, 6.0, 8.86, 12.19]],
	["gunshots/sks.wav", [0.35, 2.3, 3.34, 6.01, 7.71, 9.72, 11.46, 12.73, 13.45]],
	["gunshots/shotty.wav", [0.0]],
]

var _cache := {}
var _last := {}
var _music: AudioStreamPlayer
var _track := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b: Array in [["Music", -14.0], ["SFX", 0.0]]:
		if false and AudioServer.get_bus_index(b[0]) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b[0])
			AudioServer.set_bus_send(i, "Master")
			AudioServer.set_bus_volume_db(i, b[1])
	for s in STEPS:
		var l := []
		for i in 5:
			l.append("impact/footstep_%s_00%d.ogg" % [s, i])
		_cache["step_" + s] = l.map(_load)
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	add_child(_music)
	get_tree().node_added.connect(_on_node_added)


func _load(f: String) -> AudioStream:
	return load(DIR + f)


func _stream(name: String) -> AudioStream:
	if not _cache.has(name):
		if not SOUNDS.has(name):
			push_warning("no sound called " + name)
			return null
		_cache[name] = SOUNDS[name].map(_load)
	var l: Array = _cache[name]
	return l.pick_random()


func _ok(name: String, gap_ms: int) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last.get(name, -100000)) < gap_ms:
		return false
	_last[name] = now
	return true


func play(name: String, db := 0.0, gap_ms := 25) -> void:
	var s := _stream(name)
	if s == null or not _ok(name, gap_ms):
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = randf_range(0.96, 1.04)
	p.bus = "Master"
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()


func at3d(name: String, pos: Vector3, db := 0.0, gap_ms := 25) -> void:
	var s := _stream(name)
	if s == null or not _ok("%s%v" % [name, pos.snapped(Vector3.ONE)], gap_ms):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = db
	p.unit_size = 6.0
	p.max_distance = 60.0
	p.pitch_scale = randf_range(0.95, 1.05)
	p.bus = "Master"
	p.finished.connect(p.queue_free)
	add_child(p)
	p.global_position = pos
	p.play()


func at2d(name: String, pos: Vector2, db := 0.0, gap_ms := 25) -> void:
	var s := _stream(name)
	if s == null or not _ok("%s%v" % [name, pos.snapped(Vector2.ONE * 32.0)], gap_ms):
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.volume_db = db
	p.max_distance = 1600.0
	p.attenuation = 0.6
	p.pitch_scale = randf_range(0.95, 1.05)
	p.bus = "Master"
	p.finished.connect(p.queue_free)
	add_child(p)
	p.global_position = pos
	p.play()


func music(key: String) -> void:
	if key == _track:
		return
	_track = key
	var tw := create_tween()
	if _music.playing:
		tw.tween_property(_music, "volume_db", -40.0, 0.6)
	tw.tween_callback(func():
		if key == "":
			_music.stop()
			return
		var st: AudioStreamMP3 = load(DIR + MUSIC[key])
		st.loop = true
		_music.stream = st
		_music.volume_db = -40.0
		_music.play())
	if key != "":
		tw.tween_property(_music, "volume_db", MUSIC_DB, 1.0)


func gunshot(db := 0.0) -> void:
	var g: Array = GUNSHOTS.pick_random()
	var at: float = g[1].pick_random()
	var p := AudioStreamPlayer.new()
	p.stream = _load(g[0])
	p.volume_db = db
	p.pitch_scale = randf_range(0.92, 1.08)
	p.bus = "Master"
	add_child(p)
	p.play(at)
	var tw := p.create_tween()
	tw.tween_interval(0.55)
	tw.tween_property(p, "volume_db", -40.0, 0.25)
	tw.tween_callback(p.queue_free)


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		var b: BaseButton = n
		b.pressed.connect(func(): play("click", -4.0))
		b.mouse_entered.connect(func():
			if not b.disabled:
				play("hover", -16.0, 60))
	if n is OptionButton:
		n.item_selected.connect(func(_i): play("click", -4.0))
