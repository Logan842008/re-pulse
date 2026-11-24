extends Node

signal roster_changed
signal room_opened
signal failed(reason: String)
signal status(msg: String)

const PEERJS_URL := "wss://0.peerjs.com:443/peerjs?key=peerjs&id=%s&token=%s"
const ID_PREFIX := "repulse-"
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LEN := 5
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
const ANSWER_WAIT := 30.0
const CONNECT_WAIT := 15.0
const MAX_NAME_LEN := 16
const SAVE_PATH := "user://profile.cfg"
const MAX_PLAYERS := 4
const MODES: Array[String] = ["1v1", "2v2", "ffa"]

const PALETTE: Array[Color] = [
	Color(0.24, 0.55, 1.0),
	Color(1.0, 0.3, 0.37),
	Color(0.71, 0.42, 1.0),
	Color(1.0, 0.6, 0.18),
	Color(0.5, 1.0, 0.12),
	Color(1.0, 0.17, 0.84),
]
const COLOR_NAMES: Array[String] = ["Blue", "Red", "Purple", "Orange", "Green", "Pink"]

var first_to := 2
var is_3d := true
var map_id := 0
var mode := "1v1"
var in_match := false
var my_name := ""
var my_color := 0
var roster := {}
var room_code := ""

var _rtc: RtcLink
var _ws: WebSocketPeer
var _hst := false
var _ru := false
var _sig_id := ""
var _st := ""
var _other := ""
var _hs := {}
var _hb := 0.0
var _join_t := 0.0
var _ga := false
var _ice := -1
var _tries := 0
var _co := 0.0
var _cn := 0
var _ct := 0.0


func _ready() -> void:
	_load_profile()
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(){function k(){if(navigator.wakeLock&&document.visibilityState==='visible'){navigator.wakeLock.request('screen').catch(function(){});}}k();document.addEventListener('visibilitychange',k);document.addEventListener('pointerdown',k,{once:true});})();", true)


func _process(delta: float) -> void:
	var state := -1 if _hst else _watch_ice(1)
	if _hst:
		_watch_all()
	if not _hst and _rtc and _rtc.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_ct -= delta
		if _ct <= 0.0:
			_ct = 1.0
			_clock_req.rpc_id(1, Time.get_ticks_msec())
	if _join_t > 0.0:
		_join_t -= delta
		if state == WebRTCPeerConnection.STATE_FAILED or _join_t <= 0.0:
			if _ga:
				_fail("Couldn't connect to the host. Try again, or try another network.")
			else:
				_fail("The host didn't answer. The room might be full or mid-match, or their game is in a background tab.")
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
	return OS.has_feature("web") or ClassDB.class_exists("WebRTCLibPeerConnection")


func host_game() -> Error:
	var err := _start_rtc(true)
	if err != OK:
		return err
	_hst = true
	_tries = 0
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
	_ga = false
	_connect_ws("%sp%d" % [ID_PREFIX, randi()])
	return OK


func leave_game() -> void:
	_close_ws()
	_hst = false
	_ru = false
	_join_t = 0.0
	_ga = false
	_ice = -1
	_hs.clear()
	_other = ""
	in_match = false
	room_code = ""
	_cn = 0
	_co = 0.0
	_ct = 0.0
	if _rtc:
		_rtc.close()
		_rtc = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster = {}
	roster_changed.emit()


func server_msec() -> int:
	if multiplayer.is_server():
		return Time.get_ticks_msec()
	return Time.get_ticks_msec() + int(_co)


func lagging() -> String:
	if _rtc == null or multiplayer.multiplayer_peer != _rtc:
		return ""
	if not _hst:
		return "HOST" if _rtc.quiet(1) > 1500 or _rtc.shaky(1) else ""
	for s: int in roster:
		var pid: int = roster[s]["pid"]
		if pid != 1 and (_rtc.quiet(pid) > 1500 or _rtc.shaky(pid)):
			return name_of(s).to_upper()
	return ""


func clock_ok() -> bool:
	return multiplayer.is_server() or _cn > 0


