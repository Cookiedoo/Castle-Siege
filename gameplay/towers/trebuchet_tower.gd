extends TowerBase

# Very long range tower that lobs arcing projectiles for area damage.

@export var projectile_scene: PackedScene = preload("res://gameplay/Projectiles/trebuchet_projectile.tscn")


func _ready() -> void:
	tower_name = "Trebuchet"
	damage = 80
	fire_rate = 0.2
	attack_range = 30.0
	max_health = 350
	cost = 400
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

	projectile.damage = damage
	projectile.set_launch_velocity(current_target.global_position, spawn_pos)
