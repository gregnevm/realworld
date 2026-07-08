# RealWorld — ui/input_verbs.gd : the design-system §5 interaction grammar as DATA (spec 0005 §2.10).
#
# The verb table, installed onto an InputController. A verb is the only thing allowed to call a sim
# mutator (R9). This is the data replacement for main.gd's _unhandled_input/_handle_click switch.
extends RefCounted

# Install the standard grammar. `session` has `.sim` and `.travel_to(lat,lon,name)`.
static func install(ic) -> void:
	ic.bind(&"order_move",   func(s, a): s.sim.order_move(int(a.x), int(a.y)))
	ic.bind(&"order_gather", func(s, a): s.sim.order_gather(int(a.x), int(a.y)))
	ic.bind(&"order_attack", func(s, a): s.sim.order_attack(a.target))
	ic.bind(&"build",        func(s, a): s.sim.try_build(String(a.kind), int(a.x), int(a.y)))
	ic.bind(&"deconstruct",  func(s, a): s.sim.demolish(int(a.x), int(a.y)))
	ic.bind(&"craft",        func(s, a): s.sim.craft_item(String(a.id)))
	ic.bind(&"equip",        func(s, a): s.sim.equip(String(a.id)))
	ic.bind(&"send_convoy",  func(s, a): s.sim.dispatch_convoy(int(a.hub), String(a.res), int(a.amt)))
	# research pipeline — the ResearchPanel emits these; the session drives kernel/progression.gd (R9)
	ic.bind(&"enqueue_research", func(s, a): s.enqueue_research(String(a.id)))
	ic.bind(&"start_research",   func(s, a): s.start_research(String(a.id)))
	ic.bind(&"clear_research",   func(s, a): s.clear_research_queue())
	ic.bind(&"launch_capsule", func(s, a):
		var r = s.sim.try_launch_capsule(float(a.lat), float(a.lon), String(a.name))
		if r.ok: s.travel_to(float(a.lat), float(a.lon), String(a.name)))
	ic.bind(&"accept_invite", func(s, a):
		var r = s.sim.accept_invite(String(a.id))
		if r.ok: s.travel_to(float(r.lat), float(r.lon), String(r.name)))
