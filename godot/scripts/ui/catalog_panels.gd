# RealWorld — ui/catalog_panels.gd : the content-tree UX surface (spec 0005 §2.6 panels).
#
# TechPanel binds the CatalogView slice (catalog_view.gd) into the HUD: research progress, how much of
# the tree is buildable/craftable right now, and what research can start next. Same contract as every
# other panel — built ONCE in _build() (R2), value-only bind (R8), styled solely through Widgets/Tokens
# (R3), emits intents rather than calling the sim (R9). Registered in mechanics.gd (R4), so surfacing
# the deep catalogue never edits hud_root.gd.
extends RefCounted

const PanelBase = preload("res://scripts/ui/panel.gd")
const Widgets = preload("res://scripts/ui/widgets.gd")

# ---- TechPanel (RIGHT dock) — the content-tree readout ----
class TechPanel extends PanelBase.Base:
	const ERAS := ["неоліт", "індустрія", "електро", "космос"]
	var _gauge: Widgets.Gauge
	var _researched: Widgets.StatRow
	var _buildable: Widgets.StatRow
	var _craftable: Widgets.StatRow
	var _next: Widgets.StatRow

	func _init() -> void:
		panel_id = &"tech"
		dock = PanelBase.DOCK_RIGHT
		priority = 30
		hotkey = KEY_T
		default_open = false

	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head)
		head.set_header("Технодерево", "tree")
		_gauge = Widgets.Gauge.new()
		vb.add_child(_gauge)
		_researched = Widgets.StatRow.new(); vb.add_child(_researched); _researched.set_row("🔬", "Досліджено", "—")
		_buildable = Widgets.StatRow.new(); vb.add_child(_buildable); _buildable.set_row("🏛", "Будується", "—")
		_craftable = Widgets.StatRow.new(); vb.add_child(_craftable); _craftable.set_row("⚒", "Крафт", "—")
		_next = Widgets.StatRow.new(); vb.add_child(_next); _next.set_row("→", "Далі", "—")

	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("catalog"):
			return
		var cat: Dictionary = vm.catalog
		if not bool(cat.get("available", false)):
			return
		var s: Dictionary = cat.summary
		var progress: float = float(s.get("progress", 0.0))
		var era: int = clampi(int(progress * 4.0), 0, 3)
		_gauge.bind({
			"fill": progress,
			"state": &"good",
			"phases": ERAS,
			"active": era,
		})
		_researched.set_value("%d/%d" % [int(s.get("researched", 0)), int(s.get("research", 0))])
		_buildable.set_value("%d/%d" % [int(s.get("buildable", 0)), int(s.get("buildings", 0))])
		_craftable.set_value("%d/%d" % [int(s.get("craftable", 0)), int(s.get("recipes", 0))])
		var nxt: Array = cat.get("next", [])
		_next.set_value(String(nxt[0]) if nxt.size() > 0 else "—")
