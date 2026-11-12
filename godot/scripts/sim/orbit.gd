# RealWorld — sim/orbit.gd : spec 0011 — the Orbit: account-level roster of clones, safe stock, lazy settle (REQ-0011-4/10…22/53/59…63).
#
# Static funcs over the account record `o` (a Dictionary; `o.safe_stock` is a SafeStock). Pure w.r.t. the world: no tick,
# no clock reads (`now` is an argument, int UTC-ms), no RNG (stats derive from a hash of (account_seed, counter, tech, genome)),
# integers only. Not wired into Session yet: `use_orbit` stays OFF, so the save and `world_hash` are untouched (REQ-0011-1/2).
extends RefCounted

const Tuning = preload("res://scripts/sim/clone_tuning.gd")
const SafeStock = preload("res://scripts/sim/safe_stock.gd")

const ACTIVE := "active"
const SLEEPING := "sleeping"
const DEGRADING := "degrading"
const GENOME_NAMES := {"gatherer": "Добувач", "builder": "Будівельник", "rider": "Райдер"}   # = Tuning.GENOMES[*].name (для view без залежності від таблиці)


# REQ-0011-63: a new account = exactly 2 clones (1 active + 1 sleeping, OD-62); the free base clone is a separate action.
static func new_account(account_seed: int, now: int) -> Dictionary:
	var o: Dictionary = {
		"clones": [], "creating": [], "base_ready_at": 0, "safe_stock": SafeStock.new(), "tech": {},
		"account_seed": account_seed, "clone_counter": 0, "last_death": {}, "bio_pool": 0,
		"saved_at": now, "last_seen_now": now,
	}
	var a: Dictionary = _make_clone(o, "", now, false)
	a["state"] = ACTIVE
	var s: Dictionary = _make_clone(o, "", now, false)
	(o["clones"] as Array).append(a)
	(o["clones"] as Array).append(s)
	return o


# REQ-0011-37: an old save has no Orbit → ONE active clone built from the existing pawn (its skills), not the free base clone and not
# the 2-clone start of a new account. Idempotent by the caller: it runs only while the save has no `orbit` key.
static func migrate_from_pawn(account_seed: int, now: int, skills: Dictionary) -> Dictionary:
	var o: Dictionary = {
		"clones": [], "creating": [], "base_ready_at": 0, "safe_stock": SafeStock.new(), "tech": {},
		"account_seed": account_seed, "clone_counter": 0, "last_death": {}, "bio_pool": 0,
		"saved_at": now, "last_seen_now": now,
	}
	var c: Dictionary = _make_clone(o, "", now, false)
	c["state"] = ACTIVE
	(c["pawn"] as Dictionary)["skills"] = skills.duplicate(true)
	(o["clones"] as Array).append(c)
	return o


# REQ-0011-16: start stats = f(account_seed, counter, tech, genome_type) in permille; no RNG. The free base clone is flat 1000.
static func derive_stats(account_seed: int, counter: int, tech: Dictionary, genome_type: String, is_base: bool) -> Dictionary:
	var out: Dictionary = {}
	var tech_levels: int = 0
	for k in tech:
		tech_levels += int(tech[k])
	for axis in Tuning.AXES:
		var v: int = 1000
		if not is_base:
			v += int(_fnv("%d|%d|%s" % [account_seed, counter, axis]) % 50)
			v += tech_levels * Tuning.value("tech_bonus_permille")
			if genome_type != "" and String((Tuning.GENOMES[genome_type] as Dictionary)["axis"]) == axis:
				v += Tuning.value("genome_start_permille")
		out[axis] = v
	return out


static func _make_clone(o: Dictionary, genome_type: String, now: int, is_base: bool) -> Dictionary:
	o["clone_counter"] = int(o["clone_counter"]) + 1   # REQ-0011-53: monotone, never decreases on death
	var n: int = int(o["clone_counter"])
	return {
		"id": "c%d" % n, "n": n, "state": SLEEPING, "born_at": now,
		"pawn": {"skills": {}, "items": [], "equipped": {}, "inv": [], "hand": null},
		"genome_type": "" if is_base else genome_type,
		"stats": derive_stats(int(o["account_seed"]), n, o["tech"], "" if is_base else genome_type, is_base),
		"starve_since": 0,
	}


