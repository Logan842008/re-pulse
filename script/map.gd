class_name Map
extends Node2D
## The arena. Walls, spawn points and powerup spots can be moved freely in the
## editor. Keep the layout symmetric when rotated 180 degrees around the centre
## so both players (who each see themselves at the bottom) get the same map.

@export var arena_size := Vector2(1152, 648)


func get_center() -> Vector2:
	return arena_size / 2.0


func get_spawn_position(slot: int) -> Vector2:
	var marker: Marker2D = $SpawnPoints/Bottom if slot == 0 else $SpawnPoints/Top
	return marker.global_position


func get_powerup_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for marker: Marker2D in $PowerupPoints.get_children():
		positions.append(marker.global_position)
	return positions