@rpc("any_peer", "call_remote", "unreliable")
func _clock_req(t: int) -> void:
	if multiplayer.is_server():
		_clock_ans.rpc_id(multiplayer.get_remote_sender_id(), t, Time.get_ticks_msec())


# keep the smallest one, it's the least delayed
@rpc("authority", "call_remote", "unreliable")
func _clock_ans(t: int, host_t: int) -> void:
	var u := float(host_t - t)
	if _cn == 0 or u < _co:
		_co = u
	else:
		_co += 0.05
	_cn += 1


func slot_of(pid: int) -> int:
	var s := _find_slot(pid)
	if s >= 0:
		return s
	return 0 if pid == 1 else 1


func _find_slot(pid: int) -> int:
	for s: int in roster:
		if roster[s].get("pid", 0) == pid:
			return s
	return -1


func slots() -> Array:
	var k := roster.keys()
	k.sort()
	return k


func team_of(slot: int) -> int:
	if mode != "2v2":
		return slot
	return roster[slot].get("team", slot % 2) if roster.has(slot) else slot % 2


func team_slots(team: int) -> Array:
	return slots().filter(func(s: int) -> bool: return team_of(s) == team)


func spawn_index(slot: int) -> int:
	if not roster.has(slot):
		return slot
	if mode == "2v2":
		return team_of(slot) * 2 + maxi(team_slots(team_of(slot)).find(slot), 0)
	return maxi(slots().find(slot), 0)


func side_name(side: int) -> String:
	if mode != "2v2":
		return name_of(side)
	return " & ".join(team_slots(side).map(name_of))


func round_text(winner: int, over: bool) -> String:
	var mine := winner == team_of(my_slot())
	var who := side_name(winner).to_upper()
	var many := mode == "2v2"
	if not over:
		if mine:
			return "ROUND WON"
		if mode == "1v1":
			return "ROUND LOST"
		return "%s %s THE ROUND" % [who, "TAKE" if many else "TAKES"]
	if mine:
		return "YOUR TEAM WINS THE MATCH!" if many else "YOU WIN THE MATCH!"
	return "%s %s THE MATCH" % [who, "WIN" if many else "WINS"]


func out_text(slot: int) -> String:
	if slot == my_slot():
		return "YOU'RE OUT"
	return "%s IS OUT" % name_of(slot).to_upper()


func char_of(slot: int) -> int:
	var ci: int = roster[slot]["color"] if roster.has(slot) else slot
	if mode != "2v2" or not roster.has(slot):
		return ci % PALETTE.size()
	var used := []
	for t in 2:
		var mems := team_slots(t)
		for i in mems.size():
			var c: int = roster[mems[i]]["color"] + i * 3
			while used.has(c % PALETTE.size()):
				c += 1
			used.append(c % PALETTE.size())
			if mems[i] == slot:
				return c % PALETTE.size()
	return ci % PALETTE.size()


func side_color(side: int) -> Color:
	if mode != "2v2":
		return color_of(side)
	var t := team_slots(side)
	return color_of(t[0]) if not t.is_empty() else PALETTE[side]


func players_needed() -> String:
	match mode:
		"2v2":
			return "4"
		"ffa":
			return "3-4"
	return "2"


func can_start() -> bool:
	match mode:
		"2v2":
			return roster.size() == 4 and team_slots(0).size() == 2
		"ffa":
			return roster.size() >= 3
	return roster.size() == 2


func my_slot() -> int:
	return slot_of(multiplayer.get_unique_id())


func color_of(slot: int) -> Color:
	return PALETTE[roster[slot]["color"]] if roster.has(slot) else PALETTE[slot]


const THEME := preload("res://lobby_theme.tres")
var _tb := {}


func tint_theme(col: Color) -> void:
	if _tb.is_empty():
		_collect_accents()
	for key: Array in _tb:
		var old: Color = _tb[key]
		var k := maxf(old.r, maxf(old.g, old.b))
		var c := Color(col.r * k, col.g * k, col.b * k, old.a)
		if key[0] is StyleBox:
			key[0].set(key[1], c)
		else:
			THEME.set_color(key[1], key[2], c)


