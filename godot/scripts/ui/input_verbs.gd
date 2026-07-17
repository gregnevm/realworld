# RealWorld — ui/input_verbs.gd : the design-system §5 interaction grammar as DATA (spec 0005 §2.10).
#
# The verb table, installed onto an InputController. A verb is the only thing allowed to call a sim
# mutator (R9). This is the data replacement for main.gd's _unhandled_input/_handle_click switch.
extends RefCounted

# Install the standard grammar. `session` has `.sim` and `.travel_to(lat,lon,name)`.
# Mutators that return {ok, msg} get their failure flashed (main.gd parity): the router is the ONE
# place allowed to route a refusal into the sim's flash channel the FeedbackBus drains (R9+R10) —
# without it the GearPanel/LogisticsPanel buttons fail as silent no-ops.
static func install(ic) -> void:
	ic.bind(&"order_move",   func(s, a): s.sim.order_move(int(a.x), int(a.y)))
	ic.bind(&"order_gather", func(s, a): s.sim.order_gather(int(a.x), int(a.y)))
	ic.bind(&"order_attack", func(s, a): s.sim.order_attack(a.target))
	ic.bind(&"build",        func(s, a): s.sim.try_build(String(a.kind), int(a.x), int(a.y)))
	ic.bind(&"cancel_action", func(s, _a): s.sim.player.action = null)   # Esc: скасувати наказ пішки
	ic.bind(&"deconstruct",  func(s, a):
		var r: Dictionary = s.sim.demolish(int(a.x), int(a.y))
		if not r.ok: s.sim._flash(String(r.get("msg", ""))))
	ic.bind(&"craft",        func(s, a):
		var r: Dictionary = s.sim.craft_item(String(a.id))
		if not r.ok: s.sim._flash(String(r.get("msg", ""))))
	ic.bind(&"equip",        func(s, a): s.sim.equip(String(a.id)))
	ic.bind(&"send_convoy",  func(s, a):
		var r: Dictionary = s.sim.dispatch_convoy(int(a.hub), String(a.res), int(a.amt))
		if not r.ok: s.sim._flash(String(r.get("msg", ""))))
	# research pipeline — the ResearchPanel emits these; the session drives kernel/progression.gd (R9)
	ic.bind(&"enqueue_research", func(s, a): s.enqueue_research(String(a.id)))
	ic.bind(&"start_research",   func(s, a): s.start_research(String(a.id)))
	ic.bind(&"clear_research",   func(s, a): s.clear_research_queue())
	ic.bind(&"launch_capsule", func(s, a):
		var r: Dictionary = s.sim.try_launch_capsule(float(a.lat), float(a.lon), String(a.name))
		if r.ok: s.travel_to(float(a.lat), float(a.lon), String(a.name))
		elif r.has("msg"): s.sim._flash(String(r.msg)))
	# ONE implementation, TWO names: "take_invite" is the panel-facing alias (the intent name must not
	# equal the sim mutator's — R9 tripwire greps panels). A shared Callable, so the handlers can't drift.
	var accept := func(s, a):
		var r: Dictionary = s.sim.accept_invite(String(a.id))
		if r.ok: s.travel_to(float(r.lat), float(r.lon), String(r.name))
		elif r.has("msg"): s.sim._flash(String(r.msg))
	ic.bind(&"accept_invite", accept)
	ic.bind(&"take_invite", accept)
	# permadeath loop-closer — the DeathScreen emits this; region-aware respawn lives in the session
	ic.bind(&"respawn", func(s, _a): s.respawn())
