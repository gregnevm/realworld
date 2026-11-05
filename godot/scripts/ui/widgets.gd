# RealWorld — ui/widgets.gd : the finite reusable primitive vocabulary (spec 0005 §2.11).
#
# Every concrete widget is an inner class extending the preloaded WidgetBase.Widget (the repo's
# inner-class + preload idiom; zero class_name). Names are 1:1 with design-system.md §4 / hud.html so
# parity is checkable element-by-element. Colors come ONLY from Tokens (R3) — no Color()/StyleBox here.
# Every public mutator calls build_once() first so the widget builds on first use, headlessly (§3.3).
extends RefCounted

const WidgetBase = preload("res://scripts/ui/widget.gd")
const Tokens = preload("res://scripts/ui/tokens.gd")
const UITheme = preload("res://scripts/ui/theme.gd")
const GameData = preload("res://scripts/data.gd")
const Fmt = preload("res://scripts/ui/format.gd")
const ArtIcons = preload("res://scripts/ui/art_icons.gd")


# ---- StatRow (.stock .r): glyph · label · right-aligned mono value (Stock / Equipment / Agents) ----
class StatRow extends WidgetBase.Widget:
	var _glyph: Label
	var _icon: TextureRect         # generated art icon; replaces the emoji glyph when a PNG exists
	var _label: Label
	var _value: Label
	var value := ""
	func _build() -> void:
		custom_minimum_size = Vector2(0, 24)
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.add_theme_constant_override("separation", 6)
		add_child(hb)
		_glyph = Label.new()
		hb.add_child(_glyph)
		_icon = TextureRect.new()
		_icon.custom_minimum_size = Vector2(22, 22)
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon.visible = false
		hb.add_child(_icon)
		_label = Label.new()
		_label.add_theme_color_override("font_color", Tokens.MUT)
		hb.add_child(_label)
		_value = Label.new()
		_value.theme_type_variation = UITheme.V_MONO
		_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# long readouts (condition lines, catalogue labels) trim with an ellipsis inside the dock
		# instead of pushing the panel wider; the full text stays reachable as the hover tooltip
		_value.clip_text = true
		_value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_value.mouse_filter = Control.MOUSE_FILTER_PASS
		hb.add_child(_value)
	func set_glyph_res(res: String) -> void:
		build_once()
		var info: Dictionary = GameData.RES[res]
		_glyph.text = String(info.icon)
		_show_icon(ArtIcons.res(res))
		_label.text = String(info.label)
		if not _label.visible:
			tooltip_text = _label.text
		_value.add_theme_color_override("font_color", Tokens.res(res))
	# Compact tile: icon + number only; the label becomes the hover tooltip (dense readouts).
	func set_compact(on: bool) -> void:
		build_once()
		_label.visible = not on
		custom_minimum_size = Vector2(84, 24) if on else Vector2(0, 24)
		tooltip_text = _label.text if on else ""
		_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	func set_row(glyph: String, label: String, val: String, icon_id: String = "") -> void:
		build_once()
		_glyph.text = glyph
		_show_icon(ArtIcons.res(icon_id) if icon_id != "" else ArtIcons.for_glyph(glyph))
		_label.text = label
		if not _label.visible:
			tooltip_text = label
		set_value(val)
	# Art icon when we have one (glyph hidden), emoji glyph otherwise (R11 fallback).
	func _show_icon(tex: Texture2D) -> void:
		_icon.texture = tex
		_icon.visible = tex != null
		_glyph.visible = tex == null
	func set_value(v) -> void:
		build_once()
		value = str(v)
		_value.text = value
		_value.tooltip_text = value if value.length() > 12 else ""
	func bind(vm) -> void:
		if vm is Dictionary and vm.has("value"):
			set_value(vm.value)

