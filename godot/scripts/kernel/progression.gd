# RealWorld — kernel/progression.gd : the research→unlock PIPELINE over the deep content tree.
#
# RimWorld analogue: ResearchManager driving the whole DefDatabase gate — but made into an explicit,
# queueable PIPELINE. The kernel already ships the primitive (production.gd's ResearchState: one active
# project, points burned in, unlocked-set out). This module is the layer above it that the UI and host
# actually drive: a QUEUE of upcoming projects, "what can I research now" (available), "what does the
# current tech state unlock" (build/craft gates over catalog.gd), a tech-level readout, and save/load.
#
# It composes on the shipped grammar and edits NOTHING: it reuses Production.ResearchState verbatim and
# reads the tree through catalog.gd's typed accessors. Adding it does not touch sim.gd / main.gd / data.gd.
#
# --- The pipeline, as data -------------------------------------------------------------------------
#   add_points(p)        feed p research-points; drains into the active project, and when a project
#                        completes the LEFTOVER points roll straight into the next queued (or, in auto
#                        mode, the next available) project — a real pipeline, not a stop-start. Returns
#                        the Array of ids unlocked by THIS call so a host can fire "research done" toasts.
#   enqueue(id)          append a project to the pipeline. Refused unless its prereqs are already
#                        unlocked, active, or ALSO queued earlier — so by the time it reaches the front
#                        its prereqs are guaranteed met (the queue is always a valid topo order).
#   available()          projects whose prereqs are met right now and that are not unlocked/active/queued.
#   auto_next()          the deterministic "research this next" pick (lowest tier, then cost, then id).
#   unlocked_buildings() / _recipes() / _items()   the catalog slice the current tech state opens.
#
# --- Determinism -----------------------------------------------------------------------------------
# Pure set/graph closure over plain data + ResearchState's float accumulation. No rng, no time, no DOM.
# Mirrored one-for-one by tests/progression.test.js so the Node validator and this loader can never
# silently disagree about the same catalog.json.
extends RefCounted

const Catalog = preload("res://scripts/kernel/catalog.gd")
const Production = preload("res://scripts/kernel/production.gd")
const Defs = preload("res://scripts/kernel/defs.gd")

var db: Defs.DefDatabase          # Defs.DefDatabase built from the catalog (id + type lookups)
var cat: Dictionary               # raw catalog dict (tier/label read from here — never JSON-int-bitten)
var research: Production.ResearchState   # the single-active-project primitive
var queue: Array = []             # [StringName] projects waiting after the active one (valid topo order)
var _research_rec: Dictionary = {}   # StringName -> raw research record (for tier/label without a db round-trip)

# p_cat: an already-parsed catalog dict, or {} to load the on-disk catalog. p_db: reuse a prebuilt
# DefDatabase (the host builds one once) or null to build our own.
func _init(p_cat: Dictionary = {}, p_db = null) -> void:
	cat = p_cat if not p_cat.is_empty() else Catalog.load_json()
	db = p_db if p_db != null else Catalog.build_db(cat)
	research = Production.ResearchState.new(db)
	for r in cat.get("research", []):
		_research_rec[StringName(str(r.get("id", "")))] = r

# ============================================================================================
# STATE READOUT
# ============================================================================================

func is_unlocked(id) -> bool:
	return research.is_unlocked(StringName(id))

func active_id() -> StringName:
	return research.active

func active_progress() -> float:
	return float(research.progress)

func active_cost() -> float:
	if research.active == &"":
		return 0.0
	var d: Variant = db.get_def(research.active)
	return d.cost() if d != null else 0.0

# Completion fraction of the active project in [0,1] (0 when nothing is active).
func active_pct() -> float:
	var c := active_cost()
	if c <= 0.0:
		return 0.0
	return clampf(active_progress() / c, 0.0, 1.0)

func unlocked_count() -> int:
	return research.unlocked.size()

func total_projects() -> int:
	return int(cat.get("research", []).size())

# The deepest tier among unlocked projects — a single "how advanced am I" HUD number (0 = neolithic start).
func tech_level() -> int:
	var lvl := 0
	for id in research.unlocked:
		lvl = maxi(lvl, tier_of(id))
	return lvl

func tier_of(id) -> int:
	var rec: Dictionary = _research_rec.get(StringName(id), {})
	return int(rec.get("tier", 0))

func label_of(id) -> String:
	if str(id) == "":
		return ""
	var rec: Dictionary = _research_rec.get(StringName(id), {})
	return str(rec.get("label", str(id)))

# ============================================================================================
# AVAILABILITY & QUEUE (the pipeline mechanics)
# ============================================================================================

