@tool
class_name Wall
extends StaticBody2D

@export var size := Vector2(64, 64):
	set(v):
		size = v
		_update()

@export var color := Color(0.078, 0.078, 0.227):
	set(v):
		color = v
		_update()

@export var outline_color := Color(0.0, 1.5, 1.7):
	set(v):
		outline_color = v
		_update()

@export var outline_width := 2.0:
	set(v):
		outline_width = v
		_update()


func _ready() -> void:
	_update()


func _update() -> void:
	if not is_node_ready():
		return
	var shape := RectangleShape2D.new()
	shape.size = size
	$CollisionShape2D.shape = shape
	var h := size / 2.0
	$Visual.polygon = PackedVector2Array([-h, Vector2(h.x, -h.y), h, Vector2(-h.x, h.y)])
	$Visual.color = color
	var i := h - Vector2.ONE * outline_width / 2.0
	$Outline.points = PackedVector2Array([-i, Vector2(i.x, -i.y), i, Vector2(-i.x, i.y)])
	$Outline.width = outline_width
	$Outline.default_color = outline_color
