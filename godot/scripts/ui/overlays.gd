# RealWorld — ui/overlays.gd : concrete world overlays (spec 0005 §2.8), all inner classes.
#
# Each `extends OverlayBase.Overlay`. NightShade is the always-on ambient night (main.gd's night_rect,
# now per tile with light pools); L and T are the §3 radio overlays (work-light map, heat map).
# Colors come ONLY from Tokens (R3): Tokens.with_alpha keeps the Color() literal in tokens.gd.
# draw_overlay reads the snapshot (snap.light / snap.heat value data), never a climate provider (R12).
extends RefCounted

const OverlayBase = preload("res://scripts/ui/overlay.gd")
const Tokens = preload("res://scripts/ui/tokens.gd")
const ViewGeom = preload("res://scripts/ui/view_geom.gd")
const TILE := ViewGeom.TILE
const CapsuleTexts = preload("res://scripts/ui/capsule_texts.gd")

# ---- Ambient night (ALWAYS on — not a toggle). Every visible tile darkens by its OWN light level, so
# campfires, torches and lamps carve warm pools out of the dark: the night the player SEES is the
# same fold sim.light_at() feeds the work-speed penalty (snap.light = ambient + ACTIVE sources, value
# data). The OverlayHost draws it before any radio overlay; it is deliberately NOT registered — an
# always-on atmosphere layer owns no hotkey (the §3 L overlay is the analytic light map below). ----
class NightShade extends OverlayBase.Overlay:
	func _init() -> void:
		overlay_id = &"night"
		radio = false
	func draw_overlay(host: CanvasItem, snap: Dictionary, cull: Dictionary) -> void:
		var lt: Dictionary = snap.get("light", {})
		var ambient: float = float(lt.get("ambient", 1.0))
		if ambient >= 0.999:
			return
		var night_max: float = float(lt.get("night_max", 0.46))
		var sources: Array = lt.get("sources", [])
		var x0: int = int(cull.get("x0", 0))
		var x1: int = int(cull.get("x1", 0))
		var base_a: float = snappedf(night_max * (1.0 - ambient), 1.0 / 64.0)
		for y in range(int(cull.get("y0", 0)), int(cull.get("y1", 0)) + 1):
			# only the sources whose reach touches this row matter; a row nobody lights is ONE rect
			var near: Array = []
			for src in sources:
				if absi(int(src.y) - y) <= int(ceil(float(src.r))):
					near.append(src)
			if near.is_empty():
				if base_a > 0.0:
					host.draw_rect(Rect2(x0 * TILE, y * TILE, (x1 - x0 + 1) * TILE, TILE), Tokens.with_alpha(Tokens.NIGHT, base_a))
				continue
			# run-length merge equal shades along the row: one rect per run, not one per tile
			var run_x := x0
			var run_a := -1.0
			var run_w := 0.0
			for x in range(x0, x1 + 2):
				var a := -2.0
				var warm := 0.0
				if x <= x1:
					var light: float = Lit.tile_light(ambient, near, x, y)
					a = snappedf(night_max * (1.0 - light), 1.0 / 64.0)
					warm = snappedf(maxf(0.0, light - ambient) * 0.12, 1.0 / 64.0)
				if a != run_a or warm != run_w:
					if run_a > 0.0:
						host.draw_rect(Rect2(run_x * TILE, y * TILE, (x - run_x) * TILE, TILE), Tokens.with_alpha(Tokens.NIGHT, run_a))
					if run_w > 0.0:
						host.draw_rect(Rect2(run_x * TILE, y * TILE, (x - run_x) * TILE, TILE), Tokens.with_alpha(Tokens.AMBER, run_w))
					run_x = x
					run_a = a
					run_w = warm

