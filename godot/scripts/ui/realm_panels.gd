# RealWorld — ui/realm_panels.gd : the RealGPS presence UI (spec 0013 §4) — a radar and a roster of
# the survivors around you.
#
# View layer only: reads the `nearby` slice of the HUD snapshot (value data, R8/R10), never a socket,
# a Realm or a delta. Children are created ONCE (R2): the roster is a fixed pool of ROWS slots that
# bind() retexts or hides. Colours come only from Tokens (R3); state is never colour alone (R11) —
# a live player is a FILLED dot, a simulated survivor a HOLLOW ring, and the roster repeats both as
# a glyph plus the bearing word and distance.
extends RefCounted

const PanelBase = preload("res://scripts/ui/panel.gd")
const WidgetBase = preload("res://scripts/ui/widget.gd")
const Widgets = preload("res://scripts/ui/widgets.gd")
const Tokens = preload("res://scripts/ui/tokens.gd")
const UITheme = preload("res://scripts/ui/theme.gd")
const Fmt = preload("res://scripts/ui/format.gd")


# ---- RadarWidget: a top-down disc centred on YOU. North is up; distance is the radial axis, scaled so
# the outer ring is the server's view radius. Pure drawing from value rows — no state but the last bind. ----
class RadarWidget extends WidgetBase.Widget:
	const SIDE := 168.0
	const RINGS := 3
	const DOT_R := 4.0
	var _rows: Array = []
	var _aoi_m := 1200.0
	var _canvas: Control = null

	func _build() -> void:
		custom_minimum_size = Vector2(SIDE, SIDE)
		_canvas = Control.new()
		_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
		_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.draw.connect(_draw_radar)
		add_child(_canvas)

	func bind(vm) -> void:
		build_once()
		if not (vm is Dictionary):
			return
		_rows = (vm.get("rows", []) as Array)
		_aoi_m = maxf(float(vm.get("aoi_m", 1200.0)), 1.0)
		_canvas.queue_redraw()

	# Where a row lands on the disc, relative to the centre, for radius `r` pixels. Static + pure so a
	# test can pin the geometry without a draw call.
	static func dot_offset(brg_deg: float, dist_m: float, aoi_m: float, r: float) -> Vector2:
		var a := deg_to_rad(brg_deg)
		var d := clampf(dist_m / maxf(aoi_m, 1.0), 0.0, 1.0) * r
		return Vector2(sin(a), -cos(a)) * d

	func _draw_radar() -> void:
		var c := _canvas.size * 0.5
		var r := minf(c.x, c.y) - 14.0
		if r <= 8.0:
			return
		var f: Font = UITheme.display_font()
		_canvas.draw_circle(c, r, Tokens.with_alpha(Tokens.PANEL2, 0.9))
		for i in range(1, RINGS + 1):
			_canvas.draw_arc(c, r * float(i) / float(RINGS), 0.0, TAU, 64, Tokens.LINE2 if i == RINGS else Tokens.LINE, 1.0)
		_canvas.draw_line(c + Vector2(0, -r), c + Vector2(0, r), Tokens.LINE, 1.0)
		_canvas.draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Tokens.LINE, 1.0)
		_canvas.draw_string(f, c + Vector2(-6, -r - 3), "Пн", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tokens.MUT)
		_canvas.draw_string(f, c + Vector2(r + 2, 4), "Сх", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tokens.DIM)
		_canvas.draw_string(f, c + Vector2(-6, r + 11), "Пд", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tokens.DIM)
		_canvas.draw_string(f, c + Vector2(-r - 14, 4), "Зх", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tokens.DIM)
		_canvas.draw_string(f, c + Vector2(r * 0.5 + 3, -r * 0.0 - 3), Fmt.distance_m(int(_aoi_m / 2.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Tokens.DIM)
		for row in _rows:
			var p := c + dot_offset(float(row.brg), float(row.dist_m), _aoi_m, r)
			if bool(row.get("same_region", false)):
				_canvas.draw_arc(p, DOT_R + 3.0, 0.0, TAU, 20, Tokens.with_alpha(Tokens.GOOD, 0.55), 1.5)   # shares your world
			if str(row.get("kind", "live")) == "live":
				_canvas.draw_circle(p, DOT_R, Tokens.GOOD)
			else:
				_canvas.draw_arc(p, DOT_R, 0.0, TAU, 20, Tokens.TEAL, 2.0)                                    # hollow = simulated
		_canvas.draw_circle(c, DOT_R + 1.0, Tokens.AMBER)                                                      # you
		_canvas.draw_arc(c, DOT_R + 4.0, 0.0, TAU, 24, Tokens.with_alpha(Tokens.AMBER, 0.5), 1.0)


# ---- NearbyPanel (RIGHT dock, Q): who is around, how far, which way. Reads vm.nearby. ----
class NearbyPanel extends PanelBase.Base:
	const ROWS := 6
	var _head: Widgets.H2Header
	var _radar: RadarWidget
	var _legend: Label
	var _empty: Label
	var _note: Label
	var _rows: Array = []
	var _names: Array = []
	var _dists: Array = []

	func _init() -> void:
		panel_id = &"nearby"; dock = PanelBase.DOCK_RIGHT; priority = 75; hotkey = KEY_Q; default_open = false
		menu_label = "📡 Поряд"; compact_open = 0

	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		_head = Widgets.H2Header.new()
		vb.add_child(_head)
		_head.set_header("Поряд", "")
		_radar = RadarWidget.new()
		_radar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(_radar)
		_legend = Label.new()
		_legend.add_theme_font_size_override("font_size", 11)
		_legend.add_theme_color_override("font_color", Tokens.DIM)
		_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_legend.text = "● гравець   ○ імітація   ◎ у твоєму світі"
		vb.add_child(_legend)
		_empty = Label.new()
		_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_empty.custom_minimum_size = Vector2(200, 0)
		_empty.add_theme_color_override("font_color", Tokens.MUT)
		vb.add_child(_empty)
		for i in ROWS:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			vb.add_child(row)
			var nm := Label.new()
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.clip_text = true
			nm.add_theme_color_override("font_color", Tokens.INK)
			row.add_child(nm)
			var dist := Label.new()
			dist.add_theme_color_override("font_color", Tokens.MUT)
			dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(dist)
			_rows.append(row); _names.append(nm); _dists.append(dist)
		_note = Label.new()
		_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_note.custom_minimum_size = Vector2(200, 0)
		_note.add_theme_font_size_override("font_size", 11)
		_note.add_theme_color_override("font_color", Tokens.WARN)
		vb.add_child(_note)

	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary):
			return
		var n: Dictionary = vm.get("nearby", {"available": false})
		if not bool(n.get("available", false)):
			visible = false
			return
		var rows: Array = n.get("rows", [])
		_head.set_header("Поряд", "%d" % int(n.get("total", 0)))
		_radar.bind(n)
		_empty.visible = rows.is_empty()
		_empty.text = "Нікого в радіусі %s. Світ ділиться на ділянки ~760 м: хто стоїть у твоїй — грає в тому ж світі." % Fmt.distance_m(int(float(n.get("aoi_m", 0.0))))
		for i in ROWS:
			_rows[i].visible = i < rows.size()
			if i < rows.size():
				var r: Dictionary = rows[i]
				var live := str(r.get("kind", "live")) == "live"
				_names[i].text = "%s %s%s" % ["●" if live else "○", str(r.name), "  ◎" if bool(r.get("same_region", false)) else ""]
				_names[i].add_theme_color_override("font_color", Tokens.INK if live else Tokens.TEAL)
				_dists[i].text = "%s · %s" % [Fmt.distance_m(int(r.dist_m)), str(r.dir)]
		var extra: int = int(n.get("total", 0)) - rows.size()
		var note := Fmt.realm_refusal(str(n.get("refusal", "")))
		if extra > 0:
			note = ("ще %d поза списком" % extra) + (" · " + note if note != "" else "")
		_note.text = note
		_note.visible = note != ""
		var rim := Fmt.distance_m(int(float(n.get("aoi_m", 0.0))))
		tooltip_text = "Радар присутності (RealGPS): північ угорі, зовнішнє коло = %s.\nДані — з реалм-сервера; поки сервера немає, інших виживальників імітує гра." % rim
