class_name Map
extends Node2D

@export var arena_size := Vector2(1152, 648)
var steps := "concrete"

var spawn_sets := {}


func get_center() -> Vector2:
	return arena_size / 2.0


func spawn_pos(slot: int) -> Vector2:
	var pts: Array = spawn_sets.get(Network.mode, spawn_sets.get("1v1", []))
	var i := Network.spawn_index(slot)
	if i < pts.size():
		return pts[i]
	var m: Marker2D = $SpawnPoints/Bottom if slot == 0 else $SpawnPoints/Top
	return m.global_position


func is_top(slot: int) -> bool:
	return spawn_pos(slot).y < get_center().y


func pickup_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for m: Marker2D in $PowerupPoints.get_children():
		out.append(m.global_position)
	return out
