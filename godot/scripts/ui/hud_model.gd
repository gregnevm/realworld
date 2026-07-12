# RealWorld — ui/hud_model.gd : the ViewModel (spec 0005 §2.5). The `Balance.assess()` analogue.
#
# PURE + Node-free: never extends Node, never calls get_node/queue_redraw/Color/add_child. It is the
# SINGLE place that reaches through session.sim, building one immutable presentation Dictionary per
# frame from read/derived surfaces only. It maps raw fields to ENUMS itself (R11) and holds only value
# data — ids, enums (StringName), numbers, Strings — never a live sim.player / enemy ref / Callable (R8).
extends RefCounted
const Fmt = preload("res://scripts/ui/format.gd")
const GameData = preload("res://scripts/data.gd")
const CatalogView = preload("res://scripts/ui/catalog_view.gd")
const CatalogSim = preload("res://scripts/catalog_sim.gd")
const Social = preload("res://scripts/social.gd")
const WorldGen = preload("res://scripts/world_gen.gd")

# session: the SessionScript (has .sim). world/ctx: the same shapes the kernel consumes (built by HudRoot).
# balance: a Balance director constructed ONCE by HudRoot and reused (never new() per frame).
static func snapshot(session, world: Dictionary, ctx: Dictionary, balance) -> Dictionary:
	if session == null or session.sim == null:
		return {"alive": false}
	var sim: Variant = session.sim
	var p: Dictionary = sim.player
	return {
		"alive":     true,
		"dead":      bool(sim.dead),
		"region":    _region_slice(sim, session),
		"clock":     _clock_slice(sim),
		"env":       _env_slice(ctx),
		"vitals":    _vitals_slice(p, sim),
		"stats":     _stats_slice(sim),
		"stock":     _stock_slice(sim),
		"build":     _build_slice(sim),
		"threat":    _threat_slice(world, ctx, balance),
		"equipment": _equipment_slice(sim),
		"raid":      _raid_slice(sim),
		"research":  _research_slice(session),
		"catalog":   _catalog_slice(sim),
		"gear":      _gear_slice(sim),
		"logistics": _logistics_slice(sim),
		"capsule":   _capsule_slice(sim),
		"social_info": _social_slice(sim),
	}

# --- gear (craft/equip loadout, spec 0001; parity with main.gd's items panel) ---
static func _gear_slice(sim) -> Dictionary:
	var p: Dictionary = sim.player
	var items: Array = (p.get("items", []) as Array)
	var eq: Dictionary = p.get("equipped", {})
	var rows: Array = []
	var unlocked: Variant = sim.get("research_unlocked")
	for id in GameData.ITEM_ORDER:
		var it: Dictionary = GameData.ITEMS[id]
		var slot := String(it.slot)
		rows.append({
			"id": String(id),
			"name": String(it.name),
			"slot": slot,
			"cost": _cost_line("i:" + String(id), it.recipe),
			"affordable": _afford(sim, it.recipe),
			"owned": items.has(id),
			"equipped": String(eq.get(slot, "")) == String(id),
			"locked": _research_locked(it, unlocked),
		})
	return {"rows": rows}

# --- logistics (real-geography trade hubs + live convoys; parity with main.gd's world panel) ---
static func _logistics_slice(sim) -> Dictionary:
	# Object.get: absent on lean test fakes -> graceful empty slice, no runtime error
	var regions: Variant = sim.get("regions")
	var live_convoys: Variant = sim.get("convoys")
	if regions == null or live_convoys == null:
		return {"hubs": [], "convoys": []}
	var hubs: Array = []
	for i in range(1, (regions as Array).size()):
		var r: Dictionary = regions[i]
		var offer: Dictionary = r.get("offer", {})
		if offer.is_empty():
			continue
		hubs.append({
			"index": i,
			"name": String(r.name),
			"dist_km": int(r.get("d", 0.0)),
			"buys": String(offer.buys),
			"buys_icon": String(GameData.RES[offer.buys].icon),
			"sells": String(offer.sells),
			"sells_icon": String(GameData.RES[offer.sells].icon),
			"rate": int(offer.rate),
			"have": _amount(sim, offer.buys),
		})
	var convoys: Array = []
	for c in live_convoys:
		convoys.append({
			"id": int(c.id),
			"hub": String(c.hub_name),
			"phase": StringName(c.phase),
			"pct": int(clampf(float(c.t) / maxf(0.01, float(c.dur)) * 100.0, 0.0, 100.0)),
			"recv_icon": String(GameData.RES[c.recv_res].icon),
			"recv_amt": int(c.recv_amt),
			"ambushed": bool(c.ambushed),
		})
	return {"hubs": hubs, "convoys": convoys}

