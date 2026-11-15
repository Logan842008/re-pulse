class_name Game
extends Node2D
# server runs the match (spawns, damage, score) and tells the client over rpc.
# each peer only moves its own player

signal exit_requested

const PLAYER_SCENE := preload("res://scene/player.tscn")
const BULLET_SCENE := preload("res://scene/bullet.tscn")
const PICKUP_SCENE := preload("res://scene/powerup.tscn")

@export var max_hp := 100
@export var bullet_dmg := 20
@export var spawn_prot_time := 1.5 # bullets pass through you for this long after FIGHT!

@export_group("Powerups")
@export var heal_amount := 40
@export var boost_time := 5.0
@export var boost_bullets := 3
@export var boost_spread_deg := 12.0
@export var pickup_interval := 8.0
@export var max_pickups := 2

@export_group("Rounds")
@export var start_delay := 3.0
@export var end_delay := 2.5

# indexed by slot (0 = host/bottom, 1 = client/top), server mirrors to client
var hp := [100, 100]
var boost_t := [0.0, 0.0]
var prot_t := [0.0, 0.0]
var scores := [0, 0]
var round_num := 0
var fighting := false
var match_over := false
var countdown := 0.0

var _started := false
var _spawn_n := 0
var _phase: Timer
var _phase_cb: Callable
var _pickup_timer: Timer

@onready var map: Map = $Map
@onready var players: Node2D = $Players
@onready var bullets: Node2D = $Bullets
@onready var pickups: Node2D = $Powerups
@onready var p_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var b_spawner: MultiplayerSpawner = $BulletSpawner
@onready var pu_spawner: MultiplayerSpawner = $PowerupSpawner
@onready var cam: Camera2D = $Camera2D
@onready var hud: Hud = $HUD


func _ready() -> void:
	p_spawner.spawn_function = _spawn_player
	b_spawner.spawn_function = _spawn_bullet
	pu_spawner.spawn_function = _spawn_pickup

	# everyone sees themselves at the bottom, so the top player's camera is
	# flipped 180 (player.gd rotates the input to match)
	cam.position = map.get_center()
	if Network.my_slot() == 1:
		cam.ignore_rotation = false
		cam.rotation = PI

	hud.setup(self)
	hud.leave_pressed.connect(exit_requested.emit)
	hud.rematch_pressed.connect(_on_rematch)

	if multiplayer.is_server():
		_phase = _make_timer(true, func(): _phase_cb.call())
		_pickup_timer = _make_timer(false, _on_pickup_timer)
	else:
		# tell the host we're loaded, otherwise its spawns/rpcs can show up
		# before our arena exists
		_client_ready.rpc_id(1)


func _process(delta: float) -> void:
	for s in 2:
		boost_t[s] = maxf(boost_t[s] - delta, 0.0)
		prot_t[s] = maxf(prot_t[s] - delta, 0.0)
	countdown = maxf(countdown - delta, 0.0)


func get_player(pid: int) -> Player:
	return players.get_node_or_null(str(pid)) as Player


func is_boosted(slot: int) -> bool:
	return boost_t[slot] > 0.0


func is_protected(slot: int) -> bool:
	return prot_t[slot] > 0.0


func wins_needed() -> int:
	return ceili(Network.best_of / 2.0)


func view_rot() -> float:
	return cam.global_rotation


func request_shoot(origin: Vector2, dir: Vector2) -> void:
	if multiplayer.is_server():
		_server_shoot(origin, dir)
	else:
		_server_shoot.rpc_id(1, origin, dir)


# spawn functions run on both peers, the spawners replicate the server's calls

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
	_started = true
	p_spawner.spawn(1)
	p_spawner.spawn(multiplayer.get_remote_sender_id())
	_start_match()


func _start_match() -> void:
	scores = [0, 0]
	round_num = 0
	_start_round()


func _start_round() -> void:
	round_num += 1
	_clear_arena()
	_pickup_timer.stop()
	_rpc_round_start.rpc(round_num, scores, Network.best_of)
	_after(start_delay, _begin_fight)


func _begin_fight() -> void:
	_rpc_fight.rpc()
	_pickup_timer.start(pickup_interval)


func _end_round(winner: int) -> void:
	fighting = false
	_pickup_timer.stop()
	_clear_bullets()
	scores[winner] += 1
	var over: bool = scores[winner] >= wins_needed()
	_rpc_round_end.rpc(winner, scores, over)
	if not over:
		_after(end_delay, _start_round)


func _on_rematch() -> void:
	if multiplayer.is_server() and match_over:
		_start_match()


@rpc("any_peer", "reliable")
func _server_shoot(origin: Vector2, dir: Vector2) -> void:
	if not multiplayer.is_server() or not fighting or dir.is_zero_approx():
		return
	var shooter := multiplayer.get_remote_sender_id()
	if shooter == 0: # 0 means the host called this directly, not over rpc
		shooter = multiplayer.get_unique_id()
	var n := boost_bullets if is_boosted(Network.slot_of(shooter)) else 1
	var spread := deg_to_rad(boost_spread_deg)
	for i in n:
		var off := (i - (n - 1) / 2.0) * spread # fan centred on the aim
		b_spawner.spawn({
			"name": _next_name("Bullet"),
			"pos": origin,
			"dir": dir.normalized().rotated(off),
			"owner": shooter,
		})


func on_bullet_hit(b: Bullet, p: Player) -> void:
	if not fighting or b.is_queued_for_deletion():
		return
	b.queue_free()
	var new_hp := maxi(hp[p.slot] - bullet_dmg, 0)
	_sync_hp.rpc(p.slot, new_hp)
	if new_hp == 0:
		_end_round(1 - p.slot)


func on_pickup(pu: Powerup, p: Player) -> void:
	# both players can touch it in the same physics frame, first call wins
	if not fighting or pu.is_queued_for_deletion():
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
	pu_spawner.spawn({
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
func _rpc_round_start(num: int, new_scores: Array, best_of: int) -> void:
	round_num = num
	scores = new_scores
	Network.best_of = best_of
	fighting = false
	match_over = false
	hp = [max_hp, max_hp]
	boost_t = [0.0, 0.0]
	prot_t = [0.0, 0.0]
	countdown = start_delay
	var me := get_player(multiplayer.get_unique_id())
	if me:
		me.respawn(map.spawn_pos(me.slot))
	hud.hide_rematch()


@rpc("authority", "call_local", "reliable")
func _rpc_fight() -> void:
	fighting = true
	prot_t = [spawn_prot_time, spawn_prot_time]
	hud.show_msg("FIGHT!", 0.8)


@rpc("authority", "call_local", "reliable")
func _rpc_round_end(winner: int, new_scores: Array, over: bool) -> void:
	fighting = false
	scores = new_scores
	match_over = over
	var won := winner == Network.my_slot()
	if not over:
		hud.show_msg("ROUND WON" if won else "ROUND LOST", end_delay)
		return
	var txt := "YOU WIN THE MATCH!" if won else "%s WINS THE MATCH" % Network.name_of(winner)
	if multiplayer.is_server():
		hud.show_rematch()
	else:
		txt += "\nWaiting for the host to start a rematch..."
	hud.show_msg(txt)


@rpc("authority", "call_local", "reliable")
func _sync_hp(slot: int, value: int) -> void:
	hp[slot] = value


@rpc("authority", "call_local", "reliable")
func _sync_boost(slot: int, secs: float) -> void:
	boost_t[slot] = secs
