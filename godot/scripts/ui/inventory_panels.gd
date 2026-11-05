# RealWorld — ui/inventory_panels.gd : spec 0009 personal-inventory UI (hotbar + inventory screen).
#
# Build-once-then-bind (R2), value data in (the `inventory` snapshot slice, R8), intents out (R9: set_hand,
# inv_move, craft_building, craft, stash_all, take_storage — the router calls the sim). Styling via
# Tokens/Theme only (R3). Mobile research 2026-11: Minecraft Bedrock (tap-to-select, hotbar 9), Valheim
# (8-slot hotbar row inside a 32-slot grid), Terraria (craft list filtered to what you can make).
extends RefCounted

const PanelBase = preload("res://scripts/ui/panel.gd")
const Widgets = preload("res://scripts/ui/widgets.gd")
const Tokens = preload("res://scripts/ui/tokens.gd")
const UITheme = preload("res://scripts/ui/theme.gd")
const ArtIcons = preload("res://scripts/ui/art_icons.gd")
const GameData = preload("res://scripts/data.gd")

const BLD := "bld:"

class SlotKit extends RefCounted:
	static func slot_tex(id: String) -> Texture2D:
		if id == "":
			return null
		if id.begins_with(BLD):
			return ArtIcons.building(id.substr(BLD.length()))
		if GameData.ITEMS.has(id):
			return ArtIcons.texture("item_" + id)
		return ArtIcons.res(id)

	# One slot button: icon + count badge text, toggle look for «in hand» / «picked up».
	static func make_slot(sz: float) -> Button:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(sz, sz)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_constant_override("icon_max_width", int(sz * 0.62))
		b.add_theme_font_size_override("font_size", 12)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		return b

	# Onboarding guide (gamedev §6: the goal points at a PLACE, not only at the corner chip): the hotbar slot
	# holding the current goal's building, -2 = the goal needs a building that is not in the hotbar, -1 = none.
	static func guide_slot(vm: Dictionary, slots: Array) -> int:
		var gl: Variant = vm.get("goals", {})
		if not (gl is Dictionary):
			return -1
		var kind := String(((gl as Dictionary).get("current", {}) as Dictionary).get("build", ""))
		if kind == "":
			return -1
		for i in mini(8, slots.size()):
			if String((slots[i] as Dictionary).get("id", "")) == BLD + kind:
				return i
		return -2

	# The amber breath the build bar uses for the goal slot (shape + motion, not colour alone — R11).
	static func pulse(b: Button, on: bool) -> void:
		if b == null:
			return
		if on:
			var k: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
			b.modulate = b.modulate.lerp(Tokens.AMBER, 0.45 * k)
			b.pivot_offset = b.size * 0.5
			b.scale = Vector2.ONE * (1.0 + 0.05 * k)
		elif b.scale != Vector2.ONE:
			b.scale = Vector2.ONE

	static func fill_slot(b: Button, sl: Dictionary, hotkey: String = "") -> void:
		var id := String(sl.get("id", ""))
		b.icon = SlotKit.slot_tex(id)
		var n: int = int(sl.get("n", 0))
		b.text = ("%d" % n if n > 1 else " ") if id != "" else (hotkey if hotkey != "" else " ")
		b.tooltip_text = String(sl.get("label", "")) + ((" ×%d" % n) if n > 1 else "")
		b.modulate = Tokens.WHITE if id != "" else Tokens.DIMMED


# ---- the hotbar (desktop BAR dock; the touch layer shows the same 8 slots in its quick bar) ----
class InventoryBarPanel extends PanelBase.Base:
	var _btns: Array = []
	var _bag_btn: Button
	func _init() -> void:
		panel_id = &"hotbar"; dock = PanelBase.DOCK_BAR; priority = 5; default_open = false
	func _build() -> void:
		rebuild_count += 1
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		add_child(hb)
		for i in 8:
			var b := SlotKit.make_slot(56.0)
			b.pressed.connect(func() -> void: emit_intent(&"set_hand", {"i": i}))
			hb.add_child(b)
			_btns.append(b)
		var inv := Button.new()
		inv.text = "🎒"
		inv.tooltip_text = "Інвентар (Tab)"
		inv.focus_mode = Control.FOCUS_NONE
		inv.custom_minimum_size = Vector2(56, 56)
		inv.add_theme_font_size_override("font_size", 24)
		inv.pressed.connect(func() -> void: emit_intent(&"toggle_inventory", {}))
		hb.add_child(inv)
		_bag_btn = inv
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary):
			return
		var inv: Dictionary = vm.get("inventory", {})
		if not bool(inv.get("enabled", false)):
			return
		var slots: Array = inv.slots
		var hand: int = int(inv.hand)
		var guide: int = SlotKit.guide_slot(vm, slots)
		for i in _btns.size():
			SlotKit.fill_slot(_btns[i], slots[i], str(i + 1))
			_btns[i].set_pressed_no_signal(i == hand)
			SlotKit.pulse(_btns[i], i == guide and i != hand)
		# the goal's building is not in the hotbar yet → the backpack button breathes (craft it there)
		_bag_btn.modulate = Tokens.WHITE
		SlotKit.pulse(_bag_btn, guide == -2)

