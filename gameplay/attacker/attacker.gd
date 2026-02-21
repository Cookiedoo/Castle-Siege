extends CharacterBody3D
class_name Attacker

# ── Tuning ────────────────────────────────────────────────────────────
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 7.0
@export var gravity: float = 20.0
@export var mouse_sensitivity: float = 0.002

@export var dash_speed: float = 22.0
@export var dash_duration: float = 0.25
@export var dash_cooldown_time: float = 1.2

@export var base_attack_damage: int = 25
@export var attack_rate: float = 0.4
@export var attack_reach: float = 3.0
@export var max_health: int = 100

# ── Economy ───────────────────────────────────────────────────────────
const GOLD_PER_CASTLE_HIT: int = 5
const GOLD_PER_TOWER_HIT: int = 3
const STARTING_ATTACKER_GOLD: int = 0

var attacker_gold: int = STARTING_ATTACKER_GOLD

signal attacker_gold_changed(new_amount: int)
signal health_changed(current_hp: int, max_hp: int)
signal player_died()
signal class_changed(class_name_str: String)
signal kill_feed_event(msg: String)

# ── Class System ──────────────────────────────────────────────────────
enum AttackerClass { NONE, ASSASSIN, VANGUARD, BERSERKER }

const CLASS_NAMES: Dictionary = {
	AttackerClass.ASSASSIN: "Assassin",
	AttackerClass.VANGUARD: "Vanguard",
	AttackerClass.BERSERKER: "Berserker",
}

# Multipliers applied on class selection
const CLASS_SPEED_MULT: Dictionary = {
	AttackerClass.ASSASSIN: 1.0,
	AttackerClass.VANGUARD: 1.0,
	AttackerClass.BERSERKER: 0.5,
}
const CLASS_HEALTH_MULT: Dictionary = {
	AttackerClass.ASSASSIN: 1.0,
	AttackerClass.VANGUARD: 1.0,
	AttackerClass.BERSERKER: 1.5,
}
const CLASS_DAMAGE_MULT: Dictionary = {
	AttackerClass.ASSASSIN: 1.0,
	AttackerClass.VANGUARD: 2.0,
	AttackerClass.BERSERKER: 1.5,
}

var current_class: int = AttackerClass.NONE
var class_speed_multiplier: float = 1.0
var class_health_multiplier: float = 1.0
var class_damage_multiplier: float = 1.0

# ── Class Ability State ───────────────────────────────────────────────
# Assassin: double jump
var has_double_jumped: bool = false
var can_double_jump: bool = false

# Vanguard: rally beacon
const RALLY_COOLDOWN: float = 18.0
const RALLY_DURATION: float = 5.0
const RALLY_RADIUS: float = 12.0
const RALLY_SPEED_BONUS: float = 0.3
var rally_cooldown: float = 0.0
var rally_active: bool = false
var rally_timer: float = 0.0
var rally_marker: Node3D = null

# Berserker: ground slam
const SLAM_COOLDOWN: float = 8.0
const SLAM_RADIUS: float = 5.0
const SLAM_DAMAGE_MULT: float = 2.5
var slam_cooldown: float = 0.0

# ── Upgrades ──────────────────────────────────────────────────────────
var damage_level: int = 0
var speed_level: int = 0
var health_level: int = 0

const DAMAGE_PER_LEVEL: int = 5
const SPEED_PER_LEVEL: float = 1.5
const HEALTH_PER_LEVEL: int = 25
const UPGRADE_COST_BASE: int = 50
const UPGRADE_COST_SCALE: int = 25

# ── Runtime State ─────────────────────────────────────────────────────
var current_health: int
var dash_timer: float = 0.0
var dash_cooldown: float = 0.0
var attack_timer: float = 0.0
var is_dashing: bool = false
var is_local_player: bool = false
var shop_open: bool = false
# Blocks mouse-look rotation while the class selection screen is active.
var awaiting_class_selection: bool = true
# When true, set_local_player will NOT capture the mouse (used during class select)
var suppress_mouse_capture: bool = false

