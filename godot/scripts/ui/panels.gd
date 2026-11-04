# RealWorld — ui/panels.gd : concrete dock/modal panels (spec 0005 §2.6), all inner classes.
#
# Every panel `extends PanelBase.Panel` (the preloaded base's inner class — the exact idiom
# environment.gd uses for `Systems.SimSystem`). A panel reads ONE slice of the snapshot and sets values
# on children it built ONCE (R2); it never touches sim and never calls a sim mutator (R9 — it emits intents).
extends RefCounted

const PanelBase = preload("res://scripts/ui/panel.gd")
const Widgets = preload("res://scripts/ui/widgets.gd")
const ArtIcons = preload("res://scripts/ui/art_icons.gd")
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
		menu_label = "📦 Склад"; compact_open = 1
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
				_extra[i].set_row(String(e.icon), String(e.label), str(int(e.amt)), String(e.get("id", "")))
				_extra[i].visible = true
			else:
				_extra[i].visible = false
		_total.set_value("%d/%d" % [int(st.total), int(st.cap)])

# ---- VitalsPanel (LEFT dock) — hero need bars (HP/hunger/rest/blood) + located-health readout ----
class VitalsPanel extends PanelBase.Base:
	var _bars: Array = []          # NeedBar instances, in bar order
	var _bar_grid: GridContainer   # 1 column on desktop, 2×2 on a phone (same bars, no rebuild — R2)
	var _touch := false
	var _felt: Widgets.StatRow     # felt °C + comfort enum icon (R11: icon+число, не лише колір)
	var _state: Widgets.StatRow    # worst hediff inspect line / здоровий / непритомний
	var _carry: Widgets.StatRow
	func _init() -> void:
		panel_id = &"vitals"; dock = PanelBase.DOCK_LEFT; priority = 10; default_open = true
		menu_label = "❤ Життєві"; compact_open = 1
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Життєві", "need")
		_bar_grid = GridContainer.new()
		_bar_grid.columns = 1
		_bar_grid.add_theme_constant_override("h_separation", 10)
		_bar_grid.add_theme_constant_override("v_separation", 5)
		vb.add_child(_bar_grid)
		for i in 4:
			var bar := Widgets.NeedBar.new()
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_bar_grid.add_child(bar)
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
			_bars[i].tooltip_text = "%s: %d%%" % [String(bars[i].get("label", "")), int(bars[i].get("pct", 0))]
		_felt.set_value("%s %s" % [Fmt.temp(float(v.get("felt_c", 20.0))), Fmt.comfort_icon(StringName(v.get("comfort", &"ok")))])
		var conds: Array = v.get("conditions", [])
		var state_line: String = "😵 непритомний" if bool(v.get("downed", false)) else ("✔ здоровий" if conds.is_empty() else String(conds[0]))
		if not conds.is_empty() and bool(v.get("downed", false)):
			state_line += " · " + String(conds[0])
		_state.set_value(state_line)
		_state.tooltip_text = "\n".join(conds) if not conds.is_empty() else "Жодних уражень"
		var carry: Dictionary = v.carry
		_carry.set_value("%d/%d" % [int(carry.cur), int(carry.cap)])
		var touch := bool((vm.get("ui", {}) as Dictionary).get("touch", false))
		if touch != _touch:
			_touch = touch
			_bar_grid.columns = 2 if touch else 1   # a phone's dock is short: bars pair up
			_carry.visible = not touch             # the haul loop runs itself; the bar is spare

# ---- PowerPanel (RIGHT dock) — the grid readout (Batch 8c): supply/draw/battery + brownout state ----
class PowerPanel extends PanelBase.Base:
	var _supply: Widgets.StatRow
	var _draw: Widgets.StatRow
	var _battery: Widgets.StatRow
	var _state: Widgets.StatRow
	func _init() -> void:
		panel_id = &"power"; dock = PanelBase.DOCK_RIGHT; priority = 15; hotkey = KEY_E; default_open = false
		menu_label = "⚡ Енергія"; compact_open = 0
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Енергія", "power")
		_supply = Widgets.StatRow.new(); vb.add_child(_supply); _supply.set_row("⚡", "Генерація", "—")
		_draw = Widgets.StatRow.new(); vb.add_child(_draw); _draw.set_row("🔌", "Споживання", "—")
		_battery = Widgets.StatRow.new(); vb.add_child(_battery); _battery.set_row("🔋", "Батареї", "—")
		_state = Widgets.StatRow.new(); vb.add_child(_state); _state.set_row("◦", "Стан", "мережі немає")
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("power"):
			return
		var p: Dictionary = vm.power
		if not bool(p.get("participants", false)):
			_supply.set_value("—")
			_draw.set_value("—")
			_battery.set_value("—")
			_state.set_value("мережі немає")
			return
		_supply.set_value("%dW" % int(p.supply))
		_draw.set_value("%dW" % int(p.draw))
		_battery.set_value("%d/%d" % [int(p.stored), int(p.capacity)])
		_state.set_value("⚠ перевантаження" if StringName(p.state) == &"brownout" else "✔ стабільна")

