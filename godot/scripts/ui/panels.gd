# RealWorld — ui/panels.gd : concrete dock/modal panels (spec 0005 §2.6), all inner classes.
#
# Every panel `extends PanelBase.Panel` (the preloaded base's inner class — the exact idiom
# environment.gd uses for `Systems.SimSystem`). A panel reads ONE slice of the snapshot and sets values
# on children it built ONCE (R2); it never touches sim and never calls a sim mutator (R9 — it emits intents).
extends RefCounted

const PanelBase = preload("res://scripts/ui/panel.gd")
const Widgets = preload("res://scripts/ui/widgets.gd")
const GameData = preload("res://scripts/data.gd")

# ---- StockPanel (RIGHT dock) — THE PROOF SLICE: Snapshot -> Panel -> Widget -> Tokens end to end ----
class StockPanel extends PanelBase.Base:
	var _rows: Dictionary = {}     # res id -> StatRow
	var _total: Widgets.StatRow
	func _init() -> void:
		panel_id = &"stock"; dock = PanelBase.DOCK_RIGHT; priority = 10
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Склад", "stock")
		for res in GameData.RES_ORDER:
			var row := Widgets.StatRow.new()
			vb.add_child(row); row.set_glyph_res(res)
			_rows[res] = row
		_total = Widgets.StatRow.new()
		vb.add_child(_total); _total.set_row("Σ", "Всього", "0")
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("stock"):
			return
		var st: Dictionary = vm.stock
		var rows: Dictionary = st.rows
		for res in _rows:
			_rows[res].set_value(int(rows.get(res, 0)))
		_total.set_value("%d/%d" % [int(st.total), int(st.cap)])

# ---- VitalsPanel (LEFT dock) — hero need bars (day/HP/hunger/rest), colored by urgency enum ----
class VitalsPanel extends PanelBase.Base:
	var _bars: Array = []          # NeedBar instances, in bar order
	var _carry: Widgets.StatRow
	func _init() -> void:
		panel_id = &"vitals"; dock = PanelBase.DOCK_LEFT; priority = 10
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Життєві", "need")
		for i in 3:
			var bar := Widgets.NeedBar.new()
			vb.add_child(bar)
			_bars.append(bar)
		_carry = Widgets.StatRow.new()
		vb.add_child(_carry); _carry.set_row("🎒", "Несе", "0/0")
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("vitals"):
			return
		var bars: Array = vm.vitals.bars
		for i in mini(_bars.size(), bars.size()):
			_bars[i].bind(bars[i])
		var carry: Dictionary = vm.vitals.carry
		_carry.set_value("%d/%d" % [int(carry.cur), int(carry.cap)])

# ---- BuildPanel (RIGHT dock) — Batch-6 catalogue palette summary: 7 category rows, each showing
# unlocked/total + affordable-now (icon+numbers, R11; research locks surface as the unlocked count) ----
class BuildPanel extends PanelBase.Base:
	var _rows: Array = []          # 7 StatRows in CAT order
	func _init() -> void:
		panel_id = &"build"; dock = PanelBase.DOCK_RIGHT; priority = 30
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Будівництво", "catalog")
		for i in 7:
			var row := Widgets.StatRow.new()
			vb.add_child(row); row.set_row("", "", "—")
			_rows.append(row)
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("catalog"):
			return
		var cat: Dictionary = vm.catalog
		if not bool(cat.get("available", false)):
			return
		var cats: Array = cat.cats
		for i in mini(_rows.size(), cats.size()):
			var c: Dictionary = cats[i]
			_rows[i].set_row(String(c.icon), String(c.label), "🔓%d/%d · ✔%d" % [int(c.unlocked), int(c.total), int(c.afford)])