# ---- NeedBar (.need): icon · track(fill) · mono value — color+icon+number always (R11) ----
class NeedBar extends WidgetBase.Widget:
	var icon := ""
	var value := ""
	var state: StringName = &"good"
	var _pct := 0.0
	var _shown := -1.0             # eased fill actually drawn (ease-out toward _pct; snaps on first bind)
	var _pulse := 0.0
	var _icon: Label
	var _art: TextureRect
	var _value: Label
	var _track: Control
	func _build() -> void:
		custom_minimum_size = Vector2(0, 22)
		set_process(true)
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.add_theme_constant_override("separation", 8)
		add_child(hb)
		_icon = Label.new()
		_icon.custom_minimum_size = Vector2(20, 0)
		hb.add_child(_icon)
		_art = TextureRect.new()
		_art.custom_minimum_size = Vector2(22, 22)
		_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_art.pivot_offset = Vector2(11, 11)
		_art.visible = false
		hb.add_child(_art)
		_track = Control.new()
		_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_track.custom_minimum_size = Vector2(0, 10)
		_track.draw.connect(_draw_track)
		hb.add_child(_track)
		_value = Label.new()
		_value.theme_type_variation = UITheme.V_MONO
		_value.custom_minimum_size = Vector2(30, 0)
		_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hb.add_child(_value)
	func _draw_track() -> void:
		var w: float = _track.size.x
		var h: float = _track.size.y
		_track.draw_rect(Rect2(0, 0, w, h), Tokens.PANEL2)
		var fill: Color = Tokens.urgency(state)
		if state == &"crit":
			fill = fill.lerp(Tokens.PANEL2, 0.35 * _pulse)   # slow blink: urgency is felt, not only coloured (R11)
		_track.draw_rect(Rect2(0, 0, w * clampf((_shown if _shown >= 0.0 else _pct) / 100.0, 0, 1), h), fill)
	# Ease-out fill (~250 ms feel) + critical pulse. View-only time: no sim state, no RNG.
	func _process(delta: float) -> void:
		if _shown < 0.0:
			return
		var moving: bool = absf(_shown - _pct) > 0.05
		if moving:
			_shown = lerpf(_shown, _pct, 1.0 - exp(-12.0 * delta))
		if state == &"crit":
			_pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
			if _art != null and _art.visible:
				var sc: float = 1.0 + 0.08 * _pulse
				_art.scale = Vector2(sc, sc)
		elif _art != null and _art.scale != Vector2.ONE:
			_art.scale = Vector2.ONE
		if (moving or state == &"crit") and _track != null:
			_track.queue_redraw()
	func bind(vm) -> void:
		build_once()
		if not (vm is Dictionary):
			return
		icon = String(vm.get("icon", ""))
		_pct = float(vm.get("pct", 0))
		state = StringName(vm.get("state", &"good"))
		value = str(int(_pct))
		if _shown < 0.0:
			_shown = _pct
		_icon.text = icon
		var tex: Texture2D = ArtIcons.for_glyph(icon)
		_art.texture = tex
		_art.visible = tex != null
		_icon.visible = tex == null
		_value.text = value
		_value.add_theme_color_override("font_color", Tokens.urgency(state))
		if _track != null:
			_track.queue_redraw()

# ---- Gauge (.gauge/.phases): a SEGMENTED horizontal meter WITH the phase-label strip above
# (design-system §4 / hud.html `.phases` спокій·рейд·облога·сплеск; spec 0005 §2.11 bind(value,phases)) ----
class Gauge extends WidgetBase.Widget:
	var value := ""
	var _fill := 0.0
	var _color: Color = Tokens.GOOD
	var _bar: Control
	var _phase_labels: Array = []       # up to 4 Labels, spread space-between over the fill
	func _build() -> void:
		custom_minimum_size = Vector2(0, 26)
		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.add_theme_constant_override("separation", 2)
		add_child(vb)
		var phases := HBoxContainer.new()
		vb.add_child(phases)
		for i in 4:
			var l := Label.new()
			l.add_theme_font_size_override("font_size", 9)
			l.add_theme_color_override("font_color", Tokens.DIM)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.horizontal_alignment = [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT][i]
			phases.add_child(l)
			_phase_labels.append(l)
		_bar = Control.new()
		_bar.custom_minimum_size = Vector2(0, 12)
		_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_bar.draw.connect(_draw_bar)
		vb.add_child(_bar)
	func _draw_bar() -> void:
		var w: float = _bar.size.x
		var h: float = _bar.size.y
		_bar.draw_rect(Rect2(0, 0, w, h), Tokens.PANEL2)
		_bar.draw_rect(Rect2(0, 0, w * clampf(_fill, 0.04, 1.0), h), _color)
		for i in range(1, 4):                                  # segment ticks at the phase thresholds
			var x: float = w * float(i) / 4.0
			_bar.draw_line(Vector2(x, 0), Vector2(x, h), Tokens.LINE, 1.0)
	func bind(vm) -> void:
		build_once()
		if not (vm is Dictionary):
			return
		_fill = clampf(float(vm.get("fill", 0.0)), 0.0, 1.0)
		_color = Tokens.urgency(StringName(vm.get("state", &"good")))
		value = str(vm.get("value", ""))
		var phases: Array = vm.get("phases", [])              # ["спокій","рейд","облога","сплеск"]
		var active: int = int(vm.get("active", -1))           # highlighted phase index
		for i in _phase_labels.size():
			if i < phases.size():
				_phase_labels[i].text = String(phases[i])
				_phase_labels[i].add_theme_color_override("font_color", Tokens.WARN if i == active else Tokens.DIM)
		if _bar != null:
			_bar.queue_redraw()

