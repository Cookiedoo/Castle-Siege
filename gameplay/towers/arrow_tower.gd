extends TowerBase

# Fast fire rate, low damage, short-to-medium range pressure tower.

@export var projectile_scene: PackedScene = preload("res://gameplay/Projectiles/arrow_projectile.tscn")


func _ready() -> void:
	tower_name = "Arrow Tower"
	damage = 15
	fire_rate = 1.5
	attack_range = 14.0
	max_health = 500
	cost = 100
	super._ready()


func fire_projectile() -> void:
	if not current_target or not is_instance_valid(current_target):
		return
	if projectile_scene == null:
		return

	var projectile: Area3D = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)

	var spawn_pos: Vector3 = global_position + Vector3.UP * 2.0
	if projectile_spawn:
		spawn_pos = projectile_spawn.global_position
	projectile.global_position = spawn_pos

	projectile.direction = (current_target.global_position - spawn_pos).normalized()
	projectile.damage = damage
