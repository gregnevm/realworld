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
			if is_instance_valid(p) and p.visible:
				p.bind(snap)

	func toggle(id: StringName) -> void:              # show/hide ONLY — never rebuild (R2)
		var p: Variant = get_panel(id)
		if p != null:
			p.visible = not p.visible

	func close_all() -> void:
		for p in panels:
			if is_instance_valid(p) and p.dock == 4:  # DOCK_MODAL
				p.visible = false