# ---- Card (.card .t-*): feed item with a category-colored left border ----
class Card extends WidgetBase.Widget:
	var _stripe: ColorRect
	var _text: Label
	func _build() -> void:
		custom_minimum_size = Vector2(0, 20)
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.add_theme_constant_override("separation", 6)
		add_child(hb)
		_stripe = ColorRect.new()
		_stripe.custom_minimum_size = Vector2(3, 0)
		hb.add_child(_stripe)
		_text = Label.new()
		_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(_text)
	func set_card(cls: String, text: String) -> void:
		build_once()
		_stripe.color = Tokens.category(cls)
		_text.text = text
		_text.add_theme_color_override("font_color", Tokens.INK)
	func bind(vm) -> void:
		if vm is Dictionary:
			set_card(String(vm.get("cls", "")), String(vm.get("text", "")))

# ---- H2Header: the panel h2 with the letter-spacing the locked design wants (§2.4 custom-draw) ----
class H2Header extends WidgetBase.Widget:
	signal toggled(collapsed: bool)      # a click on the header folds/unfolds the panel body (progressive disclosure)
	var _text := ""
	var _tag := ""
	var collapsed := false
	var collapsible := false             # set by the panel base once it has split header from body
	func _build() -> void:
		custom_minimum_size = Vector2(0, 20)
		draw.connect(_on_draw)
		gui_input.connect(_on_input)
	func _on_input(ev: InputEvent) -> void:
		if collapsible and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			set_collapsed(not collapsed)
	func set_collapsed(v: bool) -> void:
		collapsed = v
		queue_redraw()
		toggled.emit(v)
	func _notification(what: int) -> void:
		if what == NOTIFICATION_READY or what == NOTIFICATION_ENTER_TREE:
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if collapsible else Control.CURSOR_ARROW
	func set_header(text: String, tag := "") -> void:
		build_once()
		_text = text.to_upper()
		_tag = tag
		queue_redraw()
	func _on_draw() -> void:
		var f: Font = UITheme.display_font()
		var x := 0.0
		if collapsible:   # chevron: ▾ open / ▸ folded — a shape, not just colour (R11)
			var cy := 8.0
			var pts := PackedVector2Array([Vector2(1, cy - 3), Vector2(9, cy - 3), Vector2(5, cy + 3)]) if not collapsed \
				else PackedVector2Array([Vector2(2, cy - 4), Vector2(2, cy + 4), Vector2(8, cy)])
			draw_colored_polygon(pts, Tokens.MUT)
			x = 16.0
		for ch in _text:
			draw_string(f, Vector2(x, 13), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Tokens.INK)
			x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 1.4   # ~.11em tracking
		# dev-facing english tags (need/stock/tech) are metadata and never drawn; a COUNT tag («5/10») is
		# player information and is drawn right-aligned in the display face
		if _tag != "" and _tag.to_lower() == _tag.to_upper():
			draw_string(f, Vector2(size.x - 64, 13), _tag, HORIZONTAL_ALIGNMENT_RIGHT, 64, 13, Tokens.AMBER)

# ---- BuildSlot (.slot .sel/.no): number · glyph · selected/locked/affordable state ----
class BuildSlot extends WidgetBase.Widget:
	var key := ""
	var _btn: Button
	signal picked(key: String)
	func _build() -> void:
		custom_minimum_size = Vector2(80, 46)
		_btn = Button.new()
		_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		_btn.pressed.connect(func(): picked.emit(key))
		add_child(_btn)
	func bind(vm) -> void:
		build_once()
		if not (vm is Dictionary):
			return
		key = String(vm.get("key", ""))
		_btn.text = "%s\n%s" % [String(vm.get("num", "")), String(vm.get("name", ""))]
		_btn.button_pressed = bool(vm.get("selected", false))
		_btn.disabled = bool(vm.get("locked", false))
		_btn.modulate = Tokens.WHITE if bool(vm.get("afford", true)) else Tokens.DIMMED