static func is_accent(c: Color) -> bool:
	var hi := maxf(c.r, maxf(c.g, c.b))
	var lo := minf(c.r, minf(c.g, c.b))
	return hi > 0.6 and 1.0 - lo / hi > 0.5


func _collect_accents() -> void:
	for type in THEME.get_stylebox_type_list():
		for n in THEME.get_stylebox_list(type):
			var sb := THEME.get_stylebox(n, type)
			for p in ["bg_color", "border_color"]:
				if p in sb and is_accent(sb.get(p)):
					_tb[[sb, p]] = sb.get(p)
	for type in THEME.get_color_type_list():
		for n in THEME.get_color_list(type):
			var c := THEME.get_color(n, type)
			if is_accent(c):
				_tb[[null, n, type]] = c


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
	_rtc = RtcLink.new()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lag="):
			_rtc.lag = a.get_slice("=", 1).to_int()
		elif a.begins_with("--jitter="):
			_rtc.jit = a.get_slice("=", 1).to_int()
		elif a.begins_with("--loss="):
			_rtc.loss = a.get_slice("=", 1).to_float()
	var err := _rtc.create_server() if host else _rtc.create_client(randi_range(2, 0x7FFFFFFF))
	if err != OK:
		_rtc = null
		return err
	multiplayer.multiplayer_peer = _rtc
	_st = str(randi())
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
	_ws.connect_to_url(PEERJS_URL % [id, _st])


func _close_ws() -> void:
	if _ws:
		_ws.close()
		_ws = null


func _on_ws_closed() -> void:
	if not _hst:
		_fail("Lost the connection to the matchmaking server.")
	elif _ru:
		get_tree().create_timer(2.0).timeout.connect(_reconnect)
	elif _tries < 3:
		_tries += 1
		_open_room()
	else:
		_fail("Couldn't reach the matchmaking server.")


func _reconnect() -> void:
	if _hst and _ws == null:
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
			if not _hst:
				status.emit("Looking for room %s..." % room_code)
				_send_offer()
			elif not _ru:
				_ru = true
				room_opened.emit()
		"EXPIRE":
			if not _hst:
				_fail("No room called %s, check the code." % room_code)
		"OFFER":
			if _hst:
				_on_offer(src, data)
		"ANSWER":
			if not _hst and src == _other and _rtc.has_peer(1):
				_ga = true
				_join_t = CONNECT_WAIT
				status.emit("Found the host, connecting...")
				_rtc.get_peer(1).connection.set_remote_description("answer", data.sdp.sdp)
		"CANDIDATE":
			var pid: int = _hs.get(src, 0) if _hst else (1 if src == _other else 0)
			if pid and _rtc.has_peer(pid):
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
	if pid < 2 or in_match or _connected() >= MAX_PLAYERS - 1:
		print("[net] ignoring offer, room is full or in a match")
		return
	if _hs.has(src) and _rtc.has_peer(_hs[src]) and not _rtc.get_peer(_hs[src]).connected:
		_rtc.remove_peer(_hs[src])
	_hs[src] = pid
	var conn := _new_conn(src, str(data.get("connectionId", "dc_0")))
	_rtc.add_peer(conn, pid)
	conn.set_remote_description("offer", data.sdp.sdp)


var _states := {}


func _watch_all() -> void:
	if _rtc == null:
		return
	var peers := _rtc.get_peers()
	for pid: int in peers:
		var s: int = peers[pid]["connection"].get_connection_state()
		if s != _states.get(pid, -1):
			_states[pid] = s
			print("[net] player %d connection: %s" % [pid, ["new", "connecting", "connected", "disconnected", "failed", "closed"][s]])
	for pid: int in _states.keys():
		if not peers.has(pid):
			print("[net] player %d gone (last seen: %s)" % [pid, ["new", "connecting", "connected", "disconnected", "failed", "closed"][_states[pid]]])
			_states.erase(pid)


func _watch_ice(pid: int) -> int:
	if _rtc == null or pid == 0 or not _rtc.has_peer(pid):
		return -1
	var s: int = _rtc.get_peer(pid).connection.get_connection_state()
	if s != _ice:
		_ice = s
		print("[net] peer %d connection state: %s" % [pid, ["new", "connecting", "connected", "disconnected", "failed", "closed"][s]])
	return s


