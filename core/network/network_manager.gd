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

# ── Peer Data ─────────────────────────────
var peer_roles: Dictionary[int, String] = {}    # peer_id -> "king" | "attacker"
var peer_names: Dictionary[int, String] = {}    # peer_id -> display name
var king_claimed_by: int = -1
var is_host: bool = false

# Multiplayer peer
var mp_peer: ENetMultiplayerPeer = null

func _ready() -> void:
	add_to_group("network_manager")

# ── HOST ───────────────────────────────
func host_game(port: int = DEFAULT_PORT) -> void:
	mp_peer = ENetMultiplayerPeer.new()
	var err = mp_peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Failed to start ENet server: %d" % err)
		return
	multiplayer.multiplayer_peer = mp_peer
	is_host = true

	peer_roles[1] = "unassigned"
	peer_names[1] = "Host"
	emit_signal("peer_list_updated")
	print("ENet server running on port %d" % port)

# ── CLIENT ─────────────────────────────
func join_game(host_ip: String, port: int = DEFAULT_PORT) -> void:
	mp_peer = ENetMultiplayerPeer.new()
	var err = mp_peer.create_client(host_ip, port)
	if err != OK:
		emit_signal("connection_failed")
		return
	multiplayer.multiplayer_peer = mp_peer
	is_host = false
	print("Connecting to server at %s:%d" % [host_ip, port])

# ── ROLE MANAGEMENT ─────────────────────────────
func request_role_change(desired_role: String) -> void:
	if is_host:
		_process_role_request(multiplayer.get_unique_id(), desired_role)
	else:
		var msg: Dictionary = {"type":"role_request", "role":desired_role}
		_send_to_server(msg)

func _process_role_request(peer_id: int, desired_role: String) -> void:
	if desired_role == "king":
		if king_claimed_by != -1 and king_claimed_by != peer_id:
			_assign_role_to(peer_id, "attacker")
			return
		king_claimed_by = peer_id
	else:
		if king_claimed_by == peer_id:
			king_claimed_by = -1
	_assign_role_to(peer_id, desired_role)

func _assign_role_to(peer_id: int, role: String) -> void:
	peer_roles[peer_id] = role
	_send_role_confirm(peer_id, role)
	_broadcast_peer_list()

func _send_role_confirm(peer_id: int, role: String) -> void:
	var msg: Dictionary = {"type":"role_confirmed", "role":role}
	if is_host:
		_send_to_peer(peer_id, msg)
	else:
		_send_to_server(msg)

func _broadcast_peer_list() -> void:
	var msg: Dictionary = {
		"type":"peer_list",
		"ids":peer_roles.keys(),
		"roles":peer_roles.values(),
		"names":peer_names.values()
	}
	if is_host:
		for peer_id in multiplayer.get_peers():
			_send_to_peer(peer_id, msg)
	else:
		_send_to_server(msg)
	emit_signal("peer_list_updated")

func _update_peer_list(ids: Array, roles: Array, names: Array) -> void:
	peer_roles.clear()
	peer_names.clear()
	for i in range(ids.size()):
		peer_roles[ids[i]] = roles[i]
		peer_names[ids[i]] = names[i]
	emit_signal("peer_list_updated")

# ── MATCH START ─────────────────────────────
func start_match_all(map_path: String) -> void:
	if not is_host:
		return
	var msg: Dictionary = {"type":"load_match", "map_path":map_path}
	for peer_id in multiplayer.get_peers():
		_send_to_peer(peer_id, msg)

# ── HELPERS ─────────────────────────────
func get_my_role() -> String:
	return get_tree().root.get_meta("player_role", "attacker")

func get_peer_count() -> int:
	return peer_roles.size()

# ── NETWORK SEND/RECEIVE ─────────────────────────────
func _send_to_peer(peer_id: int, msg: Dictionary) -> void:
	var json_str: String = JSON.stringify(msg)
	multiplayer.send_rpc_id(peer_id, "_receive_message", [json_str.to_utf8_buffer()])

func _send_to_server(msg: Dictionary) -> void:
	var json_str: String = JSON.stringify(msg)
	multiplayer.send_rpc_id(1, "_receive_message", [json_str.to_utf8_buffer()])

@rpc("any_peer", "call_local", "reliable")
func _receive_message(packet_bytes: PackedByteArray) -> void:
	var packet_str: String = packet_bytes.get_string_from_utf8()
	var parser := JSON.new()
	var parse_result = parser.parse(packet_str)

	if parse_result.error != OK:
		push_error("Failed to parse JSON: %s" % packet_str)
		return

	var msg: Dictionary = parse_result.result
	if typeof(msg) != TYPE_DICTIONARY:
		push_error("Parsed JSON is not a Dictionary!")
		return

	if not msg.has("type"):
		return

	match msg["type"]:
		"role_request":
			if is_host:
				_process_role_request(multiplayer.get_remote_sender_id(), msg["role"])
		"role_confirmed":
			get_tree().root.set_meta("player_role", msg["role"])
			emit_signal("role_confirmed", msg["role"])
		"peer_list":
			_update_peer_list(msg["ids"], msg["roles"], msg["names"])
		"load_match":
			get_tree().root.set_meta("selected_map", msg["map_path"])
			get_tree().change_scene_to_file("res://world/game_world.tscn")