# ---- ChoiceRow: a full-width action row (label · right-aligned meta · click -> picked(id)). The
# research/catalog pick primitive: it emits a semantic id and the PANEL turns that into an intent, so
# R9 stays clean (a widget never names a sim mutator). Tooltip carries the R5 explain. ----
class ChoiceRow extends WidgetBase.Widget:
	var id: StringName = &""
	var _btn: Button
	signal picked(id: StringName)
	func _build() -> void:
		_btn = Button.new()
		_btn.add_theme_font_size_override("font_size", 13)   # compact rows: the LEFT dock is tall
		_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_btn.clip_text = true
		_btn.pressed.connect(func(): picked.emit(id))
		add_child(_btn)
		_btn.minimum_size_changed.connect(_fit)
		_fit()
	# a themed Button's minimum height (font + style padding) is known only once the theme reaches it in
	# the tree; a hard-coded 22px row let the button overflow onto the next VBox child (the «Доступні»
	# list drawing over the «Черга» header) — so the row tracks the button's own minimum instead
	func _fit() -> void:
		custom_minimum_size = Vector2(0, maxf(22.0, _btn.get_combined_minimum_size().y))
	func bind(vm) -> void:
		build_once()
		if not (vm is Dictionary):
			return
		id = StringName(vm.get("id", ""))
		var meta := String(vm.get("meta", ""))
		_btn.text = ("%s   %s" % [String(vm.get("label", "")), meta]) if meta != "" else String(vm.get("label", ""))
		_btn.tooltip_text = String(vm.get("tip", ""))
		_btn.disabled = bool(vm.get("disabled", false))
		_btn.modulate = Tokens.DIMMED if bool(vm.get("dim", false)) else Tokens.WHITE
		visible = bool(vm.get("shown", true))

# ---- CatalogSlot: a clickable content-tree row (build/craft/research action); emits chosen(id) ----
# bind({id, label, sub, enabled}). An empty id hides the slot so a fixed-size pool (R2) shows a page.
class CatalogSlot extends WidgetBase.Widget:
	var item_id: StringName = &""
	var _btn: Button
	signal chosen(id: StringName)
	func _build() -> void:
		_btn = Button.new()
		_btn.add_theme_font_size_override("font_size", 13)
		_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_btn.pressed.connect(func(): chosen.emit(item_id))
		add_child(_btn)
		_btn.minimum_size_changed.connect(_fit)
		_fit()
	# a themed Button's minimum height (font + style padding) is known only once the theme reaches it in
	# the tree; a hard-coded 22px row let the button overflow onto the next VBox child (the «Доступні»
	# list drawing over the «Черга» header) — so the row tracks the button's own minimum instead
	func _fit() -> void:
		custom_minimum_size = Vector2(0, maxf(22.0, _btn.get_combined_minimum_size().y))
	func bind(vm) -> void:
		build_once()
		if not (vm is Dictionary):
			return
		item_id = StringName(vm.get("id", &""))
		var lbl := String(vm.get("label", ""))
		var sub := String(vm.get("sub", ""))
		_btn.text = ("%s   %s" % [lbl, sub]) if sub != "" else lbl
		_btn.disabled = not bool(vm.get("enabled", true))
		_btn.tooltip_text = String(vm.get("tip", ""))
		_btn.modulate = Tokens.DIMMED if _btn.disabled else Tokens.WHITE
		visible = item_id != &""

# ---- OverlayChip (.ov-chip .on): label · hotkey · on-state (toolbar toggle for a map overlay) ----
class OverlayChip extends WidgetBase.Widget:
	var overlay_id: StringName = &""
	var _btn: Button
	signal toggled_overlay(id: StringName)
	func _build() -> void:
		_btn = Button.new()
		_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		_btn.pressed.connect(func(): toggled_overlay.emit(overlay_id))
		add_child(_btn)
	func setup(id: StringName, label: String, key: String) -> void:
		build_once()
		overlay_id = id
		_btn.text = "%s [%s]" % [label, key]
	func bind(vm) -> void:
		build_once()
		if vm is Dictionary:
			_btn.button_pressed = bool(vm.get("on", false))

# ---- LegendBox: bottom-left of the viewport; grows a row per active overlay (§3) ----
class LegendBox extends WidgetBase.Widget:
	var _list: VBoxContainer
	func _build() -> void:
		_list = VBoxContainer.new()
		_list.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_list)
	func set_rows(rows: Array) -> void:
		build_once()
		for c in _list.get_children():
			_list.remove_child(c)
			c.queue_free()
		for r in rows:
			var lbl := Label.new()
			lbl.text = "%s %s" % [String(r.get("icon", "▪")), String(r.get("label", ""))]
			lbl.add_theme_color_override("font_color", Tokens.MUT)
			lbl.add_theme_font_size_override("font_size", 11)
			_list.add_child(lbl)

# ---- Feedback subscribers: connect ONCE, disconnect in _exit_tree (R8 / §2.7 cycle-leak guard) ----
# A card over the world: translucent ink panel + category stripe + wrapped text. Plain containers, so
# the card's height follows its text (a fixed-height Control would let two-line messages overlap).
class CardKit extends RefCounted:
	static func make(width: float, font_size: int = 13) -> Dictionary:
		var pc := PanelContainer.new()
		pc.theme_type_variation = UITheme.V_CARD
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(hb)
		var stripe := ColorRect.new()
		stripe.custom_minimum_size = Vector2(3, 0)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(stripe)
		var lbl := Label.new()
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(width, 0)
		lbl.add_theme_font_size_override("font_size", font_size)
		hb.add_child(lbl)
		return {"panel": pc, "stripe": stripe, "label": lbl}

