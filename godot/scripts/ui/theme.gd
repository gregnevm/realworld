# RealWorld — ui/theme.gd : builds ONE Godot Theme resource from Tokens (spec 0005 §2.4).
#
# Node-free build fn. Replaces main.gd's _sb_panel/_sb_bar/_mk_modal and every C_* const with a single
# Theme whose type-variations style each widget by `theme_type_variation` — no inline StyleBox anywhere
# else (R3). StyleBoxFlat/Color are allowed HERE and in tokens.gd only.
#
# Godot-4.7 gotcha (from the adversarial review): a theme_type_variation resolves only if the variation
# name is (1) registered as a variation of a built-in base via set_type_variation AND (2) given its own
# styleboxes. So we always do the two-step: register the variation, THEN set the box on the variation.
extends RefCounted
const Tokens = preload("res://scripts/ui/tokens.gd")

# Variation names the widgets ask for (kept as consts so callers can't typo them).
const V_PANEL   := &"RwPanel"      # dock panel surface
const V_MODAL   := &"RwModal"      # centered modal surface
const V_BAR     := &"RwBar"        # need-bar track / raised chip
const V_MONO    := &"MonoValue"    # right-aligned numeric Label
const V_CARD    := &"RwCard"       # translucent feed/flash/banner card over the world
const V_TIP     := &"RwTip"        # hover-inspect tooltip (amber edge: «this is about the cursor»)
const V_BARE    := &"RwBare"       # chromeless dock unit: the content (medallions) IS the HUD, no box behind it
const V_PRIMARY := &"RwPrimary"    # the ONE primary action of a screen (spawn «Грати»): amber fill, dark ink

static func build() -> Theme:
	install_emoji_fallback()
	var t := Theme.new()

	# The emoji-chained variation must sit on the THEME's default_font: ThemeDB.fallback_font alone is
	# only the engine's last resort, and the built-in default theme already carries a font, so Label
	# lookups never reach it (desktop hid this by pulling system emoji fonts; web has none -> hex boxes).
	t.default_font = ThemeDB.fallback_font

	# Dock panel surface (replaces _sb_bar).
	t.set_type_variation(V_PANEL, &"PanelContainer")
	t.set_stylebox("panel", V_PANEL, _sb_glass(Tokens.with_alpha(Tokens.PANEL, 0.86), Tokens.LINE2, 8, 12))

	# Modal surface (replaces _sb_panel / _mk_modal).
	t.set_type_variation(V_MODAL, &"PanelContainer")
	t.set_stylebox("panel", V_MODAL, _sb_glass(Tokens.with_alpha(Tokens.PANEL, 0.96), Tokens.LINE2, Tokens.R, 14))

	# Feedback cards over the world: readable on snow AND water (opaque-ish ink panel).
	t.set_type_variation(V_CARD, &"PanelContainer")
	t.set_stylebox("panel", V_CARD, _sb_glass(Tokens.with_alpha(Tokens.PANEL, 0.92), Tokens.LINE2, 6, 8))
	t.set_type_variation(V_BARE, &"PanelContainer")
	var bare := StyleBoxEmpty.new()
	bare.set_content_margin_all(2)
	t.set_stylebox("panel", V_BARE, bare)
	t.set_type_variation(V_TIP, &"PanelContainer")
	t.set_stylebox("panel", V_TIP, _sb(Color(Tokens.PANEL2.r, Tokens.PANEL2.g, Tokens.PANEL2.b, 0.96), Tokens.AMBER, 6, 8))

	# Need-bar track (raised inset).
	t.set_type_variation(V_BAR, &"PanelContainer")
	t.set_stylebox("panel", V_BAR, _sb(Color("0c1116"), Tokens.LINE, 20, 0))

	# Numeric labels (mono/tabular look; the actual tabular figures depend on the bundled font, see below).
	t.set_type_variation(V_MONO, &"Label")
	t.set_color("font_color", V_MONO, Tokens.INK)
	t.set_font_size("font_size", V_MONO, 12)

	# Base Label/Button colors so the whole HUD reads from the token palette.
	t.set_color("font_color", "Label", Tokens.INK)
	t.set_color("font_color", "Button", Tokens.INK)
	t.set_color("font_hover_color", "Button", Tokens.AMBER)
	t.set_color("font_focus_color", "Button", Tokens.AMBER)
	t.set_stylebox("normal", "Button", _sb(Tokens.PANEL2, Tokens.LINE2, 6, 6))
	t.set_stylebox("hover", "Button", _sb(Tokens.PANEL2, Tokens.AMBER, 6, 6))
	t.set_stylebox("pressed", "Button", _sb(Tokens.PANEL, Tokens.AMBER, 6, 6))
	t.set_stylebox("focus", "Button", _sb_outline(Tokens.AMBER, 6))
	t.set_type_variation(V_PRIMARY, &"Button")
	t.set_stylebox("normal", V_PRIMARY, _sb(Tokens.AMBER, Tokens.AMBER, 8, 10))
	t.set_stylebox("hover", V_PRIMARY, _sb(Tokens.AMBER.lightened(0.12), Tokens.INK, 8, 10))
	t.set_stylebox("pressed", V_PRIMARY, _sb(Tokens.AMBER.darkened(0.15), Tokens.AMBER, 8, 10))
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(st, V_PRIMARY, Tokens.BG)
	return t

