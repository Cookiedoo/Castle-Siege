extends Node3D

@export var round_end_scene:    PackedScene = preload("res://ui/round_end_screen.tscn")
@export var class_select_scene: PackedScene = preload("res://ui/class_select.tscn")
@export var kill_feed_scene:    PackedScene = preload("res://ui/kill_feed.tscn")

@onready var respawn_points:  Node3D = $RespawnPoints
@onready var attackers_root:  Node3D = $Attackers

# Role is resolved once at startup and never changes during a match.
var assigned_role:  String      = "king"
var king_camera:    KingCamera  = null
var attackers:      Array       = []
var game_manager:   GameManager = null
var round_end_screen: Control   = null
var total_gold_earned: int      = 0

# The attacker body this local client controls (null for king).
var local_attacker: Node = null


func _ready() -> void:
	add_to_group("game_world")
	_load_selected_map()
	king_camera = get_node_or_null("KingCamera")

	var managers: Array = get_tree().get_nodes_in_group("game_manager")
	if managers.size() > 0:
		game_manager = managers[0] as GameManager
		game_manager.king_victory.connect(_on_match_ended.bind(true))
		game_manager.attacker_victory.connect(_on_match_ended.bind(false))
		game_manager.gold_changed.connect(_on_gold_changed)
		game_manager.attacker_eliminated.connect(_on_attacker_eliminated)

	for dz in get_tree().get_nodes_in_group("death_zones"):
		if dz.has_signal("attacker_died"):
			dz.attacker_died.connect(_on_attacker_died)

	await get_tree().process_frame
	await get_tree().process_frame
	_apply_map_config()
	_refresh_attackers()
	_spawn_kill_feed()

	assigned_role = _resolve_role()

	# Assign multiplayer authority to attacker bodies.
	# Server peer (ID 1) maps to the first attacker if they are an attacker.
	# Each subsequent peer maps to the next attacker body in order.
	_assign_attacker_authorities()

	if assigned_role == "attacker":
		_activate_attacker_role()
	else:
		_activate_king_role()

	_show_class_select(assigned_role)


func _resolve_role() -> String:
	if get_tree().root.has_meta("player_role"):
		return get_tree().root.get_meta("player_role")
	# Fallback: host with no role set is king
	if multiplayer.is_server():
		return "king"
	return "attacker"


func _assign_attacker_authorities() -> void:
	# Build ordered list of attacker peer IDs (all peers whose role is "attacker").
	# The king peer controls no attacker body.
	# Server (peer 1) always has authority over game_manager and castle.
	# Attacker bodies get authority of their owning peer so physics run locally on that client.
	if not multiplayer.has_multiplayer_peer():
		# Singleplayer / offline — no authority changes needed
		return

	var nm_nodes: Array = get_tree().get_nodes_in_group("network_manager")
	if nm_nodes.is_empty():
		return
	var nm: NetworkManager = nm_nodes[0] as NetworkManager

	# Collect attacker peer IDs in deterministic order (sorted ascending by peer ID)
	var attacker_peers: Array = []
	var all_ids: Array = nm.peer_roles.keys()
	all_ids.sort()
	for pid in all_ids:
		if nm.peer_roles[pid] == "attacker":
			attacker_peers.append(pid)

	var my_id: int = multiplayer.get_unique_id()

	# Assign each attacker body to a peer
	for i in range(attackers.size()):
		var body: Node = attackers[i]
		if i < attacker_peers.size():
			var owner_id: int = attacker_peers[i]
			body.set_multiplayer_authority(owner_id)
			if owner_id == my_id:
				local_attacker = body
		else:
			# More bodies than attacker peers — disable extras
			body.visible = false
			body.set_physics_process(false)
			body.set_process(false)


func _activate_king_role() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	$KingHUD.visible = true
	if king_camera and is_instance_valid(king_camera):
		king_camera.set_local_player(true)
	# Disable all attacker bodies on king's machine — they are simulated by clients
	for a in attackers:
		if is_instance_valid(a):
			a.set_local_player(false)
			a.set_physics_process(false)
			a.set_process(false)
			a.get_node_or_null("Camera3D").current = false if a.get_node_or_null("Camera3D") else null


func _activate_attacker_role() -> void:
	$KingHUD.visible = false
	if king_camera and is_instance_valid(king_camera):
		king_camera.set_local_player(false)
	# Only activate the attacker body this peer owns
	var target: Node = local_attacker if local_attacker else (attackers[0] if attackers.size() > 0 else null)
	if target and is_instance_valid(target):
		target.suppress_mouse_capture = true
		target.set_local_player(true)
		target.suppress_mouse_capture = false
	# Disable all other attacker bodies on this peer — they are remote players
	for a in attackers:
		if is_instance_valid(a) and a != target:
			a.set_local_player(false)
			a.set_physics_process(false)
			a.set_process(false)


func _show_class_select(role: String) -> void:
	if role == "king":
		_start_match_deferred()
		return
	if class_select_scene == null:
		_start_match_deferred()
		return
	var screen: Control = class_select_scene.instantiate()
	screen.set_meta("assigned_role", role)
	get_tree().root.add_child(screen)
	screen.class_selected.connect(_on_class_selected)