# ── Node References ───────────────────────────────────────────────────
@onready var camera: Camera3D = $Camera3D
@onready var attack_range_area: Area3D = $AttackRange
@onready var hud: Control = null


func _ready() -> void:
	current_health = _get_max_health()
	attacker_gold = STARTING_ATTACKER_GOLD
	add_to_group("attackers")

	var managers: Array = get_tree().get_nodes_in_group("game_manager")
	if managers.size() > 0:
		managers[0].register_attacker(self)

	_bind_hud()
	set_process(is_local_player)
	set_physics_process(is_local_player)

	if is_local_player:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# Release held velocity and explicitly clear input actions so nothing carries over.
		velocity.x = 0.0
		velocity.z = 0.0
		is_dashing = false
		Input.action_release("move_left")
		Input.action_release("move_right")
		Input.action_release("move_forward")
		Input.action_release("move_back")
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		# Only recapture mouse if we are the local player AND class has been chosen.
		if is_local_player and not shop_open and not awaiting_class_selection:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ── Class Selection ───────────────────────────────────────────────────

func apply_class(chosen_class: int) -> void:
	current_class = chosen_class
	awaiting_class_selection = false
	class_speed_multiplier = CLASS_SPEED_MULT.get(chosen_class, 1.0)
	class_health_multiplier = CLASS_HEALTH_MULT.get(chosen_class, 1.0)
	class_damage_multiplier = CLASS_DAMAGE_MULT.get(chosen_class, 1.0)

	# Recalculate health with new multiplier
	current_health = _get_max_health()
	emit_signal("health_changed", current_health, _get_max_health())
	emit_signal("class_changed", CLASS_NAMES.get(chosen_class, "Unknown"))


# ── HUD Binding ───────────────────────────────────────────────────────

func _bind_hud() -> void:
	var hud_wrapper: Control = get_node_or_null("AttackerHUD")
	if not hud_wrapper:
		return
	hud_wrapper.visible = true
	hud_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_mouse_ignore_recursive(hud_wrapper)
	if hud_wrapper.has_method("set_player"):
		hud = hud_wrapper
		hud.set_player(self)
	else:
		for child in hud_wrapper.get_children():
			if child.has_method("set_player"):
				hud = child
				hud.set_player(self)
				break


func _set_mouse_ignore_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			if child.name == "ShopPanel":
				continue
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_set_mouse_ignore_recursive(child)


func set_local_player(value: bool) -> void:
	is_local_player = value
	set_process(value)
	set_physics_process(value)
	if camera:
		camera.current = value
	var hud_wrapper: Control = get_node_or_null("AttackerHUD")
	if hud_wrapper:
		hud_wrapper.visible = value
	if value and not suppress_mouse_capture:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ── Input ─────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not is_local_player:
		return
	# Do not rotate view until the player has chosen their class.
	if awaiting_class_selection:
		return
	if event is InputEventMouseMotion and not shop_open:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))


# ── Physics Loop ──────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not is_local_player:
		return

	dash_cooldown = max(0.0, dash_cooldown - delta)
	slam_cooldown = max(0.0, slam_cooldown - delta)
	rally_cooldown = max(0.0, rally_cooldown - delta)
	_tick_rally(delta)

	if not shop_open:
		_handle_movement(delta)
		_handle_jump()
		_apply_gravity(delta)
		_handle_dash(delta)
		_handle_class_ability()
		_handle_melee_attack(delta)
		move_and_slide()

	if Input.is_action_just_pressed("shop_toggle"):
		_toggle_shop()


# ── Movement ──────────────────────────────────────────────────────────

func _handle_movement(_delta: float) -> void:
	if is_dashing:
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	dir.y = 0
	if dir.length() > 0:
		dir = dir.normalized()
	var target_vel := dir * _get_current_speed()
	# Lower lerp weight = snappier feel without killing momentum
	var lerp_weight: float = 12.0 * get_physics_process_delta_time()
	velocity.x = lerp(velocity.x, target_vel.x, lerp_weight)
	velocity.z = lerp(velocity.z, target_vel.z, lerp_weight)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0:
		velocity.y = 0


