# Compile-time parse check for the scene scripts (headless, no window needed).
# Preloading an entry script transitively compiles its whole preload/const-preload chain, so this
# catches type/semantic errors GDScript only surfaces at compile time (gdparse cannot). newhud_main
# pulls in the entire view layer (panels/widgets/hud_model/overlays) + kernel/progression via session.
extends SceneTree

func _init() -> void:
	var a = preload("res://scripts/main.gd")
	var b = preload("res://scripts/world_view.gd")
	var c = preload("res://newhud_main.gd")
	print("PARSE OK: main=%s world_view=%s newhud=%s" % [a != null, b != null, c != null])
	quit(0)
