# RealWorld — ui/world_panels.gd : logistics / capsule / social / help dock panels (spec 0005 §2.6).
#
# Parity port of the main.gd monolith's world panels into the registry architecture. Every panel
# `extends PanelBase.Base`, creates its children ONCE in _build() (R2 fixed pools — bind() only hides
# or retexts pool slots, never rebuilds), colors only through Tokens consts (R3), reads only the vm
# slice handed to bind() (R10), and emits intents instead of calling the sim (R9).
extends RefCounted

const PanelBase = preload("res://scripts/ui/panel.gd")
const Widgets = preload("res://scripts/ui/widgets.gd")
const Tokens = preload("res://scripts/ui/tokens.gd")
const LatLon = preload("res://scripts/ui/latlon.gd")
const UITheme = preload("res://scripts/ui/theme.gd")
const Fmt = preload("res://scripts/ui/format.gd")

# ---- LogisticsPanel (RIGHT dock, M) — trade hubs + convoys in flight, reading vm.logistics ----
class LogisticsPanel extends PanelBase.Base:
	const HUB_MAX := 5   # 5 найближчих хабів на регіон (контент-пак)
	const CONVOY_MAX := 4
	var _hub_rows: Array = []       # VBox per hub slot (info Label + send Button), built ONCE (R2)
	var _hub_labels: Array = []
	var _hub_buttons: Array = []
	var _hub_args: Array = []       # per-slot intent args refreshed in bind; read by the ONE-time handler
	var _convoy_labels: Array = []
	func _init() -> void:
		panel_id = &"logistics_bay"; dock = PanelBase.DOCK_RIGHT; priority = 60; hotkey = KEY_M; default_open = false
		menu_label = "🚚 Логістика"; compact_open = 0
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Логістика", "hub")
		for i in HUB_MAX:
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 2)
			vb.add_child(row)
			var lbl := Label.new()
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(lbl)
			var btn := Button.new()
			btn.text = "🚚 Відправити 10"
			btn.pressed.connect(_on_send.bind(i))
			row.add_child(btn)
			_hub_rows.append(row); _hub_labels.append(lbl); _hub_buttons.append(btn)
			_hub_args.append({})
		var h2 := Widgets.H2Header.new()
		vb.add_child(h2); h2.set_header("Конвої", "")
		for i in CONVOY_MAX:
			var c := Label.new()
			c.add_theme_color_override("font_color", Tokens.MUT)
			vb.add_child(c)
			_convoy_labels.append(c)
	func _on_send(slot: int) -> void:
		var a: Dictionary = _hub_args[slot]
		if a.is_empty():
			return
		emit_intent(&"send_convoy", {"hub": int(a.hub), "res": String(a.res), "amt": 10})
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("logistics"):
			return
		var lg: Dictionary = vm.logistics
		var hubs: Array = lg.get("hubs", [])
		for i in HUB_MAX:
			if i < hubs.size():
				var h: Dictionary = hubs[i]
				var have: int = int(h.get("have", 0))
				_hub_rows[i].visible = true
				_hub_labels[i].text = "%s · %d км\nкупує %s%s → дає %s (курс %d:1) · маєш %d" % [
					String(h.get("name", "?")), int(h.get("dist_km", 0)),
					String(h.get("buys_icon", "")), String(h.get("buys", "")),
					String(h.get("sells_icon", "")) + String(h.get("sells", "")),
					int(h.get("rate", 1)), have]
				_hub_buttons[i].disabled = have < 10
				_hub_buttons[i].modulate = Tokens.DIMMED if have < 10 else Tokens.WHITE
				_hub_args[i] = {"hub": int(h.get("index", i)), "res": String(h.get("buys", ""))}
			else:
				_hub_rows[i].visible = false      # hidden POOL SLOT — the pool itself is never rebuilt (R2)
				_hub_args[i] = {}
		var convoys: Array = lg.get("convoys", [])
		for i in CONVOY_MAX:
			if i < convoys.size():
				var c: Dictionary = convoys[i]
				var ambushed := bool(c.get("ambushed", false))
				var back: bool = String(c.get("phase", "out")) == "back"
				var phase_txt: String = "назад" if back else "туди"
				if back:
					phase_txt += " +%d %s" % [int(c.get("recv_amt", 0)), String(c.get("recv_icon", ""))]
				var txt := "🚚 #%d → %s · %d%% · %s" % [
					int(c.get("id", 0)), String(c.get("hub", "?")), int(c.get("pct", 0)), phase_txt]
				if ambushed:
					txt += " ⚔ засідка"
				_convoy_labels[i].text = txt
				_convoy_labels[i].add_theme_color_override("font_color", Tokens.WARN if ambushed else Tokens.MUT)
				_convoy_labels[i].visible = true
			else:
				_convoy_labels[i].visible = false