# ---- BalancePanel (RIGHT dock) — the director readout: threat gauge + phase (empty-gated until §8) ----
class BalancePanel extends PanelBase.Base:
	var _gauge: Widgets.Gauge
	var _phase: Widgets.StatRow
	var _threat: Widgets.StatRow
	var _wealth: Widgets.StatRow
	var _hint: Widgets.StatRow
	func _init() -> void:
		panel_id = &"balance"; dock = PanelBase.DOCK_RIGHT; priority = 20; default_open = true
		menu_label = "⚖ Загроза"; compact_open = 0
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
		panel_id = &"research"; dock = PanelBase.DOCK_LEFT; priority = 20; default_open = false
		menu_label = "🔬 Дослідження"
		reveal_once = true   # pips into view with the first research bench (design-system §2)
	func wants_reveal(vm) -> bool:
		if not (vm is Dictionary) or not vm.has("research"):
			return false
		var r: Dictionary = vm.research
		return bool(r.get("wired", false)) and (float(r.get("rate", 0.0)) > 0.0 or int(r.get("unlocked", 0)) > 0)
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
	var _scroll: ScrollContainer   # the palette scrolls sideways when the screen is narrower (phones)
	var _hb: HBoxContainer
	var _touch_sized := false
	func _init() -> void:
		panel_id = &"build_bar"; dock = PanelBase.DOCK_BAR; priority = 10; default_open = true
	func _build() -> void:
		rebuild_count += 1
		_scroll = ScrollContainer.new()
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(_scroll)
		_hb = HBoxContainer.new()
		_hb.add_theme_constant_override("separation", 4)
		_scroll.add_child(_hb)
		for i in GameData.BUILD_ORDER.size():
			var btn := Button.new()
			btn.toggle_mode = true
			btn.add_theme_font_size_override("font_size", 12)
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			btn.expand_icon = true
			btn.add_theme_constant_override("icon_max_width", 36)
			btn.add_theme_constant_override("h_separation", 0)
			btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			btn.resized.connect(func() -> void: btn.pivot_offset = btn.size * 0.5)
			btn.mouse_entered.connect(_pop.bind(btn, 1.06, 0.10))
			btn.mouse_exited.connect(_pop.bind(btn, 1.0, 0.12))
			btn.button_down.connect(_pop.bind(btn, 0.94, 0.06))
			btn.button_up.connect(_pop.bind(btn, 1.06, 0.08))
			btn.pressed.connect(_on_slot.bind(i))
			_hb.add_child(btn)
			_btns.append(btn)
			_keys.append("")
	# Hover/press feedback: short ease-out scale tween (~0.1 s). View-only; a fresh tween kills the previous.
	func _pop(btn: Button, to: float, dur: float) -> void:
		if btn.disabled:
			return
		var tw := btn.create_tween()
		tw.tween_property(btn, "scale", Vector2(to, to), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# The SAME intent the digit keys fire — the router toggles view.selected_build (the one truth),
	# and the next bind() re-reads it from vm.build.slots[].selected, so mouse and keyboard can't drift.
	func _on_slot(i: int) -> void:
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
				_btns[i].icon = ArtIcons.building(_keys[i])
				_btns[i].disabled = locked   # замок дерева досліджень: слот видно (ціль!), тиснути — ні
				_btns[i].set_pressed_no_signal(bool(s.get("selected", false)))
				_btns[i].tooltip_text = String(s.get("tip", ""))
				_btns[i].modulate = Tokens.WHITE if (bool(s.get("afford", false)) and not locked) else Tokens.DIMMED
				_btns[i].visible = true
			else:
				_btns[i].visible = false
		_fit(bool((vm.get("ui", {}) as Dictionary).get("touch", false)))

	# Finger-sized slots on touch; the palette never runs off a narrow screen — it scrolls instead.
	func _fit(touch: bool) -> void:
		if touch != _touch_sized:
			_touch_sized = touch
			for b in _btns:
				b.custom_minimum_size = Vector2(64, 66) if touch else Vector2(84, 74)
				b.add_theme_constant_override("icon_max_width", 26 if touch else 36)
		var need: Vector2 = _hb.get_combined_minimum_size()
		var avail: float = maxf(200.0, get_viewport_rect().size.x - 44.0)
		_scroll.custom_minimum_size = Vector2(minf(need.x, avail), need.y + (10.0 if need.x > avail else 0.0))

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
		menu_label = "🎒 Спорядження"; compact_open = 0
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

# ---- TopBarPanel (TOP dock) — design-system §2 TOP BAR: 🕓 day/clock · ☀/🌙 phase · season ·
# ⛅ weather · 🌡 outdoor °C · 📍 region — plus the time chips (⏸ ×1 ×2 ×3). Reads vm.clock/env/
# region/speed (value data); a chip click emits set_speed (view state, bound by the entry scene). ----
class TopBarPanel extends PanelBase.Base:
	const CHIPS := [0.0, 1.0, 2.0, 3.0]
	# touch tools (phones have no keyboard / right button / wheel): ☰ panels menu · ✖ cancel ·
	# 🗑 remove tool · zoom out/in. Built once, shown only when vm.ui.touch (R2).
	const TOOLS := [["☰", &"toggle_menu", "Панелі та оверлеї"], ["✖", &"cancel_tool", "Скасувати"],
		["🗑", &"remove_tool", "Розібрати: торкнись своєї будівлі"], ["−", &"zoom_out", "Віддалити"], ["+", &"zoom_in", "Наблизити"]]
	var _clock: Label
	var _season: Label
	var _weather: Label
	var _temp: Label
	var _region: Label
	var _chips: Array = []
	var _tools: Array = []
	var _tool_box: HBoxContainer
	var _touch := false
	func _init() -> void:
		panel_id = &"top_bar"; dock = PanelBase.DOCK_TOP; priority = 0; default_open = true
	func _build() -> void:
		rebuild_count += 1
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		add_child(hb)
		_clock = _cell(hb, "Час доби й номер дня. Доба — 2.5 хв на ×1.")
		_season = _cell(hb, "Сезон за справжньою широтою регіону.")
		_weather = _cell(hb, "Погода регіону (сніг/дощ — вогкість; мороз — різке похолодання).")
		_temp = _cell(hb, "Температура надворі. Що відчуває тіло — у панелі «Життєві»; карта тепла — T.")
		_region = _cell(hb, "")
		_region.add_theme_color_override("font_color", Tokens.ACCENT)
		var chips := HBoxContainer.new()
		chips.add_theme_constant_override("separation", 2)
		hb.add_child(chips)
		for m in CHIPS:
			var b := Button.new()
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE   # Space must stay the pause key, not «press focused chip»
			b.text = "⏸" if m == 0.0 else "×%d" % int(m)
			b.tooltip_text = "Пауза (Space)" if m == 0.0 else "Швидкість ×%d (+/−)" % int(m)
			b.add_theme_font_size_override("font_size", 12)
			b.pressed.connect(_on_chip.bind(m))
			chips.add_child(b)
			_chips.append(b)
		_tool_box = HBoxContainer.new()
		_tool_box.add_theme_constant_override("separation", 2)
		_tool_box.visible = false
		hb.add_child(_tool_box)
		for t in TOOLS:
			var tb := Button.new()
			tb.text = String(t[0])
			tb.tooltip_text = String(t[2])
			tb.focus_mode = Control.FOCUS_NONE
			tb.custom_minimum_size = Vector2(40, 36)
			tb.toggle_mode = StringName(t[1]) == &"remove_tool" or StringName(t[1]) == &"toggle_menu"
			tb.pressed.connect(emit_intent.bind(StringName(t[1]), {}))
			_tool_box.add_child(tb)
			_tools.append(tb)
	func _cell(parent: Control, tip: String) -> Label:
		var l := Label.new()
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		parent.add_child(l)
		return l
	func _on_chip(mult: float) -> void:
		emit_intent(&"set_speed", {"mult": mult})
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("clock"):
			return
		var c: Dictionary = vm.clock
		var phase: StringName = StringName(c.get("phase", &"day"))
		_clock.text = "%s День %d · %s" % [Fmt.phase_icon(phase), int(c.get("day", 1)), String(c.get("hhmm", ""))]
		var season := String(c.get("season", ""))
		_season.text = "%s %s" % [Fmt.season_icon(season), season] if season != "" else ""
		_season.visible = season != "" and not _touch
		var env: Dictionary = vm.get("env", {})
		_weather.text = Fmt.weather_label(StringName(env.get("weather", &"clear")))
		var t: float = float(env.get("temp_c", 15.0))
		var anomaly: float = float(env.get("anomaly_c", 0.0))
		_temp.text = "🌡 %s%s" % [Fmt.temp(t), " ⚠" if anomaly < 0.0 else ""]
		var heat: Dictionary = vm.get("heat", {})
		var lo: float = float(heat.get("comfort_min", 12.0))
		var hi: float = float(heat.get("comfort_max", 30.0))
		_temp.add_theme_color_override("font_color", Tokens.TEAL if t < lo else (Tokens.CRIT if t > hi else Tokens.INK))
		var reg: Dictionary = vm.get("region", {})
		if not reg.is_empty():
			_region.text = "📍 %s" % String(reg.get("name", ""))
			_region.tooltip_text = "%s · seed %s — координати = seed світу: ними можна ділитися" % [
				Fmt.region_line(String(reg.get("name", "")), float(reg.get("lat", 0.0)), float(reg.get("lon", 0.0))),
				Fmt.seed_hex(int(reg.get("seed", 0)))]
		var speed: float = float(vm.get("speed", 1.0))
		for i in _chips.size():
			_chips[i].set_pressed_no_signal(is_equal_approx(float(CHIPS[i]), speed))
		var ui: Dictionary = vm.get("ui", {})
		var touch := bool(ui.get("touch", false))
		if touch != _touch:
			_touch = touch
			_tool_box.visible = touch
			_season.visible = not touch and _season.text != ""   # a phone's top strip keeps the essentials
			_region.visible = not touch
			for chip in _chips:
				chip.custom_minimum_size = Vector2(40, 36) if touch else Vector2.ZERO
		if touch:
			_tools[0].set_pressed_no_signal(bool(ui.get("menu", false)))
			_tools[2].set_pressed_no_signal(bool(ui.get("remove", false)))

# ---- GoalsPanel (LEFT dock, J) — the onboarding chain made visible: the current goal, HOW to do it
# (keys named), its live progress and what comes next. Reads vm.goals (session goals_view, R8). ----
class GoalsPanel extends PanelBase.Base:
	var _count: Widgets.H2Header
	var _title: Label
	var _hint: Label
	var _bar: Widgets.NeedBar
	var _next: Label
	func _init() -> void:
		panel_id = &"goals"; dock = PanelBase.DOCK_LEFT; priority = 15; hotkey = KEY_J; default_open = true
		menu_label = "🎯 Цілі"; compact_open = 1
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		add_child(vb)
		_count = Widgets.H2Header.new()
		vb.add_child(_count); _count.set_header("Цілі", "0/0")
		_title = Label.new()
		_title.add_theme_font_size_override("font_size", 14)
		_title.add_theme_color_override("font_color", Tokens.AMBER)
		vb.add_child(_title)
		_hint = Label.new()
		_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_hint.custom_minimum_size = Vector2(210, 0)
		_hint.add_theme_font_size_override("font_size", 12)
		_hint.add_theme_color_override("font_color", Tokens.INK)
		vb.add_child(_hint)
		_bar = Widgets.NeedBar.new()
		vb.add_child(_bar)
		_next = Label.new()
		_next.add_theme_font_size_override("font_size", 11)
		_next.add_theme_color_override("font_color", Tokens.DIM)
		_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_next.custom_minimum_size = Vector2(210, 0)
		vb.add_child(_next)
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("goals"):
			return
		var g: Dictionary = vm.goals
		if not bool(g.get("available", false)):
			visible = false
			return
		_count.set_header("Цілі", "%d/%d" % [int(g.get("done", 0)), int(g.get("total", 0))])
		if bool(g.get("all_done", false)):
			_title.text = "🏁 Базу закладено!"
			_hint.text = "Далі — вільна гра: досліджуй (N/U), торгуй конвоями (M), подорожуй капсулою (V), запроси друзів (O)."
			_bar.visible = false
			_next.visible = false
			return
		var cur: Dictionary = g.get("current", {})
		_title.text = String(cur.get("title", ""))
		var touch := bool((vm.get("ui", {}) as Dictionary).get("touch", false))
		_hint.text = Fmt.touchify(String(cur.get("hint", ""))) if touch else String(cur.get("hint", ""))
		var pct: int = int(round(float(cur.get("pct", 0.0)) * 100.0))
		_bar.visible = true
		_bar.bind({"icon": "◎", "pct": pct, "state": &"good" if pct >= 100 else &"warn"})
		var nxt := String(g.get("next", ""))
		_next.text = ("далі: " + nxt) if nxt != "" else ""
		_next.visible = nxt != ""
