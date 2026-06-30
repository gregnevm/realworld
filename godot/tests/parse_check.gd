# Compile-time parse check for the scene scripts (headless, no window needed).
extends SceneTree

func _init() -> void:
	var a = preload("res://scripts/main.gd")
	var b = preload("res://scripts/world_view.gd")
	print("PARSE OK: main=%s world_view=%s" % [a != null, b != null])
	quit(0)
