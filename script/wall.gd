@tool
class_name Wall
extends StaticBody2D

@export var size := Vector2(64, 64):
	set(value):
		size = value
		_update()

@export var color := Color(0.35, 0.37, 0.42):
	set(value):
		color = value
		_update()


func _ready() -> void:
	_update()


func _update() -> void:
	if not is_node_ready():
		return
	var shape := RectangleShape2D.new()
	shape.size = size
	$CollisionShape2D.shape = shape
	var half := size / 2.0
	$Visual.polygon = PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
	$Visual.color = color
