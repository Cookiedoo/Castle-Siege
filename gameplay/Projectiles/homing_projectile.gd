extends Area3D

# Homing projectile that curves toward its target.
# Used by the Wizard Tower.

var target: Node3D = null
var damage: int = 40
var direction: Vector3 = Vector3.FORWARD

@export var speed: float = 14.0
@export var turn_speed: float = 4.0
@export var lifetime: float = 6.0

var age: float = 0.0


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if target and is_instance_valid(target):
		var desired: Vector3 = (target.global_position - global_position).normalized()
		direction = direction.lerp(desired, turn_speed * delta).normalized()

	global_position += direction * speed * delta

	age += delta
	if age >= lifetime:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
