# RealWorld — ui/lifecycle.gd : app-lifecycle screens (spawn + death) for the new HUD (spec 0005).
#
# NOT dock panels — these are full-screen chrome the ENTRY SCENE mounts around the HUD: the spawn
# screen picks the world address (координати — це seed) and the death screen closes the permadeath
# loop. Both are build-once Controls that only EMIT signals — the entry scene turns them into session
# calls / router verbs (R9: no sim mutator is named here). Styling goes through Tokens/Theme only (R3).
extends RefCounted

const Tokens = preload("res://scripts/ui/tokens.gd")
const LatLon = preload("res://scripts/ui/latlon.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const WidgetBase = preload("res://scripts/ui/widget.gd")
const Fmt = preload("res://scripts/ui/format.gd")
const GameData = preload("res://scripts/data.gd")

# --- spawn: the world-address picker -----------------------------------------------------------
class SpawnScreen extends Control:
	signal spawn_chosen(lat: float, lon: float, place_name: String)
	signal continue_chosen

	# {place, day, dead} of a save on disk (set by the entry scene BEFORE the screen enters the tree);
	# non-empty -> a «▶ Продовжити» button heads the screen. Empty -> the screen is unchanged.
	var continue_meta: Dictionary = {}
	var _lat_edit: LineEdit
	var _lon_edit: LineEdit
	var _status: Label

	func _ready() -> void:
		# hud_root gotcha: під CanvasLayer Control НЕ успадковує розмір в'юпорта — FULL_RECT колапсує
		# в нуль; пінимось у TOP_LEFT і розміряємось явно (re-fit на resize)
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		_fit_viewport()
		get_viewport().size_changed.connect(_fit_viewport)
		var bg := ColorRect.new()
		bg.color = Tokens.BG
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		var scroll := ScrollContainer.new()
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(scroll)
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		# a ScrollContainer only widens a child that asks to EXPAND — without it the column hugged
		# the left edge instead of centering
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.add_child(center)
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(460, 0)
		box.add_theme_constant_override("separation", 6)
		center.add_child(box)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(0, 8)
		box.add_child(pad)

		var title := Label.new()
		title.text = "RealWorld"
		title.add_theme_font_size_override("font_size", 36)
		title.add_theme_color_override("font_color", Tokens.ACCENT)
		box.add_child(title)
		var sub := Label.new()
		sub.text = "Survival-MMORPG на справжній географії після Колапсу. Руїни Старого світу досі обходять патрульні роботи. Обери точку висадки:"   # gdlint: ignore=max-line-length
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(sub)
		var note := Label.new()
		note.text = "🌍 Координати — це seed світу: ті самі координати завжди дають той самий світ, для кожного гравця. Координати — це адреса, якою ділишся з друзями."   # gdlint: ignore=max-line-length
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 13)
		note.add_theme_color_override("font_color", Tokens.GOOD)
		box.add_child(note)

		if not continue_meta.is_empty():
			var cont := Button.new()
			cont.text = "▶  Продовжити: %s · день %d%s" % [String(continue_meta.get("place", "")),
				int(continue_meta.get("day", 1)), " (☠ пішак загинув)" if bool(continue_meta.get("dead", false)) else ""]
			cont.custom_minimum_size = Vector2(0, 44)
			cont.add_theme_font_size_override("font_size", 17)
			cont.pressed.connect(func() -> void: continue_chosen.emit())
			box.add_child(cont)
			var warn := Label.new()
			warn.text = "Нова висадка нижче почне інший світ і перезапише це збереження."
			warn.add_theme_font_size_override("font_size", 12)
			warn.add_theme_color_override("font_color", Tokens.MUT)
			box.add_child(warn)

		box.add_child(_section("Пресети"))
		for pr in GameData.SPAWN_PRESETS:
			var btn := Button.new()
			btn.text = "%s · seed %s" % [Fmt.region_line(String(pr.name), float(pr.lat), float(pr.lon)),
				Fmt.seed_hex(WorldGen.hash_seed(float(pr.lat), float(pr.lon)))]
			btn.pressed.connect(_choose.bind(float(pr.lat), float(pr.lon), String(pr.name)))
			box.add_child(btn)

		box.add_child(_section("Real-GPS / свої координати"))
		var row := HBoxContainer.new()
		_lat_edit = LineEdit.new()
		_lat_edit.placeholder_text = "широта (lat)"
		_lat_edit.custom_minimum_size = Vector2(150, 0)
		_lon_edit = LineEdit.new()
		_lon_edit.placeholder_text = "довгота (lon)"
		_lon_edit.custom_minimum_size = Vector2(150, 0)
		row.add_child(_lat_edit)
		row.add_child(_lon_edit)
		box.add_child(row)
		var btns := HBoxContainer.new()
		var gps := Button.new()
		gps.text = "📍 Моя GPS-локація"
		gps.pressed.connect(_use_real_gps)
		btns.add_child(gps)
		var go := Button.new()
		go.text = "🛬 Висадка за координатами"
		go.pressed.connect(_start_from_coords)
		btns.add_child(go)
		box.add_child(btns)

		box.add_child(_section("Режим інвайта (висадка до друга)"))
		var demo := Button.new()
		demo.text = "✉ Демо-інвайт: Бровари (50.5109, 30.7909)"
		demo.pressed.connect(_choose.bind(50.5109, 30.7909, "Інвайт: Бровари"))
		box.add_child(demo)

		var hint := Label.new()
		hint.text = "Керування: ЛКМ — іти/добувати/атакувати · ПКМ — розібрати · колесо — зум · WASD · 1–0 будувати (затисни — ряд) · Space пауза · +/− швидкість · Esc скасувати · J — цілі · H — довідка"   # gdlint: ignore=max-line-length
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", Tokens.MUT)
		box.add_child(hint)

		_status = Label.new()
		_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_status.add_theme_color_override("font_color", Tokens.WARN)
		box.add_child(_status)

	func _fit_viewport() -> void:
		WidgetBase.Widget.fit_viewport(self)

	func _section(t: String) -> Label:
		var l := Label.new()
		l.text = "— " + t + " —"
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Tokens.WARN)
		return l

	func _choose(lat: float, lon: float, place_name: String) -> void:
		spawn_chosen.emit(lat, lon, place_name)

	func _start_from_coords() -> void:
		var c: Dictionary = LatLon.parse(_lat_edit.text, _lon_edit.text)
		if not bool(c.ok):
			_status.text = String(c.msg)
			return
		_choose(float(c.lat), float(c.lon), "Свої координати")

	func _use_real_gps() -> void:
		# Web export: browser geolocation. Elsewhere: manual entry is the universal fallback.
		if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
			_status.text = "Запит GPS у браузері… дозволь доступ і введи координати, якщо не спрацює."
			var js := "navigator.geolocation && navigator.geolocation.getCurrentPosition(function(p){window.__rw_lat=p.coords.latitude;window.__rw_lon=p.coords.longitude;});"
			JavaScriptBridge.eval(js, true)
			await get_tree().create_timer(1.5).timeout
			if not visible or not is_inside_tree():
				return   # поки чекали GPS, гравець уже висадився пресетом — пізній результат не має бутити другу сесію
			var lat: Variant = JavaScriptBridge.eval("window.__rw_lat", true)
			var lon: Variant = JavaScriptBridge.eval("window.__rw_lon", true)
			if lat != null and lon != null:
				_lat_edit.text = str(lat)
				_lon_edit.text = str(lon)
				_start_from_coords()
				return
		_status.text = "GPS доступний у веб-збірці. Введи координати вручну і тисни «Висадка»."

