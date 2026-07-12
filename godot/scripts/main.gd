# RealWorld — main.gd : scene controller (session, spawn, HUD, panels, input, loop)
extends Node2D

const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const GameData = preload("res://scripts/data.gd")
const WorldViewScript = preload("res://scripts/world_view.gd")
const Social = preload("res://scripts/social.gd")
const SessionScript = preload("res://scripts/session.gd")
const MapWidget = preload("res://scripts/map_widget.gd")
const TILE := 28
const MAP_N := 56
const NEIGHBOR_STEP_DEG := 0.01   # ~1.1 km — "around" regions you scout on foot

var sim: Variant
var view: Node2D
var cam: Camera2D
var playing := false
var speed := 1.0
var speed_idx := 0
const SPEEDS := [1.0, 2.0, 3.0, 0.0]

# session orchestration lives in session.gd; social/home mirror it for read-only UI use
var session: Variant
var social: Dictionary = {}
var home := {"lat": 0.0, "lon": 0.0, "name": ""}

# auto/screenshot mode
var auto_mode := false
var auto_t := 0.0
var auto_built := false
var auto_shot := false
var auto_osm := false

# ui screenshot mode (dev verification)
var ui_mode := false
var ui_t := 0.0
var ui_shot := false
var ui_stage := 0
var _gameshot := false

# OSM real-geography fetch
var force_osm := false
var use_osm_check: CheckButton
var http: HTTPRequest
var _osm_bbox: Dictionary = {}

# theme
var _sb_panel: StyleBoxFlat
var _sb_bar: StyleBoxFlat

# UI refs
var spawn_layer: CanvasLayer
var hud: CanvasLayer
var death_layer: CanvasLayer
var info_label: RichTextLabel
var stock_label: RichTextLabel
var log_label: RichTextLabel
var region_label: Label
var banner_label: Label
var flash_label: Label
var build_bar: HBoxContainer
var build_buttons := {}
var toolbar: HBoxContainer
var night_rect: ColorRect
var world_panel: PanelContainer
var items_panel: PanelContainer
var capsule_panel: PanelContainer
var social_panel: PanelContainer
var help_panel: PanelContainer
var spawn_status: Label
var gps_lat_edit: LineEdit
var gps_lon_edit: LineEdit
var cap_lat_edit: LineEdit
var cap_lon_edit: LineEdit
var _invite_cursor := 0

const PRESETS := [
	{"name": "Київ", "lat": 50.4501, "lon": 30.5234},
	{"name": "Львів", "lat": 49.8397, "lon": 24.0297},
	{"name": "Манхеттен", "lat": 40.7549, "lon": -73.9840},
	{"name": "Кіото", "lat": 35.0116, "lon": 135.7681},
	{"name": "Рейк'явік", "lat": 64.1466, "lon": -21.9426},
]

# ---- theme colors ----
const C_ACCENT := "5db0ff"
const C_GOOD := "5fd38a"
const C_WARN := "ffcf5c"
const C_BAD := "ff6b6b"
const C_DIM := "8fa3b5"

# Batch 8a: environment chips (colorblind rule: icon + word, never color alone)
const WEATHER_ICON := {&"clear": "☀", &"rain": "🌧", &"snow": "❄", &"fog": "🌫", &"cold_snap": "🥶"}

func _ready() -> void:
	_init_theme()
	_build_world_nodes()
	_build_hud()
	_build_death_screen()
	_build_spawn_screen()
	var uargs := OS.get_cmdline_user_args()
	if "autoosm" in uargs:
		force_osm = true
		auto_mode = true
		auto_osm = true
		_start_game(50.4501, 30.5234, "Київ")
	elif "auto" in uargs:
		auto_mode = true
		_start_game(50.4501, 30.5234, "Київ")
	elif "gps" in uargs:
		var gi := uargs.find("gps")
		if gi + 2 < uargs.size():
			_start_game(uargs[gi + 1].to_float(), uargs[gi + 2].to_float(), "GPS-висадка")
	elif "invite" in uargs:
		var ii := uargs.find("invite")
		if ii + 2 < uargs.size():
			var nm: String = uargs[ii + 3] if ii + 3 < uargs.size() else "Інвайт"
			_start_game(uargs[ii + 1].to_float(), uargs[ii + 2].to_float(), "Інвайт: " + nm)
	elif "spawnshot" in uargs:
		await get_tree().create_timer(0.4).timeout
		await _save_shot("O:/realworld/godot/spawn_shot.png")
		get_tree().quit()
	elif "uishot" in uargs:
		ui_mode = true
		_start_game(50.4501, 30.5234, "Київ")
	elif "gameshot" in uargs:
		auto_mode = true
		_gameshot = true
		_start_game(50.4501, 30.5234, "Київ")

func _init_theme() -> void:
	_sb_panel = StyleBoxFlat.new()
	_sb_panel.bg_color = Color(0.07, 0.09, 0.12, 0.94)
	_sb_panel.border_color = Color.html(C_ACCENT)
	_sb_panel.set_border_width_all(1)
	_sb_panel.set_corner_radius_all(8)
	_sb_panel.set_content_margin_all(14)
	_sb_bar = StyleBoxFlat.new()
	_sb_bar.bg_color = Color(0.06, 0.08, 0.11, 0.86)
	_sb_bar.set_corner_radius_all(6)
	_sb_bar.set_content_margin_all(6)

func _build_world_nodes() -> void:
	view = WorldViewScript.new()
	add_child(view)
	cam = Camera2D.new()
	cam.zoom = Vector2(1, 1)
	add_child(cam)
	cam.make_current()

