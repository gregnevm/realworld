# RealWorld — world_view.gd : custom-draw renderer reading the Sim state
extends Node2D

const WorldGen = preload("res://scripts/world_gen.gd")
const GameData = preload("res://scripts/data.gd")
const InventoryMod = preload("res://scripts/sim/inventory.gd")
const MainCapsule = preload("res://scripts/sim/capsule.gd")   # лише читання рівнів/імунітету для знаків на корпусі
const ViewGeom = preload("res://scripts/ui/view_geom.gd")
const CapsuleTexts = preload("res://scripts/ui/capsule_texts.gd")
const Fmt = preload("res://scripts/ui/format.gd")
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
const GROUND_TINT := Color(0.88, 0.90, 0.89, 1.0)
const SHADOW := Color(0, 0, 0, 0.30)
# Value plan (see "Reducing Visual Confusion"): ground has a SMALL light/dark range, objects & actors are the
# highest-contrast things on screen. FLATTEN lifts the ground blacks; OUTLINE is a dark silhouette rim.
const GROUND_FLATTEN := Color(0.20, 0.22, 0.21, 0.22)
const OUTLINE := Color(0.04, 0.05, 0.06, 0.85)
# Animation is VIEW-ONLY (wall-clock + per-pawn motion deltas): it never reads or writes sim state/RNG.
const LIGHT_KINDS := ["campfire", "torch", "torch_lamp", "lamp", "standing_lamp", "brazier"]
var _last_pos: Dictionary = {}     # instance id -> Vector2 (previous frame world pos) → walking detection
var _gait: Dictionary = {}         # instance id -> accumulated walk phase

# --- floating feedback text (view-only): "+3 🪵" when stock rises, red "-N" on hits. Observes the sim by
# diffing numbers between frames — it never writes sim state and never touches RNG. -------------------
var _fx: Array = []                 # {text, pos(world), age, color, icon}
var _last_stock: Dictionary = {}    # res id -> amount last frame
var _last_hp: Dictionary = {}       # enemy index / "hero" -> hp last frame
const FX_LIFE := 1.1
var _rings: Array = []              # order-acknowledge ripples {pos, age}
var _born: Dictionary = {}          # building cell -> wall-clock time it appeared (placement pop)
var _seen_b: Dictionary = {}        # building cells seen last frame
var _b_baseline := false            # first observation = existing base: no pops on load
var _last_epos: Array = []          # enemy world positions last frame (death poofs)
var _poofs: Array = []              # {pos, age}
var action_target: Dictionary = {}  # touch scheme: what the action button will act on (scene sets it each frame)
var action_mode: StringName = &"gather"
var action_build := ""              # build mode: the building the button will place (its ghost fills the brackets)
const ACTION_COL := {&"gather": Color(0.44, 0.68, 0.33, 1.0), &"build": Color(0.88, 0.69, 0.44, 1.0), &"repair": Color(0.53, 0.82, 0.84, 1.0), &"fight": Color(0.88, 0.42, 0.36, 1.0)}
var shake := 0.0                    # TRAUMA 0..1 (Eiserloh): events add, decays 1/s; the scene offsets the camera by trauma²
var hitstop := 0.0                  # seconds the RENDER holds its frame (Vlambeer/Dead Cells hit-stop) — the sim never pauses
var _hero_flash := 0.0              # white flash on the hero for the first frames of a hit
var _last_target := -1

func fx_add(text: String, wpos: Vector2, color: Color, icon_id: String = "") -> void:
	if _fx.size() > 24:
		_fx.pop_front()
	_fx.append({"text": text, "pos": wpos, "age": 0.0, "color": color, "icon": icon_id})

