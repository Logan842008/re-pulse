class_name Weather
extends Node3D

const BOX := Vector2(36, 36)
const SNOW_BOX := Vector2(26, 26)

var snow := false
var _parts: GPUParticles3D


func _init(isn := false) -> void:
	snow = isn


func _ready() -> void:
	var bx := SNOW_BOX if snow else BOX
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(bx.x / 2.0, 0.5, bx.y / 2.0)
	pm.direction = Vector3.DOWN
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_keep_scale = true
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 0.4
	mat.distance_fade_max_distance = 2.2

	_parts = GPUParticles3D.new()
	if snow:
		pm.spread = 20.0
		pm.initial_velocity_min = 0.6
		pm.initial_velocity_max = 1.0
		pm.gravity = Vector3(0, -0.6, 0)
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.8
		pm.turbulence_noise_scale = 5.0
		pm.turbulence_influence_min = 0.015
		pm.turbulence_influence_max = 0.04
		pm.scale_min = 0.6
		pm.scale_max = 1.3
		quad.size = Vector2(0.17, 0.17)
		mat.albedo_texture = load("res://assets/particles/circle_05.png")
		mat.uv1_offset = Vector3(0.29, 0.29, 0)
		mat.uv1_scale = Vector3(0.42, 0.42, 1)
		mat.albedo_color = Color(0.92, 0.96, 1.0, 0.8)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_parts.amount = 1500
		_parts.lifetime = 12.0
	else:
		pm.spread = 2.0
		pm.initial_velocity_min = 17.0
		pm.initial_velocity_max = 21.0
		pm.gravity = Vector3(0, -9.8, 0)
		quad.size = Vector2(0.03, 0.7)
		mat.albedo_texture = load("res://assets/particles/trace_01.png")
		mat.uv1_offset = Vector3(0.469, 0.156, 0)
		mat.uv1_scale = Vector3(0.06, 0.48, 1)
		mat.albedo_color = Color(0.82, 0.88, 0.96, 0.6)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		_parts.amount = 12000
		_parts.lifetime = 1.7
	quad.material = mat
	_parts.draw_pass_1 = quad
	_parts.process_material = pm
	_parts.preprocess = _parts.lifetime
	_parts.local_coords = false
	_parts.visibility_aabb = AABB(Vector3(-bx.x / 2.0, -40, -bx.y / 2.0), Vector3(bx.x, 42, bx.y))
	add_child(_parts)

	var field := GPUParticlesCollisionHeightField3D.new()
	field.size = Vector3(bx.x + 8, 60, bx.y + 8)
	field.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	field.follow_camera_enabled = true
	add_child(field)


func thin(v: float) -> void:
	_parts.amount_ratio = v


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position + Vector3(0, 9, 0)
	p.y = minf(p.y, 12.0)
	var jumped := _parts.global_position.distance_to(p) > 12.0
	_parts.global_position = p
	if jumped:
		_parts.restart()
