# RealWorld — map_widget.gd : schematic lat/lon minimap for the logistics panel.
# Pure presentation: projects real coordinates (equirectangular, lon compressed by cos(lat))
# into a small box so home / trade hubs / friend outposts read as a real-world layout.
extends Control

var points: Array = []   # [{lat, lon, color: Color, label: String, kind: String}]
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(0, 210)

func set_points(pts: Array) -> void:
	points = pts
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.05, 0.07, 0.10, 0.92))
	draw_rect(rect, Color.html("2a3a4a"), false, 1.0)
	if points.size() < 1:
		return
	var mid_lat := 0.0
	for p in points:
		mid_lat += float(p.lat)
	mid_lat /= points.size()
	var kx: float = cos(deg_to_rad(mid_lat))
	# planar projection
	var proj := []
	var minx := 1e30
	var maxx := -1e30
	var miny := 1e30
	var maxy := -1e30
	for p in points:
		var x: float = float(p.lon) * kx
		var y: float = -float(p.lat)   # north up
		proj.append(Vector2(x, y))
		minx = minf(minx, x); maxx = maxf(maxx, x)
		miny = minf(miny, y); maxy = maxf(maxy, y)
	var pad := 26.0
	var w: float = maxf(1.0, size.x - pad * 2)
	var h: float = maxf(1.0, size.y - pad * 2)
	var dx: float = maxf(1e-4, maxx - minx)
	var dy: float = maxf(1e-4, maxy - miny)
	var scale: float = minf(w / dx, h / dy)
	var ox: float = (size.x - dx * scale) * 0.5 - minx * scale
	var oy: float = (size.y - dy * scale) * 0.5 - miny * scale
	var screen := []
	for pv in proj:
		screen.append(Vector2(pv.x * scale + ox, pv.y * scale + oy))
	# home is the first point — draw trade routes from it
	var home: Vector2 = screen[0]
	for i in range(1, points.size()):
		if str(points[i].get("kind", "")) == "hub":
			draw_line(home, screen[i], Color(0.36, 0.69, 1.0, 0.28), 1.0)
	# markers
	for i in points.size():
		var p: Dictionary = points[i]
		var s: Vector2 = screen[i]
		var col: Color = p.get("color", Color.WHITE)
		match str(p.get("kind", "")):
			"home":
				_draw_star(s, 7.0, col)
			"hub":
				draw_rect(Rect2(s.x - 4, s.y - 4, 8, 8), col)
			"friend":
				draw_circle(s, 4.0, col)
			"you":
				draw_circle(s, 5.0, col)
				draw_arc(s, 8.0, 0, TAU, 20, col, 1.5)
			_:
				draw_circle(s, 3.0, col)
		var lbl := str(p.get("label", ""))
		if lbl != "":
			draw_string(_font, s + Vector2(7, 4), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

func _draw_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var rr: float = r if k % 2 == 0 else r * 0.45
		var a: float = -PI / 2 + k * PI / 5
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)
