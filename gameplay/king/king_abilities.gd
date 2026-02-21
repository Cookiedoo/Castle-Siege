extends Node
class_name KingAbilities

# Five active king abilities.

# ── Costs ─────────────────────────────────────────────────────────────
const COST_REPAIR:  int = 250
const COST_REVEAL:  int = 100
const COST_SLOW:    int = 150
const COST_METEOR:  int = 300
const COST_GUARDS:  int = 200

# ── Cooldowns ─────────────────────────────────────────────────────────
const CD_REPAIR:  float = 30.0
const CD_REVEAL:  float = 20.0
const CD_SLOW:    float = 45.0
const CD_METEOR:  float = 60.0
const CD_GUARDS:  float = 90.0

# ── Effect Tuning ─────────────────────────────────────────────────────
const REVEAL_DURATION:  float = 10.0
const SLOW_DURATION:    float = 5.0
const SLOW_AMOUNT:      float = 0.45
const REPAIR_AMOUNT:    int   = 500

const METEOR_DELAY:     float = 3.0
const METEOR_RADIUS:    float = 8.0
const METEOR_DAMAGE:    int   = 300

const GUARD_COUNT:      int   = 3
const GUARD_DURATION:   float = 30.0

# ── Exports ───────────────────────────────────────────────────────────
@export var soldier_scene: PackedScene = preload("res://gameplay/towers/knight_soldier.tscn")

signal ability_used(ability_name: String, cooldown: float)
signal ability_ready(ability_name: String)

var cooldowns: Dictionary = {
	"repair": 0.0, "reveal": 0.0, "slow": 0.0,
	"meteor": 0.0, "guards": 0.0,
}

var game_manager: GameManager = null
var reveal_timer: float = 0.0
var slow_timer:   float = 0.0
var reveal_markers: Array = []

# Pending meteor: position chosen, waiting for explosion
var meteor_pending: bool = false
var meteor_target: Vector3 = Vector3.ZERO
var meteor_countdown: float = 0.0
var meteor_warning: Node3D = null

# Active summoned guards
var active_guards: Array = []


func _ready() -> void:
	add_to_group("king_abilities")
	call_deferred("_find_game_manager")


func _find_game_manager() -> void:
	var managers: Array = get_tree().get_nodes_in_group("game_manager")
	if managers.size() > 0:
		game_manager = managers[0] as GameManager


func _process(delta: float) -> void:
	if not game_manager or game_manager.current_state != GameManager.GameState.PLAYING:
		return
	_tick_cooldowns(delta)
	_tick_effects(delta)
	_tick_meteor(delta)
	_handle_input()


func _tick_cooldowns(delta: float) -> void:
	for key in cooldowns:
		var prev: float = cooldowns[key]
		cooldowns[key] = max(0.0, cooldowns[key] - delta)
		if prev > 0.0 and cooldowns[key] <= 0.0:
			emit_signal("ability_ready", key)


func _tick_effects(delta: float) -> void:
	if reveal_timer > 0.0:
		reveal_timer -= delta
		if reveal_timer <= 0.0:
			_clear_reveal_markers()

	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			_clear_slow()

	# Clean dead guards
	active_guards = active_guards.filter(func(g: Node) -> bool: return is_instance_valid(g))


func _tick_meteor(delta: float) -> void:
	if not meteor_pending:
		return
	meteor_countdown -= delta

	# Pulse the warning ring opacity
	if meteor_warning and is_instance_valid(meteor_warning):
		var pulse: float = abs(sin(meteor_countdown * 4.0))
		for child in meteor_warning.get_children():
			if child is MeshInstance3D:
				child.modulate = Color(1.0, 0.3, 0.1, 0.3 + pulse * 0.5)

	if meteor_countdown <= 0.0:
		_detonate_meteor()


func _handle_input() -> void:
	if Input.is_action_just_pressed("ability_repair"):
		use_repair()
	elif Input.is_action_just_pressed("ability_reveal"):
		use_reveal()
	elif Input.is_action_just_pressed("ability_slow"):
		use_slow()
	elif Input.is_action_just_pressed("ability_meteor"):
		_start_meteor_targeting()
	elif Input.is_action_just_pressed("ability_guards"):
		use_guards()


# ── Repair ────────────────────────────────────────────────────────────

func use_repair() -> bool:
	if cooldowns["repair"] > 0.0 or not game_manager:
		return false
	if not game_manager.spend_gold(COST_REPAIR):
		return false
	game_manager.damage_castle(-REPAIR_AMOUNT)
	cooldowns["repair"] = CD_REPAIR
	emit_signal("ability_used", "repair", CD_REPAIR)
	_push_feed("Castle repaired!")
	return true


