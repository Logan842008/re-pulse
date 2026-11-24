class_name Player
extends CharacterBody2D

const WALL_LAYER := 1

@export var speed := 260.0
@export var fire_delay := 0.3
@export var boost_fire_delay := 0.25
@export var muzzle_dist := 34.0
@export var aim_len := 1300.0

var peer_id := 1
var slot := 0
var game: Game

var _cd := 0.0
var _box: Node2D
var _bf := -1.0
var _step_d := 0.0
var _lp := Vector2.ZERO
var _net := Snaps.new()
var _pt := 0.0
var _snap := []
var _tj: Node2D
var _tp := PackedVector2Array()
var _dot := CircleShape2D.new()
var snap: Array:
	get:
		return _snap
	set(v):
		if v.size() == 3 and not is_multiplayer_authority():
			_net.push(v[0], v)

@onready var pivot: Node2D = $Pivot
@onready var bs: Vector2 = $CollisionShape2D.shape.size


func _ready() -> void:
	var c := Network.color_of(slot)
	$Body.color = c.darkened(0.55)
	$Edge.default_color = _glow(c, 1.8)
	$Pivot/Gun.color = _glow(c.lightened(0.35), 1.6)
	$NameTag/Label.text = Network.name_of(slot)
	$NameTag.rotation = game.view_rot()
	_pt = Time.get_ticks_msec() / 1000.0
	var me := Network.my_slot()
	if is_multiplayer_authority():
		_dot.radius = 4.0
		_tj = Node2D.new()
		_tj.top_level = true
		_tj.z_index = 5
		_tj.draw.connect(_draw_tj)
		add_child(_tj)
	if slot == me or (Network.mode == "2v2" and Network.team_of(slot) == Network.team_of(me)):
		_box = Node2D.new()
		_box.draw.connect(_draw_box)
		$NameTag.add_child(_box)


static func _glow(c: Color, amt: float) -> Color:
	return Color(c.r * amt, c.g * amt, c.b * amt, 1.0)


func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		_follow()
	visible = game.is_alive(slot)
	_steps()
	var blink := game.is_protected(slot) and Time.get_ticks_msec() % 200 < 100
	modulate.a = 0.35 if blink else 1.0
	if _box:
		var f := float(game.hp[slot]) / game.max_hp
		if f != _bf:
			_bf = f
			_box.queue_redraw()
	if _tj:
		_tj.visible = Controls.touch and Controls.aim != Vector2.ZERO and game.is_alive(slot)
		if _tj.visible:
			_tp = _path()
			_tj.queue_redraw()


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_cd -= delta
	_pt += delta
	if Controls.aim != Vector2.ZERO:
		pivot.global_rotation = Controls.aim.rotated(game.view_rot()).angle()
	elif not Controls.touch:
		pivot.look_at(get_global_mouse_position())
	_stamp()
	if not game.fighting or not game.is_alive(slot):
		velocity = Vector2.ZERO
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input.rotated(game.view_rot()) * speed
	move_and_slide()
	_push_out()
	_stamp()

	if Input.is_action_pressed("shoot") and _cd <= 0.0:
		_cd = boost_fire_delay if game.is_boosted(slot) else fire_delay
		_shoot()


func _draw_box() -> void:
	var lbl: Label = $NameTag/Label
	var w := lbl.get_theme_font("font").get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lbl.get_theme_font_size("font_size")).x
	var r := Rect2(-w / 2.0 - 7.0, lbl.position.y - 1.0, w + 14.0, lbl.size.y + 2.0)
	var c := Network.color_of(slot)
	_box.draw_rect(r, Color(0.03, 0.03, 0.06, 0.45), false, 2.0)
	var pts := ring(r, maxf(_bf, 0.0))
	if pts.size() > 1:
		_box.draw_polyline(pts, _glow(c, 1.6), 2.0)


