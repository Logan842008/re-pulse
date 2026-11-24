extends Node

var _maps := {}
var keep := []


func key(is_3d: bool, idx: int) -> String:
	return "%s%d" % ["3d" if is_3d else "2d", idx]


func has_map(is_3d: bool, idx: int) -> bool:
	return _maps.has(key(is_3d, idx))


func take(is_3d: bool, idx: int) -> Node:
	var k := key(is_3d, idx)
	if _maps.has(k):
		var m: Node = _maps[k]
		_maps.erase(k)
		return m
	var m := Maps.scene(is_3d, idx).instantiate()
	if is_3d:
		m.show_markers = false
	m.set_meta("map_key", k)
	return m


func give_back(m: Node) -> void:
	if m.get_parent():
		m.get_parent().remove_child(m)
	_maps[m.get_meta("map_key")] = m


func _exit_tree() -> void:
	for m: Node in _maps.values():
		m.free()
	_maps.clear()
	keep.clear()