func _on_class_selected(attacker_class: int) -> void:
	var target: Node = local_attacker if local_attacker else (attackers[0] if attackers.size() > 0 else null)
	if target and is_instance_valid(target):
		target.apply_class(attacker_class)
		_push_feed("You chose %s" % Attacker.CLASS_NAMES.get(attacker_class, "Unknown"))
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_start_match_deferred()


func _start_match_deferred() -> void:
	if game_manager and game_manager.current_state == GameManager.GameState.LOBBY:
		# Only the server authoritatively starts the match.
		# Clients receive start via _rpc_sync_match_start.
		if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
			game_manager.start_match()


func _spawn_kill_feed() -> void:
	if kill_feed_scene == null:
		return
	var kf: Control = kill_feed_scene.instantiate()
	get_tree().root.add_child(kf)


func _push_feed(msg: String) -> void:
	for node in get_tree().get_nodes_in_group("kill_feed"):
		if node.has_method("push"):
			node.push(msg)
			return


func _on_gold_changed(new_amount: int) -> void:
	if game_manager and new_amount > total_gold_earned:
		total_gold_earned = new_amount


func _on_attacker_eliminated(_attacker_id: int) -> void:
	_push_feed("Attacker eliminated! King +100g")


# ── Map Loading ──────────────────────────────────────────────────────

func _load_selected_map() -> void:
	var map_path: String = get_tree().root.get_meta("selected_map", "")
	if map_path == "":
		return
	if not ResourceLoader.exists(map_path):
		push_error("Map not found: " + map_path)
		return
	var map_instance: Node3D = load(map_path).instantiate()
	map_instance.name = "LoadedMap"
	add_child(map_instance)
	move_child(map_instance, 0)


func _apply_map_config() -> void:
	var loaded_map: Node3D = get_node_or_null("LoadedMap")
	if not loaded_map:
		return
	var config: MapConfig = null
	for child in loaded_map.get_children():
		if child is MapConfig:
			config = child
			break
	if not config:
		push_warning("No MapConfig found.")
		return
	if king_camera:
		king_camera.global_position = config.king_camera_start
	var dz: Node3D = get_node_or_null("DeathZone")
	if dz:
		dz.global_position.y = config.death_zone_y
	call_deferred("_apply_physics_positions", config)


func _apply_physics_positions(config: MapConfig) -> void:
	var castle_node: Node3D = get_node_or_null("Castle")
	if castle_node:
		castle_node.global_position = config.castle_position
	var spawn_ch: Array = respawn_points.get_children()
	var att_ch:   Array = attackers_root.get_children()
	for i in range(config.spawn_positions.size()):
		if i < spawn_ch.size():
			spawn_ch[i].global_position = config.spawn_positions[i]
		if i < att_ch.size():
			att_ch[i].global_position = config.spawn_positions[i]
	var res_root: Node3D = get_node_or_null("ResourceNodes")
	if res_root:
		var res_ch: Array = res_root.get_children()
		for i in range(config.resource_node_positions.size()):
			if i < res_ch.size():
				res_ch[i].global_position = config.resource_node_positions[i]


func _refresh_attackers() -> void:
	attackers.clear()
	for node in get_tree().get_nodes_in_group("attackers"):
		if is_instance_valid(node):
			attackers.append(node)


# ── Match End ────────────────────────────────────────────────────────

func _on_match_ended(king_won: bool) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if round_end_scene == null:
		return
	round_end_screen = round_end_scene.instantiate()
	get_tree().root.add_child(round_end_screen)
	var match_time: float = game_manager.current_match_time if game_manager else 0.0
	var towers_built_count: int = game_manager.towers_built if game_manager else 0
	round_end_screen.show_result(king_won, match_time, towers_built_count, total_gold_earned)
	round_end_screen.play_again_requested.connect(_on_play_again)
	round_end_screen.return_to_menu_requested.connect(_on_return_to_menu)


func _on_play_again() -> void:
	if round_end_screen:
		round_end_screen.queue_free()
		round_end_screen = null
	get_tree().change_scene_to_file("res://world/game_world.tscn")


func _on_return_to_menu() -> void:
	if round_end_screen:
		round_end_screen.queue_free()
		round_end_screen = null
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


# ── Death / Respawn ──────────────────────────────────────────────────

func _on_attacker_died(attacker: Node) -> void:
	if not is_instance_valid(attacker):
		return
	var was_local: bool = "is_local_player" in attacker and attacker.is_local_player
	attacker.set_local_player(false)
	attacker.visible = false
	attacker.set_physics_process(false)
	attacker.set_process(false)
	var class_str: String = Attacker.CLASS_NAMES.get(attacker.current_class, "Attacker")
	_push_feed("%s fell — lost an upgrade" % class_str)
	await get_tree().create_timer(2.5).timeout
	if not is_instance_valid(attacker):
		return
	attacker.global_position = _get_random_spawn_point()
	attacker.reset_state()
	if was_local and assigned_role == "attacker":
		attacker.set_local_player(true)
	_push_feed("%s respawned" % class_str)


func _get_random_spawn_point() -> Vector3:
	var points: Array = respawn_points.get_children()
	if points.size() == 0:
		return Vector3(0, 5, 30)
	return points.pick_random().global_position
