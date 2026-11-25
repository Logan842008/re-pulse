class_name Player3D
extends CharacterBody3D

const WORLD_MASK := 1
const SENS := 0.0022
const VM_POS := Vector3(0.2, -0.2, -0.36)
const VM_SCALE := 0.55
const VM_ADS := Vector3(0.0, -0.14, -0.3)
const FOV := 90.0
const CHAR := "res://assets/models/character/character-%s.glb"
const CHARS := ["p", "b", "h", "d", "c", "e"]

@export var speed := 6.6
@export var walk_speed := 3.3
@export var jump := 4.8
@export var accel := 80.0
@export var stop_accel := 120.0
@export var air_accel := 18.0
@export var ads_speed := 0.75

@export_group("Crouch / slide")
@export var crouch_speed := 0.45
@export var slide_speed := 14.0
@export var slide_time := 0.8
@export var slide_cooldown := 0.3

const STAND_H := 1.8
const CROUCH_H := 1.1
const EYE := 1.6
const CROUCH_EYE := 0.95
const BODY_SCALE := 1.8 / 2.7

var peer_id := 1
var slot := 0
var game: Game3D
var crouch := 0.0
var sliding := false

var _st := 0.0
var _sc := 0.0
var _sd := Vector3.ZERO
var _cw := false
var _body: Node3D
var _cap: CapsuleShape3D

var _cd := 0.0
var _kick := 0.0
var _shown := -1
var _model: Node3D
var _vm: Node3D
var _anim: AnimationPlayer
var _arm: Node3D
var _last := Vector3.ZERO
var _move := 0.0
var _bm: ShaderMaterial
var scope := 0.0
var err := 0.0
var _bloom := 0.0
var _step_d := 0.0
var _svy := 0.0
var _ws := false
var _wsc := false
var _net := Snaps.new()
var _pt := 0.0
var _snap := []
var snap: Array:
	get:
		return _snap
	set(v):
		if v.size() == 5 and not is_multiplayer_authority():
			_net.push(v[0], v)

@onready var head: Node3D = $Head
@onready var cam: Camera3D = $Head/Camera3D


func _ready() -> void:
	var c := Network.color_of(slot)
	$NameTag.text = Network.name_of(slot)
	$NameTag.modulate = c.lightened(0.4)
	_cap = $Shape.shape.duplicate()
	$Shape.shape = _cap
	_build_body()
	_pt = Time.get_ticks_msec() / 1000.0
	_last = global_position
	_build_box()

	if not is_multiplayer_authority():
		cam.queue_free()
		_vm = Node3D.new()
		_vm.position = Vector3(-0.2, -1.05, 0)
		_vm.basis = Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
		_arm.add_child(_vm)
		return

	cam.current = true
	for m: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	$NameTag.hide()
	_vm = Node3D.new()
	_vm.position = VM_POS
	cam.add_child(_vm)
	if not Controls.touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_box() -> void:
	var me := Network.my_slot()
	if Network.mode != "2v2" or slot == me or Network.team_of(slot) != Network.team_of(me):
		return
	var tag: Label3D = $NameTag
	var font: Font = tag.font if tag.font else ThemeDB.fallback_font
	var sz := font.get_string_size(tag.text, HORIZONTAL_ALIGNMENT_LEFT, -1, tag.font_size) * tag.pixel_size
	var quad := QuadMesh.new()
	quad.size = Vector2(sz.x + 0.22, sz.y + 0.1)
	_bm = ShaderMaterial.new()
	_bm.shader = preload("res://script/name_box.gdshader")
	_bm.set_shader_parameter("size", quad.size)
	_bm.set_shader_parameter("color", Network.color_of(slot).lightened(0.2))
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = _bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tag.add_child(mi)


func _build_body() -> void:
	var ci := Network.char_of(slot)
	_body = load(CHAR % CHARS[ci % CHARS.size()]).instantiate()
	_body.rotation.y = PI
	_body.scale = Vector3.ONE * BODY_SCALE
	add_child(_body)
	_arm = _body.find_child("arm-right")
	_anim = _body.find_children("*", "AnimationPlayer")[0]
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for a in ["idle", "walk", "sprint"]:
		_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_anim.play("idle")