func _handle_jump() -> void:
	# Reset double jump state on landing
	if is_on_floor():
		has_double_jumped = false
		can_double_jump = (current_class == AttackerClass.ASSASSIN)

	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = jump_velocity
		elif can_double_jump and not has_double_jumped and current_class == AttackerClass.ASSASSIN:
			# Assassin double jump — higher than normal jump
			velocity.y = jump_velocity * 1.3
			has_double_jumped = true
			can_double_jump = false


var _dash_direction: Vector3 = Vector3.ZERO

func _handle_dash(delta: float) -> void:
	if Input.is_action_just_pressed("ability_1") and dash_cooldown <= 0.0:
		is_dashing = true
		dash_timer = dash_duration
		dash_cooldown = dash_cooldown_time
		# Lock the dash direction at the moment of input
		_dash_direction = -camera.global_basis.z
		_dash_direction.y = 0.0
		if _dash_direction.length_squared() > 0.01:
			_dash_direction = _dash_direction.normalized()
		else:
			_dash_direction = -global_basis.z

	if is_dashing:
		# Re-apply velocity every frame so move_and_slide wall contact can't kill it
		velocity.x = _dash_direction.x * dash_speed
		velocity.z = _dash_direction.z * dash_speed
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing = false


# ── Class Abilities ───────────────────────────────────────────────────

func _handle_class_ability() -> void:
	if not Input.is_action_just_pressed("class_ability"):
		return
	match current_class:
		AttackerClass.VANGUARD:
			_use_rally()
		AttackerClass.BERSERKER:
			_use_ground_slam()
		# Assassin double jump is handled in _handle_jump directly


func _use_rally() -> void:
	if rally_cooldown > 0.0:
		return
	rally_cooldown = RALLY_COOLDOWN
	rally_active = true
	rally_timer = RALLY_DURATION

	# Visual marker at player feet
	if rally_marker and is_instance_valid(rally_marker):
		rally_marker.queue_free()
	rally_marker = _spawn_rally_marker()


func _tick_rally(delta: float) -> void:
	if not rally_active:
		return
	rally_timer -= delta

	# Apply speed boost to all nearby attackers each frame
	for attacker in get_tree().get_nodes_in_group("attackers"):
		if not is_instance_valid(attacker):
			continue
		if global_position.distance_to(attacker.global_position) <= RALLY_RADIUS:
			attacker.set_meta("_rally_boosted", true)

	if rally_timer <= 0.0:
		rally_active = false
		# Clear rally boost flags
		for attacker in get_tree().get_nodes_in_group("attackers"):
			if is_instance_valid(attacker):
				attacker.remove_meta("_rally_boosted") if attacker.has_meta("_rally_boosted") else null
		if rally_marker and is_instance_valid(rally_marker):
			rally_marker.queue_free()
			rally_marker = null


func _spawn_rally_marker() -> Node3D:
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = RALLY_RADIUS
	cyl.bottom_radius = RALLY_RADIUS
	cyl.height = 0.1
	cyl.radial_segments = 24
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	cyl.material = mat
	mesh_inst.mesh = cyl
	# Add to game world root so cleanup is automatic on scene change
	var game_world = get_tree().get_first_node_in_group("game_world")
	var parent: Node = game_world if game_world else get_tree().current_scene
	parent.add_child(mesh_inst)
	return mesh_inst


func _use_ground_slam() -> void:
	if slam_cooldown > 0.0:
		return
	slam_cooldown = SLAM_COOLDOWN

	# AOE damage to all towers and soldiers in radius
	var slam_damage: int = int(_get_attack_damage() * SLAM_DAMAGE_MULT)
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = SLAM_RADIUS
	query.shape = sphere
	query.transform = global_transform
	query.collision_mask = 4 | 8 | 16

	var results: Array = space_state.intersect_shape(query, 32)
	for result in results:
		var body: Node = result.get("collider")
		if not body:
			continue
		if body.is_in_group("towers") and body.has_method("take_damage"):
			body.take_damage(slam_damage)
			add_attacker_gold(GOLD_PER_TOWER_HIT)
		elif body.get_parent() and body.get_parent().is_in_group("towers"):
			body.get_parent().take_damage(slam_damage)
			add_attacker_gold(GOLD_PER_TOWER_HIT)
		elif body.has_method("take_damage") and not body.is_in_group("attackers"):
			body.take_damage(slam_damage)

	# Visual shockwave ring
	_spawn_slam_ring()

	# Slight upward bounce so slam feels impactful
	velocity.y = 5.0


