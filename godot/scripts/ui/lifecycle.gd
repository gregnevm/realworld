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
const ArtIcons = preload("res://scripts/ui/art_icons.gd")

# --- shared chrome helpers -------------------------------------------------------------------------
class Chrome extends RefCounted:
	# Key-art backdrop that breathes: cover-fit texture + a very slow zoom/pan loop (≈26 s) so a menu is never
	# a still image. View-only; ends with the node (tween is bound to it).
	static func add_backdrop(host: Control, key_id: String) -> TextureRect:
		var tex: Texture2D = ArtIcons.key(key_id)
		if tex == null:
			return null
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.resized.connect(func() -> void: tr.pivot_offset = tr.size * 0.5)
		host.add_child(tr)
		tr.scale = Vector2(1.08, 1.08)
		var tw := tr.create_tween().set_loops()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(tr, "scale", Vector2(1.0, 1.0), 13.0)
		tw.tween_property(tr, "scale", Vector2(1.08, 1.08), 13.0)
		return tr

	# Horizontal/vertical scrim from solid ground colour to clear: keeps text readable over art.
	static func add_scrim(host: Control, from_alpha: float, vertical: bool = false) -> void:
		var g := Gradient.new()
		g.set_color(0, Tokens.with_alpha(Tokens.BG, from_alpha))
		g.set_color(1, Tokens.with_alpha(Tokens.BG, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1) if vertical else Vector2(0.75, 0)
		var r := TextureRect.new()
		r.texture = gt
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		host.add_child(r)

	# Staggered arrival: each child fades in and rises 14 px, 70 ms apart (ease-out cubic, 0.45 s).
	static func stagger_in(items: Array) -> void:
		var i := 0
		for it in items:
			var c: Control = it
			c.modulate = Tokens.with_alpha(Tokens.WHITE, 0.0)
			var tw := c.create_tween()
			tw.tween_interval(0.07 * i)
			tw.tween_property(c, "modulate", Tokens.WHITE, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			i += 1

	# Hover/press pop shared by every menu button (the build bar uses the same feel).
	static func pop_button(btn: Button) -> void:
		btn.resized.connect(func() -> void: btn.pivot_offset = btn.size * 0.5)
		btn.mouse_entered.connect(func() -> void: _pop(btn, 1.03, 0.10))
		btn.mouse_exited.connect(func() -> void: _pop(btn, 1.0, 0.12))
		btn.button_down.connect(func() -> void: _pop(btn, 0.97, 0.06))
		btn.button_up.connect(func() -> void: _pop(btn, 1.03, 0.08))

	static func _pop(btn: Button, to: float, dur: float) -> void:
		if not btn.is_inside_tree():
			return
		btn.create_tween().tween_property(btn, "scale", Vector2(to, to), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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
		Chrome.add_backdrop(self, "key_spawn")        # generated key art (falls back to the flat ground colour)
		Chrome.add_scrim(self, 0.94)                  # left-to-right: solid under the text, clear over the art
		Chrome.add_scrim(self, 0.55, true)            # top fade keeps the title crisp
		var scroll := ScrollContainer.new()
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(scroll)
		var margin := MarginContainer.new()
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin.add_theme_constant_override("margin_left", 56)
		margin.add_theme_constant_override("margin_top", 24)
		margin.add_theme_constant_override("margin_bottom", 28)
		margin.add_theme_constant_override("margin_right", 24)
		scroll.add_child(margin)
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(500, 0)
		box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN     # the column hugs the LEFT; the art owns the right
		box.add_theme_constant_override("separation", 6)
		margin.add_child(box)
		var arrivals: Array = []

		var title := Label.new()
		title.text = "RealWorld"
		title.add_theme_font_size_override("font_size", 56)
		title.add_theme_color_override("font_color", Tokens.INK)
		box.add_child(title)
		arrivals.append(title)
		var kicker := Label.new()
		kicker.text = "СУРВАЙВАЛ · РЕАЛЬНА ГЕОГРАФІЯ · ПІСЛЯ КОЛАПСУ"
		kicker.add_theme_font_size_override("font_size", 13)
		kicker.add_theme_color_override("font_color", Tokens.AMBER)
		box.add_child(kicker)
		arrivals.append(kicker)
		var sub := Label.new()
		sub.text = "Машини, що керували світом, повстали. Їхні патрульні роботи досі ходять руїнами. Ти — один виживальник на справжній карті Землі."   # gdlint: ignore=max-line-length
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.add_theme_color_override("font_color", Tokens.MUT)
		box.add_child(sub)
		arrivals.append(sub)

		if not continue_meta.is_empty():
			var cont := Button.new()
			cont.text = "▶  Продовжити: %s · день %d%s" % [String(continue_meta.get("place", "")),
				int(continue_meta.get("day", 1)), " (☠ пішак загинув)" if bool(continue_meta.get("dead", false)) else ""]
			cont.custom_minimum_size = Vector2(0, 56)
			cont.add_theme_font_size_override("font_size", 18)
			cont.pressed.connect(func() -> void: continue_chosen.emit())
			Chrome.pop_button(cont)
			box.add_child(cont)
			arrivals.append(cont)
			var warn := Label.new()
			warn.text = "Нова висадка нижче почне інший світ і перезапише це збереження."
			warn.add_theme_font_size_override("font_size", 12)
			warn.add_theme_color_override("font_color", Tokens.MUT)
			box.add_child(warn)

		var h1 := _section("Обери точку висадки")
		box.add_child(h1)
		arrivals.append(h1)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		box.add_child(grid)
		for pr in GameData.SPAWN_PRESETS:
			var btn := Button.new()
			btn.text = "%s\n(%.2f, %.2f) · seed %s" % [String(pr.name), float(pr.lat), float(pr.lon),
				Fmt.seed_hex(WorldGen.hash_seed(float(pr.lat), float(pr.lon)))]
			btn.custom_minimum_size = Vector2(246, 60)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(_choose.bind(float(pr.lat), float(pr.lon), String(pr.name)))
			Chrome.pop_button(btn)
			grid.add_child(btn)
			arrivals.append(btn)
		var note := Label.new()
		note.text = "🌍 Координати — це seed: ті самі координати завжди дають той самий світ. Це адреса, якою ділишся з друзями."   # gdlint: ignore=max-line-length
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", Tokens.GOOD)
		box.add_child(note)

		var h2 := _section("Свої координати")
		box.add_child(h2)
		arrivals.append(h2)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_lat_edit = LineEdit.new()
		_lat_edit.placeholder_text = "широта (lat)"
		_lat_edit.custom_minimum_size = Vector2(150, 40)
		_lon_edit = LineEdit.new()
		_lon_edit.placeholder_text = "довгота (lon)"
		_lon_edit.custom_minimum_size = Vector2(150, 40)
		row.add_child(_lat_edit)
		row.add_child(_lon_edit)
		box.add_child(row)
		arrivals.append(row)
		var btns := HBoxContainer.new()
		btns.add_theme_constant_override("separation", 8)
		var gps := Button.new()
		gps.text = "📍 Моя GPS-локація"
		gps.custom_minimum_size = Vector2(0, 44)
		gps.pressed.connect(_use_real_gps)
		Chrome.pop_button(gps)
		btns.add_child(gps)
		var go := Button.new()
		go.text = "🛬 Висадка за координатами"
		go.custom_minimum_size = Vector2(0, 44)
		go.pressed.connect(_start_from_coords)
		Chrome.pop_button(go)
		btns.add_child(go)
		box.add_child(btns)
		arrivals.append(btns)

		var demo := Button.new()
		demo.text = "✉ Висадка до друга (демо-інвайт): Бровари"
		demo.custom_minimum_size = Vector2(0, 40)
		demo.alignment = HORIZONTAL_ALIGNMENT_LEFT
		demo.pressed.connect(_choose.bind(50.5109, 30.7909, "Інвайт: Бровари"))
		Chrome.pop_button(demo)
		box.add_child(demo)
		arrivals.append(demo)

		var hint := Label.new()
		hint.text = "ЛКМ — іти/добувати · колесо — зум · WASD · 1–0 будувати (затисни — ряд) · Space пауза · J цілі · H довідка"   # gdlint: ignore=max-line-length
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Tokens.MUT)
		box.add_child(hint)

		_status = Label.new()
		_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_status.add_theme_color_override("font_color", Tokens.WARN)
		box.add_child(_status)
		Chrome.stagger_in(arrivals)

	func _fit_viewport() -> void:
		WidgetBase.Widget.fit_viewport(self)

	func _section(t: String) -> Label:
		var l := Label.new()
		l.text = t.to_upper()
		l.add_theme_font_size_override("font_size", 13)
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
		bg.color = Tokens.BG
		bg.mouse_filter = Control.MOUSE_FILTER_STOP   # блокує кліки по світу під екраном смерті
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		Chrome.add_backdrop(self, "key_death")
		var tint := ColorRect.new()                    # cold blood-tinted veil over the art: «this is the end of a life»
		tint.color = Tokens.with_alpha(Tokens.BLOOD, 0.28)
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tint.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(tint)
		Chrome.add_scrim(self, 0.75, true)
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
		Chrome.pop_button(b)
		vb.add_child(b)
		# slow, heavy arrival: the screen fades up over 1.2 s, the title lands last-first (silence before the words)
		modulate = Tokens.with_alpha(Tokens.WHITE, 0.0)
		create_tween().tween_property(self, "modulate", Tokens.WHITE, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	func _fit_viewport() -> void:
		WidgetBase.Widget.fit_viewport(self)
