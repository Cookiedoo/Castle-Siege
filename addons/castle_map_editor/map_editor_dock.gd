@tool
extends Control

# The dock panel UI for the Castle Map Editor plugin.
# Displays categorized preset buttons. Calls editor_plugin.spawn_preset(name).

var editor_plugin = null

# Preset definitions: [display_label, preset_key]
const PRESETS: Array = [
	["--- PLATFORMS ---",  ""],
	["Flat Platform 10x10", "flat_platform"],
	["Large Platform 20x20","large_platform"],
	["Small Platform 5x5",  "small_platform"],
	["Bridge Segment",      "bridge_segment"],
	["Spawn Pad",           "spawn_pad"],
	["--- STRUCTURE ---",  ""],
	["Ramp",               "ramp"],
	["Wall Block",         "wall_block"],
	["Tall Pillar",        "tall_pillar"],
	["Archway",            "archway"],
	["Cover Block",        "cover_block"],
	["--- TERRAIN ---",   ""],
	["Mountain Chunk",     "mountain_chunk"],
	["Castle Pedestal",    "castle_pedestal"],
]


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(180, 0)
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "Map Editor"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Select a node in the\nscene tree, then click\na preset to place it."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.8, 0.8, 0.8)
	vbox.add_child(hint)

	vbox.add_child(HSeparator.new())

	for entry in PRESETS:
		var label_text: String = entry[0]
		var key: String = entry[1]

		if key == "":
			# Section header
			var lbl := Label.new()
			lbl.text = label_text
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.modulate = Color(0.7, 0.9, 1.0)
			vbox.add_child(lbl)
		else:
			var btn := Button.new()
			btn.text = label_text
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.custom_minimum_size = Vector2(0, 32)
			btn.pressed.connect(_on_preset_pressed.bind(key))
			vbox.add_child(btn)


func _on_preset_pressed(preset_key: String) -> void:
	if editor_plugin == null:
		push_warning("Map Editor dock has no editor_plugin reference.")
		return
	editor_plugin.spawn_preset(preset_key)
