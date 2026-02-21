extends Control

var maps: Array[Dictionary] = [
	{"name": "Test Arena",        "path": "res://world/Maps/test_arena.tscn"},
	{"name": "Spire Fortress",    "path": "res://world/Maps/spire_fortress.tscn"},
	{"name": "Mountain Fortress", "path": "res://world/Maps/mountain_fortress.tscn"},
	{"name": "Valley Maze",       "path": "res://world/Maps/valley_maze.tscn"},
	{"name": "Parkour Gauntlet",  "path": "res://world/Maps/parkour_gauntlet.tscn"},
	{"name": "Bomb-omb Field",    "path": "res://world/Maps/Bomb-omb field.tscn"},
]
var selected_map_index: int = 0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_update_map_label()


func _on_multiplayer_pressed() -> void:
	get_tree().root.set_meta("selected_map", maps[selected_map_index]["path"])
	get_tree().root.set_meta("random_roles", false)
	get_tree().change_scene_to_file("res://ui/lobby.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_map_left_pressed() -> void:
	selected_map_index = (selected_map_index - 1 + maps.size()) % maps.size()
	_update_map_label()


func _on_map_right_pressed() -> void:
	selected_map_index = (selected_map_index + 1) % maps.size()
	_update_map_label()


func _update_map_label() -> void:
	var label: Label = $VBoxContainer/MapSelector/MapLabel
	if label:
		label.text = maps[selected_map_index]["name"]