# --- capsule / invites (spec 0002 drop pods; the shareable-address travel loop) ---
static func _capsule_slice(sim) -> Dictionary:
	var caps: Variant = sim.get("capsule")
	var live_invites: Variant = sim.get("invites")
	if caps == null or live_invites == null:
		return {"charges": 0, "radius_km": 0, "invites": []}
	var invites: Array = []
	for inv in live_invites:
		invites.append({
			"id": String(inv.id),
			"name": String(inv.get("name", "?")),
			"inviter": String(inv.get("inviter", "?")),
			"clan": String(inv.get("clan", "—")),
			"lat": float(inv.get("lat", 0.0)),
			"lon": float(inv.get("lon", 0.0)),
		})
	return {
		"charges": int((caps as Dictionary).get("charges", 0)),
		"radius_km": int((caps as Dictionary).get("radius_km", 0)),
		"invites": invites,
	}

# --- social (read view over the clan/alliance/empire graph + friends geography, spec 0002) ---
static func _social_slice(sim) -> Dictionary:
	var g: Variant = sim.get("social")   # Object.get: absent on fakes / headless sims -> graceful
	if g == null or not (g is Dictionary) or (g as Dictionary).is_empty():
		return {"available": false}
	var friends: Array = []
	for f in g.friends:
		friends.append({
			"name": String(f.name),
			"clan_name": String(g.clans[f.clan].name),
			"place": String(f.get("place", "")),
			"lat": float(f.lat),
			"lon": float(f.lon),
			"dist_km": int(WorldGen.haversine_km(float(sim.map.lat), float(sim.map.lon), float(f.lat), float(f.lon))),
		})
	var hostile_ids: Array = Social.hostiles(g)   # ONE walk — names AND pressure read from it
	var hostile_names: Array = []
	for cid in hostile_ids:   # hostiles() returns clan IDS, not dicts
		hostile_names.append(String((g.clans[cid] as Dictionary).name))
	return {
		"available": true,
		"clan": String(Social.my_clan(g).name),
		"members": (Social.my_clan(g).members as Array).size(),
		"alliance": String(Social.my_alliance(g).get("name", "—")),
		"empire": String(Social.my_empire(g).get("name", "—")),
		"hostiles": hostile_names,
		"pressure": float(Social.raid_pressure(g, hostile_ids)),
		"friends": friends,
	}

# icon+number cost line (colorblind-safe: icon precedes the number, R11). Delegates to the ONE
# formatter GameData.cost_str and caches per def-id: recipe/cost tables are const, а слайси
# рахуються щокадру — формат виконується раз на id, не 60×/с.
static var _cost_cache: Dictionary = {}
static func _cost_line(id: String, cost: Dictionary) -> String:
	if not _cost_cache.has(id):
		_cost_cache[id] = GameData.cost_str(cost)
	return String(_cost_cache[id])

# --- content tree (the deep catalogue surfaced in the HUD via the CatalogView pipeline) ---
# Value-data only (R8). Reads the process-shared forward-engine model (catalog_sim) so the browsers'
# actionable rows and the router's build/craft/research commands operate the SAME state — browse an
# action, click it, watch the counts move. The live data.gd sim (`sim`) is untouched; this is a
# parallel catalogue model whose db is the cached default catalogue.
static func _catalog_slice(_sim) -> Dictionary:
	var cs: Variant = CatalogSim.shared(CatalogView.default_db())
	return CatalogView.snapshot(cs.db, cs.view_state())

# Build the Balance `world` dict {buildings,stock,items} from the sim. Lives HERE (not in HudRoot) so
# the thin controller never names an economy field (R4 keeps hud_root.gd free of mechanic tokens).
static func world_of(sim) -> Dictionary:
	if sim == null:
		return {"buildings": [], "stock": {}, "items": []}
	var bs := []
	for b in sim.buildings:
		var def: Dictionary = GameData.BUILDINGS.get(b.kind, {})
		bs.append({"value": float(def.get("hp", 50.0)) * 0.5})
	return {"buildings": bs, "stock": sim.stock, "items": (sim.player.get("items", []) as Array)}

