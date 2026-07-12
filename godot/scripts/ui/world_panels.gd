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
	func _init() -> void:
		panel_id = &"capsule_bay"; dock = PanelBase.DOCK_RIGHT; priority = 70; hotkey = KEY_V; default_open = false
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
		var coords := HBoxContainer.new()
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
	const CONTROLS := "ЛКМ — іти/добувати/атакувати\nПКМ — розібрати будівлю\nколесо — зум · WASD — рух\n1–0 — будувати · Esc — скасувати\nSpace — швидкість/пауза\nL — світло · T — температура\nB/C/N — каталог (демо) · U — техно · Y — ери\nI — спорядження · M — логістика\nV — капсула · O — соціальне · H — довідка"   # gdlint: ignore=max-line-length
	var _body: Label
	func _init() -> void:
		panel_id = &"help"; dock = PanelBase.DOCK_RIGHT; priority = 90; hotkey = KEY_H; default_open = false
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
	func bind(_vm) -> void:
		rebind_count += 1
		build_once()
