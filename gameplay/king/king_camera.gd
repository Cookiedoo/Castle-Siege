extends Camera3D
class_name KingCamera

# -- Camera Tuning --
@export var move_speed: float = 15.0
@export var zoom_speed: float = 5.0
@export var min_zoom: float = 10.0
@export var max_zoom: float = 50.0
@export var edge_pan_margin: float = 30.0
@export var edge_pan_speed: float = 10.0

# Physics layer used for buildable ground
@export var buildable_ground_mask: int = 1

# -- State --
var build_controller: BuildController = null
var is_local_player: bool = false


func _ready() -> void:
	add_to_group("king_camera_group")
	call_deferred("_find_build_controller")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# Godot never fires key-up events for keys held when the window loses focus.
		# Explicitly release all movement actions so get_vector returns zero on re-focus.
		Input.action_release("move_left")
		Input.action_release("move_right")
		Input.action_release("move_forward")
		Input.action_release("move_back")
		set_process(false)
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		if is_local_player:
			set_process(true)


func _find_build_controller() -> void:
	build_controller = get_tree().get_first_node_in_group("build_controller")
	if build_controller == null:
		push_error("BuildController not found in scene")
		return
	build_controller.set_camera(self)


func set_local_player(value: bool) -> void:
	is_local_player = value
	current = value
	set_process(value)
	set_physics_process(value)

	if build_controller:
		build_controller.set_process(value)

	if value:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(delta: float) -> void:
	if not is_local_player:
		return

	_handle_camera_movement(delta)
	_handle_tower_building()


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player:
		return
	# Scroll wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			global_position.y = clamp(global_position.y - zoom_speed, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			global_position.y = clamp(global_position.y + zoom_speed, min_zoom, max_zoom)


func _handle_camera_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Vector3(input_dir.x, 0, input_dir.y)

	var viewport_size := get_viewport().get_visible_rect().size
	var mouse_pos := get_viewport().get_mouse_position()

	if mouse_pos.x < edge_pan_margin:
		dir.x -= 1.0
	elif mouse_pos.x > viewport_size.x - edge_pan_margin:
		dir.x += 1.0
	if mouse_pos.y < edge_pan_margin:
		dir.z -= 1.0
	elif mouse_pos.y > viewport_size.y - edge_pan_margin:
		dir.z += 1.0

	if dir.length() > 0:
		dir = dir.normalized()

	global_position += dir * move_speed * delta


func _handle_tower_building() -> void:
	if build_controller == null:
		return

	# Tower selection hotkeys
	if Input.is_action_just_pressed("build_tower_1"):
		build_controller.select_tower("arrow")
	elif Input.is_action_just_pressed("build_tower_2"):
		build_controller.select_tower("wizard")
	elif Input.is_action_just_pressed("build_tower_3"):
		build_controller.select_tower("knight")
	elif Input.is_action_just_pressed("build_tower_4"):
		build_controller.select_tower("wall")
	elif Input.is_action_just_pressed("build_tower_5"):
		build_controller.select_tower("trebuchet")

	if Input.is_action_just_pressed("cancel"):
		build_controller.cancel_build()

	# Update preview position while building
	if build_controller.is_building:
		var world_pos := _get_world_position_from_mouse()
		if world_pos != Vector3.INF:
			build_controller.update_preview(world_pos)
		else:
			# Hovering a wall or invalid surface — show red preview at last position
			build_controller.mark_preview_invalid()

	# Place tower on click
	if build_controller.is_building and Input.is_action_just_pressed("ui_select"):
		build_controller.place_tower()


func _get_world_position_from_mouse() -> Vector3:
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := project_ray_origin(mouse_pos)
	var ray_end := ray_origin + project_ray_normal(mouse_pos) * 500.0

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = buildable_ground_mask
	query.collide_with_areas = false

	var result := space_state.intersect_ray(query)
	if result.has("position") and result.has("normal"):
		# Only allow placement on surfaces that are mostly facing up.
		# This prevents towers from snapping onto vertical wall sides.
		var normal: Vector3 = result["normal"]
		if normal.dot(Vector3.UP) >= 0.7:
			return result["position"]
	return Vector3.INF
