@tool
extends ArenaMap

const TINT := [Color("a9cfc6"), Color("dba796"), Color("ecebe2"), Color("e2d29e")]
const PALMS := ["tree_palm", "tree_palmBend", "tree_palmTall", "tree_palmDetailedTall"]
const TREES := ["tree_default_dark", "tree_fat", "tree_detailed", "tree_oak_dark"]
const PLANTS := ["plant_bushLarge", "plant_bushDetailed", "plant_bush", "grass_large", "grass_leafs"]

var _env: Environment
var _fog := 0.0
var _exp := 1.0
var _sat := 1.0
var _rain: Weather


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	var we := $WorldEnvironment as WorldEnvironment
	_env = we.environment.duplicate()
	we.environment = _env
	_fog = _env.fog_density
	_exp = _env.tonemap_exposure
	_sat = _env.adjustment_saturation
	var w := find_children("*", "Weather", true, false)
	if w.size() > 0:
		_rain = w[0]


# rain and fog turn to mush from up high, fade them out
func _process(_d: float) -> void:
	if _env == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var h := smoothstep(16.0, 28.0, cam.global_position.y)
	_env.fog_density = _fog * (1.0 - h)
	_env.tonemap_exposure = _exp * lerpf(1.0, 0.9, h)
	_env.adjustment_saturation = _sat * lerpf(1.0, 0.92, h)
	if _rain:
		_rain.thin(1.0 - h)


func _layout() -> void:
	weather = "rain"
	steps = "grass"
	wet = 0.6
	wall_h = 4.0
	tower = Vector3(6, 2.2, 6)
	blocks = [
		[-13, -24, -6, -22, 3.5],
		[6, -24, 13, -22, 3.5],
		[-9, -20, -7, -12, 3.5],
		[7, -19, 9, -12, 3.5],
		[13, -19, 19, -17, 3.5],
		[19, -17, 21, -11, 3.5],
	]
	cover = [
		[-2.5, -17.5, 2.5, -16, 2.4],
		[-5, -10.5, -3, -9.5, 1.1],
		[2.5, -13.5, 4, -12, 1.1],
		[14, -23, 15.5, -21.5, 1.1],
		[-6.5, -5.5, -5, -4, 1.4],
	]
	gun_pts = [Vector2(15.5, -15.5), Vector2(0, -12)]


func _look(role: String, k := 0, b := []) -> Material:
	match role:
		"floor":
			return tex("forest_ground_04", Color.WHITE, 0.3)
		"tower":
			return tex("large_sandstone_blocks", Color.WHITE, 0.35)
		"outer":
			return tex("mossy_rock", Color("b8c4a8"), 0.3)
		"wall":
			return tex("mossy_sandstone", TINT[k], 0.35)
		"cover":
			if b[4] >= 2.0:
				return tex("sandstone_blocks_08", TINT[k], 0.45)
			return tex("mossy_sandstone", Color("d9d2b8"), 0.6)
		"ramp":
			return tex("stone_tiles", Color("cfc6b0"), 0.6)
	return super(role, k, b)


func _decorate_wedge(w: Node3D, _k: int) -> void:
	patch(w, Vector3(0, 0, -13), Vector2(5, 12), tex("mossy_cobblestone", Color.WHITE, 0.45))
	patch(w, Vector3(0, 0, -22), Vector2(12, 4), tex("brown_mud", Color.WHITE, 0.35))

	prop(w, "nature/statue_column", Vector3(2.4, tower.y, -2.4), 0.0, 3.5, true)

	prop(w, "nature/log_large", Vector3(-4.5, 0, -7.8), 0.0, 4.0, true)
	tree(w, "nature/tree_default_dark", Vector3(9.5, 0, -9.5), 7.0, 0.6)
	_trunk(w, Vector3(0, 3.84, -15), 18.0)
	prop(w, "nature/statue_head", Vector3(16.5, 0, -12.5), PI * 0.75, 3.0, true)
	prop(w, "nature/rock_largeB", Vector3(22, 0, -21.5), 1.0, 3.0, true)
	tree(w, "nature/" + PALMS[rng.randi() % 4], Vector3(-11, 0, -14.5), 4.5)
	tree(w, "nature/" + TREES[rng.randi() % 4], Vector3(11, 0, -15.5), 4.0, 0.45)
	tree(w, "nature/" + PALMS[rng.randi() % 4], Vector3(-11, 0, -19.5), 4.0)
	tree(w, "nature/" + TREES[rng.randi() % 4], Vector3(11.5, 0, -20.5), 3.5, 0.4)
	tree(w, "nature/" + PALMS[rng.randi() % 4], Vector3(17.2, 0, -20.8), 4.5)
	tree(w, "nature/" + TREES[rng.randi() % 4], Vector3(22.6, 0, -13), 4.0, 0.45)

	for p: Vector3 in [Vector3(-6.4, 0, -21.4), Vector3(6.4, 0, -21.4), Vector3(-7.4, 0, -11.4), Vector3(9.6, 0, -18), Vector3(13.5, 0, -16.5), Vector3(21.5, 0, -12), Vector3(-2.8, 0, -15.6), Vector3(2.8, 0, -15.6), Vector3(4.5, 0, -4.5)]:
		prop(w, "nature/" + PLANTS[rng.randi() % PLANTS.size()], p, rng.randf() * TAU, 3.0 + rng.randf() * 1.5)
	prop(w, "nature/mushroom_redGroup", Vector3(-12.2, 0, -21.6), 0.0, 3.0)
	prop(w, "nature/flower_redA", Vector3(12.4, 0, -21.4), 0.0, 3.0)
	prop(w, "nature/flower_yellowA", Vector3(-8.5, 0, -10.8), 0.0, 3.0)
	prop(w, "survival/campfire-pit", Vector3(18, 0, -22), 0.0, 4.0)

	var x := -36.0
	while x < 36.0:
		var pick := PALMS if rng.randf() < 0.55 else TREES
		prop(w, "nature/" + pick[rng.randi() % 4], Vector3(x, 0, -26.5 - rng.randf() * 14.0), rng.randf() * TAU, 5.0 + rng.randf() * 3.0)
		x += 1.4 + rng.randf() * 1.4
	for i in 3:
		prop(w, "nature/rock_tallB", Vector3(-24 + i * 22, 0, -29), rng.randf() * TAU, 4.0)


func _decorate(gen: Node3D) -> void:
	patch(gen, Vector3.ZERO, Vector2(13, 13), tex("stone_tiles", Color("d6cdb6"), 0.5))
	var under := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	under.mesh = pm
	under.position.y = -0.02
	under.material_override = tex("forest_ground_04", Color("b9c2a4"), 0.2)
	gen.add_child(under)
	Mat.greenify(gen, rng)


func _trunk(w: Node3D, pos: Vector3, length: float) -> void:
	var m := prop(w, "nature/log_large", Vector3.ZERO, 0.0, 1.0)
	var acc := [null]
	_bounds(m, Transform3D.IDENTITY, acc)
	var a: AABB = acc[0]
	var k := Vector3(length / a.size.x, 1.6, 1.6)
	m.scale = k
	m.position = pos - a.get_center() * k
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = a.size * k
	cs.shape = sh
	body.add_child(cs)
	body.position = pos
	w.add_child(body)
