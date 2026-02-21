extends Node
class_name GameManager

# -- Game State --
enum GameState { LOBBY, PLAYING, ENDED }
var current_state: int = GameState.LOBBY

# -- Castle --
const CASTLE_MAX_HEALTH: int = 1000
var castle_current_health: int = CASTLE_MAX_HEALTH

# -- Match Timer --
const MATCH_TIME_LIMIT: float = 900.0
var current_match_time: float = 0.0

# -- Economy --
const PASSIVE_GOLD_INTERVAL: float = 10.0
const PASSIVE_GOLD_AMOUNT: int = 50
const KILL_BONUS_GOLD: int = 100
const STARTING_GOLD: int = 500

var king_gold: int = STARTING_GOLD
var passive_gold_timer: float = 0.0

# -- Tracking --
var attacker_players: Array = []
var attackers_eliminated: int = 0
var towers_built: int = 0

# -- Signals --
signal game_state_changed(new_state: int)
signal castle_damaged(current_hp: int, max_hp: int)
signal attacker_eliminated(attacker_id: int)
signal king_victory()
signal attacker_victory()
signal gold_changed(new_amount: int)


func _ready() -> void:
	add_to_group("game_manager")


func start_match() -> void:
	current_state = GameState.PLAYING
	current_match_time = 0.0
	passive_gold_timer = 0.0
	king_gold = STARTING_GOLD
	reset_castle_health()
	emit_signal("gold_changed", king_gold)
	emit_signal("game_state_changed", current_state)
	# Replicate match start to all peers
	if multiplayer.is_server():
		_rpc_sync_match_start.rpc(STARTING_GOLD, CASTLE_MAX_HEALTH)


func _process(delta: float) -> void:
	# Only the server runs authoritative game logic
	if not multiplayer.is_server():
		return
	if current_state != GameState.PLAYING:
		return

	current_match_time += delta

	passive_gold_timer += delta
	if passive_gold_timer >= PASSIVE_GOLD_INTERVAL:
		passive_gold_timer -= PASSIVE_GOLD_INTERVAL
		add_gold(PASSIVE_GOLD_AMOUNT)

	check_win_conditions()


func check_win_conditions() -> void:
	if castle_current_health <= 0:
		end_match(false)
		return

	var alive_count: int = 0
	for attacker in attacker_players:
		if is_instance_valid(attacker) and attacker.has_method("is_alive") and attacker.is_alive():
			alive_count += 1

	if alive_count == 0 and attacker_players.size() > 0:
		end_match(true)
		return

	if current_match_time >= MATCH_TIME_LIMIT:
		end_match(true)


# -- Castle --

func reset_castle_health() -> void:
	castle_current_health = CASTLE_MAX_HEALTH
	emit_signal("castle_damaged", castle_current_health, CASTLE_MAX_HEALTH)


func damage_castle(amount: int) -> void:
	if current_state != GameState.PLAYING:
		return
	if multiplayer.is_server():
		_apply_castle_damage(amount)
	else:
		# Clients ask the server to apply damage
		_rpc_request_castle_damage.rpc_id(1, amount)


func _apply_castle_damage(amount: int) -> void:
	castle_current_health = clamp(castle_current_health - amount, 0, CASTLE_MAX_HEALTH)
	# Broadcast new castle HP to all peers
	_rpc_sync_castle_hp.rpc(castle_current_health)
	emit_signal("castle_damaged", castle_current_health, CASTLE_MAX_HEALTH)


# -- Economy --

func add_gold(amount: int) -> void:
	king_gold += amount
	emit_signal("gold_changed", king_gold)
	if multiplayer.is_server():
		_rpc_sync_gold.rpc(king_gold)


func spend_gold(amount: int) -> bool:
	if king_gold >= amount:
		king_gold -= amount
		emit_signal("gold_changed", king_gold)
		if multiplayer.is_server():
			_rpc_sync_gold.rpc(king_gold)
		return true
	return false


# -- Attacker Registration --

func register_attacker(attacker: Node) -> void:
	if not attacker in attacker_players:
		attacker_players.append(attacker)


func unregister_attacker(attacker: Node) -> void:
	attacker_players.erase(attacker)


func eliminate_attacker(attacker: Node) -> void:
	attackers_eliminated += 1
	add_gold(KILL_BONUS_GOLD)
	emit_signal("attacker_eliminated", attacker.get_instance_id())


func request_attacker_respawn(attacker: Node) -> void:
	var worlds: Array = get_tree().get_nodes_in_group("game_world")
	if worlds.size() > 0 and worlds[0].has_method("_on_attacker_died"):
		worlds[0]._on_attacker_died(attacker)


# -- Match End --

func end_match(king_won: bool) -> void:
	if current_state == GameState.ENDED:
		return
	current_state = GameState.ENDED
	if multiplayer.is_server():
		_rpc_sync_match_end.rpc(king_won)
	_apply_match_end(king_won)


func _apply_match_end(king_won: bool) -> void:
	if king_won:
		emit_signal("king_victory")
	else:
		emit_signal("attacker_victory")
	emit_signal("game_state_changed", current_state)


# -- Time Helpers --

func get_time_remaining() -> float:
	return max(0.0, MATCH_TIME_LIMIT - current_match_time)


func format_time(seconds: float) -> String:
	var mins: int = int(seconds) / 60
	var secs: int = int(seconds) % 60
	return "%02d:%02d" % [mins, secs]


# ── RPCs ─────────────────────────────────────────────────────────────

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_castle_damage(amount: int) -> void:
	# Only the server processes incoming damage requests
	if multiplayer.is_server():
		_apply_castle_damage(amount)


@rpc("authority", "call_local", "unreliable_ordered")
func _rpc_sync_castle_hp(hp: int) -> void:
	castle_current_health = hp
	emit_signal("castle_damaged", castle_current_health, CASTLE_MAX_HEALTH)


@rpc("authority", "call_local", "unreliable_ordered")
func _rpc_sync_gold(amount: int) -> void:
	king_gold = amount
	emit_signal("gold_changed", king_gold)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_match_start(start_gold: int, castle_hp: int) -> void:
	if not multiplayer.is_server():
		current_state = GameState.PLAYING
		king_gold = start_gold
		castle_current_health = castle_hp
		emit_signal("gold_changed", king_gold)
		emit_signal("castle_damaged", castle_current_health, CASTLE_MAX_HEALTH)
		emit_signal("game_state_changed", current_state)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync_match_end(king_won: bool) -> void:
	current_state = GameState.ENDED
	_apply_match_end(king_won)