# ── Reveal ────────────────────────────────────────────────────────────

func use_reveal() -> bool:
	if cooldowns["reveal"] > 0.0 or not game_manager:
		return false
	if not game_manager.spend_gold(COST_REVEAL):
		return false
	cooldowns["reveal"] = CD_REVEAL
	reveal_timer = REVEAL_DURATION
	_create_reveal_markers()
	emit_signal("ability_used", "reveal", CD_REVEAL)
	return true


func _create_reveal_markers() -> void:
	_clear_reveal_markers()
	for attacker in get_tree().get_nodes_in_group("attackers"):
		if not is_instance_valid(attacker):
			continue
		if attacker.has_method("is_alive") and not attacker.is_alive():
			continue
		var marker := Label3D.new()
		marker.text = "ATTACKER"
		marker.modulate = Color(1.0, 0.2, 0.2)
		marker.font_size = 28
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		attacker.add_child(marker)
		marker.position = Vector3(0, 3.5, 0)
		reveal_markers.append(marker)


func _clear_reveal_markers() -> void:
	for m in reveal_markers:
		if is_instance_valid(m):
			m.queue_free()
	reveal_markers.clear()


# ── Slow ──────────────────────────────────────────────────────────────

func use_slow() -> bool:
	if cooldowns["slow"] > 0.0 or not game_manager:
		return false
	if not game_manager.spend_gold(COST_SLOW):
		return false
	cooldowns["slow"] = CD_SLOW
	slow_timer = SLOW_DURATION
	_apply_slow()
	emit_signal("ability_used", "slow", CD_SLOW)
	_push_feed("Mass Slow activated!")
	return true


func _apply_slow() -> void:
	for attacker in get_tree().get_nodes_in_group("attackers"):
		if not is_instance_valid(attacker):
			continue
		if "walk_speed" in attacker:
			attacker.set_meta("_pre_slow_walk", attacker.walk_speed)
			attacker.set_meta("_pre_slow_sprint", attacker.sprint_speed)
			attacker.walk_speed   *= (1.0 - SLOW_AMOUNT)
			attacker.sprint_speed *= (1.0 - SLOW_AMOUNT)


func _clear_slow() -> void:
	for attacker in get_tree().get_nodes_in_group("attackers"):
		if not is_instance_valid(attacker):
			continue
		if attacker.has_meta("_pre_slow_walk"):
			attacker.walk_speed   = attacker.get_meta("_pre_slow_walk")
			attacker.sprint_speed = attacker.get_meta("_pre_slow_sprint")
			attacker.remove_meta("_pre_slow_walk")
			attacker.remove_meta("_pre_slow_sprint")


# ── Meteor Strike ─────────────────────────────────────────────────────

func _start_meteor_targeting() -> void:
	if cooldowns["meteor"] > 0.0 or not game_manager:
		return
	if meteor_pending:
		return
	if not game_manager.spend_gold(COST_METEOR):
		return

	# Raycast from king camera to get target position
	var king_cam: Camera3D = get_tree().get_first_node_in_group("king_camera_group")
	if not king_cam:
		# Refund if no camera found
		game_manager.add_gold(COST_METEOR)
		return

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = king_cam.project_ray_origin(mouse_pos)
	var ray_dir:    Vector3 = king_cam.project_ray_normal(mouse_pos)
	var ray_end:    Vector3 = ray_origin + ray_dir * 500.0

	var space: PhysicsDirectSpaceState3D = _get_physics_space()
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		game_manager.add_gold(COST_METEOR)
		return

	meteor_target    = result["position"]
	meteor_pending   = true
	meteor_countdown = METEOR_DELAY
	cooldowns["meteor"] = CD_METEOR
	emit_signal("ability_used", "meteor", CD_METEOR)
	_push_feed("Meteor incoming!")
	_spawn_meteor_warning(meteor_target)


func _spawn_meteor_warning(pos: Vector3) -> void:
	meteor_warning = Node3D.new()
	meteor_warning.global_position = pos

	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius    = METEOR_RADIUS
	ring_mesh.bottom_radius = METEOR_RADIUS
	ring_mesh.height        = 0.1
	ring_mesh.radial_segments = 32

	var mat := StandardMaterial3D.new()
	mat.albedo_color   = Color(1.0, 0.3, 0.1, 0.5)
	mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test  = true
	ring_mesh.material = mat

	var ring_inst := MeshInstance3D.new()
	ring_inst.mesh = ring_mesh
	meteor_warning.add_child(ring_inst)
	var _gw1 = get_tree().get_first_node_in_group("game_world")
	var _p1: Node = _gw1 if _gw1 else get_tree().current_scene
	_p1.add_child(meteor_warning)


