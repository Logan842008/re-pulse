extends Node
## Hosting and joining a LAN match, plus the roster of player names and
## colours. Autoloaded as "Network".
##
## The host is always player slot 0 (spawns at the bottom) and the client is
## slot 1 (spawns at the top). Slots are used everywhere for health, score,
## names and colours so both peers agree on who is who.

signal roster_changed

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 1 # 1v1: the host plus one client.
const MAX_NAME_LENGTH := 16
const PROFILE_PATH := "user://profile.cfg"

## Colours players can pick from. Green and yellow are left out because the
## powerups use them.
const PALETTE: Array[Color] = [
	Color(0.3, 0.6, 1.0),
	Color(1.0, 0.35, 0.35),
	Color(0.7, 0.45, 1.0),
	Color(1.0, 0.6, 0.2),
	Color(0.2, 0.9, 0.9),
	Color(1.0, 0.45, 0.8),
]
const PALETTE_NAMES: Array[String] = ["Blue", "Red", "Purple", "Orange", "Cyan", "Pink"]

## Rounds in a match (best of N). Picked by the host and sent to the client
## when each round starts.
var best_of := 3

## This player's own choices (saved between sessions).
var my_name := ""
var my_color := 0

## Who is in the match, keyed by slot: {"name": String, "color": int}.
## The server owns it and sends every change to the client.
var roster := {}


func _ready() -> void:
	_load_profile()
	multiplayer.connected_to_server.connect(submit_profile)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func host_game(port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	submit_profile()
	return OK


func join_game(address: String, port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave_game() -> void:
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster = {}
	roster_changed.emit()


func slot_of(peer_id: int) -> int:
	return 0 if peer_id == 1 else 1


func local_slot() -> int:
	return slot_of(multiplayer.get_unique_id())


func get_color(slot: int) -> Color:
	return PALETTE[roster[slot]["color"]] if roster.has(slot) else PALETTE[slot]


func get_player_name(slot: int) -> String:
	return roster[slot]["name"] if roster.has(slot) else "Player %d" % (slot + 1)


## IPv4 addresses the other player can type in to join this machine.
func get_lan_addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.contains(".") and not address.begins_with("127.") and not address.begins_with("169.254."):
			result.append(address)
	return result


## Sends my_name / my_color to the server, which updates the roster.
func submit_profile() -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	if multiplayer.is_server():
		_apply_profile(1, my_name, my_color)
	else:
		_receive_profile.rpc_id(1, my_name, my_color)


func save_profile() -> void:
	var config := ConfigFile.new()
	config.set_value("profile", "name", my_name)
	config.set_value("profile", "color", my_color)
	config.save(PROFILE_PATH)


func _load_profile() -> void:
	var config := ConfigFile.new()
	if config.load(PROFILE_PATH) == OK:
		my_name = config.get_value("profile", "name", "")
		my_color = clampi(config.get_value("profile", "color", 0), 0, PALETTE.size() - 1)


@rpc("any_peer", "reliable")
func _receive_profile(player_name: String, color: int) -> void:
	if multiplayer.is_server():
		_apply_profile(multiplayer.get_remote_sender_id(), player_name, color)


## Server only: the single place names and colours are decided, so two
## players can never end up with the same colour.
func _apply_profile(peer_id: int, player_name: String, color: int) -> void:
	var slot := slot_of(peer_id)
	var taken: int = roster[1 - slot]["color"] if roster.has(1 - slot) else -1
	if color < 0 or color >= PALETTE.size() or color == taken:
		# Keep the colour they already have, or give them the first free one.
		color = roster[slot]["color"] if roster.has(slot) else (1 if taken == 0 else 0)
	player_name = player_name.strip_edges().left(MAX_NAME_LENGTH)
	if player_name.is_empty():
		player_name = "Player %d" % (slot + 1)
	roster[slot] = {"name": player_name, "color": color}
	_sync_roster.rpc(roster)


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server() and roster.has(slot_of(peer_id)):
		roster.erase(slot_of(peer_id))
		_sync_roster.rpc(roster)


@rpc("authority", "call_local", "reliable")
func _sync_roster(new_roster: Dictionary) -> void:
	roster = new_roster
	roster_changed.emit()
