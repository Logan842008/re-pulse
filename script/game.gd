class_name Game
extends Node2D

signal exit_requested

const PLAYER_SCENE := preload("res://scene/player.tscn")
const BULLET_SCENE := preload("res://scene/bullet.tscn")
const PICKUP_SCENE := preload("res://scene/powerup.tscn")

@export var max_hp := 100
@export var bullet_dmg := 20
@export var spawn_prot_time := 1.5

@export_group("Powerups")
@export var heal_amount := 40
@export var boost_time := 4.0
@export var boost_bullets := 2
@export var boost_spread_deg := 10.0
@export var pickup_interval := 8.0
@export var max_pickups := 2

@export_group("Rounds")
@export var start_delay := 3.0
@export var end_delay := 2.5

var hp := [100, 100, 100, 100]
var boost_t := [0.0, 0.0, 0.0, 0.0]
var prot_t := [0.0, 0.0, 0.0, 0.0]
var scores := [0, 0, 0, 0]
var round_num := 0
var fighting := false
var match_over := false
var countdown := 0.0
var round_t := 0.0
var _fight_at := 0
var _fight_t0 := 0
var ms := MatchStats.new()
var _kills := {}

var _started := false
var _loaded := {}
var _spawn_n := 0
var _sid := 0
var _ghosts := {}
var ghosts: Node2D
var _phase: Timer
var _phase_cb: Callable
var _pt: Timer

var map: Map
@onready var players: Node2D = $Players
@onready var bullets: Node2D = $Bullets
@onready var pickups: Node2D = $Powerups
@onready var p_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var b_spawner: MultiplayerSpawner = $BulletSpawner
@onready var ps: MultiplayerSpawner = $PowerupSpawner
@onready var cam: Camera2D = $Camera2D
@onready var hud: Hud = $HUD


func _ready() -> void:
	map = Maps.scene(false, Network.map_id).instantiate()
	map.name = "Map"
	add_child(map)
	move_child(map, 0)
	p_spawner.spawn_function = _spawn_player
	b_spawner.spawn_function = _spawn_bullet
	ghosts = Node2D.new()
	ghosts.name = "Ghosts"
	add_child(ghosts)
	move_child(ghosts, bullets.get_index() + 1)
	ps.spawn_function = _spawn_pickup

	cam.position = map.get_center()
	if map.is_top(Network.my_slot()):
		cam.ignore_rotation = false
		cam.rotation = PI

	hud.setup(self)
	Sfx.music("2d")
	hud.leave_pressed.connect(exit_requested.emit)
	hud.rematch_pressed.connect(_on_rematch)

	if multiplayer.is_server():
		_phase = _make_timer(true, func(): _phase_cb.call())
		_pt = _make_timer(false, _on_pickup_timer)
		_make_timer(false, _send_pings).start(2.0)
	else:
		_client_ready.rpc_id(1)


func _process(delta: float) -> void:
	for s in 4:
		boost_t[s] = maxf(boost_t[s] - delta, 0.0)
		prot_t[s] = maxf(prot_t[s] - delta, 0.0)
	var now := Network.server_msec()
	if _fight_at > 0:
		countdown = maxf((_fight_at - now) / 1000.0, 0.0)
		if now >= _fight_at:
			_fight_t0 = _fight_at
			_fight_at = 0
			_fight()
	if fighting:
		round_t = maxf((now - _fight_t0) / 1000.0, 0.0)


func get_player(pid: int) -> Player:
	return players.get_node_or_null(str(pid)) as Player


func is_boosted(slot: int) -> bool:
	return boost_t[slot] > 0.0


func is_protected(slot: int) -> bool:
	return prot_t[slot] > 0.0


func is_alive(slot: int) -> bool:
	return hp[slot] > 0


func can_hit(op: int, p: Player) -> bool:
	if p.peer_id == op or not is_alive(p.slot) or is_protected(p.slot):
		return false
	return Network.team_of(Network.slot_of(op)) != Network.team_of(p.slot)


