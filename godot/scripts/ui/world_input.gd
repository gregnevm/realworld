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

	const SPEEDS := [1.0, 2.0, 3.0, 0.0]      # main.gd parity: ×1 → ×2 → ×3 → pause
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
	var speed_idx := 0

	# PURE click grammar (main.gd _handle_click parity): armed build wins; then a raider within
	# ATTACK_RADIUS of the cursor; then a resource node under the cursor; else walk there.
	static func decide_click(enemies: Array, nodes: Dictionary, n: int, selected_build: String, t: Vector2i, fx: float, fy: float) -> Dictionary:
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
		if session == null or session.sim.dead:
			return
		if event is InputEventKey and event.pressed and not event.echo \
				and (event as InputEventKey).keycode == KEY_SPACE and not _typing():
			cycle_speed()
			get_viewport().set_input_as_handled()

	func _unhandled_input(event: InputEvent) -> void:
		if session == null or view == null or session.sim.dead:
			return
		if event is InputEventMouseButton and event.pressed:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_click(_mouse_tile())
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
				router.dispatch(&"cancel_action", {}, session)      # наказ пішки — сим-стан, лише verb (R9)
			else:
				_toggle_by_hotkey(k)

	func _click(t: Vector2i) -> void:
		var sim: Variant = session.sim
		var w: Vector2 = view.get_global_mouse_position()
		var d: Dictionary = decide_click(sim.enemies, sim.map.nodes, int(sim.n), String(view.selected_build), t, w.x / TILE, w.y / TILE)
		router.dispatch(StringName(d.verb), d.args, session)

	# Digits arm the ghost through the SAME select_build verb the BuildBar clicks use — one owner
	# for the toggle semantics (the entry scene binds it), so keyboard and mouse can never drift.
	func _select_build(i: int) -> void:
		if i < GameData.BUILD_ORDER.size():
			router.dispatch(&"select_build", {"kind": GameData.BUILD_ORDER[i]}, session)

	func cycle_speed() -> void:
		speed_idx = (speed_idx + 1) % SPEEDS.size()
		speed = float(SPEEDS[speed_idx])
		speed_changed.emit(speed)

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
