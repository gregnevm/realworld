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

# --- generated art (art/ pipeline → assets/gen). Every lookup falls back to the vector drawing below,
# so a missing/unimported PNG never blanks the map. Index = WorldGen terrain id.
const ART_DIR := "res://assets/gen/"
const TERRAIN_TILE := ["tile_water", "tile_grass", "tile_forest", "tile_rock", "tile_road", "tile_dirt", "tile_ruins", "tile_sand", "tile_snow"]
const HIT_FLASH := Color(1.7, 1.7, 1.7, 1.0)
var _tex_cache := {}
var _crop_cache := {}   # path-less: Texture2D instance id → opaque Rect2i (generated sprites carry ~20% transparent padding)
# Ground is muted (lower value contrast, slight desaturation) so objects/actors — kept at full strength — pop.
const GROUND_TINT := Color(0.80, 0.82, 0.82, 1.0)
const SHADOW := Color(0, 0, 0, 0.30)
var _tile_tex: Array = []

func _ready() -> void:
	for h in WorldGen.TERRAIN_COLOR:
		terrain_colors.append(Color.html(h))
	_font = ThemeDB.fallback_font
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for tid in TERRAIN_TILE:
		_tile_tex.append(art_texture("tile", String(tid)))

# Texture for assets/gen/<dir>/<id>.png, or null. Imported resource first (exports / editor); raw PNG via
# Image.load_from_file when there is no import cache (fresh checkout, headless tests). Misses are cached too.
func art_texture(dir: String, id: String) -> Texture2D:
	var path := "%s%s/%s.png" % [ART_DIR, dir, id]
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_tex_cache[path] = tex
	return tex

# Opaque bounding rect of a sprite (cached). Drawing only this region removes the transparent margin the
# generator leaves, so a "1-tile" sprite actually fills its tile instead of looking tiny.
func content_rect(tex: Texture2D) -> Rect2:
	var key := tex.get_instance_id()
	if _crop_cache.has(key):
		return _crop_cache[key]
	var r := Rect2(Vector2.ZERO, tex.get_size())
	var img := tex.get_image()
	if img != null and not img.is_empty() and img.detect_alpha() != Image.ALPHA_NONE:
		var u := img.get_used_rect()
		if u.size.x > 0 and u.size.y > 0:
			r = Rect2(u)
	_crop_cache[key] = r
	return r

# Draw `tex` cropped to its content, fitted into `box` (aspect kept), bottom-centred on the box.
func draw_sprite_fit(tex: Texture2D, box: Rect2, tint: Color = Color.WHITE, flip_x: bool = false) -> void:
	var src := content_rect(tex)
	var sc := minf(box.size.x / src.size.x, box.size.y / src.size.y)
	var sz := src.size * sc
	var pos := Vector2(box.position.x + (box.size.x - sz.x) * 0.5, box.end.y - sz.y)
	var dst := Rect2(pos, sz)
	if flip_x:
		dst = Rect2(Vector2(dst.end.x, dst.position.y), Vector2(-sz.x, sz.y))
	draw_texture_rect_region(tex, dst, src, tint)

# Soft elliptical contact shadow (cheap ambient occlusion) under an object standing at `foot`.
func draw_contact_shadow(foot: Vector2, radius: float) -> void:
	draw_set_transform(foot, 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, radius, SHADOW)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# Building art: sprites dir first, floors/zones live in tile dir (bld_ prefix in both).