static func find(o: Dictionary, id: String) -> int:
	var cl: Array = o["clones"]
	for i in cl.size():
		if String((cl[i] as Dictionary)["id"]) == id:
			return i
	return -1


static func active_clone(o: Dictionary) -> Dictionary:
	for c in o["clones"]:
		if String((c as Dictionary)["state"]) == ACTIVE:
			return c
	return {}


# REQ-0011-11: at most one active; every verb ends by calling this. Returns a list of violations (empty = ok).
static func check_invariants(o: Dictionary) -> Array:
	var errs: Array = []
	var actives: int = 0
	var seen: Dictionary = {}
	for c in o["clones"]:
		var d: Dictionary = c
		if String(d["state"]) == ACTIVE:
			actives += 1
		if seen.has(String(d["id"])):
			errs.append("dup_id")
		seen[String(d["id"])] = true
	if actives > 1:
		errs.append("many_active")
	if (o["clones"] as Array).size() > Tuning.value("roster_slots") + 1:   # +1: the free base clone may exceed the slots only on an empty roster path
		errs.append("roster_over")
	return errs


# Back to the Orbit screen: the active clone falls asleep (0 active is valid only here).
static func to_orbit(o: Dictionary) -> void:
	for c in o["clones"]:
		if String((c as Dictionary)["state"]) == ACTIVE:
			(c as Dictionary)["state"] = SLEEPING


# REQ-0011-13: respawn = choosing a sleeping clone. Degrading clones can be woken too (the stage is a warning, OD-C19).
static func choose(o: Dictionary, id: String) -> Dictionary:
	var i: int = find(o, id)
	if i < 0:
		return {"ok": false, "reason": &"no_clone"}
	if not active_clone(o).is_empty():
		return {"ok": false, "reason": &"already_active"}
	(o["clones"][i] as Dictionary)["state"] = ACTIVE
	return {"ok": true, "id": id}


# REQ-0011-14/59/60/61: the free base clone — always offered; 5-min cooldown from absolute `now`; flat stats, no genome.
# On a full roster it is refused unless the roster is empty (anti-softlock keeps a way out of every state).
static func claim_base_clone(o: Dictionary, now: int) -> Dictionary:
	if now < int(o["last_seen_now"]):
		return {"ok": false, "reason": &"clock_back"}   # REQ-0011-22: a clock rolled back never shortens the cooldown
	if now < int(o["base_ready_at"]):
		return {"ok": false, "reason": &"cooldown", "ready_at": int(o["base_ready_at"])}
	var cl: Array = o["clones"]
	if cl.size() >= Tuning.value("roster_slots") and not cl.is_empty():
		return {"ok": false, "reason": &"roster_full"}
	var c: Dictionary = _make_clone(o, "", now, true)
	cl.append(c)
	o["base_ready_at"] = maxi(int(o["base_ready_at"]), now + Tuning.value("base_cooldown_ms"))
	o["last_seen_now"] = maxi(int(o["last_seen_now"]), now)
	return {"ok": true, "id": String(c["id"])}


# REQ-0011-15: a levelled clone costs 1 genome + bio from the safe stock and takes ~12 real hours (OD-94).
static func begin_creation(o: Dictionary, genome_type: String, now: int) -> Dictionary:
	if not Tuning.GENOMES.has(genome_type):
		return {"ok": false, "reason": &"bad_genome"}
	var slots_used: int = (o["clones"] as Array).size() + (o["creating"] as Array).size()
	if slots_used >= Tuning.value("roster_slots"):
		return {"ok": false, "reason": &"roster_full"}
	var ss: Variant = o["safe_stock"]
	var gid: String = "genome:" + genome_type
	if int(ss.count(gid)) < Tuning.value("create_genome"):
		return {"ok": false, "reason": &"no_genome"}
	if _bio_total(ss) < Tuning.value("create_bio"):
		return {"ok": false, "reason": &"no_bio"}
	ss.take(gid, Tuning.value("create_genome"))
	_take_bio(ss, Tuning.value("create_bio"))
	(o["creating"] as Array).append({"started_at": now, "ready_at": now + Tuning.value("create_ms"), "genome_type": genome_type})
	return {"ok": true}


