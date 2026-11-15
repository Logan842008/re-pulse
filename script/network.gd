extends Node
# autoload. host = peer 1 = slot 0 (bottom), client = slot 1 (top)
#
# browsers can't accept incoming connections, so both sides meet on the public
# peerjs server just to swap the webrtc offer/answer/candidates, then it's p2p.
# host registers as "repulse-<CODE>". peerjs kills the socket if a message isn't
# in its own format, hence the connectionId/label junk in the payloads

signal roster_changed
signal room_opened
signal failed(reason: String)
signal status(msg: String)

const PEERJS_URL := "wss://0.peerjs.com:443/peerjs?key=peerjs&id=%s&token=%s"
const ID_PREFIX := "repulse-"
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LEN := 5
# relay for when direct p2p is blocked (metered.ca > TURN Server > Credentials)
const TURN_USER := "011a917e130b19eed56f678b"
const TURN_PASS := "Zekyrf3mNehszELp"
const ICE_SERVERS := [
	{"urls": ["stun:stun.l.google.com:19302", "stun:stun.relay.metered.ca:80"]},
	{
		"urls": [
			"turn:standard.relay.metered.ca:80",
			"turn:standard.relay.metered.ca:80?transport=tcp",
			"turn:standard.relay.metered.ca:443",
			"turns:standard.relay.metered.ca:443?transport=tcp",
		],
		"username": TURN_USER,
		"credential": TURN_PASS,
	},
]
const HEARTBEAT := 5.0
const ANSWER_WAIT := 30.0 # long enough for the host to tab back in
const CONNECT_WAIT := 15.0
const MAX_NAME_LEN := 16
const SAVE_PATH := "user://profile.cfg"

# no green or yellow, the powerups use those
const PALETTE: Array[Color] = [
	Color(0.24, 0.55, 1.0),
	Color(1.0, 0.3, 0.37),
	Color(0.71, 0.42, 1.0),
	Color(1.0, 0.6, 0.18),
	Color(0.0, 0.94, 1.0),
	Color(1.0, 0.17, 0.84),
]
const COLOR_NAMES: Array[String] = ["Blue", "Red", "Purple", "Orange", "Cyan", "Pink"]

var best_of := 3
var my_name := ""
var my_color := 0
# slot -> {"name": String, "color": int}, owned by the server
var roster := {}
var room_code := ""

var _rtc: WebRTCMultiplayerPeer
var _ws: WebSocketPeer
var _hosting := false
var _room_up := false
var _sig_id := ""
var _sig_token := ""
var _other := "" # peerjs id of the other side
var _pending := 0 # host: peer id of whoever is mid-handshake
var _hb := 0.0
var _join_t := 0.0
var _got_answer := false
var _ice := -1
var _retries := 0


func _ready() -> void:
	_load_profile()
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _process(delta: float) -> void:
	var state := _watch_ice(_pending if _hosting else 1)
	if _join_t > 0.0:
		_join_t -= delta
		if state == WebRTCPeerConnection.STATE_FAILED or _join_t <= 0.0:
			if _got_answer:
				_fail("Couldn't connect to the host. Try again, or try another network.")
			else:
				_fail("The host didn't answer. Their game needs to be open and not in a background tab.")
			return
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			while _ws and _ws.get_available_packet_count() > 0:
				var msg = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
				if msg is Dictionary:
					_on_signal(msg)
			_hb -= delta
			if _ws and _hb <= 0.0:
				_hb = HEARTBEAT
				_ws.send_text('{"type":"HEARTBEAT"}')
		WebSocketPeer.STATE_CLOSED:
			_ws = null
			_on_ws_closed()


static func webrtc_available() -> bool:
	# browsers have it built in, desktop needs the webrtc-native GDExtension
	return OS.has_feature("web") or ClassDB.class_exists("WebRTCLibPeerConnection")


func host_game() -> Error:
	var err := _start_rtc(true)
	if err != OK:
		return err
	_hosting = true
	_retries = 0
	_open_room()
	submit_profile()
	return OK


func join_game(code: String) -> Error:
	var err := _start_rtc(false)
	if err != OK:
		return err
	room_code = code.strip_edges().to_upper()
	_other = ID_PREFIX + room_code
	_join_t = ANSWER_WAIT
	_got_answer = false
	_connect_ws("%sp%d" % [ID_PREFIX, randi()])
	return OK


