# RealWorld — ui/overlays.gd : concrete world overlays (spec 0005 §2.8), all inner classes.
#
# Each `extends OverlayBase.Overlay`. The first, LightOverlay, reimplements main.gd's night_rect
# darkening as a world-space overlay in the newhud OverlayHost (main.gd's own night_rect stays live
# until Batch 7). Colors come ONLY from Tokens (R3): Tokens.with_alpha keeps the Color() literal in
# tokens.gd. draw_overlay reads the snapshot (snap.clock.daylight), never a climate provider (R12).
extends RefCounted

const OverlayBase = preload("res://scripts/ui/overlay.gd")
const Tokens = preload("res://scripts/ui/tokens.gd")
const ViewGeom = preload("res://scripts/ui/view_geom.gd")
const TILE := ViewGeom.TILE

# ---- L · Light / night (design-system §3 hotkey L) ----
class LightOverlay extends OverlayBase.Overlay:
	func _init() -> void:
		overlay_id = &"light"
		hotkey = KEY_L
		radio = true
		legend_rows = [
			{"icon": "🌙", "label": "темрява · −робота"},
			{"icon": "💡", "label": "лампа — коло світла"},
		]
	func draw_overlay(host: CanvasItem, snap: Dictionary, cull: Dictionary) -> void:
		var clock: Dictionary = snap.get("clock", {})
		var dark: float = float(clock.get("daylight", 0.0))   # 0..0.46 ambient darkening (sim.daylight)
		if dark <= 0.0:
			return
		var x0: int = int(cull.get("x0", 0))
		var y0: int = int(cull.get("y0", 0))
		var x1: int = int(cull.get("x1", 0))
		var y1: int = int(cull.get("y1", 0))
		var rect := Rect2(x0 * TILE, y0 * TILE, (x1 - x0 + 1) * TILE, (y1 - y0 + 1) * TILE)
		host.draw_rect(rect, Tokens.with_alpha(Tokens.NIGHT, dark))

# ---- T · Temperature (design-system §3 hotkey T) — heat-map placeholder reading snap.env.temp_c ----
class TemperatureOverlay extends OverlayBase.Overlay:
	func _init() -> void:
		overlay_id = &"temperature"
		hotkey = KEY_T
		radio = true
		legend_rows = [
			{"icon": "🟦", "label": "холод"},
			{"icon": "🟥", "label": "жар"},
		]
	func draw_overlay(host: CanvasItem, snap: Dictionary, cull: Dictionary) -> void:
		var env: Dictionary = snap.get("env", {})
		var t: float = float(env.get("temp_c", 15.0))
		if t >= 8.0 and t <= 26.0:
			return   # in comfort band -> nothing to tint (band is legible by absence)
		var tint: Color = Tokens.with_alpha(Tokens.TEAL if t < 8.0 else Tokens.CRIT, 0.18)
		var x0: int = int(cull.get("x0", 0))
		var y0: int = int(cull.get("y0", 0))
		var x1: int = int(cull.get("x1", 0))
		var y1: int = int(cull.get("y1", 0))
		host.draw_rect(Rect2(x0 * TILE, y0 * TILE, (x1 - x0 + 1) * TILE, (y1 - y0 + 1) * TILE), tint)
