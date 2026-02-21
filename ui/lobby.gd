extends Control

@onready var host_btn: Button       = $Panel/VBox/ModeRow/HostButton
@onready var join_btn: Button       = $Panel/VBox/ModeRow/JoinButton
@onready var ip_field: LineEdit     = $Panel/VBox/JoinRow/IPField
@onready var port_field: LineEdit   = $Panel/VBox/JoinRow/PortField
@onready var join_row: HBoxContainer= $Panel/VBox/JoinRow
@onready var status_label: Label    = $Panel/VBox/StatusLabel
@onready var map_label: Label       = $Panel/VBox/MapRow/MapLabel
@onready var start_btn: Button      = $Panel/VBox/StartButton
@onready var player_list: VBoxContainer = $Panel/VBox/PlayerList
@onready var back_btn: Button       = $Panel/VBox/BackButton
@onready var role_row: HBoxContainer= $Panel/VBox/RoleRow
@onready var btn_be_king: Button    = $Panel/VBox/RoleRow/BecomeKingBtn
@onready var btn_be_attacker: Button= $Panel/VBox/RoleRow/BecomeAttackerBtn
@onready var role_status: Label     = $Panel/VBox/RoleRow/RoleStatusLabel

var network_manager: NetworkManager = null
var selected_map_index: int = 0
var is_hosting: bool = false
var connected: bool = false

