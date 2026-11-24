class_name Game3D
extends Node3D

signal exit_requested

const PLAYER_SCENE := preload("res://scene/player_3d.tscn")

@export var max_hp := 200
@export var spawn_prot_time := 1.5

@export_group("Pickups")
@export var heal_amount := 80
@export var health_respawn := 15.0
@export var gun_interval := 6.0
@export var max_guns := 3

@export_group("Rounds")
@export var start_delay := 3.0
@export var end_delay := 2.5

var hp := [200, 200, 200, 200]
var prot_t := [0.0, 0.0, 0.0, 0.0]
var gun := [0, 0, 0, 0]
var ammo := [-1, -1, -1, -1]
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
var flip := false

var _started := false
var _loaded := {}
var _spawn_n := 0
var _ls := {}
var _budget := {}
var _sid := 0
var _ghosts := {}
var ghosts: Node3D
var _pickups: Array[Pickup3D] = []
var _hn := 0
var _rt: Array[float] = []
var _gun_t := 0.0
var _phase: Timer
var _phase_cb: Callable

var arena: ArenaMap
@onready var players: Node3D = $Players
@onready var bullets: Node3D = $Bullets
@onready var props: Node3D = $Props
@onready var p_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var b_spawner: MultiplayerSpawner = $BulletSpawner
@onready var hud: Hud3D = $HUD


func _ready() -> void:
	arena = Maps.scene(true, Network.map_id).instantiate()
	arena.name = "Arena"
	arena.show_markers = false
	add_child(arena)
	move_child(arena, 0)
	p_spawner.spawn_function = _spawn_player
	b_spawner.spawn_function = _spawn_bullet
	ghosts = Node3D.new()
	ghosts.name = "Ghosts"
	add_child(ghosts)
	hud.setup(self)
	Sfx.music("3d")
	hud.leave_pressed.connect(exit_requested.emit)
	hud.rematch_pressed.connect(_on_rematch)

	if multiplayer.is_server():
		_phase = Timer.new()
		_phase.one_shot = true
		_phase.timeout.connect(func(): _phase_cb.call())
		add_child(_phase)
		var pt := Timer.new()
		pt.wait_time = 2.0
		pt.timeout.connect(_send_pings)
		add_child(pt)
		pt.start()
	else:
		_client_ready.rpc_id(1)


func _process(delta: float) -> void:
	for s in 4:
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


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not fighting:
		return
	for i in _pickups.size():
		var pu := _pickups[i]
		if pu.kind == Pickup3D.NONE:
			if i < _hn:
				_rt[i] -= delta
				if _rt[i] <= 0.0:
					_sync_pickup.rpc(i, Pickup3D.HEALTH)
			continue
		for p in pu.touching():
			if _take(pu, p):
				_rt[i] = health_respawn
				_sync_pickup.rpc(i, Pickup3D.NONE)
				break

	_gun_t -= delta
	if _gun_t <= 0.0:
		_gun_t = gun_interval
		_drop_gun()


func get_player(pid: int) -> Player3D:
	return players.get_node_or_null(str(pid)) as Player3D


func me() -> Player3D:
	return get_player(multiplayer.get_unique_id())


func is_protected(slot: int) -> bool:
	return prot_t[slot] > 0.0


func is_alive(slot: int) -> bool:
	return hp[slot] > 0


func can_hit(op: int, p: Player3D) -> bool:
	if p.peer_id == op or not is_alive(p.slot) or is_protected(p.slot):
		return false
	return Network.team_of(Network.slot_of(op)) != Network.team_of(p.slot)


func in_play() -> Array:
	return players.get_children().map(func(p: Player3D) -> int: return p.slot)


func wins_needed() -> int:
	return Network.first_to


func spawn_xf(slot: int) -> Transform3D:
	var sides := arena.spawns(Network.mode, flip)
	var i := Network.spawn_index(slot)
	if Network.mode == "2v2":
		return sides[i / 2][i % 2]
	return sides[i % sides.size()][0]


# draw our shot now, hide the host's copy when it gets here
func request_fire(origin: Vector3, dir: Vector3) -> void:
	var sd := randi()
	if multiplayer.is_server():
		_server_fire(origin, dir, 0, sd)
		return
	_sid += 1
	var me := multiplayer.get_unique_id()
	var w: int = gun[Network.slot_of(me)]
	var dirs := pellets(dir, Weapons.LIST[w], sd)
	for i in dirs.size():
		var key := "%d_%d" % [_sid, i]
		var b := _spawn_bullet({"name": "G" + key, "pos": origin, "dir": dirs[i], "owner": me, "w": w})
		b.ghost = true
		_ghosts[key] = b
		b.tree_exited.connect(func() -> void: _ghosts.erase(key))
		ghosts.add_child(b)
	_server_fire.rpc_id(1, origin, dir, _sid, sd)