# --- region / seed (the shareable world address; spec pillar) ---
static func _region_slice(sim, session) -> Dictionary:
	var m: Dictionary = sim.map
	var chain := ""
	var stored := 0
	if session != null and session.has_method("chain_head"):
		chain = Fmt.short_hash(String(session.chain_head()))
	if session != null and session.has_method("stored_region_count"):
		stored = int(session.stored_region_count())
	return {
		"name": String(m.get("place_name", "Регіон")),
		"lat": float(m.get("lat", 0.0)),
		"lon": float(m.get("lon", 0.0)),
		"seed": int(sim.region_seed()),
		"chain": chain,
		"stored": stored,
	}

# --- clock ---
static func _clock_slice(sim) -> Dictionary:
	var f: float = float(sim.time.frac)
	return {
		"day": int(sim.time.day),
		"hhmm": Fmt.hhmm(f),
		"phase": Fmt.phase_enum(f),
		"daylight": float(sim.daylight()),
	}

# --- environment (from the kernel ctx a TemperatureSystem/WeatherSystem writes; defaults until wired) ---
static func _env_slice(ctx: Dictionary) -> Dictionary:
	return {
		"temp_c": float(ctx.get("temp_c", 15.0)),
		"weather": StringName(ctx.get("weather", &"clear")),
		"light": float(ctx.get("light", 1.0)),
		"indoor": bool(ctx.get("indoor", false)),
	}

# --- vitals (need bars carry an urgency ENUM, not a color — R11) ---
static func _need_row(id: StringName, v: float) -> Dictionary:
	var vv: float = clampf(v, 0.0, 100.0)
	return {
		"id": id,
		"label": Fmt.need_label(id),
		"icon": Fmt.need_icon(id),
		"pct": int(vv),
		"state": Fmt.urgency_enum(vv),
	}

static func _vitals_slice(p: Dictionary, sim) -> Dictionary:
	return {
		"bars": [
			_need_row(&"hp", float(p.get("hp", 0.0))),
			_need_row(&"hunger", float(p.get("hunger", 0.0))),
			_need_row(&"rest", float(p.get("rest", 0.0))),
		],
		"sleeping": bool(p.get("sleeping", false)),
		"carry": {"cur": int(sim.carry_total()), "cap": int(p.get("carry_cap", 0))},
	}

# --- stats: ONE-TRUTH-PER-NUMBER (R5). value = legacy getter; explain = placeholder of the same shape
# so the swap to StatWorker.value(ctx)/.explain(ctx) (spec 0003 §8) needs no widget change. ---
static func _stats_slice(sim) -> Dictionary:
	var dmg: float = float(sim.melee_damage())
	return {"melee": {"value": dmg, "explain": Fmt.melee_explain_placeholder(dmg)}}

# Stock reads go through the sim's open-stock seam (spec 0008 phase 2: keys may be catalogue ids when
# sim.use_catalog is on); lean test fakes carry a plain dict, so degrade to the raw read for them.
static func _amount(sim, res) -> int:
	return int(sim.res_amount(res)) if sim.has_method("res_amount") else int(sim.stock.get(res, 0))

static func _afford(sim, cost: Dictionary) -> bool:
	return bool(sim.afford(cost)) if sim.has_method("afford") else GameData.can_afford(sim.stock, cost)

# --- stock (rows in RES_ORDER; total computed purely; cap from the sim) ---
static func _stock_slice(sim) -> Dictionary:
	var rows := {}
	var total := 0
	for res in GameData.RES_ORDER:
		var amt: int = _amount(sim, res)
		rows[res] = amt
		total += amt
	return {"rows": rows, "total": total, "cap": int(sim.storage_cap())}

# --- build palette (afford flag per building; locked = research-ворота ще не відкриті, spec 0007) ---
static func _build_slice(sim) -> Dictionary:
	var slots := []
	var unlocked: Variant = sim.get("research_unlocked")
	for i in GameData.BUILD_ORDER.size():
		var key: String = GameData.BUILD_ORDER[i]
		var def: Dictionary = GameData.BUILDINGS[key]
		slots.append({
			"key": key,
			"name": String(def.name),
			"afford": _afford(sim, def.cost),
			"locked": _research_locked(def, unlocked),
			"cost": _cost_line("b:" + key, def.cost),
			"hotkey": "1234567890".substr(i, 1) if i < 10 else "",
		})
	return {"slots": slots}

