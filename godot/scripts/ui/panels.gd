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
	# Mobile-HUD redesign (2026-11): a bare row of resource medallions (icon + count badge, name in the
	# tooltip) — Clash/Boom-Beach-style counters, no box, no header, no labels. Storage fill is the last token.
	const EXTRA_POOL := 8          # fixed pool of catalogue-stock tokens (R2; slice caps to match)
	const FOOD_WARN := 4           # portions: below this the food token warns (≈ one hungry day)
	var _rows: Dictionary = {}     # res id -> Medallion
	var _extra: Array = []         # Medallion pool for catalogue-only resources (spec 0008 phase 4)
	var _total: Widgets.Medallion
	var _pack := false
	func _init() -> void:
		panel_id = &"stock"; dock = PanelBase.DOCK_RIGHT; priority = 10; default_open = true; bare = true
		menu_label = "📦 Склад"; compact_open = 1
	func _build() -> void:
		rebuild_count += 1
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 2)
		flow.alignment = FlowContainer.ALIGNMENT_END
		flow.custom_minimum_size = Vector2(330, 0)
		add_child(flow)
		for res in GameData.RES_ORDER:
			var m := Widgets.Medallion.new()
			flow.add_child(m)
			m.set_token(ArtIcons.res(String(res)), String(GameData.RES[res].icon), String(GameData.RES[res].label))
			_rows[res] = m
		for i in EXTRA_POOL:
			var xm := Widgets.Medallion.new()
			flow.add_child(xm)
			xm.visible = false
			_extra.append(xm)
		_total = Widgets.Medallion.new()
		flow.add_child(_total)
		_total.set_token(ArtIcons.building("storage"), "Σ", "Склад заповнено")   # storage crate ≠ the hero's backpack
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("stock"):
			return
		var st: Dictionary = vm.stock
		var rows: Dictionary = st.rows
		var learning: bool = int((vm.get("clock", {}) as Dictionary).get("day", 1)) <= VitalsPanel.LEARN_DAYS
		for res in _rows:
			var n: int = int(rows.get(res, 0))
			# alarm hierarchy: «8 food — мало?» was the loudest red on screen while a robot broke the wall.
			# Out of food is critical, a few portions left is a warning, the rest is calm.
			var fstate: StringName = (&"crit" if n == 0 else (&"warn" if n < FOOD_WARN else &"good")) if res == "food" else &"good"
			var cap: String = ("Нема їжі" if fstate == &"crit" else "Мало їжі") if fstate != &"good" else (String(GameData.RES[res].label) if learning else "")
			_rows[res].bind({"value": str(n), "state": fstate, "caption": cap})
			# what you hold, plus food always (running out of it is the news); a «0» medallion was noise
			# that the independent read could not decode (gamedev §5)
			_rows[res].visible = n > 0 or res == "food"
		var extra: Array = st.get("extra", [])
		for i in _extra.size():
			if i < extra.size():
				var e: Dictionary = extra[i]
				if _extra[i].label != String(e.label):
					_extra[i].set_token(ArtIcons.res(String(e.get("id", ""))), String(e.icon), String(e.label))
				_extra[i].bind({"value": str(int(e.amt)), "state": &"good"})
				_extra[i].visible = true
			else:
				_extra[i].visible = false
		var fill: float = float(st.total) / maxf(1.0, float(st.cap))
		var pack: bool = bool(st.get("backpack", false))
		if pack != _pack:   # spec 0009: the counter is the BACKPACK's slots, not the storage — say so with the right icon
			_pack = pack
			_total.set_token(ArtIcons.for_glyph("🎒") if pack else ArtIcons.building("storage"), "🎒" if pack else "Σ",
				"Рюкзак: зайнято слотів" if pack else "Склад заповнено")
		var tstate: StringName = &"crit" if fill >= 0.98 else (&"warn" if fill >= 0.85 else &"good")
		var tcap: String = ("Повний" if tstate == &"crit" else ("Майже повний" if tstate == &"warn" else ("Слоти" if pack else "Склад") if learning else ""))
		_total.bind({"value": "%d/%d" % [int(st.total), int(st.cap)], "state": tstate, "caption": tcap})

