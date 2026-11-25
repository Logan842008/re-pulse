class_name Spectator
extends Camera3D

const FLY := 9.0
const SENS := 0.0022
const ARM := Vector3(0.55, 0.35, 2.6)

var game: Game3D
var on := false
var ghost := false
var target := -1
var _yaw := 0.0
var _pitch := 0.0


func _init(g: Game3D) -> void:
	game = g
	fov = 80.0


func start() -> void:
	if on:
		return
	on = true
	target = -1
	var c := get_viewport().get_camera_3d()
	if c:
		global_transform = c.global_transform
	_grab_angles()
	ghost = not _pick(1)
	current = true


func stop() -> void:
	if not on:
		return
	on = false
	current = false
	var me := game.me()
	if me and is_instance_valid(me.cam):
		me.cam.current = true


func alive() -> Array:
	var mine := Network.my_slot()
	var mt := Network.team_of(mine)
	var l: Array = game.in_play().filter(func(s: int) -> bool: return s != mine and game.is_alive(s))
	# teammates first
	l.sort_custom(func(a: int, b: int) -> bool:
		var ma := Network.team_of(a) == mt
		var mb := Network.team_of(b) == mt
		return ma and not mb or ma == mb and a < b)
	return l


func target_name() -> String:
	return Network.name_of(target) if target >= 0 else ""


func look(rel: Vector2) -> void:
	if not ghost:
		return
	_yaw -= rel.x * SENS
	_pitch = clampf(_pitch - rel.y * SENS, -1.5, 1.5)


func _pick(dir: int) -> bool:
	var l := alive()
	if l.is_empty():
		return false
	var i := l.find(target)
	target = l[0] if i < 0 else l[(i + dir + l.size()) % l.size()]
	ghost = false
	return true


func _grab_angles() -> void:
	var e := global_basis.get_euler()
	_pitch = e.x
	_yaw = e.y


func _unhandled_input(e: InputEvent) -> void:
	if on and e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(e.relative * Controls.sens)


func _process(delta: float) -> void:
	if not on:
		return
	if Controls.live():
		if Input.is_action_just_pressed("ghost"):
			ghost = not ghost
			if ghost:
				_grab_angles()
			elif not _pick(0):
				ghost = true
		elif Input.is_action_just_pressed("fire"):
			_pick(0 if ghost else 1)
		elif Input.is_action_just_pressed("scope"):
			_pick(-1)
	if ghost:
		_fly(delta)
	else:
		_follow(delta)


func _follow(delta: float) -> void:
	var p := game._of(target)
	if p == null or not game.is_alive(target):
		if not _pick(1):
			ghost = true
			_grab_angles()
		return
	var eye := p.head.global_position
	var b := Basis.from_euler(Vector3(p.head.rotation.x * 0.85, p.rotation.y, 0.0))
	var want := eye + b * ARM
	var q := PhysicsRayQueryParameters3D.create(eye, want, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		want = hit.position + (eye - want).normalized() * 0.3
	if global_position.distance_to(want) > 6.0:
		global_position = want
	else:
		global_position = global_position.lerp(want, minf(delta * 14.0, 1.0))
	global_basis = b


func _fly(delta: float) -> void:
	global_basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	if not Controls.live():
		return
	var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var up := Input.get_action_strength("jump") - Input.get_action_strength("crouch")
	var sp := FLY * (2.2 if Input.is_action_pressed("walk") else 1.0)
	var v := global_basis * Vector3(mv.x, 0.0, mv.y) + Vector3.UP * up
	global_position = (global_position + v * sp * delta).clamp(Vector3(-45, 0.5, -45), Vector3(45, 40, 45))
