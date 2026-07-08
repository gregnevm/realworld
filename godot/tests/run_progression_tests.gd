# RealWorld — headless tests for the research→unlock PIPELINE (kernel/progression.gd).
# Run: Godot_console.exe --headless --path godot -s res://tests/run_progression_tests.gd
#
# The Godot-side parity of tests/progression.test.js. Both drive the SAME godot/content/catalog.json
# through the SAME algorithm; this suite proves the GDScript kernel matches the Node validator so the
# forward engine and CI can never disagree about how the tech pipeline walks the tree. Proves:
#   1. the pipeline builds over the whole research tree and cold-starts empty;
#   2. cold-start availability is exactly the prereq-free projects;
#   3. a full auto-walk unlocks the ENTIRE tree in prereq-respecting order, spending exactly Σcost;
#   4. leftover points roll from a finished project into the next (pipeline continuity);
#   5. enqueue only accepts a valid topological order;
#   6. the unlocked catalogue grows monotonically and ends at full reachability;
#   7. illegal starts are refused;
#   8. the whole pipeline round-trips through to_dict()/from_dict().
extends SceneTree

const Catalog = preload("res://scripts/kernel/catalog.gd")
const Progression = preload("res://scripts/kernel/progression.gd")

var passed := 0
var failed := 0

func _init() -> void:
	print("== RealWorld progression-pipeline tests ==")
	_t_build()
	_t_cold_availability()
	_t_full_walk()
	_t_pipeline_continuity()
	_t_enqueue_topo()
	_t_monotonic_unlock()
	_t_illegal_starts()
	_t_serialization()
	print("\n== RESULT: %d passed, %d failed ==" % [passed, failed])
	quit(1 if failed > 0 else 0)

func ok(cond: bool, name: String) -> void:
	if cond:
		passed += 1
		print("  [pass] ", name)
	else:
		failed += 1
		printerr("  [FAIL] ", name)
		print("  [FAIL] ", name)

func _new() -> Progression:
	return Progression.new(Catalog.load_json())

# --- 1. build ------------------------------------------------------------------------------------
func _t_build() -> void:
	var p := _new()
	ok(p.total_projects() >= 40, "loads the full research tree (%d)" % p.total_projects())
	ok(p.unlocked_count() == 0, "cold start: nothing unlocked")
	ok(p.tech_level() == 0, "cold start: tech level 0")

# --- 2. cold availability == prereq-free projects ------------------------------------------------
func _t_cold_availability() -> void:
	var cat: Dictionary = Catalog.load_json()
	var p := Progression.new(cat)
	var avail: Dictionary = {}
	for r in p.available():
		avail[r.id] = true
	var rootless: Dictionary = {}
	for r in cat.get("research", []):
		if r.get("prereqs", []).is_empty():
			rootless[StringName(str(r.get("id", "")))] = true
	ok(avail.size() == rootless.size(), "available count == prereq-free count (%d)" % rootless.size())
	var same := true
	for id in rootless:
		if not avail.has(id):
			same = false
	ok(same and rootless.size() > 0, "cold-start availability is exactly the entry-point projects")

# --- 3. full auto-walk unlocks everything in prereq order ----------------------------------------
func _t_full_walk() -> void:
	var cat: Dictionary = Catalog.load_json()
	var p := Progression.new(cat)
	var count := 0
	var spent := 0.0
	var last_level := 0
	var order_ok := true
	var complete_ok := true
	var guard := 0
	while p.unlocked_count() < p.total_projects() and guard < 1000:
		guard += 1
		var nxt: StringName = p.auto_next()
		if nxt == &"":
			order_ok = false
			break
		var d = p.db.get_def(nxt)
		for pr in d.prereqs():
			if not p.is_unlocked(StringName(str(pr))):
				order_ok = false
		p.start(nxt)
		spent += p.active_cost()
		var done: Array = p.add_points(p.active_cost())
		if done.size() != 1 or done[0] != nxt:
			complete_ok = false
		count += 1
		if p.tech_level() < last_level:
			order_ok = false
		last_level = p.tech_level()
	ok(order_ok, "every project picked after its prereqs; tech level never decreases")
	ok(complete_ok, "each project completes on exactly its cost")
	ok(p.unlocked_count() == p.total_projects(), "the entire tree unlocks (%d)" % p.unlocked_count())
	ok(count == p.total_projects(), "each project unlocked exactly once")
	var total_cost := 0.0
	for r in cat.get("research", []):
		total_cost += float(r.get("cost", 0.0))
	ok(absf(spent - total_cost) < 1e-4, "points spent == Σ project costs (%.1f)" % total_cost)
	var max_tier := 0
	for r in cat.get("research", []):
		max_tier = maxi(max_tier, int(r.get("tier", 0)))
	ok(p.tech_level() == max_tier, "finishing the tree reaches the deepest tier (%d)" % max_tier)

