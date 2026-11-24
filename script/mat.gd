class_name Mat

const TEX := "res://assets/textures/%s/%s_%s_1k.jpg"

static var _cache := {}


static func tex(name: String, tint := Color.WHITE, scale := 0.4, wet := 0.0) -> StandardMaterial3D:
	var key := "%s_%s_%s_%s" % [name, tint.to_html(), scale, wet]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(TEX % [name, name, "diff"])
		m.albedo_color = tint.darkened(wet * 0.2)
		m.normal_enabled = true
		m.normal_texture = load(TEX % [name, name, "nor_gl"])
		m.normal_scale = 0.25
		m.roughness_texture = load(TEX % [name, name, "rough"])
		m.roughness = 1.0 - wet * 0.55
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * scale
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_cache[key] = m
	return _cache[key]


static func greenify(root: Node, rng: RandomNumberGenerator) -> void:
	var done := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if m == null:
				continue
			var c := m.albedo_color
			if not (c.g > 0.5 and c.b > 0.45 and c.r < 0.5):
				continue
			if not done.has(m):
				var g := m.duplicate() as StandardMaterial3D
				g.albedo_color = Color.from_hsv(0.29 + rng.randf() * 0.04, 0.62, c.v * 0.72)
				done[m] = g
			mi.set_surface_override_material(i, done[m])
