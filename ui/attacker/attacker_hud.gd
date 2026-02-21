extends Control

@onready var health_bar:          ProgressBar = $TopLeft/HealthPanel/HealthInner/HealthBar
@onready var health_label:        Label       = $TopLeft/HealthPanel/HealthInner/HealthLabel
@onready var castle_health_bar:   ProgressBar = $TopLeft/CastlePanel/CastleInner/CastleHealthBar
@onready var castle_hp_label:     Label       = $TopLeft/CastlePanel/CastleInner/CastleHPLabel
@onready var timer_label:         Label       = $TopRight/TimerLabel
@onready var class_label:         Label       = $TopRight/ClassLabel
@onready var gold_label:          Label       = $TopRight/GoldLabel
@onready var dash_cooldown:       ColorRect   = $BottomBar/Row/DashAbility/DashIcon/DashCooldown
@onready var dash_cooldown_label: Label       = $BottomBar/Row/DashAbility/DashIcon/DashCooldown/DashCooldownLabel
@onready var class_cooldown:      ColorRect   = $BottomBar/Row/ClassAbility/ClassIcon/ClassCooldown
@onready var class_cooldown_label: Label      = $BottomBar/Row/ClassAbility/ClassIcon/ClassCooldown/ClassCooldownLabel
@onready var class_ability_label: Label       = $BottomBar/Row/ClassAbility/ClassAbilityLabel
@onready var attack_indicator:    ColorRect   = $AttackIndicator
@onready var shop_panel:          PanelContainer = $ShopPanel

var player: Node       = null
var game_manager: Node = null

var btn_damage: Button = null
var btn_speed:  Button = null
var btn_health: Button = null


func _ready() -> void:
	var managers: Array = get_tree().get_nodes_in_group("game_manager")
	if managers.size() > 0:
		game_manager = managers[0]
		game_manager.castle_damaged.connect(_on_castle_damaged)
		if castle_health_bar:
			castle_health_bar.max_value = game_manager.CASTLE_MAX_HEALTH
			castle_health_bar.value = game_manager.castle_current_health
			_update_castle_label()

	if shop_panel:
		shop_panel.visible = false
		_build_shop_ui()

	if attack_indicator:
		attack_indicator.visible = false


func set_player(p: Node) -> void:
	player = p
	if not player:
		return
	if health_bar:
		health_bar.max_value = player._get_max_health()
		health_bar.value = player.current_health
	if player.has_signal("attacker_gold_changed"):
		player.attacker_gold_changed.connect(_on_gold_changed)
		_on_gold_changed(player.attacker_gold)
	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed)
	if player.has_signal("class_changed"):
		player.class_changed.connect(_on_class_changed)


func _process(_delta: float) -> void:
	if not player:
		return
	_tick_health()
	_tick_dash_cooldown()
	_tick_class_ability()
	_tick_attack_indicator()
	_tick_timer()
	if shop_panel and shop_panel.visible:
		_refresh_shop_labels()


func _tick_health() -> void:
	if health_bar:
		health_bar.value = player.current_health
	if health_label:
		health_label.text = "%d / %d" % [player.current_health, player._get_max_health()]


func _tick_timer() -> void:
	if not game_manager or not timer_label:
		return
	if game_manager.current_state == game_manager.GameState.PLAYING:
		timer_label.text = game_manager.format_time(game_manager.get_time_remaining())


func _tick_dash_cooldown() -> void:
	if not player.has_method("get_dash_cooldown_remaining"):
		return
	var cd: float = player.get_dash_cooldown_remaining()
	if dash_cooldown:
		dash_cooldown.visible = cd > 0.0
	if dash_cooldown_label and cd > 0.0:
		dash_cooldown_label.text = str(ceili(cd))


