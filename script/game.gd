class_name Game
extends Node2D

signal exit_requested

const PLAYER_SCENE := preload("res://scene/player.tscn")
const BULLET_SCENE := preload("res://scene/bullet.tscn")
const POWERUP_SCENE := preload("res://scene/powerup.tscn")

@export var max_health := 100
@export var bullet_damage := 20
@export var spawn_protection_time := 1.5

@export_group("Powerups")
@export var health_pickup_amount := 40
@export var weapon_boost_duration := 5.0
@export var weapon_boost_bullets := 3
@export var weapon_boost_spread_degrees := 12.0
@export var powerup_spawn_interval := 8.0
@export var max_powerups := 2

@export_group("Rounds")
@export var round_start_delay := 3.0
@export var round_end_delay := 2.5

var health := [100, 100]
var boost_left := [0.0, 0.0]
var protection_left := [0.0, 0.0]
var scores := [0, 0]
var round_number := 0
var round_active := false
var match_over := false
var countdown_left := 0.0

var _started := false
var _spawn_counter := 0
var _phase_timer: Timer
var _phase_callback: Callable
var _powerup_timer: Timer

@onready var map: Map = $Map
@onready var players: Node2D = $Players
@onready var bullets: Node2D = $Bullets
@onready var powerups: Node2D = $Powerups
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var bullet_spawner: MultiplayerSpawner = $BulletSpawner
@onready var powerup_spawner: MultiplayerSpawner = $PowerupSpawner
@onready var camera: Camera2D = $Camera2D
@onready var hud: Hud = $HUD


func _ready() -> void:
	player_spawner.spawn_function = _spawn_player
	bullet_spawner.spawn_function = _spawn_bullet
	powerup_spawner.spawn_function = _spawn_powerup

	camera.position = map.get_center()
	if Network.local_slot() == 1:
		camera.ignore_rotation = false
		camera.rotation = PI

	hud.setup(self)
	hud.leave_pressed.connect(exit_requested.emit)
	hud.rematch_pressed.connect(_on_rematch_pressed)

	if multiplayer.is_server():
		_phase_timer = _make_timer(true, _on_phase_timer_timeout)
		_powerup_timer = _make_timer(false, _on_powerup_timer_timeout)
	else:
		_client_ready.rpc_id(1)


func _process(delta: float) -> void:
	for slot in 2:
		boost_left[slot] = maxf(boost_left[slot] - delta, 0.0)
		protection_left[slot] = maxf(protection_left[slot] - delta, 0.0)
	countdown_left = maxf(countdown_left - delta, 0.0)


func get_player(peer_id: int) -> Player:
	return players.get_node_or_null(str(peer_id)) as Player


func is_boosted(slot: int) -> bool:
	return boost_left[slot] > 0.0


func is_protected(slot: int) -> bool:
	return protection_left[slot] > 0.0


func rounds_to_win() -> int:
	return ceili(Network.best_of / 2.0)


func view_rotation() -> float:
	return camera.global_rotation


func request_shoot(origin: Vector2, direction: Vector2) -> void:
	if multiplayer.is_server():
		_server_shoot(origin, direction)
	else:
		_server_shoot.rpc_id(1, origin, direction)


func _spawn_player(peer_id: int) -> Node:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.peer_id = peer_id
	player.slot = Network.slot_of(peer_id)
	player.game = self
	player.position = map.get_spawn_position(player.slot)
	player.set_multiplayer_authority(peer_id)
	return player


func _spawn_bullet(data: Dictionary) -> Node:
	var bullet: Bullet = BULLET_SCENE.instantiate()
	bullet.name = data["name"]
	bullet.position = data["position"]
	bullet.direction = data["direction"]
	bullet.owner_peer_id = data["owner"]
	bullet.color = Network.get_color(Network.slot_of(data["owner"]))
	bullet.game = self
	return bullet


func _spawn_powerup(data: Dictionary) -> Node:
	var powerup: Powerup = POWERUP_SCENE.instantiate()
	powerup.name = data["name"]
	powerup.position = data["position"]
	powerup.kind = data["kind"]
	powerup.game = self
	return powerup


