@tool
extends ArenaMap

const TINT := [Color("5b8fbf"), Color("c0583f"), Color("d6d6d6"), Color("dcae48")]
const CONTAINERS := ["a", "b", "c"]
const C_SCALE := 7.5


const STACKS := [
	[-9, -22.5, true, 2],
	[9, -22.5, true, 2],
	[-8.5, -14.5, false, 2],
	[8.5, -13.5, false, 2],
	[17, -19.5, true, 2],
	[0, -15, true, 1],
	[17, -13.5, true, 1],
]


func _layout() -> void:
	weather = "snow"
	steps = "snow"
	tower = Vector3(4, 2.5, 4)
	cover = [
		[-1, -9.5, 1, -8.5, 1.1],
		[3.5, -12.5, 5, -11, 1.2],
		[-5.75, -5.75, -4.25, -4.25, 1.5],
	]
	gun_pts = [Vector2(21.5, -15), Vector2(0, -11.5)]


func _look(role: String, k := 0, b := []) -> Material:
	match role:
		"floor":
			return tex("snow_02", Color("9eabc0"), 0.3)
		"tower":
			return tex("painted_concrete", Color("dfe6ee"), 0.4)
		"outer":
			return tex("painted_concrete", Color("c3cedb"), 0.35)
		"cover":
			if b[4] <= 1.1:
				return tex("painted_concrete", Color("f2c94c"), 0.5)
			return tex("wood_planks", Color.WHITE, 0.6)
		"ramp":
			return tex("metal_plate", Color.WHITE, 0.5)
	return super(role, k, b)


func _stack(w: Node3D, cx: float, cz: float, turned: bool, levels: int, solid := true) -> void:
	var sz := Vector3(6, 2.25, 3) if turned else Vector3(3, 2.25, 6)
	for i in levels:
		var m := prop(w, "industrial/shipping-container-" + CONTAINERS[rng.randi() % 3], Vector3.ZERO, PI / 2.0 if turned else 0.0, C_SCALE)
		var acc := [null]
		_bounds(m, Transform3D.IDENTITY, acc)
		var c: Vector3 = m.basis * (acc[0] as AABB).get_center()
		var bottom: float = (acc[0] as AABB).position.y * C_SCALE
		m.position = Vector3(cx - c.x, i * (sz.y + 0.01) - bottom, cz - c.z)
	if solid:
		box(w, Vector3(cx, sz.y * levels / 2.0, cz), Vector3(sz.x, sz.y * levels, sz.z), null).get_child(0).queue_free()


func _decorate_wedge(w: Node3D, k: int) -> void:
	var road := tex("asphalt_snow", Color.WHITE, 0.3)
	patch(w, Vector3(0, 0, -15), Vector2(8, 12), road)
	patch(w, Vector3(0, 0, -22), Vector2(12, 4), road)

	for s: Array in STACKS:
		_stack(w, s[0], s[1], s[2], s[3])

	for p: Vector3 in [Vector3(-6.4, 0, -19.6), Vector3(10.6, 0, -13), Vector3(4.6, 0, -6.5), Vector3(19.5, 0, -22.5)]:
		prop(w, "holiday/lantern", p, 0.0, 2.4)
		lamp(w, p + Vector3(0, 3.9, 0), Color("ffd29a") if k % 2 == 0 else Color("bcd6ff"), 3.2, 12.0)

	for p: Vector3 in [Vector3(-12, 0, -20.2), Vector3(11.5, 0, -19.6), Vector3(-6, 0, -12), Vector3(8.5, 0, -8.5), Vector3(22.5, 0, -16)]:
		prop(w, "holiday/snow-pile", p, rng.randf() * TAU, 2.5)
	prop(w, "cars/tractor-shovel", Vector3(22, 0, -21.5), 0.0, 1.0, true)
	prop(w, "survival/barrel", Vector3(16.2, 0, -22.9), 0.0, 4.0, true)
	prop(w, "survival/barrel", Vector3(17.5, 0, -22.9), 0.0, 4.0, true)

	for i in 4:
		var cx := -21.0 + i * 14.0
		_stack(w, cx, -29, true, 1, false)
		if i % 2 == 0:
			_stack(w, cx + 1, -32.5, true, 2, false)
	prop(w, "industrial/water-tower", Vector3(26, 0, -33), 0.3, 6.0)
	prop(w, "industrial/detail-tank-large", Vector3(-8, 0, -35), 0.0, 4.5)
	var x := -34.0
	while x < 34.0:
		prop(w, "holiday/tree-snow-" + ["a", "b", "c"][rng.randi() % 3], Vector3(x, 0, -38 - rng.randf() * 5.0), rng.randf() * TAU, 3.5 + rng.randf())
		x += 4.5 + rng.randf() * 2.0
	prop(w, "holiday/rocks-large", Vector3(-30, 0, -31), rng.randf() * TAU, 2.0)


func _decorate(gen: Node3D) -> void:
	var under := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	under.mesh = pm
	under.position.y = -0.02
	under.material_override = tex("snow_02", Color("8794aa"), 0.2)
	gen.add_child(under)
