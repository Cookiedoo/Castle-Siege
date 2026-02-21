extends StaticBody3D

# Castle is the King's primary objective. Attackers win by destroying it.

@onready var mesh: MeshInstance3D = $MeshInstance3D
@export var build_exclusion_radius: float = 6.0

var game_manager: GameManager = null
var health_label: Label3D = null
var flash_restore_timer: Timer = null
var health_color_mat: Material = null


func _ready() -> void:
	add_to_group("castle")

	var managers: Array = get_tree().get_nodes_in_group("game_manager")
	if managers.size() > 0:
		game_manager = managers[0] as GameManager
		game_manager.castle_damaged.connect(_on_castle_damaged)

	_create_health_label()
	_setup_flash_timer()


func _create_health_label() -> void:
	health_label = Label3D.new()
	health_label.font_size = 32
	health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_label.no_depth_test = true
	health_label.position = Vector3(0, 6.5, 0)
	add_child(health_label)
	_update_label()


func _setup_flash_timer() -> void:
	flash_restore_timer = Timer.new()
	flash_restore_timer.wait_time = 0.15
	flash_restore_timer.one_shot = true
	flash_restore_timer.timeout.connect(_on_flash_timeout)
	add_child(flash_restore_timer)


func _on_flash_timeout() -> void:
	if mesh:
		# Restore to health-based color, or null if none set yet
		mesh.material_override = health_color_mat


func _update_label() -> void:
	if not health_label or not game_manager:
		return
	var hp: int = game_manager.castle_current_health
	var max_hp: int = game_manager.CASTLE_MAX_HEALTH
	health_label.text = "CASTLE " + str(hp) + "/" + str(max_hp)

	var pct: float = float(hp) / float(max_hp)
	if pct > 0.6:
		health_label.modulate = Color(0.3, 0.5, 1.0, 0.9)
	elif pct > 0.3:
		health_label.modulate = Color(1.0, 0.8, 0.2, 0.9)
	else:
		health_label.modulate = Color(1.0, 0.2, 0.2, 0.9)


func damage(amount: int) -> void:
	if game_manager:
		game_manager.damage_castle(amount)
	_flash_hit()


func _flash_hit() -> void:
	if not mesh:
		return
	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.2, 0.2, 1.0)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.0, 0.0)
	flash_mat.emission_energy_multiplier = 2.0
	mesh.material_override = flash_mat
	if flash_restore_timer:
		flash_restore_timer.start()


func _on_castle_damaged(current_hp: int, max_hp: int) -> void:
	_update_label()

	if not mesh:
		return

	# Build the health-based color material
	var health_percent: float = float(current_hp) / float(max_hp)
	var mat := StandardMaterial3D.new()
	if health_percent > 0.6:
		mat.albedo_color = Color(0.3, 0.3, 0.8)
	elif health_percent > 0.3:
		mat.albedo_color = Color(0.8, 0.5, 0.1)
	else:
		mat.albedo_color = Color(0.8, 0.1, 0.1)

	# Always store so flash can restore to it
	health_color_mat = mat

	# Apply immediately only if not mid-flash
	if flash_restore_timer and flash_restore_timer.is_stopped():
		mesh.material_override = mat