func building_texture(kind: String) -> Texture2D:
	var t := art_texture("sprite", "bld_" + kind)
	return t if t != null else art_texture("tile", "bld_" + kind)

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
			var tr := Rect2(x * TILE, y * TILE, TILE + 1, TILE + 1)
			var ttex: Texture2D = _tile_tex[tiles[i]] if tiles[i] < _tile_tex.size() else null
			if ttex != null:
				draw_texture_rect(ttex, tr, false, GROUND_TINT)
			else:
				draw_rect(tr, terrain_colors[tiles[i]])
				if (x + y) % 2 == 1:
					draw_rect(tr, Color(0, 0, 0, 0.05))
	# painter's order (row-major = top to bottom) so tall sprites overlap the tile behind them correctly
	var node_keys: Array = sim.map.nodes.keys()
	node_keys.sort()
	for key in node_keys:
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
		var gtex := building_texture(selected_build)
		if gtex != null:
			draw_texture_rect(gtex, gr, false, Color(1, 1, 1, 0.75))
		else:
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
	var ntex := art_texture("sprite", "node_" + String(node.kind))
	if ntex != null:
		var tall: bool = String(node.kind) == "tree"
		var box := Rect2((x + 0.5) * TILE - TILE * (0.62 if tall else 0.5), (y + 1.0) * TILE - TILE * (1.5 if tall else 0.95), TILE * (1.24 if tall else 1.0), TILE * (1.5 if tall else 0.95))
		draw_contact_shadow(Vector2(c.x, (y + 0.92) * TILE), TILE * (0.34 if tall else 0.36))
		draw_sprite_fit(ntex, box)
		return
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
	var btex := building_texture(String(b.kind))
	if btex != null:
		var floorlike: bool = String(b.kind) == "floor" or String(b.kind).ends_with("_floor") or String(b.kind) == "grow_zone"
		var inset := 0.0 if (floorlike or blocking_wall) else 1.0
		if floorlike:
			draw_texture_rect(btex, Rect2(p.x, p.y, TILE + 1, TILE + 1), false)
		else:
			draw_contact_shadow(Vector2(c.x, p.y + TILE * 0.92), TILE * 0.40)
			draw_sprite_fit(btex, Rect2(p.x + inset, p.y - TILE * 0.12, TILE - 2 * inset, TILE * 1.08))
		if float(def.get("range", 0.0)) > 0.0:
			draw_line(c, c + Vector2(cos(b.aim), sin(b.aim)) * TILE * 0.45, Color.html("2a2f36"), maxf(2.0, TILE * 0.12))
	elif blocking_wall:
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
	var is_bot: bool = String(e.get("kind", "raider")) == "bot"
	var atex := art_texture("actor", "actor_patrol_robot" if is_bot else "actor_raider")
	if atex != null:
		_draw_actor(atex, c, cos(e.face), HIT_FLASH if e.hit_flash > 0 else Color.WHITE)
	elif is_bot:
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

# Actor sprite: ~1.5 tiles, feet near the pawn's position, mirrored when facing left.
func _draw_actor(tex: Texture2D, c: Vector2, face_x: float, tint: Color) -> void:
	var sz := TILE * 1.9
	draw_contact_shadow(c + Vector2(0, TILE * 0.36), TILE * 0.32)
	draw_sprite_fit(tex, Rect2(c.x - sz * 0.5, c.y + TILE * 0.40 - sz, sz, sz), tint, face_x < -0.2)

func _draw_player() -> void:
	var p: Dictionary = sim.player
	var c := Vector2(p.px * TILE, p.py * TILE)
	var r := TILE * 0.34
	draw_circle(c + Vector2(0, r * 0.7), r * 0.9, Color(0, 0, 0, 0.3))
	var htex := art_texture("actor", "actor_hero")
	if htex != null:
		_draw_actor(htex, c, cos(p.face), Color(0.62, 0.72, 0.95) if p.sleeping else Color.WHITE)
	else:
		draw_circle(c, r, Color.html("7da0c0") if p.sleeping else Color.html("e7c25a"))
		draw_arc(c, r, 0, TAU, 18, Color.html("1c2530"), 2.0)
		draw_circle(c + Vector2(cos(p.face), sin(p.face)) * r * 0.55, r * 0.22, Color.html("1c2530"))
	if p.action != null and p.action.type == "gather" and float(p.action.get("dur", 0)) > 0:
		var frac: float = clampf(p.action.t / p.action.dur, 0, 1)
		draw_arc(c, r + 5, -PI / 2, -PI / 2 + frac * TAU, 24, Color.html("5db0ff"), 3.0)
