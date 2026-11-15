class_name Bullet
extends CharacterBody2D
# bounces off the "walls" layer. harmless until the first bounce, then it can
# hit the opponent (not the shooter, not someone spawn protected).
# both peers simulate it but only the server checks hits and frees it.
# sprite should be white and pointing right, it gets tinted

const FLASH_TIME := 0.15
const TRAIL_PTS := 10

@export var speed := 600.0
@export var max_ricochets := 3
@export var lifetime := 8.0 # in case one gets stuck

@export_group("Glow")
@export var unarmed_glow := 1.0
@export var unarmed_alpha := 0.5
@export var armed_glow := 3.0
@export var ricochet_flash := 4.0

var dir := Vector2.RIGHT
var owner_id := 1
var color := Color.WHITE
var game: Game

var bounces := 0
var _dead := false
var _flash := 0.0

@onready var hitbox: Area2D = $Hitbox
@onready var vis: Node2D = $Visual
@onready var trail: Line2D = $Trail
@onready var spark: CPUParticles2D = $Spark


func _ready() -> void:
	velocity = dir.normalized() * speed
	rotation = velocity.angle()
	$Visual/Placeholder.visible = $Visual/Sprite.texture == null
	_update_glow()
	if not multiplayer.is_server():
		hitbox.monitoring = false


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta / FLASH_TIME, 0.0)
	_update_glow()
	# trail is top_level, so its points are in world space
	trail.add_point(global_position, 0)
	while trail.get_point_count() > TRAIL_PTS:
		trail.remove_point(trail.get_point_count() - 1)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_expire()
		return

	var motion := velocity * delta
	# a few passes so clipping a corner can bounce twice in one frame
	for i in 4:
		var col := move_and_collide(motion)
		if col == null:
			break
		bounces += 1
		if bounces >= max_ricochets:
			_expire()
			return
		var n := col.get_normal()
		velocity = velocity.bounce(n)
		motion = col.get_remainder().bounce(n)
		_flash = 1.0
		_spark_at(col.get_position())
	rotation = velocity.angle()

	if multiplayer.is_server() and bounces > 0:
		_check_hits()


func _update_glow() -> void:
	var armed := bounces > 0
	var tint := color * ((armed_glow if armed else unarmed_glow) + ricochet_flash * _flash)
	tint.a = 1.0 if armed else unarmed_alpha
	vis.modulate = tint
	trail.modulate = tint


func _spark_at(p: Vector2) -> void:
	spark.global_position = p
	spark.color = Color(color.r * 3.0, color.g * 3.0, color.b * 3.0, 1.0)
	spark.restart()


func _check_hits() -> void:
	for body in hitbox.get_overlapping_bodies():
		if body is Player and body.peer_id != owner_id and not game.is_protected(body.slot):
			game.on_bullet_hit(self, body)
			return


func _expire() -> void:
	_dead = true
	hide()
	# only the server frees it, the spawner then removes the client's copy
	if multiplayer.is_server():
		queue_free()
