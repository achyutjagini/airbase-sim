extends Control
# Thin wrapper so the parent CommandCenter can hook into _draw
var cc_ref: Node = null

func _draw() -> void:
	if cc_ref != null and cc_ref.has_method("_draw_life_chart"):
		cc_ref._draw_life_chart(self)
