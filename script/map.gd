class_name Map
extends Node2D
# keep the layout symmetric when rotated 180 around the centre. both players
# see themselves at the bottom, so otherwise they'd get different maps

@export var arena_size := Vector2(1152, 648)


func get_center() -> Vector2:
	return arena_size / 2.0


func spawn_pos(slot: int) -> Vector2:
	var m: Marker2D = $SpawnPoints/Bottom if slot == 0 else $SpawnPoints/Top
	return m.global_position


func pickup_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for m: Marker2D in $PowerupPoints.get_children():
		out.append(m.global_position)
	return out