# ---------------- spawn screen ----------------
func _build_spawn_screen() -> void:
	spawn_layer = CanvasLayer.new()
	spawn_layer.layer = 6
	add_child(spawn_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	spawn_layer.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	spawn_layer.add_child(scroll)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.custom_minimum_size = Vector2(0, 720)
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)

	var title := Label.new()
	title.text = "RealWorld — Godot"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color.html(C_ACCENT))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Survival-MMORPG на справжній географії після Колапсу. Руїни Старого світу досі обходять патрульні роботи. Обери точку висадки:"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	var seed_note := Label.new()
	seed_note.text = "🌍 Координати — це seed світу: ті самі координати завжди дають той самий світ, для кожного гравця. Координати — це адреса, якою ділишся з друзями."
	seed_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	seed_note.add_theme_font_size_override("font_size", 13)
	seed_note.modulate = Color.html(C_GOOD)
	box.add_child(seed_note)

	var osm_chk := CheckButton.new()
	osm_chk.text = "Реальна географія з OpenStreetMap (повільніше)"
	box.add_child(osm_chk)
	use_osm_check = osm_chk

	box.add_child(_section("Пресети"))
	for pr in PRESETS:
		var btn := Button.new()
		btn.text = "%s  (%.4f, %.4f) · seed %08x" % [pr.name, pr.lat, pr.lon, WorldGen.hash_seed(pr.lat, pr.lon)]
		btn.pressed.connect(_start_game.bind(pr.lat, pr.lon, pr.name))
		box.add_child(btn)

	box.add_child(_section("Real-GPS / свої координати"))
	var grow := HBoxContainer.new()
	gps_lat_edit = LineEdit.new()
	gps_lat_edit.placeholder_text = "широта (lat)"
	gps_lat_edit.custom_minimum_size = Vector2(150, 0)
	gps_lon_edit = LineEdit.new()
	gps_lon_edit.placeholder_text = "довгота (lon)"
	gps_lon_edit.custom_minimum_size = Vector2(150, 0)
	grow.add_child(gps_lat_edit)
	grow.add_child(gps_lon_edit)
	box.add_child(grow)
	var gbtns := HBoxContainer.new()
	var gps_btn := Button.new()
	gps_btn.text = "📍 Моя GPS-локація"
	gps_btn.pressed.connect(_use_real_gps)
	gbtns.add_child(gps_btn)
	var coord_btn := Button.new()
	coord_btn.text = "🛬 Висадка за координатами"
	coord_btn.pressed.connect(_start_from_coords)
	gbtns.add_child(coord_btn)
	box.add_child(gbtns)

	box.add_child(_section("Режим інвайта (висадка до друга)"))
	var inv_hint := Label.new()
	inv_hint.text = "Друг ділиться координатами — введи їх і висадись поруч."
	inv_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inv_hint.modulate = Color.html(C_DIM)
	box.add_child(inv_hint)
	var demo := Button.new()
	demo.text = "✉ Демо-інвайт: Бровари (50.5109, 30.7909)"
	demo.pressed.connect(_start_game.bind(50.5109, 30.7909, "Інвайт: Бровари"))
	box.add_child(demo)

	var hint := Label.new()
	hint.text = "Керування: ЛКМ — іти/добувати/атакувати · ПКМ — розібрати будівлю · колесо — зум · WASD · 1–7 будувати · M логістика · I спорядження · C капсула · F соціальне · H довідка · Space пауза"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color.html(C_DIM)
	box.add_child(hint)

	spawn_status = Label.new()
	spawn_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spawn_status.add_theme_color_override("font_color", Color.html(C_WARN))
	box.add_child(spawn_status)

func _spawn_msg(t: String) -> void:
	if spawn_status != null:
		spawn_status.text = t

func _section(t: String) -> Label:
	var l := Label.new()
	l.text = "— " + t + " —"
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color.html(C_WARN))
	return l

func _use_real_gps() -> void:
	# Web export: browser geolocation. Elsewhere: prompt manual entry (the universal fallback).
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		_spawn_msg("Запит GPS у браузері… дозволь доступ і введи координати, якщо не спрацює.")
		var js := "navigator.geolocation && navigator.geolocation.getCurrentPosition(function(p){window.__rw_lat=p.coords.latitude;window.__rw_lon=p.coords.longitude;});"
		JavaScriptBridge.eval(js, true)
		await get_tree().create_timer(1.5).timeout
		var lat: Variant = JavaScriptBridge.eval("window.__rw_lat", true)
		var lon: Variant = JavaScriptBridge.eval("window.__rw_lon", true)
		if lat != null and lon != null:
			gps_lat_edit.text = str(lat)
			gps_lon_edit.text = str(lon)
			_start_from_coords()
			return
	_spawn_msg("GPS доступний у веб/мобільній збірці. Введи координати вручну і тисни «Висадка».")

# Parse a lat/lon pair — accepts two fields, OR a single "lat, lon" pasted into the first field
# (that's the shareable address form). Validates legal ranges so we never seed a phantom world.
func _parse_latlon(a: String, b: String) -> Dictionary:
	var la := a.strip_edges()
	var lo := b.strip_edges()
	if "," in la and (lo == "" or not ("," in lo)):
		var parts := la.split(",")
		la = parts[0].strip_edges()
		if lo == "" and parts.size() > 1:
			lo = parts[1].strip_edges()
	if la == "" or lo == "":
		return {"ok": false, "msg": "Введи координати (напр. 50.4501, 30.5234)."}
	var lat := la.to_float()
	var lon := lo.to_float()
	if absf(lat) > 90.0 or absf(lon) > 180.0:
		return {"ok": false, "msg": "Поза межами: широта ±90°, довгота ±180°."}
	return {"ok": true, "lat": lat, "lon": lon}

func _start_from_coords() -> void:
	var c := _parse_latlon(gps_lat_edit.text, gps_lon_edit.text)
	if not c.ok:
		_spawn_msg(c.msg)
		return
	_start_game(c.lat, c.lon, "Свої координати")

