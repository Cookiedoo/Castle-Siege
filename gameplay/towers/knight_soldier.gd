extends CharacterBody3D

# Simple melee AI soldier spawned by the Knight Tower.
# Chases the nearest attacker and hits them on contact.

@export var move_speed: float = 4.5
@export var melee_damage: int = 15
@export var attack_cooldown: float = 1.0
@export var max_health: int = 60
@export var chase_range: float = 20.0

var current_health: int
var attack_timer: float = 0.0
var target: Node3D = null
var parent_tower: Node3D = null


func _ready() -> void:
	current_health = max_health
	collision_layer = 4
	collision_mask = 3


func _physics_process(delta: float) -> void:
	attack_timer = max(0.0, attack_timer - delta)

	_apply_gravity(delta)
	_find_target()
	_chase_and_attack(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 20.0 * delta


func _find_target() -> void:
	if target and is_instance_valid(target):
		if target.has_method("is_alive") and target.is_alive():
			var dist: float = global_position.distance_to(target.global_position)
			if dist <= chase_range:
				return
	target = null

	var best_dist: float = chase_range
	for attacker in get_tree().get_nodes_in_group("attackers"):
		if not is_instance_valid(attacker):
			continue
		if attacker.has_method("is_alive") and not attacker.is_alive():
			continue
		var dist: float = global_position.distance_to(attacker.global_position)
		if dist < best_dist:
			best_dist = dist
			target = attacker


func _chase_and_attack(_delta: float) -> void:
	if not target or not is_instance_valid(target):
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var direction: Vector3 = (target.global_position - global_position)
	direction.y = 0.0
	var dist: float = direction.length()

	if dist > 1.5:
		direction = direction.normalized()
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		# Face movement direction
		look_at(global_position + direction, Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if attack_timer <= 0.0:
			_melee_attack()


func _melee_attack() -> void:
	attack_timer = attack_cooldown
	if target and is_instance_valid(target) and target.has_method("take_damage"):
		target.take_damage(melee_damage)


func take_damage(amount: int) -> void:
	current_health -= amount
	if current_health <= 0:
		queue_free()
