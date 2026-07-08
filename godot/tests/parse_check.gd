# Compile-time parse check for the scene scripts (headless, no window needed).
extends SceneTree

func _init() -> void:
	var a = preload("res://scripts/main.gd")
	var b = preload("res://scripts/world_view.gd")
	# newhud_main pulls in the whole view-layer graph (registries → panels → catalog_panels,
	# catalog_sim, catalog_verbs), so preloading it compile-checks the new HUD wiring in CI.
	var c = preload("res://newhud_main.gd")
	print("PARSE OK: main=%s world_view=%s newhud=%s" % [a != null, b != null, c != null])
	quit(0)
