# RealWorld — ui/panel_registry.gd : the `SystemRegistry` analogue (spec 0005 §2.6).
#
# Near-verbatim copy of kernel/systems.gd SystemRegistry (add/sort-by-priority/get/dispatch), so a
# reviewer who knows the kernel reads the view instantly. bind_visible() is the view's tick_all().
extends RefCounted

class PanelRegistry extends RefCounted:
	var panels: Array = []

	func register(p) -> void:
		panels.append(p)
		panels.sort_custom(func(a, b): return a.priority < b.priority)   # same idiom as SystemRegistry.add

	func get_panel(id: StringName):
		for p in panels:
			if p.panel_id == id:
				return p
		return null

	func by_dock(d: int) -> Array:
		return panels.filter(func(p): return p.dock == d)

	func count() -> int:
		return panels.size()

	func bind_visible(snap: Dictionary) -> void:      # the view's tick_all: skip hidden panels
		for p in panels:
			if not is_instance_valid(p):
				continue
			if not p.visible and p.reveal_once and not p.revealed and p.wants_reveal(snap):
				p.visible = true                         # first relevance: pip into view, once
				p.revealed = true
			if p.visible:
				p.bind(snap)

	func toggle(id: StringName) -> void:              # show/hide ONLY — never rebuild (R2)
		var p: Variant = get_panel(id)
		if p != null:
			p.visible = not p.visible
			if p.visible and p.is_inside_tree():   # open = 0.16 s fade-in (ease-out), close = instant
				# FADE ONLY: a docked panel's position belongs to its container. The old +10 px rise tweened
				# position.y back to the value read BEFORE layout (a hidden child keeps a stale 0), so the first
				# open landed on top of the dock's first panel (the stock strip) instead of under it.
				p.modulate.a = 0.0
				var tw: Tween = p.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				tw.tween_property(p, "modulate:a", 1.0, 0.16)

	func close_all() -> void:
		for p in panels:
			if is_instance_valid(p) and p.dock == 4:  # DOCK_MODAL
				p.visible = false
