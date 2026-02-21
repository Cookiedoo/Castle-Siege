extends Node
class_name NetworkManager

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 6

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_disconnected()
signal connection_failed()
signal peer_list_updated()
signal role_confirmed(role: String)

# peer_id -> "king" | "attacker"
var peer_roles: Dictionary = {}
# peer_id -> display name string
var peer_names: Dictionary = {}

var is_host: bool = false
var king_claimed_by: int = -1


func _ready() -> void:
	add_to_group("network_manager")
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ── Host / Join / Disconnect ──────────────────────────────────────────

func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	# Host starts with no role claimed — they choose in the lobby too
	peer_roles[1] = "unassigned"
	peer_names[1] = "Host"
	emit_signal("peer_list_updated")
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	return OK


func disconnect_from_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peer_roles.clear()
	peer_names.clear()
	king_claimed_by = -1
	is_host = false


# ── Role Selection ────────────────────────────────────────────────────

# Client calls this when they click a role button in the lobby
func request_role_change(desired_role: String) -> void:
	var my_id: int = multiplayer.get_unique_id()
	if multiplayer.is_server():
		_process_role_request(my_id, desired_role)
	else:
		_rpc_request_role.rpc_id(1, desired_role)


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_role(desired_role: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_process_role_request(sender, desired_role)


func _process_role_request(peer_id: int, desired_role: String) -> void:
	# Server-side role logic
	if desired_role == "king":
		if king_claimed_by != -1 and king_claimed_by != peer_id:
			# King already taken — force attacker
			_assign_role_to(peer_id, "attacker")
			return
		# Release previous king if this peer is switching from king
		if king_claimed_by == peer_id and desired_role != "king":
			king_claimed_by = -1
		king_claimed_by = peer_id
		_assign_role_to(peer_id, "king")
	else:
		# If this peer was king, release the slot
		if king_claimed_by == peer_id:
			king_claimed_by = -1
		_assign_role_to(peer_id, "attacker")


func _assign_role_to(peer_id: int, role: String) -> void:
	peer_roles[peer_id] = role
	# Tell that specific peer their confirmed role
	if peer_id == multiplayer.get_unique_id():
		_rpc_receive_role.rpc_id(peer_id, role)
	else:
		_rpc_receive_role.rpc_id(peer_id, role)
	# Broadcast updated peer list to everyone
	_broadcast_peer_list()


@rpc("authority", "call_local", "reliable")
func _rpc_receive_role(role: String) -> void:
	get_tree().root.set_meta("player_role", role)
	emit_signal("role_confirmed", role)


func _broadcast_peer_list() -> void:
	if not multiplayer.is_server():
		return
	var ids: Array = peer_roles.keys()
	var roles: Array = peer_roles.values()
	var names: Array = peer_names.values()
	_rpc_receive_peer_list.rpc(ids, roles, names)
	emit_signal("peer_list_updated")


@rpc("authority", "call_local", "reliable")
func _rpc_receive_peer_list(ids: Array, roles: Array, names: Array) -> void:
	peer_roles.clear()
	peer_names.clear()
	for i in range(ids.size()):
		peer_roles[ids[i]] = roles[i]
		peer_names[ids[i]] = names[i]
	emit_signal("peer_list_updated")


# ── Start Match ───────────────────────────────────────────────────────

func start_match_all(map_path: String) -> void:
	if not multiplayer.is_server():
		return
	_rpc_load_game_world.rpc(map_path)


@rpc("authority", "call_local", "reliable")
func _rpc_load_game_world(map_path: String) -> void:
	get_tree().root.set_meta("selected_map", map_path)
	get_tree().change_scene_to_file("res://world/game_world.tscn")


# ── Peer Events ───────────────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		peer_roles[peer_id] = "unassigned"
		peer_names[peer_id] = "Player %d" % peer_id
		_broadcast_peer_list()
	emit_signal("player_connected", peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if king_claimed_by == peer_id:
		king_claimed_by = -1
	peer_roles.erase(peer_id)
	peer_names.erase(peer_id)
	if multiplayer.is_server():
		_broadcast_peer_list()
	emit_signal("player_disconnected", peer_id)


func _on_connected_to_server() -> void:
	# Server will broadcast peer list automatically when we connected
	pass


func _on_connection_failed() -> void:
	emit_signal("connection_failed")


func _on_server_disconnected() -> void:
	emit_signal("server_disconnected")


# ── Helpers ───────────────────────────────────────────────────────────

func get_my_role() -> String:
	return get_tree().root.get_meta("player_role", "attacker")


func is_king_slot_taken() -> bool:
	return king_claimed_by != -1


func get_peer_count() -> int:
	return peer_roles.size()