func leave_game() -> void:
	_close_ws()
	_hosting = false
	_room_up = false
	_join_t = 0.0
	_got_answer = false
	_ice = -1
	_pending = 0
	_other = ""
	room_code = ""
	if _rtc:
		_rtc.close()
		_rtc = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster = {}
	roster_changed.emit()


func slot_of(pid: int) -> int:
	return 0 if pid == 1 else 1


func my_slot() -> int:
	return slot_of(multiplayer.get_unique_id())


func color_of(slot: int) -> Color:
	return PALETTE[roster[slot]["color"]] if roster.has(slot) else PALETTE[slot]


func name_of(slot: int) -> String:
	return roster[slot]["name"] if roster.has(slot) else "Player %d" % (slot + 1)


func submit_profile() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer is OfflineMultiplayerPeer or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if multiplayer.is_server():
		_apply_profile(1, my_name, my_color)
	else:
		_recv_profile.rpc_id(1, my_name, my_color)


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "name", my_name)
	cfg.set_value("profile", "color", my_color)
	cfg.save(SAVE_PATH)


func _load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		my_name = cfg.get_value("profile", "name", "")
		my_color = clampi(cfg.get_value("profile", "color", 0), 0, PALETTE.size() - 1)


func _start_rtc(host: bool) -> Error:
	if not webrtc_available():
		return ERR_UNAVAILABLE
	_rtc = WebRTCMultiplayerPeer.new()
	var err := _rtc.create_server() if host else _rtc.create_client(randi_range(2, 0x7FFFFFFF))
	if err != OK:
		_rtc = null
		return err
	multiplayer.multiplayer_peer = _rtc
	_sig_token = str(randi())
	return OK


func _open_room() -> void:
	room_code = ""
	for i in CODE_LEN:
		room_code += CODE_CHARS[randi() % CODE_CHARS.length()]
	_connect_ws(ID_PREFIX + room_code)


func _connect_ws(id: String) -> void:
	_sig_id = id
	_hb = HEARTBEAT
	_ws = WebSocketPeer.new()
	_ws.connect_to_url(PEERJS_URL % [id, _sig_token])


func _close_ws() -> void:
	if _ws:
		_ws.close()
		_ws = null


func _on_ws_closed() -> void:
	if not _hosting:
		_fail("Lost the connection to the matchmaking server.")
	elif _room_up:
		# peerjs drops quiet sockets (background tabs stop the heartbeat).
		# reconnecting with the same id + token gets the same code back
		get_tree().create_timer(2.0).timeout.connect(_reconnect)
	elif _retries < 3:
		# closed before OPEN, probably the code is taken
		_retries += 1
		_open_room()
	else:
		_fail("Couldn't reach the matchmaking server.")


func _reconnect() -> void:
	if _hosting and _ws == null:
		_connect_ws(_sig_id)


func _fail(reason: String) -> void:
	leave_game()
	failed.emit(reason)


func _send(type: String, dst: String, payload: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify({"type": type, "dst": dst, "payload": payload}))


func _on_signal(msg: Dictionary) -> void:
	var src: String = msg.get("src", "")
	var data = msg.get("payload")
	if not data is Dictionary:
		data = {}
	var type: String = str(msg.get("type", ""))
	if type != "CANDIDATE":
		print("[net] got %s %s" % [type, src])
	match type:
		"OPEN":
			if not _hosting:
				status.emit("Looking for room %s..." % room_code)
				_send_offer()
			elif not _room_up:
				_room_up = true
				room_opened.emit()
		"EXPIRE":
			if not _hosting:
				_fail("No room called %s, check the code." % room_code)
		"OFFER":
			if _hosting:
				_on_offer(src, data)
		"ANSWER":
			if not _hosting and src == _other and _rtc.has_peer(1):
				_got_answer = true
				_join_t = CONNECT_WAIT
				status.emit("Found the host, connecting...")
				_rtc.get_peer(1).connection.set_remote_description("answer", data.sdp.sdp)
		"CANDIDATE":
			var pid := _pending if _hosting else 1
			if src == _other and _rtc.has_peer(pid):
				var c: Dictionary = data.candidate
				_rtc.get_peer(pid).connection.add_ice_candidate(c.sdpMid, int(c.sdpMLineIndex), c.candidate)
		"ERROR":
			_fail("Matchmaking server error: %s" % str(data.get("msg", "unknown")))