# Web builds have no system emoji font (desktop silently falls back to Segoe/Apple emoji; the web
# canvas cannot), so every icon glyph used to render as a box. Bundle monochrome NotoEmoji (OFL,
# assets/fonts/) and chain it behind the built-in default via ThemeDB.fallback_font — lives HERE
# because fonts are theme concern (R3). load_dynamic_font() reads the .ttf bytes directly, so
# headless test runs never touch the importer; the raw .ttf ships in the PCK via include_filter.
# Exported builds ship the ttf as an IMPORTED resource behind a path remap (FileAccess can't see it,
# ResourceLoader can); fresh checkouts / headless test runs have only the raw file (no import cache,
# so ResourceLoader can't see it but FileAccess can). Try both — each environment satisfies one.
static func _load_emoji_font() -> Font:
	var path := "res://assets/fonts/NotoEmoji-Regular.ttf"
	if ResourceLoader.exists(path):
		var res: Variant = load(path)
		if res is Font:
			return res
	if FileAccess.file_exists(path):
		var ff := FontFile.new()
		if ff.load_dynamic_font(path) == OK:
			return ff
	return null

# Typography (2026-11): Rubik (OFL, Cyrillic) is the body face, Oswald (OFL, condensed) the display face for
# headers/titles/big numbers — the engine default read as «prototype». Chain: Rubik → built-in default (any
# glyph Rubik lacks) → NotoEmoji (icons). Both faces are variable fonts; weight is set per variation.
const BODY_FONT := "res://assets/fonts/Rubik-Variable.ttf"
const DISPLAY_FONT := "res://assets/fonts/Oswald-Variable.ttf"
static var _display: Font = null

static func install_emoji_fallback() -> void:
	var base: Font = ThemeDB.fallback_font
	if base is FontVariation:
		return   # already installed (scene reload / respawn re-enters _ready)
	var emoji: Font = _load_emoji_font()
	var chain: Array[Font] = [base]
	if emoji != null:
		chain.append(emoji)
	var body: Font = _load_font(BODY_FONT)
	var f := FontVariation.new()
	if body != null:
		f.base_font = body
		f.variation_opentype = {"wght": 500}
		f.fallbacks = chain
	else:
		f.base_font = base
		f.fallbacks = [emoji] if emoji != null else []
	ThemeDB.fallback_font = f
	var disp: Font = _load_font(DISPLAY_FONT)
	if disp != null:
		var dv := FontVariation.new()
		dv.base_font = disp
		dv.variation_opentype = {"wght": 560}
		dv.fallbacks = [f]
		_display = dv

# Display face (Oswald) for headers, titles and hero numbers; the body face when it is missing.
static func display_font() -> Font:
	if _display == null:
		install_emoji_fallback()
	return _display if _display != null else ThemeDB.fallback_font

static func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var res: Variant = load(path)
		if res is Font:
			return res
	if FileAccess.file_exists(path):
		var ff := FontFile.new()
		if ff.load_dynamic_font(path) == OK:
			return ff
	return null

# StyleBoxFlat factory (allowed in this file per R3).
static func _sb(bg: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s

# «Glass» surface for panels floating over the world: translucent ground colour, a brighter hairline on top
# (light from above), a soft drop shadow that lifts the panel off the map. Pure StyleBox — no per-frame cost.
static func _sb_glass(bg: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var s := _sb(bg, border, radius, pad)
	s.border_width_top = 2
	s.border_color = border
	s.shadow_color = Color(0, 0, 0, 0.42)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 3)
	return s

# Transparent box with just a focus-visible outline (a11y focus ring, design-system §0.6 / R7-adjacent).
static func _sb_outline(border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	return s