# Moves finished creations into the roster as sleeping clones (ordered by ready_at, then by insertion).
static func collect_ready(o: Dictionary, now: int) -> int:
	var made: int = 0
	var rest: Array = []
	for e in o["creating"]:
		var d: Dictionary = e
		if int(d["ready_at"]) <= now:
			(o["clones"] as Array).append(_make_clone(o, String(d["genome_type"]), int(d["ready_at"]), false))
			made += 1
		else:
			rest.append(d)
	o["creating"] = rest
	return made


# REQ-0011-12/17/52: a death removes the clone and writes last_death; idempotent by clone_id.
@warning_ignore("integer_division")
static func on_death(o: Dictionary, clone_id: String, cause: String, now: int, bag_pos: Array = [], bag_region: String = "") -> Dictionary:
	var i: int = find(o, clone_id)
	if i < 0:
		return {"ok": false, "reason": &"already_gone"}
	var c: Dictionary = o["clones"][i]
	(o["clones"] as Array).remove_at(i)
	o["last_death"] = {
		"clone_id": clone_id, "cause": cause, "at": now, "born_at": int(c["born_at"]),
		"lived_real_sec": maxi(0, (now - int(c["born_at"])) / 1000), "bag_pos": bag_pos, "bag_region": bag_region,
	}
	return {"ok": true}


# --- REQ-0011-18…22: lazy settle of the sleepers ---------------------------------------------------------------------------

static func _bio_total(ss: Variant) -> int:
	var t: int = 0
	for sl in ss.slots:
		var d: Dictionary = sl
		if not d.is_empty() and Tuning.is_bio(String(d["id"])):
			t += int(d["n"])
	return t


static func _take_bio(ss: Variant, n: int) -> int:
	var left: int = n
	for i in range(ss.slots.size() - 1, -1, -1):
		if left <= 0:
			break
		var d: Dictionary = ss.slots[i]
		if not d.is_empty() and Tuning.is_bio(String(d["id"])):
			left -= int(ss.take(String(d["id"]), left))
	return n - left


static func _take_ration(ss: Variant) -> int:
	for sl in ss.slots:
		var d: Dictionary = sl
		if not d.is_empty() and Tuning.is_ration(String(d["id"])):
			return int(ss.take(String(d["id"]), 1))
	return 0


static func copy_account(o: Dictionary) -> Dictionary:
	var c: Dictionary = o.duplicate(true)
	c["safe_stock"] = (o["safe_stock"] as RefCounted).call("copy")
	return c


# Pure: returns the settled COPY; `o` is untouched. Δ = max(0, now - saved_at), 0 if the clock went back (OD-60), capped (OD-49).
# Whole quanta only; the remainder stays in saved_at, so settle(settle(o,t1),t2) == settle(o,t2) for quantum-aligned times.
@warning_ignore("integer_division")
static func settle(o: Dictionary, now: int) -> Dictionary:
	var r: Dictionary = copy_account(o)
	var seen: int = int(r["last_seen_now"])
	var base: int = int(r["saved_at"])
	var delta: int = 0 if now < seen else maxi(0, now - base)
	r["last_seen_now"] = maxi(seen, now)
	var cap: int = Tuning.value("catchup_cap_ms")
	var q: int = Tuning.value("quantum_ms")
	var capped: bool = delta > cap
	if capped:
		delta = cap
	var steps: int = delta / q
	var rate_q: int = Tuning.value("bio_per_hour") * Tuning.MICRO * q / 3600000
	var ss: Variant = r["safe_stock"]
	for k in steps:
		var tq: int = base + k * q
		var cl: Array = r["clones"]
		var dead_ids: Array = []
		for c in cl:   # roster stays ordered by ascending id (n): clones are only appended, ids are monotone
			var d: Dictionary = c
			if String(d["state"]) == ACTIVE:
				continue
			var fed: bool = false
			if int(r["bio_pool"]) < rate_q:
				var got: int = _take_ration(ss)
				r["bio_pool"] = int(r["bio_pool"]) + got * Tuning.MICRO
			if int(r["bio_pool"]) >= rate_q:
				r["bio_pool"] = int(r["bio_pool"]) - rate_q
				fed = true
			if fed:
				d["starve_since"] = 0
				d["state"] = SLEEPING   # OD-151: feeding resets the starvation clock and heals `degrading`
			else:
				if int(d["starve_since"]) == 0:
					d["starve_since"] = tq + 1   # +1 keeps 0 as «not starving» even at t=0
				var starving_for: int = tq + q - int(d["starve_since"]) + 1
				if starving_for >= Tuning.value("dead_after_ms"):
					dead_ids.append(String(d["id"]))
				elif starving_for >= Tuning.value("degrade_after_ms"):
					d["state"] = DEGRADING
		for id in dead_ids:
			on_death(r, String(id), "bio_starvation", tq + q)
	r["saved_at"] = now if capped else base + steps * q
	return r


