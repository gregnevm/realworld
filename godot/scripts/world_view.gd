# RealWorld — world_view.gd : custom-draw renderer reading the Sim state
extends Node2D

const WorldGen = preload("res://scripts/world_gen.gd")
const GameData = preload("res://scripts/data.gd")
const ViewGeom = preload("res://scripts/ui/view_geom.gd")
const TILE := ViewGeom.TILE

var sim: Variant
var hover := Vector2i(-9999, -9999)
var selected_build := ""
# The armed «remove» tool (touch's right-click): selected_build holds this id instead of a building.
const REMOVE_TOOL := "__remove__"

# one glyph table for the ghost preview AND the placed-building letters (content-pack complete)
const BUILD_GLYPH := {"wall": "#", "door": "D", "floor": ".", "storage": "S", "workbench": "W",
	"bed": "B", "turret": "T", "research_bench": "R", "campfire": "C", "torch": "t",
	"lamp": "L", "heater": "H", "spike_trap": "x"}
var terrain_colors: Array[Color] = []
var _font: Font

func _ready() -> void:
	for h in WorldGen.TERRAIN_COLOR:
		terrain_colors.append(Color.html(h))
	_font = ThemeDB.fallback_font

func _draw() -> void:
	if sim == null or sim.map.is_empty():
		return
	var n: int = sim.n
	var tiles: PackedByteArray = sim.map.tiles
	var x0 := 0
	var y0 := 0
	var x1 := n - 1
	var y1 := n - 1
	var cam := get_viewport().get_camera_2d()
	if cam:
		var vr: Vector2 = get_viewport_rect().size / cam.zoom
		var tl: Vector2 = cam.get_screen_center_position() - vr / 2.0
		x0 = clampi(int(tl.x / TILE) - 1, 0, n - 1)
		y0 = clampi(int(tl.y / TILE) - 1, 0, n - 1)
		x1 = clampi(int((tl.x + vr.x) / TILE) + 1, 0, n - 1)
		y1 = clampi(int((tl.y + vr.y) / TILE) + 1, 0, n - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := y * n + x
			draw_rect(Rect2(x * TILE, y * TILE, TILE + 1, TILE + 1), terrain_colors[tiles[i]])
			if (x + y) % 2 == 1:
				draw_rect(Rect2(x * TILE, y * TILE, TILE + 1, TILE + 1), Color(0, 0, 0, 0.05))
	for key in sim.map.nodes:
		var nx: int = key % n
		var ny: int = int(key / n)
		if nx < x0 or nx > x1 or ny < y0 or ny > y1:
			continue
		_draw_node(sim.map.nodes[key], nx, ny)
	for b in sim.buildings:
		_draw_building(b)
	# move / gather target marker (parity with JS renderer)
	if sim.player.action != null and sim.player.action.has("cell") and int(sim.player.action.cell) >= 0:
		var cell: int = sim.player.action.cell
		draw_rect(Rect2((cell % n) * TILE + 2, int(cell / n) * TILE + 2, TILE - 4, TILE - 4), Color(1, 0.81, 0.36, 0.9), false, 2.0)
	if selected_build == REMOVE_TOOL and sim._in(hover.x, hover.y):
		var own: bool = sim.bgrid.has(hover.y * n + hover.x)
		var rr := Rect2(hover.x * TILE + 3, hover.y * TILE + 3, TILE - 6, TILE - 6)
		var rc := Color.html("ff6b6b") if own else Color(1, 0.42, 0.42, 0.45)
		draw_rect(rr, Color(1, 0.35, 0.35, 0.25 if own else 0.1))
		draw_line(rr.position, rr.end, rc, 3.0)
		draw_line(Vector2(rr.end.x, rr.position.y), Vector2(rr.position.x, rr.end.y), rc, 3.0)
	elif selected_build != "" and sim._in(hover.x, hover.y):
		var sel_def: Dictionary = sim.building_def(selected_build)
		var okb: bool = not sel_def.is_empty() and sim.build_valid(hover.x, hover.y) and sim.afford(sel_def.get("cost", {}))
		var col := Color(0.35, 0.82, 0.55, 0.5) if okb else Color(1, 0.35, 0.35, 0.45)
		var gr := Rect2(hover.x * TILE + 1, hover.y * TILE + 1, TILE - 2, TILE - 2)
		draw_rect(gr, col)
		draw_rect(gr, Color.html("5fd38a") if okb else Color.html("ff6b6b"), false, 2.0)
		var gl: String = BUILD_GLYPH.get(selected_build, str(sel_def.get("glyph", "?")))
		draw_string(_font, Vector2(hover.x * TILE + TILE * 0.3, hover.y * TILE + TILE * 0.7), gl, HORIZONTAL_ALIGNMENT_LEFT, -1, int(TILE * 0.5), Color(1, 1, 1, 0.85))
	for s in sim.shots:
		draw_line(Vector2(s.x1 * TILE, s.y1 * TILE), Vector2(s.x2 * TILE, s.y2 * TILE), Color(1, 0.9, 0.47, clampf(s.t / 0.12, 0, 1)), 2.0)
	for e in sim.enemies:
		_draw_raider(e)
	_draw_player()

func _draw_node(node, x: int, y: int) -> void:
	var c := Vector2((x + 0.5) * TILE, (y + 0.5) * TILE)
	var r := TILE * 0.36
	match node.kind:
		"tree":
			draw_rect(Rect2(c.x - TILE * 0.05, c.y, TILE * 0.1, TILE * 0.32), Color.html("5a3d22"))
			draw_circle(c - Vector2(0, TILE * 0.06), r, Color.html("2f6b30"))
		"rock":
			draw_circle(c + Vector2(-r * 0.3, r * 0.1), r * 0.7, Color.html("8b9099"))
			draw_circle(c + Vector2(r * 0.4, 0), r * 0.6, Color.html("767b83"))
		"bush":
			draw_circle(c, r * 0.7, Color.html("4f8a3f"))
			for k in 3:
				draw_circle(c + Vector2((k - 1) * r * 0.4, (k % 2) * r * 0.2), r * 0.14, Color.html("d3506a"))
		"scrap":
			draw_rect(Rect2(c.x - r * 0.5, c.y - r * 0.2, r, r * 0.4), Color.html("86d0d6"))

func _draw_building(b) -> void:
	var def: Dictionary = sim.building_def(String(b.kind))
	var p := Vector2(b.x * TILE, b.y * TILE)
	var c := p + Vector2(TILE, TILE) * 0.5
	var blocking_wall: bool = String(b.kind) == "wall" or (def.get("blocks", false) and String(b.kind).ends_with("_wall"))
	if blocking_wall:
		draw_rect(Rect2(p.x + 1, p.y + 1, TILE - 2, TILE - 2), Color.html("8a8f97"))
	elif String(b.kind) == "floor" or String(b.kind).ends_with("_floor"):
		draw_rect(Rect2(p.x + 1, p.y + 1, TILE - 2, TILE - 2), Color.html("7d756a"))
	else:
		draw_rect(Rect2(p.x + 2, p.y + 2, TILE - 4, TILE - 4), Color(0.08, 0.10, 0.13, 0.7))
		var letter: String = BUILD_GLYPH.get(b.kind, str(def.get("glyph", "?")))
		draw_string(_font, c + Vector2(-TILE * 0.22, TILE * 0.22), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, int(TILE * 0.6), Color.html("e7edf3"))
		if float(def.get("range", 0.0)) > 0.0:
			draw_line(c, c + Vector2(cos(b.aim), sin(b.aim)) * TILE * 0.45, Color.html("2a2f36"), maxf(2.0, TILE * 0.12))
	var max_hp := float(def.get("hp", 50.0))
	if b.hp < max_hp:
		var fr: float = b.hp / max_hp
		draw_rect(Rect2(p.x + 2, p.y - 2, TILE - 4, 3), Color(0, 0, 0, 0.5))
		var bc := Color.html("5fd38a") if fr > 0.5 else (Color.html("ffcf5c") if fr > 0.25 else Color.html("ff6b6b"))
		draw_rect(Rect2(p.x + 2, p.y - 2, (TILE - 4) * fr, 3), bc)

func _draw_raider(e) -> void:
	var c := Vector2(e.px * TILE, e.py * TILE)
	var r := TILE * 0.34
	if String(e.get("kind", "raider")) == "bot":
		# патрульний робот Старого світу: сталевий корпус + червоне око-сенсор у напрямку руху
		var body := Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2))
		draw_rect(body, Color(1, 1, 1) if e.hit_flash > 0 else Color.html("8a97a3"))
		draw_rect(body, Color.html("39434c"), false, 2.0)
		draw_circle(c + Vector2(cos(e.face), sin(e.face)) * r * 0.45, r * 0.2, Color.html("d8423a"))
	else:
		draw_circle(c, r, Color(1, 1, 1) if e.hit_flash > 0 else Color.html("d8423a"))
		draw_arc(c, r, 0, TAU, 16, Color.html("5e120f"), 2.0)
	var fr: float = e.hp / e.maxhp
	draw_rect(Rect2(c.x - r, c.y - r - 6, r * 2, 3), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(c.x - r, c.y - r - 6, r * 2 * fr, 3), Color.html("ff6b6b"))

func _draw_player() -> void:
	var p: Dictionary = sim.player
	var c := Vector2(p.px * TILE, p.py * TILE)
	var r := TILE * 0.34
	draw_circle(c + Vector2(0, r * 0.7), r * 0.9, Color(0, 0, 0, 0.3))
	draw_circle(c, r, Color.html("7da0c0") if p.sleeping else Color.html("e7c25a"))
	draw_arc(c, r, 0, TAU, 18, Color.html("1c2530"), 2.0)
	draw_circle(c + Vector2(cos(p.face), sin(p.face)) * r * 0.55, r * 0.22, Color.html("1c2530"))
	if p.action != null and p.action.type == "gather" and float(p.action.get("dur", 0)) > 0:
		var frac: float = clampf(p.action.t / p.action.dur, 0, 1)
		draw_arc(c, r + 5, -PI / 2, -PI / 2 + frac * TAU, 24, Color.html("5db0ff"), 3.0)
