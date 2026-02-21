extends TowerBase

# High health obstacle that blocks attacker movement.
# Has no attack capability.

func _ready() -> void:
	tower_name = "Defensive Wall"
	damage = 0
	fire_rate = 0.0
	attack_range = 0.0
	max_health = 800
	cost = 75
	super._ready()


# Walls never acquire targets or fire, but base _process handles flash
# via Timer so no override needed. Override only to skip targeting:
func _process(delta: float) -> void:
	if is_preview:
		return
	# No targeting or firing for walls


func fire_projectile() -> void:
	pass
