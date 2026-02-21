extends Node3D
class_name ResourceNode

# -- Tuning --
@export var capture_time: float = 5.0
@export var gold_per_tick: int = 10
@export var tick_interval: float = 5.0
@export var tower_defend_radius: float = 8.0

# -- State --
var owner_team: String = "king"
var capture_progress: float = 0.0
var tick_timer: float = 0.0
var attackers_in_range: Array = []
var king_tower_nearby: bool = false

signal node_captured(res_node: Node, team: String)

@onready var capture_area: Area3D = $CaptureArea
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var progress_label: Label3D = $ProgressLabel


func _ready() -> void:
	add_to_group("resource_nodes")

	capture_area.collision_layer = 0
	capture_area.collision_mask = 2

	capture_area.body_entered.connect(_on_body_entered)
	capture_area.body_exited.connect(_on_body_exited)

	call_deferred("_check_for_nearby_towers")
	_update_visual()


func _process(delta: float) -> void:
	_check_for_nearby_towers()
	_handle_capture(delta)
	_handle_gold_ticks(delta)
	_update_progress_display()


# --------------------------------------------------
# Tower Detection
# --------------------------------------------------

func _check_for_nearby_towers() -> void:
	king_tower_nearby = false

	for tower in get_tree().get_nodes_in_group("towers"):
		if not is_instance_valid(tower):
			continue
		if global_position.distance_to(tower.global_position) <= tower_defend_radius:
			king_tower_nearby = true
			return


# --------------------------------------------------
# Capture Logic (Symmetrical)
# --------------------------------------------------

func _handle_capture(delta: float) -> void:
	var live_attackers: int = 0

	for a in attackers_in_range:
		if is_instance_valid(a) and a.has_method("is_alive") and a.is_alive():
			live_attackers += 1

	var king_present: bool = king_tower_nearby

	# Contested
	if king_present and live_attackers > 0:
		return

	# Attacker capturing
	if live_attackers > 0 and owner_team != "attacker":
		capture_progress += delta * live_attackers
		if capture_progress >= capture_time:
			capture_progress = 0.0
			_set_owner("attacker")
		return

	# King capturing (tower nearby)
	if king_present and owner_team != "king":
		capture_progress += delta
		if capture_progress >= capture_time:
			capture_progress = 0.0
			_set_owner("king")
		return

	# Decay when idle
	if live_attackers == 0 and not king_present:
		capture_progress = max(0.0, capture_progress - delta * 0.5)


# --------------------------------------------------
# Gold Tick
# --------------------------------------------------

func _handle_gold_ticks(delta: float) -> void:
	if owner_team == "neutral":
		return

	tick_timer += delta
	if tick_timer < tick_interval:
		return

	tick_timer -= tick_interval

	if owner_team == "attacker":
		for attacker in get_tree().get_nodes_in_group("attackers"):
			if is_instance_valid(attacker) and attacker.has_method("add_attacker_gold"):
				attacker.add_attacker_gold(gold_per_tick)

	elif owner_team == "king":
		var managers: Array = get_tree().get_nodes_in_group("game_manager")
		if managers.size() > 0:
			managers[0].add_gold(gold_per_tick)


# --------------------------------------------------
# Ownership
# --------------------------------------------------

func _set_owner(team: String) -> void:
	if owner_team == team:
		return

	owner_team = team
	capture_progress = 0.0
	tick_timer = 0.0

	emit_signal("node_captured", self, team)
	_update_visual()


# --------------------------------------------------
# Visuals
# --------------------------------------------------

func _update_visual() -> void:
	if not mesh:
		return

	var mat := StandardMaterial3D.new()

	match owner_team:
		"neutral":
			mat.albedo_color = Color(0.5, 0.5, 0.5)
		"attacker":
			mat.albedo_color = Color(1.0, 0.3, 0.3)
		"king":
			mat.albedo_color = Color(0.3, 0.3, 1.0)

	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.3

	mesh.material_override = mat


func _update_progress_display() -> void:
	if not progress_label:
		return

	if king_tower_nearby and owner_team != "king":
		var pct: int = int((capture_progress / capture_time) * 100)
		progress_label.text = "Reclaiming: " + str(pct) + "%"
		progress_label.visible = true
		return

	if owner_team == "king" and capture_progress > 0:
		var pct2: int = int((capture_progress / capture_time) * 100)
		progress_label.text = "Capturing: " + str(pct2) + "%"
		progress_label.visible = true
		return

	match owner_team:
		"attacker":
			progress_label.text = "ATTACKER"
		"king":
			progress_label.text = "KING"
		_:
			progress_label.text = "NEUTRAL"

	progress_label.visible = true


# --------------------------------------------------
# Area Detection
# --------------------------------------------------

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("attackers") and body not in attackers_in_range:
		attackers_in_range.append(body)


func _on_body_exited(body: Node) -> void:
	attackers_in_range.erase(body)
