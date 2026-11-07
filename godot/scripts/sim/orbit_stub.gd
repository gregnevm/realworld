# RealWorld — sim/orbit_stub.gd : STUBS of the spec 0011 (Орбіта) seams that spec 0010 consumes (0010-W1b, D2).
#
# Spec 0011 (Orbit: roster of clones, safe stock) is frozen for step 1 (OD-106): only the SEAMS exist, and they live
# in this file — NOT in sim/capsule.gd — so that 0011, when it lands, replaces THIS file's bodies and never edits the
# capsule domain. Static funcs over the sim instance `s`, no state, no preload of sim.gd (no cycle).
#
# Seam owned here today:
#   respawn_source(s) — WHOSE BODY comes back after death. 0011 will answer with the roster (1 active clone + the free
#   base clone on a 5-minute cooldown, OD-51/54/57); until then it is the existing starter pawn, `_default_player`.
#   WHERE the body stands is NOT decided here: the position is set by MainCapsule.landing (one landing seam, REQ-0010-98).
# The safe-zone container is `Session.orbit.safe_stock` once 0011 exists (never `Session.safe_stock`): `safe_stock_of(session)` is the ONE
# place that reads it, and answers null until then. W3b adds the two action seams of spec 0010 (REQ-0010-28/29), both honest stubs:
#   send_to_safe_zone(s, safe_stock) — the ONLY way a resource goes from the world into the safe stock. `safe_stock` is a duck-typed
#     container with `deposit(res: String, n: int) -> int` (the accepted amount, partial like OD-58); the slot capacity (32, OD-61/105) is
#     0011's number and lives in ITS container, not here. null -> {ok:false, reason:&"no_orbit"}.
#   call_reinforcement(s, safe_stock) — the price source and what is delivered are open (Q-9, OD-67): always {ok:false, reason:&"no_orbit"}.
# Resources moved into the safe stock leave `s.stock`, so neither resolve_raid (it only touches `invested`) nor the death bag reaches them.
extends RefCounted


# The body a respawn brings: a fresh starter pawn standing on the map spawn (landing moves it next to the capsule).
static func respawn_source(s) -> Dictionary:
	return s._default_player(s.map.spawn)


# The safe-stock container of a session; null while spec 0011 (Orbit) does not exist.
static func safe_stock_of(session: Variant) -> Variant:
	if session == null:
		return null
	var orbit: Variant = session.get("orbit")
	return orbit.get("safe_stock") if orbit != null else null


# REQ-0010-29: move what the capsule storage holds into the safe stock — as much as fits, the rest stays (OD-58). Resources go in alphabetical order
# (deterministic). {ok:true, moved:{res:n}, left:{res:n}} | {ok:false, reason: no_capsule|dead|no_orbit|empty|full}.
static func send_to_safe_zone(s, safe_stock: Variant = null) -> Dictionary:
	if s.get("use_main_capsule") != true or (s.main_capsule as Dictionary).is_empty():
		return {"ok": false, "reason": &"no_capsule"}
	if s.dead:
		return {"ok": false, "reason": &"dead"}
	if safe_stock == null:
		return {"ok": false, "reason": &"no_orbit"}
	var moved: Dictionary = {}
	var left: Dictionary = {}
	var keys: Array = (s.stock as Dictionary).keys()
	keys.sort()
	for k in keys:
		var have: int = int(s.res_amount(k))   # stock-шов: ключі вже у словнику активного режиму (res_key — тотожність)
		if have <= 0:
			continue
		var took: int = clampi(int(safe_stock.deposit(String(k), have)), 0, have)
		if took > 0:
			s._stock_take(String(k), took)
			moved[String(k)] = took
		if took < have:
			left[String(k)] = have - took
	if moved.is_empty():
		return {"ok": false, "reason": &"full" if not left.is_empty() else &"empty"}
	return {"ok": true, "moved": moved, "left": left}


# REQ-0010-28 (stub): the reinforcement needs the Orbit (price source Q-9, payload OD-67) -> refused until 0011.
static func call_reinforcement(_s: Variant, _safe_stock: Variant = null) -> Dictionary:
	return {"ok": false, "reason": &"no_orbit"}


# REQ-0010-86: does the panel offer «Підкріплення»? Not on the stub (the window/payload are unknown) — the panel shows no unavailable action.
static func reinforcement_offered(_s: Variant, _safe_stock: Variant = null) -> bool:
	return false
