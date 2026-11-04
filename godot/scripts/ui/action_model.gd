# RealWorld — ui/action_model.gd : PURE logic of the touch action scheme (no nodes, no sim writes).
#
# The phone controls: left stick moves, the right ACTION control acts on the auto-target in front of the
# hero. This file is the testable half: gesture classification, modes, auto-target (cone + range +
# priority), the primary verb per mode, the radial-menu options per target, and the quick-slot model.
# Everything returns VALUE data ({verb, args}) — the scene routes verbs (R9); nothing here mutates the sim.
extends RefCounted

const GameData = preload("res://scripts/data.gd")

# Gesture timings (Android ViewConfiguration: double-tap ≈300 ms, long-press ≈400–500 ms; tap slop ≈ 8 dp
# → 14 logical px at our ~0.16 mm/px). A horizontal/vertical DRAG is a swipe past DRAG_MIN on one axis.
const DOUBLE_TAP := 0.30
const HOLD := 0.40            # AOSP DEFAULT_LONG_PRESS_TIMEOUT (was 500, now 400 ms)
const SLOP := 14.0
const DRAG_MIN := 34.0
const DRAG_STEP := 46.0          # one quick-slot step / one zoom notch per this many px of drag

const MODES: Array[StringName] = [&"gather", &"build", &"repair", &"fight"]
const MODE_INFO := {
	&"gather": {"label": "Добувати", "glyph": "⛏"},
	&"build":  {"label": "Будувати", "glyph": "🔨"},
	&"repair": {"label": "Ремонт",   "glyph": "🔧"},
	&"fight":  {"label": "Бій",      "glyph": "⚔"},
}
# auto-target reach per mode (tiles) and the facing cone (half-angle). In-cone targets win; outside the
# cone a target still counts but pays a distance penalty (soft lock — the player is rarely perfectly aimed).
const RANGE := {&"gather": 3.2, &"build": 2.0, &"repair": 4.0, &"fight": 7.0}
const CONE := deg_to_rad(45.0)          # Opsive/Brawl-style assist cone
const STICKY_CONE := deg_to_rad(70.0)   # a held target survives a wider swing (no flicker)
const OFF_CONE_PENALTY := 2.5

# Sticky target: keep the previous target while it is still valid, in range and inside the wider cone —
# auto-aim that flickers between two trees is worse than none (Opsive «stickiness angle»).
static func keep_target(sim, prev: Dictionary, mode: StringName, origin: Vector2, facing: float) -> bool:
	if prev.is_empty() or StringName(prev.get("mode", &"")) != mode:
		return false
	var pos := Vector2(float(prev.x) + 0.5, float(prev.y) + 0.5)
	if StringName(prev.kind) == &"enemy":
		var e: Variant = prev.ref
		if not (e is Dictionary) or bool(e.get("dead", false)) or not sim.enemies.has(e):
			return false
		pos = Vector2(e.px, e.py)
	elif StringName(prev.kind) == &"node":
		if not sim.map.nodes.has(int(prev.y) * int(sim.n) + int(prev.x)):
			return false
	elif StringName(prev.kind) == &"building":
		if not sim.bgrid.has(int(prev.y) * int(sim.n) + int(prev.x)):
			return false
	var d: float = pos.distance_to(origin)
	if d > float(RANGE.get(mode, 3.0)) + 0.5:
		return false
	return d < 0.8 or absf(Vector2(cos(facing), sin(facing)).angle_to(pos - origin)) <= STICKY_CONE

static func next_mode(m: StringName) -> StringName:
	var i: int = MODES.find(m)
	return MODES[(i + 1) % MODES.size()]

# held = seconds the finger was down; moved = total drag vector; gap = seconds since the previous tap's
# release (INF if none). Order matters: a drag is never a tap; a quick second tap is a double, not a tap.
static func classify(held: float, moved: Vector2, gap: float) -> StringName:
	if absf(moved.y) >= DRAG_MIN and absf(moved.y) > absf(moved.x):
		return &"drag_v"
	if absf(moved.x) >= DRAG_MIN:
		return &"drag_h"
	if moved.length() > SLOP:
		return &"none"                      # a wobble that is neither a tap nor a swipe does nothing
	if held >= HOLD:
		return &"hold"
	if gap <= DOUBLE_TAP:
		return &"double"
	return &"tap"

