class_name Bullet
extends CharacterBody2D

const FLASH_TIME := 0.15
const TRAIL_PTS := 10

@export var speed := 600.0
@export var max_ricochets := 3
@export var lifetime := 8.0

@export_group("Glow")
@export var unarmed_glow := 1.0
@export var unarmed_alpha := 0.5
@export var armed_glow := 3.0
@export var ricochet_flash := 4.0

var dir := Vector2.RIGHT
var owner_id := 1
var color := Color.WHITE
var game: Game
var ghost := false
var claimed := false
var shadow := false
var _age := 0.0

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
	if is_inside_tree() and not shadow:
		Sfx.at2d("shot_0", global_position, -6.0)
	$Visual/Placeholder.visible = $Visual/Sprite.texture == null
	_update_glow()
	if not multiplayer.is_server() or ghost:
		hitbox.monitoring = false
	if shadow:
		vis.hide()
		trail.hide()
		spark.hide()


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta / FLASH_TIME, 0.0)
	_update_glow()
	trail.add_point(global_position, 0)
	while trail.get_point_count() > TRAIL_PTS:
		trail.remove_point(trail.get_point_count() - 1)


func _physics_process(delta: float) -> void:
	if ghost:
		_age += delta
		if not claimed and _age > 1.0:
			queue_free()
			return
	if _dead:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_expire()
		return

	var motion := velocity * delta
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
		if not shadow:
			Sfx.at2d("bounce", col.get_position(), -12.0)
	rotation = velocity.angle()

	if multiplayer.is_server() and not ghost and bounces > 0:
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
		if body is Player and game.can_hit(owner_id, body):
			game.on_bullet_hit(self, body)
			return


func _expire() -> void:
	_dead = true
	hide()
	if multiplayer.is_server() or (ghost and claimed):
		queue_free()
