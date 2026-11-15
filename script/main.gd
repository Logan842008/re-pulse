extends Node

enum State { OFFLINE, CONNECTING, ROOM }

const GAME_SCENE := preload("res://scene/game.tscn")
const ROUND_OPTIONS: Array[int] = [1, 3, 5]

var _state := State.OFFLINE

@onready var level: Node = $Level
@onready var level_spawner: MultiplayerSpawner = $LevelSpawner
@onready var lobby: CanvasLayer = $Lobby
@onready var name_edit: LineEdit = %NameEdit
@onready var swatches: HBoxContainer = %Swatches
@onready var rounds_row: HBoxContainer = %RoundsRow
@onready var rounds_option: OptionButton = %Rounds
@onready var connect_box: VBoxContainer = %ConnectBox
@onready var host_button: Button = %HostButton
@onready var address_edit: LineEdit = %Address
@onready var join_button: Button = %JoinButton
@onready var room_box: VBoxContainer = %RoomBox
@onready var player_list: VBoxContainer = %PlayerList
@onready var start_button: Button = %StartButton
@onready var room_hint: Label = %RoomHint
@onready var leave_button: Button = %LeaveButton
@onready var status_label: Label = %Status


func _ready() -> void:
	level_spawner.add_spawnable_scene(GAME_SCENE.resource_path)
	level_spawner.spawned.connect(_on_game_spawned)

	for rounds in ROUND_OPTIONS:
		rounds_option.add_item("Best of %d" % rounds)
	rounds_option.select(ROUND_OPTIONS.find(Network.best_of))
	name_edit.max_length = Network.MAX_NAME_LENGTH
	name_edit.text = Network.my_name
	name_edit.text_changed.connect(_on_name_changed)
	_build_swatches()

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_return_to_lobby)
	Network.roster_changed.connect(_refresh)

	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_refresh()


func _on_name_changed(new_name: String) -> void:
	Network.my_name = new_name
	Network.save_profile()
	Network.submit_profile()


func _on_swatch_pressed(color: int) -> void:
	Network.my_color = color
	Network.save_profile()
	Network.submit_profile()
	_refresh()


func _build_swatches() -> void:
	for i in Network.PALETTE.size():
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(30, 30)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.tooltip_text = Network.PALETTE_NAMES[i]
		swatch.pressed.connect(_on_swatch_pressed.bind(i))
		swatches.add_child(swatch)


func _my_color() -> int:
	var slot := Network.local_slot()
	if _state == State.ROOM and Network.roster.has(slot):
		return Network.roster[slot]["color"]
	return Network.my_color


func _opponent_color() -> int:
	var slot := 1 - Network.local_slot()
	if _state == State.ROOM and Network.roster.has(slot):
		return Network.roster[slot]["color"]
	return -1


func _refresh_swatches() -> void:
	var mine := _my_color()
	var taken := _opponent_color()
	for i in swatches.get_child_count():
		var swatch: Button = swatches.get_child(i)
		swatch.disabled = i == taken
		swatch.text = "X" if i == taken else ""
		var style := StyleBoxFlat.new()
		style.bg_color = Network.PALETTE[i].darkened(0.7) if i == taken else Network.PALETTE[i]
		style.set_corner_radius_all(15)
		style.border_color = Color(0.91, 0.98, 1.0)
		style.set_border_width_all(3 if i == mine else 0)
		if i == mine:
			style.shadow_color = Color(Network.PALETTE[i], 0.7)
			style.shadow_size = 10
		var hover := style.duplicate()
		if i != mine and i != taken:
			hover.bg_color = Network.PALETTE[i].lightened(0.25)
		for state in ["normal", "pressed", "disabled", "focus"]:
			swatch.add_theme_stylebox_override(state, style)
		swatch.add_theme_stylebox_override("hover", hover)
		swatch.add_theme_color_override("font_disabled_color", Color(0.48, 0.5, 0.66))