func _connected() -> int:
	var n := 0
	for p in _rtc.get_peers().values():
		if p.connected:
			n += 1
	return n


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
	# peerjs closes the socket if these extra fields aren't there
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
	_close_ws()
	submit_profile()


func _on_peer_disconnected(pid: int) -> void:
	for src: String in _hs.keys():
		if _hs[src] == pid:
			_hs.erase(src)
	var s := _find_slot(pid)
	if multiplayer.is_server() and s >= 0:
		roster.erase(s)
		_sync_roster.rpc(roster)


@rpc("any_peer", "reliable")
func _recv_profile(pname: String, color: int) -> void:
	if multiplayer.is_server():
		_apply_profile(multiplayer.get_remote_sender_id(), pname, color)


func _apply_profile(pid: int, pname: String, color: int) -> void:
	var slot := _find_slot(pid)
	var fresh := slot < 0
	if fresh:
		slot = 0 if pid == 1 else _free_slot()
		if slot < 0:
			return
	var team: int = _smaller_team() if fresh else roster[slot]["team"]
	var teams := mode == "2v2"
	var mates := roster.keys().filter(func(o: int) -> bool: return o != slot and roster[o]["team"] == team)
	if teams and fresh and not mates.is_empty():
		color = roster[mates[0]]["color"]
	var taken := []
	for s: int in roster:
		if s != slot and not (teams and mates.has(s)):
			taken.append(roster[s]["color"])
	if color < 0 or color >= PALETTE.size() or taken.has(color):
		color = -1 if fresh else roster[slot]["color"]
		if color < 0 or taken.has(color):
			for c in PALETTE.size():
				if not taken.has(c):
					color = c
					break
	pname = pname.strip_edges().left(MAX_NAME_LEN)
	if pname.is_empty():
		pname = "Player %d" % (slot + 1)
	roster[slot] = {"name": pname, "color": color, "pid": pid, "team": team}
	if teams:
		for s: int in mates:
			roster[s]["color"] = color
	_sync_roster.rpc(roster)


func fix_colors() -> void:
	if not multiplayer.is_server() or roster.is_empty():
		return
	var used := []
	if mode == "2v2":
		for t in 2:
			var mems := team_slots(t)
			if mems.is_empty():
				continue
			var c: int = roster[mems[0]]["color"]
			if used.has(c):
				c = _free_color(used)
			for s: int in mems:
				roster[s]["color"] = c
			used.append(c)
	else:
		for s: int in slots():
			if used.has(roster[s]["color"]):
				roster[s]["color"] = _free_color(used)
			used.append(roster[s]["color"])
	_sync_roster.rpc(roster)


func _free_color(used: Array) -> int:
	for c in PALETTE.size():
		if not used.has(c):
			return c
	return 0


func _free_slot() -> int:
	for s in range(1, MAX_PLAYERS):
		if not roster.has(s):
			return s
	return -1


func _smaller_team() -> int:
	var a := 0
	for s: int in roster:
		a += 1 if roster[s]["team"] == 0 else -1
	return 1 if a > 0 else 0


func request_team(team: int) -> void:
	if multiplayer.is_server():
		_set_team(1, team)
	else:
		_recv_team.rpc_id(1, team)


@rpc("any_peer", "reliable")
func _recv_team(team: int) -> void:
	if multiplayer.is_server():
		_set_team(multiplayer.get_remote_sender_id(), team)


func _set_team(pid: int, team: int) -> void:
	var s := _find_slot(pid)
	if s < 0 or in_match or team < 0 or team > 1:
		return
	var others := roster.keys().filter(func(o: int) -> bool: return o != s and roster[o]["team"] == team)
	if others.size() >= 2:
		return
	roster[s]["team"] = team
	if not others.is_empty():
		roster[s]["color"] = roster[others[0]]["color"]
	fix_colors()


@rpc("authority", "call_local", "reliable")
func _sync_roster(nr: Dictionary) -> void:
	roster = nr
	roster_changed.emit()
