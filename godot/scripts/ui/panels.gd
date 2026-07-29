# RealWorld — ui/panels.gd : concrete dock/modal panels (spec 0005 §2.6), all inner classes.
#
# Every panel `extends PanelBase.Panel` (the preloaded base's inner class — the exact idiom
# environment.gd uses for `Systems.SimSystem`). A panel reads ONE slice of the snapshot and sets values
# on children it built ONCE (R2); it never touches sim and never calls a sim mutator (R9 — it emits intents).
extends RefCounted

const PanelBase = preload("res://scripts/ui/panel.gd")
const Widgets = preload("res://scripts/ui/widgets.gd")
const GameData = preload("res://scripts/data.gd")
const Tokens = preload("res://scripts/ui/tokens.gd")
const Fmt = preload("res://scripts/ui/format.gd")

# ---- StockPanel (RIGHT dock) — THE PROOF SLICE: Snapshot -> Panel -> Widget -> Tokens end to end ----
class StockPanel extends PanelBase.Base:
	const EXTRA_POOL := 8          # fixed pool of catalogue-stock lines (R2; slice caps to match)
	var _rows: Dictionary = {}     # res id -> StatRow
	var _extra: Array = []         # StatRow pool for catalogue-only resources (spec 0008 phase 4)
	var _total: Widgets.StatRow
	func _init() -> void:
		panel_id = &"stock"; dock = PanelBase.DOCK_RIGHT; priority = 10; default_open = true
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
		for i in EXTRA_POOL:
			var xrow := Widgets.StatRow.new()
			vb.add_child(xrow); xrow.set_row("•", "—", "")
			xrow.visible = false
			_extra.append(xrow)
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
		var extra: Array = st.get("extra", [])
		for i in _extra.size():
			if i < extra.size():
				var e: Dictionary = extra[i]
				_extra[i].set_row(String(e.icon), String(e.label), str(int(e.amt)))
				_extra[i].visible = true
			else:
				_extra[i].visible = false
		_total.set_value("%d/%d" % [int(st.total), int(st.cap)])

# ---- VitalsPanel (LEFT dock) — hero need bars (HP/hunger/rest/blood) + located-health readout ----
class VitalsPanel extends PanelBase.Base:
	var _bars: Array = []          # NeedBar instances, in bar order
	var _felt: Widgets.StatRow     # felt °C + comfort enum icon (R11: icon+число, не лише колір)
	var _state: Widgets.StatRow    # worst hediff inspect line / здоровий / непритомний
	var _carry: Widgets.StatRow
	func _init() -> void:
		panel_id = &"vitals"; dock = PanelBase.DOCK_LEFT; priority = 10; default_open = true
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Життєві", "need")
		for i in 4:
			var bar := Widgets.NeedBar.new()
			vb.add_child(bar)
			_bars.append(bar)
		_felt = Widgets.StatRow.new()
		vb.add_child(_felt); _felt.set_row("🌡", "Відчуття", "—")
		_state = Widgets.StatRow.new()
		vb.add_child(_state); _state.set_row("🩺", "Стан", "—")
		_carry = Widgets.StatRow.new()
		vb.add_child(_carry); _carry.set_row("🎒", "Несе", "0/0")
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("vitals"):
			return
		var v: Dictionary = vm.vitals
		var bars: Array = v.bars
		for i in mini(_bars.size(), bars.size()):
			_bars[i].bind(bars[i])
		_felt.set_value("%d°C %s" % [int(round(float(v.get("felt_c", 20.0)))), Fmt.comfort_icon(StringName(v.get("comfort", &"ok")))])
		var conds: Array = v.get("conditions", [])
		var state_line: String = "😵 непритомний" if bool(v.get("downed", false)) else ("✔ здоровий" if conds.is_empty() else String(conds[0]))
		if not conds.is_empty() and bool(v.get("downed", false)):
			state_line += " · " + String(conds[0])
		_state.set_value(state_line)
		var carry: Dictionary = v.carry
		_carry.set_value("%d/%d" % [int(carry.cur), int(carry.cap)])

# ---- BalancePanel (RIGHT dock) — the director readout: threat gauge + phase (empty-gated until §8) ----
class BalancePanel extends PanelBase.Base:
	var _gauge: Widgets.Gauge
	var _phase: Widgets.StatRow
	var _threat: Widgets.StatRow
	var _wealth: Widgets.StatRow
	var _hint: Widgets.StatRow
	func _init() -> void:
		panel_id = &"balance"; dock = PanelBase.DOCK_RIGHT; priority = 20; default_open = true
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
	var _unlocks: Widgets.StatRow
	var _cat: Widgets.StatRow
	var _rows: Array = []      # ChoiceRow pool (researchable options), built ONCE (R2)
	var _qrows: Array = []     # StatRow pool (the queue)
	func _init() -> void:
		panel_id = &"research"; dock = PanelBase.DOCK_LEFT; priority = 20; default_open = true
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
		_unlocks = Widgets.StatRow.new(); vb.add_child(_unlocks); _unlocks.set_row("🔓", "Відкриє", "—")
		_cat = Widgets.StatRow.new(); vb.add_child(_cat); _cat.set_row("📚", "Каталог", "—")
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
			_unlocks.set_value("—"); _cat.set_value("—")
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
		var eta: float = float(r.get("active_eta_days", -1.0))
		var eta_str: String = (" ≈%.1fд" % eta) if (al != "" and eta >= 0.0) else ""
		_active_lbl.set_value((al + eta_str) if al != "" else "—")
		var nu: Dictionary = r.get("next_unlocks", {})
		var nu_total: int = int(nu.get("total", 0))
		_unlocks.set_value(("%d (%dб %dр %dп)" % [nu_total, int(nu.get("buildings", 0)), int(nu.get("recipes", 0)), int(nu.get("items", 0))]) if nu_total > 0 else "—")
		var cc: Dictionary = r.get("counts", {})
		var cb: Dictionary = cc.get("buildings", {})
		var cr: Dictionary = cc.get("recipes", {})
		var ci: Dictionary = cc.get("items", {})
		_cat.set_value("%dб %dр %dп" % [int(cb.get("unlocked", 0)), int(cr.get("unlocked", 0)), int(ci.get("unlocked", 0))])
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

