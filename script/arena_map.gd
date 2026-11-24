@tool
class_name ArenaMap
extends Node3D

const SIDES := ["n", "e", "s", "w"]
const MODELS := "res://assets/models/%s.glb"
const SIDE_COL := [Color("5fb3b3"), Color("c8664e"), Color("ebe5da"), Color("d9b45a")]

@export var show_markers := true

var size := 48.0
var wall_h := 5.0
var blocks := []
var cover := []
var roofs := []
var roof_h := 4.0
var spawn_pts := [Vector2(-2, -21), Vector2(2, -21)]
var pickup_pt := Vector2(0, -23)
var gun_pts := []
var tower := Vector3(4, 3, 4)
var ramps := true
var lamp_col := Color("ffe2b8")
var steps := "concrete"
var weather := ""
var wet := 0.0

var _spawns := {}
var _pickups := {}
var _guns: Array[Marker3D] = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	_web_look()
	build()


# web build looks flat without this. env is shared so tweak a copy
func _web_look() -> void:
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if Engine.is_editor_hint() or we == null or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		return
	var env := we.environment.duplicate() as Environment
	env.ambient_light_energy *= 0.7
	env.tonemap_exposure *= 1.05
	env.fog_density *= 0.5
	env.adjustment_contrast = 1.14
	env.adjustment_saturation *= 1.08
	we.environment = env


func build() -> void:
	var old := get_node_or_null("Gen")
	if old:
		old.free()
	var gen := Node3D.new()
	gen.name = "Gen"
	add_child(gen)
	_guns.clear()
	blocks.clear()
	cover.clear()
	roofs.clear()
	gun_pts.clear()
	_layout()
	rng.seed = 7

	var half := size / 2.0
	_box(gen, Vector3(0, -0.25, 0), Vector3(size, 0.5, size), _look("floor"))
	if tower != Vector3.ZERO:
		_box(gen, Vector3(0, tower.y / 2.0, 0), tower, _look("tower"))

	for k in 4:
		var w := Node3D.new()
		w.name = SIDES[k].to_upper()
		w.rotation.y = -k * PI / 2.0
		gen.add_child(w)

		_box(w, Vector3(0, (wall_h + 1) / 2.0, -half - 0.5), Vector3(size + 2, wall_h + 1, 1), _look("outer", k))
		for b in blocks:
			_rect(w, b, _look("wall", k, b))
		for b in cover:
			_rect(w, b, _look("cover", k, b))
		for r in roofs:
			_roof(w, r)
		if ramps and tower != Vector3.ZERO:
			_ramp(w)

		var pts: Array[Marker3D] = []
		for p: Vector2 in spawn_pts:
			var m := Marker3D.new()
			m.position = Vector3(p.x, 0, p.y)
			m.rotation.y = PI
			w.add_child(m)
			pts.append(m)
			if show_markers:
				_marker(m, CylinderMesh.new(), SIDE_COL[k].lightened(0.3))
		_spawns[SIDES[k]] = pts

		var pk := Marker3D.new()
		pk.position = Vector3(pickup_pt.x, 0, pickup_pt.y)
		w.add_child(pk)
		_pickups[SIDES[k]] = pk
		if show_markers:
			_marker(pk, BoxMesh.new(), Color("ffd84a"))

		for p: Vector2 in gun_pts:
			var m := Marker3D.new()
			m.position = Vector3(p.x, 0, p.y)
			w.add_child(m)
			_guns.append(m)
			if show_markers:
				_marker(m, BoxMesh.new(), Color("ff4655"))

		_decorate_wedge(w, k)

	if tower != Vector3.ZERO:
		var top := Marker3D.new()
		top.position = Vector3(0, tower.y, 0)
		gen.add_child(top)
		_guns.append(top)
	_decorate(gen)
	if weather != "" and not Engine.is_editor_hint():
		gen.add_child(Weather.new(weather == "snow"))


func _layout() -> void:
	pass


func _look(_role: String, _k := 0, _b := []) -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.6, 0.6, 0.6)
	return m


func _decorate_wedge(_w: Node3D, _k: int) -> void:
	pass


func _decorate(_gen: Node3D) -> void:
	pass


func gun_spots(mode := "") -> Array[Vector3]:
	var out: Array[Vector3] = []
	var crns := _corners() if mode == "ffa" else []
	for i in _guns.size():
		if not crns.has(i):
			out.append(_guns[i].global_position)
	return out


func _corners() -> Array:
	if gun_pts.is_empty():
		return []
	return range(4).map(func(k: int) -> int: return k * gun_pts.size())


func spawns(mode: String, flip := false) -> Array:
	var a := "e" if flip else "n"
	var b := "w" if flip else "s"
	match mode:
		"ffa":
			return SIDES.map(func(s): return [_xf(_spawns[s][0])])
		"1v1":
			return [[_xf(_spawns[a][0])], [_xf(_spawns[b][0])]]
		_:
			return [_spawns[a].map(_xf), _spawns[b].map(_xf)]