# ---- the inventory screen: 8×4 grid (row 1 = hotbar) · craft list · the storage you stand at ----
class InventoryPanel extends PanelBase.Base:
	const COLS := 8
	const HINT_IDLE := "Вибери предмет, щоб узяти. Верхній ряд — хотбар."
	const HINT_HELD := "Вибери інший слот, щоб покласти, — або розділи чи викинь."
	var _grid: GridContainer
	var _slots: Array = []
	var _sel := -1                     # «picked up» slot (tap one, tap another = move/merge/swap)
	var _craft_box: VBoxContainer
	var _craft_rows: Array = []        # {row, icon, label, btn}
	var _store_box: VBoxContainer
	var _stash_btn: Button
	var _store_rows: Array = []
	var _hint: Label
	var _tool_btns: Array = []         # sort · split · drop (split/drop act on the picked-up slot)
	func _init() -> void:
		panel_id = &"inventory"; dock = PanelBase.DOCK_LEFT; priority = 5; hotkey = KEY_TAB; default_open = false
		menu_label = "🎒 Інвентар"; compact_open = 0
	func _build() -> void:
		rebuild_count += 1
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 6)
		add_child(vb)
		var head := Widgets.H2Header.new()
		vb.add_child(head); head.set_header("Інвентар", "")
		_hint = Label.new()
		_hint.add_theme_font_size_override("font_size", 12)
		_hint.add_theme_color_override("font_color", Tokens.MUT)
		_hint.text = HINT_IDLE
		_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_hint.custom_minimum_size = Vector2(340, 0)
		_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var top := HBoxContainer.new()   # hint + an explicit way out («no ✕ — how do I close it?», 2nd independent read)
		top.add_child(_hint)
		var close := Button.new()
		close.text = "✕ Закрити"
		close.tooltip_text = "Закрити інвентар (Tab)"
		close.focus_mode = Control.FOCUS_NONE
		close.custom_minimum_size = Vector2(96, 36)
		close.pressed.connect(func() -> void: emit_intent(&"toggle_inventory", {}))
		top.add_child(close)
		vb.add_child(top)
		_grid = GridContainer.new()
		_grid.columns = COLS
		_grid.add_theme_constant_override("h_separation", 4)
		_grid.add_theme_constant_override("v_separation", 4)
		vb.add_child(_grid)
		for i in 32:
			var b := SlotKit.make_slot(52.0)
			b.pressed.connect(_on_slot.bind(i))
			_grid.add_child(b)
			_slots.append(b)
		var tools := HBoxContainer.new()   # act on the picked-up slot (tap a slot first)
		tools.add_theme_constant_override("separation", 6)
		vb.add_child(tools)
		for spec in [["⇅ Сортувати", &"inv_sort"], ["½ Розділити", &"inv_split"], ["⤓ Викинути", &"inv_drop"]]:
			var tb := Button.new()
			tb.text = String(spec[0])
			tb.focus_mode = Control.FOCUS_NONE
			tb.custom_minimum_size = Vector2(0, 38)
			tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var verb: StringName = spec[1]
			tb.pressed.connect(func() -> void:
				if verb == &"inv_sort":
					emit_intent(verb, {})
				elif _sel >= 0:
					emit_intent(verb, {"i": _sel})
					_sel = -1)
			tools.add_child(tb)
			_tool_btns.append(tb)
		var ch := Widgets.H2Header.new()
		vb.add_child(ch); ch.set_header("Крафт", "")
		_craft_box = VBoxContainer.new()
		_craft_box.add_theme_constant_override("separation", 3)
		vb.add_child(_craft_box)
		for i in 24:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var ic := TextureRect.new()
			ic.custom_minimum_size = Vector2(30, 30)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			row.add_child(ic)
			var lb := Label.new()
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lb.add_theme_font_size_override("font_size", 13)
			lb.clip_text = true
			row.add_child(lb)
			var btn := Button.new()
			btn.focus_mode = Control.FOCUS_NONE
			btn.custom_minimum_size = Vector2(110, 34)
			row.add_child(btn)
			btn.pressed.connect(_on_craft.bind(i))
			_craft_box.add_child(row)
			row.visible = false
			_craft_rows.append({"row": row, "icon": ic, "label": lb, "btn": btn, "type": "", "id": ""})
		_store_box = VBoxContainer.new()
		_store_box.add_theme_constant_override("separation", 3)
		vb.add_child(_store_box)
		var sh := Widgets.H2Header.new()
		_store_box.add_child(sh); sh.set_header("Склад поруч", "")
		_stash_btn = Button.new()
		_stash_btn.text = "⇣ Розкласти рюкзак на склад"
		_stash_btn.focus_mode = Control.FOCUS_NONE
		_stash_btn.custom_minimum_size = Vector2(0, 40)
		_stash_btn.pressed.connect(func() -> void: emit_intent(&"stash_all", {}))
		_store_box.add_child(_stash_btn)
		for i in 8:
			var r := HBoxContainer.new()
			var ic2 := TextureRect.new()
			ic2.custom_minimum_size = Vector2(26, 26)
			ic2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			r.add_child(ic2)
			var l2 := Label.new()
			l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(l2)
			var tb := Button.new()
			tb.text = "Взяти 10"
			tb.focus_mode = Control.FOCUS_NONE
			tb.custom_minimum_size = Vector2(96, 34)
			tb.pressed.connect(_on_take.bind(i))
			r.add_child(tb)
			_store_box.add_child(r)
			r.visible = false
			_store_rows.append({"row": r, "icon": ic2, "label": l2, "res": ""})
		_store_box.visible = false
	func _on_slot(i: int) -> void:
		if _sel < 0:
			_sel = i
		else:
			if _sel != i:
				emit_intent(&"inv_move", {"a": _sel, "b": i})
			_sel = -1
	func _on_craft(i: int) -> void:
		var r: Dictionary = _craft_rows[i]
		if String(r.type) == "building":
			emit_intent(&"craft_building", {"kind": String(r.id)})
		elif String(r.type) == "item":
			emit_intent(&"craft", {"id": String(r.id)})
	func _on_take(i: int) -> void:
		emit_intent(&"take_storage", {"res": String(_store_rows[i].res), "n": 10})
	func bind(vm) -> void:
		rebind_count += 1
		build_once()
		if not (vm is Dictionary):
			return
		var inv: Dictionary = vm.get("inventory", {})
		if not bool(inv.get("enabled", false)):
			return
		var slots: Array = inv.slots
		_hint.text = HINT_IDLE if _sel < 0 else HINT_HELD   # one short line that answers «what now?» for the current step
		if _tool_btns.size() == 3:
			_tool_btns[1].disabled = _sel < 0
			_tool_btns[2].disabled = _sel < 0
		for i in _slots.size():
			SlotKit.fill_slot(_slots[i], slots[i], str(i + 1) if i < 8 else "")
			_slots[i].set_pressed_no_signal(i == _sel or (i == int(inv.hand) and _sel < 0))
		var craft: Array = inv.craft
		for i in _craft_rows.size():
			var r: Dictionary = _craft_rows[i]
			if i >= craft.size():
				r.row.visible = false
				continue
			var c: Dictionary = craft[i]
			r.type = String(c.type)
			r.id = String(c.id)
			r.row.visible = true
			r.icon.texture = SlotKit.slot_tex((BLD + String(c.id)) if String(c.type) == "building" else String(c.id))
			var have: int = int(c.get("have", 0))
			# «є 1» read as «ε 1» in the independent read — say it in words: how many you already CARRY
			r.label.text = "%s  %s%s" % [String(c.label), String(c.cost), ("   · у рюкзаку: %d" % have) if have > 0 else ""]
			r.btn.text = "Скрафтити" if bool(c.ok) else String(c.why)
			r.btn.disabled = not bool(c.ok)
			r.btn.tooltip_text = String(c.why)
			r.row.modulate = Tokens.WHITE if bool(c.ok) else Tokens.DIMMED
		_store_box.visible = bool(inv.get("near_storage", false))
		var st: Array = inv.get("storage", [])
		for i in _store_rows.size():
			var sr: Dictionary = _store_rows[i]
			if i < st.size():
				sr.res = String(st[i].res)
				sr.icon.texture = ArtIcons.res(String(st[i].res))
				sr.label.text = "%s  %d" % [String(st[i].label), int(st[i].n)]
				sr.row.visible = true
			else:
				sr.row.visible = false
