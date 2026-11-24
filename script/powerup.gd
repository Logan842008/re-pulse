class_name Powerup
extends Area2D

enum Kind { HEALTH, WEAPON }

var kind := Kind.HEALTH
var game: Game


func _ready() -> void:
	$HealthVisual.visible = kind == Kind.HEALTH
	$WeaponVisual.visible = kind == Kind.WEAPON
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)
	else:
		monitoring = false


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 1.0 + 0.08 * sin(t * 4.0)
	$HealthVisual.scale = Vector2.ONE * pulse
	$WeaponVisual.scale = Vector2.ONE * pulse
	$WeaponVisual.rotation = t * 1.5


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		game.on_pickup(self, body)
