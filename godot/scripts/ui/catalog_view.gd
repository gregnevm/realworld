# RealWorld — ui/catalog_view.gd : the CONTENT-TREE ViewModel (the catalogue's HudModel analogue).
#
# PURE + Node-free (never extends Node, never a raw color / get_node): the single place that turns the deep
# content catalogue (kernel/catalog.gd Defs) + a play STATE ({unlocked research, stock}) into UI-ready
# value-data slices — exactly the shape hud_model.gd builds for the live sim. It maps raw defs to enums
# itself (status &unlocked/&available/&locked) and returns ONLY value data (ids, enums, numbers,
# Strings, and Arrays/Dicts of those) so it satisfies R8 like any other slice. Panels bind these slices;
# they never reach into the DefDatabase themselves.
#
# The pipeline: catalog.json → Catalog.build_db() (DefDatabase of typed defs) → CatalogView.snapshot()
# (this file, value-data) → catalog_panels.gd (build-once + bind) → Widgets → Tokens. One-way (R1).
extends RefCounted

const Catalog = preload("res://scripts/kernel/catalog.gd")

# Lazily-built, process-cached DefDatabase of the on-disk catalogue. The HUD reads the tree every frame
# through snapshot(); building the DB once and reusing it keeps that hot path allocation-free (the same
# reason HudRoot constructs the Balance director ONCE, never per frame).
static var _db = null
static func default_db():
	if _db == null:
		_db = Catalog.build_db()
	return _db

# ---- state helpers -------------------------------------------------------------------------------

# Every prereq of a research def already in `unlocked`?
static func _prereqs_met(rdef, unlocked: Dictionary) -> bool:
	for p in rdef.prereqs():
		if not unlocked.has(StringName(str(p))):
			return false
	return true

# Research status enum: &"unlocked" (done) · &"available" (can start now) · &"locked" (prereqs unmet).
static func research_status(rdef, unlocked: Dictionary) -> StringName:
	if unlocked.has(rdef.id):
		return &"unlocked"
	return &"available" if _prereqs_met(rdef, unlocked) else &"locked"

# A research gate ("" == ungated) is satisfied when the named project is unlocked.
static func _gate_ok(ref, unlocked: Dictionary) -> bool:
	var r: String = str(ref)
	return r == "" or unlocked.has(StringName(r))

# Every key of a cost/input dict is present in `stock` at >= the required amount.
static func _afford(cost: Dictionary, stock: Dictionary) -> bool:
	for k in cost:
		if float(stock.get(k, 0)) < float(cost[k]):
			return false
	return true

# Human-readable "🪵3 🪨5"-style cost line via the def labels (kept value-data — it returns a String).
static func cost_str(db, cost: Dictionary) -> String:
	var parts: Array = []
	for k in cost:
		var d = db.get_def(StringName(str(k)))
		var icon: String = (d.icon() if d != null and d.has_method("icon") else "")
		parts.append("%s%d" % [icon if icon != "" else str(k) + " ", int(cost[k])])
	return " ".join(parts)

# ---- the snapshot (value-data slices; the assess()/HudModel.snapshot() analogue) -----------------
#
# state: {"unlocked": {research_id: true}, "stock": {res_id: amt}}. A missing state is the neolithic
# start (nothing researched, empty stock) — the encyclopedia still renders the whole tree, gated.
static func snapshot(db, state: Dictionary = {}) -> Dictionary:
	if db == null:
		return {"available": false}
	var unlocked: Dictionary = state.get("unlocked", {})
	var stock: Dictionary = state.get("stock", {})
	return {
		"available": true,
		"summary": _summary(db, unlocked, stock),
		"research": _research_rows(db, unlocked),
		"tiers": _tiers(db, unlocked),
		"next": _next_research(db, unlocked),
	}

# Per-tier research progress: [{tier, unlocked, total}] ascending — the tech-era climb (neolithic→spacer).
static func _tiers(db, unlocked: Dictionary) -> Array:
	var by_tier: Dictionary = {}
	for r in Catalog.research_projects(db):
		var t: int = int(r.data.get("tier", 0))
		if not by_tier.has(t):
			by_tier[t] = {"unlocked": 0, "total": 0}
		by_tier[t]["total"] = int(by_tier[t]["total"]) + 1
		if unlocked.has(r.id):
			by_tier[t]["unlocked"] = int(by_tier[t]["unlocked"]) + 1
	var keys: Array = by_tier.keys()
	keys.sort()
	var out: Array = []
	for t in keys:
		out.append({"tier": int(t), "unlocked": int(by_tier[t]["unlocked"]), "total": int(by_tier[t]["total"])})
	return out

static func _summary(db, unlocked: Dictionary, stock: Dictionary) -> Dictionary:
	var research: Array = Catalog.research_projects(db)
	var researched := 0
	for r in research:
		if unlocked.has(r.id):
			researched += 1
	var buildable := 0
	for b in Catalog.buildings(db):
		if _gate_ok(b.research(), unlocked) and _afford(b.cost(), stock):
			buildable += 1
	var craftable := 0
	for rc in Catalog.recipes(db):
		if _gate_ok(rc.requires_research(), unlocked) and _afford(rc.inputs(), stock):
			craftable += 1
	var total_research: int = research.size()
	return {
		"resources": Catalog.resources(db).size(),
		"research": total_research,
		"buildings": Catalog.buildings(db).size(),
		"recipes": Catalog.recipes(db).size(),
		"items": Catalog.items(db).size(),
		"researched": researched,
		"buildable": buildable,
		"craftable": craftable,
		"progress": (float(researched) / float(total_research)) if total_research > 0 else 0.0,
	}

# Research rows sorted by tier then id, each carrying a status enum (R11) + cost + prereq labels.
static func _research_rows(db, unlocked: Dictionary) -> Array:
	var rows: Array = []
	var defs: Array = Catalog.research_projects(db).duplicate()
	defs.sort_custom(func(a, b):
		var ta: int = int(a.data.get("tier", 0))
		var tb: int = int(b.data.get("tier", 0))
		if ta == tb:
			return str(a.id) < str(b.id)
		return ta < tb)
	for r in defs:
		var preqs: Array = []
		for p in r.prereqs():
			var pd = db.get_def(StringName(str(p)))
			preqs.append(String(pd.label()) if pd != null and pd.has_method("label") else str(p))
		rows.append({
			"id": r.id,
			"label": String(r.data.get("label", str(r.id))),
			"tier": int(r.data.get("tier", 0)),
			"cost": float(r.cost()),
			"status": research_status(r, unlocked),
			"prereqs": preqs,
		})
	return rows

# The labels of research you could START right now (prereqs met, not yet unlocked) — the "next" hint.
static func _next_research(db, unlocked: Dictionary) -> Array:
	var out: Array = []
	for r in Catalog.research_projects(db):
		if research_status(r, unlocked) == &"available":
			out.append(String(r.data.get("label", str(r.id))))
	out.sort()
	return out
