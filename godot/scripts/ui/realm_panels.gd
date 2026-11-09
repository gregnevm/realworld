# RealWorld — ui/realm_panels.gd : the RealGPS presence UI (spec 0013 §4) — a minimap of your region with
# the survivors around you on it, and a roster.
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


# ---- MinimapWidget: the active region seen from above (one texel per tile, drawn once per region seed),
# with YOU, your capsule and the survivors around you on it. Other players are placed by their real
# bearing and distance from you converted to tiles (metres / m_per_tile); anyone beyond the map edge is
# pinned to the rim as a ▲ pointing the way. A scale bar says what a tile-length is in metres. ----
class MinimapWidget extends WidgetBase.Widget:
	const SIDE := 176.0
	const DOT_R := 3.5
	const BAR_M := 100.0
	var _rows: Array = []
	var _n := 0
	var _hero := Vector2.ZERO
	var _cap := Vector2(-1, -1)
	var _m_per_tile := 13.0
	var _key := -1
	var _tex: ImageTexture = null
	var _canvas: Control = null

	func _build() -> void:
		custom_minimum_size = Vector2(SIDE, SIDE)
		_canvas = Control.new()
		_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
		_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_canvas.draw.connect(_draw_map)
		add_child(_canvas)

	func bind(vm) -> void:
		build_once()
		if not (vm is Dictionary):
			return
		_rows = (vm.get("rows", []) as Array)
		var m: Dictionary = vm.get("map", {})
		if not m.is_empty():
			_n = int(m.get("n", 0))
			_hero = Vector2(float(m.hero.x), float(m.hero.y))
			var cap: Dictionary = m.get("capsule", {})
			_cap = Vector2(float(cap.x), float(cap.y)) if not cap.is_empty() else Vector2(-1, -1)
			_m_per_tile = maxf(float(vm.get("cell_m", 760.0)) / float(maxi(_n, 1)), 0.1)
			if int(m.get("key", 0)) != _key or _tex == null:
				_key = int(m.get("key", 0))
				_tex = terrain_texture(Marshalls.base64_to_raw(str(m.get("tiles", ""))), _n)
		_canvas.queue_redraw()

	# Terrain ids (WorldGen enum) -> palette ids. ONE site, so the legend of the map is this table.
	static func terrain_token(t: int) -> String:
		match t:
			0: return "water"
			2: return "forest"
			3: return "rock"
			4: return "road"
			5: return "soil"
			6: return "ruin"
			7: return "sand"
			8: return "snow"
			_: return "grass"

	# One texel per tile. Null when the data is missing or the wrong size (the widget then draws only a frame).
	static func terrain_texture(tiles: PackedByteArray, n: int) -> ImageTexture:
		if n <= 0 or tiles.size() != n * n:
			return null
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				img.set_pixel(x, y, Tokens.terrain(terrain_token(int(tiles[y * n + x]))))
		return ImageTexture.create_from_image(img)

	# Where a player is on the map, in TILE units: your tile + (bearing, distance) converted to tiles.
	static func tile_pos(hero: Vector2, brg_deg: float, dist_m: float, m_per_tile: float) -> Vector2:
		var a := deg_to_rad(brg_deg)
		return hero + Vector2(sin(a), -cos(a)) * (dist_m / maxf(m_per_tile, 0.1))

	# A tile-space point -> a pixel on the widget; `inside` is false (and the point is pinned to the rim)
	# when it falls off the map.
	static func to_pixel(tile: Vector2, n: int, side: float, margin: float) -> Dictionary:
		var k := side / float(maxi(n, 1))
		var p := tile * k + Vector2(k, k) * 0.5
		var inside := p.x >= 0.0 and p.y >= 0.0 and p.x <= side and p.y <= side
		return {"p": Vector2(clampf(p.x, margin, side - margin), clampf(p.y, margin, side - margin)), "inside": inside}

	func _draw_map() -> void:
		var side := minf(_canvas.size.x, _canvas.size.y)
		if side <= 24.0:
			return
		var f: Font = UITheme.display_font()
		var frame := Rect2(Vector2.ZERO, Vector2(side, side))
		_canvas.draw_rect(frame, Tokens.PANEL2)
		if _tex != null:
			_canvas.draw_texture_rect(_tex, frame, false)
			_canvas.draw_rect(frame, Tokens.with_alpha(Tokens.BG, 0.18))   # settle the terrain behind the markers
		_canvas.draw_rect(frame, Tokens.LINE2, false, 1.0)
		if _n <= 0:
			return
		if _cap.x >= 0.0:
			var cp: Vector2 = to_pixel(_cap, _n, side, 5.0).p
			_canvas.draw_rect(Rect2(cp - Vector2(4, 4), Vector2(8, 8)), Tokens.TEAL, false, 2.0)   # ◎ capsule core
		for row in _rows:
			var tp := tile_pos(_hero, float(row.brg), float(row.dist_m), _m_per_tile)
			var px: Dictionary = to_pixel(tp, _n, side, 6.0)
			var p: Vector2 = px.p
			var live := str(row.get("kind", "live")) == "live"
			var col: Color = Tokens.GOOD if live else Tokens.TEAL
			if not bool(px.inside):
				var dir := Vector2(sin(deg_to_rad(float(row.brg))), -cos(deg_to_rad(float(row.brg))))
				var perp := Vector2(-dir.y, dir.x)
				_canvas.draw_colored_polygon(PackedVector2Array([p + dir * 6.0, p - dir * 3.0 + perp * 4.5, p - dir * 3.0 - perp * 4.5]), col)   # ▲ off-map
				continue
			if bool(row.get("same_region", false)):
				_canvas.draw_arc(p, DOT_R + 3.0, 0.0, TAU, 20, Tokens.with_alpha(Tokens.WHITE, 0.7), 1.0)   # ◎ shares your world
			if live:
				_canvas.draw_circle(p, DOT_R, col)
			else:
				_canvas.draw_circle(p, DOT_R, Tokens.with_alpha(Tokens.BG, 0.6))
				_canvas.draw_arc(p, DOT_R, 0.0, TAU, 20, col, 1.8)
		var hp: Vector2 = to_pixel(_hero, _n, side, 4.0).p
		_canvas.draw_circle(hp, DOT_R + 1.5, Tokens.BG)
		_canvas.draw_circle(hp, DOT_R, Tokens.AMBER)
		_canvas.draw_arc(hp, DOT_R + 3.5, 0.0, TAU, 24, Tokens.with_alpha(Tokens.AMBER, 0.6), 1.0)
		_canvas.draw_string(f, Vector2(side * 0.5 - 6.0, 11.0), "Пн", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tokens.with_alpha(Tokens.INK, 0.85))
		var bar_px: float = BAR_M / _m_per_tile * side / float(_n)   # scale bar: what 100 m is on THIS map
		var by := side - 9.0
		_canvas.draw_line(Vector2(7, by), Vector2(7.0 + bar_px, by), Tokens.INK, 2.0)
		_canvas.draw_line(Vector2(7, by - 3), Vector2(7, by + 3), Tokens.INK, 1.0)
		_canvas.draw_line(Vector2(7.0 + bar_px, by - 3), Vector2(7.0 + bar_px, by + 3), Tokens.INK, 1.0)
		_canvas.draw_string(f, Vector2(11.0 + bar_px, by + 4.0), "%d м" % int(BAR_M), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tokens.INK)


