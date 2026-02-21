extends Control

@onready var gold_label:        Label       = $TopBar/Row/GoldLabel
@onready var castle_health_bar: ProgressBar = $TopBar/Row/CastleHealthBar
@onready var castle_hp_label:   Label       = $TopBar/Row/CastleHPLabel
@onready var timer_label:       Label       = $TopBar/Row/TimerLabel
@onready var build_buttons:     HBoxContainer = $BuildMenu/Inner/BuildButtons
@onready var ability_buttons:   HBoxContainer = $AbilityBar/Inner/AbilityButtons

var game_manager:   GameManager    = null
var build_controller: BuildController = null
var king_abilities: Node           = null

var tower_btns: Dictionary = {}
var ability_btns: Dictionary = {}

const TOWER_DEFS: Array = [
	{"key": "arrow",     "label": "1:Arrow\n(100g)",     "cost": 100},
	{"key": "wizard",    "label": "2:Wizard\n(300g)",    "cost": 300},
	{"key": "knight",    "label": "3:Knight\n(250g)",    "cost": 250},
	{"key": "wall",      "label": "4:Wall\n(75g)",       "cost": 75},
	{"key": "trebuchet", "label": "5:Trebuchet\n(400g)", "cost": 400},
]

const ABILITY_DEFS: Array = [
	{"key": "repair",  "label": "R:Repair\n(250g)",  "cost": 250},
	{"key": "reveal",  "label": "F:Reveal\n(100g)",  "cost": 100},
	{"key": "slow",    "label": "G:Slow\n(150g)",    "cost": 150},
	{"key": "meteor",  "label": "T:Meteor\n(300g)",  "cost": 300},
	{"key": "guards",  "label": "Y:Guards\n(200g)",  "cost": 200},
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var managers: Array = get_tree().get_nodes_in_group("game_manager")
	if managers.size() > 0:
		game_manager = managers[0] as GameManager
		game_manager.gold_changed.connect(_on_gold_changed)
		game_manager.castle_damaged.connect(_on_castle_damaged)
		game_manager.king_victory.connect(_on_king_victory)
		game_manager.attacker_victory.connect(_on_attacker_victory)
		_on_gold_changed(game_manager.king_gold)
		_on_castle_damaged(game_manager.castle_current_health, game_manager.CASTLE_MAX_HEALTH)

	call_deferred("_find_build_controller")
	call_deferred("_find_abilities")
	call_deferred("_build_tower_buttons")
	call_deferred("_build_ability_buttons")


func _find_build_controller() -> void:
	var nodes: Array = get_tree().get_nodes_in_group("build_controller")
	if nodes.size() > 0:
		build_controller = nodes[0] as BuildController


func _find_abilities() -> void:
	var nodes: Array = get_tree().get_nodes_in_group("king_abilities")
	if nodes.size() > 0:
		king_abilities = nodes[0]


func _build_tower_buttons() -> void:
	for child in build_buttons.get_children():
		child.queue_free()
	for info in TOWER_DEFS:
		var btn := _make_btn(info["label"])
		var key: String = info["key"]
		btn.pressed.connect(func(): if build_controller: build_controller.select_tower(key))
		build_buttons.add_child(btn)
		tower_btns[key] = btn


func _build_ability_buttons() -> void:
	for child in ability_buttons.get_children():
		child.queue_free()
	var ability_calls: Dictionary = {
		"repair": func(): if king_abilities: king_abilities.use_repair(),
		"reveal": func(): if king_abilities: king_abilities.use_reveal(),
		"slow":   func(): if king_abilities: king_abilities.use_slow(),
		"meteor": func(): if king_abilities: king_abilities._start_meteor_targeting(),
		"guards": func(): if king_abilities: king_abilities.use_guards(),
	}
	for info in ABILITY_DEFS:
		var btn := _make_btn(info["label"])
		btn.pressed.connect(ability_calls[info["key"]])
		ability_buttons.add_child(btn)
		ability_btns[info["key"]] = btn


func _make_btn(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(108, 58)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn


func _process(_delta: float) -> void:
	_refresh_tower_affordability()
	_refresh_ability_buttons()
	_refresh_timer()


func _refresh_timer() -> void:
	if not game_manager or not timer_label:
		return
	if game_manager.current_state == GameManager.GameState.PLAYING:
		timer_label.text = game_manager.format_time(game_manager.get_time_remaining())


func _refresh_tower_affordability() -> void:
	if not game_manager or not build_controller:
		return
	for key in tower_btns:
		var btn: Button = tower_btns[key]
		btn.disabled = game_manager.king_gold < build_controller.get_tower_cost(key)


func _refresh_ability_buttons() -> void:
	if not king_abilities:
		_find_abilities()
		return
	var costs: Dictionary = {"repair": 250, "reveal": 100, "slow": 150, "meteor": 300, "guards": 200}
	var base_labels: Dictionary = {
		"repair": "R:Repair\n(250g)", "reveal": "F:Reveal\n(100g)",
		"slow":   "G:Slow\n(150g)",  "meteor": "T:Meteor\n(300g)",
		"guards": "Y:Guards\n(200g)",
	}
	for key in ability_btns:
		var btn: Button = ability_btns[key]
		if not btn:
			continue
		var cd: float = king_abilities.get_cooldown(key)
		var can_afford: bool = game_manager != null and game_manager.king_gold >= costs.get(key, 999)
		if cd > 0.0:
			btn.text = key.capitalize() + "\n%.0fs" % cd
			btn.disabled = true
		else:
			btn.text = base_labels[key]
			btn.disabled = not can_afford


func _on_gold_changed(new_amount: int) -> void:
	if gold_label:
		gold_label.text = "Gold: %d" % new_amount


func _on_castle_damaged(current_hp: int, max_hp: int) -> void:
	if castle_health_bar:
		castle_health_bar.max_value = max_hp
		castle_health_bar.value = current_hp
	if castle_hp_label:
		castle_hp_label.text = "%d / %d" % [current_hp, max_hp]


func _on_king_victory() -> void:
	if timer_label:
		timer_label.text = "VICTORY"
		timer_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))


func _on_attacker_victory() -> void:
	if timer_label:
		timer_label.text = "CASTLE FALLS"
		timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