# --- 4. pipeline continuity (leftover points roll into the next project) -------------------------
func _t_pipeline_continuity() -> void:
	var cat: Dictionary = Catalog.load_json()
	var p := Progression.new(cat)
	var roots: Array = []
	for r in cat.get("research", []):
		if r.get("prereqs", []).is_empty():
			roots.append(r)
		if roots.size() == 2:
			break
	ok(p.enqueue(StringName(str(roots[0].get("id")))), "enqueue first root")
	ok(p.enqueue(StringName(str(roots[1].get("id")))), "enqueue second root")
	var both: float = float(roots[0].get("cost")) + float(roots[1].get("cost"))
	var done: Array = p.add_points(both)
	ok(done.size() == 2 and str(done[0]) == str(roots[0].get("id")) and str(done[1]) == str(roots[1].get("id")),
		"both queued projects complete in one pump")
	ok(p.active_id() == &"" and absf(p.active_progress()) < 1e-9, "pipeline idles cleanly once the queue drains")

# --- 5. enqueue accepts only a valid topological order -------------------------------------------
func _t_enqueue_topo() -> void:
	var cat: Dictionary = Catalog.load_json()
	var p := Progression.new(cat)
	var dep: Dictionary = {}
	for r in cat.get("research", []):
		if not r.get("prereqs", []).is_empty():
			dep = r
			break
	ok(not dep.is_empty(), "found a project with prereqs")
	ok(p.enqueue(StringName(str(dep.get("id")))) == false, "cannot enqueue a project whose prereqs are not yet in the pipeline")

# --- 6. monotonic unlock, ends at full reachability ----------------------------------------------
func _t_monotonic_unlock() -> void:
	var cat: Dictionary = Catalog.load_json()
	var p := Progression.new(cat)
	var ungated := 0
	for b in cat.get("buildings", []):
		if str(b.get("research", "")) == "":
			ungated += 1
	ok(p.unlocked_buildings().size() == ungated, "cold start opens exactly the ungated buildings (%d)" % ungated)
	var last_b := p.unlocked_buildings().size()
	var mono := true
	var guard := 0
	while p.unlocked_count() < p.total_projects() and guard < 1000:
		guard += 1
		p.start(p.auto_next())
		p.add_points(p.active_cost())
		var b := p.unlocked_buildings().size()
		if b < last_b:
			mono = false
		last_b = b
	ok(mono, "unlocked building set never shrinks as tech advances")
	ok(p.unlocked_buildings().size() == cat.get("buildings", []).size(), "all buildings open once fully researched")
	ok(p.unlocked_recipes().size() == cat.get("recipes", []).size(), "all recipes open once fully researched")
	ok(p.unlocked_items().size() == cat.get("items", []).size(), "all items open once fully researched")

# --- 7. illegal starts refused -------------------------------------------------------------------
func _t_illegal_starts() -> void:
	var cat: Dictionary = Catalog.load_json()
	var p := Progression.new(cat)
	var deep: Dictionary = {}
	for r in cat.get("research", []):
		if int(r.get("tier", 0)) >= 3:
			deep = r
			break
	ok(not deep.is_empty() and p.start(StringName(str(deep.get("id")))) == false, "cannot start a deep project with unmet prereqs")
	var root: Dictionary = {}
	for r in cat.get("research", []):
		if r.get("prereqs", []).is_empty():
			root = r
			break
	ok(p.start(StringName(str(root.get("id")))), "can start a root project")
	var other: StringName = &""
	for r in cat.get("research", []):
		if r.get("prereqs", []).is_empty() and str(r.get("id")) != str(root.get("id")):
			other = StringName(str(r.get("id")))
			break
	ok(p.start(other) == false, "cannot start a second project while one is active")

# --- 8. serialization round-trip -----------------------------------------------------------------
func _t_serialization() -> void:
	var cat: Dictionary = Catalog.load_json()
	var p := Progression.new(cat)
	var guard := 0
	while p.unlocked_count() < 5 and guard < 50:
		guard += 1
		p.start(p.auto_next())
		p.add_points(p.active_cost())
	p.start(p.auto_next())
	p.add_points(p.active_cost() * 0.5)
	var blob: Dictionary = p.to_dict()
	var q := Progression.new(cat)
	q.from_dict(blob)
	ok(q.unlocked_count() == p.unlocked_count(), "unlocked set restored")
	ok(str(q.active_id()) == str(p.active_id()), "active project restored")
	ok(absf(q.active_progress() - p.active_progress()) < 1e-6, "progress restored")
	ok(q.summary().hash() == p.summary().hash(), "the viewmodel summary is identical after a round-trip")