class BannerWidget extends WidgetBase.Widget:
	var _bus: Variant
	var _card: Dictionary = {}
	var status: StringName = &"none"
	func _build() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card = CardKit.make(0.0)
		var lbl: Label = _card.label
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.add_theme_font_size_override("font_size", 17)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_card.panel)
		visible = false
	func subscribe(bus) -> void:
		build_once()
		_bus = bus
		bus.banner.connect(_on_banner)
	func _on_banner(evt: Dictionary) -> void:
		var text := String(evt.get("params", {}).get("text", ""))
		status = StringName(evt.get("status", &"none"))
		_card.label.text = text
		# R11: the banner text already carries its icon; the color echoes the urgency
		var col: Color = Tokens.CRIT if status == &"raid_active" else (Tokens.WARN if status == &"raid_incoming" else Tokens.TEAL)
		_card.label.add_theme_color_override("font_color", col)
		_card.stripe.color = col
		visible = text != ""
	func _exit_tree() -> void:
		if _bus != null and _bus.banner.is_connected(_on_banner):
			_bus.banner.disconnect(_on_banner)

class FlashWidget extends WidgetBase.Widget:
	const HOLD := 2.2
	var _bus: Variant
	var _card: Dictionary = {}
	var _t := 0.0
	var text := ""
	func _build() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card = CardKit.make(0.0)
		var lbl: Label = _card.label
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.add_theme_color_override("font_color", Tokens.WARN)
		_card.stripe.color = Tokens.WARN
		add_child(_card.panel)
		visible = false
		set_process(true)
	func subscribe(bus) -> void:
		build_once()
		_bus = bus
		bus.flash.connect(_on_flash)
	func _on_flash(evt: Dictionary) -> void:
		text = String(evt.get("params", {}).get("text", ""))
		_card.label.text = text
		_t = HOLD
		modulate = Tokens.WHITE
		visible = text != ""
	func _process(dt: float) -> void:
		if _t > 0.0:
			_t = maxf(0.0, _t - dt)
			if _t < 0.5:
				modulate = Tokens.with_alpha(Tokens.WHITE, _t / 0.5)   # a short fade, not a pop
			if _t == 0.0:
				visible = false
	# Anchor the refusal to WHO it is about (gamedev §5: a flash floating mid-screen «I didn't point at
	# anything» — and it covered the enemy's intent badge): centred just above the hero's head, clamped
	# on screen. A negative anchor keeps the authored pin (fakes / tests / no hero on screen).
	func follow(anchor: Vector2, screen: Vector2) -> void:
		if not visible or anchor.x < 0.0:
			return
		var sz: Vector2 = (_card.panel as Control).get_combined_minimum_size()
		var p := anchor - Vector2(sz.x * 0.5, sz.y + 10.0)
		p.x = clampf(p.x, 4.0, maxf(4.0, screen.x - sz.x - 4.0))
		p.y = clampf(p.y, 56.0, maxf(56.0, screen.y - sz.y - 4.0))
		WidgetBase.Widget.pin_at(self, p)
	func _exit_tree() -> void:
		if _bus != null and _bus.flash.is_connected(_on_flash):
			_bus.flash.disconnect(_on_flash)

