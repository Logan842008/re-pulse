class_name RtcLink
extends MultiplayerPeerExtension

# godot's webrtc peer kicks you on any 2 sec wifi blip, this waits it out
const GRACE := 12.0
const NAMES := ["reliable", "ordered", "unreliable"]

var lag := 0 # --lag= --jitter= --loss= for testing
var jit := 0
var loss := 0.0

var _id := 0
var _srv := false
var _st := CONNECTION_DISCONNECTED
var _peers := {}
var _in := []
var _out := []
var _ord := {}
var _tgt := 0
var _mode := TRANSFER_MODE_RELIABLE
var _chan := 0
var _refuse := false
var _prev := 0


func create_server() -> Error:
	_id = 1
	_srv = true
	_st = CONNECTION_CONNECTED
	_prev = Time.get_ticks_msec()
	return OK


func create_client(id: int) -> Error:
	_id = id
	_srv = false
	_st = CONNECTION_CONNECTING
	_prev = Time.get_ticks_msec()
	return OK


func add_peer(conn: WebRTCPeerConnection, pid: int) -> Error:
	var cfg := [
		{"negotiated": true, "id": 1},
		{"negotiated": true, "id": 2, "maxRetransmits": 0},
		{"negotiated": true, "id": 3, "maxRetransmits": 0, "ordered": false},
	]
	var chs := []
	for i in 3:
		var c := conn.create_data_channel(NAMES[i], cfg[i])
		if c == null:
			return ERR_CANT_CREATE
		c.write_mode = WebRTCDataChannel.WRITE_MODE_BINARY
		chs.append(c)
	_peers[pid] = {"connection": conn, "ch": chs, "connected": false, "down": 0.0, "last": Time.get_ticks_msec()}
	return OK


func has_peer(pid: int) -> bool:
	return _peers.has(pid)


func get_peer(pid: int) -> Dictionary:
	return _peers.get(pid, {})


func get_peers() -> Dictionary:
	return _peers


func remove_peer(pid: int) -> void:
	_drop(pid, true)


func quiet(pid: int) -> int:
	var p: Dictionary = _peers.get(pid, {})
	if p.is_empty() or not p.connected:
		return -1
	return Time.get_ticks_msec() - int(p.last)


func shaky(pid: int) -> bool:
	return _peers.has(pid) and _peers[pid].down > 0.0


func _drop(pid: int, tell: bool) -> void:
	if not _peers.has(pid):
		return
	var p: Dictionary = _peers[pid]
	_peers.erase(pid)
	for c: WebRTCDataChannel in p.ch:
		c.close()
	p.connection.close()
	_in = _in.filter(func(k: Array) -> bool: return k[0] != pid)
	if p.connected and tell:
		peer_disconnected.emit(pid)
	if not _srv and pid == 1:
		_st = CONNECTION_DISCONNECTED


func _poll() -> void:
	var now := Time.get_ticks_msec()
	var dt := (now - _prev) / 1000.0
	_prev = now
	if not _out.is_empty():
		_flush(now)
	var gone := []
	for pid: int in _peers:
		var p: Dictionary = _peers[pid]
		var conn: WebRTCPeerConnection = p.connection
		conn.poll()
		var cs := conn.get_connection_state()
		var open := 0
		var shut := false
		for c: WebRTCDataChannel in p.ch:
			c.poll()
			var rs := c.get_ready_state()
			if rs == WebRTCDataChannel.STATE_OPEN:
				open += 1
			elif rs != WebRTCDataChannel.STATE_CONNECTING:
				shut = true
		if cs == WebRTCPeerConnection.STATE_FAILED or cs == WebRTCPeerConnection.STATE_CLOSED or (shut and p.connected):
			gone.append(pid)
			continue
		if cs == WebRTCPeerConnection.STATE_DISCONNECTED:
			if p.down == 0.0:
				print("[net] link to %d dropped, waiting for it to come back" % pid)
			p.down += clampf(dt, 0.001, 0.25)
			if p.down > GRACE:
				gone.append(pid)
				continue
		elif cs == WebRTCPeerConnection.STATE_CONNECTED:
			if p.down > 0.0:
				print("[net] link to %d back after %.1fs" % [pid, p.down])
			p.down = 0.0
			if not p.connected and open == 3:
				p.connected = true
				p.last = now
				if not _srv:
					_st = CONNECTION_CONNECTED
				peer_connected.emit(pid)
		if not p.connected:
			continue
		for i in 3:
			var c: WebRTCDataChannel = p.ch[i]
			while c.get_available_packet_count() > 0:
				_in.append([pid, i, c.get_packet()])
				p.last = now
	for pid: int in gone:
		print("[net] link to %d lost" % pid)
		_drop(pid, true)