# ---------------- HUD ----------------
func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 3
	add_child(hud)

	night_rect = ColorRect.new()
	night_rect.color = Color(0.03, 0.05, 0.13, 0.0)
	night_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	night_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(night_rect)

	# top-left: needs / character
	var info_wrap := PanelContainer.new()
	info_wrap.add_theme_stylebox_override("panel", _sb_bar)
	info_wrap.position = Vector2(12, 10)
	info_wrap.custom_minimum_size = Vector2(260, 0)
	hud.add_child(info_wrap)
	info_label = _rich(160)
	info_wrap.add_child(info_label)

	# top-right: stock — pinned to the right edge, grows left+down (resize-safe)
	var stock_wrap := PanelContainer.new()
	stock_wrap.add_theme_stylebox_override("panel", _sb_bar)
	stock_wrap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stock_wrap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	stock_wrap.grow_vertical = Control.GROW_DIRECTION_END
	stock_wrap.offset_left = -12
	stock_wrap.offset_right = -12
	stock_wrap.offset_top = 10
	stock_wrap.offset_bottom = 10
	stock_wrap.custom_minimum_size = Vector2(200, 0)
	hud.add_child(stock_wrap)
	stock_label = _rich(184)
	stock_wrap.add_child(stock_label)

	# top-center: toolbar — full-width strip, buttons auto-centered (independent of count/width),
	# transparent to the mouse so world clicks pass through the empty area
	toolbar = HBoxContainer.new()
	toolbar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	toolbar.offset_top = 8
	toolbar.offset_left = 280   # clear the top-left needs panel
	toolbar.offset_right = -212 # clear the top-right stock panel
	toolbar.alignment = BoxContainer.ALIGNMENT_CENTER
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toolbar.add_theme_constant_override("separation", 6)
	hud.add_child(toolbar)
	_tool_btn("🗺 Логістика", func(): _toggle_only(world_panel))
	_tool_btn("🛠 Спорядження", func(): _toggle_only(items_panel))
	_tool_btn("🧭 Капсула", func(): _toggle_only(capsule_panel))
	_tool_btn("🛡 Соціальне", func(): _toggle_only(social_panel))
	_tool_btn("❔ Довідка", func(): _toggle_only(help_panel))
	_tool_btn("⏯ Швидкість", _cycle_speed)

	# centered banners under the toolbar (full-width so text truly centers)
	region_label = _wide_label(44, 14, false)
	region_label.add_theme_color_override("font_color", Color.html(C_ACCENT))
	banner_label = _wide_label(72, 20, false)
	banner_label.add_theme_color_override("font_color", Color(1, 0.6, 0.6))
	flash_label = _wide_label(120, 16, true)
	flash_label.add_theme_color_override("font_color", Color.html(C_WARN))

	# bottom-left: log — pinned to the bottom-left corner, grows right+up (resize-safe)
	var log_wrap := PanelContainer.new()
	log_wrap.add_theme_stylebox_override("panel", _sb_bar)
	log_wrap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_wrap.grow_horizontal = Control.GROW_DIRECTION_END
	log_wrap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	log_wrap.offset_left = 12
	log_wrap.offset_right = 12
	log_wrap.offset_top = -70
	log_wrap.offset_bottom = -70
	log_wrap.custom_minimum_size = Vector2(430, 0)
	hud.add_child(log_wrap)
	log_label = _rich(112)
	log_wrap.add_child(log_label)

	# bottom-center: build bar — full-width strip, buttons auto-centered
	build_bar = HBoxContainer.new()
	build_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	build_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	build_bar.offset_top = -8
	build_bar.offset_bottom = -8
	build_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	build_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_bar.add_theme_constant_override("separation", 4)
	hud.add_child(build_bar)
	var idx := 1
	for key in GameData.BUILD_ORDER:
		var def: Dictionary = GameData.BUILDINGS[key]
		var btn := Button.new()
		btn.text = "%d %s\n%s" % [idx, def.name, GameData.cost_str(def.cost)]
		btn.tooltip_text = _build_tooltip(key)
		btn.custom_minimum_size = Vector2(80, 46)
		btn.pressed.connect(_select_build.bind(key))
		build_bar.add_child(btn)
		build_buttons[key] = btn
		idx += 1

	world_panel = _mk_modal(Vector2(-190, -160), Vector2(380, 0))
	items_panel = _mk_modal(Vector2(-240, -200), Vector2(480, 0))
	capsule_panel = _mk_modal(Vector2(-250, -230), Vector2(500, 0))
	social_panel = _mk_modal(Vector2(-260, -220), Vector2(520, 0))
	help_panel = _mk_modal(Vector2(-260, -230), Vector2(520, 0))

