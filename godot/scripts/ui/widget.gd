# RealWorld — ui/widget.gd : the Widget BASE (spec 0005 §2.11). The `ThingComp` analogue.
#
# A widget IS a Control (built once, bind()-mutated — R2), styled by a theme_type_variation (R3),
# pinned via the pin_* helpers that encapsulate the verified resize-safe anchoring recipe ONCE (R7).
# Base is an inner class, preloaded (zero class_name, per repo precedent). Concrete widgets are inner
# classes in widgets.gd that `const WidgetBase = preload(...)` then `extends WidgetBase.Widget`.
extends RefCounted

class Widget extends Control:
	var _built := false

	func _ready() -> void:
		build_once()

	# Idempotent builder. Called from _ready AND lazily from every public mutator, so a widget builds
	# on first use whether or not it has entered the tree — this is what makes the Control layer provable
	# in a plain headless SceneTree with no frame-await (spec 0005 §3.3), while staying build-once (R2).
	func build_once() -> void:
		if _built:
			return
		_built = true
		_build()

	func _build() -> void: pass          # override: create child Controls ONCE
	func bind(_vm) -> void: pass          # override: set values on existing children only (call build_once() first)

	# --- the verified anchoring recipe, in ONE place (R7). Raw .position/PRESET_TOP_RIGHT are banned. ---
	static func pin_top_left(c: Control, ox := 12.0, oy := 10.0) -> void:
		c.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
		c.grow_horizontal = Control.GROW_DIRECTION_END
		c.grow_vertical = Control.GROW_DIRECTION_END
		c.offset_left = ox; c.offset_right = ox; c.offset_top = oy; c.offset_bottom = oy
		c.size = Vector2.ZERO

	static func pin_top_right(c: Control, ox := 12.0, oy := 10.0) -> void:
		c.set_anchors_preset(Control.PRESET_TOP_RIGHT, false)
		c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		c.grow_vertical = Control.GROW_DIRECTION_END
		c.offset_left = -ox; c.offset_right = -ox; c.offset_top = oy; c.offset_bottom = oy
		c.size = Vector2.ZERO

	static func pin_bottom_left(c: Control, ox := 12.0, oy := 70.0) -> void:
		c.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, false)
		c.grow_horizontal = Control.GROW_DIRECTION_END
		c.grow_vertical = Control.GROW_DIRECTION_BEGIN
		c.offset_left = ox; c.offset_right = ox; c.offset_top = -oy; c.offset_bottom = -oy
		c.size = Vector2.ZERO

	static func pin_center(c: Control) -> void:
		c.set_anchors_preset(Control.PRESET_CENTER, false)
		c.grow_horizontal = Control.GROW_DIRECTION_BOTH
		c.grow_vertical = Control.GROW_DIRECTION_BOTH   # deletes magic offsets like (-190,-160)

	# The CanvasLayer gotcha, in ONE place: a Control under a CanvasLayer does not inherit the viewport
	# size, so FULL_RECT collapses to width 0. Pin TOP_LEFT + size explicitly; the caller re-connects
	# its own bound method to size_changed (bound methods auto-disconnect when the owner is freed).
	static func fit_viewport(c: Control) -> void:
		c.position = Vector2.ZERO
		c.size = c.get_viewport().get_visible_rect().size