func _spawn_slam_ring() -> void:
	var ring := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = SLAM_RADIUS
	mesh.bottom_radius = SLAM_RADIUS
	mesh.height = 0.08
	mesh.radial_segments = 24
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.1, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mesh.material = mat
	ring.mesh = mesh
	ring.global_position = global_position
	var game_world = get_tree().get_first_node_in_group("game_world")
	var parent: Node = game_world if game_world else get_tree().current_scene
	parent.add_child(ring)
	# Auto-destroy after brief flash
	var timer := get_tree().create_timer(0.3)
	timer.timeout.connect(func(): if is_instance_valid(ring): ring.queue_free())


# ── Combat ────────────────────────────────────────────────────────────

func _handle_melee_attack(delta: float) -> void:
	attack_timer -= delta
	if attack_timer > 0.0:
		return
	if not Input.is_action_pressed("attack"):
		return
	attack_timer = attack_rate

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var cam_pos: Vector3 = camera.global_position
	var cam_forward: Vector3 = -camera.global_basis.z
	var ray_end: Vector3 = cam_pos + cam_forward * attack_reach

	var query := PhysicsRayQueryParameters3D.create(cam_pos, ray_end)
	query.collision_mask = 1 | 4 | 8 | 16
	query.collide_with_areas = false

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return

	var hit_body: Node = result["collider"]
	var dmg: int = _get_attack_damage()

	# Castle — Vanguard cannot damage castle directly
	if hit_body.is_in_group("castle") and hit_body.has_method("damage"):
		if current_class == AttackerClass.VANGUARD:
			return
		hit_body.damage(dmg)
		add_attacker_gold(GOLD_PER_CASTLE_HIT)
		return

	# Tower direct hit
	if hit_body.is_in_group("towers") and hit_body.has_method("take_damage"):
		hit_body.take_damage(dmg)
		add_attacker_gold(GOLD_PER_TOWER_HIT)
		return

	# Tower child hit
	var parent_node: Node = hit_body.get_parent()
	if parent_node and parent_node.is_in_group("towers") and parent_node.has_method("take_damage"):
		parent_node.take_damage(dmg)
		add_attacker_gold(GOLD_PER_TOWER_HIT)
		return

	if hit_body.has_method("take_damage"):
		hit_body.take_damage(dmg)


# ── Stat Getters ──────────────────────────────────────────────────────

func _get_attack_damage() -> int:
	var base: int = base_attack_damage + (damage_level * DAMAGE_PER_LEVEL)
	return int(base * class_damage_multiplier)


func _get_current_speed() -> float:
	var base: float = sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var upgrade_bonus: float = speed_level * SPEED_PER_LEVEL
	var rally_bonus: float = RALLY_SPEED_BONUS if has_meta("_rally_boosted") else 0.0
	return (base + upgrade_bonus) * class_speed_multiplier * (1.0 + rally_bonus)


func _get_max_health() -> int:
	var base: int = max_health + (health_level * HEALTH_PER_LEVEL)
	return int(base * class_health_multiplier)


# ── Upgrades ──────────────────────────────────────────────────────────

func get_upgrade_cost(level: int) -> int:
	return UPGRADE_COST_BASE + (level * UPGRADE_COST_SCALE)


func upgrade_damage() -> bool:
	var cost: int = get_upgrade_cost(damage_level)
	if spend_attacker_gold(cost):
		damage_level += 1
		return true
	return false


func upgrade_speed() -> bool:
	var cost: int = get_upgrade_cost(speed_level)
	if spend_attacker_gold(cost):
		speed_level += 1
		return true
	return false