# Call once per frame BEFORE queue_redraw(): ages the texts and spawns new ones from observed deltas.
func observe_sim(dt: float) -> void:
	for f in _fx:
		f.age = float(f.age) + dt
	_fx = _fx.filter(func(f) -> bool: return float(f.age) < FX_LIFE)
	if sim == null or sim.map.is_empty():
		return
	var hero := Vector2(sim.player.px * TILE, sim.player.py * TILE - TILE * 1.3)
	var k := 0
	for res in GameData.RES_ORDER:
		var now_amt: int = int(sim.res_amount(res))
		if _last_stock.has(res):
			var d: int = now_amt - int(_last_stock[res])
			if d > 0:
				fx_add("+%d" % d, hero + Vector2(0, -TILE * 0.45 * k), Color(1.0, 0.95, 0.8), "res_" + String(res))
				k += 1
		_last_stock[res] = now_amt
	var tgt: int = int(sim.player.action.get("cell", -1)) if sim.player.action is Dictionary else -1
	if tgt >= 0 and tgt != _last_target:
		_rings.append({"pos": Vector2((tgt % sim.n + 0.5) * TILE, (int(tgt / sim.n) + 0.5) * TILE), "age": 0.0})
	_last_target = tgt
	for rg in _rings:
		rg.age = float(rg.age) + dt
	_rings = _rings.filter(func(rg) -> bool: return float(rg.age) < 0.45)
	var now_b: Dictionary = {}
	for b in sim.buildings:
		var bc: int = int(b.y) * int(sim.n) + int(b.x)
		now_b[bc] = true
		if _b_baseline and not _seen_b.has(bc):
			_born[bc] = _now()
	_seen_b = now_b
	_b_baseline = true
	var epos: Array = []
	for e in sim.enemies:
		epos.append(Vector2(e.px * TILE, e.py * TILE))
	if epos.size() < _last_epos.size():   # someone fell: poof where an enemy was and none is now
		for lp in _last_epos:
			var gone := true
			for q in epos:
				if (q as Vector2).distance_to(lp) < TILE * 0.8:
					gone = false
					break
			if gone:
				_poofs.append({"pos": lp, "age": 0.0})
				hitstop = 0.06                       # a kill lands heavier
				shake = minf(1.0, shake + 0.2)
	_last_epos = epos
	for pf in _poofs:
		pf.age = float(pf.age) + dt
	_poofs = _poofs.filter(func(pf) -> bool: return float(pf.age) < 0.6)
	shake = maxf(0.0, shake - dt * 1.0)
	hitstop = maxf(0.0, hitstop - dt)
	_hero_flash = maxf(0.0, _hero_flash - dt)
	var hp_now: float = float(sim.player.hp)
	if _last_hp.has("hero") and hp_now < float(_last_hp.hero) - 0.4:
		fx_add("-%d" % int(round(float(_last_hp.hero) - hp_now)), hero + Vector2(TILE * 0.5, 0), Color(1.0, 0.42, 0.38))
		shake = minf(1.0, shake + 0.35)
		hitstop = 0.04
		_hero_flash = 0.08
	_last_hp["hero"] = hp_now
	for ei in sim.enemies.size():
		var e: Variant = sim.enemies[ei]
		var key := "e%d" % ei
		if _last_hp.has(key) and float(e.hp) < float(_last_hp[key]) - 0.4:
			fx_add("-%d" % int(round(float(_last_hp[key]) - float(e.hp))), Vector2(e.px * TILE, e.py * TILE - TILE * 0.9), Color(1.0, 0.85, 0.4))
		_last_hp[key] = float(e.hp)

