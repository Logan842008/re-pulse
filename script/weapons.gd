class_name Weapons

const MODEL := "res://assets/models/blaster/blaster-%s.glb"

const LIST := [
	{
		"name": "PULSE", "dmg": 20, "delay": 0.3, "pellets": 1, "spread": 0.0,
		"speed": 26.0, "bounces": 3, "ammo": -1, "size": 0.09, "kick": 0.8,
		"zoom": 1.25, "scope": false, "head": 2.5, "legs": 0.85, "run_err": 4.0, "hip_err": 0.0,
		"model": "b",
	},
	{
		"name": "BURST", "dmg": 9, "delay": 0.09, "pellets": 1, "spread": 2.0,
		"speed": 30.0, "bounces": 3, "ammo": 45, "size": 0.07, "kick": 0.3,
		"zoom": 1.25, "scope": false, "head": 2.5, "legs": 0.85, "run_err": 5.0, "hip_err": 0.0,
		"model": "h",
	},
	{
		"name": "SCATTER", "dmg": 8, "delay": 0.8, "pellets": 6, "spread": 7.0,
		"speed": 22.0, "bounces": 2, "ammo": 8, "size": 0.07, "kick": 3.0,
		"zoom": 1.0, "scope": false, "head": 2.0, "legs": 0.85, "run_err": 2.0, "hip_err": 0.0,
		"model": "q",
	},
	{
		"name": "RAIL", "dmg": 45, "delay": 0.8, "pellets": 1, "spread": 0.0,
		"speed": 60.0, "bounces": 5, "ammo": 6, "size": 0.12, "kick": 2.0,
		"zoom": 2.5, "scope": true, "head": 4.5, "legs": 0.85, "run_err": 9.0, "hip_err": 5.0,
		"model": "e",
	},
]


static func build_model(idx: int, col: Color, s := 1.0) -> Node3D:
	var root := Node3D.new()
	var gun: Node3D = load(MODEL % LIST[idx]["model"]).instantiate()
	gun.scale = Vector3.ONE * s
	root.add_child(gun)
	var acc := [null]
	_bounds(gun, gun.transform, acc)
	var box: AABB = acc[0]
	var shift := -box.get_center()
	shift.z = -(box.end.z - box.size.z * 0.35)
	gun.position += shift
	box.position += shift

	var glow := StandardMaterial3D.new()
	glow.albedo_color = col
	glow.emission_enabled = true
	glow.emission = col
	glow.emission_energy_multiplier = 2.0
	var strip := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03 * s, 0.012 * s, box.size.z * 0.4)
	strip.mesh = bm
	strip.material_override = glow
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strip.position = box.get_center() + Vector3(0, box.size.y * 0.5, 0)
	root.add_child(strip)

	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(box.get_center().x, box.position.y + box.size.y * 0.75, box.position.z)
	root.add_child(muzzle)
	return root


static func _bounds(n: Node, xf: Transform3D, acc: Array) -> void:
	if n is MeshInstance3D:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a: AABB = xf * n.get_aabb()
		acc[0] = a if acc[0] == null else acc[0].merge(a)
	for c in n.get_children():
		_bounds(c, xf * c.transform if c is Node3D else xf, acc)
