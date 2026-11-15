extends Node
# lobby. only the host makes the Game scene, LevelSpawner copies it to the client

enum State { OFFLINE, CONNECTING, ROOM }

const GAME_SCENE := preload("res://scene/game.tscn")
const ROUND_OPTS: Array[int] = [1, 3, 5]

var _state := State.OFFLINE

@onready var level: Node = $Level
@onready var level_spawner: MultiplayerSpawner = $LevelSpawner
@onready var lobby: CanvasLayer = $Lobby
@onready var name_edit: LineEdit = %NameEdit
@onready var swatches: HBoxContainer = %Swatches
@onready var rounds_row: HBoxContainer = %RoundsRow
@onready var rounds_opt: OptionButton = %Rounds
@onready var connect_box: VBoxContainer = %ConnectBox
@onready var host_btn: Button = %HostButton
@onready var code_edit: LineEdit = %CodeEdit
@onready var join_btn: Button = %JoinButton
@onready var room_box: VBoxContainer = %RoomBox
@onready var player_list: VBoxContainer = %PlayerList
@onready var start_btn: Button = %StartButton
@onready var room_hint: Label = %RoomHint
@onready var leave_btn: Button = %LeaveButton
@onready var status_lbl: Label = %Status


func _ready() -> void:
	level_spawner.add_spawnable_scene(GAME_SCENE.resource_path)
	level_spawner.spawned.connect(_on_game_spawned)

	for n in ROUND_OPTS:
		rounds_opt.add_item("Best of %d" % n)
	rounds_opt.select(ROUND_OPTS.find(Network.best_of))
	name_edit.max_length = Network.MAX_NAME_LEN
	name_edit.text = Network.my_name
	name_edit.text_changed.connect(_on_name_changed)
	code_edit.max_length = Network.CODE_LEN
	code_edit.text_submitted.connect(_on_join.unbind(1))
	_build_swatches()

	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	start_btn.pressed.connect(_on_start)
	leave_btn.pressed.connect(_return_to_lobby)
	Network.roster_changed.connect(_refresh)
	Network.room_opened.connect(_on_room_opened)
	Network.failed.connect(_return_to_lobby)
	Network.status.connect(func(msg: String): status_lbl.text = msg)

	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_refresh()


func _on_name_changed(new_name: String) -> void:
	Network.my_name = new_name
	Network.save_profile()
	Network.submit_profile()


func _on_swatch(idx: int) -> void:
	Network.my_color = idx
	Network.save_profile()
	Network.submit_profile()
	_refresh()


func _build_swatches() -> void:
	for i in Network.PALETTE.size():
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(30, 30)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.focus_mode = Control.FOCUS_NONE
		sw.tooltip_text = Network.COLOR_NAMES[i]
		sw.pressed.connect(_on_swatch.bind(i))
		swatches.add_child(sw)


# in a room the server's roster wins, offline it's just the saved pick
func _my_color() -> int:
	var slot := Network.my_slot()
	if _state == State.ROOM and Network.roster.has(slot):
		return Network.roster[slot]["color"]
	return Network.my_color


func _opp_color() -> int:
	var slot := 1 - Network.my_slot()
	if _state == State.ROOM and Network.roster.has(slot):
		return Network.roster[slot]["color"]
	return -1


func _refresh_swatches() -> void:
	var mine := _my_color()
	var taken := _opp_color()
	for i in swatches.get_child_count():
		var sw: Button = swatches.get_child(i)
		var col := Network.PALETTE[i]
		sw.disabled = i == taken
		sw.text = "X" if i == taken else ""
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.7) if i == taken else col
		sb.set_corner_radius_all(15)
		sb.border_color = Color(0.91, 0.98, 1.0)
		sb.set_border_width_all(3 if i == mine else 0)
		if i == mine:
			sb.shadow_color = Color(col, 0.7)
			sb.shadow_size = 10
		var hover := sb.duplicate()
		if i != mine and i != taken:
			hover.bg_color = col.lightened(0.25)
		for s in ["normal", "pressed", "disabled", "focus"]:
			sw.add_theme_stylebox_override(s, sb)
		sw.add_theme_stylebox_override("hover", hover)
		sw.add_theme_color_override("font_disabled_color", Color(0.48, 0.5, 0.66))


