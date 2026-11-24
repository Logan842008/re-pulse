class_name Maps

const D3 := [
	{"name": "Suburbs", "time": "Evening", "scene": "res://scene/maps/suburbs.tscn"},
	{"name": "Frostyard", "time": "Night, snowing", "scene": "res://scene/maps/frostyard.tscn"},
	{"name": "Jungle Ruins", "time": "Afternoon, rain", "scene": "res://scene/maps/jungle.tscn"},
]
const D2 := [
	{"name": "Pirate Fort", "time": "Afternoon", "scene": "res://scene/maps2d/fort2d.tscn"},
	{"name": "Market Square", "time": "Evening", "scene": "res://scene/maps2d/market2d.tscn"},
	{"name": "Graveyard", "time": "Night", "scene": "res://scene/maps2d/graveyard2d.tscn"},
]


static func list(is_3d: bool) -> Array:
	return D3 if is_3d else D2


static func scene(is_3d: bool, idx: int) -> PackedScene:
	var l := list(is_3d)
	return load(l[clampi(idx, 0, l.size() - 1)]["scene"])
