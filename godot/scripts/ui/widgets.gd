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

# ---- StatRow (.stock .r): glyph · label · right-aligned mono value (Stock / Equipment / Agents) ----
class StatRow extends WidgetBase.Widget:
	var _glyph: Label
	var _label: Label
	var _value: Label
	var value := ""
	func _build() -> void:
		custom_minimum_size = Vector2(0, 20)
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.add_theme_constant_override("separation", 6)
		add_child(hb)
		_glyph = Label.new()
		hb.add_child(_glyph)
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
		_label.text = String(info.label)
		_value.add_theme_color_override("font_color", Tokens.res(res))
	func set_row(glyph: String, label: String, val: String) -> void:
		build_once()
		_glyph.text = glyph
		_label.text = label
		set_value(val)
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
	var _icon: Label
	var _value: Label
	var _track: Control
	func _build() -> void:
		custom_minimum_size = Vector2(0, 18)
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.add_theme_constant_override("separation", 8)
		add_child(hb)
		_icon = Label.new()
		_icon.custom_minimum_size = Vector2(20, 0)
		hb.add_child(_icon)
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
		_track.draw_rect(Rect2(0, 0, w * clampf(_pct / 100.0, 0, 1), h), Tokens.urgency(state))
	func bind(vm) -> void:
		build_once()
		if not (vm is Dictionary):
			return
		icon = String(vm.get("icon", ""))
		_pct = float(vm.get("pct", 0))
		state = StringName(vm.get("state", &"good"))
		value = str(int(_pct))
		_icon.text = icon
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
	var _text := ""
	var _tag := ""
	func _build() -> void:
		custom_minimum_size = Vector2(0, 16)
		draw.connect(_on_draw)
	func set_header(text: String, tag := "") -> void:
		build_once()
		_text = text.to_upper()
		_tag = tag
		queue_redraw()
	func _on_draw() -> void:
		var f := ThemeDB.fallback_font
		var x := 0.0
		for ch in _text:
			draw_string(f, Vector2(x, 11), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Tokens.MUT)
			x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 1.6   # ~.16em tracking
		if _tag != "":
			draw_string(f, Vector2(size.x - 60, 11), _tag, HORIZONTAL_ALIGNMENT_RIGHT, 60, 10, Tokens.DIM)

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
		custom_minimum_size = Vector2(0, 22)
		_btn = Button.new()
		_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_btn.clip_text = true
		_btn.pressed.connect(func(): picked.emit(id))
		add_child(_btn)
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
		custom_minimum_size = Vector2(0, 22)
		_btn = Button.new()
		_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_btn.pressed.connect(func(): chosen.emit(item_id))
		add_child(_btn)
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
class BannerWidget extends WidgetBase.Widget:
	var _bus: Variant
	var _label: Label
	func _build() -> void:
		_label = Label.new()
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.add_theme_color_override("font_color", Tokens.CRIT)
		add_child(_label)
	func subscribe(bus) -> void:
		build_once()
		_bus = bus
		bus.banner.connect(_on_banner)
	func _on_banner(evt: Dictionary) -> void:
		_label.text = String(evt.get("params", {}).get("text", ""))
		visible = _label.text != ""
	func _exit_tree() -> void:
		if _bus != null and _bus.banner.is_connected(_on_banner):
			_bus.banner.disconnect(_on_banner)

class FlashWidget extends WidgetBase.Widget:
	var _bus: Variant
	var _label: Label
	var _t := 0.0
	func _build() -> void:
		_label = Label.new()
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.add_theme_color_override("font_color", Tokens.WARN)
		add_child(_label)
		set_process(true)
	func subscribe(bus) -> void:
		build_once()
		_bus = bus
		bus.flash.connect(_on_flash)
	func _on_flash(evt: Dictionary) -> void:
		_label.text = String(evt.get("params", {}).get("text", ""))
		_t = 2.2
	func _process(dt: float) -> void:
		if _t > 0.0:
			_t = maxf(0.0, _t - dt)
			if _t == 0.0:
				_label.text = ""
	func _exit_tree() -> void:
		if _bus != null and _bus.flash.is_connected(_on_flash):
			_bus.flash.disconnect(_on_flash)

class FeedWidget extends WidgetBase.Widget:
	var _bus: Variant
	var _list: VBoxContainer
	var _max := 8
	func _build() -> void:
		_list = VBoxContainer.new()
		_list.set_anchors_preset(Control.PRESET_FULL_RECT)
		_list.add_theme_constant_override("separation", 4)
		add_child(_list)
	func subscribe(bus) -> void:
		build_once()
		_bus = bus
		bus.feed.connect(_on_feed)
	func _on_feed(evt: Dictionary) -> void:
		var c := Card.new()
		_list.add_child(c)
		_list.move_child(c, 0)
		c.set_card(String(evt.get("cls", "")), String(evt.get("text", "")))
		while _list.get_child_count() > _max:
			var old := _list.get_child(_list.get_child_count() - 1)
			_list.remove_child(old)
			old.queue_free()
	func _exit_tree() -> void:
		if _bus != null and _bus.feed.is_connected(_on_feed):
			_bus.feed.disconnect(_on_feed)