# ---- ResearchPanel (LEFT dock) — active project progress + unlocked count + next startable few ----
class ResearchPanel extends PanelBase.Base:
	var _active_row: Widgets.StatRow
	var _bar: Widgets.NeedBar
	var _done: Widgets.StatRow
	var _avail: Array = []         # up to 6 StatRows of startable projects
	func _init() -> void:
		panel_id = &"research"; dock = PanelBase.DOCK_LEFT; priority = 30
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Дослідження", "tech")
		_active_row = Widgets.StatRow.new()
		vb.add_child(_active_row); _active_row.set_row("🔬", "Проєкт", "—")
		_bar = Widgets.NeedBar.new()
		vb.add_child(_bar)
		_done = Widgets.StatRow.new()
		vb.add_child(_done); _done.set_row("📖", "Відкрито", "0/0")
		for i in 6:
			var row := Widgets.StatRow.new()
			vb.add_child(row); row.set_row("", "", "")
			_avail.append(row)
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("research"):
			return
		var re: Dictionary = vm.research
		if not bool(re.get("available", false)):
			return
		var act: Dictionary = re.active
		_active_row.set_row(String(act.icon), "Проєкт", String(act.label))
		_bar.bind({"icon": "⏳", "pct": int(act.pct), "state": &"good"})
		_done.set_value("%d/%d" % [int(re.done), int(re.total)])
		var avail: Array = re.avail
		for i in _avail.size():
			if i < avail.size():
				var a: Dictionary = avail[i]
				_avail[i].set_row(String(a.icon), String(a.label), "%.1fд" % float(a.cost))
			else:
				_avail[i].set_row("", "", "")

# ---- CraftPanel (LEFT dock) — the bench bill queues from the kernel world (stalled -> warn, R11) ----
class CraftPanel extends PanelBase.Base:
	const MAX_ROWS := 8
	var _rows: Array = []
	func _init() -> void:
		panel_id = &"bills"; dock = PanelBase.DOCK_LEFT; priority = 20
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Виробництво", "bills")
		for i in MAX_ROWS:
			var row := Widgets.StatRow.new()
			vb.add_child(row); row.set_row("", "", "")
			_rows.append(row)
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("bills"):
			return
		var bl: Dictionary = vm.bills
		if not bool(bl.get("available", false)):
			return
		var rows: Array = bl.rows
		if rows.is_empty():
			_rows[0].set_row("·", "верстатів немає", "")
			for i in range(1, _rows.size()):
				_rows[i].set_row("", "", "")
			return
		for i in _rows.size():
			if i < rows.size():
				var r: Dictionary = rows[i]
				var mark: String = "⛔" if StringName(r.state) == &"warn" else String(r.icon)
				_rows[i].set_row(mark, String(r.label), String(r.value))
			else:
				_rows[i].set_row("", "", "")

# ---- BalancePanel (RIGHT dock) — the director readout: threat gauge + phase (empty-gated until §8) ----
class BalancePanel extends PanelBase.Base:
	var _gauge: Widgets.Gauge
	var _phase: Widgets.StatRow
	var _threat: Widgets.StatRow
	var _wealth: Widgets.StatRow
	var _hint: Widgets.StatRow
	func _init() -> void:
		panel_id = &"balance"; dock = PanelBase.DOCK_RIGHT; priority = 20
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Balance", "director")
		_gauge = Widgets.Gauge.new(); vb.add_child(_gauge)
		_phase = Widgets.StatRow.new(); vb.add_child(_phase); _phase.set_row("◔", "Фаза", "—")
		_threat = Widgets.StatRow.new(); vb.add_child(_threat); _threat.set_row("⚔", "Загроза", "—")
		_wealth = Widgets.StatRow.new(); vb.add_child(_wealth); _wealth.set_row("💰", "Багатство", "—")
		_hint = Widgets.StatRow.new(); vb.add_child(_hint); _hint.set_row("~", "Прогноз рейду", "—")
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("threat"):
			return
		var th: Dictionary = vm.threat
		if not bool(th.get("available", false)):
			return
		var phase: StringName = StringName(th.phase)
		var state: StringName = _phase_state(phase)
		_gauge.bind({"fill": clampf(float(th.threat) / 320.0, 0.04, 1.0), "state": state,
			"phases": [_phase_label(&"calm"), _phase_label(&"raid"), _phase_label(&"siege"), _phase_label(&"spike")],
			"active": _phase_index(phase)})
		_phase.set_value(_phase_label(phase))
		_threat.set_value(int(th.threat))
		_wealth.set_value(int(th.wealth))
		_hint.set_value("~%d рейдерів" % int(th.raid_hint))
	func _phase_index(phase: StringName) -> int:
		match phase:
			&"calm": return 0
			&"raid": return 1
			&"siege": return 2
			_: return 3
	func _phase_state(phase: StringName) -> StringName:
		match phase:
			&"calm": return &"good"
			&"raid": return &"warn"
			_: return &"crit"
	func _phase_label(phase: StringName) -> String:
		match phase:
			&"calm": return "спокій"
			&"raid": return "рейд"
			&"siege": return "облога"
			_: return "сплеск"
