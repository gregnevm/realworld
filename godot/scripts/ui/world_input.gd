# RealWorld — ui/world_input.gd : the world-space input adapter (spec 0005 §2.10 event half, R12).
#
# The EVENT half of the interaction grammar: it turns raw input (clicks, keys, wheel) into the SAME
# verbs input_verbs.gd binds and dispatches them through the router — it calls no sim mutator itself
# (R9). The click decision is a PURE static (decide_click) so the grammar is headless-testable.
# Hotkey toggles are GENERIC (R4 spirit): panels/overlays carry their locked §3 key as metadata and
# this adapter flips whatever the registries hold — it names no mechanic. WASD writes sim.move_input
# (an input CHANNEL the sim polls, main.gd parity — not a mutator call; the ONLY sanctioned direct
# sim touch here). Camera zoom is pure view state, owned here like main.gd owned it.
extends RefCounted

const GameData = preload("res://scripts/data.gd")
const ViewGeom = preload("res://scripts/ui/view_geom.gd")

class WorldInput extends Node:
	signal speed_changed(mult: float)

	const SPEEDS := [1.0, 2.0, 3.0]           # running speeds; pause is a separate toggle (Space)
	const TILE := ViewGeom.TILE
	const ATTACK_RADIUS := 0.7                 # click within 0.7 tiles of a raider = attack (parity)
	const ZOOM_STEP := 1.1
	const ZOOM_MIN := 0.55
	const ZOOM_MAX := 2.2

	var router: Variant = null                 # InputController — the ONLY sim seam (R9)
	var session: Variant = null                # SessionScript; null until the spawn screen starts one
	var view: Variant = null                   # WorldView — owns hover + selected_build (ghost state)
	var cam: Camera2D = null
	var preg: Variant = null                   # PanelRegistry — generic hotkey toggles (R12)
	var oreg: Variant = null                   # OverlayRegistry — generic hotkey toggles (R12)
	var speed := 1.0
	var last_speed := 1.0                      # the running speed Space resumes to
	var mouse_in_world := false                # the last motion reached the world (no HUD control ate it)
	var _painting := false                     # LMB held with a paintable ghost armed (§5 drag = run)
	var _paint_last := Vector2i(-9999, -9999)

	# PURE speed grammar (R12, headless-testable): Space toggles pause <-> the last running speed;
	# +/- step through SPEEDS (stepping while paused resumes at the stepped speed); a chip click sets
	# an exact speed. Returns {speed, last}. The old Space-cycle needed THREE presses to pause from ×1.
	static func next_speed(cur: float, last: float, action: StringName, value: float = 1.0) -> Dictionary:
		var run: float = last if cur <= 0.0 else cur
		match action:
			&"toggle_pause":
				return {"speed": run if cur <= 0.0 else 0.0, "last": run}
			&"faster", &"slower":
				var i: int = maxi(0, SPEEDS.find(run))
				i = clampi(i + (1 if action == &"faster" else -1), 0, SPEEDS.size() - 1)
				return {"speed": float(SPEEDS[i]), "last": float(SPEEDS[i])}
			&"set":
				return {"speed": value, "last": value if value > 0.0 else run}
		return {"speed": cur, "last": last}

	# Which kinds a held drag paints as a RUN (walls, floors, fields, traps, cables): a def may opt in
	# with `paint: true`; catalogue ids follow the same suffix families. Single-object buildings
	# (benches, beds, turrets…) stay one-click so a twitchy drag never spends a fortune.
	static func paintable(kind: String, def: Dictionary = {}) -> bool:
		if bool(def.get("paint", false)):
			return true
		return kind == "wall" or kind == "floor" or kind == "spike_trap" or kind == "grow_zone" \
			or kind.ends_with("_wall") or kind.ends_with("_floor") or kind.ends_with("conduit")

	# Cells of a run from a to b (inclusive): Bresenham made 4-CONNECTED — a diagonal step inserts its
	# corner cell, so a dragged wall never leaves a corner-to-corner gap the indoor flood (4-way) would
	# leak air through. A fast drag never skips cells either.
	static func line_cells(a: Vector2i, b: Vector2i) -> Array:
		var out: Array = []
		var dx: int = absi(b.x - a.x)
		var dy: int = -absi(b.y - a.y)
		var sx: int = 1 if a.x < b.x else -1
		var sy: int = 1 if a.y < b.y else -1
		var err: int = dx + dy
		var c := a
		while true:
			out.append(c)
			if c == b or out.size() > 1024:
				break
			var e2: int = 2 * err
			var stepped_x := false
			if e2 >= dy:
				err += dy
				c.x += sx
				stepped_x = true
			if e2 <= dx:
				if stepped_x:
					out.append(c)          # the corner: keeps the run 4-connected
				err += dx
				c.y += sy
		return out

	# PURE click grammar (main.gd _handle_click parity): armed build wins; then a raider within
	# ATTACK_RADIUS of the cursor; then a resource node under the cursor; then an OWN grow zone
	# (cycles its crop — the farming v2 verb); else walk there.
	static func decide_click(enemies: Array, nodes: Dictionary, n: int, selected_build: String, t: Vector2i, fx: float, fy: float, grow_cells: Dictionary = {}) -> Dictionary:
		if selected_build != "":
			return {"verb": &"build", "args": {"kind": selected_build, "x": t.x, "y": t.y}}
		var best: Variant = null
		var bd := ATTACK_RADIUS
		for e in enemies:
			var d: float = sqrt((e.px - fx) * (e.px - fx) + (e.py - fy) * (e.py - fy))
			if d < bd:
				bd = d
				best = e
		if best != null:
			return {"verb": &"order_attack", "args": {"target": best}}
		if t.x >= 0 and t.y >= 0 and t.x < n and t.y < n and nodes.has(t.y * n + t.x):
			return {"verb": &"order_gather", "args": {"x": t.x, "y": t.y}}
		if grow_cells.has(t.y * n + t.x):
			return {"verb": &"set_crop", "args": {"x": t.x, "y": t.y}}
		return {"verb": &"order_move", "args": {"x": t.x, "y": t.y}}

	# PURE key grammar for the build bar: digits 1..9,0 arm/disarm a GameData.BUILD_ORDER slot.
	static func build_slot_for_key(keycode: int) -> int:
		if keycode >= KEY_1 and keycode <= KEY_9:
			return keycode - KEY_1
		if keycode == KEY_0:
			return 9
		return -1

	func _process(_dt: float) -> void:
		if session == null or view == null:
			return
		var sim: Variant = session.sim
		view.hover = _mouse_tile()
		if _painting and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_painting = false                       # release outside our event stream (focus loss)
		if sim.dead or _typing():
			# raw-полінг клавіш ігнорує gui-фокус: без цього гейта набір "wasd" у LineEdit
			# (координати CapsulePanel) водив би пішку по мапі, поки гравець просто друкує
			sim.move_input = Vector2.ZERO
			return
		var mv := Vector2.ZERO
		if Input.is_key_pressed(KEY_W):
			mv.y -= 1
		if Input.is_key_pressed(KEY_S):
			mv.y += 1
		if Input.is_key_pressed(KEY_A):
			mv.x -= 1
		if Input.is_key_pressed(KEY_D):
			mv.x += 1
		sim.move_input = mv

	# true, коли фокус клавіатури — в текстовому полі HUD (LineEdit/TextEdit)
	func _typing() -> bool:
		var focus: Control = get_viewport().gui_get_focus_owner()
		return focus is LineEdit or focus is TextEdit

	# Space мусить лишатися паузою навіть після кліку по кнопці HUD: клік лишає фокус на BaseButton,
	# і той з'їдає ui_accept у gui-шарі раніше за _unhandled_input (повторно тиснучи власний action).
	# Тому пауза перехоплюється в _input — ДО gui — але не краде пробіл у текстових полів.
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			mouse_in_world = false                  # _unhandled_input flips it back if no GUI ate it
		if session == null or session.sim.dead:
			return
		if event is InputEventKey and event.pressed and not event.echo \
				and (event as InputEventKey).keycode == KEY_SPACE and not _typing():
			apply_speed(&"toggle_pause")
			get_viewport().set_input_as_handled()

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			mouse_in_world = true                   # reached past the HUD: the cursor is over the map
		if session == null or view == null or session.sim.dead:
			return
		if event is InputEventMouseButton and not event.pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_painting = false
		elif event is InputEventMouseMotion and _painting:
			_paint_to(_mouse_tile())
		if event is InputEventMouseButton and event.pressed:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				var t := _mouse_tile()
				var sel := String(view.selected_build)
				_click(t)
				if sel != "" and paintable(sel, session.sim.building_def(sel) if session.sim.has_method("building_def") else {}):
					_painting = true                # keep laying the run while the button is held
					_paint_last = t
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				# cancels a pending build, else tears down your own building under the cursor (parity)
				if String(view.selected_build) != "":
					view.selected_build = ""
				else:
					var t := _mouse_tile()
					router.dispatch(&"deconstruct", {"x": t.x, "y": t.y}, session)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_by(ZOOM_STEP)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_by(1.0 / ZOOM_STEP)
		elif event is InputEventKey and event.pressed and not event.echo:
			var k := (event as InputEventKey).keycode
			var slot := build_slot_for_key(k)
			if slot >= 0:
				_select_build(slot)
			elif k == KEY_ESCAPE:
				view.selected_build = ""                            # ghost = view state, owned here
				_painting = false
				router.dispatch(&"cancel_action", {}, session)      # наказ пішки — сим-стан, лише verb (R9)
			elif k == KEY_EQUAL or k == KEY_PLUS or k == KEY_KP_ADD:
				apply_speed(&"faster")
			elif k == KEY_MINUS or k == KEY_KP_SUBTRACT:
				apply_speed(&"slower")
			else:
				_toggle_by_hotkey(k)

	func _click(t: Vector2i) -> void:
		var sim: Variant = session.sim
		var w: Vector2 = view.get_global_mouse_position()
		var grow_cells: Dictionary = {}
		if sim.has_method("building_def"):
			for cell in sim.bgrid:
				if bool(sim.building_def(String(sim.bgrid[cell].kind)).get("grow", false)):
					grow_cells[cell] = true
		var d: Dictionary = decide_click(sim.enemies, sim.map.nodes, int(sim.n), String(view.selected_build), t, w.x / TILE, w.y / TILE, grow_cells)
		router.dispatch(StringName(d.verb), d.args, session)

	# Digits arm the ghost through the SAME select_build verb the BuildBar clicks use — one owner
	# for the toggle semantics (the entry scene binds it), so keyboard and mouse can never drift.
	func _select_build(i: int) -> void:
		if i < GameData.BUILD_ORDER.size():
			router.dispatch(&"select_build", {"kind": GameData.BUILD_ORDER[i]}, session)

	func apply_speed(action: StringName, value: float = 1.0) -> void:
		var r: Dictionary = next_speed(speed, last_speed, action, value)
		speed = float(r.speed)
		last_speed = float(r.last)
		speed_changed.emit(speed)

	# Paint the run from the last painted cell to `t`: every new cell on the line that can take the
	# building gets the SAME build verb a click sends (R9); occupied/blocked cells are skipped
	# silently so a sweep across a tree line doesn't spam refusals.
	func _paint_to(t: Vector2i) -> void:
		if t == _paint_last or String(view.selected_build) == "":
			return
		var sim: Variant = session.sim
		var kind := String(view.selected_build)
		var cells: Array = line_cells(_paint_last, t)
		for i in range(1, cells.size()):
			var c: Vector2i = cells[i]
			if sim.build_valid(c.x, c.y):
				router.dispatch(&"build", {"kind": kind, "x": c.x, "y": c.y}, session)
		_paint_last = t

	# The cursor in WORLD tile units (float) — the inspect slice hit-tests enemies with it.
	func hover_world() -> Vector2:
		if view == null:
			return Vector2(-9999, -9999)
		var w: Vector2 = view.get_global_mouse_position()
		return Vector2(w.x / TILE, w.y / TILE)

	# Generic §3 hotkey routing: whatever the registries hold, keyed by their own metadata (R12).
	# Overlays win over panels so the LOCKED overlay keys stay reserved (design-system §3).
	func _toggle_by_hotkey(k: int) -> void:
		if oreg != null:
			for o in oreg.overlays:
				if int(o.hotkey) == k:
					oreg.toggle(o.overlay_id)
					return
		if preg != null:
			for p in preg.panels:
				if int(p.hotkey) == k:
					preg.toggle(p.panel_id)
					return

	func _zoom_by(factor: float) -> void:
		if cam == null:
			return
		var z: float = clampf(cam.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
		cam.zoom = Vector2(z, z)

	func _mouse_tile() -> Vector2i:
		return ViewGeom.mouse_tile(view.get_global_mouse_position(), TILE)
