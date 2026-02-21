extends TowerBase

# Periodically spawns melee soldier units that chase attackers.
# Soldiers die when this tower is destroyed.

@export var soldier_scene: PackedScene = preload("res://gameplay/towers/knight_soldier.tscn")
@export var max_soldiers: int = 3
@export var spawn_interval: float = 8.0

var spawn_timer: float = 0.0
var soldiers: Array = []


func _ready() -> void:
	tower_name = "Knight Tower"
	damage = 0
	fire_rate = 0.0
	attack_range = 18.0
	max_health = 600
	cost = 250
	super._ready()


func _process(delta: float) -> void:
	if is_preview:
		return

	# Clean dead soldier references
	soldiers = soldiers.filter(func(s: Node) -> bool: return is_instance_valid(s))

	spawn_timer += delta
	if spawn_timer >= spawn_interval and soldiers.size() < max_soldiers:
		spawn_timer = 0.0
		_spawn_soldier()


func _spawn_soldier() -> void:
	if soldier_scene == null:
		return

	var soldier: CharacterBody3D = soldier_scene.instantiate()
	get_tree().current_scene.add_child(soldier)
	soldier.global_position = global_position + Vector3(randf_range(-1.5, 1.5), 0.5, randf_range(-1.5, 1.5))
	soldier.parent_tower = self
	soldiers.append(soldier)


func destroy() -> void:
	for soldier in soldiers:
		if is_instance_valid(soldier):
			soldier.queue_free()
	soldiers.clear()
	super.destroy()


func fire_projectile() -> void:
	pass
