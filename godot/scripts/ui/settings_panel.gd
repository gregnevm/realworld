# RealWorld — ui/settings_panel.gd : модальне вікно «Налаштування» (build-once; лише емітить сигнали — R9).
#
# Рядки генеруються з Settings.DEFS (одна правда; жодної механіки тут не названо). Вікно нічого не пише на диск
# і не чіпає сесію: entry-сцена слухає changed/action і застосовує. Стан показано текстом (ON ✓ / OFF), не лише кольором (R11).
extends RefCounted

const WidgetBase = preload("res://scripts/ui/widget.gd")
const Tokens = preload("res://scripts/ui/tokens.gd")
const UITheme = preload("res://scripts/ui/theme.gd")
const Settings = preload("res://scripts/settings.gd")

class SettingsPanel extends WidgetBase.Widget:
	signal changed(id: String, value: Variant)
	signal action(id: String)
	signal closed

	var is_mobile := false            # ставить entry-сцена ДО першого показу: mobile_only-рядки лише на телефоні
	var in_game := false              # дії сесії (зберегти / у меню / нова гра) лише коли гра йде
	var _rows: Dictionary = {}        # id -> {"kind", "buttons": [Button], "toggle": Button}
	var _actions: VBoxContainer
	var _confirm_btn: Button
	var _confirm_armed := false
	var _info: Label

	func _build() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var pc := PanelContainer.new()
		pc.theme_type_variation = UITheme.V_MODAL
		pc.set_anchors_preset(Control.PRESET_CENTER)
		pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
		pc.grow_vertical = Control.GROW_DIRECTION_BOTH
		pc.custom_minimum_size = Vector2(520, 0)
		add_child(pc)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 8)
		pc.add_child(vb)
		var head := HBoxContainer.new()
		vb.add_child(head)
		var title := Label.new()
		title.text = "⚙ Налаштування"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_color_override("font_color", Tokens.AMBER)
		head.add_child(title)
		var x := Button.new()
		x.text = "✖"
		x.custom_minimum_size = Vector2(44, 38)
		x.focus_mode = Control.FOCUS_NONE
		x.pressed.connect(func() -> void: closed.emit())
		head.add_child(x)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(0, 320)
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vb.add_child(scroll)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 6)
		scroll.add_child(col)
		var section := ""
		for d in Settings.DEFS:
			if bool(d.get("mobile_only", false)) and not is_mobile:
				continue
			if String(d.section) != section:
				section = String(d.section)
				var sl := Label.new()
				sl.text = section.to_upper()
				sl.add_theme_font_size_override("font_size", 13)
				sl.add_theme_color_override("font_color", Tokens.DIM)
				col.add_child(sl)
			_add_row(col, d)
		_actions = VBoxContainer.new()
		_actions.add_theme_constant_override("separation", 6)
		col.add_child(_actions)
		var al := Label.new()
		al.text = "ГРА"
		al.add_theme_font_size_override("font_size", 13)
		al.add_theme_color_override("font_color", Tokens.DIM)
		_actions.add_child(al)
		_add_action("save_now", "💾 Зберегти зараз")
		_add_action("to_menu", "↩ У головне меню")
		_confirm_btn = _add_action("new_game", "🗑 Нова гра…")
		_actions.visible = in_game
		var foot := HBoxContainer.new()
		vb.add_child(foot)
		_info = Label.new()
		_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_info.add_theme_color_override("font_color", Tokens.DIM)
		_info.add_theme_font_size_override("font_size", 13)
		_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		foot.add_child(_info)
		var rst := Button.new()
		rst.text = "↺ Скинути"
		rst.custom_minimum_size = Vector2(110, 38)
		rst.focus_mode = Control.FOCUS_NONE
		rst.pressed.connect(func() -> void: action.emit("reset_settings"))
		foot.add_child(rst)

	func _add_row(col: VBoxContainer, d: Dictionary) -> void:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		col.add_child(row)
		var line := HBoxContainer.new()
		row.add_child(line)
		var lb := Label.new()
		lb.text = String(d.label)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(lb)
		var rec := {"kind": String(d.kind), "buttons": [], "toggle": null}
		if String(d.kind) == "toggle":
			var b := Button.new()
			b.toggle_mode = true
			b.custom_minimum_size = Vector2(96, 40)
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(func() -> void: changed.emit(String(d.id), b.button_pressed))
			line.add_child(b)
			rec["toggle"] = b
		else:
			var seg := HBoxContainer.new()
			seg.add_theme_constant_override("separation", 4)
			line.add_child(seg)
			for i in range((d.options as Array).size()):
				var b := Button.new()
				b.toggle_mode = true
				b.text = String(d.labels[i])
				b.custom_minimum_size = Vector2(54, 40)
				b.focus_mode = Control.FOCUS_NONE
				var val: Variant = d.options[i]
				b.pressed.connect(func() -> void: changed.emit(String(d.id), val))
				seg.add_child(b)
				(rec["buttons"] as Array).append({"btn": b, "val": val})
		var hint := Label.new()
		hint.text = String(d.get("hint", ""))
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Tokens.DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(hint)
		_rows[String(d.id)] = rec

	func _add_action(id: String, text: String) -> Button:
		var b := Button.new()
		b.text = text
		b.custom_minimum_size = Vector2(0, 44)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: _on_action(id))
		_actions.add_child(b)
		return b

	# «Нова гра» стирає збереження — двоступеневе підтвердження: перше натискання лише озброює кнопку.
	func _on_action(id: String) -> void:
		if id == "new_game":
			if not _confirm_armed:
				_confirm_armed = true
				_confirm_btn.text = "⚠ Так, стерти збереження"
				return
			_disarm()
		else:
			_disarm()
		action.emit(id)

	func _disarm() -> void:
		_confirm_armed = false
		if _confirm_btn != null:
			_confirm_btn.text = "🗑 Нова гра…"

	# values: id -> поточне значення; info — рядок збірки.
	func bind(vm) -> void:
		build_once()
		var values: Dictionary = vm.get("values", {})
		for id in _rows:
			var rec: Dictionary = _rows[id]
			var v: Variant = values.get(id)
			if v == null:
				continue
			if String(rec.kind) == "toggle":
				var tb: Button = rec.toggle
				tb.set_pressed_no_signal(bool(v))
				tb.text = "ON ✓" if bool(v) else "OFF"
			else:
				for e in rec.buttons:
					(e.btn as Button).set_pressed_no_signal(is_equal_approx(float(e.val), float(v)))
		_info.text = String(vm.get("info", ""))
		_actions.visible = in_game
		_disarm()

	func row_ids() -> Array:
		build_once()
		return _rows.keys()
