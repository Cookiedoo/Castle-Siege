extends Control

# Shown after role assignment during the pre-match countdown.
# Attacker players pick their class here. King players see a "You are King" screen.
# Emits class_selected when a choice is made or times out.

signal class_selected(attacker_class: int)

const AUTO_SELECT_TIME: float = 15.0

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var subtitle_label: Label = $Panel/VBox/SubtitleLabel
@onready var btn_assassin: Button = $Panel/VBox/ClassRow/AssassinBtn
@onready var btn_vanguard: Button = $Panel/VBox/ClassRow/VanguardBtn
@onready var btn_berserker: Button = $Panel/VBox/ClassRow/BerserkerBtn
@onready var timer_label: Label = $Panel/VBox/TimerLabel
@onready var class_row: HBoxContainer = $Panel/VBox/ClassRow

var countdown: float = AUTO_SELECT_TIME
var is_king: bool = false
var selected: bool = false


func _ready() -> void:
	var role: String = get_meta("assigned_role", get_tree().root.get_meta("player_role", "attacker"))
	is_king = (role == "king")

	if is_king:
		# King gets a brief 3-second toast, not a blocking screen.
		# Mouse stays visible so they can immediately use the HUD.
		countdown = 3.0
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		title_label.text = "YOU ARE THE KING"
		title_label.modulate = Color(1.0, 0.85, 0.2)
		subtitle_label.text = "Defend your castle."
		class_row.visible = false
		# Make the panel non-blocking so king HUD is usable immediately
		var panel = get_node_or_null("Panel")
		if panel:
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_set_mouse_ignore_recursive(panel)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		title_label.text = "CHOOSE YOUR CLASS"
		title_label.modulate = Color(1.0, 1.0, 1.0)
		subtitle_label.text = "Pick a role for the coming assault."
		class_row.visible = true

	btn_assassin.pressed.connect(func(): _pick(Attacker.AttackerClass.ASSASSIN))
	btn_vanguard.pressed.connect(func(): _pick(Attacker.AttackerClass.VANGUARD))
	btn_berserker.pressed.connect(func(): _pick(Attacker.AttackerClass.BERSERKER))


func _set_mouse_ignore_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_set_mouse_ignore_recursive(child)


func _process(delta: float) -> void:
	if selected:
		return
	countdown -= delta
	if timer_label:
		timer_label.text = "Auto-selecting in %d..." % max(0, int(countdown))
	if countdown <= 0.0:
		# Auto-select assassin if nothing chosen
		if not is_king:
			_pick(Attacker.AttackerClass.ASSASSIN)
		else:
			_finish()


func _pick(attacker_class: int) -> void:
	selected = true
	emit_signal("class_selected", attacker_class)
	_finish()


func _finish() -> void:
	queue_free()
