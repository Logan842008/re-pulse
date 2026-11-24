@tool
extends TopdownMap

const TREES := ["tree-high-round", "tree-high", "tree"]


func _layout() -> void:
	steps = "concrete"
	env.background_color = Color(0.2, 0.14, 0.18)
	env.ambient_light_color = Color(0.82, 0.74, 0.96)
	env.ambient_light_energy = 1.5
	env.tonemap_exposure = 1.25
	sun.rotation_degrees = Vector3(-36, -60, 0)
	sun.light_color = Color(1, 0.72, 0.62)
	sun.light_energy = 1.6

	ground(tex("stone_tiles", Color.WHITE, 0.45))
	var lawn := tex("leafy_grass", Color("a8c890"), 0.5)
	patch(Rect2(26, 470, 240, 152), lawn)
	patch(Rect2(886, 470, 240, 152), lawn)
	patch(rc(576, 324, 260, 180), tex("cobblestone_pavement", Color("f0e6e0"), 0.5), false)

	border(28, 2.0, tex("large_sandstone_blocks", Color("c8beb2"), 0.5))
	row("castle/wall", Vector2(0, 660), Vector2(1152, 660), 23, 0.0, 1.6)
	row("castle/wall", Vector2(-12, 0), Vector2(-12, 648), 13, PI / 2.0, 1.6)
	for p: Vector2 in [Vector2(14, 634), Vector2(14, 14)]:
		prop("castle/tower-square-base-color", p, 0.0, 1.8)
		prop("castle/tower-square-top-roof-high", p, 0.0, 1.8, "", true, 1.8)

	prop("town/fountain-round-detail", Vector2(576, 324), 0.0, 2.2, "round", false)

	for i in 3:
		var kind := "town/stall-red" if i != 1 else "town/stall-green"
		prop(kind, Vector2(512 + i * 64, 474), 0.0, 2.0, "box")
	prop("town/cart-high", Vector2(330, 420), 0.4, 2.0, "box")
	prop("town/cart", Vector2(860, 560), -0.3, 2.0, "box")
	prop("castle/siege-catapult", Vector2(900, 400), PI * 0.5, 1.8, "box")
	prop("survival/barrel", Vector2(420, 590), 0.0, 4.0, "round")
	prop("survival/barrel", Vector2(448, 570), 0.0, 4.0, "round")
	prop("town/rock-large", Vector2(1060, 340), 0.3, 1.6, "round")

	var hedge := "town/hedge-large"
	row(hedge, Vector2(266, 476), Vector2(266, 600), 4, 0.0, 2.0)
	block(rc(266, 538, 22, 124))
	row(hedge, Vector2(700, 490), Vector2(760, 490), 2, PI / 2.0, 2.0)
	block(rc(730, 490, 64, 22))

	for p: Vector2 in [Vector2(90, 540), Vector2(190, 590), Vector2(1080, 520)]:
		prop("town/" + TREES[rng.randi() % TREES.size()], p, rng.randf() * TAU, 2.0)
		post(p, 9.0)

	for p: Vector2 in [Vector2(470, 400), Vector2(700, 600), Vector2(160, 420), Vector2(1010, 600)]:
		prop("town/lantern", p, 0.0, 2.0)
		post(p, 6.0)
	lamp(Vector2(470, 400), Color("ffb066"), 2.2, 7.0)
	lamp(Vector2(700, 600), Color("ffb066"), 2.2, 7.0)
	lamp(Vector2(160, 420), Color("ffb066"), 1.8, 6.0)
	lamp(Vector2(1010, 600), Color("ffb066"), 1.8, 6.0)
	prop("town/banner-red", Vector2(640, 420), 0.0, 2.0)
	prop("town/stall-bench", Vector2(560, 560), PI / 2.0, 2.0)

	spawn(Vector2(576, 592))
	team_spawns(Vector2(520, 596), Vector2(632, 596))
	ffa_spawns(Vector2(130, 590), Vector2(1050, 570))
	pickups([Vector2(130, 380), Vector2(1000, 450), Vector2(420, 330)])