func _tick_class_ability() -> void:
	if not player.has_method("get_class_ability_cooldown"):
		return
	var cd: float = player.get_class_ability_cooldown()

	if player.current_class == Attacker.AttackerClass.ASSASSIN:
		var ready: bool = player.can_double_jump and not player.has_double_jumped
		if class_cooldown:
			class_cooldown.visible = not ready
		if class_cooldown_label:
			class_cooldown_label.text = "~"
		return

	if class_cooldown:
		class_cooldown.visible = cd > 0.0
	if class_cooldown_label and cd > 0.0:
		class_cooldown_label.text = str(ceili(cd))


func _tick_attack_indicator() -> void:
	if attack_indicator:
		attack_indicator.visible = player.attack_timer > player.attack_rate - 0.1


func _on_class_changed(class_name_str: String) -> void:
	if class_label:
		class_label.text = class_name_str
		match class_name_str:
			"Assassin":  class_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7))
			"Vanguard":  class_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
			"Berserker": class_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	if class_ability_label:
		var desc: Dictionary = {
			"Assassin":  "DOUBLE JUMP",
			"Vanguard":  "RALLY (V)",
			"Berserker": "SLAM (V)",
		}
		class_ability_label.text = desc.get(class_name_str, "ABILITY")


func set_shop_visible(vis: bool) -> void:
	if shop_panel:
		shop_panel.visible = vis
		shop_panel.mouse_filter = Control.MOUSE_FILTER_STOP if vis else Control.MOUSE_FILTER_IGNORE


func _build_shop_ui() -> void:
	for child in shop_panel.get_children():
		child.queue_free()
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_STOP
	shop_panel.add_child(vbox)

	var title := Label.new()
	title.text = "UPGRADES  (Q to close)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	var note := Label.new()
	note.text = "Death removes your highest upgrade!"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
	vbox.add_child(note)
	vbox.add_child(HSeparator.new())

	btn_damage = _shop_btn(vbox, _on_buy_damage)
	btn_speed  = _shop_btn(vbox, _on_buy_speed)
	btn_health = _shop_btn(vbox, _on_buy_health)
	_refresh_shop_labels()


func _shop_btn(parent: Node, callback: Callable) -> Button:
	var btn := Button.new()
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn


func _refresh_shop_labels() -> void:
	if not player:
		return
	if btn_damage:
		var cost: int = player.get_upgrade_cost(player.damage_level)
		btn_damage.text = "Damage  Lv%d  (%d dmg)  —  %dg" % [player.damage_level, player._get_attack_damage(), cost]
		btn_damage.disabled = player.attacker_gold < cost
	if btn_speed:
		var cost: int = player.get_upgrade_cost(player.speed_level)
		btn_speed.text = "Speed  Lv%d  —  %dg" % [player.speed_level, cost]
		btn_speed.disabled = player.attacker_gold < cost
	if btn_health:
		var cost: int = player.get_upgrade_cost(player.health_level)
		btn_health.text = "Health  Lv%d  (%d max)  —  %dg" % [player.health_level, player._get_max_health(), cost]
		btn_health.disabled = player.attacker_gold < cost


func _on_buy_damage() -> void:
	if player: player.upgrade_damage(); _refresh_shop_labels()

func _on_buy_speed() -> void:
	if player: player.upgrade_speed(); _refresh_shop_labels()

func _on_buy_health() -> void:
	if player: player.upgrade_health(); _refresh_shop_labels()


func _on_castle_damaged(current_hp: int, max_hp: int) -> void:
	if castle_health_bar:
		castle_health_bar.max_value = max_hp
		castle_health_bar.value = current_hp
	_update_castle_label()


func _update_castle_label() -> void:
	if castle_hp_label and game_manager:
		castle_hp_label.text = "%d / %d" % [game_manager.castle_current_health, game_manager.CASTLE_MAX_HEALTH]


func _on_gold_changed(new_amount: int) -> void:
	if gold_label:
		gold_label.text = "Gold: %d" % new_amount


func _on_health_changed(current_hp: int, max_hp: int) -> void:
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = current_hp
	if health_label:
		health_label.text = "%d / %d" % [current_hp, max_hp]
