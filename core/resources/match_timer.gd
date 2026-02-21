extends Label

# Attach this script to any Label node in any HUD.
# It finds the GameManager and displays the remaining match time.
# Works identically in King HUD and Attacker HUD.

var game_manager: Node = null


func _ready() -> void:
	var managers: Array = get_tree().get_nodes_in_group("game_manager")
	if managers.size() > 0:
		game_manager = managers[0]
		# Show initial time
		_update_display()

		# Listen for match end to swap display text
		if game_manager.has_signal("king_victory"):
			game_manager.king_victory.connect(_on_king_victory)
		if game_manager.has_signal("attacker_victory"):
			game_manager.attacker_victory.connect(_on_attacker_victory)


func _process(_delta: float) -> void:
	if game_manager and game_manager.current_state == game_manager.GameState.PLAYING:
		_update_display()


func _update_display() -> void:
	var seconds_left: float = game_manager.get_time_remaining()
	var mins: int = int(seconds_left) / 60
	var secs: int = int(seconds_left) % 60
	text = "%02d:%02d" % [mins, secs]


func _on_king_victory() -> void:
	text = "KING WINS"


func _on_attacker_victory() -> void:
	text = "ATTACKERS WIN"