func _detonate_meteor() -> void:
	meteor_pending = false
	if meteor_warning and is_instance_valid(meteor_warning):
		meteor_warning.queue_free()
		meteor_warning = null

	# Damage all attackers in radius
	var space: PhysicsDirectSpaceState3D = _get_physics_space()
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = METEOR_RADIUS
	query.shape = sphere
	query.transform = Transform3D(Basis(), meteor_target)
	query.collision_mask = 2

	var results: Array = space.intersect_shape(query, 16)
	var hit_count: int = 0
	for result in results:
		var body: Node = result.get("collider")
		if body and body.has_method("take_damage"):
			body.take_damage(METEOR_DAMAGE)
			hit_count += 1

	_push_feed("Meteor struck! Hit %d attackers." % hit_count)

	# Explosion flash sphere
	_spawn_explosion_flash(meteor_target)


func _spawn_explosion_flash(pos: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = METEOR_RADIUS * 0.8
	sphere.height = METEOR_RADIUS * 1.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color  = Color(1.0, 0.5, 0.1, 0.6)
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material   = mat
	flash.mesh = sphere
	flash.global_position = pos
	var _gw2 = get_tree().get_first_node_in_group("game_world")
	var _p2: Node = _gw2 if _gw2 else get_tree().current_scene
	_p2.add_child(flash)
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(func(): if is_instance_valid(flash): flash.queue_free())


# ── Summon Guards ─────────────────────────────────────────────────────

func use_guards() -> bool:
	if cooldowns["guards"] > 0.0 or not game_manager:
		return false
	if not game_manager.spend_gold(COST_GUARDS):
		return false
	if soldier_scene == null:
		return false

	cooldowns["guards"] = CD_GUARDS
	emit_signal("ability_used", "guards", CD_GUARDS)
	_push_feed("Royal Guards summoned!")

	# Find castle position as spawn anchor
	var castle_pos: Vector3 = Vector3.ZERO
	var castles: Array = get_tree().get_nodes_in_group("castle")
	if castles.size() > 0:
		castle_pos = castles[0].global_position

	for i in range(GUARD_COUNT):
		var guard: CharacterBody3D = soldier_scene.instantiate()
		var _gw3 = get_tree().get_first_node_in_group("game_world")
		var _p3: Node = _gw3 if _gw3 else get_tree().current_scene
		_p3.add_child(guard)
		var angle: float = (TAU / GUARD_COUNT) * i
		guard.global_position = castle_pos + Vector3(cos(angle) * 4.0, 1.0, sin(angle) * 4.0)
		guard.add_to_group("king_guards")
		active_guards.append(guard)

		# Auto-destroy after GUARD_DURATION
		var guard_ref := guard
		var t := get_tree().create_timer(GUARD_DURATION)
		t.timeout.connect(func():
			if is_instance_valid(guard_ref):
				guard_ref.queue_free()
		)

	return true


# ── Kill Feed Helper ──────────────────────────────────────────────────

func _push_feed(msg: String) -> void:
	for node in get_tree().get_nodes_in_group("kill_feed"):
		if node.has_method("push"):
			node.push(msg)
			return



# ── Physics Space Helper ──────────────────────────────────────────────

func _get_physics_space() -> PhysicsDirectSpaceState3D:
	# KingAbilities extends Node, not Node3D, so get_world_3d() is unavailable.
	# Borrow the world from the scene root or any Node3D we can find.
	var scene: Node = get_tree().current_scene
	if scene is Node3D:
		return (scene as Node3D).get_world_3d().direct_space_state
	for child in scene.get_children():
		if child is Node3D:
			return (child as Node3D).get_world_3d().direct_space_state
	return null


# ── HUD Query Helpers ─────────────────────────────────────────────────

func get_cooldown(ability: String) -> float:
	return cooldowns.get(ability, 0.0)


func get_max_cooldown(ability: String) -> float:
	match ability:
		"repair": return CD_REPAIR
		"reveal": return CD_REVEAL
		"slow":   return CD_SLOW
		"meteor": return CD_METEOR
		"guards": return CD_GUARDS
	return 1.0