func _on_host() -> void:
	var err := Network.host_game()
	if err != OK:
		status_lbl.text = _err_text(err)
		return
	_state = State.CONNECTING
	status_lbl.text = "Opening a room..."
	_refresh()


func _on_room_opened() -> void:
	_state = State.ROOM
	status_lbl.text = ""
	_refresh()


func _on_join() -> void:
	if _state != State.OFFLINE:
		return
	var code := code_edit.text.strip_edges().to_upper()
	if code.is_empty():
		status_lbl.text = "Type the room code first."
		return
	var err := Network.join_game(code)
	if err != OK:
		status_lbl.text = _err_text(err)
		return
	_state = State.CONNECTING
	status_lbl.text = "Joining %s..." % code
	_refresh()


func _err_text(err: Error) -> String:
	if err == ERR_UNAVAILABLE:
		return "WebRTC not available (desktop needs the webrtc-native plugin)."
	return "Couldn't start (%s)." % error_string(err)


func _on_connected() -> void:
	_state = State.ROOM
	status_lbl.text = ""
	_refresh()


func _on_start() -> void:
	if not multiplayer.is_server() or Network.roster.size() < 2:
		return
	Network.best_of = ROUND_OPTS[rounds_opt.selected]
	var game: Game = GAME_SCENE.instantiate()
	game.exit_requested.connect(_return_to_lobby)
	level.add_child(game, true)
	lobby.hide()


func _on_game_spawned(node: Node) -> void:
	node.exit_requested.connect(_return_to_lobby)
	lobby.hide()


func _on_peer_disconnected(_pid: int) -> void:
	if multiplayer.is_server():
		_opponent_left.call_deferred()


# host keeps the room open and waits for someone new
func _opponent_left() -> void:
	_close_game()
	lobby.show()
	status_lbl.text = "Your opponent left."
	_refresh()


func _on_server_disconnected() -> void:
	_return_to_lobby.call_deferred("The host left.")


func _return_to_lobby(msg := "") -> void:
	_close_game()
	Network.leave_game()
	_state = State.OFFLINE
	lobby.show()
	status_lbl.text = msg
	_refresh()


func _close_game() -> void:
	for c in level.get_children():
		level.remove_child(c)
		c.queue_free()


func _refresh() -> void:
	var in_room := _state == State.ROOM
	var is_host := in_room and multiplayer.is_server()
	var full := Network.roster.size() == 2

	connect_box.visible = not in_room
	host_btn.disabled = _state != State.OFFLINE
	join_btn.disabled = _state != State.OFFLINE
	code_edit.editable = _state == State.OFFLINE
	rounds_row.visible = not in_room or is_host
	room_box.visible = in_room
	start_btn.visible = is_host
	start_btn.disabled = not full
	leave_btn.visible = _state != State.OFFLINE

	if is_host and not full:
		room_hint.text = "Waiting for an opponent...\nRoom code:  %s" % Network.room_code
	elif is_host:
		room_hint.text = "Opponent is here. Press Start Match when you're both ready."
	else:
		room_hint.text = "Waiting for the host to start the match..."

	_refresh_players()
	_refresh_swatches()


func _refresh_players() -> void:
	for c in player_list.get_children():
		c.queue_free()
	for slot in [0, 1]:
		if not Network.roster.has(slot):
			continue
		var col := Network.color_of(slot)
		var row := HBoxContainer.new()
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(16, 16)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(8)
		sb.shadow_color = Color(col, 0.6)
		sb.shadow_size = 6
		chip.add_theme_stylebox_override("panel", sb)
		var lbl := Label.new()
		lbl.text = Network.name_of(slot)
		if slot == 0:
			lbl.text += "  (host)"
		if slot == Network.my_slot():
			lbl.text += "  - you"
		row.add_child(chip)
		row.add_child(lbl)
		player_list.add_child(row)
