extends Node3D
class_name MapConfig

# Per-map configuration node. Place one of these inside each map scene.
# Set all positions in the editor by moving child Marker3D nodes or by
# typing world-space coordinates directly into the exported arrays.
# GameWorld reads this after loading the map and repositions all game objects.

# Where the Castle node should sit on this map.
@export var castle_position: Vector3 = Vector3(0, 2, 0)

# Where the King's camera starts (height and XZ center of the map).
@export var king_camera_start: Vector3 = Vector3(0, 40, 10)

# Attacker spawn positions. Must have at least one entry.
# Order matches Attacker1, Attacker2, Attacker3 in the scene.
@export var spawn_positions: Array[Vector3] = [
	Vector3(-20, 2, 30),
	Vector3(20, 2, 30),
	Vector3(0, 2, -30),
]

# Resource node positions for NodeA, NodeB, NodeC.
@export var resource_node_positions: Array[Vector3] = [
	Vector3(-20, 2, 0),
	Vector3(20, 2, 0),
	Vector3(0, 2, -20),
]

# Y position of the death zone floor (kill plane below the map).
@export var death_zone_y: float = -30.0
