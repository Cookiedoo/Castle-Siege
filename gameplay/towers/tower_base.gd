extends Node3D
class_name TowerBase

# -- Tower Stats (override in subclasses) --
@export var tower_name: String = "Basic Tower"
@export var max_health: int = 500
@export var damage: int = 20
@export var fire_rate: float = 1.0
@export var attack_range: float = 15.0
@export var cost: int = 100

# -- Runtime State --
var current_health: int
var current_target: Node3D = null
var last_fire_time: float = 0.0
var is_preview: bool = false
var can_place: bool = true

# -- Visual Feedback --
var health_label: Label3D = null
var flash_restore_timer: Timer = null

# Range ring cache — building these once prevents shader recompile stutter
var _ring_mat_valid: StandardMaterial3D = null
var _ring_mat_invalid: StandardMaterial3D = null
var _ring_mesh: CylinderMesh = null
var _last_valid_state: bool = true
# Ghost preview material cache — same reason: avoid per-frame shader recompile
var _ghost_mat_valid: StandardMaterial3D = null
var _ghost_mat_invalid: StandardMaterial3D = null

# How close a tower must be to a resource node to claim it for the king
const RESOURCE_CLAIM_RADIUS: float = 8.0

# -- Node References --
@onready var detection_area: Area3D = $DetectionArea
@onready var projectile_spawn: Node3D = $ProjectileSpawn
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	current_health = max_health
	if not is_preview:
		add_to_group("towers")
		_setup_detection_area()
		_create_health_label()
		_setup_flash_timer()
		# Defer so resource nodes have time to enter the tree
		call_deferred("_claim_nearby_resource_nodes")


func _setup_flash_timer() -> void:
	flash_restore_timer = Timer.new()
	flash_restore_timer.wait_time = 0.15
	flash_restore_timer.one_shot = true
	flash_restore_timer.timeout.connect(_on_flash_timeout)
	add_child(flash_restore_timer)


func _on_flash_timeout() -> void:
	# Unconditionally clear the flash override
	if mesh_instance:
		mesh_instance.material_override = null


func _setup_detection_area() -> void:
	if not detection_area:
		return

	var has_shape: bool = false
	for child in detection_area.get_children():
		if child is CollisionShape3D:
			has_shape = true
			break

	if not has_shape:
		var shape := SphereShape3D.new()
		shape.radius = attack_range
		var collision := CollisionShape3D.new()
		collision.shape = shape
		detection_area.add_child(collision)

	detection_area.collision_layer = 0
	detection_area.collision_mask = 2

	if not detection_area.body_entered.is_connected(_on_enemy_entered_range):
		detection_area.body_entered.connect(_on_enemy_entered_range)
	if not detection_area.body_exited.is_connected(_on_enemy_exited_range):
		detection_area.body_exited.connect(_on_enemy_exited_range)


func _create_health_label() -> void:
	health_label = Label3D.new()
	health_label.text = str(current_health) + "/" + str(max_health)
	health_label.font_size = 24
	health_label.modulate = Color(1, 1, 1, 0.9)
	health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_label.no_depth_test = true
	health_label.position = Vector3(0, 3.5, 0)
	add_child(health_label)
	_update_health_display()


func _update_health_display() -> void:
	if not health_label:
		return
	if is_preview:
		health_label.visible = false
		return

	health_label.text = str(current_health) + "/" + str(max_health)

	var pct: float = float(current_health) / float(max_health)
	if pct > 0.6:
		health_label.modulate = Color(0.3, 1.0, 0.3, 0.9)
	elif pct > 0.3:
		health_label.modulate = Color(1.0, 0.8, 0.2, 0.9)
	else:
		health_label.modulate = Color(1.0, 0.2, 0.2, 0.9)


func _claim_nearby_resource_nodes() -> void:
	for node in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(node):
			continue
		var dist: float = global_position.distance_to(node.global_position)
		if dist <= RESOURCE_CLAIM_RADIUS:
			if node.has_method("set_owner_by_tower"):
				node.set_owner_by_tower("king")


func _process(delta: float) -> void:
	if is_preview:
		return

	if current_target and is_instance_valid(current_target):
		if _is_valid_target(current_target):
			_rotate_to_target(delta)
			_attempt_fire(delta)
		else:
			current_target = null
	else:
		_acquire_target()


func _is_valid_target(target_node: Node) -> bool:
	if not target_node.is_in_group("attackers"):
		return false
	if target_node.has_method("is_alive") and not target_node.is_alive():
		return false
	return true


func _acquire_target() -> void:
	if not detection_area:
		return

	var enemies: Array = detection_area.get_overlapping_bodies()
	var valid_enemies: Array = []

	for enemy in enemies:
		if _is_valid_target(enemy):
			valid_enemies.append(enemy)

	if valid_enemies.size() > 0:
		current_target = _get_nearest_enemy(valid_enemies)


