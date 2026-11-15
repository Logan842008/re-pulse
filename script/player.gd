class_name Player
extends CharacterBody2D

const WALL_LAYER := 1

@export var speed := 260.0
@export var fire_interval := 0.3 ## time between each shot
@export var boosted_fire_interval := 0.12 ## time between with booster
@export var muzzle_distance := 34.0

var peer_id := 1
var slot := 0
var game: Game

var _cooldown := 0.0

@onready var pivot: Node2D = $Pivot
@onready var body_size: Vector2 = $CollisionShape2D.shape.size


func _ready() -> void:
	var color := Network.get_color(slot)
	$Body.color = color
	$Pivot/Gun.color = color.lightened(0.5)
	$NameTag/Label.text = Network.get_player_name(slot)
<<<<<<< Updated upstream
	# Counter the flipped camera so the name reads upright, above the player on screen.
=======
>>>>>>> Stashed changes
	$NameTag.rotation = game.view_rotation()


func _process(_delta: float) -> void:
<<<<<<< Updated upstream
	# Blink while spawn protection is on.
=======
>>>>>>> Stashed changes
	var blink_off := game.is_protected(slot) and Time.get_ticks_msec() % 200 < 100
	modulate.a = 0.35 if blink_off else 1.0


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_cooldown -= delta
	pivot.look_at(get_global_mouse_position())
	if not game.round_active:
		velocity = Vector2.ZERO
		return

<<<<<<< Updated upstream
	# Input is in screen space; turn it with the camera so W is always "up on my screen".
=======
>>>>>>> Stashed changes
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input.rotated(game.view_rotation()) * speed
	move_and_slide()
	_push_out_of_opponent()

	if Input.is_action_pressed("shoot") and _cooldown <= 0.0:
		_cooldown = boosted_fire_interval if game.is_boosted(slot) else fire_interval
		_shoot()


func respawn(at: Vector2) -> void:
	global_position = at
	velocity = Vector2.ZERO
	_cooldown = 0.0

## prevent overlap
func _push_out_of_opponent() -> void:
	for other: Player in game.players.get_children():
		if other == self:
			continue
		var offset := global_position - other.global_position
		var overlap := body_size - offset.abs()
		if overlap.x <= 0.0 or overlap.y <= 0.0:
			continue
<<<<<<< Updated upstream
		# Separate along whichever axis overlaps least.
=======
>>>>>>> Stashed changes
		var push := Vector2(signf(offset.x) * overlap.x, 0.0) if overlap.x < overlap.y \
				else Vector2(0.0, signf(offset.y) * overlap.y)
		move_and_collide(push * 0.5)


func _shoot() -> void:
	var direction := Vector2.RIGHT.rotated(pivot.global_rotation)
	var origin := global_position + direction * muzzle_distance
<<<<<<< Updated upstream
	# If the gun pokes into a wall, fire from just in front of the wall instead.
=======
	# prevent overlap
>>>>>>> Stashed changes
	var query := PhysicsRayQueryParameters2D.create(global_position, origin, WALL_LAYER)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit:
		origin = hit.position - direction * 6.0
	game.request_shoot(origin, direction)