func _unhandled_input(e: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(e.relative * Controls.sens)


func look(rel: Vector2) -> void:
	var s := SENS * tan(deg_to_rad(cam.fov) / 2.0) / tan(deg_to_rad(FOV) / 2.0)
	rotate_y(-rel.x * s)
	head.rotation.x = clampf(head.rotation.x - rel.y * s, -1.5, 1.5)


func _process(delta: float) -> void:
	var w: int = game.gun[slot]
	if w != _shown:
		_shown = w
		if _model:
			_model.queue_free()
		var s := VM_SCALE if is_multiplayer_authority() else 1.5
		_model = Weapons.build_model(w, Network.color_of(slot), s)
		_vm.add_child(_model)

	if not is_multiplayer_authority():
		_follow()
	var v := (global_position - _last) / maxf(delta, 0.001)
	_last = global_position
	_move = lerpf(_move, Vector2(v.x, v.z).length(), minf(delta * 10.0, 1.0))
	_sounds(v.y, delta)
	var dead: bool = game.hp[slot] <= 0
	var low := crouch > 0.5
	var want := "die" if dead else "sit" if low else "sprint" if _move > 3.5 else "walk" if _move > 0.5 else "idle"
	if _anim.assigned_animation != want:
		_anim.play(want, 0.15)
	_anim.advance(delta)
	if not dead:
		_arm.rotation = Vector3(-PI / 2.0 - head.rotation.x, 0, 0)
	_vm.visible = not dead and not (Weapons.LIST[w]["scope"] and scope > 0.85)
	$NameTag.modulate.a = 0.35 if dead else 1.0
	if _bm:
		_bm.set_shader_parameter("fill", float(game.hp[slot]) / game.max_hp)
	_apply_pose(delta)


func _sounds(vy: float, delta: float) -> void:
	if game.hp[slot] <= 0:
		return
	var at := global_position + Vector3(0, 0.1, 0)
	var was := _svy
	_svy = lerpf(_svy, vy, minf(delta * 15.0, 1.0))
	if _svy > 2.5 and was <= 2.5:
		Sfx.at3d("jump", at, -10.0)
	elif was < -3.0 and _svy >= -1.0:
		Sfx.at3d("land", at, -6.0)
	if sliding and not _ws:
		Sfx.at3d("slide", at, -10.0)
	_ws = sliding
	if _move < walk_speed * 1.2 or absf(_svy) > 1.0 or crouch > 0.5 or sliding:
		_step_d = minf(_step_d, 1.2)
		return
	_step_d += _move * delta
	if _step_d >= 2.2:
		_step_d = 0.0
		Sfx.at3d("step_" + game.arena.steps, at, -9.0 if is_multiplayer_authority() else -4.0, 0)


func _apply_pose(delta: float) -> void:
	_cap.height = lerpf(STAND_H, CROUCH_H, crouch)
	$Shape.position.y = _cap.height / 2.0
	head.position.y = lerpf(EYE, CROUCH_EYE, crouch)
	$NameTag.position.y = head.position.y + 0.55
	_body.position.y = -0.45 * crouch
	_body.rotation.x = lerpf(_body.rotation.x, -0.5 if sliding else 0.0, minf(delta * 12.0, 1.0))
	if is_multiplayer_authority():
		cam.rotation.z = lerpf(cam.rotation.z, 0.05 if sliding else 0.0, minf(delta * 10.0, 1.0))


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_cd -= delta
	var live := game.fighting and Controls.live() and game.is_alive(slot)

	_sc -= delta
	var ctrl := live and Input.is_action_pressed("crouch")
	var flat := Vector2(velocity.x, velocity.z)
	if ctrl and not _cw and is_on_floor() and flat.length() > speed * 0.6 and _sc <= 0.0:
		sliding = true
		_st = slide_time
		_sd = Vector3(flat.x, 0, flat.y).normalized()
	_cw = ctrl

	if not is_on_floor():
		velocity += get_gravity() * delta
		_end_slide()
	elif live and Input.is_action_pressed("jump"):
		velocity.y = jump
		_end_slide()

	if sliding:
		_st -= delta
		var sp := lerpf(speed * crouch_speed, slide_speed, _st / slide_time)
		velocity.x = _sd.x * sp
		velocity.z = _sd.z * sp
		if _st <= 0.0:
			_end_slide()
	else:
		var input := Input.get_vector("move_left", "move_right", "move_up", "move_down") if live else Vector2.ZERO
		var wlk := live and Input.is_action_pressed("walk")
		var sp := (walk_speed if wlk else speed) * lerpf(1.0, crouch_speed, crouch) * lerpf(1.0, ads_speed, scope)
		var want := transform.basis * Vector3(input.x, 0, input.y) * sp
		var a := (accel if input != Vector2.ZERO else stop_accel) if is_on_floor() else air_accel
		a *= delta
		velocity.x = move_toward(velocity.x, want.x, a)
		velocity.z = move_toward(velocity.z, want.z, a)
	if not game.fighting:
		velocity.x = 0.0
		velocity.z = 0.0
	crouch = move_toward(crouch, 1.0 if ctrl or sliding else 0.0, delta * 8.0)
	move_and_slide()

	var g: Dictionary = Weapons.LIST[game.gun[slot]]
	_aim(g, live, delta)
	var trg := live and Input.is_action_pressed("fire")
	if trg and _cd <= 0.0:
		_cd = g["delay"]
		_fire(g)

	_kick = move_toward(_kick, 0.0, delta * 0.6)
	_vm.position = VM_POS.lerp(VM_ADS, scope) + Vector3(0, 0, _kick)
	_vm.rotation.x = _kick * 2.0
	_pt += delta
	_stamp()


func _aim(g: Dictionary, live: bool, delta: float) -> void:
	var want: bool = live and g["zoom"] > 1.0 and Input.is_action_pressed("scope") and not sliding
	if want != _wsc:
		_wsc = want
		Sfx.play("scope_in" if want else "scope_out", -10.0)
	scope = move_toward(scope, 1.0 if want else 0.0, delta * (8.0 if want else 12.0))
	var zoomed: float = rad_to_deg(2.0 * atan(tan(deg_to_rad(FOV) / 2.0) / g["zoom"]))
	cam.fov = lerpf(FOV, zoomed, scope)
	var run := clampf(Vector2(velocity.x, velocity.z).length() / speed, 0.0, 1.0)
	run = maxf(run - walk_speed / speed * 0.9, 0.0) / (1.0 - walk_speed / speed * 0.9)
	var e: float = g["run_err"] * run + (0.0 if is_on_floor() else 7.0) + _bloom
	e *= lerpf(1.0, 0.6, crouch)
	e += g["hip_err"] * (1.0 - scope)
	e *= lerpf(1.0, 0.4, scope)
	err = e
	_bloom = move_toward(_bloom, 0.0, delta * 5.0)


func _fire(g: Dictionary) -> void:
	var space := get_world_3d().direct_space_state
	var from := cam.global_position
	var fwd := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 200.0, WORLD_MASK)
	var hit := space.intersect_ray(q)
	var target: Vector3 = hit.position if hit else from + fwd * 200.0
	var origin: Vector3 = _model.get_node("Muzzle").global_position
	if space.intersect_ray(PhysicsRayQueryParameters3D.create(from, origin, WORLD_MASK)):
		origin = from
	var dir := target - origin
	if dir.length() < 1.0:
		dir = fwd
	dir = _jitter(dir.normalized(), err)
	_bloom = minf(_bloom + g["kick"] * 0.9, 6.0)
	game.request_fire(origin, dir.normalized())
	head.rotation.x = minf(head.rotation.x + deg_to_rad(g["kick"]), 1.5)
	_kick = minf(_kick + 0.04 + g["kick"] * 0.01, 0.12)


