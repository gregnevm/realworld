# RealWorld — ui/catalog_verbs.gd : the content-tree interaction grammar (spec 0005 §2.10, R9).
#
# The sibling of input_verbs.gd for the catalogue write-side: it binds the research / build / craft
# INTENTS a panel emits to the catalog_sim commands that execute them. Like input_verbs.gd this is the
# ONLY place those command names appear — panels emit an intent (a verb StringName + args), never call
# the sim (R9). Install onto any InputController; the catalog_sim is captured so `dispatch` needs no
# per-call session plumbing.
extends RefCounted

# sim: a catalog_sim.gd instance. After install, ic.dispatch(&"cat_*", args, _) drives it.
static func install(ic, sim) -> void:
	ic.bind(&"cat_research", func(_s, a): sim.start_research(StringName(str(a.get("id", "")))))
	ic.bind(&"cat_build", func(_s, a): sim.build(StringName(str(a.get("id", "")))))
	ic.bind(&"cat_craft", func(_s, a): sim.queue_craft(
		StringName(str(a.get("id", ""))),
		StringName(str(a.get("mode", "count"))),
		int(a.get("target", 1))))
