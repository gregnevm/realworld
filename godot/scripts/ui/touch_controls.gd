# RealWorld — ui/touch_controls.gd : the phone control layer (left stick · action button · quick bar ·
# radial menu · mode toast). VIEW only: it reads value data the scene hands in (bind_state) and EMITS
# signals; the entry scene turns them into router verbs / view state (R9 — no sim mutator is named here).
# Styling through Tokens/Theme only (R3). Research basis (2026-11): Apple HIG game controls (floating
# stick, ≥44 pt), Android ViewConfiguration (double-tap 300 ms, long-press 400 ms, slop 8 dp), Brawl Stars
# (tap = auto-target), Kurtenbach & Buxton / Hopkins (radial ≤ 6–8 items, menu under the finger),
# Terraria/Minecraft mobile (5–6 slot hotbar + inventory button).
extends RefCounted

const Settings = preload("res://scripts/settings.gd")
const Tokens = preload("res://scripts/ui/tokens.gd")
const UITheme = preload("res://scripts/ui/theme.gd")
const WidgetBase = preload("res://scripts/ui/widget.gd")
const ArtIcons = preload("res://scripts/ui/art_icons.gd")
const AM = preload("res://scripts/ui/action_model.gd")
const InventoryPanels = preload("res://scripts/ui/inventory_panels.gd")

const MODE_COLOR := {&"gather": Tokens.GOOD, &"build": Tokens.AMBER, &"repair": Tokens.TEAL, &"fight": Tokens.CRIT}

