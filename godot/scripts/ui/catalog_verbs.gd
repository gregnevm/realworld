# RealWorld — ui/catalog_verbs.gd : the content-tree interaction grammar (spec 0005 §2.10, R9).
#
# The sibling of input_verbs.gd for the catalogue write-side: it binds the research / build / craft
# INTENTS a panel emits to the commands that execute them. Like input_verbs.gd this is the ONLY place
# those command names appear — panels emit an intent (a verb StringName + args), never call the sim
# (R9). Install onto any InputController; the catalog_sim sandbox is captured, the SESSION arrives
# per-dispatch, so each intent routes by mode (spec 0008 phase 3):
#   • session.sim.use_catalog ON  -> the LIVE world: cat_build arms the ordinary select_build ghost
#     (the map click then lands in sim.try_build, which speaks catalogue ids through the def seam);
#     cat_craft runs sim.craft_catalog; cat_research feeds the session research pipeline (0007).
#   • flag OFF -> the forward-engine catalog_sim sandbox, exactly as before.
# Refusal texts live HERE (the router is the R10 seam), formatted from the sim's value-data reasons.
extends RefCounted

static func _live(s) -> bool:
	if s == null or not ("sim" in s) or s.sim == null:
		return false
	return bool(s.sim.get("use_catalog") == true)

static func _flash_refusal(s, r: Dictionary) -> void:
	match StringName(r.get("reason", &"")):
		&"no_station":
			s.sim._flash("Потрібна станція: %s." % str(r.get("station_label", "?")))
		&"locked":
			s.sim._flash("🔒 Потребує дослідження: %s." % str(r.get("research_label", "?")))
		&"cost":
			s.sim._flash("Бракує: " + str(r.get("missing", "")))
		_:
			s.sim._flash("Невідомий рецепт.")

# sandbox: a catalog_sim.gd instance. After install, ic.dispatch(&"cat_*", args, session) routes live/sandbox.
static func install(ic, sandbox) -> void:
	# WEAKREF, not `ic`: a bound closure capturing the controller it is bound to would be a
	# Callable -> controller -> Callable RefCounted cycle — never collected (ObjectDB leak).
	var wr: WeakRef = weakref(ic)
	ic.bind(&"cat_research", func(s, a):
		if _live(s):
			s.start_research(String(a.get("id", "")))
		else:
			sandbox.start_research(StringName(str(a.get("id", "")))))
	ic.bind(&"cat_build", func(s, a):
		if _live(s):
			# arm the ordinary build ghost: the SAME select_build/click grammar the BuildBar uses —
			# the map click then lands in sim.try_build, which speaks catalogue ids via the def seam
			var router: Variant = wr.get_ref()
			if router != null:
				router.dispatch(&"select_build", {"kind": str(a.get("id", ""))}, s)
		else:
			sandbox.build(StringName(str(a.get("id", "")))))
	ic.bind(&"cat_craft", func(s, a):
		if _live(s):
			var r: Dictionary = s.sim.craft_catalog(String(a.get("id", "")))
			if bool(r.get("ok", false)):
				s.sim._log("⚒ %s: +%d %s" % [str(r.get("label", "")), int(r.get("added", 0)), str(r.get("out_icon", ""))], "good")
			else:
				_flash_refusal(s, r)
		else:
			sandbox.queue_craft(
				StringName(str(a.get("id", ""))),
				StringName(str(a.get("mode", "count"))),
				int(a.get("target", 1))))