# Projects researchable RIGHT NOW: prereqs met, and not already unlocked / active / queued.
func available() -> Array:
	var out: Array = []
	for r in Catalog.research_projects(db):
		var id: StringName = r.id
		if research.is_unlocked(id) or id == research.active or queue.has(id):
			continue
		if research.prereqs_met(id):
			out.append(r)
	return out

func is_available(id) -> bool:
	var sid := StringName(id)
	if research.is_unlocked(sid) or sid == research.active or queue.has(sid):
		return false
	return db.get_def(sid) != null and research.prereqs_met(sid)

# The deterministic "what to research next" pick used by auto mode + suggested-next UI. Cheapest first
# by (tier, cost, id) so the walk is reproducible and reads bottom-up through the tree.
func auto_next() -> StringName:
	var avail := available()
	if avail.is_empty():
		return &""
	avail.sort_custom(_cmp_research)
	return avail[0].id

func _cmp_research(a, b) -> bool:
	var ta: int = tier_of(a.id)
	var tb: int = tier_of(b.id)
	if ta != tb:
		return ta < tb
	var ca: float = a.cost()
	var cb: float = b.cost()
	if not is_equal_approx(ca, cb):
		return ca < cb
	return str(a.id) < str(b.id)

# Append a project to the pipeline. Kept a valid topo order: a project may be queued only when every
# prereq is already unlocked / active / queued-before-it, guaranteeing it is startable when it fronts.
func enqueue(id) -> bool:
	var sid := StringName(id)
	if research.is_unlocked(sid) or db.get_def(sid) == null:
		return false
	if sid == research.active or queue.has(sid):
		return false
	var d: Variant = db.get_def(sid)
	for p in d.prereqs():
		var pid := StringName(str(p))
		if not (research.is_unlocked(pid) or queue.has(pid) or pid == research.active):
			return false
	queue.append(sid)
	_ensure_active(false)          # start immediately if the pipeline was idle
	return true

func dequeue(id) -> void:
	queue.erase(StringName(id))

# Start `id` as the active project right now (bypasses the queue). Refused if something is already active.
func start(id) -> bool:
	if research.active != &"":
		return false
	return research.try_start(StringName(id))

# ============================================================================================
# FEEDING POINTS (the pump)
# ============================================================================================

# Burn `points` research-points into the pipeline. Completes the active project when it reaches cost and
# rolls the LEFTOVER into the next queued (or, when `auto`, the next available) project, so a big daily
# grant can finish several cheap projects in one call. Returns the ids unlocked by this call (in order).
func add_points(points: float, auto: bool = false) -> Array:
	var newly: Array = []
	var remaining: float = maxf(0.0, points)
	_ensure_active(auto)
	while remaining > 1e-9 and research.active != &"":
		var cur: StringName = research.active
		var d: Variant = db.get_def(cur)
		if d == null:
			break
		var need: float = maxf(0.0, d.cost() - research.progress)
		if remaining + 1e-9 >= need:
			research.advance(need)     # progress -> cost: unlocks cur, clears active
			newly.append(cur)
			remaining -= need
			_ensure_active(auto)
		else:
			research.advance(remaining)
			remaining = 0.0
	return newly

# Make sure a project is active if one can be: first from the queue (front is always startable for a
# valid queue), else — only in auto mode — the deterministic next-available pick.
func _ensure_active(auto: bool) -> void:
	while research.active == &"" and not queue.is_empty():
		var id: StringName = queue[0]
		if research.is_unlocked(id):
			queue.pop_front()
			continue
		if research.can_start(id):
			queue.pop_front()
			research.try_start(id)
		else:
			break                      # front not yet startable (malformed queue) — stop, don't drop it
	if research.active == &"" and auto:
		var nxt := auto_next()
		if nxt != &"":
			research.try_start(nxt)

# ============================================================================================
# TECH-PATH PLANNER (the "what do I need to unlock this" pipeline, as data)
# ============================================================================================

# The ordered research prerequisite chain ending at `id` — a valid topological order (every project's
# prereqs precede it), deduped. This is the tech PATH the UI shows for a locked target. [] if id unknown.
func research_path(id) -> Array:
	var target := StringName(id)
	var d: Variant = db.get_def(target)
	if d == null or not (d is Production.ResearchDef):
		return []
	var out: Array = []
	var seen: Dictionary = {}
	_visit_path(target, out, seen, {})
	return out

func _visit_path(id: StringName, out: Array, seen: Dictionary, stack: Dictionary) -> void:
	if seen.has(id) or stack.has(id):        # dedupe + cycle guard (the tree is a DAG, but stay total)
		return
	stack[id] = true
	var d: Variant = db.get_def(id)
	if d != null:
		for p in d.prereqs():
			_visit_path(StringName(str(p)), out, seen, stack)
	stack.erase(id)
	seen[id] = true
	out.append(id)

