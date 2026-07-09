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

# Lazily-built, process-cached raw catalogue JSON — the BOM planner in catalog.gd walks this dict (not the
# DefDatabase). Same on-disk source as default_db(), so ids align; cached once like the db (cheap hot path).
static var _cat = null
static func default_cat() -> Dictionary:
	if _cat == null:
		_cat = Catalog.load_json()
	return _cat

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
		"build_actions": _build_actions(db, unlocked, stock),
		"craft_actions": _craft_actions(db, unlocked, stock, state.get("stations", {})),
		"research_actions": _research_actions(db, unlocked),
	}

# --- actionable slices: the rows an interactive browser turns into clickable, intent-emitting slots.
# Each row is value-data {id, label, sub, enabled, tip}. Affordable rows come first (enabled + clickable);
# unlocked-but-unaffordable "near-miss" rows follow, dimmed, their tip naming the shortfall — the spec 0008
# phase-1 "to make X you need …" guidance, powered by the BOM planner (production_chain / raw_requirements /
# missing_for) in catalog.gd. Capped so a fixed-size (R2) browser binds one page; tips are computed only for
# the rows that survive the cap, so the per-frame snapshot never walks the graph for hidden rows.
const ACTION_CAP := 12

# Affordable defs first, then near-miss, up to the cap — so slot 0 is always the actionable one.
static func _cap_merge(ready: Array, near: Array) -> Array:
	var out: Array = []
	for x in ready:
		if out.size() >= ACTION_CAP: break
		out.append(x)
	for x in near:
		if out.size() >= ACTION_CAP: break
		out.append(x)
	return out

# The shortfall line ("🪨5") for a cost the player cannot yet afford, via the planner's missing_for.
static func _short_str(db, cost: Dictionary, stock: Dictionary) -> String:
	return cost_str(db, Catalog.missing_for(cost, stock))

# The full raw budget of a cost rolled down to map-obtained resources ("🪵18 🪨4") — raw_requirements.
static func raw_bill_str(db, cost: Dictionary) -> String:
	return cost_str(db, Catalog.raw_requirements(default_cat(), cost))

# Buildings whose research is unlocked: affordable ones first (clickable), then unaffordable (dimmed).
static func _build_actions(db, unlocked: Dictionary, stock: Dictionary) -> Array:
	var ready: Array = []
	var near: Array = []
	for b in Catalog.buildings(db):
		if not _gate_ok(b.research(), unlocked):
			continue
		(ready if _afford(b.cost(), stock) else near).append(b)
	var out: Array = []
	for b in _cap_merge(ready, near):
		var afford := _afford(b.cost(), stock)
		out.append({
			"id": b.id, "label": String(b.label()), "sub": cost_str(db, b.cost()), "enabled": afford,
			"tip": ("Уся сировина: %s" % raw_bill_str(db, b.cost())) if afford else ("Потрібно ще: %s" % _short_str(db, b.cost(), stock)),
		})
	return out

# Recipes whose station is PLACED and research unlocked: craftable-now first, then input-short (dimmed).
static func _craft_actions(db, unlocked: Dictionary, stock: Dictionary, stations: Dictionary) -> Array:
	var ready: Array = []
	var near: Array = []
	for rc in Catalog.recipes(db):
		if not stations.has(StringName(str(rc.data.get("station", "")))):
			continue
		if not _gate_ok(rc.requires_research(), unlocked):
			continue
		(ready if _afford(rc.inputs(), stock) else near).append(rc)
	var out: Array = []
	for rc in _cap_merge(ready, near):
		var oid := StringName(str(rc.output().get("id", "")))
		var od = db.get_def(oid)
		var olabel: String = String(od.label()) if od != null and od.has_method("label") else str(oid)
		var afford := _afford(rc.inputs(), stock)
		var tip: String
		if afford:
			var chain: Array = Catalog.production_chain(default_cat(), oid)
			tip = "%s ← %s · шлях %d кр." % [olabel, cost_str(db, rc.inputs()), chain.size()]
		else:
			tip = "Потрібно ще: %s" % _short_str(db, rc.inputs(), stock)
		out.append({
			"id": rc.id, "label": String(rc.data.get("label", str(rc.id))), "sub": "→ " + olabel,
			"enabled": afford, "tip": tip,
		})
	return out

# Research you can start right now (prereqs met, not yet unlocked); tip advertises what it unlocks.
static func _research_actions(db, unlocked: Dictionary) -> Array:
	var out: Array = []
	for r in Catalog.research_projects(db):
		if out.size() >= ACTION_CAP:
			break
		if research_status(r, unlocked) == &"available":
			out.append({
				"id": r.id, "label": String(r.data.get("label", str(r.id))),
				"sub": "%d дн." % int(r.cost()), "enabled": true, "tip": _unlocks_tip(r.id),
			})
	return out

# "Відкриє: 🏛3 ⚒2 🔧1" — how many buildings/recipes/items this research gates (scanned from the tree).
static func _unlocks_tip(research_id) -> String:
	var rid := StringName(str(research_id))
	var cat := default_cat()
	var nb := 0
	var nr := 0
	var ni := 0
	for b in cat.get("buildings", []):
		if StringName(str(b.get("research", ""))) == rid: nb += 1
	for rc in cat.get("recipes", []):
		if StringName(str(rc.get("research", ""))) == rid: nr += 1
	for it in cat.get("items", []):
		if StringName(str(it.get("research", ""))) == rid: ni += 1
	return "Відкриє: 🏛%d ⚒%d 🔧%d" % [nb, nr, ni]

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

# Research you could START right now (prereqs met, not yet unlocked) as {id, label} — the "next" hint.
# Carries the id so a panel can emit a &"cat_research" intent for it, not just show the label.
static func _next_research(db, unlocked: Dictionary) -> Array:
	var out: Array = []
	for r in Catalog.research_projects(db):
		if research_status(r, unlocked) == &"available":
			out.append({"id": r.id, "label": String(r.data.get("label", str(r.id)))})
	out.sort_custom(func(a, b): return String(a["label"]) < String(b["label"]))
	return out