# --- death: the permadeath loop-closer ----------------------------------------------------------
class DeathScreen extends Control:
	signal respawn_chosen

	var _epitaph: Label
	var cause := ""

	# The death's value data (HudModel death slice): WHY and HOW LONG — a death you can read is a
	# lesson; a bare «ти загинув» after a silent freeze was the opening's worst moment.
	func bind(vm: Dictionary) -> void:
		if _epitaph == null:
			return
		cause = String(vm.get("cause", ""))
		var lived: int = int(vm.get("lived", 0))
		var lines: Array = []
		if cause != "":
			lines.append("Причина: %s." % cause)
		if lived > 0:
			lines.append("Прожито днів: %d (до дня %d)." % [lived, int(vm.get("day", 0))])
		lines.append(_lesson(cause))
		_epitaph.text = "\n".join(lines)

	static func _lesson(c: String) -> String:
		if "замерз" in c:
			return "Порада: багаття (9) + стіни (1) з дверима (2) навколо — у приміщенні тепло тримається."
		if "голод" in c:
			return "Порада: збирай ягоди з кущів і тримай їжу на складі — біля складу пішак їсть сам."
		if "тепловий" in c:
			return "Порада: у спеку ховайся в приміщенні, не стій біля вогню."
		if "кров" in c or "рани" in c:
			return "Порада: бийся біля турелей і шипів, а рани лікуй сном у ліжку."
		return "Порада: тримай тепло, їжу й сон — і будуй оборону до 5-го дня."

	func _ready() -> void:
		# та сама CanvasLayer-гоча, що й у SpawnScreen: явний розмір замість FULL_RECT
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		_fit_viewport()
		get_viewport().size_changed.connect(_fit_viewport)
		var bg := ColorRect.new()
		bg.color = Tokens.with_alpha(Tokens.BLOOD, 0.5)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP   # блокує кліки по світу під екраном смерті
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(center)
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 12)
		center.add_child(vb)
		var t := Label.new()
		t.text = "☠  ТИ ЗАГИНУВ"
		t.add_theme_font_size_override("font_size", 44)
		t.add_theme_color_override("font_color", Tokens.CRIT)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(t)
		var s := Label.new()
		s.text = "Одне життя, глибока симуляція. Героя й усе, що він ніс, втрачено.\nПоселення лишається: нова пішка прибуде туди — з нуля, без прокачки."   # gdlint: ignore=max-line-length
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.custom_minimum_size = Vector2(460, 0)
		vb.add_child(s)
		_epitaph = Label.new()
		_epitaph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_epitaph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_epitaph.custom_minimum_size = Vector2(460, 0)
		_epitaph.add_theme_color_override("font_color", Tokens.WARN)
		vb.add_child(_epitaph)
		var b := Button.new()
		b.text = "🧬  Респавн — нова пішка"
		b.custom_minimum_size = Vector2(260, 48)
		b.pressed.connect(func() -> void: respawn_chosen.emit())
		vb.add_child(b)

	func _fit_viewport() -> void:
		WidgetBase.Widget.fit_viewport(self)