# The research still to do to open a gate ("" gate -> [] : already open). The path minus what's unlocked —
# so a locked build/craft row can read "N дослідж." and expand to the exact remaining steps, in order.
func steps_to_unlock(gate) -> Array:
	var g := str(gate)
	if g == "":
		return []
	var out: Array = []
	for id in research_path(StringName(g)):
		if not research.is_unlocked(id):
			out.append(id)
	return out

# Total research-points still to spend to reach a target project (Σ cost of the not-yet-unlocked steps,
# counting the target itself). Combined with a points/day rate this yields a live ETA. 0 once unlocked.
func remaining_cost(target) -> float:
	var total := 0.0
	for id in steps_to_unlock(target):
		var d: Variant = db.get_def(id)
		if d != null:
			total += d.cost()
	return total

# ============================================================================================
# UNLOCK GATES OVER CATALOG CONTENT (what the current tech state opens)
# ============================================================================================

# A gate ("" / missing = ungated) is open when its project is unlocked. The single predicate the
# build/craft UI filters on — mirrors catalog.gd._gate_ok but reads the LIVE unlocked set.
func gate_ok(ref) -> bool:
	var s := str(ref)
	return s == "" or research.is_unlocked(StringName(s))

func unlocked_buildings() -> Array:
	var out: Array = []
	for b in Catalog.buildings(db):
		if gate_ok(b.research()):
			out.append(b)
	return out

func locked_buildings() -> Array:
	var out: Array = []
	for b in Catalog.buildings(db):
		if not gate_ok(b.research()):
			out.append(b)
	return out

func unlocked_recipes() -> Array:
	var out: Array = []
	for r in Catalog.recipes(db):
		if gate_ok(r.requires_research()):
			out.append(r)
	return out

func unlocked_items() -> Array:
	var out: Array = []
	for it in Catalog.items(db):
		if gate_ok(it.research()):
			out.append(it)
	return out

# What completing a given research project OPENS: the buildings/recipes/items gated exactly on it. The
# reverse of the gate — powers the "researching X will unlock …" preview. Ungated content is in no set.
func unlocks_of(research_id) -> Dictionary:
	var rid := StringName(research_id)
	var out: Dictionary = {"buildings": [], "recipes": [], "items": []}
	if rid == &"":
		return out
	for b in Catalog.buildings(db):
		if b.research() == rid:
			out.buildings.append(b.id)
	for r in Catalog.recipes(db):
		if r.requires_research() == rid:
			out.recipes.append(r.id)
	for it in Catalog.items(db):
		if it.research() == rid:
			out.items.append(it.id)
	return out

# Per-category unlocked/total of the catalogue under the current tech state — the tech-dashboard readout.
func catalog_counts() -> Dictionary:
	return {
		"buildings": {"unlocked": unlocked_buildings().size(), "total": Catalog.buildings(db).size()},
		"recipes": {"unlocked": unlocked_recipes().size(), "total": Catalog.recipes(db).size()},
		"items": {"unlocked": unlocked_items().size(), "total": Catalog.items(db).size()},
	}

# The research id gating a building/recipe/item ("" when ungated) — the label the UI shows on a locked row.
func building_gate(id) -> StringName:
	var b: Variant = db.get_def(StringName(id))
	return b.research() if b != null and b is Catalog.BuildingDef else &""

func recipe_gate(id) -> StringName:
	var r: Variant = db.get_def(StringName(id))
	return r.requires_research() if r != null and r is Production.RecipeDef else &""

func item_gate(id) -> StringName:
	var it: Variant = db.get_def(StringName(id))
	return it.research() if it != null and it is Catalog.ItemDef else &""

# ============================================================================================
# VIEWMODEL SLICE + SERIALIZATION
# ============================================================================================

# A pure value-data summary for the HUD ViewModel (no live refs — spec 0005 R8).
func summary() -> Dictionary:
	return {
		"active": research.active,
		"active_label": label_of(research.active),
		"active_pct": active_pct(),
		"active_cost": active_cost(),
		"active_progress": active_progress(),
		"queue": queue.duplicate(),
		"unlocked": unlocked_count(),
		"total": total_projects(),
		"level": tech_level(),
	}

# Persist the whole pipeline (unlocked set + active project + progress + queue) as plain JSON-safe data.
func to_dict() -> Dictionary:
	var un: Array = []
	for k in research.unlocked:
		un.append(str(k))
	var q: Array = []
	for s in queue:
		q.append(str(s))
	return {"unlocked": un, "active": str(research.active), "progress": active_progress(), "queue": q}

func from_dict(d: Dictionary) -> void:
	research.unlocked = {}
	for k in d.get("unlocked", []):
		research.unlocked[StringName(str(k))] = true
	research.active = StringName(str(d.get("active", "")))
	research.progress = float(d.get("progress", 0.0))
	queue = []
	for s in d.get("queue", []):
		queue.append(StringName(str(s)))
