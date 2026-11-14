@tool
class_name Wall
extends StaticBody2D
## A rectangular wall or obstacle that bullets ricochet off. Set [member size]
## in the inspector; the collision shape and placeholder visual follow it.

@export var size := Vector2(64, 64):
	set(value):
		size = value
		_update()

@export var color := Color(0.078, 0.078, 0.227): ## Fill colour (dark indigo).
	set(value):
		color = value
		_update()

## Edge colour. Values above 1 glow through the WorldEnvironment in main.tscn.
@export var outline_color := Color(0.0, 1.5, 1.7):
	set(value):
		outline_color = value
		_update()

@export var outline_width := 2.0:
	set(value):
		outline_width = value
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
	# Glowing edge, drawn just inside the shape so it lines up with the collision.
	var inset := half - Vector2.ONE * outline_width / 2.0
	$Outline.points = PackedVector2Array([-inset, Vector2(inset.x, -inset.y), inset, Vector2(-inset.x, inset.y)])
	$Outline.width = outline_width
	$Outline.default_color = outline_color
