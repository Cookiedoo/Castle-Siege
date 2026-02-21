extends Control

# Displayed when a match ends. Shows winner, stats, and navigation options.
# Loaded additively over game_world so GameManager signals are still live.

signal play_again_requested()
signal return_to_menu_requested()

@onready var result_label: Label = $Panel/VBox/ResultLabel
@onready var detail_label: Label = $Panel/VBox/DetailLabel
@onready var play_again_btn: Button = $Panel/VBox/PlayAgainButton
@onready var menu_btn: Button = $Panel/VBox/MenuButton


func _ready() -> void:
	play_again_btn.pressed.connect(_on_play_again)
	menu_btn.pressed.connect(_on_return_to_menu)
	# Intercept all mouse input so game doesn't react behind this screen
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_result(king_won: bool, match_time: float, towers_built: int, gold_earned: int) -> void:
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if king_won:
		result_label.text = "KING VICTORY"
		result_label.modulate = Color(0.4, 0.6, 1.0)
	else:
		result_label.text = "CASTLE FALLS"
		result_label.modulate = Color(1.0, 0.3, 0.3)

	var mins: int = int(match_time) / 60
	var secs: int = int(match_time) % 60
	detail_label.text = "Time: %02d:%02d   |   Towers Built: %d   |   Gold Earned: %d" % [
		mins, secs, towers_built, gold_earned
	]


func _on_play_again() -> void:
	emit_signal("play_again_requested")


func _on_return_to_menu() -> void:
	emit_signal("return_to_menu_requested")