# ---- Зона Основної капсули (spec 0010 REQ-0010-16): ALWAYS-ON маркер без хоткея (патерн NightShade, не в реєстрі). Показується ЛИШЕ коли капсулу
# вибрано (її панель відкрита) або надійшло попередження/контакт рейду — slice вирішує (snap.capsule.main.ring.show), оверлей лише малює.
# Метрика зони — Чебишов (дані), тож «кільце» — квадрат (2r+1) клітинок навколо капсули: правда про те, що саме діє, а не коло з іншою площею.
# Попередження — інший колір І товща лінія + кутові «засічки» (R11: не лише колір). ----
class CapsuleRing extends OverlayBase.Overlay:
	func _init() -> void:
		overlay_id = &"capsule_ring"
		radio = false
	func draw_overlay(host: CanvasItem, snap: Dictionary, _cull: Dictionary) -> void:
		var main: Dictionary = (snap.get("capsule", {}) as Dictionary).get("main", {})
		var ring: Dictionary = main.get("ring", {})
		if not bool(ring.get("show", false)):
			return
		var r: int = int(ring.get("radius", 0))
		var alert: bool = bool(ring.get("alert", false))
		var col: Color = Tokens.CRIT if alert else Tokens.TEAL
		var area := Rect2((int(ring.x) - r) * TILE, (int(ring.y) - r) * TILE, (2 * r + 1) * TILE, (2 * r + 1) * TILE)
		host.draw_rect(area, Tokens.with_alpha(col, 0.07))
		host.draw_rect(area, Tokens.with_alpha(col, 0.85), false, 3.0 if alert else 2.0)
		var tick: float = TILE * 0.5
		for corner in [Vector2(area.position.x, area.position.y), Vector2(area.end.x, area.position.y),
				Vector2(area.position.x, area.end.y), Vector2(area.end.x, area.end.y)]:
			var sx: float = 1.0 if corner.x <= area.position.x else -1.0
			var sy: float = 1.0 if corner.y <= area.position.y else -1.0
			host.draw_line(corner, corner + Vector2(tick * sx, 0.0), Tokens.with_alpha(col, 1.0), 4.0)
			host.draw_line(corner, corner + Vector2(0.0, tick * sy), Tokens.with_alpha(col, 1.0), 4.0)
		# підпис рамки (T-Ніколая: рамка без слів читалась як межа мапи) — табличка ПІД табличкою капсули (world_view), у кольорі рамки: верхній
		# край рамки часто під топ-баром, а бічні краї — під боковими панелями. Під час тривоги — «сюди йде рейд» + ціль, і стрілки «звідки» (OD-88)
		var font: Font = ThemeDB.fallback_font
		var l1: String = CapsuleTexts.t("zone_label_alert" if alert else "zone_label")
		var l2: String = CapsuleTexts.t("zone_label_alert2" if alert else "zone_label2")
		var fs := 10
		var w: float = maxf(font.get_string_size(l1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, font.get_string_size(l2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x) + 12.0
		var pill_rows: int = 4 if int(main.get("immune_left_ms", 0)) > 0 else 3   # висота таблички капсули (world_view._draw_capsule_marks)
		var box := Rect2((float(ring.x) + 0.5) * TILE - w * 0.5, (float(ring.y) + 1.0) * TILE + 4.0 + 13.0 * float(pill_rows) + 6.0, w, 29.0)
		host.draw_rect(box, Tokens.with_alpha(Tokens.BG, 0.92))
		host.draw_rect(box, Tokens.with_alpha(col, 0.9), false, 1.0)
		host.draw_string(font, box.position + Vector2(6.0, 11.0), l1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Tokens.with_alpha(col, 1.0))
		host.draw_string(font, box.position + Vector2(6.0, 24.0), l2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Tokens.INK)
		if alert:
			_draw_incoming(host, area, int(ring.get("dir", 0)), col)
		# контакт: кожен рейдер — червоний ромб-позначка з обводкою (R11: форма, не лише колір) і лінія до ядра, щоб бій читався й коли спрайт далеко/малий
		var core: Vector2 = area.get_center()
		for rd in ring.get("raiders", []):
			var at := Vector2(float(rd.x) * TILE, float(rd.y) * TILE)
			var pts := PackedVector2Array([at + Vector2(0, -9), at + Vector2(9, 0), at + Vector2(0, 9), at + Vector2(-9, 0)])
			host.draw_line(at, core, Tokens.with_alpha(col, 0.28), 1.5)
			host.draw_colored_polygon(pts, Tokens.with_alpha(col, 0.55))
			host.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Tokens.with_alpha(Tokens.INK, 0.95), 1.5)

	# Три шеврони, що вказують на капсулу з того краю рамки, з якого йде рейд (0 захід, 1 схід, 2 північ, 3 південь — Threats.edge_cell).
	func _draw_incoming(host: CanvasItem, area: Rect2, dir: int, col: Color) -> void:
		var mid: Vector2 = area.get_center()
		var inward: Vector2 = [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP][clampi(dir, 0, 3)]
		var side: Vector2 = Vector2(-inward.y, inward.x)
		var edge: Vector2 = mid - inward * (area.size.x * 0.5)
		for i in 3:
			var tip: Vector2 = edge - inward * (TILE * (0.2 + 0.7 * float(i)))
			var back: Vector2 = tip - inward * (TILE * 0.7)
			host.draw_line(back + side * TILE * 0.55, tip, Tokens.with_alpha(col, 1.0), 4.0)
			host.draw_line(back - side * TILE * 0.55, tip, Tokens.with_alpha(col, 1.0), 4.0)

# Shared light math (sim.light_at parity: Manhattan distance, linear falloff to the source radius).
class Lit extends RefCounted:
	static func tile_light(ambient: float, sources: Array, x: int, y: int) -> float:
		var light := ambient
		for src in sources:
			var r: float = float(src.r)
			var d := float(absi(int(src.x) - x) + absi(int(src.y) - y))
			if d <= r:
				light = maxf(light, clampf(1.0 - d / r, 0.0, 1.0))
		return clampf(light, 0.0, 1.0)

# ---- L · Light (design-system §3 hotkey L) — the WORK-light map: tiles too dark to work at full
# speed get a cold hatch, every light source shows its reach. Ambient darkness is always drawn by the
# NightShade above; this layer answers «where can I work tonight?». ----
class LightOverlay extends OverlayBase.Overlay:
	func _init() -> void:
		overlay_id = &"light"
		hotkey = KEY_L
		menu_label = "💡 Світло (L)"
		radio = true
		legend_rows = [
			{"icon": "🌙", "label": "темно · робота до +50% довше"},
			{"icon": "💡", "label": "коло світла (вогонь, смолоскип, лампа)"},
		]
	func draw_overlay(host: CanvasItem, snap: Dictionary, cull: Dictionary) -> void:
		var lt: Dictionary = snap.get("light", {})
		var ambient: float = float(lt.get("ambient", 1.0))
		var threshold: float = float(lt.get("threshold", 0.35))
		var sources: Array = lt.get("sources", [])
		for y in range(int(cull.get("y0", 0)), int(cull.get("y1", 0)) + 1):
			for x in range(int(cull.get("x0", 0)), int(cull.get("x1", 0)) + 1):
				if Lit.tile_light(ambient, sources, x, y) < threshold:
					var p := Vector2(x * TILE, y * TILE)
					host.draw_line(p + Vector2(4, TILE - 4), p + Vector2(TILE - 4, 4), Tokens.with_alpha(Tokens.TEAL, 0.35), 1.0)
		for src in sources:
			var c := Vector2((int(src.x) + 0.5) * TILE, (int(src.y) + 0.5) * TILE)
			host.draw_arc(c, float(src.r) * TILE, 0.0, TAU, 40, Tokens.with_alpha(Tokens.AMBER, 0.7), 2.0)

# ---- T · Temperature (design-system §3 hotkey T) — the REAL heat map: outdoor °C, indoor buffering
# toward the setpoint and every active emitter's reach (snap.heat — the same fold as sim.temp_at, so
# the map never disagrees with what the body feels). Blue = below comfort, green = in band, red = hot. ----
class TemperatureOverlay extends OverlayBase.Overlay:
	func _init() -> void:
		overlay_id = &"temperature"
		hotkey = KEY_T
		menu_label = "🌡 Тепло (T)"
		radio = true
		legend_rows = [
			{"icon": "🟦", "label": "холодно (нижче 12°C, без одягу)"},
			{"icon": "🟩", "label": "комфорт 12–30°C"},
			{"icon": "🟥", "label": "спека (понад 30°C)"},
		]
	static func tile_temp(heat: Dictionary, indoor: Dictionary, x: int, y: int, n: int) -> float:
		var t: float = float(heat.get("ambient", 15.0))
		if indoor.has(y * n + x):
			t += (float(heat.get("setpoint", 21.0)) - t) * float(heat.get("insulation", 0.6))
		var reach: int = int(heat.get("radius", 6))
		for e in heat.get("emitters", []):
			if absi(int(e.x) - x) + absi(int(e.y) - y) <= reach:
				t += float(e.heat)
		return t
	func draw_overlay(host: CanvasItem, snap: Dictionary, cull: Dictionary) -> void:
		var heat: Dictionary = snap.get("heat", {})
		if not bool(heat.get("available", false)):
			return
		var lo: float = float(heat.get("comfort_min", 12.0))
		var hi: float = float(heat.get("comfort_max", 30.0))
		var n: int = int(heat.get("n", 0))
		var indoor: Dictionary = {}
		for c in heat.get("indoor", []):
			indoor[int(c)] = true
		for y in range(int(cull.get("y0", 0)), int(cull.get("y1", 0)) + 1):
			for x in range(int(cull.get("x0", 0)), int(cull.get("x1", 0)) + 1):
				var t := tile_temp(heat, indoor, x, y, n)
				var col: Color
				if t < lo:
					col = Tokens.with_alpha(Tokens.TEAL, clampf(0.12 + (lo - t) / 40.0, 0.12, 0.5))
				elif t > hi:
					col = Tokens.with_alpha(Tokens.CRIT, clampf(0.12 + (t - hi) / 30.0, 0.12, 0.5))
				else:
					col = Tokens.with_alpha(Tokens.GOOD, 0.16)
				host.draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), col)
