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

static func build() -> Theme:
	var t := Theme.new()

	# Dock panel surface (replaces _sb_bar).
	t.set_type_variation(V_PANEL, &"PanelContainer")
	t.set_stylebox("panel", V_PANEL, _sb(Tokens.PANEL, Tokens.LINE, 6, 10))

	# Modal surface (replaces _sb_panel / _mk_modal).
	t.set_type_variation(V_MODAL, &"PanelContainer")
	t.set_stylebox("panel", V_MODAL, _sb(Color(Tokens.PANEL.r, Tokens.PANEL.g, Tokens.PANEL.b, 0.97), Tokens.LINE2, Tokens.R, 14))

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
	return t

# StyleBoxFlat factory (allowed in this file per R3).
static func _sb(bg: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s

# Transparent box with just a focus-visible outline (a11y focus ring, design-system §0.6 / R7-adjacent).
static func _sb_outline(border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	return s