static func _jitter(d: Vector3, deg: float) -> Vector3:
	if deg <= 0.0:
		return d
	var side := d.cross(Vector3.UP).normalized() if absf(d.y) < 0.99 else Vector3.RIGHT
	var up := side.cross(d)
	var ang := randf() * TAU
	var r := sqrt(randf()) * tan(deg_to_rad(deg))
	return (d + side * cos(ang) * r + up * sin(ang) * r).normalized()


func _end_slide() -> void:
	if sliding:
		sliding = false
		_sc = slide_cooldown


func zone(y: float) -> int:
	var r := (y - global_position.y) / _cap.height
	if r > 0.8:
		return 0
	return 2 if r < 0.42 else 1


func place(xf: Transform3D) -> void:
	scope = 0.0
	_bloom = 0.0
	global_position = xf.origin
	rotation = Vector3(0, xf.basis.get_euler().y, 0)
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_cd = 0.0
	sliding = false
	crouch = 0.0
	_stamp()


func _stamp() -> void:
	_snap = [int(_pt * 1000.0), position, rotation.y, head.rotation.x, crouch]


func _follow() -> void:
	var s := _net.sample()
	if s.is_empty():
		return
	var a: Array = s[0]
	var b: Array = s[1]
	var f: float = s[2]
	if a[1].distance_to(b[1]) > 6.0:
		a = b
	var k := minf(f, 1.0)
	position = a[1].lerp(b[1], f)
	rotation.y = lerp_angle(a[2], b[2], k)
	head.rotation.x = lerpf(a[3], b[3], k)
	crouch = lerpf(a[4], b[4], k)