func _flush(now: int) -> void:
	var keep := []
	for k: Array in _out:
		if k[0] > now:
			keep.append(k)
		elif _peers.has(k[1]) and _peers[k[1]].connected:
			_peers[k[1]].ch[k[2]].put_packet(k[3])
	_out = keep


func _send(pid: int, ch: int, buf: PackedByteArray) -> void:
	if lag <= 0 and jit <= 0 and loss <= 0.0:
		_peers[pid].ch[ch].put_packet(buf)
		return
	if ch > 0 and randf() < loss:
		return
	var at := Time.get_ticks_msec() + lag + randi_range(0, jit)
	if ch < 2:
		var key := pid * 4 + ch
		at = maxi(at, int(_ord.get(key, 0)))
		_ord[key] = at
	_out.append([at, pid, ch, buf])


func _put_packet_script(buf: PackedByteArray) -> Error:
	var ch := 0
	if _mode == TRANSFER_MODE_UNRELIABLE_ORDERED:
		ch = 1
	elif _mode == TRANSFER_MODE_UNRELIABLE:
		ch = 2
	for pid: int in _peers:
		if not _peers[pid].connected:
			continue
		if _tgt == 0 or (_tgt > 0 and pid == _tgt) or (_tgt < 0 and pid != -_tgt):
			_send(pid, ch, buf)
	return OK


func _get_packet_script() -> PackedByteArray:
	if _in.is_empty():
		return PackedByteArray()
	return _in.pop_front()[2]


func _get_available_packet_count() -> int:
	return _in.size()


func _get_packet_peer() -> int:
	return _in[0][0] if not _in.is_empty() else 0


func _get_packet_channel() -> int:
	return 0


func _get_packet_mode() -> TransferMode:
	var ch: int = _in[0][1] if not _in.is_empty() else 0
	if ch == 1:
		return TRANSFER_MODE_UNRELIABLE_ORDERED
	if ch == 2:
		return TRANSFER_MODE_UNRELIABLE
	return TRANSFER_MODE_RELIABLE


func _get_max_packet_size() -> int:
	return 1 << 18


func _set_target_peer(pid: int) -> void:
	_tgt = pid


func _set_transfer_mode(m: TransferMode) -> void:
	_mode = m


func _get_transfer_mode() -> TransferMode:
	return _mode


func _set_transfer_channel(c: int) -> void:
	_chan = c


func _get_transfer_channel() -> int:
	return _chan


func _get_unique_id() -> int:
	return _id


func _is_server() -> bool:
	return _srv


func _is_server_relay_supported() -> bool:
	return true


func _get_connection_status() -> ConnectionStatus:
	return _st


func _set_refuse_new_connections(on: bool) -> void:
	_refuse = on


func _is_refusing_new_connections() -> bool:
	return _refuse


func _disconnect_peer(pid: int, force: bool) -> void:
	_drop(pid, not force)


func _close() -> void:
	for pid: int in _peers.keys():
		_drop(pid, false)
	_in.clear()
	_out.clear()
	_st = CONNECTION_DISCONNECTED