func _on_host_pressed() -> void:
	var err := Network.host_game()
	if err != OK:
		status_label.text = "Could not host on port %d (%s)." % [Network.DEFAULT_PORT, error_string(err)]
		return
	_state = State.ROOM
	status_label.text = ""
	_refresh()


func _on_join_pressed() -> void:
	var address := address_edit.text.strip_edges()
	if address.is_empty():
		status_label.text = "Type the host's IP address first."
		return
	var err := Network.join_game(address)
	if err != OK:
		status_label.text = "Could not connect (%s)." % error_string(err)
		return
	_state = State.CONNECTING
	status_label.text = "Connecting to %s..." % address
	_refresh()


func _on_connected_to_server() -> void:
	_state = State.ROOM
	status_label.text = ""
	_refresh()


func _on_start_pressed() -> void:
	if not multiplayer.is_server() or Network.roster.size() < 2:
		return
	Network.best_of = ROUND_OPTIONS[rounds_option.selected]
	var game: Game = GAME_SCENE.instantiate()
	game.exit_requested.connect(_return_to_lobby)
	level.add_child(game, true)
	lobby.hide()


func _on_game_spawned(node: Node) -> void:
	node.exit_requested.connect(_return_to_lobby)
	lobby.hide()


func _on_peer_disconnected(_peer_id: int) -> void:
	if multiplayer.is_server():
		_opponent_left.call_deferred()


func _opponent_left() -> void:
	_close_game()
	lobby.show()
	status_label.text = "Your opponent left."
	_refresh()


func _on_server_disconnected() -> void:
	_return_to_lobby.call_deferred("The host left.")


func _on_connection_failed() -> void:
	_return_to_lobby.call_deferred("Could not reach the host. Check the IP and that you're on the same network.")


func _return_to_lobby(message := "") -> void:
	_close_game()
	Network.leave_game()
	_state = State.OFFLINE
	lobby.show()
	status_label.text = message
	_refresh()


func _close_game() -> void:
	for child in level.get_children():
		level.remove_child(child)
		child.queue_free()


func _refresh() -> void:
	var in_room := _state == State.ROOM
	var is_host := in_room and multiplayer.is_server()
	var full := Network.roster.size() == 2

	connect_box.visible = not in_room
	host_button.disabled = _state != State.OFFLINE
	join_button.disabled = _state != State.OFFLINE
	address_edit.editable = _state == State.OFFLINE
	rounds_row.visible = not in_room or is_host
	room_box.visible = in_room
	start_button.visible = is_host
	start_button.disabled = not full
	leave_button.visible = _state != State.OFFLINE

	if is_host and not full:
		var addresses := Network.get_lan_addresses()
		room_hint.text = "Waiting for an opponent...\nThey should join: %s" % (
				"  or  ".join(addresses) if not addresses.is_empty() else "(no LAN address found)")
	elif is_host:
		room_hint.text = "Opponent is here. Press Start Match when you're both ready."
	else:
		room_hint.text = "Waiting for the host to start the match..."

	_refresh_player_list()
	_refresh_swatches()


func _refresh_player_list() -> void:
	for child in player_list.get_children():
		child.queue_free()
	for slot in [0, 1]:
		if not Network.roster.has(slot):
			continue
		var row := HBoxContainer.new()
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(16, 16)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var chip_style := StyleBoxFlat.new()
		chip_style.bg_color = Network.get_color(slot)
		chip_style.set_corner_radius_all(8)
		chip_style.shadow_color = Color(Network.get_color(slot), 0.6)
		chip_style.shadow_size = 6
		chip.add_theme_stylebox_override("panel", chip_style)
		var label := Label.new()
		label.text = Network.get_player_name(slot)
		if slot == 0:
			label.text += "  (host)"
		if slot == Network.local_slot():
			label.text += "  - you"
		row.add_child(chip)
		row.add_child(label)
		player_list.add_child(row)
