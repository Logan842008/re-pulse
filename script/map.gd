class_name Map
extends Node2D

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