func _get_nearest_enemy(enemies: Array) -> Node3D:
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for enemy in enemies:
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest = enemy
			nearest_dist = dist

	return nearest


func _rotate_to_target(delta: float) -> void:
	if not current_target:
		return
	var direction: Vector3 = current_target.global_position - global_position
	var target_rotation: float = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)


func _attempt_fire(_delta: float) -> void:
	var current_time: float = Time.get_ticks_msec() / 1000.0
	if fire_rate <= 0.0:
		return
	if current_time - last_fire_time >= 1.0 / fire_rate:
		fire_projectile()
		last_fire_time = current_time


func fire_projectile() -> void:
	pass


func take_damage(amount: int) -> void:
	current_health -= amount
	current_health = max(0, current_health)
	_update_health_display()
	_flash_hit()
	if current_health <= 0:
		destroy()


func _flash_hit() -> void:
	if not mesh_instance:
		return
	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.3, 0.3, 1.0)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.0, 0.0)
	flash_mat.emission_energy_multiplier = 2.0
	mesh_instance.material_override = flash_mat
	# Restart the restore timer (resets if already running)
	if flash_restore_timer:
		flash_restore_timer.start()


func destroy() -> void:
	remove_from_group("towers")

	for node in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(node):
			continue
		if node.has_method("on_tower_destroyed"):
			var dist: float = global_position.distance_to(node.global_position)
			if dist <= RESOURCE_CLAIM_RADIUS:
				node.on_tower_destroyed()

	_push_kill_feed(tower_name + " destroyed!")
	queue_free()


func _push_kill_feed(msg: String) -> void:
	for node in get_tree().get_nodes_in_group("kill_feed"):
		if node.has_method("push"):
			node.push(msg)
			return



func _on_enemy_entered_range(body: Node3D) -> void:
	if body.is_in_group("attackers") and not current_target:
		current_target = body


func _on_enemy_exited_range(body: Node3D) -> void:
	if body == current_target:
		current_target = null


func set_preview_mode(preview: bool, valid: bool = true) -> void:
	is_preview = preview
	can_place = valid

	if mesh_instance:
		if not _ghost_mat_valid:
			_ghost_mat_valid = StandardMaterial3D.new()
			_ghost_mat_valid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_ghost_mat_valid.albedo_color = Color(0.2, 0.8, 0.2, 0.45)
		if not _ghost_mat_invalid:
			_ghost_mat_invalid = StandardMaterial3D.new()
			_ghost_mat_invalid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_ghost_mat_invalid.albedo_color = Color(0.9, 0.2, 0.2, 0.45)
		mesh_instance.material_override = _ghost_mat_valid if valid else _ghost_mat_invalid

	if health_label:
		health_label.visible = false

	if preview:
		for child in get_children():
			if child is StaticBody3D:
				child.collision_layer = 0
				child.collision_mask = 0
		# Only rebuild when validity flips or ring doesn't exist yet
		if valid != _last_valid_state or get_node_or_null("_RangeRing") == null:
			_last_valid_state = valid
			_show_range_ring(valid)
	else:
		_hide_range_ring()


func _show_range_ring(valid: bool) -> void:
	if attack_range <= 0.0:
		return

	# Build materials once — reusing the same object means Godot never
	# recompiles the shader, which eliminates the fade-in stutter.
	if not _ring_mat_valid:
		_ring_mat_valid = StandardMaterial3D.new()
		_ring_mat_valid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat_valid.no_depth_test = true
		_ring_mat_valid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat_valid.albedo_color = Color(0.2, 0.8, 0.2, 0.3)

	if not _ring_mat_invalid:
		_ring_mat_invalid = StandardMaterial3D.new()
		_ring_mat_invalid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat_invalid.no_depth_test = true
		_ring_mat_invalid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat_invalid.albedo_color = Color(0.8, 0.2, 0.2, 0.25)

	# Reuse the existing ring node if it exists — only swap the material
	var ring_instance: MeshInstance3D = get_node_or_null("_RangeRing")
	if not ring_instance:
		if not _ring_mesh:
			_ring_mesh = CylinderMesh.new()
			_ring_mesh.top_radius = attack_range
			_ring_mesh.bottom_radius = attack_range
			_ring_mesh.height = 0.05
			_ring_mesh.rings = 1
			_ring_mesh.radial_segments = 32
		ring_instance = MeshInstance3D.new()
		ring_instance.name = "_RangeRing"
		ring_instance.mesh = _ring_mesh
		ring_instance.position = Vector3(0, -0.5, 0)
		add_child(ring_instance)

	_ring_mesh.material = _ring_mat_valid if valid else _ring_mat_invalid


func _hide_range_ring() -> void:
	var existing: Node = get_node_or_null("_RangeRing")
	if existing:
		existing.queue_free()