# ---- CapsulePanel (RIGHT dock, V) — charges/radius, coordinate launch, invite list (vm.capsule) ----
class CapsulePanel extends PanelBase.Base:
	const INVITE_MAX := 4
	var _status: Label
	var _status_base := ""          # bind()-refreshed base line; the parse msg is appended after it
	var _lat_edit: LineEdit
	var _lon_edit: LineEdit
	var _launch: Button
	var _invite_rows: Array = []
	var _invite_labels: Array = []
	var _invite_buttons: Array = []
	var _invite_ids: Array = []     # per-slot invite id refreshed in bind; read by the ONE-time handler
	# --- Основна капсула (spec 0010, режим ON): один пул вузлів, збудований РАЗОМ з легасі-рядками (R2), показується лише при vm.capsule.main ---
	const STORE_MAX := 6
	var _coords: HBoxContainer
	var _inv_head: Widgets.H2Header
	var _m_nodes: Array = []        # усі вузли ON-режиму (bind перемикає їх разом із легасі-вузлами — одне місце правди про режим)
	var _m_levels: Label
	var _m_immune: Label
	var _m_raid: Label
	var _m_up: Button
	var _m_up_cost: Label
	var _m_up_why: Label
	var _m_more: Button
	var _m_more_box: VBoxContainer
	var _m_more_open := false       # view-стан розкриття (D1): за замовчуванням згорнуто
	var _m_prot: Button
	var _m_prot_cost: Label
	var _m_prot_why: Label
	var _m_stash: Button
	var _m_store_rows: Array = []
	var _m_store_labels: Array = []
	var _m_store_res: Array = []    # per-slot res id refreshed in bind; read by the ONE-time handler
	func _init() -> void:
		panel_id = &"capsule_bay"; dock = PanelBase.DOCK_RIGHT; priority = 70; hotkey = KEY_V; default_open = false
		menu_label = "🚀 Капсула"; compact_open = 0
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Капсула", "pod")
		_status = Label.new()
		_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(_status)
		_build_main(vb)
		var coords := HBoxContainer.new()
		_coords = coords
		coords.add_theme_constant_override("separation", 6)
		vb.add_child(coords)
		_lat_edit = LineEdit.new()
		_lat_edit.placeholder_text = "широта (lat)"
		_lat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		coords.add_child(_lat_edit)
		_lon_edit = LineEdit.new()
		_lon_edit.placeholder_text = "довгота (lon)"
		_lon_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		coords.add_child(_lon_edit)
		_launch = Button.new()
		_launch.text = "🚀 Запуск за координатами"
		_launch.pressed.connect(_on_launch)
		vb.add_child(_launch)
		var h2 := Widgets.H2Header.new()
		_inv_head = h2
		vb.add_child(h2); h2.set_header("Інвайти", "")
		for i in INVITE_MAX:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			vb.add_child(row)
			var lbl := Label.new()
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_color_override("font_color", Tokens.MUT)
			row.add_child(lbl)
			var btn := Button.new()
			btn.text = "Прийняти"
			btn.pressed.connect(_on_take.bind(i))
			row.add_child(btn)
			_invite_rows.append(row); _invite_labels.append(lbl); _invite_buttons.append(btn)
			_invite_ids.append(null)
	# ON-режим: ОДНА головна залита дія «Прокачати»; «Захист» і «Склад» — під розкриттям «Ще» (REQ-0010-86, D1). Жодних нових H2-заголовків.
	func _build_main(vb: VBoxContainer) -> void:
		_m_levels = _m_label(vb, Tokens.INK)
		_m_immune = _m_label(vb, Tokens.TEAL)
		_m_raid = _m_label(vb, Tokens.WARN)
		_m_up = _m_button(vb, 44)
		_m_up.theme_type_variation = UITheme.V_PRIMARY   # єдина залита кнопка панелі
		_m_up.pressed.connect(func() -> void: emit_intent(&"capsule_upgrade", {}))
		_m_up_cost = _m_label(vb, Tokens.MUT)
		_m_up_why = _m_label(vb, Tokens.WARN)
		_m_more = _m_button(vb, 36)
		_m_more.flat = true
		_m_more.alignment = HORIZONTAL_ALIGNMENT_LEFT   # the phone's action circle sits over the dock's bottom-right: keep the label clear of it
		_m_more.pressed.connect(_on_more)
		_m_more_box = VBoxContainer.new()
		_m_more_box.add_theme_constant_override("separation", 4)
		_m_more_box.visible = false
		vb.add_child(_m_more_box)
		_m_nodes.append(_m_more_box)
		_m_prot = _m_button(_m_more_box, 40)
		_m_prot.pressed.connect(func() -> void: emit_intent(&"capsule_protect", {}))
		_m_prot_cost = _m_label(_m_more_box, Tokens.MUT)
		_m_prot_why = _m_label(_m_more_box, Tokens.WARN)
		_m_stash = _m_button(_m_more_box, 40)
		_m_stash.text = "⇣ Скласти рюкзак на склад"
		_m_stash.pressed.connect(func() -> void: emit_intent(&"stash_all", {}))
		for i in STORE_MAX:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			row.visible = false
			_m_more_box.add_child(row)
			var lbl := Label.new()
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_color_override("font_color", Tokens.MUT)
			row.add_child(lbl)
			var btn := Button.new()
			btn.text = "Взяти 10"
			btn.focus_mode = Control.FOCUS_NONE
			btn.custom_minimum_size = Vector2(96, 34)
			btn.pressed.connect(_on_store.bind(i))
			row.add_child(btn)
			_m_store_rows.append(row); _m_store_labels.append(lbl); _m_store_res.append("")
	func _m_label(parent: Node, col: Color) -> Label:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", col)
		l.visible = false
		parent.add_child(l)
		_m_nodes.append(l)
		return l
	func _m_button(parent: Node, h: int) -> Button:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, h)
		b.visible = false
		parent.add_child(b)
		_m_nodes.append(b)
		return b
	func _on_more() -> void:
		_m_more_open = not _m_more_open
		_m_more_box.visible = _m_more_open
		_m_more.text = ("▾ " if _m_more_open else "▸ ") + "Ще: захист і склад"
	func _on_store(slot: int) -> void:
		if String(_m_store_res[slot]) != "":
			emit_intent(&"take_storage", {"res": String(_m_store_res[slot]), "n": 10})
	func _bind_main(main: Dictionary) -> void:
		var acts: Array = main.get("actions", [])
		_m_levels.visible = true
		_m_levels.text = "◎ Рівень %d/%d · 🛡 Захист %d/%d" % [int(main.level), int(main.max), int(main.protection), int(main.max_protection)]
		var left: int = int(main.get("immune_left_ms", 0))
		_m_immune.visible = left > 0
		_m_immune.text = "🛡 Імунітет: ще %s" % Fmt.left_ms(left)
		var rs: StringName = StringName(main.get("raid_state", &"none"))
		_m_raid.visible = rs == &"warning" or rs == &"contact"
		_m_raid.text = "⚠ Рейд на підході" if rs == &"warning" else "⚔ Рейд: бій за ядро"
		_axis_rows(acts.has(&"upgrade"), main.get("upgrade", {}), _m_up, _m_up_cost, _m_up_why, "⬆ Прокачати → рівень %d")
		_axis_rows(acts.has(&"protection"), main.get("protect", {}), _m_prot, _m_prot_cost, _m_prot_why, "🛡 Захист → рівень %d")
		_m_more.visible = true
		_m_more_box.visible = _m_more_open
		_m_more.text = ("▾ " if _m_more_open else "▸ ") + "Ще: захист і склад"
		_m_stash.visible = acts.has(&"storage")
		var st: Array = main.get("storage", []) if acts.has(&"storage") else []
		for i in STORE_MAX:
			if i < st.size():
				_m_store_rows[i].visible = true
				_m_store_labels[i].text = "%s  %d" % [String(st[i].label), int(st[i].n)]
				_m_store_res[i] = String(st[i].res)
			else:
				_m_store_rows[i].visible = false   # hidden POOL SLOT (R2)
				_m_store_res[i] = ""
	# «Прокачати»/«Захист»: кнопка лише коли дія доступна за станом (жодних недоступних дій); без ресурсів — приглушена, АЛЕ тапається:
	# відмова — та сама перша причина словами (REQ-0010-38), і в панелі, і над героєм.
	func _axis_rows(offered: bool, ax: Dictionary, btn: Button, cost: Label, why: Label, fmt: String) -> void:
		btn.visible = offered
		cost.visible = offered
		why.visible = offered and not bool(ax.get("can", false))
		if not offered:
			return
		var can: bool = bool(ax.get("can", false))
		btn.text = fmt % int(ax.get("next", 0))
		btn.modulate = Tokens.WHITE if can else Tokens.DIMMED
		cost.visible = can   # one line at a time (phone height): the price while affordable, the first missing resource when not
		cost.text = "Ціна: " + String(ax.get("cost", ""))
		why.text = String(ax.get("why", ""))
	func _set_legacy(on: bool) -> void:
		_status.visible = on
		_coords.visible = on
		_launch.visible = on
		_inv_head.visible = on
		if not on:
			for i in INVITE_MAX:
				_invite_rows[i].visible = false
	func _on_launch() -> void:
		# Parsing lives HERE (the click), never in bind().
		var parsed: Dictionary = LatLon.parse(_lat_edit.text, _lon_edit.text)
		if bool(parsed.get("ok", false)):
			emit_intent(&"launch_capsule", {"lat": float(parsed.lat), "lon": float(parsed.lon), "name": "Свої координати"})
		else:
			_status.text = _status_base + "\n⚠ " + String(parsed.get("msg", ""))
	func _on_take(slot: int) -> void:
		if _invite_ids[slot] == null:
			return
		emit_intent(&"take_invite", {"id": _invite_ids[slot]})
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("capsule"):
			return
		var cap: Dictionary = vm.capsule
		if cap.has("main"):   # ON: заряди/радіус/запуск/інвайти не показуються (REQ-0010-41), лишається панель капсули
			_set_legacy(false)
			_bind_main(cap.main)
			return
		if not _status.visible:   # легасі-вузли сховано == панель була в ON; перемикання ON -> OFF (на практиці прапор замкнений; свідомо чесно)
			_set_legacy(true)
			for n in _m_nodes:
				n.visible = false
		var charges: int = int(cap.get("charges", 0))
		var drained := charges <= 0
		_status_base = "Зарядів: %d · радіус %d км" % [charges, int(cap.get("radius_km", 0))]
		_status.text = _status_base
		_launch.disabled = drained
		_launch.modulate = Tokens.DIMMED if drained else Tokens.WHITE
		var invites: Array = cap.get("invites", [])
		for i in INVITE_MAX:
			if i < invites.size():
				var inv: Dictionary = invites[i]
				_invite_rows[i].visible = true
				_invite_labels[i].text = "✉ %s (%s) → %s" % [
					String(inv.get("inviter", "?")), String(inv.get("clan", "—")), String(inv.get("name", "?"))]
				_invite_buttons[i].disabled = drained
				_invite_buttons[i].modulate = Tokens.DIMMED if drained else Tokens.WHITE
				_invite_ids[i] = inv.get("id")
			else:
				_invite_rows[i].visible = false   # hidden POOL SLOT (R2)
				_invite_ids[i] = null

