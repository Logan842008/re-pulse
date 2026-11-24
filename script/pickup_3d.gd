class_name Pickup3D
extends Area3D

const HEALTH := 0
const NONE := -1

var kind := NONE:
	set(v):
		kind = v
		if is_inside_tree():
			_rebuild()

var _vis: Node3D


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.9
	cs.shape = sh
	cs.position.y = 0.6
	add_child(cs)
	collision_layer = 0
	collision_mask = 2
	monitoring = multiplayer.is_server()
	_rebuild()


func _process(delta: float) -> void:
	if _vis:
		_vis.rotate_y(delta * 2.0)
		_vis.position.y = 0.75 + sin(Time.get_ticks_msec() / 400.0) * 0.08


func touching() -> Array[Player3D]:
	var out: Array[Player3D] = []
	if kind != NONE and monitoring:
		for b in get_overlapping_bodies():
			if b is Player3D:
				out.append(b)
	return out


func _rebuild() -> void:
	if _vis:
		_vis.queue_free()
		_vis = null
	if kind == NONE:
		return
	_vis = Node3D.new()
	add_child(_vis)
	var col := Color("4be07a") if kind == HEALTH else Color("ffcc33")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.2
	if kind == HEALTH:
		for s: Vector3 in [Vector3(0.5, 0.16, 0.16), Vector3(0.16, 0.5, 0.16)]:
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = s
			mi.mesh = box
			mi.material_override = mat
			_vis.add_child(mi)
		return
	_vis.add_child(Weapons.build_model(kind, col, 1.6))
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.6
	ring.mesh = torus
	ring.material_override = mat
	ring.position.y = -0.6
	_vis.add_child(ring)
	var lbl := Label3D.new()
	lbl.text = Weapons.LIST[kind]["name"]
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 36
	lbl.outline_size = 8
	lbl.position.y = 0.6
	_vis.add_child(lbl)
