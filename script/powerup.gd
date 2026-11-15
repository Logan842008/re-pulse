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


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		game.on_powerup_touched(self, body)