# ---- SocialPanel (RIGHT dock, O) — clan/alliance/empire web + nearby friends (vm.social_info) ----
class SocialPanel extends PanelBase.Base:
	const FRIEND_MAX := 4
	var _info: Array = []           # 5 Labels: clan / alliance / empire / hostiles / pressure
	var _friends_head: Widgets.H2Header
	var _friend_rows: Array = []
	var _friend_labels: Array = []
	var _friend_buttons: Array = []
	var _friend_args: Array = []    # per-slot fly-intent args refreshed in bind
	func _init() -> void:
		panel_id = &"social_web"; dock = PanelBase.DOCK_RIGHT; priority = 80; hotkey = KEY_O; default_open = false
		menu_label = "🛡 Соціальне"; compact_open = 0
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Соціальне", "web")
		for i in 5:
			var lbl := Label.new()
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.add_theme_color_override("font_color", Tokens.MUT)
			vb.add_child(lbl)
			_info.append(lbl)
		_friends_head = Widgets.H2Header.new()
		vb.add_child(_friends_head); _friends_head.set_header("Друзі поруч", "")
		for i in FRIEND_MAX:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			vb.add_child(row)
			var lbl := Label.new()
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_color_override("font_color", Tokens.MUT)
			row.add_child(lbl)
			var btn := Button.new()
			btn.text = "🚀 Летіти"
			btn.pressed.connect(_on_fly.bind(i))
			row.add_child(btn)
			_friend_rows.append(row); _friend_labels.append(lbl); _friend_buttons.append(btn)
			_friend_args.append({})
	func _on_fly(slot: int) -> void:
		var a: Dictionary = _friend_args[slot]
		if a.is_empty():
			return
		emit_intent(&"launch_capsule", {"lat": float(a.lat), "lon": float(a.lon), "name": String(a.name)})
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary) or not vm.has("social_info"):
			return
		var so: Dictionary = vm.social_info
		if not bool(so.get("available", false)):
			_info[0].visible = true
			_info[0].text = "— поза мережею —"
			for i in range(1, 5):
				_info[i].visible = false
			_friends_head.visible = false
			for i in FRIEND_MAX:
				_friend_rows[i].visible = false
				_friend_args[i] = {}
			return
		for i in 5:
			_info[i].visible = true
		_friends_head.visible = true
		_info[0].text = "🛡 клан: %s · %d осіб" % [String(so.get("clan", "—")), int(so.get("members", 0))]
		_info[1].text = "🤝 альянс: %s" % String(so.get("alliance", "—"))
		_info[2].text = "👑 імперія: %s" % String(so.get("empire", "—"))
		var hostiles: Array = so.get("hostiles", [])
		_info[3].text = "⚔ вороги: %s" % (", ".join(hostiles) if hostiles.size() > 0 else "—")
		var pressure: float = float(so.get("pressure", 1.0))
		_info[4].text = "рейд-тиск ×%.1f" % pressure
		_info[4].add_theme_color_override("font_color", Tokens.WARN if pressure > 1.0 else Tokens.MUT)
		var friends: Array = so.get("friends", [])
		for i in FRIEND_MAX:
			if i < friends.size():
				var f: Dictionary = friends[i]
				_friend_rows[i].visible = true
				_friend_labels[i].text = "🧍 %s · %s · %d км" % [
					String(f.get("name", "?")), String(f.get("clan_name", "—")), int(f.get("dist_km", 0))]
				_friend_args[i] = {"lat": float(f.get("lat", 0.0)), "lon": float(f.get("lon", 0.0)), "name": String(f.get("place", ""))}
			else:
				_friend_rows[i].visible = false   # hidden POOL SLOT (R2)
				_friend_args[i] = {}

