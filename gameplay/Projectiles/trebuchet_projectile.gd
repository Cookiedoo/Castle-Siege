extends Area3D

# Arcing projectile with area-of-effect damage on landing.
# Used by the Trebuchet Tower.

var damage: int = 80
var direction: Vector3 = Vector3.FORWARD
var velocity_vec: Vector3 = Vector3.ZERO

@export var gravity_strength: float = 15.0
@export var blast_radius: float = 5.0
@export var lifetime: float = 8.0

var age: float = 0.0
var has_exploded: bool = false


func _ready() -> void:
	collision_layer = 8
	collision_mask = 3
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	velocity_vec.y -= gravity_strength * delta
	global_position += velocity_vec * delta

	age += delta
	if age >= lifetime:
		queue_free()


func set_launch_velocity(target_pos: Vector3, launch_pos: Vector3) -> void:
	# Calculate a simple arc to reach the target
	var displacement: Vector3 = target_pos - launch_pos
	var horizontal_dist: float = Vector2(displacement.x, displacement.z).length()
	var flight_time: float = max(horizontal_dist / 12.0, 0.5)

	velocity_vec.x = displacement.x / flight_time
	velocity_vec.z = displacement.z / flight_time
	# Compensate for gravity so the arc lands near the target
	velocity_vec.y = (displacement.y / flight_time) + (0.5 * gravity_strength * flight_time)


func _on_body_entered(body: Node) -> void:
	if has_exploded:
		return
	_explode()


func _explode() -> void:
	has_exploded = true

	# Deal AOE damage to all attackers within blast radius
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape_query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = blast_radius
	shape_query.shape = sphere
	shape_query.transform = global_transform
	shape_query.collision_mask = 2

	var results: Array = space_state.intersect_shape(shape_query, 16)
	for result in results:
		var collider: Node = result.get("collider")
		if collider and collider.has_method("take_damage"):
			collider.take_damage(damage)

	queue_free()
