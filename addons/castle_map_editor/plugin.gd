@tool
extends EditorPlugin

# Castle Map Editor Plugin
# Adds a dock panel with CSG preset buttons.
# Clicking a preset instantiates a pre-configured CSGCombiner child
# into the currently selected scene node (or scene root if none selected).

const DOCK_SCENE_PATH = "res://addons/castle_map_editor/map_editor_dock.tscn"

var dock: Control = null


func _enter_tree() -> void:
	var dock_scene: PackedScene = load(DOCK_SCENE_PATH)
	if dock_scene == null:
		push_error("Castle Map Editor: dock scene not found at " + DOCK_SCENE_PATH)
		return

	dock = dock_scene.instantiate()
	dock.editor_plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null


# Called by dock buttons to spawn a preset into the scene
func spawn_preset(preset_name: String) -> void:
	var root: Node = get_tree().edited_scene_root
	if root == null:
		push_warning("Castle Map Editor: No scene is open for editing.")
		return

	# Find the target parent: prefer selected node, fall back to scene root
	var selected: Array = get_editor_interface().get_selection().get_selected_nodes()
	var parent: Node = root
	if selected.size() > 0:
		parent = selected[0]

	var preset: Node3D = _build_preset(preset_name)
	if preset == null:
		push_warning("Castle Map Editor: Unknown preset: " + preset_name)
		return

	# Record undo action
	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action("Place " + preset_name)
	undo.add_do_method(parent, "add_child", preset)
	undo.add_do_property(preset, "owner", root)
	undo.add_undo_method(parent, "remove_child", preset)
	undo.commit_action()

	# Select the new node so it can be moved immediately
	get_editor_interface().get_selection().clear()
	get_editor_interface().get_selection().add_node(preset)


func _build_preset(name: String) -> Node3D:
	# Each preset is a CSGCombiner3D with use_collision = true
	# and one or more CSGBox3D/CSGCylinder3D children.
	match name:
		"flat_platform":
			return _make_box_preset("FlatPlatform", 10, 1, 10, Color(0.4, 0.7, 0.4))
		"large_platform":
			return _make_box_preset("LargePlatform", 20, 1, 20, Color(0.4, 0.7, 0.4))
		"small_platform":
			return _make_box_preset("SmallPlatform", 5, 1, 5, Color(0.5, 0.8, 0.5))
		"ramp":
			return _make_ramp_preset()
		"wall_block":
			return _make_box_preset("WallBlock", 1, 6, 8, Color(0.35, 0.35, 0.35))
		"tall_pillar":
			return _make_box_preset("TallPillar", 2, 12, 2, Color(0.3, 0.3, 0.35))
		"archway":
			return _make_archway_preset()
		"spawn_pad":
			return _make_spawn_pad_preset()
		"castle_pedestal":
			return _make_box_preset("CastlePedestal", 8, 4, 8, Color(0.6, 0.6, 0.8))
		"bridge_segment":
			return _make_box_preset("BridgeSegment", 4, 0.5, 16, Color(0.5, 0.45, 0.35))
		"cover_block":
			return _make_box_preset("CoverBlock", 3, 2, 3, Color(0.4, 0.4, 0.4))
		"mountain_chunk":
			return _make_box_preset("MountainChunk", 16, 10, 16, Color(0.3, 0.25, 0.2))

	return null


func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.uv1_triplanar = true
	return mat


func _make_combiner(preset_name: String) -> CSGCombiner3D:
	var combiner := CSGCombiner3D.new()
	combiner.name = preset_name
	combiner.use_collision = true
	return combiner


func _make_box_preset(preset_name: String, sx: float, sy: float, sz: float, color: Color) -> Node3D:
	var combiner := _make_combiner(preset_name)
	var box := CSGBox3D.new()
	box.name = "Shape"
	box.size = Vector3(sx, sy, sz)
	box.material = _make_material(color)
	combiner.add_child(box)
	box.owner = combiner
	return combiner


func _make_ramp_preset() -> Node3D:
	# A ramp: box rotated 20 degrees around X, set on the ground
	var combiner := _make_combiner("Ramp")
	var box := CSGBox3D.new()
	box.name = "RampBody"
	box.size = Vector3(6, 1, 10)
	box.rotation_degrees = Vector3(-20, 0, 0)
	box.position = Vector3(0, 1.5, 0)
	box.material = _make_material(Color(0.5, 0.45, 0.3))
	combiner.add_child(box)
	box.owner = combiner
	return combiner


func _make_archway_preset() -> Node3D:
	# Two pillars + a lintel box on top
	var combiner := _make_combiner("Archway")

	var left := CSGBox3D.new()
	left.name = "PillarLeft"
	left.size = Vector3(1.5, 8, 1.5)
	left.position = Vector3(-3, 4, 0)
	left.material = _make_material(Color(0.35, 0.35, 0.35))
	combiner.add_child(left)
	left.owner = combiner

	var right := CSGBox3D.new()
	right.name = "PillarRight"
	right.size = Vector3(1.5, 8, 1.5)
	right.position = Vector3(3, 4, 0)
	right.material = _make_material(Color(0.35, 0.35, 0.35))
	combiner.add_child(right)
	right.owner = combiner

	var lintel := CSGBox3D.new()
	lintel.name = "Lintel"
	lintel.size = Vector3(9, 1.5, 1.5)
	lintel.position = Vector3(0, 8.25, 0)
	lintel.material = _make_material(Color(0.3, 0.3, 0.3))
	combiner.add_child(lintel)
	lintel.owner = combiner

	return combiner


func _make_spawn_pad_preset() -> Node3D:
	# Raised pad with a distinct color so spawn zones are visible in editor
	var combiner := _make_combiner("SpawnPad")
	var base := CSGBox3D.new()
	base.name = "PadBase"
	base.size = Vector3(12, 0.5, 12)
	base.material = _make_material(Color(0.2, 0.6, 0.2))
	combiner.add_child(base)
	base.owner = combiner
	return combiner
