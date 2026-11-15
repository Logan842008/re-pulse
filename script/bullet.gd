class_name Bullet
extends CharacterBody2D

const FLASH_TIME := 0.15
const TRAIL_POINTS := 10

@export var speed := 600.0
@export var max_ricochets := 3
@export var lifetime := 8.0

@export_group("Glow")
@export var unarmed_glow := 1.0
@export var unarmed_alpha := 0.5
@export var armed_glow := 3.0
@export var ricochet_flash := 4.0

var direction := Vector2.RIGHT
var owner_peer_id := 1
var color := Color.WHITE
var game: Game

var ricochets := 0
var _spent := false
var _flash := 0.0

@onready var hitbox: Area2D = $Hitbox
@onready var visual: Node2D = $Visual
@onready var trail: Line2D = $Trail
@onready var spark: CPUParticles2D = $Spark


func _ready() -> void:
	velocity = direction.normalized() * speed
	rotation = velocity.angle()
	$Visual/Placeholder.visible = $Visual/Sprite.texture == null
	_update_glow()
	if not multiplayer.is_server():
		hitbox.monitoring = false


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta / FLASH_TIME, 0.0)
	_update_glow()
	trail.add_point(global_position, 0)
	while trail.get_point_count() > TRAIL_POINTS:
		trail.remove_point(trail.get_point_count() - 1)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_expire()
		return

	var motion := velocity * delta
	for i in 4:
		var collision := move_and_collide(motion)
		if collision == null:
			break
		ricochets += 1
		if ricochets >= max_ricochets:
			_expire()
			return
		var normal := collision.get_normal()
		velocity = velocity.bounce(normal)
		motion = collision.get_remainder().bounce(normal)
		_flash = 1.0
		_spark_at(collision.get_position())
	rotation = velocity.angle()

	if multiplayer.is_server() and ricochets > 0:
		_check_hits()


func _update_glow() -> void:
	var armed := ricochets > 0
	var brightness := (armed_glow if armed else unarmed_glow) + ricochet_flash * _flash
	var tint := color * brightness
	tint.a = 1.0 if armed else unarmed_alpha
	visual.modulate = tint
	trail.modulate = tint


func _spark_at(point: Vector2) -> void:
	spark.global_position = point
	spark.color = Color(color.r * 3.0, color.g * 3.0, color.b * 3.0, 1.0)
	spark.restart()


func _check_hits() -> void:
	for body in hitbox.get_overlapping_bodies():
		if body is Player and body.peer_id != owner_peer_id and not game.is_protected(body.slot):
			game.on_bullet_hit_player(self, body)
			return


func _expire() -> void:
	_spent = true
	hide()
	if multiplayer.is_server():
		queue_free()