func _draw_fx() -> void:
	for pf in _poofs:   # enemy down: a burst of 8 grey chunks flying out + a fading ring
		var t2: float = clampf(float(pf.age) / 0.6, 0.0, 1.0)
		var e2: float = 1.0 - pow(1.0 - t2, 2.0)
		for k in 8:
			var ang: float = TAU * float(k) / 8.0 + 0.4
			draw_circle(pf.pos + Vector2(cos(ang), sin(ang)) * TILE * 0.9 * e2, TILE * 0.09 * (1.0 - t2), Color(0.62, 0.66, 0.70, 1.0 - t2))
		draw_arc(pf.pos, TILE * 0.7 * e2, 0, TAU, 24, Color(0.86, 0.9, 0.95, 0.6 * (1.0 - t2)), 2.0)
	for rg in _rings:   # order acknowledged: one fast expanding ring (0.45 s, ease-out)
		var t: float = clampf(float(rg.age) / 0.45, 0.0, 1.0)
		var e: float = 1.0 - pow(1.0 - t, 3.0)
		draw_arc(rg.pos, TILE * (0.2 + 0.7 * e), 0, TAU, 32, Color(1, 0.86, 0.5, 0.9 * (1.0 - t)), 3.0 * (1.0 - t) + 1.0)
	for f in _fx:
		var t: float = clampf(float(f.age) / FX_LIFE, 0.0, 1.0)
		var rise: float = 1.0 - pow(1.0 - t, 2.0)                 # ease-out: quick lift, soft settle
		var a: float = 1.0 - pow(t, 3.0)                          # hold, then fade late
		var p: Vector2 = f.pos + Vector2(0, -TILE * 0.9 * rise)
		var col: Color = f.color
		col.a = a
		var fs := int(TILE * 0.5)
		var tw: float = _font.get_string_size(String(f.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var icon: Texture2D = art_texture("icon", String(f.icon)) if String(f.icon) != "" else null
		var isz := TILE * 0.55
		var total: float = tw + (isz + 3.0 if icon != null else 0.0)
		var x0: float = p.x - total * 0.5
		if icon != null:
			draw_texture_rect(icon, Rect2(x0, p.y - isz * 0.8, isz, isz), false, Color(1, 1, 1, a))
			x0 += isz + 3.0
		draw_string_outline(_font, Vector2(x0, p.y), String(f.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.04, 0.05, 0.06, a * 0.9))
		draw_string(_font, Vector2(x0, p.y), String(f.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _now() -> float:
	return Time.get_ticks_msec() * 0.001

# Walk phase for a pawn: advances with distance travelled, 0 amplitude when standing still.
func _gait_of(key: int, pos: Vector2) -> Vector2:   # x = phase, y = moving (0..1)
	var last: Vector2 = _last_pos.get(key, pos)
	var d: float = pos.distance_to(last)
	_last_pos[key] = pos
	var ph: float = float(_gait.get(key, 0.0)) + d * 0.9
	_gait[key] = ph
	return Vector2(ph, clampf(d * 40.0, 0.0, 1.0))
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
func draw_sprite_fit(tex: Texture2D, box: Rect2, tint: Color = Color.WHITE, flip_x: bool = false, outline: bool = true, rot: float = 0.0, squash: Vector2 = Vector2.ONE) -> void:
	var src := content_rect(tex)
	var sc := minf(box.size.x / src.size.x, box.size.y / src.size.y)
	var sz := src.size * sc
	var pos := Vector2(box.position.x + (box.size.x - sz.x) * 0.5, box.end.y - sz.y)
	var dst := Rect2(pos, sz)
	var animated: bool = rot != 0.0 or squash != Vector2.ONE or flip_x
	if animated:   # pivot = bottom-centre (feet / trunk base): sway, squash & stretch keep the sprite planted
		var pv := Vector2(dst.position.x + dst.size.x * 0.5, box.end.y)
		var sq := Vector2(-squash.x if flip_x else squash.x, squash.y)   # mirror via matrix: negative rect sizes draw nothing
		draw_set_transform_matrix(Transform2D(rot, sq, 0.0, pv) * Transform2D(0.0, Vector2.ONE, 0.0, -pv))
	if outline:
		var o := maxf(1.0, TILE * 0.045)
		for d in [Vector2(o, 0), Vector2(-o, 0), Vector2(0, o), Vector2(0, -o)]:
			draw_texture_rect_region(tex, Rect2(dst.position + d, dst.size), src, OUTLINE)
	draw_texture_rect_region(tex, dst, src, tint)
	if animated:
		draw_set_transform_matrix(Transform2D.IDENTITY)

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
				# break the repetition: per-cell flip (4 variants) + ±4% brightness jitter from a cell hash.
				# Pure function of (x, y) → stable frame to frame, never touches sim RNG.
				var hh: int = ((x * 73856093) ^ (y * 19349663)) & 0xff
				var jit: float = 1.0 + (float(hh & 15) / 15.0 - 0.5) * 0.08
				var tint := Color(GROUND_TINT.r * jit, GROUND_TINT.g * jit, GROUND_TINT.b * jit, 1.0)
				if hh & 48:   # a negative rect size draws NOTHING in Godot — flip through the transform matrix
					var cc := tr.get_center()
					draw_set_transform_matrix(Transform2D(0.0, Vector2(-1.0 if hh & 16 else 1.0, -1.0 if hh & 32 else 1.0), 0.0, cc) * Transform2D(0.0, Vector2.ONE, 0.0, -cc))
					draw_texture_rect(ttex, tr, false, tint)
					draw_set_transform_matrix(Transform2D.IDENTITY)
				else:
					draw_texture_rect(ttex, tr, false, tint)
				_shore(tiles, n, x, y, int(tiles[i]), tr)
			else:
				draw_rect(tr, terrain_colors[tiles[i]])
				if (x + y) % 2 == 1:
					draw_rect(tr, Color(0, 0, 0, 0.05))
	draw_rect(Rect2(x0 * TILE, y0 * TILE, (x1 - x0 + 1) * TILE, (y1 - y0 + 1) * TILE), GROUND_FLATTEN)
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
	# order feedback: a marching dotted path to the target + a pulsing ring on it (RTS/colony-sim grammar —
	# the player always sees WHERE the pawn is going and that the click registered)
	if sim.player.action != null and sim.player.action.has("cell") and int(sim.player.action.cell) >= 0:
		var cell: int = sim.player.action.cell
		var tc := Vector2((cell % n + 0.5) * TILE, (int(cell / n) + 0.5) * TILE)
		var path: Array = sim.player.action.get("path", []) if sim.player.action.get("path") is Array else []
		var prev := Vector2(sim.player.px * TILE, sim.player.py * TILE)
		var march: float = fmod(_now() * 1.6, 1.0)
		var di := 0
		for wp in path:
			var wpos := Vector2((float(wp.x) + 0.5) * TILE, (float(wp.y) + 0.5) * TILE) if wp is Vector2i or wp is Vector2 else tc
			var seg: float = prev.distance_to(wpos)
			var steps: int = maxi(1, int(seg / (TILE * 0.5)))
			for k in steps:
				var q: Vector2 = prev.lerp(wpos, (float(k) + march) / float(steps))
				draw_circle(q, TILE * 0.085, Color(1, 0.81, 0.36, 0.85 if di % 2 == 0 else 0.45))
				di += 1
			prev = wpos
		var pulse: float = 0.5 + 0.5 * sin(_now() * 5.0)
		draw_arc(tc, TILE * (0.30 + 0.06 * pulse), 0, TAU, 28, Color(1, 0.81, 0.36, 0.95), 2.0)
		draw_arc(tc, TILE * (0.44 + 0.10 * pulse), 0, TAU, 28, Color(1, 0.81, 0.36, 0.35 * (1.0 - pulse)), 2.0)
	if selected_build == REMOVE_TOOL and sim._in(hover.x, hover.y):
		var own: bool = sim.bgrid.has(hover.y * n + hover.x)
		var rr := Rect2(hover.x * TILE + 3, hover.y * TILE + 3, TILE - 6, TILE - 6)
		var rc := Color.html("ff6b6b") if own else Color(1, 0.42, 0.42, 0.45)
		draw_rect(rr, Color(1, 0.35, 0.35, 0.25 if own else 0.1))
		draw_line(rr.position, rr.end, rc, 3.0)
		draw_line(Vector2(rr.end.x, rr.position.y), Vector2(rr.position.x, rr.end.y), rc, 3.0)
	elif selected_build != "" and sim._in(hover.x, hover.y):
		var sel_def: Dictionary = sim.building_def(selected_build)
		var have_it: bool = int(InventoryMod.count(sim, "bld:" + selected_build)) > 0 if sim.use_inventory else bool(sim.afford(sel_def.get("cost", {})))
		var okb: bool = not sel_def.is_empty() and sim.build_valid(hover.x, hover.y) and have_it
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
	for ei in sim.enemies.size():
		_draw_raider(sim.enemies[ei], ei)
	_draw_intents()
	_draw_action_target()
	_draw_bags()
	if cam:
		var vr2: Vector2 = get_viewport_rect().size / cam.zoom
		var vrect := Rect2(cam.get_screen_center_position() - vr2 / 2.0, vr2)
		_draw_edge_threats(vrect, cam.zoom.x)
		_draw_edge_bags(vrect, cam.zoom.x)
	_draw_player()
	for b in sim.buildings:   # hull plaque goes AFTER the pawn (T-Ніколая: герой біля капсули закривав підпис і ряди знаків)
		if String(b.kind) == MainCapsule.KIND:
			_draw_capsule_marks(Vector2(b.x * TILE, b.y * TILE), Vector2(b.x * TILE, b.y * TILE) + Vector2(TILE, TILE) * 0.5)
	_draw_fx()

# Shoreline: where land meets water, a thin pale foam line on the LAND edge and a dark wet rim on the
# WATER edge — turns a hard tile seam into a readable coast (the single biggest "map looks stitched" cue).
const FOAM := Color(0.80, 0.90, 0.95, 0.45)
const WET := Color(0.03, 0.10, 0.16, 0.35)
func _shore(tiles: PackedByteArray, n: int, x: int, y: int, t: int, tr: Rect2) -> void:
	var is_water: bool = t == 0
	var w := maxf(2.0, TILE * 0.09)
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for d in dirs:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if nx < 0 or ny < 0 or nx >= n or ny >= n:
			continue
		var nw: bool = tiles[ny * n + nx] == 0
		if nw == is_water:
			continue
		var edge: Rect2
		if d.y < 0:
			edge = Rect2(tr.position.x, tr.position.y, TILE, w)
		elif d.y > 0:
			edge = Rect2(tr.position.x, tr.position.y + TILE - w, TILE, w)
		elif d.x < 0:
			edge = Rect2(tr.position.x, tr.position.y, w, TILE)
		else:
			edge = Rect2(tr.position.x + TILE - w, tr.position.y, w, TILE)
		draw_rect(edge, WET if is_water else FOAM)

func _draw_node(node, x: int, y: int) -> void:
	var c := Vector2((x + 0.5) * TILE, (y + 0.5) * TILE)
	var r := TILE * 0.36
	var ntex := art_texture("sprite", "node_" + String(node.kind))
	if ntex != null:
		var tall: bool = String(node.kind) == "tree"
		var box := Rect2((x + 0.5) * TILE - TILE * (0.62 if tall else 0.5), (y + 1.0) * TILE - TILE * (1.5 if tall else 0.95), TILE * (1.24 if tall else 1.0), TILE * (1.5 if tall else 0.95))
		draw_contact_shadow(Vector2(c.x, (y + 0.92) * TILE), TILE * (0.34 if tall else 0.36))
		var kind_s := String(node.kind)
		var sway := 0.0
		if kind_s == "tree" or kind_s == "bush":   # wind: slow, per-cell phase so a forest ripples instead of marching
			var ph: float = float(x * 7 + y * 13)
			sway = sin(_now() * (1.3 if tall else 1.8) + ph * 0.6) * (0.022 if tall else 0.03)
		var a: Variant = sim.player.action
		if a is Dictionary and String(a.get("type", "")) == "gather" and int(a.get("cell", -1)) == y * sim.n + x and float(a.get("dur", 0.0)) > 0.0:
			sway += sin(_now() * 22.0) * 0.05   # the tool bites: the node jolts in time with the swing
		draw_sprite_fit(ntex, box, Color.WHITE, false, true, sway)
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
	var bcell: int = int(b.y) * int(sim.n) + int(b.x)
	var pop := 1.0                      # placement: ease-out-back scale 0.4 → 1.08 → 1.0 over 0.35 s + dust ring
	if _born.has(bcell):
		var ta: float = (_now() - float(_born[bcell])) / 0.35
		if ta >= 1.0:
			_born.erase(bcell)
		else:
			var c1 := 1.70158
			var u: float = ta - 1.0
			pop = 0.4 + 0.6 * (1.0 + (c1 + 1.0) * u * u * u + c1 * u * u)
			draw_arc(c + Vector2(0, TILE * 0.3), TILE * (0.3 + 0.5 * ta), 0, TAU, 24, Color(0.85, 0.78, 0.62, 0.5 * (1.0 - ta)), 2.0)
	if blocking_wall:
		_draw_wall_links(b, c)
	var btex := building_texture(String(b.kind))
	if btex != null:
		var floorlike: bool = String(b.kind) == "floor" or String(b.kind).ends_with("_floor") or String(b.kind) == "grow_zone"
		var inset := 0.0 if (floorlike or blocking_wall) else 1.0
		if floorlike:
			draw_texture_rect(btex, Rect2(p.x, p.y, TILE + 1, TILE + 1), false)
		else:
			draw_contact_shadow(Vector2(c.x, p.y + TILE * 0.92), TILE * 0.40)
			var bt := Color.WHITE
			if LIGHT_KINDS.has(String(b.kind)):   # fire/lamp: layered-sine flicker (not a clean sine) + warm halo
				var fk: float = 0.5 + 0.5 * sin(_now() * 9.0 + b.x * 3.1 + b.y * 1.7) * sin(_now() * 5.3 + b.y)
				bt = Color(1.0 + 0.18 * fk, 1.0 + 0.08 * fk, 1.0)
				draw_circle(c + Vector2(0, -TILE * 0.1), TILE * (0.62 + 0.10 * fk), Color(1.0, 0.62, 0.2, 0.10 + 0.07 * fk))
			draw_sprite_fit(btex, Rect2(p.x + inset, p.y - TILE * 0.12, TILE - 2 * inset, TILE * 1.08), bt, false, true, 0.0, Vector2(pop, pop))
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

# Плейтест 2026-11-08 #4: стіни читались рядом окремих плашок. Балка до східного/південного сусіда-стіни (view-only, без арту):
# кожну пару малюємо один раз (від західної/північної клітинки), під спрайтами, тож контур лінії = контур споруди.
func _draw_wall_links(b, c: Vector2) -> void:
	var stone: bool = String(b.kind).begins_with("stone")
	var beam := Color(0.46, 0.47, 0.50, 1.0) if stone else Color(0.43, 0.31, 0.19, 1.0)
	var rim := Color(0.04, 0.05, 0.06, 0.85)
	var w: float = TILE * 0.26
	for d in [Vector2i(1, 0), Vector2i(0, 1)]:
		var nx: int = int(b.x) + d.x
		var ny: int = int(b.y) + d.y
		if nx >= int(sim.n) or ny >= int(sim.n):
			continue
		var ncell: int = ny * int(sim.n) + nx
		if not sim.bgrid.has(ncell):
			continue
		var nb: Dictionary = sim.bgrid[ncell]
		var nk := String(nb.kind)
		if not (nk == "wall" or (nk.ends_with("_wall") and bool(sim.building_def(nk).get("blocks", false)))):
			continue
		var e: Vector2 = c + Vector2(d) * TILE
		draw_line(c, e, rim, w + 2.0)
		draw_line(c, e, beam, w)

# Основна капсула, greybox (spec 0010 REQ-0010-87; арт — лише після G0–G1, P4): ОДНА підписана табличка під корпусом (T-Ніколая: знаки без слів
# лежали на спрайтах і не читались). Рядки: назва; «Рівень n/5» + ряд кружків; «Захист n/5» + ряд квадратів (R11: різна ФОРМА, не лише колір);
# під імунітетом — ще рядок із часом і щит-кільце навколо корпусу. Корпус обведений, щоб серед столу/бочки було видно, ЩО саме капсула.
func _draw_capsule_marks(p: Vector2, c: Vector2) -> void:
	var cap: Dictionary = sim.main_capsule
	var lvl: int = int(cap.get("level", 0))
	var prot: int = int(cap.get("protection", 0))
	var lamp_n: int = maxi(1, MainCapsule.max_level(sim))
	var plate_n: int = maxi(1, MainCapsule.max_protection(sim))
	var amber := Color(0.88, 0.69, 0.44, 1.0)
	var steel := Color(0.53, 0.82, 0.84, 1.0)
	var empty := Color(0.78, 0.83, 0.86, 0.5)
	var fs := 10
	var step := 10.0
	var t_level: String = CapsuleTexts.t("mark_level") % [lvl, lamp_n]
	var t_prot: String = CapsuleTexts.t("mark_protect") % [prot, plate_n]
	var title: String = CapsuleTexts.t("capsule_title")
	var imm: bool = MainCapsule.is_immune(sim)
	var t_imm: String = CapsuleTexts.t("mark_immune") % Fmt.left_ms(MainCapsule.immune_left_ms(sim)) if imm else ""
	var tw: float = 0.0
	for s in [t_level, t_prot]:
		tw = maxf(tw, _font.get_string_size(String(s), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var w: float = maxf(tw + step * float(maxi(lamp_n, plate_n)) + 14.0, _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0)
	w = maxf(w, _font.get_string_size(t_imm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0)
	# T-Ніколая 2026-11-09 (OD «лише поруч/hover»): повна табличка — лише коли герой ≤3.5 клітинки або курсор на капсулі/під нею;
	# здалеку — контур корпусу + назва одним рядком (тексти й числа спеки не змінено). Імунітет показуємо завжди (це подія, не стан).
	var cell: Vector2 = Vector2((p.x + TILE * 0.5) / TILE, (p.y + TILE * 0.5) / TILE)
	var near_hero: bool = Vector2(float(sim.player.px), float(sim.player.py)).distance_to(cell) <= 3.5
	var near_ptr: bool = absi(hover.x - int(p.x / TILE)) <= 1 and hover.y >= int(p.y / TILE) and hover.y <= int(p.y / TILE) + 3
	var placing: bool = selected_build != ""   # привид у руці: табличка не лежить на землі, куди ставиш («біля пішака»)
	if not ((near_hero and not placing) or near_ptr or imm):
		draw_rect(Rect2(p, Vector2(TILE, TILE)), amber, false, 1.5)
		_mark_text(c + Vector2(0.0, TILE * 0.95), title, Color(1.0, 0.93, 0.8))
		return
	var rows: int = 4 if imm else 3
	var box := Rect2(c.x - w * 0.5, p.y + TILE + 4.0, w, 13.0 * float(rows) + 3.0)
	draw_rect(Rect2(p, Vector2(TILE, TILE)), amber, false, 1.5)
	draw_line(Vector2(c.x, p.y + TILE), Vector2(c.x, box.position.y), amber, 1.0)
	draw_rect(box, Color(0.04, 0.05, 0.06, 0.92))
	draw_rect(box, Color(amber.r, amber.g, amber.b, 0.8), false, 1.0)
	var y: float = box.position.y + 11.0
	draw_string(_font, Vector2(box.position.x + 5.0, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.93, 0.8))
	y += 13.0
	draw_string(_font, Vector2(box.position.x + 5.0, y), t_level, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, amber)
	for i in lamp_n:
		var at := Vector2(box.end.x - 5.0 - step * float(lamp_n - i) + step * 0.5, y - 3.5)
		if i < lvl:
			draw_circle(at, 3.6, amber)
		else:
			draw_arc(at, 3.2, 0.0, TAU, 12, empty, 1.5)
	y += 13.0
	draw_string(_font, Vector2(box.position.x + 5.0, y), t_prot, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, steel)
	for i in plate_n:
		var r := Rect2(box.end.x - 5.0 - step * float(plate_n - i) + step * 0.5 - 3.2, y - 6.7, 6.4, 6.4)
		if i < prot:
			draw_rect(r, steel)
		else:
			draw_rect(r, empty, false, 1.5)
	if imm:
		y += 13.0
		draw_string(_font, Vector2(box.position.x + 5.0, y), t_imm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, steel)
		draw_circle(c, TILE * 0.80, Color(steel.r, steel.g, steel.b, 0.12))
		draw_arc(c, TILE * 0.80, 0.0, TAU, 32, Color(steel.r, steel.g, steel.b, 0.85), 2.0)
		var ring_txt: String = CapsuleTexts.t("immune_ring")   # кільце без слів читалось як радіус; підкладка — напис на тлі будівель нечитний (T-Ніколая)
		var rw: float = _font.get_string_size(ring_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10.0
		var rr := Rect2(c.x - rw * 0.5, c.y - TILE * 0.95 - 13.0, rw, 17.0)
		draw_rect(rr, Color(0.04, 0.05, 0.06, 0.92))
		draw_rect(rr, Color(steel.r, steel.g, steel.b, 0.85), false, 1.0)
		_mark_text(c + Vector2(0.0, -TILE * 0.95), ring_txt, Color(0.80, 0.97, 0.98))

func _mark_text(at: Vector2, text: String, col: Color) -> void:
	var fs := 11
	var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(at.x - w * 0.5, at.y)
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0.04, 0.05, 0.06, 0.9))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _draw_raider(e, idx: int = 0) -> void:
	var c := Vector2(e.px * TILE, e.py * TILE)
	var r := TILE * 0.34
	var is_bot: bool = String(e.get("kind", "raider")) == "bot"
	var atex := art_texture("actor", "actor_patrol_robot" if is_bot else "actor_raider")
	if atex != null:
		_draw_actor(atex, c, cos(e.face), HIT_FLASH if e.hit_flash > 0 else Color.WHITE, 100 + idx, clampf(float(e.hit_flash) / 0.12, 0.0, 1.0) * 0.08)
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

# --- threat telegraphing (Into the Breach / Slay the Spire): every enemy shows its INTENT before it acts —
# what it is about to do + the number. Derived from sim data (distance, path, target) — view only. ---
const INTENT_HIT := Color(0.88, 0.42, 0.36, 1.0)
const INTENT_WARN := Color(0.88, 0.69, 0.44, 1.0)
func enemy_intent(e) -> Dictionary:
	var p: Dictionary = sim.player
	var d: float = Vector2(e.px, e.py).distance_to(Vector2(p.px, p.py))
	if d < 1.25:
		return {"glyph": "⚔", "num": int(round(float(e.dmg) * float(sim.armor_mult()))), "col": INTENT_HIT, "hunt": true}
	if not (e.path as Array).is_empty():
		var nx: Vector2i = e.path[0]
		var bi: int = nx.y * sim.n + nx.x
		if sim.bgrid.has(bi) and bool(sim.building_def(String(sim.bgrid[bi].kind)).get("blocks", false)):
			return {"glyph": "🔨", "num": int(e.dmg), "col": INTENT_WARN, "hunt": false}
	if int(e.tx) == int(p.px) and int(e.ty) == int(p.py):
		return {"glyph": "⚔", "num": int(round(float(e.dmg) * float(sim.armor_mult()))), "col": INTENT_WARN, "hunt": true}
	return {"glyph": "👁" if String(e.get("kind", "raider")) == "bot" else "⚑", "num": -1, "col": Color(0.53, 0.82, 0.84, 1.0), "hunt": false}

static func _intent_word(it: Dictionary) -> String:
	match String(it.glyph):
		"⚔": return "удар −%d" % int(it.num)
		"🔨": return "ламає стіну"
		"👁": return "патруль"
	return "блукає"

func _draw_intents() -> void:
	for e in sim.enemies:
		var it := enemy_intent(e)
		var head := Vector2(e.px * TILE, e.py * TILE - TILE * 1.35)
		if bool(it.hunt):   # the next three steps of its path, as a red dotted line on the ground
			var prev := Vector2(e.px * TILE, e.py * TILE)
			for k in mini(3, (e.path as Array).size()):
				var w: Vector2i = e.path[k]
				var q := Vector2((w.x + 0.5) * TILE, (w.y + 0.5) * TILE)
				for j in 3:
					draw_circle(prev.lerp(q, (j + 0.5) / 3.0), TILE * 0.06, Color(it.col.r, it.col.g, it.col.b, 0.75))
				prev = q
		var fs := int(TILE * 0.42)
		# glyph + a WORD: «🔨11» read as «level? HP?» in the independent read (gamedev §5) — say the intent
		var label: String = String(it.glyph) + " " + _intent_word(it)
		var tw: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var rr := Rect2(head.x - tw * 0.5 - 5.0, head.y - fs * 0.95, tw + 10.0, fs * 1.25)
		draw_rect(rr, Color(0.05, 0.07, 0.09, 0.85))
		draw_rect(rr, it.col, false, 1.5)
		draw_string(_font, Vector2(rr.position.x + 5.0, head.y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, it.col)

# The auto-target BEFORE the tap (Terraria smart-cursor square / Brawl auto-aim): corner brackets in the
# mode colour, gently breathing, so the player always knows what the action button will hit.
func _draw_action_target() -> void:
	if action_target.is_empty():
		return
	var col: Color = ACTION_COL.get(action_mode, Color.WHITE)
	var p := Vector2(float(action_target.x), float(action_target.y)) * TILE
	if StringName(action_target.get("kind", &"")) == &"enemy" and action_target.ref is Dictionary:
		p = Vector2(action_target.ref.px - 0.5, action_target.ref.py - 0.5) * TILE
	var k: float = 0.5 + 0.5 * sin(_now() * 5.0)
	var pad: float = TILE * (0.02 + 0.06 * k)
	var r := Rect2(p - Vector2(pad, pad), Vector2(TILE + 2 * pad, TILE + 2 * pad))
	if action_mode == &"build" and action_build != "":   # empty brackets did not say WHAT lands there (3rd read)
		var gtex := building_texture(action_build)
		if gtex != null:
			draw_texture_rect(gtex, Rect2(p, Vector2(TILE, TILE)), false, Color(1, 1, 1, 0.8 + 0.2 * k))
	var arm: float = TILE * 0.3
	var w := 3.0
	for corner in [[r.position, Vector2(1, 0), Vector2(0, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 0), Vector2(0, 1)],
			[Vector2(r.position.x, r.end.y), Vector2(1, 0), Vector2(0, -1)], [r.end, Vector2(-1, 0), Vector2(0, -1)]]:
		draw_line(corner[0], corner[0] + corner[1] * arm, col, w)
		draw_line(corner[0], corner[0] + corner[2] * arm, col, w)

# spec 0009: dropped / death bags on the map — the backpack art bobbing on the cell, an amber halo for a death
# bag (your pawn's whole kit) — and an amber edge arrow when it is off screen (the «map marker»).
const BAG_COL := Color(0.88, 0.69, 0.44, 1.0)
func _draw_bags() -> void:
	if sim.get("bags") == null:
		return
	var tex := art_texture("ui", "ui_carry")
	for bag in sim.bags:
		var c := Vector2((int(bag.x) + 0.5) * TILE, (int(bag.y) + 0.5) * TILE)
		var bob: float = sin(_now() * 3.0 + float(bag.x)) * TILE * 0.06
		var death: bool = (bag.slots as Array).size() > 1
		if death:
			var rr: float = TILE * (0.48 + 0.05 * sin(_now() * 4.0))
			draw_circle(c, rr, Color(BAG_COL.r, BAG_COL.g, BAG_COL.b, 0.22))
			draw_arc(c, rr, 0.0, TAU, 32, Color(BAG_COL.r, BAG_COL.g, BAG_COL.b, 0.85), 2.0, true)   # reads on dark rock too
		draw_contact_shadow(c + Vector2(0, TILE * 0.3), TILE * 0.28)
		if tex != null:
			draw_sprite_fit(tex, Rect2(c.x - TILE * 0.38, c.y - TILE * 0.5 - bob, TILE * 0.76, TILE * 0.76))
		else:
			draw_circle(c - Vector2(0, bob), TILE * 0.25, BAG_COL)

func _draw_edge_bags(view: Rect2, zoom: float) -> void:
	if sim.get("bags") == null:
		return
	var inner := view.grow(-26.0 / maxf(zoom, 0.01))
	var ctr := view.get_center()
	for bag in sim.bags:
		var bp := Vector2((int(bag.x) + 0.5) * TILE, (int(bag.y) + 0.5) * TILE)
		if view.has_point(bp):
			continue
		var dir: Vector2 = (bp - ctr).normalized()
		var tmax := INF
		if absf(dir.x) > 0.001:
			tmax = minf(tmax, (inner.size.x * 0.5) / absf(dir.x))
		if absf(dir.y) > 0.001:
			tmax = minf(tmax, (inner.size.y * 0.5) / absf(dir.y))
		var at: Vector2 = ctr + dir * tmax
		var r: float = 9.0 / maxf(zoom, 0.01)
		draw_circle(at, r, BAG_COL)
		draw_arc(at, r, 0, TAU, 20, Color(0.05, 0.07, 0.09, 0.9), 1.5 / maxf(zoom, 0.01))
		draw_line(at + dir * r, at + dir * r * 2.0, BAG_COL, 2.5 / maxf(zoom, 0.01))

# Off-screen threats: a pulsing arrow on the screen edge pointing at each enemy outside the view (edge
# indicators — the low-clutter alternative to a minimap). `view` is the camera rect in world px.
func _draw_edge_threats(view: Rect2, zoom: float) -> void:
	var inset: float = 26.0 / maxf(zoom, 0.01)
	var inner := view.grow(-inset)
	var ctr := view.get_center()
	var pulse: float = 0.6 + 0.4 * sin(_now() * 6.0)
	for e in sim.enemies:
		var ep := Vector2(e.px * TILE, e.py * TILE)
		if view.has_point(ep):
			continue
		var dir: Vector2 = (ep - ctr).normalized()
		var tmax := INF
		if absf(dir.x) > 0.001:
			tmax = minf(tmax, (inner.size.x * 0.5) / absf(dir.x))
		if absf(dir.y) > 0.001:
			tmax = minf(tmax, (inner.size.y * 0.5) / absf(dir.y))
		var at: Vector2 = ctr + dir * tmax
		var sz: float = 11.0 / maxf(zoom, 0.01)
		var side := Vector2(-dir.y, dir.x)
		var pts := PackedVector2Array([at + dir * sz, at - dir * sz * 0.6 + side * sz * 0.8, at - dir * sz * 0.6 - side * sz * 0.8])
		draw_colored_polygon(pts, Color(INTENT_HIT.r, INTENT_HIT.g, INTENT_HIT.b, pulse))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.05, 0.07, 0.09, 0.9), 1.5 / maxf(zoom, 0.01))

# Actor sprite: ~1.5 tiles, feet near the pawn's position, mirrored when facing left.
func _draw_actor(tex: Texture2D, c: Vector2, face_x: float, tint: Color, key: int = 0, hit: float = 0.0, work: float = 0.0) -> void:
	var sz := TILE * 1.9
	var g := _gait_of(key, c)
	var t := _now()
	# idle breathing (slow, ~2%) → walking bob + lean (step-synced) → hit squash → work swing, additive
	var breath: float = sin(t * 2.2 + float(key % 7)) * 0.018 * (1.0 - g.y)
	var bob: float = absf(sin(g.x * 1.6)) * TILE * 0.07 * g.y
	var lean: float = sin(g.x * 1.6) * 0.06 * g.y * (-1.0 if face_x < -0.2 else 1.0)
	var squash := Vector2(1.0 - breath * 0.5 + hit * 2.2, 1.0 + breath - hit * 1.6)
	var swing: float = sin(t * 11.0) * 0.10 * work
	draw_contact_shadow(c + Vector2(0, TILE * 0.36), TILE * (0.32 - 0.03 * (bob / maxf(TILE * 0.07, 0.001))))
	draw_sprite_fit(tex, Rect2(c.x - sz * 0.5, c.y + TILE * 0.40 - sz - bob, sz, sz), tint, face_x < -0.2, true, lean + swing, squash)

func _draw_player() -> void:
	var p: Dictionary = sim.player
	var c := Vector2(p.px * TILE, p.py * TILE)
	var r := TILE * 0.34
	# «this is you»: a thin amber ground ring under the hero, slowly breathing (readable at a glance among actors)
	draw_set_transform(c + Vector2(0, TILE * 0.36), 0.0, Vector2(1.0, 0.42))
	draw_arc(Vector2.ZERO, TILE * (0.46 + 0.02 * sin(_now() * 2.0)), 0, TAU, 32, Color(0.88, 0.69, 0.44, 0.75), 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var htex := art_texture("actor", "actor_hero")
	if htex != null:
		var working: bool = p.action != null and String(p.action.get("type", "")) == "gather"
		var htint: Color = HIT_FLASH if _hero_flash > 0.0 else (Color(0.62, 0.72, 0.95) if p.sleeping else Color.WHITE)
		_draw_actor(htex, c, cos(p.face), htint, 1, 0.08 if _hero_flash > 0.0 else 0.0, 1.0 if working else 0.0)
	else:
		draw_circle(c, r, Color.html("7da0c0") if p.sleeping else Color.html("e7c25a"))
		draw_arc(c, r, 0, TAU, 18, Color.html("1c2530"), 2.0)
		draw_circle(c + Vector2(cos(p.face), sin(p.face)) * r * 0.55, r * 0.22, Color.html("1c2530"))
	if p.action != null and p.action.type == "gather" and float(p.action.get("dur", 0)) > 0:
		var frac: float = clampf(p.action.t / p.action.dur, 0, 1)
		draw_arc(c, r + 5, -PI / 2, -PI / 2 + frac * TAU, 24, Color.html("5db0ff"), 3.0)
