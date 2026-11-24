@tool
extends TopdownMap

const PALMS := ["palm-detailed-straight", "palm-detailed-bend", "palm-straight", "palm-bend"]


func _layout() -> void:
	steps = "wood"
	env.background_color = Color(0.85, 0.75, 0.55)
	env.ambient_light_color = Color(0.78, 0.84, 0.95)
	env.ambient_light_energy = 0.68
	env.tonemap_exposure = 0.71
	sun.rotation_degrees = Vector3(-62, -30, 0)
	sun.light_color = Color(1, 0.94, 0.82)
	sun.light_energy = 1.1
	env.adjustment_saturation = 1.0

	ground(tex("dense_sand", Color("f4e4c8"), 0.3))
	var deck := tex("wood_planks", Color("e8c9a4"), 0.6)
	patch(rc(576, 588, 300, 110), deck)
	patch(rc(576, 324, 220, 220), tex("sandstone_blocks_08", Color("eadcbc"), 0.6), false)

	border(26, 2.0, tex("sandstone_blocks_08", Color("d9cbb0"), 0.5))
	row("pirate/castle-wall", Vector2(0, 656), Vector2(1152, 656), 26, 0.0, 0.7)
	row("pirate/castle-wall", Vector2(-8, 0), Vector2(-8, 648), 15, PI / 2.0, 0.7)
	for p: Vector2 in [Vector2(20, 628), Vector2(20, 20)]:
		prop("pirate/tower-complete-small", p, 0.0, 0.8)

	prop("pirate/tower-complete-large", Vector2(576, 324), 0.0, 0.9, "round", false)
	prop("pirate/flag-pirate-high", Vector2(640, 280), 0.0, 1.0, "", false)

	prop("pirate/structure", Vector2(576, 470), 0.0, 1.0, "box")
	prop("pirate/structure-roof", Vector2(576, 470), 0.0, 1.0, "", true, 2.2)
	prop("pirate/barrel", Vector2(500, 486), 0.0, 0.7, "round")
	prop("pirate/barrel", Vector2(652, 456), 0.0, 0.7, "round")

	prop("pirate/rocks-sand-a", Vector2(300, 430), 0.4, 0.5, "round")
	prop("pirate/cannon-mobile", Vector2(870, 470), -0.4, 1.0, "box")
	prop("pirate/crate", Vector2(920, 520), 0.0, 1.0, "box")
	prop("pirate/crate-bottles", Vector2(950, 486), 0.3, 1.0, "box")
	prop("pirate/crate", Vector2(410, 586), 0.2, 1.0, "box")
	prop("pirate/crate-bottles", Vector2(380, 556), 0.0, 1.0, "box")
	prop("pirate/boat-row-small", Vector2(760, 598), 0.3, 1.0, "box")
	prop("pirate/chest", Vector2(1060, 590), 0.6, 0.9, "box")
	prop("pirate/rocks-c", Vector2(1080, 360), 0.0, 0.45, "round")
	prop("pirate/cannon", Vector2(140, 330), PI * 0.5, 1.0, "box")

	for p: Vector2 in [Vector2(80, 560), Vector2(240, 600), Vector2(1080, 470)]:
		prop("pirate/" + PALMS[rng.randi() % PALMS.size()], p, rng.randf() * TAU, 1.0)
		post(p, 10.0)
	prop("pirate/grass-plant", Vector2(470, 400), 0.0, 1.2)
	prop("pirate/flag-pirate", Vector2(300, 470), 0.0, 1.0)

	spawn(Vector2(576, 592))
	team_spawns(Vector2(548, 596), Vector2(604, 596))
	ffa_spawns(Vector2(160, 585), Vector2(990, 600))
	pickups([Vector2(130, 470), Vector2(1010, 420), Vector2(440, 380)])
