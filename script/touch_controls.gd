class_name TouchControls
extends Control

const R := 70.0
const LOOK := 0.9
const FONT := preload("res://Rajdhani-SemiBold.ttf")
const MOVES := ["move_left", "move_right", "move_up", "move_down"]

var game: Node
var three := true
var blockers: Array[Control] = []
var _om: Callable
var _btns := []
var _held := {}
var _on := {}
var _stick := -1
var _sc := Vector2.ZERO
var _sv := Vector2.ZERO
var _aim := -1
var _aim_c := Vector2.ZERO
var _aim_v := Vector2.ZERO
var _look := {}
var _pts := {}
var _next := 0


func _init(g: Node, is_3d: bool, om := Callable()) -> void:
	game = g
	three = is_3d
	_om = om


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	if three:
		_btns = [
			["fire", "fire", Vector2(-150, -215), 58.0, "FIRE", false],
			["scope", "scope", Vector2(-280, -295), 38.0, "SCOPE", true],
			["jump", "jump", Vector2(-70, -335), 40.0, "JUMP", false],
			["slide", "crouch", Vector2(-285, -170), 38.0, "SLIDE", false],
			["menu", "", Vector2(46, 46), 26.0, "MENU", false],
			["tab", "scoreboard", Vector2(112, 46), 26.0, "SCORES", false],
		]
	else:
		_btns = [["tab", "scoreboard", Vector2(46, 120), 26.0, "SCORES", false]]
	visibility_changed.connect(func():
		if not visible:
			_release_all())


func _exit_tree() -> void:
	_release_all()


func _spot(b: Array) -> Vector2:
	var p: Vector2 = b[2]
	return Vector2(p.x if p.x >= 0.0 else size.x + p.x, p.y if p.y >= 0.0 else size.y + p.y)


func _button(n: String) -> Array:
	for b: Array in _btns:
		if b[0] == n:
			return b
	return []


func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			if _nearest(e.position, 12.0) >= 0:
				return
			var id := _next
			_next += 1
			_pts[id] = e.position
			_down(id, e.position)
			if not _tracked(id):
				_pts.erase(id)
		else:
			var id := _nearest(e.position, INF)
			if id >= 0:
				_pts.erase(id)
				_up(id)
	elif e is InputEventScreenDrag:
		var id := _nearest(e.position, 160.0)
		if id >= 0:
			var rel: Vector2 = e.position - _pts[id]
			_pts[id] = e.position
			_drag(id, e.position, rel)


func _nearest(p: Vector2, within: float) -> int:
	var best := -1
	var d := within
	for id: int in _pts:
		var dd := p.distance_to(_pts[id])
		if dd <= d:
			d = dd
			best = id
	return best


func _tracked(id: int) -> bool:
	return id == _stick or id == _aim or _look.has(id) or _held.has(id)


func _down(i: int, p: Vector2) -> void:
	for c in blockers:
		if c.is_visible_in_tree() and c.get_global_rect().has_point(p):
			return
	for b: Array in _btns:
		if p.distance_to(_spot(b)) <= b[3] * 1.15:
			_press(b, i)
			return
	if p.x < size.x * 0.45 and p.y > size.y * 0.3 and _stick < 0:
		_stick = i
		_sc = p
		_sv = Vector2.ZERO
	elif not three and p.x > size.x * 0.55 and p.y > size.y * 0.3 and _aim < 0:
		_aim = i
		_aim_c = p
		_aim_v = Vector2.ZERO
	elif three and p.x >= size.x * 0.45:
		_look[i] = true


func _press(b: Array, i: int) -> void:
	if b[0] == "menu":
		_release_all()
		if _om.is_valid():
			_om.call()
		return
	if b[5]:
		_on[b[0]] = not _on.get(b[0], false)
		if _on[b[0]]:
			Input.action_press(b[1])
		else:
			Input.action_release(b[1])
	else:
		Input.action_press(b[1])
	_held[i] = b[0]


func _drag(i: int, p: Vector2, rel: Vector2) -> void:
	if i == _stick:
		_sc = _follow(_sc, p)
		_sv = ((p - _sc) / R).limit_length(1.0)
		_set_move(_sv)
	elif i == _aim:
		_aim_c = _follow(_aim_c, p)
		_aim_v = ((p - _aim_c) / R).limit_length(1.0)
		Controls.aim = _aim_v if _aim_v.length() > 0.25 else Vector2.ZERO
		if _aim_v.length() > 0.6:
			Input.action_press("shoot")
		else:
			Input.action_release("shoot")
	elif three and (_look.has(i) or _held.get(i, "") == "fire"):
		var me = game.me()
		if me:
			me.look(rel * LOOK)


static func _follow(c: Vector2, p: Vector2) -> Vector2:
	var d := p - c
	return p - d.normalized() * R if d.length() > R else c


func _up(i: int) -> void:
	if i == _stick:
		_stick = -1
		_sv = Vector2.ZERO
		_set_move(Vector2.ZERO)
	elif i == _aim:
		_aim = -1
		_aim_v = Vector2.ZERO
		Controls.aim = Vector2.ZERO
		Input.action_release("shoot")
	elif _held.has(i):
		var b := _button(_held[i])
		_held.erase(i)
		if not b.is_empty() and not b[5]:
			Input.action_release(b[1])
	_look.erase(i)


func _set_move(v: Vector2) -> void:
	var amt := [-v.x, v.x, -v.y, v.y]
	for k in 4:
		if amt[k] > 0.05:
			Input.action_press(MOVES[k], amt[k])
		else:
			Input.action_release(MOVES[k])


func _release_all() -> void:
	for a in MOVES + ["shoot", "fire", "scope", "jump", "crouch", "scoreboard"]:
		Input.action_release(a)
	_held.clear()
	_pts.clear()
	_on.clear()
	_look.clear()
	_stick = -1
	_aim = -1
	_sv = Vector2.ZERO
	_aim_v = Vector2.ZERO
	Controls.aim = Vector2.ZERO


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var col := Network.color_of(Network.my_slot())
	_draw_stick(_sc if _stick >= 0 else Vector2(170, size.y - 245), _sv, _stick >= 0, "MOVE", col)
	if not three:
		_draw_stick(_aim_c if _aim >= 0 else Vector2(size.x - 170, size.y - 245), _aim_v, _aim >= 0, "AIM", col)
	for b: Array in _btns:
		var c := _spot(b)
		var r: float = b[3]
		var down: bool = _held.values().has(b[0]) or _on.get(b[0], false)
		draw_circle(c, r, Color(col, 0.45) if down else Color(1, 1, 1, 0.1))
		draw_arc(c, r, 0.0, TAU, 48, Color(col.lightened(0.3), 0.85 if down else 0.5), 2.5, true)
		var fs := 18 if r > 30.0 else 12
		var w := FONT.get_string_size(b[4], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(FONT, c + Vector2(-w / 2.0, fs * 0.35), b[4], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))


func _draw_stick(c: Vector2, v: Vector2, active: bool, label: String, col: Color) -> void:
	draw_circle(c, R, Color(1, 1, 1, 0.08 if active else 0.04))
	draw_arc(c, R, 0.0, TAU, 48, Color(1, 1, 1, 0.35 if active else 0.15), 2.0, true)
	draw_circle(c + v * R, 30.0, Color(col, 0.55) if active else Color(1, 1, 1, 0.12))
	if not active:
		var w := FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(FONT, c + Vector2(-w / 2.0, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.5))