@rpc("any_peer", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server() or _started:
		return
	_started = true
	player_spawner.spawn(1)
	player_spawner.spawn(multiplayer.get_remote_sender_id())
	_start_match()


func _start_match() -> void:
	scores = [0, 0]
	round_number = 0
	_start_round()


func _start_round() -> void:
	round_number += 1
	_clear_arena()
	_powerup_timer.stop()
	_round_starting.rpc(round_number, scores, Network.best_of)
	_after(round_start_delay, _begin_fighting)


func _begin_fighting() -> void:
	_round_live.rpc()
	_powerup_timer.start(powerup_spawn_interval)


func _end_round(winner_slot: int) -> void:
	round_active = false
	_powerup_timer.stop()
	_clear_bullets()
	scores[winner_slot] += 1
	var is_match_over: bool = scores[winner_slot] >= rounds_to_win()
	_round_ended.rpc(winner_slot, scores, is_match_over)
	if not is_match_over:
		_after(round_end_delay, _start_round)


func _on_rematch_pressed() -> void:
	if multiplayer.is_server() and match_over:
		_start_match()


@rpc("any_peer", "reliable")
func _server_shoot(origin: Vector2, direction: Vector2) -> void:
	if not multiplayer.is_server() or not round_active or direction.is_zero_approx():
		return
	var shooter := multiplayer.get_remote_sender_id()
	if shooter == 0:
		shooter = multiplayer.get_unique_id()
	var count := weapon_boost_bullets if is_boosted(Network.slot_of(shooter)) else 1
	var spread := deg_to_rad(weapon_boost_spread_degrees)
	for i in count:
		var offset := (i - (count - 1) / 2.0) * spread
		bullet_spawner.spawn({
			"name": _next_name("Bullet"),
			"position": origin,
			"direction": direction.normalized().rotated(offset),
			"owner": shooter,
		})


func on_bullet_hit_player(bullet: Bullet, player: Player) -> void:
	if not round_active or bullet.is_queued_for_deletion():
		return
	bullet.queue_free()
	var new_health := maxi(health[player.slot] - bullet_damage, 0)
	_sync_health.rpc(player.slot, new_health)
	if new_health == 0:
		_end_round(1 - player.slot)


func on_powerup_touched(powerup: Powerup, player: Player) -> void:
	if not round_active or powerup.is_queued_for_deletion():
		return
	powerup.queue_free()
	match powerup.kind:
		Powerup.Kind.HEALTH:
			_sync_health.rpc(player.slot, mini(health[player.slot] + health_pickup_amount, max_health))
		Powerup.Kind.WEAPON:
			_sync_boost.rpc(player.slot, weapon_boost_duration)


func _on_powerup_timer_timeout() -> void:
	if not round_active or powerups.get_child_count() >= max_powerups:
		return
	var taken := powerups.get_children().map(func(p: Node2D) -> Vector2: return p.position)
	var free_spots := map.get_powerup_positions().filter(func(spot: Vector2) -> bool: return not taken.has(spot))
	if free_spots.is_empty():
		return
	powerup_spawner.spawn({
		"name": _next_name("Powerup"),
		"position": free_spots.pick_random(),
		"kind": [Powerup.Kind.HEALTH, Powerup.Kind.WEAPON].pick_random(),
	})


func _clear_arena() -> void:
	_clear_bullets()
	for powerup in powerups.get_children():
		powerup.queue_free()


func _clear_bullets() -> void:
	for bullet in bullets.get_children():
		bullet.queue_free()


func _next_name(prefix: String) -> String:
	_spawn_counter += 1
	return "%s%d" % [prefix, _spawn_counter]


func _make_timer(one_shot: bool, callback: Callable) -> Timer:
	var timer := Timer.new()
	timer.one_shot = one_shot
	timer.timeout.connect(callback)
	add_child(timer)
	return timer


func _after(seconds: float, callback: Callable) -> void:
	_phase_callback = callback
	_phase_timer.start(seconds)


func _on_phase_timer_timeout() -> void:
	_phase_callback.call()


@rpc("authority", "call_local", "reliable")
func _round_starting(number: int, new_scores: Array, best_of: int) -> void:
	round_number = number
	scores = new_scores
	Network.best_of = best_of
	round_active = false
	match_over = false
	health = [max_health, max_health]
	boost_left = [0.0, 0.0]
	protection_left = [0.0, 0.0]
	countdown_left = round_start_delay
	var me := get_player(multiplayer.get_unique_id())
	if me:
		me.respawn(map.get_spawn_position(me.slot))
	hud.hide_rematch()


@rpc("authority", "call_local", "reliable")
func _round_live() -> void:
	round_active = true
	protection_left = [spawn_protection_time, spawn_protection_time]
	hud.show_message("FIGHT!", 0.8)


@rpc("authority", "call_local", "reliable")
func _round_ended(winner_slot: int, new_scores: Array, is_match_over: bool) -> void:
	round_active = false
	scores = new_scores
	match_over = is_match_over
	var won := winner_slot == Network.local_slot()
	if not is_match_over:
		hud.show_message("ROUND WON" if won else "ROUND LOST", round_end_delay)
		return
	var text := "YOU WIN THE MATCH!" if won else "%s WINS THE MATCH" % Network.get_player_name(winner_slot)
	if multiplayer.is_server():
		hud.show_rematch()
	else:
		text += "\nWaiting for the host to start a rematch..."
	hud.show_message(text)


@rpc("authority", "call_local", "reliable")
func _sync_health(slot: int, value: int) -> void:
	health[slot] = value


@rpc("authority", "call_local", "reliable")
func _sync_boost(slot: int, seconds: float) -> void:
	boost_left[slot] = seconds