# true, коли def має ворота досліджень і вони ще не відкриті (мапа з сима; ключі String/StringName)
static func _research_locked(def: Dictionary, unlocked: Variant) -> bool:
	var need := String(def.get("research", ""))
	if need == "":
		return false
	if unlocked == null or not (unlocked is Dictionary):
		return true
	return not ((unlocked as Dictionary).has(need) or (unlocked as Dictionary).has(StringName(need)))

# --- threat (the Balance HUD readout; assess() snapshot mapped to value data) ---
static func _threat_slice(world: Dictionary, ctx: Dictionary, balance) -> Dictionary:
	if balance == null:
		return {"available": false}
	var a: Dictionary = balance.assess(world, ctx)
	return {
		"available": true,
		"phase": StringName(a.get("phase", &"calm")),
		"threat": float(a.get("threat", 0.0)),
		"wealth": float(a.get("wealth", 0.0)),
		"raid_hint": int(a.get("raid_hint", 0)),
		"difficulty": float(a.get("difficulty", 1.0)),
		"generosity": float(a.get("generosity", 1.0)),
	}

# --- equipment (equipped tool/weapon names; value data only) ---
static func _equipment_slice(sim) -> Dictionary:
	var p: Dictionary = sim.player
	var eq: Dictionary = p.get("equipped", {})
	return {
		"tool": _item_name(String(eq.get("tool", ""))),
		"weapon": _item_name(String(eq.get("weapon", ""))),
		"owned": (p.get("items", []) as Array).duplicate(),
	}

static func _item_name(id: String) -> String:
	return String(GameData.ITEMS[id].name) if (id != "" and GameData.ITEMS.has(id)) else "—"

# --- research (the tech-pipeline readout; value data only — a Progression summary + option/queue lists).
# Reads an optional session.progression (kernel/progression.gd); {wired:false} when research isn't wired
# yet, so the panel degrades gracefully and the fake-session tests stay green. ---
static func _research_slice(session) -> Dictionary:
	var prog: Variant = session.progression if (session != null and "progression" in session) else null
	if prog == null:
		return {"wired": false}
	var s: Dictionary = prog.summary()
	var options: Array = []
	for r in prog.available():
		options.append({
			"id": r.id,
			"label": prog.label_of(r.id),
			"tier": prog.tier_of(r.id),
			"cost": float(r.cost()),
		})
	options.sort_custom(func(a, b): return (int(a.tier) < int(b.tier)) if int(a.tier) != int(b.tier) else (float(a.cost) < float(b.cost)))
	var queue: Array = []
	for qid in (s.get("queue", []) as Array):
		queue.append({"id": qid, "label": prog.label_of(qid), "tier": prog.tier_of(qid)})
	var rate := 0.0
	if session != null and session.has_method("research_rate"):
		rate = float(session.research_rate())
	var active_remaining: float = maxf(0.0, float(s.get("active_cost", 0.0)) - float(s.get("active_progress", 0.0)))
	var eta: float = (active_remaining / rate) if (rate > 0.0 and float(s.get("active_cost", 0.0)) > 0.0) else -1.0
	return {
		"wired": true,
		"rate": rate,
		"active_eta_days": eta,
		"level": int(s.get("level", 0)),
		"unlocked": int(s.get("unlocked", 0)),
		"total": int(s.get("total", 0)),
		"active": StringName(s.get("active", &"")),
		"active_label": String(s.get("active_label", "")),
		"active_pct": float(s.get("active_pct", 0.0)),
		"options": options,
		"queue": queue,
		"counts": prog.catalog_counts(),
		"next_unlocks": _next_unlocks(prog),
	}

# How much the ACTIVE project will open (per-category counts) — the "researching X unlocks N" preview.
static func _next_unlocks(prog) -> Dictionary:
	var a: StringName = prog.active_id()
	if a == &"":
		return {"buildings": 0, "recipes": 0, "items": 0, "total": 0}
	var u: Dictionary = prog.unlocks_of(a)
	var nb: int = (u.buildings as Array).size()
	var nr: int = (u.recipes as Array).size()
	var ni: int = (u.items as Array).size()
	return {"buildings": nb, "recipes": nr, "items": ni, "total": nb + nr + ni}

# --- raid (state enum for the banner; no live enemy refs — R8) ---
static func _raid_slice(sim) -> Dictionary:
	var r: Dictionary = sim.raid
	var state: StringName = &"none"
	if bool(r.get("active", false)):
		state = &"active"
	elif bool(r.get("warned", false)):
		state = &"incoming"
	return {"state": state, "wave": int(r.get("wave", 0)), "count": (sim.enemies as Array).size()}
