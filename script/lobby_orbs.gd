extends Node2D

@export var orb_count := 3
@export var speed := 220.0
@export var margin := 22.0
@export var trail_length := 14
@export var colors: Array[Color] = [Color(0.0, 1.8, 2.0), Color(2.0, 0.3, 1.7), Color(0.0, 1.8, 2.0)]

var _orbs: Array[Dictionary] = []


func _ready() -> void:
	for i in orb_count:
		var color: Color = colors[i % colors.size()]
		var trail := Line2D.new()
		trail.width = 4.0
		trail.modulate = color
		trail.gradient = _fade_gradient()
		trail.joint_mode = Line2D.LINE_JOINT_ROUND
		add_child(trail)

		var orb := Polygon2D.new()
		orb.polygon = _circle(6.0)
		orb.color = color
		add_child(orb)

		var area := _bounds()
		orb.position = Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		var velocity := Vector2.RIGHT.rotated(randf_range(0.3, 1.2) + i * TAU / orb_count) * speed
		_orbs.append({"orb": orb, "trail": trail, "velocity": velocity, "color": color, "flash": 0.0})


func _process(delta: float) -> void:
	var area := _bounds()
	for data in _orbs:
		var orb: Polygon2D = data["orb"]
		var velocity: Vector2 = data["velocity"]
		var pos := orb.position + velocity * delta
		if pos.x < area.position.x or pos.x > area.end.x:
			velocity.x = -velocity.x
			data["flash"] = 1.0
		if pos.y < area.position.y or pos.y > area.end.y:
			velocity.y = -velocity.y
			data["flash"] = 1.0
		orb.position = pos.clamp(area.position, area.end)
		data["velocity"] = velocity

		data["flash"] = maxf(data["flash"] - delta * 5.0, 0.0)
		orb.modulate = Color.WHITE * (1.0 + 1.5 * data["flash"])
		orb.modulate.a = 1.0

		var trail: Line2D = data["trail"]
		trail.add_point(orb.position, 0)
		while trail.get_point_count() > trail_length:
			trail.remove_point(trail.get_point_count() - 1)


func _bounds() -> Rect2:
	var size := get_viewport_rect().size
	return Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)


static func _circle(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 16:
		points.append(Vector2.RIGHT.rotated(TAU * i / 16.0) * radius)
	return points


static func _fade_gradient() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.0))
	return g