func upgrade_health() -> bool:
	var cost: int = get_upgrade_cost(health_level)
	if spend_attacker_gold(cost):
		health_level += 1
		var new_max: int = _get_max_health()
		current_health = min(current_health + HEALTH_PER_LEVEL, new_max)
		emit_signal("health_changed", current_health, new_max)
		return true
	return false


# Kill penalty: lose one level of whichever stat is highest
func apply_death_penalty() -> void:
	var highest_stat: String = ""
	var highest_val: int = 0
	if damage_level > highest_val:
		highest_val = damage_level
		highest_stat = "damage"
	if speed_level > highest_val:
		highest_val = speed_level
		highest_stat = "speed"
	if health_level > highest_val:
		highest_val = health_level
		highest_stat = "health"

	if highest_stat == "damage" and damage_level > 0:
		damage_level -= 1
		emit_signal("kill_feed_event", "Lost Damage upgrade on death")
	elif highest_stat == "speed" and speed_level > 0:
		speed_level -= 1
		emit_signal("kill_feed_event", "Lost Speed upgrade on death")
	elif highest_stat == "health" and health_level > 0:
		health_level -= 1
		current_health = min(current_health, _get_max_health())
		emit_signal("kill_feed_event", "Lost Health upgrade on death")


# ── Economy ───────────────────────────────────────────────────────────

func add_attacker_gold(amount: int) -> void:
	attacker_gold += amount
	emit_signal("attacker_gold_changed", attacker_gold)


func spend_attacker_gold(amount: int) -> bool:
	if attacker_gold >= amount:
		attacker_gold -= amount
		emit_signal("attacker_gold_changed", attacker_gold)
		return true
	return false


# ── Health / Death ────────────────────────────────────────────────────

func take_damage(amount: int) -> void:
	current_health -= amount
	if current_health <= 0:
		current_health = 0
		emit_signal("health_changed", current_health, _get_max_health())
		die()
		return
	emit_signal("health_changed", current_health, _get_max_health())


func die() -> void:
	apply_death_penalty()
	set_process(false)
	set_physics_process(false)
	emit_signal("player_died")
	velocity = Vector3.ZERO
	visible = false
	collision_layer = 0
	collision_mask = 0
	var managers: Array = get_tree().get_nodes_in_group("game_manager")
	if managers.size() > 0:
		managers[0].request_attacker_respawn(self)


func is_alive() -> bool:
	return current_health > 0


func get_dash_cooldown_remaining() -> float:
	return dash_cooldown


func get_class_ability_cooldown() -> float:
	match current_class:
		AttackerClass.VANGUARD:  return rally_cooldown
		AttackerClass.BERSERKER: return slam_cooldown
	return 0.0


func get_class_ability_max_cooldown() -> float:
	match current_class:
		AttackerClass.VANGUARD:  return RALLY_COOLDOWN
		AttackerClass.BERSERKER: return SLAM_COOLDOWN
	return 1.0


func reset_state() -> void:
	current_health = _get_max_health()
	velocity = Vector3.ZERO
	is_dashing = false
	dash_cooldown = 0.0
	slam_cooldown = 0.0
	rally_cooldown = 0.0
	rally_active = false
	rally_timer = 0.0
	shop_open = false
	has_double_jumped = false
	can_double_jump = (current_class == AttackerClass.ASSASSIN)
	collision_layer = 2
	collision_mask = 5
	visible = true
	set_process(true)
	set_physics_process(true)
	emit_signal("health_changed", current_health, _get_max_health())
	# Clean up any lingering rally visual
	if rally_marker and is_instance_valid(rally_marker):
		rally_marker.queue_free()
		rally_marker = null
	# Remove rally boost meta if present
	if has_meta("_rally_boosted"):
		remove_meta("_rally_boosted")


# ── Shop ──────────────────────────────────────────────────────────────

func _toggle_shop() -> void:
	shop_open = not shop_open
	if shop_open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if hud and hud.has_method("set_shop_visible"):
		hud.set_shop_visible(shop_open)