# ---- BuildBarPanel (BAR dock) — the placement bar (main.gd parity): one toggle Button per buildable.
# A FIXED pool sized from GameData.BUILD_ORDER at _build time (R2); bind() only re-texts/re-modulates. ----
class BuildBarPanel extends PanelBase.Base:
	var _btns: Array = []      # fixed Button pool, one per GameData.BUILD_ORDER entry (R2)
	var _keys: Array = []      # current build kind per button, refreshed in bind()
	func _init() -> void:
		panel_id = &"build_bar"; dock = PanelBase.DOCK_BAR; priority = 10; default_open = true
	func _build() -> void:
		rebuild_count += 1
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		add_child(hb)
		for i in GameData.BUILD_ORDER.size():
			var btn := Button.new()
			btn.toggle_mode = true
			btn.add_theme_font_size_override("font_size", 12)
			btn.pressed.connect(_on_slot.bind(i))
			hb.add_child(btn)
			_btns.append(btn)
			_keys.append("")
	# LOCAL radio: arming slot i visually un-presses the rest; clicking the armed slot again disarms.
	# Either way the SAME intent fires — the router toggles view.selected_build (the actual truth).
	# NOTE: the pressed look is purely local, so digits 1..0 armed via the keyboard router won't sync
	# the bar's visuals — acceptable for now.
	func _on_slot(i: int) -> void:
		if _btns[i].button_pressed:
			for j in _btns.size():
				if j != i:
					_btns[j].button_pressed = false
		emit_intent(&"select_build", {"kind": String(_keys[i])})
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("build"):
			return
		var slots: Array = vm.build.slots
		for i in _btns.size():
			if i < slots.size():
				var s: Dictionary = slots[i]
				_keys[i] = String(s.get("key", ""))
				var locked := bool(s.get("locked", false))
				var name := ("🔒 " + String(s.get("name", ""))) if locked else String(s.get("name", ""))
				_btns[i].text = "%s %s\n%s" % [String(s.get("hotkey", "")), name, String(s.get("cost", ""))]
				_btns[i].disabled = locked   # замок дерева досліджень: слот видно (ціль!), тиснути — ні
				_btns[i].modulate = Tokens.WHITE if (bool(s.get("afford", false)) and not locked) else Tokens.DIMMED
				_btns[i].visible = true
			else:
				_btns[i].visible = false

# ---- GearPanel (LEFT dock) — craft + equip loadout (spec 0001 parity): one FIXED row per
# GameData.ITEM_ORDER entry (R2), each row = status Label + "⚒" craft + "✋" equip buttons.
# Buttons emit intents only (R9); afford/owned state is icon+disable, never color alone (R11). ----
class GearPanel extends PanelBase.Base:
	var _rowboxes: Array = []  # fixed HBoxContainer pool, one per GameData.ITEM_ORDER entry (R2)
	var _labels: Array = []
	var _crafts: Array = []
	var _equips: Array = []
	var _ids: Array = []       # current item id per row, refreshed in bind()
	func _init() -> void:
		panel_id = &"gear"; dock = PanelBase.DOCK_LEFT; priority = 80; hotkey = KEY_I; default_open = false
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Спорядження", "gear")
		for i in GameData.ITEM_ORDER.size():
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			vb.add_child(row)
			var lbl := Label.new()
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_font_size_override("font_size", 12)
			lbl.clip_text = true
			row.add_child(lbl)
			var cb := Button.new()
			cb.text = "⚒"
			cb.pressed.connect(_on_craft.bind(i))
			row.add_child(cb)
			var eb := Button.new()
			eb.text = "✋"
			eb.pressed.connect(_on_equip.bind(i))
			row.add_child(eb)
			_rowboxes.append(row); _labels.append(lbl); _crafts.append(cb); _equips.append(eb)
			_ids.append("")
	func _on_craft(i: int) -> void:
		emit_intent(&"craft", {"id": String(_ids[i])})   # panel emits intent; router calls sim (R9)
	func _on_equip(i: int) -> void:
		emit_intent(&"equip", {"id": String(_ids[i])})
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("gear"):
			return
		var rows: Array = vm.gear.rows
		for i in _rowboxes.size():
			if i >= rows.size():
				_rowboxes[i].visible = false
				continue
			_rowboxes[i].visible = true
			var rw: Dictionary = rows[i]
			_ids[i] = String(rw.get("id", ""))
			var locked := bool(rw.get("locked", false))
			var txt := "%s%s  %s" % ["🔒 " if locked else "", String(rw.get("name", "")), String(rw.get("cost", ""))]
			if bool(rw.get("equipped", false)):
				txt += " · ✔ вдягнуто"
			elif bool(rw.get("owned", false)):
				txt += " · є"
			_labels[i].text = txt
			var afford := bool(rw.get("affordable", false)) and not locked
			_crafts[i].disabled = not afford
			_crafts[i].modulate = Tokens.WHITE if afford else Tokens.DIMMED
			_equips[i].disabled = not bool(rw.get("owned", false))