func _send_offer() -> void:
	var conn := _new_conn(_other, "dc_%x" % randi())
	_rtc.add_peer(conn, 1)
	conn.create_offer()


func _on_offer(src: String, data: Dictionary) -> void:
	var meta = data.get("metadata")
	var pid: int = int(meta.get("pid", 0)) if meta is Dictionary else 0
	# no way to send "room full" back through peerjs, they just time out
	if pid < 2 or _has_opponent():
		print("[net] ignoring offer, room is full")
		return
	if _pending and _rtc.has_peer(_pending):
		_rtc.remove_peer(_pending) # last attempt never finished
	_pending = pid
	_ice = -1
	_other = src
	var conn := _new_conn(src, str(data.get("connectionId", "dc_0")))
	_rtc.add_peer(conn, pid)
	conn.set_remote_description("offer", data.sdp.sdp)


# logs state changes to the console, handy when a join fails
func _watch_ice(pid: int) -> int:
	if _rtc == null or pid == 0 or not _rtc.has_peer(pid):
		return -1
	var s: int = _rtc.get_peer(pid).connection.get_connection_state()
	if s != _ice:
		_ice = s
		print("[net] peer %d connection state: %s" % [pid, ["new", "connecting", "connected", "disconnected", "failed", "closed"][s]])
	return s


func _has_opponent() -> bool:
	for p in _rtc.get_peers().values():
		if p.connected:
			return true
	return false


func _new_conn(dst: String, cid: String) -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	conn.initialize({"iceServers": ICE_SERVERS})
	conn.session_description_created.connect(_on_sdp.bind(conn, dst, cid))
	conn.ice_candidate_created.connect(_on_ice.bind(dst, cid))
	return conn


func _on_sdp(type: String, sdp: String, conn: WebRTCPeerConnection, dst: String, cid: String) -> void:
	if _rtc == null:
		return
	conn.set_local_description(type, sdp)
	var payload := {"sdp": {"type": type, "sdp": sdp}, "type": "data", "connectionId": cid}
	if type == "offer":
		payload.merge({"label": cid, "reliable": true, "serialization": "binary", "metadata": {"pid": _rtc.get_unique_id()}})
	_send(type.to_upper(), dst, payload)


func _on_ice(mid: String, index: int, cand: String, dst: String, cid: String) -> void:
	_send("CANDIDATE", dst, {
		"candidate": {"candidate": cand, "sdpMid": mid, "sdpMLineIndex": index},
		"type": "data",
		"connectionId": cid,
	})


func _on_connected() -> void:
	_join_t = 0.0
	_close_ws() # handshake is done, nothing else goes through peerjs
	submit_profile()


func _on_peer_disconnected(pid: int) -> void:
	if multiplayer.is_server() and roster.has(slot_of(pid)):
		roster.erase(slot_of(pid))
		_sync_roster.rpc(roster)


@rpc("any_peer", "reliable")
func _recv_profile(pname: String, color: int) -> void:
	if multiplayer.is_server():
		_apply_profile(multiplayer.get_remote_sender_id(), pname, color)


# server decides the final name/colour so both can't grab the same colour
func _apply_profile(pid: int, pname: String, color: int) -> void:
	var slot := slot_of(pid)
	var taken: int = roster[1 - slot]["color"] if roster.has(1 - slot) else -1
	if color < 0 or color >= PALETTE.size() or color == taken:
		color = roster[slot]["color"] if roster.has(slot) else (1 if taken == 0 else 0)
	pname = pname.strip_edges().left(MAX_NAME_LEN)
	if pname.is_empty():
		pname = "Player %d" % (slot + 1)
	roster[slot] = {"name": pname, "color": color}
	_sync_roster.rpc(roster)


@rpc("authority", "call_local", "reliable")
func _sync_roster(new_roster: Dictionary) -> void:
	roster = new_roster
	roster_changed.emit()
