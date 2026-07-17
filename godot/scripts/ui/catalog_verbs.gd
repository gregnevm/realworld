# RealWorld — ui/catalog_verbs.gd : the content-tree interaction grammar (spec 0005 §2.10, R9).
#
# The sibling of input_verbs.gd for the catalogue write-side: it binds the research / build / craft
# INTENTS a panel emits to the commands that execute them. Like input_verbs.gd this is the ONLY place
# those command names appear — panels emit an intent (a verb StringName + args), never call the sim (R9).
#
# ONE intent, TWO honest targets (spec 0008 phase 3 — «одна правда на дію»):
#   • live catalogue world (session.sim.use_catalog ON) — the verbs act on the REAL game:
#     cat_build arms the placement ghost (via the view-owned `arm_build` callable the entry scene
#     supplies — the ghost is VIEW state, same tier that binds select_build), cat_craft runs the live
#     sim's catalogue craft, cat_research feeds the LIVE research queue (kernel/progression via session);
#   • otherwise — the catalog_sim sandbox, exactly as before (browsers are badged «демо»).
extends RefCounted

# sandbox: a catalog_sim.gd instance; arm_build: Callable(String) that toggles the build ghost.
static func install(ic, sandbox, arm_build: Callable = Callable()) -> void:
	ic.bind(&"cat_research", func(s, a) -> void:
		var id := String(a.get("id", ""))
		if _live(s):
			s.enqueue_research(id)
		else:
			sandbox.start_research(StringName(id)))
	ic.bind(&"cat_build", func(s, a) -> void:
		var id := String(a.get("id", ""))
		if _live(s):
			if arm_build.is_valid():
				arm_build.call(id)
		else:
			sandbox.build(StringName(id)))
	ic.bind(&"cat_craft", func(s, a) -> void:
		var id := String(a.get("id", ""))
		if _live(s):
			var r: Dictionary = s.sim.catalog_craft(id)
			if not bool(r.get("ok", false)):
				s.sim._flash(String(r.get("msg", "")))
		else:
			sandbox.queue_craft(
				StringName(id),
				StringName(str(a.get("mode", "count"))),
				int(a.get("target", 1))))


# The dispatch target: the live catalogue world iff the session's sim speaks catalogue stock.
# (`== true`, не bool(): Object.get на fake без властивості повертає null, а bool(null) — помилка.)
static func _live(s) -> bool:
	if s == null:
		return false
	var sim: Variant = s.get("sim")
	return sim != null and sim.get("use_catalog") == true