static func ring(r: Rect2, f: float) -> PackedVector2Array:
	var top := Vector2(r.get_center().x, r.position.y)
	var crns := [top, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position, top]
	var left := (r.size.x + r.size.y) * 2.0 * clampf(f, 0.0, 1.0)
	var pts := PackedVector2Array([top])
	for i in range(1, crns.size()):
		var seg: float = crns[i - 1].distance_to(crns[i])
		if left >= seg:
			pts.append(crns[i])
			left -= seg
		else:
			pts.append(crns[i - 1].move_toward(crns[i], left))
			break
	return pts


func _steps() -> void:
	var d := global_position.distance_to(_lp)
	_lp = global_position
	if not visible or d > 40.0 or d < 0.5:
		return
	_step_d += d
	if _step_d >= 70.0:
		_step_d = 0.0
		Sfx.at2d("step_" + game.map.steps, global_position, -14.0 if is_multiplayer_authority() else -10.0, 0)


func respawn(at: Vector2) -> void:
	global_position = at
	velocity = Vector2.ZERO
	_cd = 0.0
	_stamp()


func _stamp() -> void:
	_snap = [int(_pt * 1000.0), position, pivot.rotation]


func _follow() -> void:
	var s := _net.sample()
	if s.is_empty():
		return
	var a: Array = s[0]
	var b: Array = s[1]
	if a[1].distance_to(b[1]) > 150.0:
		a = b
	position = a[1].lerp(b[1], s[2])
	pivot.rotation = lerp_angle(a[2], b[2], minf(s[2], 1.0))


# players dont collide online so push apart by hand
func _push_out() -> void:
	for other: Player in game.players.get_children():
		if other == self or not game.is_alive(other.slot):
			continue
		var off := global_position - other.global_position
		var ovlp := bs - off.abs()
		if ovlp.x <= 0.0 or ovlp.y <= 0.0:
			continue
		var push := Vector2(signf(off.x) * ovlp.x, 0.0) if ovlp.x < ovlp.y \
				else Vector2(0.0, signf(off.y) * ovlp.y)
		move_and_collide(push * 0.5)


func _shoot() -> void:
	var dir := Vector2.RIGHT.rotated(pivot.global_rotation)
	game.request_shoot(_muzzle(dir), dir)


func _muzzle(dir: Vector2) -> Vector2:
	var org := global_position + dir * muzzle_dist
	var q := PhysicsRayQueryParameters2D.create(global_position, org, WALL_LAYER)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit:
		org = hit.position - dir * 6.0
	return org


# aim line for touch, way too hard to aim on a phone otherwise
func _path() -> PackedVector2Array:
	var dir := Vector2.RIGHT.rotated(pivot.global_rotation)
	var at := _muzzle(dir)
	var pts := PackedVector2Array([at])
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = _dot
	q.collision_mask = WALL_LAYER
	var left := aim_len
	for i in 3:
		q.transform = Transform2D(0.0, at)
		q.motion = dir * left
		var r := space.cast_motion(q)
		if r[1] >= 1.0:
			pts.append(at + q.motion)
			break
		var hit: Vector2 = at + q.motion * r[0]
		q.transform = Transform2D(0.0, at + q.motion * r[1])
		q.motion = Vector2.ZERO
		var info := space.get_rest_info(q)
		left -= at.distance_to(hit)
		at = hit
		pts.append(at)
		if info.is_empty() or left <= 0.0:
			break
		dir = dir.bounce(info["normal"])
	return pts


# shots only hurt after a bounce so keep it dim till then
func _draw_tj() -> void:
	var c := _glow(Network.color_of(slot).lightened(0.3), 1.5)
	var gone := 0.0
	var gap := 16.0
	for s in range(1, _tp.size()):
		var a := _tp[s - 1]
		var b := _tp[s]
		var seg := a.distance_to(b)
		var d := fposmod(-gone, gap)
		while d < seg:
			var k := 1.0 - (gone + d) / aim_len
			c.a = (0.35 if s == 1 else 0.9) * clampf(k * 1.4, 0.0, 1.0)
			_tj.draw_circle(a.lerp(b, d / seg), 2.5 if s == 1 else 3.2, c)
			d += gap
		gone += seg
		if s < _tp.size() - 1:
			c.a = 0.9
			_tj.draw_arc(b, 6.0, 0.0, TAU, 16, c, 1.5)
