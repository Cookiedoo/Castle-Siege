extends Node
class_name BuildController

signal placement_validated(valid: bool, position: Vector3)
signal tower_placed(tower_type: String, position: Vector3)
signal build_mode_changed(active: bool)

@export var snap_to_grid: bool = true
@export var grid_size: float = 1.0
@export var min_tower_spacing: float = 3.5
@export var max_towers: int = 20
@export var default_castle_exclusion_radius: float = 6.0

var is_building := false
var selected_tower_type := ""
var tower_preview: Node3D = null
var preview_position := Vector3.ZERO

var game_manager: GameManager = null
var king_camera: Camera3D = null
var towers_root: Node3D = null
var castle: Node3D = null
var castle_exclusion_radius := 0.0

var tower_scenes := {
	"arrow": preload("res://gameplay/towers/arrow_tower.tscn"),
	"wizard": preload("res://gameplay/towers/wizard_tower.tscn"),
	"knight": preload("res://gameplay/towers/knight_tower.tscn"),
	"wall": preload("res://gameplay/towers/defensive_wall.tscn"),
	"trebuchet": preload("res://gameplay/towers/trebuchet_tower.tscn"),
}

var tower_costs := {
	"arrow": 100,
	"wizard": 300,
	"knight": 250,
	"wall": 75,
	"trebuchet": 400,
}


func _ready() -> void:
	add_to_group("build_controller")

	var managers := get_tree().get_nodes_in_group("game_manager")
	if not managers.is_empty():
		game_manager = managers[0] as GameManager

	var castles := get_tree().get_nodes_in_group("castle")
	if not castles.is_empty():
		castle = castles[0] as Node3D
		_resolve_castle_exclusion_radius()

	towers_root = get_node_or_null("../Towers")
	if towers_root == null:
		towers_root = Node3D.new()
		towers_root.name = "Towers"
		get_parent().add_child(towers_root)

	# Place starter towers on resource nodes after a frame
	# so all resource nodes are initialized
	call_deferred("_spawn_starter_towers")


func _spawn_starter_towers() -> void:
	# Place a free arrow tower near each resource node so they start king-owned
	for res_node in get_tree().get_nodes_in_group("resource_nodes"):
		if not is_instance_valid(res_node):
			continue
		var tower: Node3D = tower_scenes["arrow"].instantiate()
		towers_root.add_child(tower)
		# Offset the tower slightly so it doesn't overlap the node mesh
		tower.global_position = res_node.global_position + Vector3(2.0, 0.0, 2.0)
		tower.add_to_group("towers")


func _resolve_castle_exclusion_radius() -> void:
	var shape_node: CollisionShape3D = castle.get_node_or_null("CollisionShape3D")
	if shape_node and shape_node.shape:
		if shape_node.shape is SphereShape3D:
			castle_exclusion_radius = shape_node.shape.radius
			return
		if shape_node.shape is BoxShape3D:
			castle_exclusion_radius = max(
				shape_node.shape.size.x,
				shape_node.shape.size.z
			) * 0.5
			return
	castle_exclusion_radius = default_castle_exclusion_radius


func set_camera(camera: Camera3D) -> void:
	king_camera = camera


func get_tower_cost(tower_type: String) -> int:
	if tower_costs.has(tower_type):
		return tower_costs[tower_type]
	return 0


func select_tower(tower_type: String) -> bool:
	if not tower_scenes.has(tower_type):
		push_error("Unknown tower type: " + tower_type)
		return false
	if game_manager == null:
		push_error("GameManager missing")
		return false
	if game_manager.king_gold < tower_costs[tower_type]:
		return false

	cancel_build()

	selected_tower_type = tower_type
	is_building = true
	_create_preview()
	emit_signal("build_mode_changed", true)
	return true


func cancel_build() -> void:
	is_building = false
	selected_tower_type = ""
	_cleanup_preview()
	emit_signal("build_mode_changed", false)


func _create_preview() -> void:
	tower_preview = tower_scenes[selected_tower_type].instantiate()
	towers_root.add_child(tower_preview)

	if tower_preview.has_method("set_preview_mode"):
		tower_preview.set_preview_mode(true, true)


func _cleanup_preview() -> void:
	if tower_preview and is_instance_valid(tower_preview):
		tower_preview.queue_free()
		tower_preview = null


func update_preview(world_pos: Vector3) -> void:
	if not is_building or tower_preview == null:
		return

	preview_position = _snap_position(world_pos)
	tower_preview.global_position = preview_position

	var valid := validate_placement(preview_position)

	if tower_preview.has_method("set_preview_mode"):
		tower_preview.set_preview_mode(true, valid)

	emit_signal("placement_validated", valid, preview_position)


func validate_placement(world_pos: Vector3) -> bool:
	var pos_2d := Vector2(world_pos.x, world_pos.z)

	# Castle exclusion
	if castle:
		var castle_pos := Vector2(
			castle.global_position.x,
			castle.global_position.z
		)
		if pos_2d.distance_to(castle_pos) < castle_exclusion_radius:
			return false

	# Tower spacing - skip the preview node
	var placed_count: int = 0
	for child in towers_root.get_children():
		if child == tower_preview:
			continue
		if child is Node3D:
			placed_count += 1
			var tpos := Vector2(
				child.global_position.x,
				child.global_position.z
			)
			if pos_2d.distance_to(tpos) < min_tower_spacing:
				return false

	# Max towers (only count actually placed towers, not preview)
	if placed_count >= max_towers:
		return false

	return true


func mark_preview_invalid() -> void:
	if tower_preview and tower_preview.has_method("set_preview_mode"):
		tower_preview.set_preview_mode(true, false)


func place_tower() -> bool:
	if not is_building or tower_preview == null:
		return false
	if not validate_placement(preview_position):
		return false
	if not game_manager.spend_gold(tower_costs[selected_tower_type]):
		return false

	_spawn_tower_local(selected_tower_type, preview_position)

	# Broadcast tower placement to all peers so their scenes stay in sync
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_tower.rpc(selected_tower_type, preview_position)

	if game_manager:
		game_manager.towers_built += 1

	emit_signal("tower_placed", selected_tower_type, preview_position)
	cancel_build()
	return true


func _spawn_tower_local(tower_type: String, pos: Vector3) -> void:
	var tower := tower_scenes[tower_type].instantiate() as Node3D
	towers_root.add_child(tower)
	tower.global_position = pos
	tower.add_to_group("towers")


@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_tower(tower_type: String, pos: Vector3) -> void:
	if tower_scenes.has(tower_type):
		_spawn_tower_local(tower_type, pos)


func _snap_position(pos: Vector3) -> Vector3:
	if not snap_to_grid:
		return pos
	return Vector3(
		round(pos.x / grid_size) * grid_size,
		pos.y,
		round(pos.z / grid_size) * grid_size
	)
