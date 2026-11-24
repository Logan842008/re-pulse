@tool
extends ArenaMap

const WALLS := [
	["whitewashed_brick", Color("b4d2ea")],
	["red_brick_03", Color.WHITE],
	["whitewashed_brick", Color.WHITE],
	["whitewashed_brick", Color("f2dd9c")],
]
const HOUSES := ["a", "b", "c", "d", "f", "h", "k", "m", "o", "r", "t"]
const CARS := ["sedan", "suv", "van", "taxi", "hatchback-sports"]


func _layout() -> void:
	blocks = [
		[-12, -24, -5, -18, wall_h],
		[5, -21, 12, -18, wall_h],
		[-12, -18, -4, -16, wall_h],
		[-8, -12, -4, -8, wall_h],
		[4, -18, 12, -8, wall_h],
	]
	cover = [
		[-2.5, -16.5, 2.5, -16, 3.0],
		[-3.5, -11, -1.5, -10.5, 1.2],
		[1.9, -13.6, 3.1, -12.4, 1.2],
		[4.25, -5.75, 5.75, -4.25, 1.5],
		[17.5, -18.5, 18.5, -17.5, 4.0],
		[14.4, -21.6, 15.6, -20.4, 1.2],
		[20.4, -15.6, 21.6, -14.4, 1.2],
	]
	roofs = [
		[12, -24, 24, -12],
		[5, -24, 12, -21],
	]
	gun_pts = [Vector2(15, -15), Vector2(-0.5, -13)]


func _look(role: String, k := 0, b := []) -> Material:
	match role:
		"floor":
			return tex("asphalt_02", Color("d6d2cc"), 0.25)
		"tower":
			return tex("whitewashed_brick", Color.WHITE, 0.4)
		"outer":
			return tex("red_brick_03", Color("d9c9c0"), 0.4)
		"wall":
			return tex(WALLS[k][0], WALLS[k][1], 0.35)
		"cover":
			var h: float = b[4]
			if h >= 4.0:
				return tex("whitewashed_brick", Color.WHITE, 0.5)
			if h >= 2.0:
				return tex("wood_planks", Color("e6d3b6"), 0.6)
			return tex("leafy_grass", Color("7fa866"), 0.8)
		"ramp":
			return tex("wood_planks", Color.WHITE, 0.6)
		"roof":
			return tex("grey_roof_tiles", Color.WHITE, 0.4)
		"indoor":
			return tex("wood_floor", Color.WHITE, 0.5)
		"ceiling":
			return tex("white_stucco", Color.WHITE, 0.35)
	return super(role, k, b)


func _decorate_wedge(w: Node3D, _k: int) -> void:
	var lawn := tex("leafy_grass", Color("9fbf86"), 0.5)
	var walk := tex("concrete_pavement", Color.WHITE, 0.4)
	patch(w, Vector3(-10, 0, -14), Vector2(4, 4), lawn)
	patch(w, Vector3(0, 0, -21), Vector2(10, 6), walk)
	patch(w, Vector3(-3.4, 0, -12.5), Vector2(1.2, 7), walk, 0.012)
	patch(w, Vector3(3.4, 0, -12.5), Vector2(1.2, 7), walk, 0.012)

	for p: Vector3 in [Vector3(-3.5, 0, -9), Vector3(3.5, 0, -15), Vector3(6, 0, -7)]:
		prop(w, "holiday/lantern", p, 0.0, 2.2)
		lamp(w, p + Vector3(0, 3.6, 0), Color("ffb36b"), 2.0, 10.0)

	mesh_collider(prop(w, "cars/" + CARS[rng.randi() % CARS.size()], Vector3(-2.6, 0, -14.4), 0.1, 1.0))
	prop(w, "suburban/planter", Vector3(-4.3, 0, -23.2), 0.0, 4.0)
	prop(w, "suburban/planter", Vector3(4.3, 0, -23.2), 0.0, 4.0)

	var x := -28.0
	while x < 30.0:
		var house: String = "suburban/building-type-" + HOUSES[rng.randi() % HOUSES.size()]
		prop(w, house, Vector3(x, 0, -34 - rng.randf() * 3.0), 0.0, 8.0)
		prop(w, "suburban/tree-large", Vector3(x + 5.5, 0, -28), rng.randf() * TAU, 10.0)
		x += 11.0


func _decorate(gen: Node3D) -> void:
	patch(gen, Vector3.ZERO, Vector2(16, 16), tex("concrete_pavement", Color.WHITE, 0.4))
	prop(gen, "suburban/tree-large", Vector3(0, 3, 0) + Vector3(1.3, 0, 1.3), 0.0, 6.0)
	var under := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(110, 110)
	under.mesh = pm
	under.position.y = -0.02
	under.material_override = tex("leafy_grass", Color("8fb07a"), 0.3)
	gen.add_child(under)
