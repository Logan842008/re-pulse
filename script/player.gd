class_name Player
extends CharacterBody2D
# only the owner reads input, the synchronizer sends pos/aim to the other peer

const WALL_LAYER := 1

@export var speed := 260.0
@export var fire_delay := 0.3
@export var boost_fire_delay := 0.12
@export var muzzle_dist := 34.0

var peer_id := 1
var slot := 0
var game: Game

var _cd := 0.0

@onready var pivot: Node2D = $Pivot
@onready var body_size: Vector2 = $CollisionShape2D.shape.size


func _ready() -> void:
	var c := Network.color_of(slot)
	$Body.color = c.darkened(0.55)
	$Edge.default_color = _glow(c, 1.8)
	$Pivot/Gun.color = _glow(c.lightened(0.35), 1.6)
	$NameTag/Label.text = Network.name_of(slot)
	# undo the flipped camera so the name stays upright and above the player
	$NameTag.rotation = game.view_rot()


static func _glow(c: Color, amt: float) -> Color:
	return Color(c.r * amt, c.g * amt, c.b * amt, 1.0)


func _process(_delta: float) -> void:
	var blink := game.is_protected(slot) and Time.get_ticks_msec() % 200 < 100
	modulate.a = 0.35 if blink else 1.0


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_cd -= delta
	pivot.look_at(get_global_mouse_position())
	if not game.fighting:
		velocity = Vector2.ZERO
		return

	# input is screen space, rotate it with the camera so W is always up on my screen
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input.rotated(game.view_rot()) * speed
	move_and_slide()
	_push_out()

	if Input.is_action_pressed("shoot") and _cd <= 0.0:
		_cd = boost_fire_delay if game.is_boosted(slot) else fire_delay
		_shoot()


func respawn(at: Vector2) -> void:
	global_position = at
	velocity = Vector2.ZERO
	_cd = 0.0


# players don't collide (each peer only moves its own), so on overlap each one
# backs off half the overlap. walking into someone pushes them at half speed,
# and move_and_collide stops the push at walls
func _push_out() -> void:
	for other: Player in game.players.get_children():
		if other == self:
			continue
		var off := global_position - other.global_position
		var overlap := body_size - off.abs()
		if overlap.x <= 0.0 or overlap.y <= 0.0:
			continue
		# separate along whichever axis overlaps less
		var push := Vector2(signf(off.x) * overlap.x, 0.0) if overlap.x < overlap.y \
				else Vector2(0.0, signf(off.y) * overlap.y)
		move_and_collide(push * 0.5)


func _shoot() -> void:
	var dir := Vector2.RIGHT.rotated(pivot.global_rotation)
	var origin := global_position + dir * muzzle_dist
	# gun poking into a wall: fire from just in front of the wall instead
	var q := PhysicsRayQueryParameters2D.create(global_position, origin, WALL_LAYER)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit:
		origin = hit.position - dir * 6.0
	game.request_shoot(origin, dir)
