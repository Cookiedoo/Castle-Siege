extends Area3D

# Straight-line projectile fired by Arrow Towers.
# Self-connects body_entered so it works even if .tscn lacks the connection.

var direction: Vector3 = Vector3.ZERO
var damage: int = 10

@export var speed: float = 20.0
@export var lifetime: float = 5.0

var age: float = 0.0


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	global_position += direction * speed * delta
	age += delta
	if age >= lifetime:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