# ---- auto-target ---------------------------------------------------------------------------------
# Returns {} when nothing fits; otherwise {kind: &"node"|&"enemy"|&"building"|&"cell", x, y, ref?, dist}.
# `origin` is the hero (tile units, float); `facing` radians; `cursor` (Vector2i, optional) overrides the
# hero-relative search with «what is under the overview cursor».
static func pick_target(sim, mode: StringName, origin: Vector2, facing: float, build_kind: String = "", cursor: Variant = null) -> Dictionary:
	if cursor is Vector2i:
		return target_at(sim, cursor, mode, build_kind)
	var reach: float = float(RANGE.get(mode, 3.0))
	var fwd := Vector2(cos(facing), sin(facing))
	var best := {}
	var acc := {"score": INF}   # GDScript lambdas capture locals BY VALUE — the running best must live in a container
	var consider := func(kind: StringName, pos: Vector2, x: int, y: int, ref: Variant) -> void:
		var d: float = pos.distance_to(origin)
		if d > reach:
			return
		var to: Vector2 = (pos - origin)
		var in_cone: bool = d < 0.6 or fwd.angle_to(to.normalized()) <= CONE and fwd.angle_to(to.normalized()) >= -CONE
		var score: float = d + (0.0 if in_cone else OFF_CONE_PENALTY)
		if score < float(acc.score):
			acc.score = score
			best.clear()
			best.merge({"kind": kind, "x": x, "y": y, "dist": d, "ref": ref})
	match mode:
		&"gather":
			for key in sim.map.nodes:
				var nx: int = int(key) % int(sim.n)
				var ny: int = int(key) / int(sim.n)
				consider.call(&"node", Vector2(nx + 0.5, ny + 0.5), nx, ny, null)
		&"fight":
			for e in sim.enemies:
				consider.call(&"enemy", Vector2(e.px, e.py), int(e.px), int(e.py), e)
		&"repair":
			for b in sim.buildings:
				var def: Dictionary = sim.building_def(String(b.kind))
				if float(b.hp) < float(def.get("hp", 50.0)):
					consider.call(&"building", Vector2(b.x + 0.5, b.y + 0.5), int(b.x), int(b.y), b)
		&"build":
			if build_kind == "":
				return {}
			# the cell one step ahead; if that is invalid, the nearest valid neighbour around the hero
			var ahead := Vector2i(int(floor(origin.x + fwd.x * 1.2)), int(floor(origin.y + fwd.y * 1.2)))
			if sim.build_valid(ahead.x, ahead.y) and ahead != Vector2i(int(origin.x), int(origin.y)):
				return {"kind": &"cell", "x": ahead.x, "y": ahead.y, "dist": 1.2, "ref": null}
			for r in [1, 2]:
				for dy in range(-r, r + 1):
					for dx in range(-r, r + 1):
						var c := Vector2i(int(origin.x) + dx, int(origin.y) + dy)
						if (dx != 0 or dy != 0) and sim.build_valid(c.x, c.y):
							consider.call(&"cell", Vector2(c.x + 0.5, c.y + 0.5), c.x, c.y, null)
				if not best.is_empty():
					break
	return best

# What sits on a given cell, interpreted for a mode (overview cursor / long-press on the map).
static func target_at(sim, c: Vector2i, mode: StringName = &"gather", build_kind: String = "") -> Dictionary:
	if not sim._in(c.x, c.y):
		return {}
	for e in sim.enemies:
		if int(e.px) == c.x and int(e.py) == c.y:
			return {"kind": &"enemy", "x": c.x, "y": c.y, "dist": 0.0, "ref": e}
	var i: int = c.y * int(sim.n) + c.x
	if sim.map.nodes.has(i):
		return {"kind": &"node", "x": c.x, "y": c.y, "dist": 0.0, "ref": null}
	if sim.bgrid.has(i):
		return {"kind": &"building", "x": c.x, "y": c.y, "dist": 0.0, "ref": sim.bgrid[i]}
	if mode == &"build" and build_kind != "" and sim.build_valid(c.x, c.y):
		return {"kind": &"cell", "x": c.x, "y": c.y, "dist": 0.0, "ref": null}
	return {"kind": &"ground", "x": c.x, "y": c.y, "dist": 0.0, "ref": null}