func pickup_spots(mode: String, flip := false) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if mode == "ffa":
		for i: int in _corners():
			out.append(_guns[i].global_position)
		return out
	for s in (["n", "s"] if flip else ["e", "w"]):
		out.append(_pickups[s].global_position)
	return out


func prop(p: Node, path: String, pos: Vector3, rot := 0.0, scl := 1.0, solid := false) -> Node3D:
	var m: Node3D = load(MODELS % path).instantiate()
	m.position = pos
	m.rotation.y = rot
	m.scale = Vector3.ONE * scl
	p.add_child(m)
	if solid:
		var acc := [null]
		_bounds(m, Transform3D.IDENTITY, acc)
		var box: AABB = acc[0]
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = box.size
		cs.shape = sh
		cs.position = box.get_center()
		body.add_child(cs)
		m.add_child(body)
	return m


func mesh_collider(m: Node3D) -> void:
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		body.add_child(cs)
		mi.add_child(body)


func tree(p: Node, path: String, pos: Vector3, scl: float, trunk := 0.35) -> Node3D:
	var m := prop(p, path, pos, rng.randf() * TAU, scl)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = trunk
	sh.height = 4.0
	cs.shape = sh
	cs.position.y = 2.0
	body.add_child(cs)
	body.position = pos
	p.add_child(body)
	return m


func patch(p: Node, pos: Vector3, sz: Vector2, mat: Material, lift := 0.01) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = sz
	mi.mesh = pm
	mi.position = pos + Vector3(0, lift, 0)
	mi.material_override = mat
	p.add_child(mi)
	return mi


func lamp(p: Node, pos: Vector3, col: Color, energy := 1.5, rng_m := 9.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.omni_attenuation = 0.8
	p.add_child(l)
	return l


func tex(name: String, tint := Color.WHITE, scale := 0.4) -> StandardMaterial3D:
	return Mat.tex(name, tint, scale * 0.65, wet)


func box(p: Node, pos: Vector3, sz: Vector3, mat: Material) -> StaticBody3D:
	return _box(p, pos, sz, mat)


func _xf(m: Marker3D) -> Transform3D:
	return m.global_transform


func _roof(w: Node3D, r: Array) -> void:
	var sz := Vector3(r[2] - r[0], 0.3, r[3] - r[1])
	var mid := Vector3((r[0] + r[2]) / 2.0, 0, (r[1] + r[3]) / 2.0)
	_box(w, mid + Vector3(0, roof_h + 0.15, 0), sz, _look("roof"))
	patch(w, mid, Vector2(sz.x, sz.z), _look("indoor"))
	var lid := patch(w, mid + Vector3(0, roof_h - 0.02, 0), Vector2(sz.x, sz.z), _look("ceiling"), 0.0)
	lid.rotation.x = PI
	var l := lamp(w, mid + Vector3(0, roof_h - 1.0, 0), lamp_col, 2.5, maxf(sz.x, sz.z) * 1.2)
	l.omni_attenuation = 0.6


func _ramp(w: Node3D) -> void:
	var h := tower.y
	var run := h / 0.75
	var r := _box(w, Vector3(0, h / 2.0 - 0.19, -(tower.z / 2.0 + run / 2.0)), Vector3(2, 0.3, h / 0.6 + 0.6), _look("ramp"))
	r.rotation.x = -asin(0.6)


func _rect(p: Node, b: Array, mat: Material) -> void:
	var sz := Vector3(float(b[2]) - b[0], b[4], float(b[3]) - b[1])
	_box(p, Vector3((b[0] + b[2]) / 2.0, b[4] / 2.0, (b[1] + b[3]) / 2.0), sz, mat)


func _box(p: Node, pos: Vector3, sz: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = sz
	mi.mesh = mesh
	mi.material_override = mat
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = sz
	cs.shape = sh
	body.add_child(mi)
	body.add_child(cs)
	p.add_child(body)
	return body


func _marker(m: Node3D, mesh: PrimitiveMesh, col: Color) -> void:
	if mesh is CylinderMesh:
		mesh.top_radius = 0.5
		mesh.bottom_radius = 0.5
		mesh.height = 0.04
	else:
		mesh.size = Vector3(0.5, 0.5, 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = 0.3 if mesh is BoxMesh else 0.02
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mi.material_override = mat
	m.add_child(mi)


static func _bounds(n: Node, xf: Transform3D, acc: Array) -> void:
	if n is MeshInstance3D:
		var a: AABB = xf * n.get_aabb()
		acc[0] = a if acc[0] == null else acc[0].merge(a)
	for c in n.get_children():
		_bounds(c, xf * c.transform if c is Node3D else xf, acc)
