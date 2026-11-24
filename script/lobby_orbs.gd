extends Node2D

@export var orb_count := 6
@export var speed := 220.0
@export var margin := 22.0
@export var trail_length := 14
var _shades: Array[Color] = [Color(0.0, 1.8, 2.0)]

var _orbs: Array[Dictionary] = []


func _ready() -> void:
	for i in orb_count:
		var c: Color = _shades[i % _shades.size()]
		var trail := Line2D.new()
		trail.width = 4.0
		trail.modulate = c
		trail.gradient = _fade()
		trail.joint_mode = Line2D.LINE_JOINT_ROUND
		add_child(trail)

		var orb := Polygon2D.new()
		orb.polygon = _circle(6.0)
		orb.color = c
		add_child(orb)

		var r := _bounds()
		orb.position = Vector2(randf_range(r.position.x, r.end.x), randf_range(r.position.y, r.end.y))
		var vel := Vector2.RIGHT.rotated(randf_range(0.3, 1.2) + i * TAU / orb_count) * speed
		_orbs.append({"orb": orb, "trail": trail, "vel": vel, "flash": 0.0})


func _process(delta: float) -> void:
	var r := _bounds()
	for o in _orbs:
		var orb: Polygon2D = o["orb"]
		var vel: Vector2 = o["vel"]
		var pos := orb.position + vel * delta
		if pos.x < r.position.x or pos.x > r.end.x:
			vel.x = -vel.x
			o["flash"] = 1.0
		if pos.y < r.position.y or pos.y > r.end.y:
			vel.y = -vel.y
			o["flash"] = 1.0
		orb.position = pos.clamp(r.position, r.end)
		o["vel"] = vel

		o["flash"] = maxf(o["flash"] - delta * 5.0, 0.0)
		orb.modulate = Color.WHITE * (1.0 + 1.5 * o["flash"])
		orb.modulate.a = 1.0

		var trail: Line2D = o["trail"]
		trail.add_point(orb.position, 0)
		while trail.get_point_count() > trail_length:
			trail.remove_point(trail.get_point_count() - 1)


func _bounds() -> Rect2:
	var sz := get_viewport_rect().size
	return Rect2(Vector2(margin, margin), sz - Vector2(margin, margin) * 2.0)


static func _circle(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 16:
		pts.append(Vector2.RIGHT.rotated(TAU * i / 16.0) * radius)
	return pts


static func _fade() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.0))
	return g


func tint(col: Color) -> void:
	_shades = [
		col * 2.0,
		col.darkened(0.5) * 1.6,
		col.lightened(0.45) * 1.8,
		col.darkened(0.25) * 1.8,
		col.lightened(0.2) * 2.0,
		col.darkened(0.6) * 1.4,
	]
	for i in _orbs.size():
		var c: Color = _shades[i % _shades.size()]
		_orbs[i]["orb"].color = c
		_orbs[i]["trail"].modulate = c