# The TAP: the mode's verb on the target ({} = nothing to do; the scene flashes a reason).
static func primary(mode: StringName, t: Dictionary, build_kind: String = "") -> Dictionary:
	if t.is_empty():
		return {}
	var k: StringName = t.kind
	var xy := {"x": int(t.x), "y": int(t.y)}
	if k == &"enemy":
		return {"verb": &"order_attack", "args": {"target": t.ref}}
	if k == &"node":
		return {"verb": &"order_gather", "args": xy}
	match mode:
		&"build":
			if k == &"cell" and build_kind != "":
				return {"verb": &"build", "args": {"kind": build_kind, "x": int(t.x), "y": int(t.y)}}
		&"repair":
			if k == &"building":
				return {"verb": &"repair", "args": xy}
	if k == &"ground" or k == &"cell":
		return {"verb": &"order_move", "args": xy}
	return {}

# The radial menu (hold / long-press): every sensible verb for this target, primary first.
static func options(sim, t: Dictionary, build_kind: String = "") -> Array:
	var out: Array = []
	if t.is_empty():
		return out
	var xy := {"x": int(t.x), "y": int(t.y)}
	match StringName(t.kind):
		&"enemy":
			out.append({"verb": &"order_attack", "args": {"target": t.ref}, "label": "Атакувати", "glyph": "⚔"})
		&"node":
			out.append({"verb": &"order_gather", "args": xy, "label": "Добути", "glyph": "⛏"})
		&"building":
			var b: Dictionary = t.ref
			var def: Dictionary = sim.building_def(String(b.kind))
			if float(b.hp) < float(def.get("hp", 50.0)):
				out.append({"verb": &"repair", "args": xy, "label": "Ремонт", "glyph": "🔧"})
			if String(b.kind) == "grow_zone":
				out.append({"verb": &"set_crop", "args": xy, "label": "Культура", "glyph": "🌱"})
			out.append({"verb": &"deconstruct", "args": xy, "label": "Розібрати", "glyph": "🗑"})
		&"cell", &"ground":
			if build_kind != "" and sim.build_valid(int(t.x), int(t.y)):
				out.append({"verb": &"build", "args": {"kind": build_kind, "x": int(t.x), "y": int(t.y)}, "label": "Будувати", "glyph": "🔨"})
	out.append({"verb": &"order_move", "args": xy, "label": "Іти сюди", "glyph": "👣"})
	return out

# ---- quick slots -----------------------------------------------------------------------------------
# A slot is {type: &"tool"|&"weapon"|&"build"|&"repair"|&"hands", id, glyph, label}. Picking one switches
# the mode automatically (axe → Gather, weapon → Fight, building → Build, hammer → Repair).
static func mode_for_slot(slot: Dictionary) -> StringName:
	match StringName(slot.get("type", &"hands")):
		&"weapon": return &"fight"
		&"build":  return &"build"
		&"repair": return &"repair"
		_:         return &"gather"

# Default/auto-filled bar: best gather tool (or hands), best weapon (or fists), the armed building, repair,
# then pinned extras. Pure function of what the hero owns — re-derived every frame, so crafting an axe
# simply makes it appear (no stale slot).
static func default_slots(sim, build_kind: String, pinned: Array = []) -> Array:
	var items: Array = sim.player.get("items", [])
	var tool := ""
	var weapon := ""
	for id in items:
		var it: Dictionary = GameData.ITEMS.get(id, {})
		if String(it.get("slot", "")) == "tool" and (tool == "" or float(it.get("gather_mult", 1.0)) > float(GameData.ITEMS[tool].get("gather_mult", 1.0))):
			tool = String(id)
		elif String(it.get("slot", "")) == "weapon" and (weapon == "" or float(it.get("dmg", 0.0)) > float(GameData.ITEMS[weapon].get("dmg", 0.0))):
			weapon = String(id)
	var out: Array = []
	out.append({"type": &"tool", "id": tool, "label": String(GameData.ITEMS[tool].name) if tool != "" else "Руки", "glyph": "⛏" if tool != "" else "✋"})
	out.append({"type": &"weapon", "id": weapon, "label": String(GameData.ITEMS[weapon].name) if weapon != "" else "Кулаки", "glyph": "⚔"})
	var bk: String = build_kind if build_kind != "" else "campfire"
	out.append({"type": &"build", "id": bk, "label": String(sim.building_def(bk).get("name", bk)), "glyph": "🔨"})
	out.append({"type": &"repair", "id": "", "label": "Ремонт", "glyph": "🔧"})
	for p in pinned:
		if out.size() >= 6:
			break
		out.append(p)
	return out