# ---- NearbyPanel (RIGHT dock, Q): the minimap + a roster of who is around, how far, which way. Reads vm.nearby. ----
class NearbyPanel extends PanelBase.Base:
	const ROWS := 6
	var _head: Widgets.H2Header
	var _minimap: MinimapWidget
	var _legend: Label
	var _empty: Label
	var _note: Label
	var _rows: Array = []
	var _names: Array = []
	var _dists: Array = []

	func _init() -> void:
		panel_id = &"nearby"; dock = PanelBase.DOCK_RIGHT; priority = 75; hotkey = KEY_Q; default_open = false
		menu_label = "🗺 Мінікарта"; compact_open = 0

	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		add_child(vb)
		_head = Widgets.H2Header.new()
		vb.add_child(_head)
		_head.set_header("Мінікарта", "")
		_minimap = MinimapWidget.new()
		_minimap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(_minimap)
		_legend = Label.new()
		_legend.add_theme_font_size_override("font_size", 11)
		_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_legend.custom_minimum_size = Vector2(200, 0)
		_legend.add_theme_color_override("font_color", Tokens.DIM)
		_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_legend.text = "● гравець · ○ імітація · ◎ у твоєму світі · ▲ за картою"
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
		_head.set_header("Мінікарта", "")
		_minimap.bind(n)
		_empty.visible = rows.is_empty()
		_empty.text = "Нікого в радіусі %s. Світ ділиться на ділянки ~760 м: хто стоїть у твоїй — грає в тому ж світі." % Fmt.distance_m(int(float(n.get("aoi_m", 0.0))))
		for i in ROWS:
			_rows[i].visible = i < rows.size()
			if i < rows.size():
				var r: Dictionary = rows[i]
				var live := str(r.get("kind", "live")) == "live"
				_names[i].text = "%s %s%s%s" % ["●" if live else "○", str(r.name), "  ◎" if bool(r.get("same_region", false)) else "", "" if live else " · імітація"]
				_names[i].add_theme_color_override("font_color", Tokens.INK if live else Tokens.TEAL)
				_dists[i].text = "%s · %s" % [Fmt.distance_m(int(r.dist_m)), str(r.dir)]
		var extra: int = int(n.get("total", 0)) - rows.size()
		var note := Fmt.realm_refusal(str(n.get("refusal", "")))
		if extra > 0:
			note = ("ще %d поза списком" % extra) + (" · " + note if note != "" else "")
		_note.text = note
		_note.visible = note != ""
		var rim := Fmt.distance_m(int(float(n.get("aoi_m", 0.0))))
		tooltip_text = "Мінікарта регіону (RealGPS): північ угорі, ти — жовта точка. Видно гравців у радіусі %s; ▲ на краю — той, хто за межею карти.\n" % rim \
			+ "Дані — з реалм-сервера; поки сервера немає, інших виживальників імітує гра."
