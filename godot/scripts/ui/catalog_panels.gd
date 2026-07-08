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
	var _next_id: StringName = &""    # id of the next-available research (for the cat_research intent)

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
		if nxt.size() > 0:
			_next_id = StringName(nxt[0].get("id", &""))
			_next.set_value(String(nxt[0].get("label", "—")))
		else:
			_next_id = &""
			_next.set_value("—")

	# Player action: begin the next-available research. Emits an INTENT (R9) — the router (catalog_verbs)
	# turns it into the sim command; the panel never touches the sim itself.
	func act_next_research() -> void:
		if _next_id != &"":
			emit_intent(&"cat_research", {"id": _next_id})

# ---- ResearchTiersPanel (RIGHT dock) — the tech-era climb, one row per research tier ----
class ResearchTiersPanel extends PanelBase.Base:
	const MAX_TIERS := 9         # the catalogue spans tiers 1..9 (neolithic → ship); fixed rows keep R2
	var _rows: Array = []        # StatRow per tier slot

	func _init() -> void:
		panel_id = &"research_tiers"
		dock = PanelBase.DOCK_RIGHT
		priority = 40
		hotkey = KEY_Y
		default_open = false

	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head)
		head.set_header("Ери", "tiers")
		for i in MAX_TIERS:
			var row := Widgets.StatRow.new()
			vb.add_child(row)
			row.set_row("◆", "—", "—")
			_rows.append(row)

	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("catalog"):
			return
		var cat: Dictionary = vm.catalog
		if not bool(cat.get("available", false)):
			return
		var tiers: Array = cat.get("tiers", [])
		for i in _rows.size():
			if i < tiers.size():
				var t: Dictionary = tiers[i]
				_rows[i].set_row("◆", "Тір %d" % int(t.get("tier", 0)),
					"%d/%d" % [int(t.get("unlocked", 0)), int(t.get("total", 0))])
			else:
				_rows[i].set_row(" ", "—", "")

# ---- ActionBrowser (LEFT dock) — a fixed pool of clickable CatalogSlots bound to an actions slice ----
# Base for the three interactive browsers. Each slot's press emits an INTENT (the browser's verb) with
# the row id (R9 — the panel never touches the sim; the router turns the intent into a catalog_sim call).
class ActionBrowser extends PanelBase.Base:
	const POOL := 12               # fixed slot pool (R2); the slice is capped to match
	var _slots: Array = []
	var _verb: StringName = &""    # intent verb this browser emits (cat_build / cat_craft / cat_research)
	var _slice: String = ""        # catalog slice key it binds (build_actions / craft_actions / …)
	var _title: String = ""

	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 3)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head)
		head.set_header(_title, "act")
		for i in POOL:
			var slot := Widgets.CatalogSlot.new()
			vb.add_child(slot)
			slot.chosen.connect(_on_chosen)
			_slots.append(slot)

	func _on_chosen(id: StringName) -> void:
		if id != &"":
			emit_intent(_verb, {"id": id})

	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("catalog"):
			return
		var cat: Dictionary = vm.catalog
		if not bool(cat.get("available", false)):
			return
		var rows: Array = cat.get(_slice, [])
		for i in _slots.size():
			if i < rows.size():
				_slots[i].bind(rows[i])
			else:
				_slots[i].bind({"id": &"", "label": "", "sub": ""})

class BuildBrowser extends ActionBrowser:
	func _init() -> void:
		panel_id = &"build_browser"; dock = PanelBase.DOCK_LEFT; priority = 50; hotkey = KEY_B
		_verb = &"cat_build"; _slice = "build_actions"; _title = "Будувати"

class CraftBrowser extends ActionBrowser:
	func _init() -> void:
		panel_id = &"craft_browser"; dock = PanelBase.DOCK_LEFT; priority = 60; hotkey = KEY_C
		_verb = &"cat_craft"; _slice = "craft_actions"; _title = "Крафт"

class ResearchBrowser extends ActionBrowser:
	func _init() -> void:
		panel_id = &"research_browser"; dock = PanelBase.DOCK_LEFT; priority = 70; hotkey = KEY_R
		_verb = &"cat_research"; _slice = "research_actions"; _title = "Дослідити"