func _mk_modal(offset: Vector2, minsize: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.visible = false
	p.add_theme_stylebox_override("panel", _sb_panel)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.position = offset
	p.custom_minimum_size = minsize
	hud.add_child(p)
	return p

func _tool_btn(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 30)
	b.pressed.connect(cb)
	toolbar.add_child(b)

func _rich(min_h: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.custom_minimum_size = Vector2(0, min_h)
	r.add_theme_font_size_override("normal_font_size", 14)
	return r

func _wide_label(margin: int, fsize: int, from_bottom: bool) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	if from_bottom:
		l.anchor_top = 1.0
		l.anchor_bottom = 1.0
		l.offset_top = -margin
	else:
		l.offset_top = margin
	hud.add_child(l)
	return l

func _build_tooltip(key: String) -> String:
	var def: Dictionary = GameData.BUILDINGS[key]
	var t := "%s — HP %d\nВартість: %s" % [def.name, int(def.hp), GameData.cost_str(def.cost)]
	if def.get("blocks", false):
		t += "\nблокує прохід"
	if def.has("capacity"):
		t += "\n+%d до складу" % int(def.capacity)
	if key == "turret":
		t += "\nдальність %.1f · DPS %d" % [def.range, int(def.dps)]
	if key == "workbench":
		t += "\nавто-крафт дощок"
	return t

# ---------------- death screen ----------------
func _build_death_screen() -> void:
	death_layer = CanvasLayer.new()
	death_layer.layer = 4
	death_layer.visible = false
	add_child(death_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.02, 0.02, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_layer.add_child(center)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 12)
	center.add_child(vb)
	var t := Label.new()
	t.text = "☠  ТИ ЗАГИНУВ"
	t.add_theme_font_size_override("font_size", 44)
	t.add_theme_color_override("font_color", Color.html(C_BAD))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var s := Label.new()
	s.text = "Одне життя, глибока симуляція. Ти втратив усе нажите й самого героя.\nНова пішка прибуде в поселення — з нуля, без прокачки."
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.custom_minimum_size = Vector2(460, 0)
	vb.add_child(s)
	var b := Button.new()
	b.text = "🧬  Респавн — нова пішка"
	b.custom_minimum_size = Vector2(260, 48)
	b.pressed.connect(_do_respawn)
	vb.add_child(b)

func _do_respawn() -> void:
	# region-aware respawn (fly home if you died at a remote outpost) lives in the session
	session.respawn()
	sim = session.sim
	view.sim = sim
	death_layer.visible = false

# ---------------- session / start ----------------
func _start_game(lat: float, lon: float, place_name: String) -> void:
	session = SessionScript.new()
	session.start(lat, lon, place_name)
	sim = session.sim
	# заморожена сцена не має research-UI (spec 0007 з'явився після freeze): відкриваємо всі
	# data.gd-ворота, інакше турель/броня назавжди замкнені й демо-база лишається без турелей
	for def in GameData.BUILDINGS.values():
		if def.has("research"):
			sim.research_unlocked[String(def.research)] = true
	for it in GameData.ITEMS.values():
		if it.has("research"):
			sim.research_unlocked[String(it.research)] = true
	social = session.social
	home = session.home
	view.sim = sim
	playing = true
	spawn_layer.visible = false
	if force_osm or (use_osm_check != null and use_osm_check.button_pressed):
		_fetch_osm(lat, lon)

# UI wrapper around the session's region travel: delegate the state change, then refresh the view.
func travel_to(lat: float, lon: float, place_name: String) -> void:
	if session == null:
		return
	session.travel_to(lat, lon, place_name)
	sim = session.sim
	view.sim = sim
	_close_all_panels()

# ---------------- main loop ----------------
func _process(dt: float) -> void:
	if not playing:
		return
	if not auto_mode:
		var mv := Vector2.ZERO
		if Input.is_key_pressed(KEY_W): mv.y -= 1
		if Input.is_key_pressed(KEY_S): mv.y += 1
		if Input.is_key_pressed(KEY_A): mv.x -= 1
		if Input.is_key_pressed(KEY_D): mv.x += 1
		sim.move_input = mv
	var sdt := dt * speed
	if sdt > 0 and not sim.dead:
		sim.update(sdt)
	cam.global_position = Vector2(sim.player.px * TILE, sim.player.py * TILE)
	view.hover = _mouse_tile()
	view.queue_redraw()
	_update_hud()
	if not auto_mode:
		death_layer.visible = sim.dead
	if auto_mode:
		_auto_step(dt)
	if ui_mode:
		_ui_step(dt)

func _ui_step(dt: float) -> void:
	ui_t += dt
	# give the pawn a small base + skills so the HUD reads richly, then shoot each new panel
	if ui_stage == 0 and ui_t > 0.2:
		ui_stage = 1
		sim.player.skills.gather = 6.0
		sim.stock.wood = 180
		sim.stock.scrap = 40
		var c: Vector2i = sim.base_center()
		_put("workbench", c.x - 1, c.y - 1)
		_put("bed", c.x + 1, c.y - 1)
		sim.craft_item("axe")
		# dispatch a convoy so the logistics panel shows live route progress in the shot
		sim.stock[sim.regions[1].offer.buys] = 60
		sim.dispatch_convoy(1, sim.regions[1].offer.buys, 20)
		sim._update_convoys(6.0)
		sim.time.frac = 0.5
	elif ui_stage == 1 and ui_t > 0.5:
		ui_stage = 2
		_toggle_only(capsule_panel)
	elif ui_stage == 2 and ui_t > 1.0:
		ui_stage = 3
		await _save_shot("O:/realworld/godot/ui_shot.png")
	elif ui_stage == 3 and ui_t > 1.2:
		ui_stage = 4
		_toggle_only(social_panel)
	elif ui_stage == 4 and ui_t > 1.7:
		ui_stage = 5
		await _save_shot("O:/realworld/godot/ui_shot_social.png")
	elif ui_stage == 5 and ui_t > 1.9:
		ui_stage = 6
		_toggle_only(world_panel)
	elif ui_stage == 6 and ui_t > 2.4:
		ui_stage = 7
		await _save_shot("O:/realworld/godot/ui_shot_map.png")
	elif ui_stage == 7 and ui_t > 2.6:
		ui_stage = 8
		_toggle_only(help_panel)
	elif ui_stage == 8 and ui_t > 3.1:
		ui_stage = 9
		await _save_shot("O:/realworld/godot/ui_shot_help.png")
		get_tree().quit()

func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("UI_SHOT saved: ", path)

func _update_hud() -> void:
	var p: Dictionary = sim.player
	info_label.text = _hud_info(p)
	stock_label.text = _hud_stock()
	region_label.text = "📍 %s · seed %08x · капсула %d" % [sim.region_display(), sim.region_seed(), int(sim.capsule.get("charges", 0))]
	banner_label.text = sim.banner
	flash_label.text = sim.flash_msg if sim.flash_t > 0 else ""
	log_label.text = _hud_log()
	for key in build_buttons:
		build_buttons[key].modulate = Color(1, 1, 1) if GameData.can_afford(sim.stock, GameData.BUILDINGS[key].cost) else Color(1, 1, 1, 0.45)
		build_buttons[key].button_pressed = (view.selected_build == key)
	night_rect.color.a = sim.daylight()

func _hud_info(p) -> String:
	var s := "[b]День %d · %s %s[/b]\n" % [sim.time.day, sim.clock_str(), sim.phase_name()]
	# Batch 8a: живе довкілля — температура з реальної широти, погода, сезон, приміщення, темрява
	var tc: float = sim.hero_temp_c()
	var tcol := C_DIM
	if tc < 5.0:
		tcol = C_ACCENT
	elif tc > 30.0:
		tcol = C_WARN
	var env := "[color=#%s]🌡 %+d°C[/color] · %s %s · %s" % [tcol, int(round(tc)),
		WEATHER_ICON.get(sim.weather, "⛅"), Sim.WEATHER_LABEL.get(sim.weather, "?"), sim.season_name()]
	if sim.is_indoor(int(p.px), int(p.py)):
		env += " · 🏠"
	if sim.dark_work_mult() > 1.001:
		env += " · [color=#%s]🌑 −темрява[/color]" % C_WARN
	s += env + "\n"
	s += "HP    %s\n" % _bbar(p.hp)
	s += "Голод %s\n" % _bbar(p.hunger)
	s += "Відп. %s\n" % _bbar(p.rest)
	s += "[color=#%s]Несе %d/%d · 🪓 %s · ⚔ %s[/color]" % [C_DIM, sim.carry_total(), int(p.carry_cap), _eq_name("tool"), _eq_name("weapon")]
	return s

func _hud_stock() -> String:
	var s := "[b]Склад %d/%d[/b]\n" % [sim.stock_total(), sim.storage_cap()]
	for k in GameData.RES_ORDER:
		s += "%s %s  %d\n" % [GameData.RES[k].icon, GameData.RES[k].label, int(sim.stock.get(k, 0))]
	return s

func _hud_log() -> String:
	var lines := PackedStringArray()
	var start: int = max(0, sim.messages.size() - 6)
	for i in range(start, sim.messages.size()):
		var msg: Dictionary = sim.messages[i]
		var col := C_DIM
		match str(msg.get("cls", "")):
			"good": col = C_GOOD
			"warn": col = C_WARN
			"bad": col = C_BAD
			_: col = "cfe0ec"
		lines.append("[color=#%s]%s[/color]" % [col, msg.text])
	return "\n".join(lines)

func _bbar(v: float) -> String:
	var vv := clampf(v, 0, 100)
	var filled := int(round(vv / 100.0 * 10))
	var col := C_GOOD if vv > 50 else (C_WARN if vv > 25 else C_BAD)
	return "[color=#%s]%s[/color][color=#2a3540]%s[/color] %d" % [col, "█".repeat(filled), "█".repeat(10 - filled), int(vv)]

func _mouse_tile() -> Vector2i:
	var w := get_global_mouse_position()
	return Vector2i(int(floor(w.x / TILE)), int(floor(w.y / TILE)))

func _select_build(key: String) -> void:
	view.selected_build = "" if view.selected_build == key else key

# ---------------- input ----------------
func _unhandled_input(event: InputEvent) -> void:
	if not playing or auto_mode:
		return
	if sim.dead:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _pointer_over_ui():
				return
			_handle_click(_mouse_tile())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# right-click cancels a pending build, else tears down your own building under the cursor
			if view.selected_build != "":
				view.selected_build = ""
			elif not _pointer_over_ui():
				_handle_demolish(_mouse_tile())
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / 1.1)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_7:
			var bi: int = k - KEY_1
			if bi < GameData.BUILD_ORDER.size():
				_select_build(GameData.BUILD_ORDER[bi])
		elif k == KEY_SPACE:
			_cycle_speed()
		elif k == KEY_M:
			_toggle_only(world_panel)
		elif k == KEY_I:
			_toggle_only(items_panel)
		elif k == KEY_C:
			_toggle_only(capsule_panel)
		elif k == KEY_F:
			_toggle_only(social_panel)
		elif k == KEY_H:
			_toggle_only(help_panel)
		elif k == KEY_ESCAPE:
			view.selected_build = ""
			sim.player.action = null
			_close_all_panels()

func _pointer_over_ui() -> bool:
	for pnl in [world_panel, items_panel, capsule_panel, social_panel, help_panel]:
		if pnl != null and pnl.visible and pnl.get_global_rect().has_point(get_viewport().get_mouse_position()):
			return true
	return false

func _handle_click(t: Vector2i) -> void:
	if view.selected_build != "":
		sim.try_build(view.selected_build, t.x, t.y)
		return
	var best: Variant = null
	var bd := 0.7
	var fx := get_global_mouse_position().x / TILE
	var fy := get_global_mouse_position().y / TILE
	for e in sim.enemies:
		var d: float = sqrt((e.px - fx) * (e.px - fx) + (e.py - fy) * (e.py - fy))
		if d < bd:
			bd = d
			best = e
	if best != null:
		sim.order_attack(best)
		return
	if sim._in(t.x, t.y) and sim.map.nodes.has(t.y * sim.n + t.x):
		sim.order_gather(t.x, t.y)
	else:
		sim.order_move(t.x, t.y)

func _handle_demolish(t: Vector2i) -> void:
	var res: Dictionary = sim.demolish(t.x, t.y)
	if not res.ok:
		sim._flash(res.msg)

func _zoom_by(factor: float) -> void:
	var z: float = clampf(cam.zoom.x * factor, 0.55, 2.2)
	cam.zoom = Vector2(z, z)

func _cycle_speed() -> void:
	speed_idx = (speed_idx + 1) % SPEEDS.size()
	speed = SPEEDS[speed_idx]

# ---------------- panels ----------------
func _close_all_panels() -> void:
	for pnl in [world_panel, items_panel, capsule_panel, social_panel, help_panel]:
		if pnl != null:
			pnl.visible = false

func _toggle_only(target: PanelContainer) -> void:
	var want := not target.visible
	_close_all_panels()
	target.visible = want
	if not want:
		return
	if target == world_panel:
		_build_world_panel()
	elif target == items_panel:
		_build_items_panel()
	elif target == capsule_panel:
		_build_capsule_panel()
	elif target == social_panel:
		_build_social_panel()
	elif target == help_panel:
		_build_help_panel()

func _clear(node: Node) -> VBoxContainer:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	node.add_child(vb)
	return vb

func _panel_title(vb: VBoxContainer, text: String) -> void:
	var t := Label.new()
	t.text = text
	t.add_theme_font_size_override("font_size", 18)
	t.add_theme_color_override("font_color", Color.html(C_ACCENT))
	vb.add_child(t)

func _close_button(vb: VBoxContainer, target: PanelContainer) -> void:
	var close := Button.new()
	close.text = "Закрити"
	close.pressed.connect(func(): target.visible = false)
	vb.add_child(close)

# --- logistics ---
func _build_world_panel() -> void:
	var vb := _clear(world_panel)
	_panel_title(vb, "🗺 Логістика — конвої (везе 20 од.)")

	# schematic real-world map: home ★ · trade hubs ▪ · friend outposts ●
	var mw := MapWidget.new()
	mw.custom_minimum_size = Vector2(348, 210)
	var pts := [{"lat": sim.regions[0].lat, "lon": sim.regions[0].lon, "kind": "home", "color": Color.html(C_ACCENT), "label": str(sim.regions[0].name)}]
	for i in range(1, sim.regions.size()):
		var r: Dictionary = sim.regions[i]
		pts.append({"lat": r.lat, "lon": r.lon, "kind": "hub", "color": Color.html(C_WARN), "label": "%s %dкм" % [r.name, int(r.d)]})
	if not social.is_empty():
		for fr in social.friends:
			pts.append({"lat": fr.lat, "lon": fr.lon, "kind": "friend", "color": Color.html(C_GOOD), "label": fr.place})
	# where you actually stand right now
	pts.append({"lat": float(sim.map.lat), "lon": float(sim.map.lon), "kind": "you", "color": Color(1, 1, 1), "label": ""})
	mw.set_points(pts)
	vb.add_child(mw)
	var legend := Label.new()
	legend.text = "★ база · ▪ торг-хаб · ● друг · ○ ти"
	legend.modulate = Color.html(C_DIM)
	legend.add_theme_font_size_override("font_size", 12)
	vb.add_child(legend)

	for i in range(1, sim.regions.size()):
		var r: Dictionary = sim.regions[i]
		var btn := Button.new()
		btn.text = "→ %s (%d км): %s → %s" % [r.name, int(r.d), GameData.RES[r.offer.buys].label, GameData.RES[r.offer.sells].label]
		btn.pressed.connect(_send_convoy.bind(i))
		vb.add_child(btn)
	if sim.convoys.size() > 0:
		vb.add_child(_section("У дорозі"))
		for c in sim.convoys:
			var pct: int = int(clampf(float(c.t) / maxf(0.001, float(c.dur)), 0, 1) * 100)
			var dir := "➡ туди" if str(c.phase) == "out" else "⬅ назад"
			var cargo: String = "%d %s → %d %s" % [int(c.send_amt), GameData.RES[c.send_res].icon, int(c.recv_amt), GameData.RES[c.recv_res].icon]
			var lbl := Label.new()
			lbl.text = "🚚 #%d %s (%d%%) · %s%s" % [int(c.id), str(c.hub_name), pct, cargo, (" ⚔ засідка" if c.get("ambushed", false) else "")]
			lbl.modulate = Color.html(C_WARN if c.get("ambushed", false) else C_DIM)
			vb.add_child(lbl)
	_close_button(vb, world_panel)

func _send_convoy(hub_index: int) -> void:
	var r: Dictionary = sim.regions[hub_index]
	var res: Dictionary = sim.dispatch_convoy(hub_index, r.offer.buys, 20)
	if not res.ok:
		sim._flash(res.msg)
	_build_world_panel()

# --- items ---
func _build_items_panel() -> void:
	var vb := _clear(items_panel)
	_panel_title(vb, "🛠 Спорядження")
	var sub := Label.new()
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.text = "Потрібен верстак. Екіпіровано: 🪓 %s · ⚔ %s" % [_eq_name("tool"), _eq_name("weapon")]
	sub.modulate = Color.html(C_DIM)
	vb.add_child(sub)
	for id in GameData.ITEM_ORDER:
		var it: Dictionary = GameData.ITEMS[id]
		# armor (vest/plate) не має dmg_bonus — крапковий доступ падав би "Invalid get index"
		var eff: String
		if it.slot == "tool":
			eff = "×%.1f видобуток" % it.gather_mult
		elif it.slot == "armor":
			eff = "−%d%% урон" % int(round(float(it.get("dmg_cut", 0.0)) * 100.0))
		else:
			eff = "+%d урон" % int(it.get("dmg_bonus", 0))
		var btn := Button.new()
		if sim.player.items.has(id):
			btn.text = "Екіпірувати: %s [%s] — %s" % [it.name, it.slot, eff]
			btn.pressed.connect(_equip_item.bind(id))
		else:
			btn.text = "Скрафтити: %s [%s] — %s · %s" % [it.name, it.slot, eff, GameData.cost_str(it.recipe)]
			btn.pressed.connect(_craft_item.bind(id))
		vb.add_child(btn)
	_close_button(vb, items_panel)

func _short_hash(h: String) -> String:
	return h.substr(0, 8) if h.length() >= 8 else "—"

func _eq_name(slot: String) -> String:
	var id: String = sim.player.equipped.get(slot, "")
	return GameData.ITEMS[id].name if (id != "" and GameData.ITEMS.has(id)) else "—"

func _craft_item(id: String) -> void:
	var res: Dictionary = sim.craft_item(id)
	if not res.ok:
		sim._flash(res.msg)
	_build_items_panel()

func _equip_item(id: String) -> void:
	sim.equip(id)
	_build_items_panel()

# --- capsule / around-maps ---
func _build_capsule_panel() -> void:
	var vb := _clear(capsule_panel)
	_panel_title(vb, "🧭 Капсула та переміщення")
	var head := Label.new()
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.text = "Заряди: %d/%d · радіус %d км · ти в: %s\nКапсула переносить пішку з повним інвентарем, база лишається." % [
		int(sim.capsule.charges), GameData.CAPSULE_DAILY_CHARGES, int(sim.capsule.radius_km), sim.region_display()]
	vb.add_child(head)
	# the coordinate seed = the shared, reproducible identity of THIS world (same for every player here)
	var seedrow := HBoxContainer.new()
	var seedlbl := Label.new()
	seedlbl.text = "🌍 seed світу: %08x — ті самі координати = той самий світ у всіх гравців" % sim.region_seed()
	seedlbl.add_theme_color_override("font_color", Color.html(C_GOOD))
	seedlbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	seedlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seedrow.add_child(seedlbl)
	var copy := Button.new()
	copy.text = "📋 Копіювати"
	copy.tooltip_text = "Скопіювати координати (адресу світу) в буфер обміну"
	copy.pressed.connect(_copy_coords)
	seedrow.add_child(copy)
	vb.add_child(seedrow)
	# distinct from the seed: the append-only SAVE history (depends on your travel, not the coordinate)
	var chain := Label.new()
	chain.text = "🔗 Збереження (seed+diff): %d регіон(ів) · історія %s" % [session.stored_region_count(), _short_hash(session.chain_head())]
	chain.modulate = Color.html(C_DIM)
	vb.add_child(chain)

	vb.add_child(_section("Інвайти від друзів"))
	if sim.invites.is_empty():
		var none := Label.new()
		none.text = "Немає інвайтів. Згенеруй у панелі «Соціальне»."
		none.modulate = Color.html(C_DIM)
		vb.add_child(none)
	for inv in sim.invites:
		var chk: Dictionary = sim.capsule_can_reach(inv.lat, inv.lon)
		var mark := "🟢" if chk.ok else "🔴"
		var btn := Button.new()
		btn.text = "%s ✉ %s → %s (%d км)" % [mark, inv.inviter, inv.name, int(chk.km)]
		btn.disabled = not chk.ok
		btn.pressed.connect(_accept_invite.bind(inv.id))
		vb.add_child(btn)

	vb.add_child(_section("Сусідні регіони (розвідати пішки, безкоштовно)"))
	var dirs := [["Північ", NEIGHBOR_STEP_DEG, 0.0], ["Південь", -NEIGHBOR_STEP_DEG, 0.0], ["Схід", 0.0, NEIGHBOR_STEP_DEG], ["Захід", 0.0, -NEIGHBOR_STEP_DEG]]
	var hb := HBoxContainer.new()
	for d in dirs:
		var nlat := float(sim.map.lat) + float(d[1])
		var nlon := float(sim.map.lon) + float(d[2])
		var btn := Button.new()
		btn.text = "🧭 %s" % d[0]
		btn.pressed.connect(travel_to.bind(nlat, nlon, "Околиця: %s" % d[0]))
		hb.add_child(btn)
	vb.add_child(hb)

	vb.add_child(_section("Довільні координати (капсула, ≤%d км)" % int(sim.capsule.radius_km)))
	var row := HBoxContainer.new()
	cap_lat_edit = LineEdit.new()
	cap_lat_edit.placeholder_text = "lat (або встав lat,lon)"
	cap_lat_edit.custom_minimum_size = Vector2(150, 0)
	cap_lon_edit = LineEdit.new()
	cap_lon_edit.placeholder_text = "lon"
	cap_lon_edit.custom_minimum_size = Vector2(120, 0)
	var go := Button.new()
	go.text = "🚀 Запустити"
	go.pressed.connect(_launch_manual)
	row.add_child(cap_lat_edit)
	row.add_child(cap_lon_edit)
	row.add_child(go)
	vb.add_child(row)
	_close_button(vb, capsule_panel)

func _copy_coords() -> void:
	# coordinates ARE the shareable address of this exact world — hand them to a friend verbatim
	var s := "%.4f,%.4f" % [float(sim.map.lat), float(sim.map.lon)]
	DisplayServer.clipboard_set(s)
	sim._flash("Скопійовано координати: %s (seed %08x)" % [s, sim.region_seed()])

func _accept_invite(id: String) -> void:
	var res: Dictionary = sim.accept_invite(id)
	if res.ok:
		travel_to(res.lat, res.lon, res.name)
	else:
		sim._flash(res.msg)
		_build_capsule_panel()

func _launch_manual() -> void:
	var c := _parse_latlon(cap_lat_edit.text, cap_lon_edit.text)
	if not c.ok:
		sim._flash(c.msg)
		return
	var res: Dictionary = sim.try_launch_capsule(c.lat, c.lon, "Ціль капсули")
	if res.ok:
		travel_to(res.lat, res.lon, res.name)
	else:
		sim._flash(res.msg)
		_build_capsule_panel()

# --- social ---
func _build_social_panel() -> void:
	var vb := _clear(social_panel)
	_panel_title(vb, "🛡 Соціальне — клан / альянс / імперія")
	var clan := Social.my_clan(social)
	var ali := Social.my_alliance(social)
	var emp := Social.my_empire(social)
	var head := RichTextLabel.new()
	head.bbcode_enabled = true
	head.fit_content = true
	head.custom_minimum_size = Vector2(0, 96)
	head.text = "🧍 [b]%s[/b]\n🛡 Клан: [b]%s[/b] — %s\n🤝 Альянс: %s\n👑 Імперія: %s" % [
		social.me.name, clan.name, ", ".join(clan.members),
		(ali.name if not ali.is_empty() else "—"),
		(emp.name if not emp.is_empty() else "—")]
	vb.add_child(head)

	vb.add_child(_section("Дипломатія (стосунки з іншими кланами)"))
	for cid in social.clans:
		if cid == social.me.clan:
			continue
		var st: String = Social.stance_toward(social, cid)
		var lbl := Label.new()
		lbl.text = "%s %s — %s" % [GameData.STANCE_ICON.get(st, "•"), social.clans[cid].name, st]
		lbl.modulate = Color.html(C_BAD) if st == "hostile" else (Color.html(C_GOOD) if st == "ally" else Color.html(C_DIM))
		vb.add_child(lbl)
	var hp := Label.new()
	hp.text = "Ворожих кланів: %d · тиск рейдів ×%.2f" % [Social.hostiles(social).size(), Social.raid_pressure(social)]
	hp.modulate = Color.html(C_WARN)
	vb.add_child(hp)

	vb.add_child(_section("Друзі (джерела капсульних інвайтів)"))
	for i in social.friends.size():
		var fr: Dictionary = social.friends[i]
		var btn := Button.new()
		btn.text = "✉ Запросити інвайт від %s (%s)" % [fr.name, fr.place]
		btn.pressed.connect(_gen_invite.bind(i))
		vb.add_child(btn)
	_close_button(vb, social_panel)

func _gen_invite(i: int) -> void:
	sim.add_invite(Social.friend_invite(social, i, sim.capsule.radius_km))
	_toggle_only(capsule_panel)

# --- help / controls ---
func _build_help_panel() -> void:
	var vb := _clear(help_panel)
	_panel_title(vb, "❔ Довідка — керування та цикл гри")
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(0, 300)
	body.add_theme_font_size_override("normal_font_size", 14)
	body.text = "\n".join([
		"[b][color=#%s]Керування[/color][/b]" % C_ACCENT,
		"• [b]ЛКМ[/b] — іти - по 🌲/🪨/🫐/руїні — добувати - по рейдеру — атакувати",
		"• [b]WASD[/b] — прямий рух - [b]ПКМ[/b] — зняти вибір / [b]розібрати[/b] свою будівлю",
		"• [b]1–7[/b] — обрати будівлю - розмісти [b]ЛКМ[/b] (зелено=можна)",
		"• [b]Колесо миші[/b] — зум - [b]Space[/b] — пауза/швидкість",
		"• [b]M[/b] логістика - [b]I[/b] спорядження - [b]C[/b] капсула - [b]F[/b] соціальне - [b]H[/b] довідка - [b]Esc[/b] закрити",
		"",
		"[b][color=#%s]Світ = координати[/color][/b]" % C_ACCENT,
		"• Карта, ресурси й соціальний ростер — [b]чиста функція координат[/b] (seed). Ті самі координати завжди дають той самий світ, для всіх гравців.",
		"• Координати — це [b]адреса[/b]: скопіюй їх (панель Капсула) і дай другу, щоб він висадився у той самий світ.",
		"• Реальна географія OSM лише уточнює процедурну основу поверх того ж seed.",
		"",
		"[b][color=#%s]Цикл виживання[/color][/b]" % C_ACCENT,
		"• Добувай ресурси → неси на [b]склад[/b] 📦 (сам розвантажуєшся поруч).",
		"• Будуй мури/турелі, [b]верстак[/b] (крафт дощок+спорядження), [b]ліжко[/b] (сон), [b]склад[/b].",
		"• Голод/відпочинок падають — їж біля складу, спи в ліжку вночі.",
		"• [b]Рейди[/b] приходять циклічно (у MMO — інші гравці); ворожі клани б'ють сильніше.",
		"• [b]Конвої[/b] возять ресурс у реальні міста й привозять інший (можлива засідка).",
		"• [b]Капсула[/b] (1/день, ≤%d км) переносить пішку з інвентарем; база лишається." % int(GameData.CAPSULE_BASE_RADIUS_KM),
		"• [b]Смерть[/b] = кінець героя: нова пішка з нуля в поселенні (база й склад лишаються).",
	])
	vb.add_child(body)
	_close_button(vb, help_panel)

# ---------------- auto screenshot mode ----------------
func _auto_step(dt: float) -> void:
	auto_t += dt
	if _gameshot:
		if not auto_built and auto_t > 0.15:
			auto_built = true
			_auto_build_base()
			_close_all_panels()
			# spawn a live raid for the shot
			sim.raid.next = 0.05
			sim.raid.timer = 0.0
			sim.raid.active = false
			sim.raid.warned = false
		if auto_t > 2.0 and cam.zoom.x > 0.75:
			cam.zoom = Vector2(0.72, 0.72)   # zoom out to survey the base (verifies cull path)
		if auto_t > 3.5 and not auto_shot:
			auto_shot = true
			await _save_shot("O:/realworld/godot/game_shot.png")
			get_tree().quit()
		return
	if auto_osm:
		if auto_t > 9.0 and not auto_shot:
			auto_shot = true
			_capture_and_quit()
		return
	if not auto_built and auto_t > 0.15:
		auto_built = true
		_auto_build_base()
	if auto_t > 2.6 and not auto_shot:
		auto_shot = true
		_capture_and_quit()

func _auto_build_base() -> void:
	sim.stock.wood = 240
	sim.stock.stone = 240
	sim.stock.scrap = 60
	sim.stock.components = 12
	var c: Vector2i = sim.base_center()
	for d in range(-3, 4):
		_put("wall", c.x + d, c.y - 3)
		_put("wall", c.x + d, c.y + 3)
		_put("wall", c.x - 3, c.y + d)
		_put("wall", c.x + 3, c.y + d)
	_put("door", c.x, c.y + 3)
	_put("workbench", c.x - 1, c.y - 1)
	_put("bed", c.x + 1, c.y - 1)
	_put("turret", c.x - 2, c.y + 2)
	_put("turret", c.x + 2, c.y - 2)
	sim.player.px = c.x + 0.5
	sim.player.py = c.y + 1.5
	sim.time.frac = 0.46
	sim.craft_item("axe")
	sim.craft_item("spear")
	items_panel.visible = true
	_build_items_panel()

func _put(kind: String, x: int, y: int) -> void:
	if sim.build_valid(x, y) and GameData.can_afford(sim.stock, GameData.BUILDINGS[kind].cost):
		sim.try_build(kind, x, y)

func _capture_and_quit() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("O:/realworld/godot/auto_shot.png")
	print("AUTO_SHOT saved")
	get_tree().quit()

# ---------------- real OSM geography (Overpass) ----------------
func _fetch_osm(lat: float, lon: float) -> void:
	var radius := 380.0
	var dlat := radius / 111320.0
	var dlon := radius / (111320.0 * cos(deg_to_rad(lat)))
	var south := lat - dlat
	var north := lat + dlat
	var west := lon - dlon
	var east := lon + dlon
	_osm_bbox = {"s": south, "n": north, "w": west, "e": east}
	var bb := "%f,%f,%f,%f" % [south, west, north, east]
	var q := "[out:json][timeout:18];(" \
		+ "way[\"highway\"](" + bb + ");" \
		+ "way[\"natural\"=\"water\"](" + bb + ");" \
		+ "way[\"waterway\"](" + bb + ");" \
		+ "way[\"natural\"=\"wood\"](" + bb + ");" \
		+ "way[\"landuse\"=\"forest\"](" + bb + ");" \
		+ "way[\"building\"](" + bb + ");" \
		+ ");out geom 1800;"
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_osm_done)
	sim._log("🌐 Тягну реальну географію OSM…")
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])
	var err := http.request("https://overpass-api.de/api/interpreter", headers, HTTPClient.METHOD_POST, "data=" + q.uri_encode())
	if err != OK:
		sim._log("🌐 OSM-запит не вдався — карта лишається процедурною.", "warn")

func _on_osm_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if http != null:
		http.queue_free()
		http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		sim._log("🌐 OSM недоступний (код %d) — карта процедурна." % code, "warn")
		return
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (json is Dictionary) or not json.has("elements"):
		sim._log("🌐 OSM: порожня відповідь — карта процедурна.", "warn")
		return
	var elements: Array = json.elements
	if elements.is_empty():
		sim._log("🌐 OSM: тут нічого не знайдено — карта процедурна.", "warn")
		return
	var stats: Dictionary = WorldGen.overlay_osm(sim.map, elements, _osm_bbox)
	sim.after_map_change()
	if view != null:
		view.queue_redraw()
	sim._log("🌐 Реальна географія OSM: дороги %d · водойми %d · ліси %d · будівлі %d." % [stats.road, stats.water, stats.forest, stats.building], "good")
