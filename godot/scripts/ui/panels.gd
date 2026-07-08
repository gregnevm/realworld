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

# ---- ResearchPanel (LEFT dock) — the tech-pipeline surface: level + active progress bar, a clickable
# list of researchable projects (click -> enqueue_research intent), and the research queue. This is the
# whole progression PIPELINE made visible + drivable; it reads ONLY vm.research (a pure Progression slice). ----
class ResearchPanel extends PanelBase.Base:
	const AVAIL_MAX := 5
	const QUEUE_MAX := 3
	var _level: Widgets.StatRow
	var _counts: Widgets.StatRow
	var _active_bar: Widgets.NeedBar
	var _active_lbl: Widgets.StatRow
	var _rows: Array = []      # ChoiceRow pool (researchable options), built ONCE (R2)
	var _qrows: Array = []     # StatRow pool (the queue)
	func _init() -> void:
		panel_id = &"research"; dock = PanelBase.DOCK_LEFT; priority = 20
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Дослідження", "tech")
		_level = Widgets.StatRow.new(); vb.add_child(_level); _level.set_row("🔬", "Рівень", "0")
		_counts = Widgets.StatRow.new(); vb.add_child(_counts); _counts.set_row("✔", "Відкрито", "0/0")
		_active_bar = Widgets.NeedBar.new(); vb.add_child(_active_bar)
		_active_lbl = Widgets.StatRow.new(); vb.add_child(_active_lbl); _active_lbl.set_row("▶", "Активне", "—")
		var h2 := Widgets.H2Header.new(); vb.add_child(h2); h2.set_header("Доступні", "queue")
		for i in AVAIL_MAX:
			var row := Widgets.ChoiceRow.new()
			vb.add_child(row)
			row.picked.connect(_on_pick)
			_rows.append(row)
		var h3 := Widgets.H2Header.new(); vb.add_child(h3); h3.set_header("Черга", "")
		for i in QUEUE_MAX:
			var q := Widgets.StatRow.new()
			vb.add_child(q); q.set_row("→", "—", "")
			_qrows.append(q)
	func _on_pick(id: StringName) -> void:
		emit_intent(&"enqueue_research", {"id": String(id)})   # panel emits intent; router calls sim (R9)
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("research"):
			return
		var r: Dictionary = vm.research
		if not bool(r.get("wired", false)):
			_level.set_value("—"); _counts.set_value("—/—")
			_active_bar.bind({"icon": "🔬", "pct": 0, "state": &"warn"})
			_active_lbl.set_value("немає стола")
			for row in _rows:
				row.bind({"id": &"", "shown": false})
			for q in _qrows:
				q.visible = false
			return
		_level.set_value("%d" % int(r.get("level", 0)))
		_counts.set_value("%d/%d" % [int(r.get("unlocked", 0)), int(r.get("total", 0))])
		var al := String(r.get("active_label", ""))
		var pct: int = int(round(float(r.get("active_pct", 0.0)) * 100.0))
		_active_bar.bind({"icon": "🔬", "pct": pct, "state": (&"good" if al != "" else &"warn")})
		_active_lbl.set_value(al if al != "" else "—")
		var opts: Array = r.get("options", [])
		for i in _rows.size():
			if i < opts.size():
				var o: Dictionary = opts[i]
				_rows[i].bind({
					"id": o.id,
					"label": String(o.label),
					"meta": "T%d·%d" % [int(o.tier), int(round(float(o.cost)))],
					"tip": "Тир %d · вартість %.1f — додати в чергу досліджень" % [int(o.tier), float(o.cost)],
					"shown": true,
				})
			else:
				_rows[i].bind({"id": &"", "shown": false})
		var q: Array = r.get("queue", [])
		for i in _qrows.size():
			if i < q.size():
				_qrows[i].set_row("→", String(q[i].label), "T%d" % int(q[i].tier))
				_qrows[i].visible = true
			else:
				_qrows[i].visible = false