static func pellets(dir: Vector3, g: Dictionary, sd: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	dir = dir.normalized()
	var side := dir.cross(Vector3.UP).normalized() if absf(dir.y) < 0.99 else Vector3.RIGHT
	var up := side.cross(dir)
	var cone := tan(deg_to_rad(g["spread"]))
	var out := []
	for i in g["pellets"]:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * cone
		out.append((dir + side * cos(ang) * r + up * sin(ang) * r).normalized())
	return out


func _spawn_player(pid: int) -> Node:
	var p: Player3D = PLAYER_SCENE.instantiate()
	p.name = str(pid)
	p.peer_id = pid
	p.slot = Network.slot_of(pid)
	p.game = self
	p.position = spawn_xf(p.slot).origin
	p.set_multiplayer_authority(pid)
	return p


func _spawn_bullet(d: Dictionary) -> Node:
	var b := Bullet3D.new()
	b.name = d["name"]
	b.position = d["pos"]
	b.dir = d["dir"]
	b.owner_id = d["owner"]
	b.weapon = d["w"]
	b.color = Network.color_of(Network.slot_of(d["owner"]))
	b.game = self
	var key := "%d_%d" % [d.get("sid", 0), d.get("i", 0)]
	if d["owner"] == multiplayer.get_unique_id() and _ghosts.has(key):
		var gh: Bullet3D = _ghosts[key]
		_ghosts.erase(key)
		gh.claimed = true
		b.shadow = true
		b.tree_exiting.connect(gh.queue_free)
	return b


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
	_clear_bullets()
	_rpc_round_start.rpc(round_num, scores, Network.first_to, randf() < 0.5, Network.server_msec() + int(start_delay * 1000.0))
	_after(start_delay, _begin_fight)


func _begin_fight() -> void:
	_gun_t = 1.0


func _end_round(winner: int) -> void:
	fighting = false
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


func _after(secs: float, cb: Callable) -> void:
	_phase_cb = cb
	_phase.start(secs)


@rpc("any_peer", "reliable")
func _server_fire(origin: Vector3, dir: Vector3, sid: int, sd: int) -> void:
	if not multiplayer.is_server() or not fighting or dir.is_zero_approx():
		return
	var pid := multiplayer.get_remote_sender_id()
	if pid == 0:
		pid = 1
	var p := get_player(pid)
	if p == null or not is_alive(p.slot):
		return
	var s := p.slot
	var g: Dictionary = Weapons.LIST[gun[s]]
	var now := Time.get_ticks_msec()
	var bud := minf(float(_budget.get(pid, 2.0)) + (now - int(_ls.get(pid, 0))) / (g["delay"] * 1000.0), 2.0)
	if bud < 0.9:
		return
	if origin.distance_to(p.global_position + Vector3(0, 1.4, 0)) > 7.0:
		return
	_budget[pid] = bud - 1.0
	_ls[pid] = now

	var dirs := pellets(dir, g, sd)
	for i in dirs.size():
		b_spawner.spawn({
			"name": _next_name(),
			"pos": origin,
			"dir": dirs[i],
			"owner": pid,
			"w": gun[s],
			"sid": sid,
			"i": i,
		})

	if ammo[s] > 0:
		var left: int = ammo[s] - 1
		_sync_gun.rpc(s, 0 if left == 0 else gun[s], -1 if left == 0 else left)


func on_bullet_hit(b: Bullet3D, p: Player3D) -> void:
	if not fighting or b.is_queued_for_deletion() or not is_alive(p.slot):
		return
	b.queue_free()
	var by := Network.slot_of(b.owner_id)
	var z := p.zone(b.global_position.y)
	var g: Dictionary = Weapons.LIST[b.weapon]
	var mult: float = g["head"] if z == 0 else g["legs"] if z == 2 else 1.0
	var dmg := roundi(b.dmg * mult)
	var v := maxi(hp[p.slot] - dmg, 0)
	ms.hit(by, p.slot, dmg, v == 0, z)
	_sync_hp.rpc(p.slot, v, by, z)
	_send_stats()
	if v == 0:
		_rpc_kill.rpc(by, p.slot, b.weapon, z == 0, ms.report(by, p.slot), ms.report(p.slot, by))
		_check_round(Network.team_of(by))


func _check_round(by: int) -> void:
	var left := []
	for s: int in in_play():
		var t := Network.team_of(s)
		if is_alive(s) and not left.has(t):
			left.append(t)
	if left.size() <= 1:
		_end_round(left[0] if left.size() == 1 else by)


func _take(pu: Pickup3D, p: Player3D) -> bool:
	if hp[p.slot] <= 0:
		return false
	if pu.kind == Pickup3D.HEALTH:
		if hp[p.slot] >= max_hp:
			return false
		_sync_hp.rpc(p.slot, mini(hp[p.slot] + heal_amount, max_hp), -1, 1)
		return true
	_sync_gun.rpc(p.slot, pu.kind, Weapons.LIST[pu.kind]["ammo"])
	return true


func _drop_gun() -> void:
	var free: Array[int] = []
	var out := 0
	for i in range(_hn, _pickups.size()):
		if _pickups[i].kind == Pickup3D.NONE:
			free.append(i)
		else:
			out += 1
	if out >= max_guns or free.is_empty():
		return
	_sync_pickup.rpc(free.pick_random(), randi_range(1, Weapons.LIST.size() - 1))


func _build_pickups() -> void:
	for p in _pickups:
		p.queue_free()
	_pickups.clear()
	_rt.clear()
	var health := arena.pickup_spots(Network.mode, flip)
	_hn = health.size()
	for pos in health + arena.gun_spots(Network.mode):
		var p := Pickup3D.new()
		p.name = "Pickup%d" % _pickups.size()
		p.kind = Pickup3D.HEALTH if _pickups.size() < _hn else Pickup3D.NONE
		props.add_child(p)
		p.global_position = pos
		_pickups.append(p)
		_rt.append(0.0)


func _clear_bullets() -> void:
	for b in bullets.get_children():
		b.queue_free()


func _clear_ghosts() -> void:
	for b in ghosts.get_children():
		b.queue_free()


func _next_name() -> String:
	_spawn_n += 1
	return "Pulse%d" % _spawn_n


@rpc("authority", "call_local", "reliable")
func _rpc_round_start(num: int, ns: Array, ft: int, nf: bool, fa: int) -> void:
	_clear_ghosts()
	round_num = num
	scores = ns
	Network.first_to = ft
	flip = nf
	fighting = false
	match_over = false
	hp = [max_hp, max_hp, max_hp, max_hp]
	prot_t = [0.0, 0.0, 0.0, 0.0]
	gun = [0, 0, 0, 0]
	ammo = [-1, -1, -1, -1]
	_fight_at = fa if Network.clock_ok() else Network.server_msec() + int(start_delay * 1000.0)
	countdown = maxf((_fight_at - Network.server_msec()) / 1000.0, 0.0)
	_kills.clear()
	Sfx.play("ready", -2.0)
	_build_pickups()
	var p := me()
	if p:
		p.place(spawn_xf(p.slot))
	hud.hide_rematch()
	hud.capture()


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
	hud.release()


@rpc("authority", "call_local", "reliable")
func _sync_hp(slot: int, value: int, by: int, zone: int) -> void:
	var msl := Network.my_slot()
	if value < hp[slot]:
		if slot == msl:
			hud.hurt()
			Sfx.play("out" if value == 0 else "hurt", -3.0)
		elif by == msl:
			hud.hit_marker(value == 0, zone == 0)
			Sfx.play("headshot" if zone == 0 else "hit", -2.0)
		if value == 0 and fighting:
			hud.show_msg(Network.out_text(slot), 1.5)
	elif value > hp[slot]:
		var p := _of(slot)
		if slot == msl:
			Sfx.play("heal", -2.0)
		elif p:
			Sfx.at3d("heal", p.global_position + Vector3(0, 1, 0), -8.0)
	hp[slot] = value


@rpc("authority", "call_local", "reliable")
func _rpc_kill(by: int, victim: int, w: int, head: bool, taken: Array, dealt: Array) -> void:
	hud.feed(by, victim, w, head)
	_kill_sound(by)
	if victim == Network.my_slot():
		hud.killed_by(by, w, head, taken, dealt)


@rpc("authority", "call_local", "reliable")
func _sync_gun(slot: int, w: int, left: int) -> void:
	if w != gun[slot] and w != 0:
		if slot == Network.my_slot():
			hud.show_msg(Weapons.LIST[w]["name"], 1.0)
			Sfx.play("pickup", -2.0)
		elif _of(slot):
			Sfx.at3d("pickup", _of(slot).global_position + Vector3(0, 1, 0), -8.0)
	gun[slot] = w
	ammo[slot] = left


@rpc("authority", "call_local", "reliable")
func _sync_pickup(i: int, kind: int) -> void:
	if i < _pickups.size():
		_pickups[i].kind = kind


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


func _of(slot: int) -> Player3D:
	for p: Player3D in players.get_children():
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