# The event feed (design-system §2 «event feed ▸ toasts / scrolling log», bottom-right): a FIXED pool
# of cards (R2 — never add/free per message); the newest message sits lowest, older ones rise and
# fade, then hide. Text is the sim's own feed (R10: drained by the bus, never read here directly).
class FeedWidget extends WidgetBase.Widget:
	const POOL := 5            # sized to sit under the default RIGHT dock (Stock + Balance) at 720p
	const FADE_AT := 4.0       # seconds a card stays fully opaque
	const GONE_AT := 5.5       # …then fades out by this age
	const WIDTH := 290.0
	const MAX_H := 205.0       # never climb into the RIGHT dock above: the oldest cards give way
	var _max_cards := 3        # compact (phones): fewer, narrower cards — the map needs the room
	var _max_h := MAX_H
	var _bus: Variant
	var _list: VBoxContainer
	var _cards: Array = []     # pool of {panel, stripe, label}, built ONCE
	var _items: Array = []     # newest LAST: {cls, text, age}
	func _build() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list = VBoxContainer.new()
		_list.add_theme_constant_override("separation", 4)
		_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# grow up-left from this widget's (bottom-right) anchor point
		_list.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, false)
		_list.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_list.grow_vertical = Control.GROW_DIRECTION_BEGIN
		add_child(_list)
		for i in POOL:
			var c: Dictionary = CardKit.make(WIDTH, 12)
			_list.add_child(c.panel)
			c.panel.visible = false
			_cards.append(c)
		set_process(true)
	func subscribe(bus) -> void:
		build_once()
		_bus = bus
		bus.feed.connect(_on_feed)
	func set_compact(on: bool) -> void:
		build_once()
		_max_cards = 2 if on else 3
		_max_h = 96.0 if on else MAX_H
		for c in _cards:
			c.label.custom_minimum_size = Vector2(230.0 if on else WIDTH, 0)
	func _on_feed(evt: Dictionary) -> void:
		var txt := String(evt.get("text", ""))
		# an immediate repeat folds into the last card (×N) and re-arms it instead of stacking duplicates
		if not _items.is_empty() and String(_items[-1].text) == txt and float(_items[-1].age) < FADE_AT:
			_items[-1].n = int(_items[-1].get("n", 1)) + 1
			_items[-1].age = 0.0
			_rebind()
			return
		_items.append({"cls": String(evt.get("cls", "")), "text": txt, "age": 0.0, "n": 1})
		while _items.size() > POOL:
			_items.remove_at(0)
		_rebind()
	func visible_texts() -> Array:
		var out: Array = []
		for it in _items:
			if float(it.age) < GONE_AT:
				out.append(String(it.text))
		return out
	func _process(dt: float) -> void:
		if _items.is_empty():
			return
		for it in _items:
			it.age = float(it.age) + dt
		while not _items.is_empty() and float(_items[0].age) >= GONE_AT:
			_items.remove_at(0)
		_rebind()
	func _rebind() -> void:
		# pool slot i shows item i (oldest on top, newest lowest — next to the action the player took);
		# walking newest-first, a card that would push the stack past MAX_H hides with all older ones
		var used := 0.0
		for i in range(_cards.size() - 1, -1, -1):
			var c: Dictionary = _cards[i]
			if i >= _items.size():
				c.panel.visible = false
				continue
			var it: Dictionary = _items[i]
			var reps: int = int(it.get("n", 1))
			c.label.text = String(it.text) if reps <= 1 else "%s  ×%d" % [String(it.text), reps]
			c.stripe.color = Tokens.category(String(it.cls))
			var a: float = 1.0 if float(it.age) < FADE_AT else clampf(1.0 - (float(it.age) - FADE_AT) / (GONE_AT - FADE_AT), 0.0, 1.0)
			# arrival: ease-out-cubic fade + small pop over 0.25 s so a new message is noticed, not just appears
			var tin: float = clampf(float(it.age) / 0.25, 0.0, 1.0)
			var ein: float = 1.0 - pow(1.0 - tin, 3.0)
			c.panel.modulate = Tokens.with_alpha(Tokens.WHITE, a * ein)
			c.panel.pivot_offset = Vector2(c.panel.size.x, c.panel.size.y * 0.5)
			var pop: float = 1.0 + 0.07 * (1.0 - ein)
			c.panel.scale = Vector2(pop, pop)
			var h: float = c.panel.get_combined_minimum_size().y + 4.0
			var rank: int = _items.size() - 1 - i              # 0 = newest
			c.panel.visible = rank < _max_cards and (used == 0.0 or used + h <= _max_h)
			used += h
	func _exit_tree() -> void:
		if _bus != null and _bus.feed.is_connected(_on_feed):
			_bus.feed.disconnect(_on_feed)

# ---- HoverTip (design-system §5 «inspect = hover»): a cursor-following card bound from the
# snapshot's inspect slice (value data). Fixed pool of line labels (R2); placed via pin_at (R7). ----
class HoverTip extends WidgetBase.Widget:
	const LINES := 4
	var _panel: PanelContainer
	var _title: Label
	var _lines: Array = []
	var _hint: Label
	var shown := false
	var title := ""
	func _build() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel = PanelContainer.new()
		_panel.theme_type_variation = UITheme.V_TIP
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_panel)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(vb)
		_title = Label.new()
		_title.add_theme_font_size_override("font_size", 14)
		vb.add_child(_title)
		for i in LINES:
			var l := Label.new()
			l.add_theme_font_size_override("font_size", 12)
			l.add_theme_color_override("font_color", Tokens.MUT)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(260, 0)
			vb.add_child(l)
			_lines.append(l)
		_hint = Label.new()
		_hint.add_theme_font_size_override("font_size", 11)
		_hint.add_theme_color_override("font_color", Tokens.AMBER)
		_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_hint.custom_minimum_size = Vector2(260, 0)
		vb.add_child(_hint)
		visible = false
	func bind(vm) -> void:
		build_once()
		shown = vm is Dictionary and bool(vm.get("shown", false))
		visible = shown
		if not shown:
			return
		title = String(vm.get("title", ""))
		_title.text = title
		_title.add_theme_color_override("font_color", Tokens.urgency(StringName(vm.get("state", &"info"))))
		var lines: Array = vm.get("lines", [])
		for i in _lines.size():
			_lines[i].visible = i < lines.size()
			if i < lines.size():
				_lines[i].text = String(lines[i])
		_hint.text = String(vm.get("hint", ""))
		_hint.visible = _hint.text != ""
	# Follow the cursor, flipping to the other side near the right/bottom edges (never off-screen).
	func follow(mouse: Vector2, screen: Vector2, touch: bool = false) -> void:
		if not shown:
			return
		var sz: Vector2 = _panel.get_combined_minimum_size()
		var p := mouse + Vector2(18, 18)
		if touch:
			p = mouse + Vector2(-sz.x * 0.5, -sz.y - 44.0)   # above the finger, which hides what's under it
			if p.y < 4.0:
				p.y = mouse.y + 44.0
		if p.x + sz.x > screen.x - 4.0:
			p.x = mouse.x - sz.x - 12.0
		if p.y + sz.y > screen.y - 4.0:
			p.y = mouse.y - sz.y - 12.0
		WidgetBase.Widget.pin_at(self, Vector2(maxf(4.0, p.x), maxf(4.0, p.y)))

