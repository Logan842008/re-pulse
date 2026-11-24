class_name Bullet3D
extends CharacterBody3D

const WORLD_MASK := 1
const PLAYER_MASK := 2

@export var lifetime := 6.0

var dir := Vector3.FORWARD
var owner_id := 1
var weapon := 0
var color := Color.WHITE
var game: Game3D
var ghost := false
var claimed := false
var shadow := false
var _age := 0.0

var bounces := 0
var dmg := 20
var _mb := 3
var _dead := false
var _flash := 0.0
var _mat: StandardMaterial3D
var _orb: MeshInstance3D
var _hitbox: Area3D
var _spark: CPUParticles3D


func _ready() -> void:
	var g: Dictionary = Weapons.LIST[weapon]
	if not shadow:
		Sfx.at3d("shot_%d" % weapon, position, -4.0)
	dmg = g["dmg"]
	_mb = g["bounces"]
	velocity = dir.normalized() * g["speed"]
	var r: float = g["size"]
	collision_layer = 4
	collision_mask = WORLD_MASK

	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r
	cs.shape = sh
	add_child(cs)

	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color.BLACK
	_mat.emission_enabled = true
	_mat.emission = color
	_orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	_orb.mesh = sm
	_orb.material_override = _mat
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_orb)
	add_child(_trail(r))

	_spark = CPUParticles3D.new()
	_spark.top_level = true
	_spark.emitting = false
	_spark.one_shot = true
	_spark.amount = 10
	_spark.lifetime = 0.25
	_spark.explosiveness = 1.0
	_spark.spread = 180.0
	_spark.gravity = Vector3.ZERO
	_spark.initial_velocity_min = 2.0
	_spark.initial_velocity_max = 5.0
	_spark.mesh = _dot(0.03)
	add_child(_spark)

	_hitbox = Area3D.new()
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = PLAYER_MASK
	_hitbox.monitorable = false
	_hitbox.monitoring = multiplayer.is_server() and not ghost
	var hs := CollisionShape3D.new()
	var hsh := SphereShape3D.new()
	hsh.radius = r + 0.2
	hs.shape = hsh
	_hitbox.add_child(hs)
	add_child(_hitbox)
	_update_glow()
	if shadow:
		hide()
		_spark.hide()


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta / 0.15, 0.0)
	_update_glow()


func _physics_process(delta: float) -> void:
	if ghost:
		_age += delta
		if not claimed and _age > 1.0:
			queue_free()
			return
	if _dead:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_expire()
		return
	var motion := velocity * delta
	for i in 4:
		var col := move_and_collide(motion)
		if col == null:
			break
		bounces += 1
		if bounces >= _mb:
			_expire()
			return
		var n := col.get_normal()
		velocity = velocity.bounce(n)
		motion = col.get_remainder().bounce(n)
		_flash = 1.0
		_spark.global_position = col.get_position()
		_spark.restart()
		if not shadow:
			Sfx.at3d("bounce", col.get_position(), -10.0)

	if multiplayer.is_server() and not ghost and bounces > 0:
		for b in _hitbox.get_overlapping_bodies():
			if b is Player3D and game.can_hit(owner_id, b):
				game.on_bullet_hit(self, b)
				return


func _update_glow() -> void:
	var armed := bounces > 0
	_mat.emission_energy_multiplier = (6.0 if armed else 1.5) + 10.0 * _flash
	_orb.scale = Vector3.ONE * ((1.0 if armed else 0.7) + 0.6 * _flash)


func _trail(r: float) -> CPUParticles3D:
	var t := CPUParticles3D.new()
	t.local_coords = false
	t.amount = 24
	t.lifetime = 0.18
	t.gravity = Vector3.ZERO
	t.initial_velocity_min = 0.0
	t.initial_velocity_max = 0.0
	t.mesh = _dot(r * 0.8)
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0))
	t.scale_amount_curve = c
	return t


func _dot(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.BLACK
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	m.material = mat
	return m


func _expire() -> void:
	_dead = true
	hide()
	if multiplayer.is_server() or (ghost and claimed):
		queue_free()