# ---- HelpPanel (RIGHT dock, H) — the static controls sheet; bind() has nothing to mutate ----
class HelpPanel extends PanelBase.Base:
	const CONTROLS := "ЛКМ — іти/добувати/атакувати\nнаведи курсор — що це і що зробить клік\nПКМ — розібрати будівлю (½ ціни назад)\nколесо — зум · WASD — рух\n1–0 — будувати · затисни ЛКМ — ряд стін\nEsc — скасувати · J — цілі\nSpace — пауза · +/− — швидкість\nL — світло (де темно працювати)\nT — тепло (де холодно/комфорт)\nB/C/N — каталог · U — техно · Y — ери\nI — спорядження · E — енергія · M — логістика\nV — капсула · O — соціальне · H — довідка\nГра зберігається сама: «Продовжити» на старті"   # gdlint: ignore=max-line-length
	const TOUCH_CONTROLS := "Тап — іти / добувати / атакувати / будувати\nутримай палець — що це (підказка)\nдва пальці — зум (або − / + угорі)\nвибери будівлю внизу й веди пальцем — ряд\n✖ — скасувати · 🗑 — розібрати (½ ціни)\n⏸ ×1 ×2 ×3 — час · ☰ — панелі й оверлеї\n«Назад» — закрити меню / інструмент\nГра зберігається сама: «Продовжити» на старті"   # gdlint: ignore=max-line-length
	var _body: Label
	var _touch := false
	func _init() -> void:
		panel_id = &"help"; dock = PanelBase.DOCK_RIGHT; priority = 90; hotkey = KEY_H; default_open = false
		menu_label = "❔ Довідка"; compact_open = 0
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Довідка", "key")
		_body = Label.new()
		_body.text = CONTROLS
		_body.add_theme_color_override("font_color", Tokens.MUT)
		vb.add_child(_body)
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		var touch: bool = vm is Dictionary and bool((vm.get("ui", {}) as Dictionary).get("touch", false))
		if touch != _touch:
			_touch = touch
			_body.text = TOUCH_CONTROLS if touch else CONTROLS
