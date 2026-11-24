@tool
extends TopdownMap

const STONES := ["gravestone-round", "gravestone-cross", "gravestone-roof", "gravestone-bevel", "gravestone-decorative"]
const PINES := ["pine", "pine-crooked", "pine-fall", "pine-fall-crooked"]
const S := 2.4


func _layout() -> void:
	steps = "grass"
	env.background_color = Color(0.03, 0.04, 0.07)
	env.ambient_light_color = Color(0.46, 0.5, 0.64)
	env.ambient_light_energy = 1.0
	sun.rotation_degrees = Vector3(-58, 40, 0)
	sun.light_color = Color(0.78, 0.84, 1.0)
	sun.light_energy = 0.6
	env.adjustment_saturation = 0.85

	ground(tex("forest_leaves_02", Color("a3a89c"), 0.35))
	var path := tex("stone_pathway_02", Color("a9a8b4"), 0.5)
	patch(Rect2(546, 500, 60, 124), path)
	patch(rc(576, 324, 300, 70), path, false)
	patch(rc(576, 324, 70, 250), path, false)

	border(26, 1.6, tex("mossy_rock", Color("8c8c8c"), 0.5))
	row("graveyard/stone-wall", Vector2(0, 635), Vector2(1152, 635), 15, 0.0, S * 1.1)
	row("graveyard/stone-wall", Vector2(13, 0), Vector2(13, 648), 8, PI / 2.0, S * 1.1)

	prop("graveyard/crypt-large", Vector2(576, 324), PI / 2.0, S, "box", false)
	prop("graveyard/crypt-large-roof", Vector2(576, 324), PI / 2.0, S, "", false, 1.0 * S)

	prop("graveyard/crypt-small", Vector2(576, 470), 0.0, S, "box")
	prop("graveyard/crypt-small-roof", Vector2(576, 470), 0.0, S, "", true, 1.0 * S)

	for r in 2:
		for i in 4:
			var p := Vector2(250 + i * 46, 420 + r * 90)
			prop("graveyard/" + STONES[rng.randi() % STONES.size()], p, 0.0, S, "box")
	for i in 3:
		prop("graveyard/" + STONES[rng.randi() % STONES.size()], Vector2(820 + i * 46, 470), 0.0, S, "box")

	row("graveyard/iron-fence", Vector2(760, 560), Vector2(920, 560), 3, 0.0, S * 0.9)
	block(rc(840, 560, 160, 20))
	prop("graveyard/crypt", Vector2(1040, 360), 0.0, S, "box")
	prop("graveyard/coffin", Vector2(420, 600), 0.4, S)
	prop("graveyard/rocks-tall", Vector2(140, 330), 0.0, S, "round")
	prop("graveyard/altar-stone", Vector2(700, 410), 0.3, S, "box")

	for p: Vector2 in [Vector2(80, 560), Vector2(200, 600), Vector2(1080, 560), Vector2(1000, 400)]:
		prop("graveyard/" + PINES[rng.randi() % PINES.size()], p, rng.randf() * TAU, S)
		post(p, 9.0)

	for p: Vector2 in [Vector2(500, 590), Vector2(700, 520), Vector2(140, 440), Vector2(1040, 480)]:
		prop("graveyard/lightpost-single", p, 0.0, S)
		post(p, 6.0)
	lamp(Vector2(500, 590), Color("ffcf7a"), 2.0, 6.0)
	lamp(Vector2(700, 520), Color("ffcf7a"), 2.0, 6.0)
	lamp(Vector2(140, 440), Color("9dffb0"), 1.8, 6.0)
	lamp(Vector2(1040, 480), Color("ffcf7a"), 1.8, 6.0)
	for p: Vector2 in [Vector2(330, 340), Vector2(900, 620), Vector2(470, 520), Vector2(980, 520)]:
		prop("graveyard/pumpkin-carved", p, rng.randf() * TAU, S)
		lamp(p, Color("ff8a3c"), 1.2, 4.0, 0.8)

	spawn(Vector2(576, 592))
	team_spawns(Vector2(532, 596), Vector2(630, 596))
	ffa_spawns(Vector2(140, 600), Vector2(1000, 600))
	pickups([Vector2(105, 400), Vector2(1000, 600), Vector2(430, 390)])