# ---- VitalsPanel (LEFT dock) — hero need bars (HP/hunger/rest/blood) + located-health readout ----
class VitalsPanel extends PanelBase.Base:
	# Mobile-HUD redesign (2026-11): no bars, no header, no box. A row of medallions — health, hunger,
	# rest, warmth (+ carry) — whose ring colour/shape/number says the state; blood and afflictions appear
	# ONLY while active (The Long Dark pattern). Fixed widget pool, bind() swaps values (R2).
	# captions: the need's NAME during the first days (learning window), afterwards only the ALERT word while off
	const LEARN_DAYS := 2
	const NAMES := ["Здоров'я", "Ситість", "Сон", "Кров"]
	const ALERTS := ["Поранено", "Голод", "Втома", "Кровотеча"]
	var _meds: Array = []          # Medallion per need bar (hp, hunger, rest, blood) in slice order
	var _warm: Widgets.Medallion   # felt °C + comfort state
	var _carry: Widgets.Medallion
	var _row: HBoxContainer
	var _cond: Label               # active afflictions only; hidden when healthy
	func _init() -> void:
		panel_id = &"vitals"; dock = PanelBase.DOCK_LEFT; priority = 10; default_open = true; bare = true
		menu_label = "❤ Життєві"; compact_open = 1
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		add_child(vb)
		_row = HBoxContainer.new()
		_row.add_theme_constant_override("separation", 6)
		vb.add_child(_row)
		for i in 4:
			var m := Widgets.Medallion.new()
			m.quiet_when_good = true
			_row.add_child(m)
			_meds.append(m)
		_warm = Widgets.Medallion.new()
		_warm.quiet_when_good = true
		_row.add_child(_warm)
		_warm.set_token(ArtIcons.for_glyph("🌡"), "🌡", "Відчуття тепла (з одягом)")
		_carry = Widgets.Medallion.new()
		_row.add_child(_carry)
		_carry.set_token(ArtIcons.for_glyph("🎒"), "🎒", "Несе")
		_cond = Label.new()
		_cond.add_theme_font_size_override("font_size", 13)
		_cond.add_theme_color_override("font_color", Tokens.CRIT)
		_cond.add_theme_color_override("font_outline_color", Tokens.BG)
		_cond.add_theme_constant_override("outline_size", 4)
		_cond.visible = false
		vb.add_child(_cond)
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("vitals"):
			return
		var v: Dictionary = vm.vitals
		var bars: Array = v.bars
		var learning: bool = int((vm.get("clock", {}) as Dictionary).get("day", 1)) <= LEARN_DAYS
		for i in mini(_meds.size(), bars.size()):
			var bar: Dictionary = bars[i]
			var pct: int = int(bar.get("pct", 0))
			if _meds[i].label == "":
				_meds[i].set_token(ArtIcons.for_glyph(String(bar.get("icon", ""))), String(bar.get("icon", "")), String(bar.get("label", "")))
			var st: StringName = bar.get("state", &"good")
			var cap: String = (ALERTS[i] if st == &"warn" or st == &"crit" else (NAMES[i] if learning else "")) if i < NAMES.size() else ""
			_meds[i].bind({"value": "%d" % pct, "state": st, "caption": cap})
			# blood is an affliction channel: shown only while bleeding/low (index 3 in the slice)
			if i == 3:
				_meds[i].visible = pct < 100
		var felt := float(v.get("felt_c", 20.0))
		var comfort := StringName(v.get("comfort", &"ok"))
		var wstate: StringName = &"good" if comfort == &"ok" else (&"crit" if absf(felt - 18.0) > 22.0 else &"warn")
		var wcap: String = ("Холодно" if comfort == &"cold" else "Спекотно") if comfort != &"ok" else ("Тепло" if learning else "")
		# no «11°» beside the top bar's «−19°C»: two temperatures read as a riddle (2nd independent read) —
		# the ring + the word say it; the felt °C itself lives in the tooltip
		_warm.bind({"value": "", "state": wstate, "caption": wcap})
		_warm.tooltip_text = "Відчуття тепла з одягом: %d°C (надворі — у верхній смузі)" % int(round(felt))
		# spec 0014 REQ-0014-11: поки кільце на мапі вказує на засіб («холод → багаття»), медальйон «Холодно» дихає в такт слоту — зв'язок видно без тексту
		var gp: Dictionary = vm.get("goal_pointer", {}) if vm is Dictionary else {}
		if String(gp.get("kind", "")) == "need":
			var kb: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
			_warm.modulate = Tokens.WHITE.lerp(Tokens.AMBER, 0.45 * kb)
		elif _warm.modulate != Tokens.WHITE:
			_warm.modulate = Tokens.WHITE
		var carry: Dictionary = v.carry
		_carry.bind({"value": "%d/%d" % [int(carry.cur), int(carry.cap)], "state": &"info" if int(carry.cur) > 0 else &"good"})
		var conds: Array = v.get("conditions", [])
		var downed := bool(v.get("downed", false))
		var line: String = ("😵 непритомний · " if downed else "") + (String(conds[0]) if not conds.is_empty() else "")
		_cond.text = line.trim_suffix(" · ")
		_cond.visible = _cond.text != ""
		_cond.tooltip_text = "\n".join(conds)
		var touch := bool((vm.get("ui", {}) as Dictionary).get("touch", false))
		# spec 0009: in an inventory world the backpack medallion (top-right) IS the load — «ноша» would repeat it
		var inv_on := bool((vm.get("inventory", {}) as Dictionary).get("enabled", false))
		_carry.visible = not touch and not inv_on   # the haul loop runs itself; a phone has no spare width

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
		panel_id = &"balance"; dock = PanelBase.DOCK_RIGHT; priority = 20; hotkey = KEY_X; default_open = false   # director internals: on demand, not on the player's face
		menu_label = "⚖ Загроза"; compact_open = 0
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Загроза", "")
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
		panel_id = &"research"; dock = PanelBase.DOCK_LEFT; priority = 20; default_open = false; collapsed_default = true   # long & secondary: starts folded, header click unfolds
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
	var _guide := ""               # build kind the current onboarding goal is about → that slot pulses
	var _hb: HBoxContainer
	var _sized_for := -1           # 0 desktop / 1 touch the slots were last sized for; -1 = never (first _fit sizes)
	# Touch build DRAWER (mobile research 2026-11: Clash of Clans / Don't Starve — a Build button under the
	# right thumb opens a categorised drawer; the map stays live). Desktop keeps the flat 1–0 hotkey row.
	const CATS := [
		{"name": "Будова", "icon": "wall", "keys": ["wall", "door", "floor"]},
		{"name": "Побут", "icon": "campfire", "keys": ["storage", "bed", "campfire", "torch", "lamp", "heater"]},
		{"name": "Ремесло", "icon": "workbench", "keys": ["workbench", "research_bench"]},
		{"name": "Оборона", "icon": "turret", "keys": ["turret", "spike_trap"]},
	]
	var _touch := false
	var external_drawer := false   # touch action scheme: no 🔨 FAB — the mode (Build) opens/closes the drawer
	var _open := false             # touch drawer open?
	var _cat := 0                  # touch: the category shown
	var _fab: Button               # 🔨 build button (touch only)
	var _tabs: HBoxContainer
	var _tab_btns: Array = []
	func _init() -> void:
		panel_id = &"build_bar"; dock = PanelBase.DOCK_BAR; priority = 10; default_open = true
	static func cat_of(key: String) -> int:
		for ci in CATS.size():
			if (CATS[ci].keys as Array).has(key):
				return ci
		return 1                   # catalogue-live extras land in «Побут» (never lost)
	func set_drawer(open: bool) -> void:
		_open = open
		_apply_layout()
	func set_category(ci: int) -> void:
		_cat = clampi(ci, 0, CATS.size() - 1)
		_open = true
		_apply_layout()
	func _apply_layout() -> void:
		if _tabs == null:
			return
		_fab.visible = _touch and not external_drawer
		_tabs.visible = _touch and _open
		_scroll.visible = (not _touch) or _open
		_fab.set_pressed_no_signal(_open)
		for ci in _tab_btns.size():
			_tab_btns[ci].set_pressed_no_signal(ci == _cat)
	func _build() -> void:
		rebuild_count += 1
		var root := VBoxContainer.new()
		root.add_theme_constant_override("separation", 4)
		add_child(root)
		_tabs = HBoxContainer.new()
		_tabs.add_theme_constant_override("separation", 4)
		root.add_child(_tabs)
		for ci in CATS.size():
			var tb := Button.new()
			tb.toggle_mode = true
			tb.icon = ArtIcons.building(String(CATS[ci].icon))
			tb.expand_icon = true
			tb.add_theme_constant_override("icon_max_width", 26)
			tb.text = String(CATS[ci].name)
			tb.custom_minimum_size = Vector2(96, 44)
			tb.focus_mode = Control.FOCUS_NONE
			tb.pressed.connect(set_category.bind(ci))
			_tabs.add_child(tb)
			_tab_btns.append(tb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		root.add_child(row)
		_scroll = ScrollContainer.new()
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		row.add_child(_scroll)
		_fab = Button.new()
		_fab.toggle_mode = true
		_fab.text = "🔨"
		_fab.add_theme_font_size_override("font_size", 26)
		_fab.custom_minimum_size = Vector2(60, 60)
		_fab.focus_mode = Control.FOCUS_NONE
		_fab.tooltip_text = "Будувати"
		_fab.pressed.connect(func() -> void: set_drawer(not _open))
		row.add_child(_fab)
		_apply_layout()   # desktop by default: no 🔨/tabs until the frame says touch
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
		var gl: Variant = vm.get("goals", {})
		_guide = String(((gl as Dictionary).get("current", {}) as Dictionary).get("build", "")) if gl is Dictionary else ""
		for i in _btns.size():
			if i < slots.size():
				var s: Dictionary = slots[i]
				_keys[i] = String(s.get("key", ""))
				var locked := bool(s.get("locked", false))
				# icon-only slot (mobile best practice: glyph in a ≥48 px target, label + cost in the tooltip);
				# the visible text is just the hotkey digit (or the lock) — the art says what it is
				_btns[i].text = "🔒" if locked else String(s.get("hotkey", ""))
				_btns[i].icon = ArtIcons.building(_keys[i])
				var tip_head := "%s  ·  %s" % [String(s.get("name", "")), String(s.get("cost", ""))]
				_btns[i].disabled = locked   # замок дерева досліджень: слот видно (ціль!), тиснути — ні
				_btns[i].set_pressed_no_signal(bool(s.get("selected", false)))
				_btns[i].tooltip_text = tip_head + ("\n" + String(s.get("tip", "")) if String(s.get("tip", "")) != "" else "")
				var base_mod: Color = Tokens.WHITE if (bool(s.get("afford", false)) and not locked) else Tokens.DIMMED
				if _keys[i] == _guide and not locked and not bool(s.get("selected", false)):
					# onboarding pulse: the slot the current goal needs breathes amber (shape+motion, not colour alone)
					var k: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
					base_mod = base_mod.lerp(Tokens.AMBER, 0.45 * k)
					_btns[i].scale = Vector2.ONE * (1.0 + 0.04 * k)
				elif _btns[i].scale != Vector2.ONE and not _btns[i].is_hovered():
					_btns[i].scale = Vector2.ONE
				_btns[i].modulate = base_mod
				_btns[i].visible = (not _touch) or cat_of(_keys[i]) == _cat
			else:
				_btns[i].visible = false
		var touch := bool((vm.get("ui", {}) as Dictionary).get("touch", false))
		if touch != _touch:
			_touch = touch
			_open = _open and external_drawer
			_apply_layout()
		if _touch:
			# guidance travels with the drawer: closed → the 🔨 pulses; open on another tab → that tab pulses
			var gk: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
			var gc: int = cat_of(_guide) if _guide != "" else -1
			_fab.modulate = Tokens.WHITE.lerp(Tokens.AMBER, 0.5 * gk) if (gc >= 0 and not _open) else Tokens.WHITE
			for ci in _tab_btns.size():
				_tab_btns[ci].modulate = Tokens.WHITE.lerp(Tokens.AMBER, 0.5 * gk) if (ci == gc and ci != _cat and _open) else Tokens.WHITE
		_fit(touch)

	# Finger-sized slots on touch; the palette never runs off a narrow screen — it scrolls instead.
	func _fit(touch: bool) -> void:
		if int(touch) != _sized_for:
			_sized_for = int(touch)
			for b in _btns:
				b.custom_minimum_size = Vector2(56, 58) if touch else Vector2(58, 62)
				b.add_theme_constant_override("icon_max_width", 34 if touch else 38)
		var need: Vector2 = _hb.get_combined_minimum_size()
		var avail: float = maxf(200.0, get_viewport_rect().size.x - 44.0)
		_scroll.custom_minimum_size = Vector2(minf(need.x, avail), need.y + (10.0 if need.x > avail else 0.0))

# ---- GearPanel (LEFT dock) — craft + equip loadout (spec 0001 parity): one FIXED row per
# GameData.ITEM_ORDER entry (R2), each row = status Label + "⚒" craft + "✋" equip buttons.
# Buttons emit intents only (R9); afford/owned state is icon+disable, never color alone (R11). ----
class GearPanel extends PanelBase.Base:
	var _rowboxes: Array = []  # fixed HBoxContainer pool, one per GameData.ITEM_ORDER entry (R2)
	var _labels: Array = []
	var _icons: Array = []     # TextureRect per row: generated item art (item_<id>), emoji-free
	var _crafts: Array = []
	var _equips: Array = []
	var _ids: Array = []       # current item id per row, refreshed in bind()
	func _init() -> void:
		panel_id = &"gear"; dock = PanelBase.DOCK_LEFT; priority = 80; hotkey = KEY_I; default_open = false
		menu_label = "🎒 Інвентар"; compact_open = 0
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
			var ic := TextureRect.new()
			ic.custom_minimum_size = Vector2(30, 30)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(ic)
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
			_rowboxes.append(row); _labels.append(lbl); _icons.append(ic); _crafts.append(cb); _equips.append(eb)
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
			_icons[i].texture = ArtIcons.texture("item_" + String(rw.get("id", "")))
			_icons[i].modulate = Tokens.DIMMED if (locked or not (bool(rw.get("owned", false)) or bool(rw.get("affordable", false)))) else Tokens.WHITE
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
	# 2026-11 independent read (gamedev §5): unlabelled ✖/🗑 read as destructive, −/+ as speed. Zoom left
	# the strip (pinch + the action button's vertical swipe do it), ✖ shows only while a tool is armed,
	# and the remove tool says what it does in words.
	# C4 (2026-11-09): ☰ і ♻ Розібрати переїхали в нижню смугу TouchControls; у верхній лишився лише контекстний ✖.
	const TOOLS := [["✖", &"cancel_tool", "Скасувати інструмент"]]
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
			_tools[0].visible = bool(ui.get("armed", false))   # nothing armed → nothing to cancel → no ✖

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
		# objective CHIP: one line (title · n/N); the how-to lives in the tooltip and the pulsing build slot
		_count.visible = false
		_hint.visible = String(cur.get("id", "")) == "fire"
		if _hint.visible:   # chip-sized: лише перші два речення (повний текст — у тултіпі нижче), щоб панель не лізла на джойстик
			var sents: PackedStringArray = _hint.text.split(". ")
			if sents.size() > 2:
				_hint.text = ". ".join(sents.slice(0, 2)) + "."
			tooltip_text = ""   # T-Ніколая 2026-11-09 (far.png №1): першу ціль не ховаємо в тултіп — на телефоні його нема; решту цілей навчив перший
		var nxt := String(g.get("next", ""))
		# the chip shows THIS goal's own progress; the chain step lives in the tooltip — «5/10» beside
		# «Розпали багаття» read as «5 of 10 logs» in the first independent read (gamedev §5)
		var tip: String = "Крок %d з %d · %s" % [int(g.get("done", 0)) + 1, int(g.get("total", 0)), (Fmt.touchify(String(cur.get("hint", ""))) if touch else String(cur.get("hint", "")))]
		if nxt != "":
			tip += "\nДалі: " + nxt
		tooltip_text = tip
		_title.tooltip_text = tip
		_title.mouse_filter = Control.MOUSE_FILTER_PASS
		var pct: int = int(round(float(cur.get("pct", 0.0)) * 100.0))
		_bar.visible = false   # no progress bar (HUD diet): progress rides the title as a number when it means something
		if pct > 0 and pct < 100:
			_title.text += "  ·  %d%%" % pct
		_next.text = ("далі: " + nxt) if nxt != "" else ""
		_next.visible = false
