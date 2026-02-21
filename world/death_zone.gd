extends Area3D
class_name DeathZone

# Kills any attacker that enters this zone (e.g. falling below the map).
# Emits a signal so GameWorld can handle respawn logic.

signal attacker_died(attacker: Node)


func _ready() -> void:
	add_to_group("death_zones")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("attackers"):
		emit_signal("attacker_died", body)