func in_play() -> Array:
	return players.get_children().map(func(p: Player) -> int: return p.slot)


func wins_needed() -> int:
	return Network.first_to


func view_rot() -> float:
	return cam.global_rotation


# same trick as 3d, local shot first
func request_shoot(origin: Vector2, dir: Vector2) -> void:
	if multiplayer.is_server():
		_server_shoot(origin, dir, 0)
		return
	_sid += 1
	var me := multiplayer.get_unique_id()
	var dirs := fan(dir, is_boosted(Network.slot_of(me)))
	for i in dirs.size():
		var key := "%d_%d" % [_sid, i]
		var b := _spawn_bullet({"name": "G" + key, "pos": origin, "dir": dirs[i], "owner": me})
		b.ghost = true
		_ghosts[key] = b
		b.tree_exited.connect(func() -> void: _ghosts.erase(key))
		ghosts.add_child(b)
	_server_shoot.rpc_id(1, origin, dir, _sid)


func fan(dir: Vector2, bst: bool) -> Array:
	var n := boost_bullets if bst else 1
	var spread := deg_to_rad(boost_spread_deg)
	var out := []
	for i in n:
		out.append(dir.normalized().rotated((i - (n - 1) / 2.0) * spread))
	return out


func _spawn_player(pid: int) -> Node:
	var p: Player = PLAYER_SCENE.instantiate()
	p.name = str(pid)
	p.peer_id = pid
	p.slot = Network.slot_of(pid)
	p.game = self
	p.position = map.spawn_pos(p.slot)
	p.set_multiplayer_authority(pid)
	return p


func _spawn_bullet(d: Dictionary) -> Node:
	var b: Bullet = BULLET_SCENE.instantiate()
	b.name = d["name"]
	b.position = d["pos"]
	b.dir = d["dir"]
	b.owner_id = d["owner"]
	b.color = Network.color_of(Network.slot_of(d["owner"]))
	b.game = self
	var key := "%d_%d" % [d.get("sid", 0), d.get("i", 0)]
	if d["owner"] == multiplayer.get_unique_id() and _ghosts.has(key):
		var gh: Bullet = _ghosts[key]
		_ghosts.erase(key)
		gh.claimed = true
		b.shadow = true
		b.tree_exiting.connect(gh.queue_free)
	return b


func _spawn_pickup(d: Dictionary) -> Node:
	var pu: Powerup = PICKUP_SCENE.instantiate()
	pu.name = d["name"]
	pu.position = d["pos"]
	pu.kind = d["kind"]
	pu.game = self
	return pu


