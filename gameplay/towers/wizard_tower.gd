extends TowerBase

# Slow fire rate, homing projectiles, high burst damage.

@export var projectile_scene: PackedScene = preload("res://gameplay/Projectiles/homing_projectile.tscn")


func _ready() -> void:
	tower_name = "Wizard Tower"
	damage = 40
	fire_rate = 0.5
	attack_range = 12.0
	max_health = 400
	cost = 300
	super._ready()


func fire_projectile() -> void:
	if not current_target or not is_instance_valid(current_target):
		return
	if projectile_scene == null:
		return

	var projectile: Area3D = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)

	var spawn_pos: Vector3 = global_position + Vector3.UP * 2.5
	if projectile_spawn:
		spawn_pos = projectile_spawn.global_position
	projectile.global_position = spawn_pos

	projectile.target = current_target
	projectile.direction = (current_target.global_position - spawn_pos).normalized()
	projectile.damage = damage
