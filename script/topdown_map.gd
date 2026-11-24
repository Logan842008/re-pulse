@tool
class_name TopdownMap
extends Map

const PX := 32.0
const SS := 2
const MODELS := "res://assets/models/%s.glb"

var view: SubViewport
var world: Node3D
var env: Environment
var sun: DirectionalLight3D
var rng := RandomNumberGenerator.new()
var _gen: Node2D
var _frames := 0


func _ready() -> void:
	build()


func _enter_tree() -> void:
	if view and _frames >= 12:
		_frames = 0
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func build() -> void:
	for n in ["Gen", "View", "SpawnPoints", "PowerupPoints"]:
		var old := get_node_or_null(n)
		if old:
			old.free()
	rng.seed = 11
	spawn_sets.clear()
	_frames = 0
	_gen = Node2D.new()
	_gen.name = "Gen"
	add_child(_gen)

	view = SubViewport.new()
	view.name = "View"
	view.size = Vector2i(arena_size * SS)
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	world = Node3D.new()
	view.add_child(world)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = arena_size.y / PX
	cam.position = Vector3(arena_size.x / PX / 2.0, 60, arena_size.y / PX / 2.0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.far = 200
	world.add_child(cam)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.05
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	world.add_child(sun)

	var art := Sprite2D.new()
	art.texture = view.get_texture()
	art.centered = false
	art.scale = Vector2.ONE / SS
	art.z_index = -50
	_gen.add_child(art)

	var sp := Node2D.new()
	sp.name = "SpawnPoints"
	add_child(sp)
	for n in ["Bottom", "Top"]:
		var m := Marker2D.new()
		m.name = n
		sp.add_child(m)
	var pp := Node2D.new()
	pp.name = "PowerupPoints"
	add_child(pp)
	_layout()
	# web renderer washes these out
	if not Engine.is_editor_hint() and RenderingServer.get_current_rendering_method() == "gl_compatibility":
		env.ambient_light_energy *= 0.5
		env.tonemap_exposure *= 0.75


func _process(_delta: float) -> void:
	if view and _frames < 12:
		_frames += 1
		if _frames == 12:
			view.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _layout() -> void:
	pass


func mirror(p: Vector2) -> Vector2:
	return arena_size - p


func mirror_rect(r: Rect2) -> Rect2:
	return Rect2(arena_size - r.end, r.size)


static func rc(cx: float, cy: float, w: float, h: float) -> Rect2:
	return Rect2(cx - w / 2.0, cy - h / 2.0, w, h)


func at(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x / PX, y, p.y / PX)


func spawn(p: Vector2) -> void:
	$SpawnPoints/Bottom.position = p
	$SpawnPoints/Top.position = mirror(p)
	spawn_sets["1v1"] = [p, mirror(p)]


func team_spawns(a: Vector2, b: Vector2) -> void:
	spawn_sets["2v2"] = [a, b, mirror(a), mirror(b)]


func ffa_spawns(a: Vector2, b: Vector2) -> void:
	spawn_sets["ffa"] = [a, mirror(a), b, mirror(b)]


func pickups(pts: Array) -> void:
	for p: Vector2 in pts:
		for q in [p, mirror(p)]:
			var m := Marker2D.new()
			m.position = q
			$PowerupPoints.add_child(m)


func ground(mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = arena_size / PX + Vector2(8, 8)
	mi.mesh = pm
	mi.position = at(arena_size / 2.0)
	mi.material_override = mat
	world.add_child(mi)


func patch(r: Rect2, mat: Material, both := true, lift := 0.01) -> void:
	for rr in ([r, mirror_rect(r)] if both else [r]):
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = rr.size / PX
		mi.mesh = pm
		mi.position = at(rr.get_center(), lift)
		mi.material_override = mat
		world.add_child(mi)


func wall(r: Rect2, h: float, mat: Material, both := true) -> void:
	for rr in ([r, mirror_rect(r)] if both else [r]):
		_solid_rect(rr.get_center(), rr.size, 0.0)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(rr.size.x / PX, h, rr.size.y / PX)
		mi.mesh = bm
		mi.position = at(rr.get_center(), h / 2.0)
		mi.material_override = mat
		world.add_child(mi)


func border(t: float, h: float, mat: Material) -> void:
	var s := arena_size
	wall(Rect2(0, 0, s.x, t), h, mat, false)
	wall(Rect2(0, s.y - t, s.x, t), h, mat, false)
	wall(Rect2(0, t, t, s.y - t * 2), h, mat, false)
	wall(Rect2(s.x - t, t, t, s.y - t * 2), h, mat, false)


func prop(path: String, p: Vector2, rot := 0.0, scl := 1.0, solid := "", both := true, y := 0.0) -> void:
	for i in (2 if both else 1):
		var q := p if i == 0 else mirror(p)
		var r := rot + PI * i
		var m: Node3D = load(MODELS % path).instantiate()
		m.scale = Vector3.ONE * scl
		m.rotation.y = -r
		world.add_child(m)
		var acc := [null]
		ArenaMap._bounds(m, Transform3D.IDENTITY, acc)
		var box: AABB = acc[0]
		var c := m.basis * box.get_center()
		m.position = at(q, y) - Vector3(c.x, 0, c.z) + Vector3(0, -box.position.y * scl, 0)
		var foot := Vector2(box.size.x, box.size.z) * scl * PX
		if solid == "box":
			_solid_rect(q, foot, r)
		elif solid == "round":
			_solid_circle(q, minf(foot.x, foot.y) / 2.0)


func row(path: String, a: Vector2, b: Vector2, n: int, rot := 0.0, scl := 1.0, both := true, y := 0.0) -> void:
	for i in n:
		prop(path, a.lerp(b, (i + 0.5) / n), rot, scl, "", both, y)


func block(r: Rect2, both := true) -> void:
	for rr in ([r, mirror_rect(r)] if both else [r]):
		_solid_rect(rr.get_center(), rr.size, 0.0)


func post(p: Vector2, r: float, both := true) -> void:
	for q in ([p, mirror(p)] if both else [p]):
		_solid_circle(q, r)


func lamp(p: Vector2, col: Color, energy := 2.0, rng_m := 8.0, height := 3.0) -> void:
	for q in [p, mirror(p)]:
		var l := OmniLight3D.new()
		l.position = at(q, height)
		l.light_color = col
		l.light_energy = energy
		l.omni_range = rng_m
		l.omni_attenuation = 1.2
		world.add_child(l)


func tex(name: String, tint := Color.WHITE, scale := 0.4) -> StandardMaterial3D:
	return Mat.tex(name, tint, scale)


func _solid_rect(c: Vector2, sz: Vector2, rot: float) -> void:
	var b := StaticBody2D.new()
	b.collision_mask = 0
	b.position = c
	b.rotation = rot
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = sz
	cs.shape = sh
	b.add_child(cs)
	_gen.add_child(b)


func _solid_circle(c: Vector2, r: float) -> void:
	var b := StaticBody2D.new()
	b.collision_mask = 0
	b.position = c
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = r
	cs.shape = sh
	b.add_child(cs)
	_gen.add_child(b)
