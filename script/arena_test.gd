extends Node3D

const MODES := ["ffa", "1v1", "2v2"]

var mode := 0
var slot := 0
var flip := false

@onready var arena: ArenaMap = $Arena
var player: FpsTestPlayer
var info: Label


func _ready() -> void:
	player = FpsTestPlayer.new()
	add_child(player)
	var ui := CanvasLayer.new()
	info = Label.new()
	info.position = Vector2(16, 12)
	info.add_theme_font_size_override("font_size", 18)
	ui.add_child(info)
	add_child(ui)
	_respawn()


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo:
		return
	match e.physical_keycode:
		KEY_1, KEY_2, KEY_3:
			mode = e.physical_keycode - KEY_1
			slot = 0
		KEY_TAB:
			slot += 1
		KEY_F:
			flip = not flip
		_:
			return
	_respawn()


func _respawn() -> void:
	var pts: Array = []
	var teams := arena.spawns(MODES[mode], flip)
	for t in teams.size():
		for xf in teams[t]:
			pts.append([t, xf])
	slot %= pts.size()
	player.place(pts[slot][1])
	var side := "E/W" if flip else "N/S"
	info.text = "%s  |  team %d, spawn %d/%d  |  pair %s\n1/2/3 mode   Tab next spawn   F swap pair   Esc mouse" % [
		MODES[mode].to_upper(), pts[slot][0] + 1, slot + 1, pts.size(), side]