# REQ-0011-22: persistence-side monotone merge — saved_at / last_seen_now / base_ready_at never decrease.
static func monotone_merge(prev: Dictionary, next: Dictionary) -> Dictionary:
	for k in ["saved_at", "last_seen_now", "base_ready_at"]:
		next[k] = maxi(int(prev.get(k, 0)), int(next.get(k, 0)))
	return next


# --- save / hash -----------------------------------------------------------------------------------------------------------

static func to_dict(o: Dictionary) -> Dictionary:
	var d: Dictionary = o.duplicate(true)
	d["safe_stock"] = (o["safe_stock"] as RefCounted).call("to_dict")
	return d


# JSON round-trip tolerant (int -> float): every number is coerced back to int.
static func from_dict(d: Dictionary) -> Dictionary:
	var o: Dictionary = {
		"clones": [], "creating": [], "tech": {}, "last_death": {},
		"base_ready_at": int(d.get("base_ready_at", 0)), "account_seed": int(d.get("account_seed", 0)),
		"clone_counter": int(d.get("clone_counter", 0)), "bio_pool": int(d.get("bio_pool", 0)),
		"saved_at": int(d.get("saved_at", 0)), "last_seen_now": int(d.get("last_seen_now", 0)),
		"safe_stock": SafeStock.from_dict(d.get("safe_stock", {})),
	}
	for c in d.get("clones", []):
		var s: Dictionary = c
		var st: Dictionary = {}
		for k in (s.get("stats", {}) as Dictionary):
			st[String(k)] = int(s["stats"][k])
		(o["clones"] as Array).append({
			"id": String(s["id"]), "n": int(s["n"]), "state": String(s["state"]), "born_at": int(s["born_at"]),
			"pawn": s.get("pawn", {}), "genome_type": String(s.get("genome_type", "")), "stats": st,
			"starve_since": int(s.get("starve_since", 0)),
		})
	for e in d.get("creating", []):
		var m: Dictionary = e
		(o["creating"] as Array).append({"started_at": int(m["started_at"]), "ready_at": int(m["ready_at"]), "genome_type": String(m["genome_type"])})
	for k in (d.get("tech", {}) as Dictionary):
		(o["tech"] as Dictionary)[String(k)] = int(d["tech"][k])
	var ld: Dictionary = d.get("last_death", {})
	if not ld.is_empty():
		var ldo: Dictionary = ld.duplicate(true)
		for k in ["at", "born_at", "lived_real_sec"]:
			ldo[k] = int(ldo.get(k, 0))
		o["last_death"] = ldo
	return o


static func _fnv(s: String) -> int:
	var h: int = -3750763034362895579   # FNV-1a 64 offset basis 0xcbf29ce484222325 as signed int64
	for b in s.to_utf8_buffer():
		h = (h ^ int(b)) * 1099511628211
	return h & 0x7fffffffffffffff


# REQ-0011-38: account hash — NOT part of world_hash; ints/strings only.
static func account_hash(o: Dictionary) -> String:
	var h: int = _fnv(JSON.stringify(to_dict(o), "", true))
	return "%08x%08x" % [(h >> 32) & 0xffffffff, h & 0xffffffff]
