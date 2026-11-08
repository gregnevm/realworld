# RealWorld — ui/input_verbs.gd : the design-system §5 interaction grammar as DATA (spec 0005 §2.10).
#
# The verb table, installed onto an InputController. A verb is the only thing allowed to call a sim
# mutator (R9). This is the data replacement for main.gd's _unhandled_input/_handle_click switch.
extends RefCounted

const InventoryMod = preload("res://scripts/sim/inventory.gd")
const MainCapsule = preload("res://scripts/sim/capsule.gd")
const Fmt = preload("res://scripts/ui/format.gd")

# Основна капсула (spec 0010, REQ-0010-36/38): sim повертає value-data, ТЕКСТ — тут (R10: ніякої української в sim). Перша причина
# відмови словами; `duplicate` мовчить (повтор команди в тому ж тіку — не помилка гравця).
static func capsule_result_text(r: Dictionary) -> String:
	var prot: bool = StringName(r.get("axis", &"capsule")) == &"protection"
	if bool(r.get("ok", false)):
		return ("▣ Захист капсули: рівень %d" % int(r.get("protection", 0))) if prot else ("◎ Капсула: рівень %d" % int(r.get("level", 0)))
	match StringName(r.get("reason", &"")):
		&"cost": return Fmt.capsule_shortfall(r.get("missing", {}), bool(r.get("far", false)))
		&"max": return "Вищого рівня нема."
		&"no_capsule": return "Капсули нема."
		&"dead": return "Зараз недоступно."
	return ""

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
	# клік по своїй грядці циклить культуру (farming v2); текст — тут, сим повертає value-data (R10)
	ic.bind(&"set_crop", func(s, a):
		var r: Dictionary = s.sim.set_crop(int(a.x), int(a.y))
		if bool(r.get("ok", false)):
			var what := "мішана грядка"
			if str(r.get("crop", "")) != "":
				what = "%s%s" % [str(r.get("icon", "")), str(r.get("label", ""))]
			s.sim._flash("🌱 Культура: " + what))
	ic.bind(&"deconstruct",  func(s, a):
		var r: Dictionary = s.sim.demolish(int(a.x), int(a.y))
		if not r.ok: s.sim._flash(String(r.get("msg", ""))))
	# spec 0009 — personal inventory
	ic.bind(&"set_hand",     func(s, a): InventoryMod.set_hand(s.sim, int(a.i)))
	ic.bind(&"inv_move",     func(s, a): InventoryMod.move(s.sim, int(a.a), int(a.b)))
	ic.bind(&"craft_building", func(s, a):
		var r: Dictionary = InventoryMod.craft_building(s.sim, String(a.kind))
		if not r.ok: s.sim._flash(String(r.get("msg", ""))))
	ic.bind(&"inv_sort",     func(s, _a): InventoryMod.sort_backpack(s.sim))
	ic.bind(&"inv_split",    func(s, a):
		if not InventoryMod.split(s.sim, int(a.i)): s.sim._flash("Нема куди розділити (потрібен вільний слот і стак ≥ 2)."))
	ic.bind(&"inv_drop",     func(s, a):
		if InventoryMod.drop(s.sim, int(a.i)): s.sim._flash("Викинуто — торба лежить поруч (підбереш, відійшовши й повернувшись)."))
	ic.bind(&"stash_all",    func(s, _a):
		var r: Dictionary = InventoryMod.stash_all(s.sim)
		s.sim._flash(String(r.get("msg", ""))))
	ic.bind(&"take_storage", func(s, a):
		var r: Dictionary = InventoryMod.take_from_storage(s.sim, String(a.res), int(a.n))
		if not r.ok: s.sim._flash(String(r.get("msg", ""))))
	ic.bind(&"repair",       func(s, a):
		var r: Dictionary = s.sim.repair(int(a.x), int(a.y))
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
	# Основна капсула: ДВІ осі — два verb-и (панель називає їх аліасами: R9 забороняє sim-імена в панелях). Захист викликає модуль напряму
	# (Sim-делегата нема — ліміт публічних методів); перехід у регіон/склад — наявні stash_all/take_storage.
	ic.bind(&"capsule_upgrade", func(s, _a):
		var msg: String = capsule_result_text(s.sim.upgrade_capsule())
		if msg != "": s.sim._flash(msg))
	ic.bind(&"capsule_protect", func(s, _a):
		var msg: String = capsule_result_text(MainCapsule.upgrade_protection(s.sim))
		if msg != "": s.sim._flash(msg))
	# permadeath loop-closer — the DeathScreen emits this; region-aware respawn lives in the session
	ic.bind(&"respawn", func(s, _a): s.respawn())