# ---- PanelMenu (touch ☰): every panel/overlay toggle as a finger-sized button grid — the phone's
# stand-in for the hotkeys. Built ONCE from the registries' own metadata (menu_label); it only emits
# chosen(kind, id) — the entry scene flips the registry, never this widget (R9 spirit). ----
class PanelMenu extends WidgetBase.Widget:
	signal chosen(kind: StringName, id: StringName)
	signal closed
	var _grid: GridContainer
	var _btns: Dictionary = {}   # "kind:id" -> Button
	func _build() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pc := PanelContainer.new()
		pc.theme_type_variation = UITheme.V_MODAL
		pc.set_anchors_preset(Control.PRESET_CENTER)
		pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
		pc.grow_vertical = Control.GROW_DIRECTION_BOTH
		add_child(pc)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 8)
		pc.add_child(vb)
		var head := HBoxContainer.new()
		vb.add_child(head)
		var title := Label.new()
		title.text = "Панелі та оверлеї"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_color_override("font_color", Tokens.AMBER)
		head.add_child(title)
		var x := Button.new()
		x.text = "✖"
		x.custom_minimum_size = Vector2(44, 38)
		x.focus_mode = Control.FOCUS_NONE
		x.pressed.connect(func() -> void: closed.emit())
		head.add_child(x)
		_grid = GridContainer.new()
		_grid.columns = 3
		_grid.add_theme_constant_override("h_separation", 6)
		_grid.add_theme_constant_override("v_separation", 6)
		vb.add_child(_grid)
	# entries: [{kind: &"panel"|&"overlay", id, label}] — called once by the entry scene
	func setup(entries: Array) -> void:
		build_once()
		for e in entries:
			var b := Button.new()
			b.toggle_mode = true
			b.text = String(e.label)
			b.custom_minimum_size = Vector2(170, 42)
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(func() -> void: chosen.emit(StringName(e.kind), StringName(e.id)))
			_grid.add_child(b)
			_btns["%s:%s" % [String(e.kind), String(e.id)]] = b
	# states: "kind:id" -> bool (is that panel/overlay showing right now)
	func bind(states) -> void:
		build_once()
		if not (states is Dictionary):
			return
		for k in _btns:
			_btns[k].set_pressed_no_signal(bool(states.get(k, false)))
	func entry_count() -> int:
		return _btns.size()



