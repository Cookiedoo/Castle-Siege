extends Control

# Floating kill feed in top-right corner.
# Messages slide in and fade out after a few seconds.
# Any system can call KillFeed.push(msg) after finding it by group.

const MAX_ENTRIES: int = 6
const ENTRY_LIFETIME: float = 4.5
const FADE_TIME: float = 0.8

var entries: Array = []

@onready var vbox: VBoxContainer = $VBox


func _ready() -> void:
	add_to_group("kill_feed")
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func push(message: String) -> void:
	var lbl := Label.new()
	lbl.text = message
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.modulate = Color(1.0, 1.0, 0.85, 1.0)
	vbox.add_child(lbl)

	var entry: Dictionary = {"label": lbl, "age": 0.0}
	entries.append(entry)

	# Prune oldest if over limit
	if entries.size() > MAX_ENTRIES:
		var oldest: Dictionary = entries.pop_front()
		if is_instance_valid(oldest["label"]):
			oldest["label"].queue_free()


func _process(delta: float) -> void:
	var to_remove: Array = []
	for entry in entries:
		entry["age"] += delta
		var lbl: Label = entry["label"]
		if not is_instance_valid(lbl):
			to_remove.append(entry)
			continue
		if entry["age"] >= ENTRY_LIFETIME - FADE_TIME:
			var fade_progress: float = (entry["age"] - (ENTRY_LIFETIME - FADE_TIME)) / FADE_TIME
			lbl.modulate.a = 1.0 - clamp(fade_progress, 0.0, 1.0)
		if entry["age"] >= ENTRY_LIFETIME:
			lbl.queue_free()
			to_remove.append(entry)

	for entry in to_remove:
		entries.erase(entry)