@rpc("any_peer", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server() or _started:
		return
	_loaded[multiplayer.get_remote_sender_id()] = true
	if _loaded.size() < Network.roster.size() - 1:
		return
	_started = true
	for s: int in Network.slots():
		p_spawner.spawn(Network.roster[s]["pid"])
	_start_match()


func _start_match() -> void:
	scores = [0, 0, 0, 0]
	round_num = 0
	ms.reset_match()
	_send_stats()
	_start_round()


func _start_round() -> void:
	round_num += 1
	ms.reset_round()
	_clear_arena()
	_pt.stop()
	_rpc_round_start.rpc(round_num, scores, Network.first_to, Network.server_msec() + int(start_delay * 1000.0))
	_after(start_delay, _begin_fight)


func _begin_fight() -> void:
	_pt.start(pickup_interval)


func _end_round(winner: int) -> void:
	fighting = false
	_pt.stop()
	_clear_bullets()
	scores[winner] += 1
	ms.history.append(winner)
	_send_stats()
	var over: bool = scores[winner] >= wins_needed()
	_rpc_round_end.rpc(winner, scores, over, Network.server_msec())
	if not over:
		_after(end_delay, _start_round)


func _on_rematch() -> void:
	if multiplayer.is_server() and match_over:
		_start_match()


@rpc("any_peer", "reliable")
func _server_shoot(origin: Vector2, dir: Vector2, sid: int) -> void:
	if not multiplayer.is_server() or not fighting or dir.is_zero_approx():
		return
	var shtr := multiplayer.get_remote_sender_id()
	if shtr == 0:
		shtr = multiplayer.get_unique_id()
	var dirs := fan(dir, is_boosted(Network.slot_of(shtr)))
	for i in dirs.size():
		b_spawner.spawn({
			"name": _next_name("Bullet"),
			"pos": origin,
			"dir": dirs[i],
			"owner": shtr,
			"sid": sid,
			"i": i,
		})


func on_bullet_hit(b: Bullet, p: Player) -> void:
	if not fighting or b.is_queued_for_deletion() or not is_alive(p.slot):
		return
	b.queue_free()
	var new_hp := maxi(hp[p.slot] - bullet_dmg, 0)
	ms.hit(Network.slot_of(b.owner_id), p.slot, bullet_dmg, new_hp == 0)
	_sync_hp.rpc(p.slot, new_hp)
	_send_stats()
	if new_hp == 0:
		_rpc_kill.rpc(Network.slot_of(b.owner_id), p.slot)
		_check_round(Network.team_of(Network.slot_of(b.owner_id)))


func _check_round(by: int) -> void:
	var left := []
	for s: int in in_play():
		var t := Network.team_of(s)
		if is_alive(s) and not left.has(t):
			left.append(t)
	if left.size() <= 1:
		_end_round(left[0] if left.size() == 1 else by)


func on_pickup(pu: Powerup, p: Player) -> void:
	if not fighting or pu.is_queued_for_deletion() or not is_alive(p.slot):
		return
	pu.queue_free()
	match pu.kind:
		Powerup.Kind.HEALTH:
			_sync_hp.rpc(p.slot, mini(hp[p.slot] + heal_amount, max_hp))
		Powerup.Kind.WEAPON:
			_sync_boost.rpc(p.slot, boost_time)


func _on_pickup_timer() -> void:
	if not fighting or pickups.get_child_count() >= max_pickups:
		return
	var used := pickups.get_children().map(func(n: Node2D) -> Vector2: return n.position)
	var spots := map.pickup_spots().filter(func(s: Vector2) -> bool: return not used.has(s))
	if spots.is_empty():
		return
	ps.spawn({
		"name": _next_name("Powerup"),
		"pos": spots.pick_random(),
		"kind": [Powerup.Kind.HEALTH, Powerup.Kind.WEAPON].pick_random(),
	})


func _clear_arena() -> void:
	_clear_bullets()
	for pu in pickups.get_children():
		pu.queue_free()


func _clear_bullets() -> void:
	for b in bullets.get_children():
		b.queue_free()


func _clear_ghosts() -> void:
	for b in ghosts.get_children():
		b.queue_free()


func _next_name(prefix: String) -> String:
	_spawn_n += 1
	return "%s%d" % [prefix, _spawn_n]


func _make_timer(one_shot: bool, cb: Callable) -> Timer:
	var t := Timer.new()
	t.one_shot = one_shot
	t.timeout.connect(cb)
	add_child(t)
	return t


func _after(secs: float, cb: Callable) -> void:
	_phase_cb = cb
	_phase.start(secs)


@rpc("authority", "call_local", "reliable")
func _rpc_round_start(num: int, ns: Array, ft: int, fa: int) -> void:
	_clear_ghosts()
	round_num = num
	scores = ns
	Network.first_to = ft
	fighting = false
	match_over = false
	hp = [max_hp, max_hp, max_hp, max_hp]
	boost_t = [0.0, 0.0, 0.0, 0.0]
	prot_t = [0.0, 0.0, 0.0, 0.0]
	_fight_at = fa if Network.clock_ok() else Network.server_msec() + int(start_delay * 1000.0)
	countdown = maxf((_fight_at - Network.server_msec()) / 1000.0, 0.0)
	_kills.clear()
	Sfx.play("ready", -2.0)
	var me := get_player(multiplayer.get_unique_id())
	if me:
		me.respawn(map.spawn_pos(me.slot))
	hud.hide_rematch()


func _fight() -> void:
	fighting = true
	round_t = 0.0
	prot_t = [spawn_prot_time, spawn_prot_time, spawn_prot_time, spawn_prot_time]
	hud.show_msg("FIGHT!", 0.8)
	Sfx.play("fight", -2.0)


@rpc("authority", "call_local", "reliable")
func _rpc_round_end(winner: int, ns: Array, over: bool, end_at: int) -> void:
	_clear_ghosts()
	fighting = false
	_fight_at = 0
	round_t = maxf((end_at - _fight_t0) / 1000.0, 0.0)
	scores = ns
	match_over = over
	_round_sound(winner, over)
	if not over:
		hud.show_msg(Network.round_text(winner, over), end_delay)
		return
	hud.show_msg("")


@rpc("authority", "call_local", "reliable")
func _sync_hp(slot: int, value: int) -> void:
	var out: bool = value == 0 and hp[slot] > 0
	_hp_sound(slot, value, hp[slot])
	hp[slot] = value
	if out and fighting:
		hud.show_msg(Network.out_text(slot), 1.5)


@rpc("authority", "call_local", "reliable")
func _rpc_kill(by: int, victim: int) -> void:
	hud.feed(by, victim)
	_kill_sound(by)


@rpc("authority", "call_local", "reliable")
func _sync_boost(slot: int, secs: float) -> void:
	boost_t[slot] = secs
	if secs > 0.0:
		if slot == Network.my_slot():
			Sfx.play("boost", -2.0)
		elif _of(slot):
			Sfx.at2d("boost", _of(slot).global_position, -8.0)


func _send_stats() -> void:
	_sync_stats.rpc(ms.stats, ms.history, ms.pings)


@rpc("authority", "call_local", "reliable")
func _sync_stats(s: Array, h: Array, p: Array) -> void:
	ms.stats = s
	ms.history = h
	ms.pings = p


func _send_pings() -> void:
	for s: int in Network.slots():
		var pid: int = Network.roster[s]["pid"]
		if pid != 1:
			_ping.rpc_id(pid, Time.get_ticks_msec())
	_send_stats()


@rpc("authority", "call_remote", "unreliable")
func _ping(t: int) -> void:
	_pong.rpc_id(1, t)


@rpc("any_peer", "call_remote", "unreliable")
func _pong(t: int) -> void:
	var s := Network.slot_of(multiplayer.get_remote_sender_id())
	if multiplayer.is_server() and s >= 0 and s < 4:
		ms.pings[s] = Time.get_ticks_msec() - t


func _hp_sound(slot: int, value: int, was: int) -> void:
	var p := _of(slot)
	if value < was:
		if slot == Network.my_slot():
			Sfx.play("out" if value == 0 else "hurt", -3.0)
		elif p:
			Sfx.at2d("hit", p.global_position, -4.0)
	elif value > was:
		if slot == Network.my_slot():
			Sfx.play("heal", -2.0)
		elif p:
			Sfx.at2d("heal", p.global_position, -8.0)


func _of(slot: int) -> Player:
	for p: Player in players.get_children():
		if p.slot == slot:
			return p
	return null


func match_point() -> bool:
	return wins_needed() > 1 and scores.any(func(v: int) -> bool: return v == wins_needed() - 1)


func _round_sound(winner: int, over: bool) -> void:
	var mine := winner == Network.team_of(Network.my_slot())
	if not over:
		Sfx.play("round_won" if mine else "round_lost", -4.0)
		return
	if not mine:
		Sfx.play("you_lose")
		return
	var flawless := true
	for i in scores.size():
		if i != winner and scores[i] > 0:
			flawless = false
	Sfx.play("flawless" if flawless else "you_win")


func _kill_sound(by: int) -> void:
	var now := Time.get_ticks_msec()
	if by == Network.my_slot():
		var multi := now - int(_kills.get(by, -100000)) < 4000
		Sfx.play("multi_kill" if multi else "kill", 0.0 if multi else -3.0)
	_kills[by] = now