class TouchControls extends Control:
	signal stick_moved(v: Vector2)          # normalised, dead-zoned
	signal overview_toggled
	signal action_tap
	signal action_double
	signal action_hold(center: Vector2)    # screen px of the button centre (radial opens there)
	signal zoom_step(dir: int)              # +1 in / -1 out (vertical drag on the action button)
	signal slot_step(dir: int)              # ±1 (horizontal drag on the action button)
	signal slot_selected(i: int)
	signal inventory_pressed
	signal tool_pressed(verb: StringName)   # C4 (2026-11-09): ☰ і «Розібрати» живуть біля дій унизу, а не у верхній смузі
	signal option_chosen(opt: Dictionary)

	const STICK_R := 62.0                   # travel radius (logical px ≈ 10 mm at our scale)
	const DEAD := 0.15
	const ACT_R := 46.0                     # action button radius (Ø ≈ 15 mm)
	const SLOTS := 8                        # = the inventory hotbar (spec 0009)

	var move_vec := Vector2.ZERO
	var gui_rects := Callable()             # () -> Array[Rect2] of HUD docks the stick must not steal touches from
	var mode: StringName = &"gather"
	var target_label := ""
	var overview := false
	var _stick_idx := -1
	var _stick_base := Vector2.ZERO
	var _stick_knob := Vector2.ZERO
	var _stick_down_t := 0.0
	var _stick_moved := false
	var _stick_last_tap := -10.0
	var _act_idx := -1
	var _act_down_t := 0.0
	var _act_start := Vector2.ZERO
	var _act_pos := Vector2.ZERO
	var _act_hold_fired := false
	var _act_drag_acc := Vector2.ZERO       # drag progress not yet turned into steps
	var _act_axis := 0                      # 0 undecided / 1 vertical / 2 horizontal
	var _act_last_tap := -10.0
	var _now := 0.0
	var _press_scale := 1.0
	var _slot_bar: HBoxContainer
	var _slot_btns: Array = []
	var _inv_btn: Button
	var _menu_btn: Button
	var _remove_btn: Button
	var _radial: ColorRect
	var _radial_btns: Array = []
	var _radial_opts: Array = []
	var _toast: Label
	var _toast_t := 0.0
	var _slot_icons: Array = []

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		WidgetBase.Widget.fit_viewport(self)
		get_viewport().size_changed.connect(func() -> void:
			WidgetBase.Widget.fit_viewport(self)
			_layout())
		_slot_bar = HBoxContainer.new()
		_slot_bar.add_theme_constant_override("separation", 6)
		add_child(_slot_bar)
		for i in SLOTS:
			var b := Button.new()
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(52, 52)
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 34)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.pressed.connect(func() -> void: slot_selected.emit(i))
			_slot_bar.add_child(b)
			_slot_btns.append(b)
		_inv_btn = Button.new()
		_inv_btn.text = "🎒"
		_inv_btn.tooltip_text = "Інвентар"
		_inv_btn.focus_mode = Control.FOCUS_NONE
		_inv_btn.custom_minimum_size = Vector2(52, 52)
		_inv_btn.add_theme_font_size_override("font_size", 24)
		_inv_btn.pressed.connect(func() -> void: inventory_pressed.emit())
		_slot_bar.add_child(_inv_btn)
		_menu_btn = _tool_btn("☰", &"toggle_menu", "Панелі та оверлеї")
		_remove_btn = _tool_btn("♻ Розібрати", &"remove_tool", "Розібрати: торкнись своєї будівлі — повернеш частину ресурсів")
		var veil := ColorRect.new()                           # dims the world under an open radial: one layer of focus
		veil.color = Tokens.with_alpha(Tokens.BG, 0.45)
		_radial = veil
		_radial.mouse_filter = Control.MOUSE_FILTER_STOP     # a tap outside the options closes the menu
		_radial.visible = false
		_radial.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
				close_radial())
		add_child(_radial)
		for i in 6:
			var rb := Button.new()
			rb.focus_mode = Control.FOCUS_NONE
			rb.custom_minimum_size = Vector2(96, 48)
			rb.add_theme_font_size_override("font_size", 15)
			rb.pressed.connect(_pick_radial.bind(i))
			_radial.add_child(rb)
			_radial_btns.append(rb)
		_toast = Label.new()
		_toast.add_theme_font_override("font", UITheme.display_font())
		_toast.add_theme_font_size_override("font_size", 22)
		_toast.add_theme_color_override("font_outline_color", Tokens.BG)
		_toast.add_theme_constant_override("outline_size", 6)
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.visible = false
		add_child(_toast)
		set_process(true)
		_layout()

	func _tool_btn(txt: String, verb: StringName, tip: String) -> Button:
		var b := Button.new()
		b.text = txt
		b.tooltip_text = tip
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(52, 52)
		b.add_theme_font_size_override("font_size", 24 if txt.length() <= 2 else 15)   # слово — щоб не читалось як руйнівна піктограма (T-Ніколая 2026-11-05)
		b.pressed.connect(func() -> void: tool_pressed.emit(verb))
		_slot_bar.add_child(b)
		return b

	func set_tool_state(menu_open: bool, remove_armed: bool) -> void:
		_menu_btn.set_pressed_no_signal(menu_open)
		_remove_btn.set_pressed_no_signal(remove_armed)

	func _layout() -> void:
		var sz: Vector2 = size
		var bar: Vector2 = _slot_bar.get_combined_minimum_size()
		_slot_bar.position = Vector2((sz.x - bar.x) * 0.5, sz.y - bar.y - 10.0)
		_slot_bar.size = bar
		_radial.position = Vector2.ZERO
		_radial.size = sz
		# the one «hint slot» of the channel contract: bottom-centre just above the quick bar — never the
		# upper-middle, where the flash (above the hero) and the threat banner live
		_toast.position = Vector2(0, _slot_bar.position.y - 44.0)
		_toast.size = Vector2(sz.x, 34)

	func act_center() -> Vector2:
		return Vector2(size.x - ACT_R - 34.0, size.y - ACT_R - 34.0)

	# --- state in (value data from the scene) ------------------------------------------------------
	func bind_state(st: Dictionary) -> void:
		var m: StringName = StringName(st.get("mode", mode))
		if m != mode:
			mode = m
			show_toast("Режим: " + String(AM.MODE_INFO[mode].label))
		target_label = String(st.get("target", ""))
		overview = bool(st.get("overview", false))
		var slots: Array = st.get("slots", [])
		var active: int = int(st.get("active", 0))
		var guide: int = int(st.get("guide", -1))
		var shown: int = InventoryPanels.SlotKit.visible_count(slots, active)
		for i in _slot_btns.size():
			var b: Button = _slot_btns[i]
			if i < slots.size() and i < shown:
				var sl: Dictionary = slots[i]
				b.visible = true
				b.set_pressed_no_signal(i == active)
				b.tooltip_text = String(sl.get("label", ""))
				var tex: Texture2D = _slot_tex(sl)
				b.icon = tex
				var cnt: int = int(sl.get("n", 0))
				b.text = ("%d" % cnt if cnt > 1 else "") if tex != null else String(sl.get("glyph", "•"))
				b.modulate = Tokens.WHITE
				if i == guide and i != active:   # the onboarding goal's building breathes amber (as on the desktop hotbar)
					var k: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
					b.modulate = Tokens.WHITE.lerp(Tokens.AMBER, 0.45 * k)
			else:
				b.visible = false
		queue_redraw()

	func _slot_tex(sl: Dictionary) -> Texture2D:
		var id := String(sl.get("id", ""))
		match StringName(sl.get("type", &"")):
			&"tool", &"weapon":
				return ArtIcons.texture("item_" + id) if id != "" else null
			&"build":
				return ArtIcons.building(id)
			&"repair":
				return ArtIcons.texture("item_sledge")
			&"res":
				return ArtIcons.res(id)
		return null

	func show_toast(t: String) -> void:
		_toast.text = t
		_toast.visible = true
		_toast_t = 1.1
		_toast.add_theme_color_override("font_color", MODE_COLOR.get(mode, Tokens.INK))

	# --- radial menu (≤ 6 options around a point; most frequent on the axes) -----------------------
	func show_radial(center: Vector2, opts: Array) -> void:
		_radial_opts = opts.slice(0, 6)
		if _radial_opts.is_empty():
			return
		_radial.position = Vector2.ZERO
		_radial.size = size                 # (re)fit every open: the layer may have been sized before the viewport
		var n: int = _radial_opts.size()
		var r := 96.0
		var dirs := [Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1), Vector2(-0.75, -0.75), Vector2(0.75, -0.75)]
		for i in _radial_btns.size():
			var b: Button = _radial_btns[i]
			if i < n:
				var o: Dictionary = _radial_opts[i]
				b.text = "%s %s" % [String(o.get("glyph", "")), String(o.get("label", ""))]
				b.visible = true
				var bs: Vector2 = b.get_combined_minimum_size()
				var p: Vector2 = center + (dirs[i] as Vector2).normalized() * r - bs * 0.5
				p.x = clampf(p.x, 8.0, size.x - bs.x - 8.0)
				p.y = clampf(p.y, 8.0, size.y - bs.y - 8.0)
				b.position = p
				b.scale = Vector2(0.6, 0.6)
				b.pivot_offset = bs * 0.5
				b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12 * Settings.motion_scale()).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			else:
				b.visible = false
		_radial.visible = true

	func close_radial() -> void:
		_radial.visible = false

	func radial_open() -> bool:
		return _radial.visible

	func _pick_radial(i: int) -> void:
		if i < _radial_opts.size():
			option_chosen.emit(_radial_opts[i])
		close_radial()

	# --- raw touches: the stick zone (left 40 %, lower 70 %) and the action button --------------------
	func _input(ev: InputEvent) -> void:
		if not visible or _radial.visible:
			return
		if ev is InputEventScreenTouch:
			var st := ev as InputEventScreenTouch
			if st.pressed:
				if _stick_idx < 0 and st.position.x < size.x * 0.40 and st.position.y > size.y * 0.30 and not _over_gui(st.position):
					_stick_idx = st.index
					_stick_base = st.position
					_stick_knob = st.position
					_stick_down_t = _now
					_stick_moved = false
					get_viewport().set_input_as_handled()
				elif _act_idx < 0 and st.position.distance_to(act_center()) <= ACT_R + 14.0:
					_act_idx = st.index
					_act_down_t = _now
					_act_start = st.position
					_act_pos = st.position
					_act_hold_fired = false
					_act_drag_acc = Vector2.ZERO
					_act_axis = 0
					_press_scale = 0.92
					get_viewport().set_input_as_handled()
			else:
				if st.index == _stick_idx:
					_release_stick()
					get_viewport().set_input_as_handled()
				elif st.index == _act_idx:
					_release_action()
					get_viewport().set_input_as_handled()
		elif ev is InputEventScreenDrag:
			var sd := ev as InputEventScreenDrag
			if sd.index == _stick_idx:
				var d: Vector2 = sd.position - _stick_base
				if d.length() > AM.SLOP:
					_stick_moved = true
				if d.length() > STICK_R:            # the base follows a finger that overshoots (floating)
					_stick_base = sd.position - d.normalized() * STICK_R
				_stick_knob = sd.position
				var v: Vector2 = (_stick_knob - _stick_base) / STICK_R
				move_vec = Vector2.ZERO if v.length() < DEAD else v.limit_length(1.0)
				stick_moved.emit(move_vec)
				get_viewport().set_input_as_handled()
			elif sd.index == _act_idx:
				_act_pos = sd.position
				_act_drag_acc += sd.relative
				var tot: Vector2 = _act_pos - _act_start
				if _act_axis == 0 and tot.length() >= AM.DRAG_MIN:
					_act_axis = 1 if absf(tot.y) > absf(tot.x) else 2
					_act_drag_acc = tot          # the swipe so far counts toward the first step
				if _act_axis == 1 and absf(_act_drag_acc.y) >= AM.DRAG_STEP:
					zoom_step.emit(-1 if _act_drag_acc.y > 0.0 else 1)   # drag up = zoom in
					_act_drag_acc.y = 0.0
				elif _act_axis == 2 and absf(_act_drag_acc.x) >= AM.DRAG_STEP:
					slot_step.emit(1 if _act_drag_acc.x > 0.0 else -1)
					_act_drag_acc.x = 0.0
				get_viewport().set_input_as_handled()

	func _over_gui(p: Vector2) -> bool:
		if Rect2(_slot_bar.position, _slot_bar.size).grow(6.0).has_point(p):
			return true
		if gui_rects.is_valid():
			for r in gui_rects.call():
				if (r as Rect2).has_point(p):
					return true
		return false

	# true where this layer owns a finger (stick zone outside HUD docks, the action button, the slot bar):
	# the world input then never turns it into a click or half of a pinch.
	func claims(p: Vector2) -> bool:
		if not visible:
			return false
		if _radial.visible:
			return true
		if p.distance_to(act_center()) <= ACT_R + 14.0:
			return true
		if Rect2(_slot_bar.position, _slot_bar.size).grow(6.0).has_point(p):
			return true
		return p.x < size.x * 0.40 and p.y > size.y * 0.30 and not _over_gui(p)

	func _release_stick() -> void:
		var held: float = _now - _stick_down_t
		if not _stick_moved and held < 0.20:
			# strict double-tap on the stick (both taps short + still) → map overview; a walk never triggers it
			if _now - _stick_last_tap <= AM.DOUBLE_TAP:
				overview_toggled.emit()
				_stick_last_tap = -10.0
			else:
				_stick_last_tap = _now
		_stick_idx = -1
		move_vec = Vector2.ZERO
		stick_moved.emit(move_vec)

	func _release_action() -> void:
		var held: float = _now - _act_down_t
		var moved: Vector2 = _act_pos - _act_start
		_act_idx = -1
		_press_scale = 1.0
		if _act_axis != 0 or _act_hold_fired:
			return                               # the drag/hold already did its job
		var kind: StringName = AM.classify(held, moved, _now - _act_last_tap)
		if kind == &"tap":
			_act_last_tap = _now
			action_tap.emit()                    # the action fires at once — never delayed waiting for a 2nd tap
		elif kind == &"double":
			_act_last_tap = -10.0
			action_double.emit()

	func _process(dt: float) -> void:
		_now += dt
		if _act_idx >= 0 and not _act_hold_fired and _act_axis == 0 and _now - _act_down_t >= AM.HOLD \
				and (_act_pos - _act_start).length() <= AM.SLOP:
			_act_hold_fired = true
			action_hold.emit(act_center())
		if _toast_t > 0.0:
			_toast_t -= dt
			_toast.modulate.a = clampf(_toast_t / 0.3, 0.0, 1.0)
			if _toast_t <= 0.0:
				_toast.visible = false
		queue_redraw()

	# --- drawing: stick (only while held), action button (mode ring + glyph + hold progress), overview cross
	func _draw() -> void:
		if _stick_idx >= 0:
			draw_circle(_stick_base, STICK_R, Tokens.with_alpha(Tokens.PANEL, 0.35))
			draw_arc(_stick_base, STICK_R, 0, TAU, 48, Tokens.with_alpha(Tokens.INK, 0.35), 2.0, true)
			var kp: Vector2 = _stick_base + (_stick_knob - _stick_base).limit_length(STICK_R)
			draw_circle(kp, 26.0, Tokens.with_alpha(Tokens.INK, 0.55))
		else:
			# idle hint where the stick lives (discoverability without a text wall)
			var hint := Vector2(110, size.y - 120)
			if not _over_gui(hint):   # an open panel (inventory) covers the stick zone: no ring drawn over it
				# visible enough to be found (a 0.12 ring read as decor in the independent read): ring + knob
				draw_circle(hint, STICK_R * 0.7, Tokens.with_alpha(Tokens.PANEL, 0.22))
				draw_arc(hint, STICK_R * 0.7, 0, TAU, 40, Tokens.with_alpha(Tokens.INK, 0.3), 2.0, true)
				draw_circle(hint, 20.0, Tokens.with_alpha(Tokens.INK, 0.25))
		var c: Vector2 = act_center()
		var col: Color = MODE_COLOR.get(mode, Tokens.INK)
		var r: float = ACT_R * _press_scale
		draw_circle(c + Vector2(0, 3), r + 2.0, Tokens.with_alpha(Tokens.BG, 0.5))
		draw_circle(c, r, Tokens.with_alpha(Tokens.PANEL, 0.9))
		draw_arc(c, r - 3.0, 0, TAU, 56, col, 5.0, true)
		if _act_idx >= 0 and not _act_hold_fired and _act_axis == 0:
			var k: float = clampf((_now - _act_down_t) / AM.HOLD, 0.0, 1.0)   # hold progress ring
			draw_arc(c, r + 6.0, -PI / 2.0, -PI / 2.0 + TAU * k, 48, Tokens.with_alpha(col, 0.9), 3.0, true)
		var f: Font = ThemeDB.fallback_font
		var g: String = String(AM.MODE_INFO.get(mode, {}).get("glyph", "?"))
		draw_string(f, c + Vector2(-ACT_R, 12.0), g, HORIZONTAL_ALIGNMENT_CENTER, ACT_R * 2.0, 34, Tokens.INK)
		if target_label != "":
			var df: Font = UITheme.display_font()
			# a pill under the words: bare green text was lost on grass (independent read, gamedev §5)
			var tw: float = df.get_string_size(target_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			var pill := Rect2(c.x - tw * 0.5 - 10.0, c.y - r - 33.0, tw + 20.0, 26.0)
			draw_rect(pill, Tokens.with_alpha(Tokens.PANEL, 0.88))
			draw_rect(pill, Tokens.with_alpha(col, 0.7), false, 1.5)
			draw_string(df, c + Vector2(-140, -r - 14.0), target_label, HORIZONTAL_ALIGNMENT_CENTER, 280, 15, col)
		if overview:
			var m := size * 0.5
			draw_line(m + Vector2(-18, 0), m + Vector2(-6, 0), Tokens.AMBER, 2.0)
			draw_line(m + Vector2(6, 0), m + Vector2(18, 0), Tokens.AMBER, 2.0)
			draw_line(m + Vector2(0, -18), m + Vector2(0, -6), Tokens.AMBER, 2.0)
			draw_line(m + Vector2(0, 6), m + Vector2(0, 18), Tokens.AMBER, 2.0)
			draw_arc(m, 24.0, 0, TAU, 32, Tokens.with_alpha(Tokens.AMBER, 0.6), 1.5, true)
