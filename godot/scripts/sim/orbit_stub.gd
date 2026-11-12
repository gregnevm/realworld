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

const Inventory = preload("res://scripts/sim/inventory.gd")

# REQ-0011-8 (OD-153, число з дорученого власником): «біля якоря респавну» = не далі за 6 клітинок від капсули.
const ASCEND_REACH := 6.0


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


# REQ-0010-28 / REQ-0011-72 (OD-154): reinforcement from the Orbit — the «resource set» variant of OD-67. Only inside the 24 h window after a
# breach (immune_until > now), once per window (reinforcement_used), for a solo owner. PRICE = 10% (rounded up) of what is invested in the
# CURRENT level, taken from the base stock (atomic: all or nothing). PAYLOAD = up to REINFORCE_PAYLOAD of each resource the safe stock holds,
# delivered into the base stock. A container without `count/take` (a test double) offers nothing -> {ok:false, reason: orbit_empty}, no side effect.
const REINFORCE_PAYLOAD := {"planks": 10, "scrap": 5, "stone": 10, "wood": 20}
const REINFORCE_PRICE_PERMILLE := 100   # OD-102: 10 %


static func _payload(safe_stock: Variant) -> Dictionary:
	var out: Dictionary = {}
	if safe_stock == null or not safe_stock.has_method("count") or not safe_stock.has_method("take"):
		return out
	for res in REINFORCE_PAYLOAD:
		var have: int = mini(int(safe_stock.count(String(res))), int(REINFORCE_PAYLOAD[res]))
		if have > 0:
			out[String(res)] = have
	return out


@warning_ignore("integer_division")
static func _price(s) -> Dictionary:
	var c: Dictionary = s.main_capsule
	var inv: Dictionary = c.get("invested", {})
	var lvl: int = int(c.get("level", 0))
	var row: Variant = inv.get(str(lvl), inv.get(lvl, {}))
	var out: Dictionary = {}
	if row is Dictionary:
		for res in (row as Dictionary):
			var n: int = int((row as Dictionary)[res])
			if n > 0:
				out[String(res)] = maxi(1, (n * REINFORCE_PRICE_PERMILLE + 999) / 1000)
	return out


static func _window_open(s) -> bool:
	return s.get("use_main_capsule") == true and not (s.main_capsule as Dictionary).is_empty() \
		and int(s.main_capsule.get("immune_until", 0)) > int(s.now_ms) and int(s.main_capsule.get("reinforcement_used", 0)) == 0


@warning_ignore("integer_division")
static func call_reinforcement(s: Variant, safe_stock: Variant = null) -> Dictionary:
	if s.get("use_main_capsule") != true or (s.main_capsule as Dictionary).is_empty():
		return {"ok": false, "reason": &"no_capsule"}
	if s.dead:
		return {"ok": false, "reason": &"dead"}
	if safe_stock == null:
		return {"ok": false, "reason": &"no_orbit"}
	if not _window_open(s):
		return {"ok": false, "reason": &"no_window"}
	var payload: Dictionary = _payload(safe_stock)
	if payload.is_empty():
		return {"ok": false, "reason": &"orbit_empty"}
	var price: Dictionary = _price(s)
	for res in price:
		if int(s.res_amount(String(res))) < int(price[res]):
			return {"ok": false, "reason": &"no_funds"}
	for res in price:
		s._stock_take(String(res), int(price[res]))
	var got: Dictionary = {}
	var keys: Array = payload.keys()
	keys.sort()
	for res in keys:
		var took: int = int(safe_stock.take(String(res), int(payload[res])))
		if took > 0:
			s._stock_add(String(res), took)
			got[String(res)] = took
	s.main_capsule.reinforcement_used = 1
	s._log("🛰 Підкріплення з орбіти прибуло на склад капсули.", "good")
	return {"ok": true, "paid": price, "delivered": got}


# REQ-0010-86: does the panel offer «Підкріплення»? Only when the call could succeed on the Orbit side (window open, unused, the safe stock holds
# a payload) — the panel shows no unavailable action. Funds are checked by the call itself (a refusal with a reason).
static func reinforcement_offered(s: Variant, safe_stock: Variant = null) -> bool:
	return safe_stock != null and not s.dead and _window_open(s) and not _payload(safe_stock).is_empty()


# REQ-0011-7/8: «піднятись на орбіту» — обрані стеки з РЮКЗАКА в safe_stock, лише коли герой біля якоря респавну (капсули). Єдиний
# другий шлях входу в safe_stock (перший — send_to_safe_zone зі складу капсули). Частковий перенос (OD-58): скільки вмістилось.
# {ok:true, moved:{res:n}} | {ok:false, reason: no_capsule|dead|no_orbit|far|empty}.
static func ascend_from_pack(s, safe_stock: Variant, picks: Array) -> Dictionary:
	if s.get("use_main_capsule") != true or (s.main_capsule as Dictionary).is_empty():
		return {"ok": false, "reason": &"no_capsule"}
	if s.dead:
		return {"ok": false, "reason": &"dead"}
	if safe_stock == null:
		return {"ok": false, "reason": &"no_orbit"}
	var t: Array = (s.main_capsule as Dictionary).tile
	var d: float = Vector2(float(s.player.px), float(s.player.py)).distance_to(Vector2(float(t[0]) + 0.5, float(t[1]) + 0.5))
	if d > ASCEND_REACH:
		return {"ok": false, "reason": &"far"}
	var ids: Array = picks.duplicate()
	ids.sort()
	var moved: Dictionary = {}
	for id in ids:
		var have: int = Inventory.count(s, String(id))
		if have <= 0:
			continue
		var took: int = clampi(int(safe_stock.deposit(String(id), have)), 0, have)
		if took > 0 and Inventory.take(s, String(id), took):
			moved[String(id)] = took
	if moved.is_empty():
		return {"ok": false, "reason": &"empty"}
	return {"ok": true, "moved": moved}