# ---- Medallion: the mobile-HUD status/resource token (round icon + state ring + number badge) ----
# Replaces progress BARS (research 2026-11: mobile survival HUDs show needs as icon tokens, state by ring
# colour + shape + number, urgency by motion — never colour alone, R11). Custom-drawn, build-once (R2):
# bind() only swaps values. Size follows the frame (desktop 46 px; touch scale enlarges the whole UI).
class Medallion extends WidgetBase.Widget:
	const D := 46.0
	var icon_tex: Texture2D = null
	var glyph := ""
	var value := ""
	var label := ""
	var state: StringName = &"good"     # good | warn | crit | info
	var badge := true
	var quiet_when_good := false        # needs: in the normal band the token is a dim icon, no number (The Long Dark / Don't Starve)
	var trend := 0                      # -1 falling / 0 steady / +1 rising (vs a ~3 s moving average) — direction beats the exact number
	# A word under the token (gamedev §5: icons+numbers alone were not decodable — «5/0/8/0, which
	# resources?»). The panel decides WHEN: names during the first days, then only while the state is off.
	var caption := ""
	var _ema := NAN
	var _pulse := 0.0
	const CAP_H := 15.0
	func _build() -> void:
		custom_minimum_size = Vector2(D + 12.0, D + 12.0 + CAP_H)
		mouse_filter = Control.MOUSE_FILTER_PASS
		draw.connect(_on_draw)
		set_process(true)
	func set_token(tex: Texture2D, glyph_fallback: String, lbl: String) -> void:
		build_once()
		icon_tex = tex
		glyph = glyph_fallback
		label = lbl
		queue_redraw()
	func bind(vm) -> void:
		build_once()
		if not (vm is Dictionary):
			return
		value = str(vm.get("value", value))
		state = StringName(vm.get("state", state))
		caption = String(vm.get("caption", ""))
		var num: float = value.get_slice("/", 0).to_float() if value.is_valid_float() or value.get_slice("/", 0).replace("°", "").is_valid_float() else NAN
		if value.ends_with("°"):
			num = value.trim_suffix("°").to_float()
		if not is_nan(num):
			if is_nan(_ema):
				_ema = num
			var d: float = num - _ema
			trend = -1 if d < -0.6 else (1 if d > 0.6 else 0)
			_ema = lerpf(_ema, num, 0.012)   # bound ~60/s → ~3 s window
		tooltip_text = "%s · %s" % [label, value] if label != "" else value
		queue_redraw()
	func _process(_dt: float) -> void:
		if state == &"crit":
			_pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
			queue_redraw()
		elif _pulse != 0.0:
			_pulse = 0.0
			queue_redraw()
	func _ring() -> Color:
		match state:
			&"crit": return Tokens.CRIT
			&"warn": return Tokens.WARN
			&"info": return Tokens.TEAL
			_:       return Tokens.LINE2
	func _on_draw() -> void:
		var c := Vector2(size.x * 0.5, D * 0.5)
		var r := D * 0.5 - 2.0
		draw_circle(c + Vector2(0, 2), r + 1.0, Tokens.with_alpha(Tokens.BG, 0.55))          # drop shadow
		draw_circle(c, r, Tokens.with_alpha(Tokens.PANEL, 0.92))
		var ring := _ring()
		var rw: float = (1.5 if quiet_when_good and state == &"good" else 3.0) + (2.0 * _pulse if state == &"crit" else 0.0)
		draw_arc(c, r - rw * 0.5, 0, TAU, 40, ring, rw, true)
		if state == &"crit":   # urgency is motion + a second halo, not only red
			draw_arc(c, r + 3.0 + 3.0 * _pulse, 0, TAU, 40, Tokens.with_alpha(Tokens.CRIT, 0.45 * (1.0 - _pulse)), 2.0, true)
		var isz := D * 0.58
		var quiet: bool = quiet_when_good and state == &"good"
		if icon_tex != null:
			draw_texture_rect(icon_tex, Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, Tokens.DIMMED if quiet else Tokens.WHITE)
		elif glyph != "":
			var gf: Font = ThemeDB.fallback_font
			draw_string(gf, c + Vector2(-isz * 0.5, isz * 0.32), glyph, HORIZONTAL_ALIGNMENT_CENTER, isz, int(isz * 0.8), Tokens.INK)
		if trend < 0 and not quiet:   # ▼ falling: a shape cue next to the ring (not colour alone, R11)
			var tx := c + Vector2(r * 0.78, -r * 0.62)
			draw_colored_polygon(PackedVector2Array([tx + Vector2(-5, -3), tx + Vector2(5, -3), tx + Vector2(0, 4)]), Tokens.urgency(state) if state != &"good" else Tokens.INK)
		if badge and value != "" and not quiet:
			var f: Font = UITheme.display_font()
			var fs := 13
			var tw: float = f.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pw: float = maxf(tw + 10.0, 22.0)
			var pr := Rect2(c.x - pw * 0.5, D - 6.0, pw, 17.0)
			draw_rect(pr, Tokens.with_alpha(Tokens.BG, 0.92))
			draw_rect(pr, ring if state != &"good" else Tokens.LINE2, false, 1.0)
			draw_string(f, Vector2(pr.position.x + (pw - tw) * 0.5, pr.position.y + 13.5), value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Tokens.urgency(state) if state != &"good" and state != &"info" else Tokens.INK)
		if caption != "":
			var cf: Font = UITheme.display_font()
			var cs := 12
			var cw: float = cf.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cs).x
			var cp := Vector2(c.x - cw * 0.5, D + 12.0 + 12.0)
			var ccol: Color = Tokens.urgency(state) if state == &"warn" or state == &"crit" else Tokens.MUT
			draw_string_outline(cf, cp, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, 4, Tokens.BG)
			draw_string(cf, cp, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, ccol)
