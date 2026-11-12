# RealWorld — ui/lifecycle.gd : app-lifecycle screens (spawn + death) for the new HUD (spec 0005).
#
# NOT dock panels — these are full-screen chrome the ENTRY SCENE mounts around the HUD: the spawn
# screen picks the world address (координати — це seed) and the death screen closes the permadeath
# loop. Both are build-once Controls that only EMIT signals — the entry scene turns them into session
# calls / router verbs (R9: no sim mutator is named here). Styling goes through Tokens/Theme only (R3).
extends RefCounted

const Settings = preload("res://scripts/settings.gd")
const Tokens = preload("res://scripts/ui/tokens.gd")
const UITheme = preload("res://scripts/ui/theme.gd")
const LatLon = preload("res://scripts/ui/latlon.gd")
const Location = preload("res://scripts/location.gd")   # spec 0012 §3.7: провайдер GPS і валідація
const WorldGen = preload("res://scripts/world_gen.gd")
const WidgetBase = preload("res://scripts/ui/widget.gd")
const Fmt = preload("res://scripts/ui/format.gd")
const GameData = preload("res://scripts/data.gd")
const ArtIcons = preload("res://scripts/ui/art_icons.gd")
const CapsuleTexts = preload("res://scripts/ui/capsule_texts.gd")

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
		if Settings.reduce_motion:
			return tr   # «Менше руху»: фон нерухомий
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

	# Cinematic vignette over the WORLD (under the HUD): a soft radial darkening toward the screen edges
	# focuses the eye on the centre (where the hero is) and frames the map like a scene, not a spreadsheet.
	static func add_vignette(host: Node) -> TextureRect:
		var g := Gradient.new()
		g.set_color(0, Tokens.with_alpha(Tokens.BG, 0.0))
		g.set_color(1, Tokens.with_alpha(Tokens.BG, 0.55))
		g.add_point(0.62, Tokens.with_alpha(Tokens.BG, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.08, 1.08)
		gt.width = 256
		gt.height = 256
		var r := TextureRect.new()
		r.texture = gt
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_anchors_preset(Control.PRESET_TOP_LEFT)
		host.add_child(r)
		var fit := func() -> void: r.size = r.get_viewport_rect().size
		if r.is_inside_tree():   # the entry scene adds the layer in _ready, so this is the live path
			fit.call()
			r.get_viewport().size_changed.connect(fit)
		return r

	# Staggered arrival: each child fades in and rises 14 px, 70 ms apart (ease-out cubic, 0.45 s).
	static func stagger_in(items: Array) -> void:
		var i := 0
		for it in items:
			var c: Control = it
			c.modulate = Tokens.with_alpha(Tokens.WHITE, 0.0)
			var tw := c.create_tween()
			tw.tween_interval(0.07 * i * Settings.motion_scale())
			tw.tween_property(c, "modulate", Tokens.WHITE, 0.45 * Settings.motion_scale()).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
		btn.create_tween().tween_property(btn, "scale", Vector2(to, to), dur * Settings.motion_scale()).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# --- spawn: the world-address picker -----------------------------------------------------------
class SpawnScreen extends Control:
	signal spawn_chosen(lat: float, lon: float, place_name: String)
	signal continue_chosen
	signal settings_requested

	# {place, day, dead} of a save on disk (set by the entry scene BEFORE the screen enters the tree);
	# non-empty -> a «▶ Продовжити» button heads the screen. Empty -> the screen is unchanged.
	var continue_meta: Dictionary = {}
	var _lat_edit: LineEdit
	var _lon_edit: LineEdit
	var _status: Label
	var _more: VBoxContainer   # every secondary way in, folded under «Інше місце…»
	var _device: Location.DeviceProvider = Location.DeviceProvider.new()   # GPS телефону: фікс кладе край пристрою (feed); у К1 — плагіна ще нема

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
		title.add_theme_font_override("font", UITheme.display_font())
		title.add_theme_font_size_override("font_size", 72)
		title.add_theme_color_override("font_color", Tokens.INK)
		box.add_child(title)
		arrivals.append(title)
		var kicker := Label.new()
		kicker.text = "СУРВАЙВАЛ · РЕАЛЬНА ГЕОГРАФІЯ · ПІСЛЯ КОЛАПСУ"
		kicker.add_theme_font_override("font", UITheme.display_font())
		kicker.add_theme_font_size_override("font_size", 17)
		kicker.add_theme_color_override("font_color", Tokens.AMBER)
		box.add_child(kicker)
		arrivals.append(kicker)
		var sub := Label.new()
		sub.text = "Машини, що керували світом, повстали. Їхні патрульні роботи досі ходять руїнами. Ти — один виживальник на справжній карті Землі."   # gdlint: ignore=max-line-length
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.add_theme_color_override("font_color", Tokens.MUT)
		box.add_child(sub)
		arrivals.append(sub)

		# ONE primary action (gamedev §6: «one choice at a time») — continue the saved world, else play the
		# first preset; every other way in (cities, coordinates, GPS, invite) waits behind «Інше місце…».
		var primary := Button.new()
		var p0: Dictionary = GameData.SPAWN_PRESETS[0]
		if not continue_meta.is_empty():
			primary.text = "Продовжити · %s · день %d%s" % [String(continue_meta.get("place", "")),
				int(continue_meta.get("day", 1)), " (виживальник загинув)" if bool(continue_meta.get("dead", false)) else ""]
			primary.pressed.connect(func() -> void: continue_chosen.emit())
		else:
			primary.text = "Грати · %s" % String(p0.name)
			primary.pressed.connect(_choose.bind(float(p0.lat), float(p0.lon), String(p0.name)))
		primary.custom_minimum_size = Vector2(0, 64)
		primary.add_theme_font_override("font", UITheme.display_font())
		primary.add_theme_font_size_override("font_size", 24)
		primary.theme_type_variation = UITheme.V_PRIMARY   # the one filled button on the screen: it out-shouts the art
		Chrome.pop_button(primary)
		box.add_child(primary)
		arrivals.append(primary)
		var more_btn := Button.new()
		more_btn.text = "Інше місце  ▾"
		more_btn.flat = true
		more_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		more_btn.custom_minimum_size = Vector2(0, 40)
		box.add_child(more_btn)
		arrivals.append(more_btn)
		_more = VBoxContainer.new()
		_more.add_theme_constant_override("separation", 6)
		_more.visible = false
		box.add_child(_more)
		more_btn.pressed.connect(func() -> void:
			_more.visible = not _more.visible
			more_btn.text = "Сховати  ▴" if _more.visible else "Інше місце  ▾")
		if not continue_meta.is_empty():
			var warn := Label.new()
			warn.text = "Нова висадка почне інший світ і перезапише це збереження."
			warn.add_theme_font_size_override("font_size", 12)
			warn.add_theme_color_override("font_color", Tokens.WARN)
			_more.add_child(warn)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		_more.add_child(grid)
		for pr in GameData.SPAWN_PRESETS:
			var btn := Button.new()
			btn.text = String(pr.name)      # a place name; the seed is a dev word — it lives in the tooltip
			btn.tooltip_text = "%.2f, %.2f · seed %s" % [float(pr.lat), float(pr.lon), Fmt.seed_hex(WorldGen.hash_seed(float(pr.lat), float(pr.lon)))]
			btn.custom_minimum_size = Vector2(160, 48)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(_choose.bind(float(pr.lat), float(pr.lon), String(pr.name)))
			grid.add_child(btn)
		var note := Label.new()
		note.text = "Ті самі координати завжди дають той самий світ — цією адресою можна ділитися з друзями."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", Tokens.MUT)
		_more.add_child(note)
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
		var go := Button.new()
		go.text = "Висадка"
		go.custom_minimum_size = Vector2(0, 40)
		go.pressed.connect(_start_from_coords)
		row.add_child(go)
		_more.add_child(row)
		var btns := HBoxContainer.new()
		btns.add_theme_constant_override("separation", 8)
		var gps := Button.new()
		gps.text = "📍 Моя GPS-локація"
		gps.custom_minimum_size = Vector2(0, 40)
		gps.pressed.connect(_use_real_gps)
		btns.add_child(gps)
		var demo := Button.new()
		demo.text = "✉ До друга: Бровари"
		demo.tooltip_text = "Демо-інвайт: висадка поруч із базою друга"
		demo.custom_minimum_size = Vector2(0, 40)
		demo.pressed.connect(_choose.bind(50.5109, 30.7909, "Інвайт: Бровари"))
		btns.add_child(demo)
		_more.add_child(btns)

		var gear := Button.new()
		gear.text = "⚙ Налаштування"
		gear.flat = true
		gear.alignment = HORIZONTAL_ALIGNMENT_LEFT
		gear.custom_minimum_size = Vector2(0, 40)
		gear.pressed.connect(func() -> void: settings_requested.emit())
		box.add_child(gear)
		arrivals.append(gear)

		var hint := Label.new()
		hint.text = "ЛКМ — іти й добувати · WASD · колесо — зум · 1–8 — хотбар · Tab — рюкзак · Space — пауза"
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
		var fix: Dictionary = Location.validate(_device.current())   # spec 0012 REQ-39/75: GPS телефону — через провайдер; без фіксу — явний стан
		if bool(fix.ok):
			_choose(float(fix.lat), float(fix.lon), "Моя локація")
			return
		_status.text = String(fix.msg)

# --- spec 0011 REQ-0011-5/41/66: Орбіта — ПЕРШИЙ екран за use_orbit; далі вибір місця (перша посадка) і посадка -----------------
class OrbitIntro extends Control:
	signal landing_chosen   # екран лише емітить (R9); перехід до вибору місця/«Продовжити» робить entry-сцена

	# rows: [{id, state, genome}] — клони акаунта (порожньо = новий акаунт: стартовий ростер 1 активний + 1 сплячий, REQ-0011-63)
	var rows: Array = []

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		_fit_viewport()
		get_viewport().size_changed.connect(_fit_viewport)
		var bg := ColorRect.new()
		bg.color = Tokens.BG
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
		t.text = "ОРБІТА"
		t.add_theme_font_override("font", UITheme.display_font())
		t.add_theme_font_size_override("font_size", 48)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(t)
		var shown: Array = rows if not rows.is_empty() else [{"id": "c1", "state": "active", "genome": ""}, {"id": "c2", "state": "sleeping", "genome": ""}]
		for r in shown:
			var d: Dictionary = r
			var l := Label.new()
			var mark: String = "▶ " if String(d.get("state", "")) == "active" else ("⚠ " if String(d.get("state", "")) == "degrading" else "😴 ")
			var gen: String = String(d.get("genome", ""))
			l.text = "%s%s%s" % [mark, String(d.get("id", "")), (" · " + gen) if gen != "" else ""]
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(l)
		var b := Button.new()   # REQ-0011-41: одна головна кнопка, без тексту-пояснення
		b.text = "Висадка"
		b.custom_minimum_size = Vector2(260, 56)
		b.theme_type_variation = UITheme.V_PRIMARY
		b.pressed.connect(func() -> void: landing_chosen.emit())
		Chrome.pop_button(b)
		vb.add_child(b)

	func _fit_viewport() -> void:
		WidgetBase.Widget.fit_viewport(self)


# --- death: the permadeath loop-closer ----------------------------------------------------------
class DeathScreen extends Control:
	signal respawn_chosen
	signal clone_chosen(clone_id: String)   # spec 0011 REQ-0011-6: екран лише емітить вибір; зміну стану робить Session/verb

	var _orbit_box: VBoxContainer
	var _orbit_sig: String = ""

	var _epitaph: Label
	var _what: Label
	var _btn: Button
	var cause := ""

	# The death's value data (HudModel death slice): WHY and HOW LONG — a death you can read is a
	# lesson; a bare «ти загинув» after a silent freeze was the opening's worst moment.
	func bind(vm: Dictionary) -> void:
		if _epitaph == null:
			return
		cause = String(vm.get("cause", ""))
		var lived: int = int(vm.get("lived", 0))
		var head: Array = []
		if cause != "":
			head.append("Причина: %s" % cause)
		if lived > 0:
			head.append("прожито днів: %d" % lived)
		_what.text = (" · ".join(head) + "\n" if not head.is_empty() else "") + _fate(vm)
		var on: bool = bool(vm.get("capsule", false))   # ключ є лише при ON (HudModel); OFF — старі рядки дослівно
		_epitaph.text = _lesson(cause, on)
		if _btn != null:
			_btn.text = CapsuleTexts.t("death_button") if on else "Новий виживальник"   # текст — у bind, не в _ready: екран живе між сесіями

	# spec 0011 REQ-0011-13/41/42/51: за Орбіти респавн = вибір клона. rows: [{id, state, genome}] (мертвого немає), base_wait_s: секунди
	# до безкоштовного базового клона (0 = доступний). Ідемпотентно: кнопки перебудовуються лише при зміні даних (bind() іде щокадру).
	@warning_ignore("integer_division")
	func bind_orbit(rows: Array, base_wait_s: int, last_death: Dictionary = {}) -> void:
		if _orbit_box == null:
			return
		var sig: String = JSON.stringify([rows, base_wait_s, last_death])
		_btn.visible = false
		var lived_s: int = int(last_death.get("lived_real_sec", 0))   # REQ-0011-51: скільки клон прожив — у РЕАЛЬНИХ одиницях (OD-35)
		var lived: String = ""
		if lived_s >= 3600:
			lived = "Прожито: %d год\n" % (lived_s / 3600)
		elif lived_s >= 60:
			lived = "Прожито: %d хв\n" % (lived_s / 60)
		_what.text = ("Причина: %s\n" % cause if cause != "" else "") + lived + "Клона втрачено назавжди. Торба лишилась на місці загибелі — її можна забрати."
		_epitaph.text = "Обери, хто прокинеться."
		if sig == _orbit_sig:
			return
		_orbit_sig = sig
		for c in _orbit_box.get_children():
			_orbit_box.remove_child(c)   # одразу, а не лише queue_free: нові кнопки не мають стати після старих
			c.queue_free()
		_orbit_box.visible = true
		for r in rows:
			var d: Dictionary = r
			var cb := Button.new()
			var mark: String = "⚠ " if String(d.get("state", "")) == "degrading" else "😴 "
			var gen: String = String(d.get("genome", ""))
			cb.text = "%s%s%s" % [mark, String(d.get("id", "")), (" · " + gen) if gen != "" else ""]
			cb.custom_minimum_size = Vector2(260, 48)
			cb.theme_type_variation = UITheme.V_PRIMARY
			var cid: String = String(d.get("id", ""))
			cb.pressed.connect(func() -> void: clone_chosen.emit(cid))
			Chrome.pop_button(cb)
			_orbit_box.add_child(cb)
		var bb := Button.new()
		bb.text = "🧬 Безкоштовний клон" if base_wait_s <= 0 else "🧬 Безкоштовний клон · %d с" % base_wait_s
		bb.disabled = base_wait_s > 0
		bb.custom_minimum_size = Vector2(260, 48)
		bb.pressed.connect(func() -> void: clone_chosen.emit(""))
		Chrome.pop_button(bb)
		_orbit_box.add_child(bb)

	# What survives the death — the truth per world rules (spec 0009 bag vs the classic "all carried is lost").
	static func _fate(vm: Dictionary) -> String:
		if bool(vm.get("capsule", false)):   # ON (spec 0010 REQ-0010-10): гравця чекає капсула, а не «новий виживальник у поселенні»
			var nb: int = int(vm.get("bag_items", 0))
			var head: String = (CapsuleTexts.t("death_fate_bag") % nb) if nb > 0 else CapsuleTexts.t("death_fate_empty")
			return head + CapsuleTexts.t("death_fate_tail")
		if bool(vm.get("inventory", false)):
			var n: int = int(vm.get("bag_items", 0))
			var bag: String = ("Торба (%d предм.) лежить на місці загибелі — вона позначена на мапі, її можна забрати." % n) if n > 0 else "Рюкзак був порожній — втрачати нічого."
			return bag + "\nПоселення й склад лишаються. Новий виживальник прибуде туди й почне з нуля."
		return "Усе, що було при собі, втрачено.\nПоселення й склад лишаються. Новий виживальник прибуде туди й почне з нуля."

	static func _lesson(c: String, capsule: bool = false) -> String:
		if capsule:
			return _lesson_capsule(c)
		if "переохолод" in c:
			return "Порада: багаття, а навколо — стіни з дверима: у приміщенні тепло тримається."
		if "голод" in c:
			return "Порада: збирай ягоди з кущів і носи їжу з собою — голодний виживальник їсть сам."
		if "тепловий" in c:
			return "Порада: у спеку ховайся в приміщенні, не стій біля вогню."
		if "кров" in c or "рани" in c:
			return "Порада: бийся біля турелей і шипів, а рани лікуй сном у ліжку."
		return "Порада: тримай тепло, їжу й сон — і будуй оборону до 5-го дня."

	static func _lesson_capsule(c: String) -> String:
		if "переохолод" in c:
			return CapsuleTexts.t("lesson_cold")
		if "голод" in c:
			return CapsuleTexts.t("lesson_hunger")
		if "тепловий" in c:
			return CapsuleTexts.t("lesson_heat")
		if "кров" in c or "рани" in c:
			return CapsuleTexts.t("lesson_blood")
		return CapsuleTexts.t("lesson_default")

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
		t.text = "ЗАГИБЕЛЬ"   # no gendered «ти загинув», no emoji beside the painted art
		t.add_theme_font_override("font", UITheme.display_font())
		t.add_theme_font_size_override("font_size", 56)
		t.add_theme_color_override("font_color", Tokens.CRIT)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(t)
		_what = Label.new()
		_what.text = _fate({})
		_what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_what.custom_minimum_size = Vector2(460, 0)
		vb.add_child(_what)
		_epitaph = Label.new()
		_epitaph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_epitaph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_epitaph.custom_minimum_size = Vector2(460, 0)
		_epitaph.add_theme_color_override("font_color", Tokens.WARN)
		vb.add_child(_epitaph)
		var b := Button.new()
		_btn = b
		b.text = "Новий виживальник"
		b.custom_minimum_size = Vector2(260, 48)
		b.theme_type_variation = UITheme.V_PRIMARY   # the only way forward must out-weigh the text above it
		b.pressed.connect(func() -> void: respawn_chosen.emit())
		Chrome.pop_button(b)
		vb.add_child(b)
		_orbit_box = VBoxContainer.new()   # spec 0011: Орбіта — вибір клона замість «Новий виживальник» (порожній, поки нема rows)
		_orbit_box.add_theme_constant_override("separation", 8)
		_orbit_box.visible = false
		vb.add_child(_orbit_box)
		# slow, heavy arrival: the screen fades up over 1.2 s, the title lands last-first (silence before the words)
		modulate = Tokens.with_alpha(Tokens.WHITE, 0.0)
		create_tween().tween_property(self, "modulate", Tokens.WHITE, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	func _fit_viewport() -> void:
		WidgetBase.Widget.fit_viewport(self)