var maps: Array[Dictionary] = [
	{"name": "Test Arena",        "path": "res://world/Maps/test_arena.tscn"},
	{"name": "Spire Fortress",    "path": "res://world/Maps/spire_fortress.tscn"},
	{"name": "Mountain Fortress", "path": "res://world/Maps/mountain_fortress.tscn"},
	{"name": "Valley Maze",       "path": "res://world/Maps/valley_maze.tscn"},
	{"name": "Parkour Gauntlet",  "path": "res://world/Maps/parkour_gauntlet.tscn"},
	{"name": "Bomb-omb Field",    "path": "res://world/Maps/Bomb-omb field.tscn"},
]


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var existing: Array = get_tree().get_nodes_in_group("network_manager")
	if existing.size() > 0:
		network_manager = existing[0] as NetworkManager
	else:
		network_manager = NetworkManager.new()
		get_tree().root.add_child(network_manager)

	# Disconnect first to avoid "already connected" errors on scene reload
	if network_manager.player_connected.is_connected(_on_player_connected):
		network_manager.player_connected.disconnect(_on_player_connected)
	if network_manager.player_disconnected.is_connected(_on_player_disconnected):
		network_manager.player_disconnected.disconnect(_on_player_disconnected)
	if network_manager.connection_failed.is_connected(_on_connection_failed):
		network_manager.connection_failed.disconnect(_on_connection_failed)
	if network_manager.server_disconnected.is_connected(_on_server_disconnected):
		network_manager.server_disconnected.disconnect(_on_server_disconnected)
	if network_manager.peer_list_updated.is_connected(_refresh_player_list):
		network_manager.peer_list_updated.disconnect(_refresh_player_list)
	if network_manager.role_confirmed.is_connected(_on_role_confirmed):
		network_manager.role_confirmed.disconnect(_on_role_confirmed)
	network_manager.player_connected.connect(_on_player_connected)
	network_manager.player_disconnected.connect(_on_player_disconnected)
	network_manager.connection_failed.connect(_on_connection_failed)
	network_manager.server_disconnected.connect(_on_server_disconnected)
	network_manager.peer_list_updated.connect(_refresh_player_list)
	network_manager.role_confirmed.connect(_on_role_confirmed)

	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	start_btn.pressed.connect(_on_start_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	btn_be_king.pressed.connect(func(): network_manager.request_role_change("king"))
	btn_be_attacker.pressed.connect(func(): network_manager.request_role_change("attacker"))
	$Panel/VBox/MapRow/MapLeftBtn.pressed.connect(_map_prev)
	$Panel/VBox/MapRow/MapRightBtn.pressed.connect(_map_next)

	role_row.visible = false
	join_row.visible = false
	start_btn.disabled = true
	_update_map_label()
	_set_status("Choose Host or Join.")


func _on_host_pressed() -> void:
	var port_text: String = port_field.text.strip_edges()
	var port: int = int(port_text) if port_text.is_valid_int() else NetworkManager.DEFAULT_PORT
	var err: Error = network_manager.host_game(port)
	if err != OK:
		_set_status("Failed to host on port %d." % port)
		return
	is_hosting = true
	connected = true
	host_btn.disabled = true
	join_btn.disabled = true
	role_row.visible = true
	start_btn.disabled = false
	_set_status("Hosting on port %d — choose your role." % port)
	_refresh_player_list()


func _on_join_pressed() -> void:
	join_row.visible = true
	var ip: String = ip_field.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	var port_text: String = port_field.text.strip_edges()
	var port: int = int(port_text) if port_text.is_valid_int() else NetworkManager.DEFAULT_PORT
	_set_status("Connecting to %s:%d..." % [ip, port])
	var err: Error = network_manager.join_game(ip, port)
	if err != OK:
		_set_status("Connection error.")
		return
	host_btn.disabled = true
	join_btn.disabled = true


func _on_start_pressed() -> void:
	if not is_hosting:
		return
	# Verify king is assigned before starting
	if not network_manager.is_king_slot_taken():
		_set_status("Someone must choose King before starting!")
		return
	var map_path: String = maps[selected_map_index]["path"]
	get_tree().root.set_meta("selected_map", map_path)
	network_manager.start_match_all(map_path)


func _on_back_pressed() -> void:
	network_manager.disconnect_from_game()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _on_player_connected(peer_id: int) -> void:
	connected = true
	role_row.visible = true
	_set_status("Player %d joined." % peer_id)


func _on_player_disconnected(peer_id: int) -> void:
	_set_status("Player %d left." % peer_id)


func _on_connection_failed() -> void:
	_set_status("Connection failed.")
	host_btn.disabled = false
	join_btn.disabled = false


func _on_server_disconnected() -> void:
	_set_status("Host disconnected.")
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _on_role_confirmed(role: String) -> void:
	role_row.visible = true
	role_status.text = "Your role: %s" % role.capitalize()
	# King button: gray out if taken by someone else
	btn_be_king.disabled = network_manager.is_king_slot_taken() and role != "king"


func _refresh_player_list() -> void:
	for child in player_list.get_children():
		child.queue_free()
	for peer_id in network_manager.peer_roles:
		var role: String = network_manager.peer_roles[peer_id]
		var lbl := Label.new()
		var host_tag: String = " [HOST]" if peer_id == 1 else ""
		var role_icon: String = "👑 " if role == "king" else ("⚔ " if role == "attacker" else "  ")
		lbl.text = "%sPlayer %d%s — %s" % [role_icon, peer_id, host_tag, role.capitalize()]
		player_list.add_child(lbl)
	if network_manager.peer_roles.is_empty():
		var lbl := Label.new()
		lbl.text = "Waiting..."
		player_list.add_child(lbl)
	# Show king slot availability
	if is_hosting or connected:
		btn_be_king.text = "Become King" if not network_manager.is_king_slot_taken() else "King Taken"
		btn_be_king.disabled = network_manager.is_king_slot_taken() and \
			network_manager.get_my_role() != "king"


func _map_prev() -> void:
	selected_map_index = (selected_map_index - 1 + maps.size()) % maps.size()
	_update_map_label()


func _map_next() -> void:
	selected_map_index = (selected_map_index + 1) % maps.size()
	_update_map_label()


func _update_map_label() -> void:
	if map_label:
		map_label.text = maps[selected_map_index]["name"]


func _set_status(msg: String) -> void:
	if status_label:
		status_label.text = msg
