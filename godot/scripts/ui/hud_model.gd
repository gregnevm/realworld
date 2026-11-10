# RealWorld — ui/hud_model.gd : the ViewModel (spec 0005 §2.5). The `Balance.assess()` analogue.
#
# PURE + Node-free: never extends Node, never calls get_node/queue_redraw/Color/add_child. It is the
# SINGLE place that reaches through session.sim, building one immutable presentation Dictionary per
# frame from read/derived surfaces only. It maps raw fields to ENUMS itself (R11) and holds only value
# data — ids, enums (StringName), numbers, Strings — never a live sim.player / enemy ref / Callable (R8).
extends RefCounted
const Fmt = preload("res://scripts/ui/format.gd")
const GameData = preload("res://scripts/data.gd")
const InventoryMod = preload("res://scripts/sim/inventory.gd")
const CatalogView = preload("res://scripts/ui/catalog_view.gd")
const GoalPointerScript = preload("res://scripts/ui/goal_pointer.gd")
const CatalogSim = preload("res://scripts/catalog_sim.gd")
const Social = preload("res://scripts/social.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const Gear = preload("res://scripts/kernel/gear.gd")
const HeroHealth = preload("res://scripts/sim/hero_health.gd")
const CatalogDefs = preload("res://scripts/catalog_defs.gd")
const Director = preload("res://scripts/sim/director.gd")
const CapsuleTexts = preload("res://scripts/ui/capsule_texts.gd")
const MainCapsule = preload("res://scripts/sim/capsule.gd")   # лише чисті читання зони/підказок (gather_preview)
const SimScript = preload("res://scripts/sim.gd")   # physics CONSTS only (light radii, emitter reach)
const WorldInputScript = preload("res://scripts/ui/world_input.gd")   # placement grammar (paintable runs)

# session: the SessionScript (has .sim). world/ctx: the same shapes the kernel consumes (built by HudRoot).
# balance: a Balance director constructed ONCE by HudRoot and reused (never new() per frame).
static func snapshot(session, world: Dictionary, ctx: Dictionary, balance) -> Dictionary:
	if session == null or session.sim == null:
		return {"alive": false}
	var sim: Variant = session.sim
	var p: Dictionary = sim.player
	var snap := {
		"alive":     true,
		"dead":      bool(sim.dead),
		"region":    _region_slice(sim, session),
		"clock":     _clock_slice(sim),
		"env":       _env_slice(sim, ctx),
		"light":     _light_slice(sim),
		"heat":      _heat_slice(sim),
		"inspect":   _inspect_slice(sim, ctx),
		"speed":     float(ctx.get("speed", 1.0)),
		"ui":        _ui_slice(ctx),
		"goals":     _goals_slice(session),
		"death":     _death_slice(sim),
		"vitals":    _vitals_slice(p, sim),
		"stats":     _stats_slice(sim),
		"stock":     _stock_slice(sim),
		"inventory": _inventory_slice(sim),
		"power":     _power_slice(sim),
		"build":     _build_slice(sim, String(ctx.get("selected_build", ""))),
		"threat":    _threat_slice(world, ctx, balance),
		"equipment": _equipment_slice(sim),
		"raid":      _raid_slice(sim),
		"research":  _research_slice(session),
		"catalog":   _catalog_slice(sim),
		"gear":      _gear_slice(sim),
		"logistics": _logistics_slice(sim),
		"capsule":   _capsule_slice(sim, ctx),
		"social_info": _social_slice(sim),
	}
	# spec 0013: the key exists ONLY while the presence layer is live — a world without it (flags OFF, no
	# tick yet) keeps the byte-identical baseline snapshot (REQ-0012-3 / REQ-0010-85 pins).
	var nearby := _nearby_slice(session)
	if bool(nearby.get("available", false)):
		snap["nearby"] = nearby
	# spec 0014 (B+C): the key exists only while there IS something to point at (a world without it keeps the baseline snapshot)
	# the hover ghost / touch brackets already frame the target → the marker steps aside (REQ-0014-6)
	var ghost_on: bool = (String(ctx.get("selected_build", "")) != "" and _hover_in_map(sim, ctx)) \
		or (bool(ctx.get("touch", false)) and String(ctx.get("action_build", "")) != "")
	if bool(ctx.get("goal_pointer", false)):   # view-прапор use_goal_pointer (REQ-0014-15): OFF (фікстури/бейзлайн-піни) → знімок байт-у-байт як до спеки
		var gp: Dictionary = GoalPointerScript.compute(sim, snap, ghost_on)
		if not gp.is_empty():
			snap["goal_pointer"] = gp
	return snap

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
static func _capsule_slice(sim, ctx: Dictionary = {}) -> Dictionary:
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
	var out: Dictionary = {
		"charges": int((caps as Dictionary).get("charges", 0)),
		"radius_km": int((caps as Dictionary).get("radius_km", 0)),
		"invites": invites,
	}
	if sim.get("use_main_capsule") == true and not (sim.get("main_capsule") as Dictionary).is_empty():
		out["main"] = _capsule_main(sim, ctx)   # ключ ЛИШЕ при ON: OFF-слайс і панель — байт-у-байт як до спеки 0010
	return out

# Основна капсула (spec 0010 W4a): рівні обох осей, дії за станами (REQ-0010-86), ціна/перша причина відмови словами (REQ-0010-38),
# кільце зони (REQ-0010-16: показується лише при вибраній капсулі — відкрита її панель — або при попередженні/контакті рейду) і склад.
# Лише value-data (R8): жодного живого посилання на sim; тексти — Fmt (R10), числа — з модуля капсули (R5).
const CAPSULE_STORAGE_ROWS := 6
static func _capsule_main(sim, ctx: Dictionary) -> Dictionary:
	var cap: Dictionary = sim.main_capsule
	var actions: Array = []
	for a in MainCapsule.actions(sim):
		actions.append(a)
	var raid_state: StringName = StringName(String((sim.get("capsule_raid") as Dictionary).get("state", "none")))
	var selected: bool = (ctx.get("open_panels", []) as Array).has("capsule_bay")
	var alert: bool = raid_state == MainCapsule.ST_WARNING or raid_state == MainCapsule.ST_CONTACT
	var at: Vector2i = MainCapsule.tile(sim)
	var stock_rows: Array = []
	var keys: Array = (sim.stock as Dictionary).keys()
	keys.sort()
	for k in keys:
		var n: int = int(sim.stock[k])
		if n > 0 and stock_rows.size() < CAPSULE_STORAGE_ROWS:
			stock_rows.append({"res": String(k), "n": n, "label": "%s %s" % [CatalogDefs.res_icon(String(k)).strip_edges(), CatalogDefs.res_label(String(k))]})
	return {
		"active": true,
		"level": int(cap.get("level", 0)), "max": MainCapsule.max_level(sim),
		"protection": MainCapsule.protection_of(sim), "max_protection": MainCapsule.max_protection(sim),
		"actions": actions,
		"upgrade": _capsule_axis(MainCapsule.quote(sim, &"capsule")),
		"protect": _capsule_axis(MainCapsule.quote(sim, &"protection")),
		"immune_left_ms": MainCapsule.immune_left_ms(sim),
		"raid_state": raid_state,
		"ring": {"show": selected or alert, "alert": alert, "x": at.x, "y": at.y, "radius": MainCapsule.zone_radius(sim),
			"dir": int((sim.get("capsule_raid") as Dictionary).get("dir", 0)), "raiders": _capsule_raiders(sim, raid_state),
			"core_hp": float((sim.get("capsule_raid") as Dictionary).get("core_hp", 0.0)) if raid_state == MainCapsule.ST_CONTACT else -1.0,
			"core_max": MainCapsule.core_hp_max(sim), "buff_pct": _capsule_buff_pct(sim)},
		"storage": stock_rows,
	}

# Позначки рейдерів на полі (лише в контакті): клітинки живих НЕ-ботів — value-data (R8), максимум RAIDER_MARKS.
const RAIDER_MARKS := 32
static func _capsule_raiders(sim, raid_state: StringName) -> Array:
	var out: Array = []
	if raid_state != MainCapsule.ST_CONTACT:
		return out
	for e in sim.enemies:
		if String((e as Dictionary).get("kind", "raider")) == "bot" or out.size() >= RAIDER_MARKS:
			continue
		out.append({"x": float(e.px), "y": float(e.py)})
	return out

static func _capsule_axis(q: Dictionary) -> Dictionary:
	return {"next": int(q.next), "can": bool(q.can), "cost": Fmt.cost_words(q.cost), "why": Fmt.capsule_shortfall(q.missing, bool(q.far))}

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
# Value-data only (R8). TWO sources behind one slice (spec 0008 phase 3):
#   • sim.use_catalog ON  -> the LIVE sim is the state: its unlocked research, its open stock, its
#     placed stations — browser rows are real actions on the real world (build_actions filtered to
#     the live-buildable adapter set so every row the player can click actually places);
#   • flag OFF (shipped default) -> the process-shared forward-engine model (catalog_sim), honestly
#     badged as a sandbox by the panels.
static func _catalog_slice(sim) -> Dictionary:
	if sim != null and bool(sim.get("use_catalog") == true):
		var stations: Dictionary = {}
		for b in sim.buildings:
			stations[StringName(String(b.kind))] = true
		return CatalogView.snapshot(CatalogView.default_db(), {
			"unlocked": sim.research_unlocked,
			"stock": sim.stock,
			"stations": stations,
			"build_filter": CatalogDefs.live_ids(),
			"live": true,
		})
	var cs: Variant = CatalogSim.shared(CatalogView.default_db())
	return CatalogView.snapshot(cs.db, cs.view_state())

# Build the Balance `world` dict {buildings,stock,items} from the sim. Lives HERE (not in HudRoot) so
# the thin controller never names an economy field (R4 keeps hud_root.gd free of mechanic tokens).
static func world_of(sim) -> Dictionary:
	if sim == null:
		return {"buildings": [], "stock": {}, "items": []}
	# real sims: the ONE sim-side builder (sim/director.gd) — the HUD readout and the live Balance
	# pacing read the SAME numbers and can never disagree. Lean fakes keep the data.gd fallback.
	if sim.has_method("building_def"):
		return Director.world_of(sim)
	var bs := []
	for b in sim.buildings:
		bs.append({"value": float(GameData.BUILDINGS.get(b.kind, {}).get("hp", 50.0)) * 0.5})
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
		"season": String(sim.season_name()) if sim.has_method("season_name") else "",
	}

# --- environment: the REAL region climate at the hero (top bar 🌡/⛅ + T overlay). Live sims answer
# from their own getters; lean fakes fall back to the kernel-ctx shape (defaults until wired). ---
static func _env_slice(sim, ctx: Dictionary) -> Dictionary:
	if sim != null and sim.has_method("ambient_temp_c"):
		var hx: int = int(sim.player.px)
		var hy: int = int(sim.player.py)
		return {
			"temp_c": float(sim.ambient_temp_c()),     # outdoor air (the climate the region has)
			"weather": StringName(sim.weather),
			"light": float(sim.light_at(hx, hy)),
			"indoor": bool(sim.is_indoor(hx, hy)),
			"anomaly_c": float(sim.temp_offset),
		}
	return {
		"temp_c": float(ctx.get("temp_c", 15.0)),
		"weather": StringName(ctx.get("weather", &"clear")),
		"light": float(ctx.get("light", 1.0)),
		"indoor": bool(ctx.get("indoor", false)),
		"anomaly_c": 0.0,
	}

# --- light: what the ambient-night pass and the L overlay draw (value data: ambient level + every
# ACTIVE light emitter with its radius — the same inputs sim.light_at() folds, so the night the
# player SEES is the night the work-speed penalty USES). ---
static func _light_slice(sim) -> Dictionary:
	if sim == null or not sim.has_method("daylight_level"):
		return {"ambient": 1.0, "sources": [], "threshold": 0.35, "night_max": SimScript.NIGHT_ALPHA_MAX}
	var src: Array = []
	for b in sim.buildings:
		if bool(sim.building_def(String(b.kind)).get("extra", {}).get("light", false)) and sim.device_active(b):
			src.append({"x": int(b.x), "y": int(b.y), "r": float(SimScript.LIGHT_RADIUS.get(String(b.kind), 3.0))})
	return {
		"ambient": float(sim.daylight_level()),
		"sources": src,
		"threshold": float(SimScript.DARK_LIGHT_THRESHOLD),
		"night_max": float(SimScript.NIGHT_ALPHA_MAX),
	}

# --- heat map inputs for the T overlay: outdoor °C + indoor cells + ACTIVE heat emitters (the same
# fold as sim.temp_at, so the map can never disagree with what the body feels). ---
static func _heat_slice(sim) -> Dictionary:
	if sim == null or not sim.has_method("ambient_temp_c"):
		return {"available": false}
	var emitters: Array = []
	for b in sim.buildings:
		var heat := float(sim.building_def(String(b.kind)).get("extra", {}).get("heat", 0.0))
		if heat > 0.0 and sim.device_active(b):
			emitters.append({"x": int(b.x), "y": int(b.y), "heat": heat})
	var indoor: Array = (sim.indoor as Dictionary).keys()
	indoor.sort()
	return {
		"available": true,
		"n": int(sim.n),
		"ambient": float(sim.ambient_temp_c()),
		"emitters": emitters,
		"indoor": indoor,
		"radius": int(SimScript.EMITTER_RADIUS),
		"setpoint": float(SimScript.INDOOR_SETPOINT_C),
		"insulation": float(SimScript.INDOOR_INSULATION),
		"comfort_min": float(Gear.COMFORT_MIN_C),
		"comfort_max": float(Gear.COMFORT_MAX_C),
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
	# located health (sim/hero_health.gd): blood bar, condition inspect lines, downed flag and the
	# felt-°C comfort state. All value data (R8); lean test fakes lack the tracker -> full-health row.
	var tracker: Variant = sim.get("health")
	var felt: float = float(sim.hero_felt_c()) if sim.has_method("hero_felt_c") else 20.0
	return {
		"bars": [
			_need_row(&"hp", float(p.get("hp", 0.0))),
			_need_row(&"hunger", float(p.get("hunger", 0.0))),
			_need_row(&"rest", float(p.get("rest", 0.0))),
			_need_row(&"blood", 100.0 * (float(tracker.blood) if tracker != null else 1.0)),
		],
		"sleeping": bool(p.get("sleeping", false)),
		"downed": bool(tracker.downed) if tracker != null else false,
		"conditions": _condition_texts(sim) if tracker != null else [],
		"felt_c": felt,
		"comfort": Fmt.comfort_enum(felt, Gear.COMFORT_MIN_C, Gear.COMFORT_MAX_C),
		"carry": {"cur": int(sim.carry_total()), "cap": int(p.get("carry_cap", 0))},
	}

static func _condition_texts(sim) -> Array:
	var out: Array = []
	for row in HeroHealth.condition_rows(sim):
		out.append(Fmt.condition_text(row))
	return out

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
# --- spec 0009 inventory: slots (value data), the hand, the craft list with first refusal reason, and the
# storage you stand at (stash/take). {enabled:false} on stock-path sims and lean fakes. ---
const INV_CRAFT_BUILDINGS := ["wall", "door", "floor", "campfire", "torch", "storage", "bed", "workbench",
	"research_bench", "spike_trap", "turret", "heater", "lamp"]
static func _inventory_slice(sim) -> Dictionary:
	if sim == null or not sim.get("use_inventory") == true:
		return {"enabled": false}
	var slots: Array = []
	for sl in sim.player.inv:
		var id := String(sl.id)
		slots.append({"id": id, "n": int(sl.n), "label": _inv_label(sim, id)})
	var at := Vector2(sim.player.px, sim.player.py)
	var craft: Array = []
	for kind in INV_CRAFT_BUILDINGS:
		var rc: Dictionary = InventoryMod.building_recipe(sim, kind)
		if rc.is_empty():
			continue
		var def: Dictionary = sim.building_def(kind)
		var why := ""
		if not sim.research_ok(def):
			why = "🔒 " + String(sim._research_label(def))
		elif String(rc.station) != "" and not InventoryMod.near_station(sim, String(rc.station)):
			why = "потрібен верстак поруч"
		elif not InventoryMod.can_pay(sim, rc.cost, at):
			why = "бракує " + String(sim._cost_str(InventoryMod.missing(sim, rc.cost, at)))
		craft.append({"type": "building", "id": kind, "label": String(rc.name), "cost": GameData.cost_str(rc.cost),
			"ok": why == "", "why": why, "have": int(InventoryMod.count(sim, InventoryMod.BLD + kind))})
	for iid in GameData.ITEM_ORDER:
		var it: Dictionary = GameData.ITEMS[iid]
		var why2 := ""
		if not sim.research_ok(it):
			why2 = "🔒 " + String(sim._research_label(it))
		elif not sim.has_workbench():
			why2 = "потрібен верстак"
		elif not InventoryMod.can_pay(sim, it.recipe, at):
			why2 = "бракує " + String(sim._cost_str(InventoryMod.missing(sim, it.recipe, at)))
		craft.append({"type": "item", "id": iid, "label": String(it.name), "cost": GameData.cost_str(it.recipe),
			"ok": why2 == "", "why": why2, "have": int(InventoryMod.count(sim, iid))})
	# what you CAN make right now comes first (Terraria-style), the rest keeps catalogue order below it
	var ready: Array = craft.filter(func(c: Dictionary) -> bool: return bool(c.ok))
	craft = ready + craft.filter(func(c: Dictionary) -> bool: return not bool(c.ok))
	var near := InventoryMod.near_storage(sim)
	var storage: Array = []
	if near:
		for res in GameData.RES_ORDER:
			if _amount(sim, res) > 0:
				storage.append({"res": res, "n": _amount(sim, res), "label": String(GameData.RES[res].label)})
	return {"enabled": true, "slots": slots, "hand": int(sim.player.get("hand", 0)), "hotbar": InventoryMod.HOTBAR,
		"craft": craft, "near_storage": near, "storage": storage, "link": InventoryMod.link_unlocked(sim),
		"bags": (sim.bags as Array).size()}

static func _inv_label(sim, id: String) -> String:
	if id == "":
		return ""
	if InventoryMod.is_building(id):
		return String(sim.building_def(InventoryMod.building_kind(id)).get("name", id))
	if GameData.ITEMS.has(id):
		return String(GameData.ITEMS[id].name)
	if GameData.RES.has(id):
		return String(GameData.RES[id].label)
	return id

static func _stock_slice(sim) -> Dictionary:
	var rows := {}
	var total := 0
	if sim.get("use_inventory") == true:   # spec 0009: the HUD counters read what you CARRY (the backpack)
		var used := 0
		for sl in sim.player.inv:
			if String(sl.id) != "":
				used += 1
		for res in GameData.RES_ORDER:
			rows[res] = int(InventoryMod.count(sim, res))
		return {"rows": rows, "total": used, "cap": InventoryMod.SLOTS, "extra": [], "backpack": true}
	for res in GameData.RES_ORDER:
		var amt: int = _amount(sim, res)
		rows[res] = amt
		total += amt
	var extra: Array = _stock_extras(sim)
	for e in extra:
		total += int(e.amt)
	return {"rows": rows, "total": total, "cap": int(sim.storage_cap()), "extra": extra}

# Catalogue-only stock lines (spec 0008 phase 4): under the open stock, mining/crafting accumulates
# resources beyond the six live ids — surface every nonzero one (sorted, capped to the panel pool)
# with its catalogue icon+label. [] when the flag is off / on lean fakes (graceful).
const STOCK_EXTRA_CAP := 8
static func _stock_extras(sim) -> Array:
	if sim == null or not bool(sim.get("use_catalog") == true):
		return []
	var mapped: Dictionary = {}
	for res in GameData.RES_ORDER:
		mapped[String(sim.res_key(res))] = true
	var db: Variant = CatalogView.default_db()
	var keys: Array = (sim.stock as Dictionary).keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		if out.size() >= STOCK_EXTRA_CAP:
			break
		if mapped.has(str(k)) or int(sim.stock[k]) <= 0:
			continue
		var d: Variant = db.get_def(StringName(str(k)))
		out.append({
			"id": str(k),
			"icon": String(d.icon()) if d != null and d.has_method("icon") else "•",
			"label": String(d.label()) if d != null and d.has_method("label") else str(k),
			"amt": int(sim.stock[k]),
		})
	return out

# --- power grid (Batch 8c readout; {participants:false} until powered buildings exist / on fakes) ---
static func _power_slice(sim) -> Dictionary:
	var net: Variant = sim.get("power_net")
	if net == null or not (net is Dictionary) or (net as Dictionary).is_empty():
		return {"participants": false}
	var d: Dictionary = net
	return {
		"participants": true,
		"supply": float(d.get("supply", 0.0)),
		"draw": float(d.get("draw", 0.0)),
		"stored": float(d.get("stored", 0.0)),
		"capacity": float(d.get("capacity", 0.0)),
		"state": &"brownout" if bool(d.get("brownout", false)) else &"ok",
	}

# --- build palette (afford flag per building; locked = research-ворота ще не відкриті, spec 0007) ---
# `selected` mirrors the armed ghost (view state handed in through ctx) so the bar's pressed look
# follows the keyboard digits too — one truth for "what am I placing".
static func _build_slice(sim, selected: String = "") -> Dictionary:
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
			"selected": key == selected,
			"tip": Fmt.building_blurb(key, def, int(SimScript.EMITTER_RADIUS)),
		})
	return {"slots": slots, "selected": selected}

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

# --- inspect (design-system §5 «inspect = hover»): what is under the cursor, as value data. The
# hovered cell, the cursor's world position and the armed ghost are VIEW state the entry scene hands
# in through ctx (hover / hover_world / selected_build); without a hover the slice is hidden. ---
const INSPECT_HIDDEN := {"shown": false}

static func _inspect_slice(sim, ctx: Dictionary) -> Dictionary:
	var vm: Dictionary = _inspect_raw(sim, ctx)
	if bool(ctx.get("touch", false)) and bool(vm.get("shown", false)):
		vm = vm.duplicate()
		vm["hint"] = Fmt.touchify(String(vm.get("hint", "")))
		var lines: Array = []
		for l in vm.get("lines", []):
			lines.append(Fmt.touchify(String(l)))
		vm["lines"] = lines
	return vm

static func _inspect_raw(sim, ctx: Dictionary) -> Dictionary:
	if sim == null or not sim.has_method("building_def") or not ctx.has("hover"):
		return INSPECT_HIDDEN
	var t: Vector2i = ctx.hover
	var n: int = int(sim.n)
	if t.x < 0 or t.y < 0 or t.x >= n or t.y >= n:
		return INSPECT_HIDDEN
	var cell: int = t.y * n + t.x
	var sel := String(ctx.get("selected_build", ""))
	if sel == WorldInputScript.WorldInput.REMOVE_TOOL:
		return _inspect_remove(sim, cell)
	if sel != "":
		return _inspect_ghost(sim, sel, t, cell)
	var hw: Vector2 = ctx.get("hover_world", Vector2(t.x + 0.5, t.y + 0.5))
	for e in sim.enemies:
		if Vector2(float(e.px), float(e.py)).distance_to(hw) < 0.7:
			return _inspect_enemy(e)
	if sim.map.nodes.has(cell):
		return _inspect_node(sim, sim.map.nodes[cell], t)
	if sim.bgrid.has(cell):
		return _inspect_building(sim, sim.bgrid[cell])
	return _inspect_ground(sim, t, cell)

# The touch remove tool's tooltip: what a tap here would take down and what it gives back.
static func _inspect_remove(sim, cell: int) -> Dictionary:
	if not sim.bgrid.has(cell):
		return {"shown": true, "state": &"info", "title": "🗑 Розібрати", "lines": ["тут нічого розбирати"],
			"hint": "торкнись своєї будівлі · ✖ — сховати інструмент"}
	var b: Dictionary = sim.bgrid[cell]
	var def: Dictionary = sim.building_def(String(b.kind))
	if bool(def.get("indestructible", false)):   # капсула: ніколи не розбирається (REQ-0010-06/75) — підказка каже це, а не «назад: нічого»
		return {"shown": true, "state": &"crit", "title": "🗑 Розібрати: %s" % String(def.get("name", "")),
			"lines": ["не розбирається"], "hint": "✖ — сховати інструмент"}
	var back: Dictionary = {}
	for k in def.get("cost", {}):
		var half: int = int(def.cost[k]) / 2
		if half > 0:
			back[k] = half
	var lone: bool = String(b.kind) == "storage" and _count_kind(sim, "storage") <= 1
	var refund := "нічого"
	if not back.is_empty():
		refund = GameData.cost_str(back) if not bool(sim.get("use_catalog") == true) else _catalog_cost(sim, back)
	return {"shown": true, "state": &"crit" if lone else &"warn",
		"title": "🗑 Розібрати: %s" % String(def.get("name", CatalogDefs.building_label(String(b.kind)))),
		"lines": ["єдиний склад — не розібрати" if lone else "назад: %s" % refund],
		"hint": "торкнись — розібрати · веди пальцем — ряд"}

# --- ui (VIEW mode flags the frame's own panels read: touch layout, the armed tool) ---
static func _ui_slice(ctx: Dictionary) -> Dictionary:
	return {
		"touch": bool(ctx.get("touch", false)),
		"remove": String(ctx.get("selected_build", "")) == WorldInputScript.WorldInput.REMOVE_TOOL,
		"armed": String(ctx.get("selected_build", "")) != "",
		"menu": bool(ctx.get("menu_open", false)),
	}

static func _inspect_enemy(e: Dictionary) -> Dictionary:
	var bot: bool = String(e.get("kind", "raider")) == "bot"
	return {"shown": true, "state": &"crit",
		"title": "🤖 Патрульний робот" if bot else "⚔ Рейдер",
		"lines": ["❤ %d/%d" % [int(ceil(float(e.hp))), int(float(e.maxhp))],
			"розібраний дає ⚙ брухт і 🔩 компоненти" if bot else "б'є сильно — бийся біля турелей і шипів"],
		"hint": "ЛКМ — атакувати"}

static func _inspect_node(sim, node: Dictionary, t: Vector2i) -> Dictionary:
	var kind := String(node.kind)
	var info: Dictionary = GameData.NODEINFO.get(kind, {})
	var res := String(info.get("res", ""))
	var gives: String = "%s %s" % [String(GameData.RES[res].icon), String(GameData.RES[res].label)] if GameData.RES.has(res) else res
	if bool(sim.get("use_catalog") == true) and kind == "rock":
		gives += " (+руда, вугілля, глина)"
	# spec 0010: баф зони капсули читається з клітинки, ДЕ ГЕРОЙ ПРАЦЮВАТИМЕ (не де він стоїть зараз) — одна правда з sim._do_gather
	var secs: float = MainCapsule.gather_preview(sim, t.y * int(sim.n) + t.x) if sim.get("use_main_capsule") == true else float(sim.gather_time(node))
	var lines: Array = ["залишилось %d · дає %s" % [int(node.amount), gives],
		"≈%.1f с за одиницю" % secs]
	if float(sim.light_at(t.x, t.y)) < float(SimScript.DARK_LIGHT_THRESHOLD):
		lines.append("🌙 темно — робота повільніша (смолоскип: клавіша 0)")
	return {"shown": true, "state": &"good", "title": Fmt.node_title(kind), "lines": lines,
		"hint": "ЛКМ — %s · повну торбу пішак сам віднесе на склад" % Fmt.node_verb(kind)}

# Поточний сумарний баф рівня (найменша з осей, %), 0 = рівня нема: підпис зони каже, ЩО саме в ній діє (число з даних, не вигадане).
static func _capsule_buff_pct(sim) -> int:
	var lvl: int = int(sim.main_capsule.get("level", 0))
	if lvl <= 0:
		return 0
	var lo: float = 1.0e9
	for key in MainCapsule.BUFF_KEYS:
		lo = minf(lo, MainCapsule.buff_bonus(sim, String(key), lvl))
	return int(round(lo * 100.0)) if lo < 1.0e8 else 0

# Що дає рівень: відсоток приросту ЗА РІВЕНЬ береться з даних (бафи рівня 1 по чотирьох осях); різні осі -> «від +N%» за найменшим.
static func _capsule_gives_level(sim) -> String:
	var lo: float = 1.0e9
	var hi: float = -1.0e9
	for key in MainCapsule.BUFF_KEYS:
		var b: float = MainCapsule.buff_bonus(sim, String(key), 1)
		lo = minf(lo, b)
		hi = maxf(hi, b)
	var pct: int = int(round(lo * 100.0))
	if pct <= 0:
		return ""   # даних про приріст нема -> рядка нема (не вигадуємо число)
	return CapsuleTexts.t("gives_level") % pct if is_equal_approx(lo, hi) else CapsuleTexts.t("gives_level_from") % pct

static func _inspect_capsule(sim) -> Dictionary:
	var lines: Array = ["◎ рівень %d/%d · ▣ захист %d/%d" % [int(sim.main_capsule.get("level", 0)), MainCapsule.max_level(sim),
		MainCapsule.protection_of(sim), MainCapsule.max_protection(sim)]]
	var gives: String = _capsule_gives_level(sim)
	if gives != "":
		lines.append(gives)
	lines.append(CapsuleTexts.t("gives_protect"))
	if MainCapsule.is_immune(sim):
		lines.append(CapsuleTexts.t("immune_inspect") % Fmt.left_ms(MainCapsule.immune_left_ms(sim)) + " · " + CapsuleTexts.t("immune_why"))
	return {"shown": true, "state": &"info", "title": String(sim.building_def(MainCapsule.KIND).get("name", "")), "lines": lines,
		"hint": "ЛКМ — панель капсули"}

static func _inspect_building(sim, b: Dictionary) -> Dictionary:
	var kind := String(b.kind)
	var def: Dictionary = sim.building_def(kind)
	if kind == MainCapsule.KIND and sim.get("use_main_capsule") == true and not (sim.get("main_capsule") as Dictionary).is_empty():
		return _inspect_capsule(sim)
	var title: String = String(def.get("name", CatalogDefs.building_label(kind)))
	var lines: Array = ["❤ %d/%d" % [int(ceil(float(b.hp))), int(float(def.get("hp", 50.0)))]]
	var blurb := Fmt.building_blurb(kind, def, int(SimScript.EMITTER_RADIUS))
	if blurb != "":
		lines.append(blurb)
	if bool(def.get("grow", false)):
		var crop := String(b.get("crop", ""))
		lines.append("🌱 %s · ріст %d%%" % [CatalogDefs.res_label(crop) if crop != "" else "мішана",
			int(round(clampf(float(b.get("growth", 0.0)), 0.0, 1.0) * 100.0))])
	if int(def.get("ammo_max", 0)) > 0:
		lines.append("🔫 набої %d/%d" % [int(b.get("ammo", 0)), int(def.ammo_max)])
	if b.has("fuel"):
		lines.append("⛽ пальне %d" % int(b.fuel))
	if not bool(sim.device_active(b)):
		lines.append("🔌 без живлення — не працює")
	var hint := "ПКМ — розібрати (повертає ½ ціни)"
	if kind == "storage" and _count_kind(sim, "storage") <= 1:
		hint = "єдиний склад — не розібрати"
	elif bool(def.get("grow", false)):
		hint = "ЛКМ — змінити культуру · " + hint
	return {"shown": true, "state": &"info", "title": title, "lines": lines, "hint": hint}

static func _inspect_ground(sim, t: Vector2i, cell: int) -> Dictionary:
	var tile: int = int(sim.map.tiles[cell])
	var name: String = Fmt.terrain_title(String(WorldGen.TERRAIN_NAME[tile]) if tile < WorldGen.TERRAIN_NAME.size() else "")
	var indoor: bool = bool(sim.is_indoor(t.x, t.y))
	var tc: float = float(sim.temp_at(t.x, t.y))
	var lines: Array = ["🌡 %s %s" % [Fmt.temp(tc), "· 🏠 у приміщенні" if indoor else "· надворі"]]
	var light: float = float(sim.light_at(t.x, t.y))
	lines.append(("🌙 темно — робота повільніша" if light < float(SimScript.DARK_LIGHT_THRESHOLD) else "💡 світло %d%%" % int(round(light * 100.0))))
	var blocked: bool = WorldGen.is_terrain_blocked(tile)
	return {"shown": true, "state": &"info", "title": name, "lines": lines,
		"hint": "непрохідно" if blocked else "ЛКМ — іти сюди"}

# the hover ghost is DRAWN only while the pointer is over the map (world_view): then it is the target frame, the marker steps aside (REQ-0014-6)
static func _hover_in_map(sim, ctx: Dictionary) -> bool:
	var h: Variant = ctx.get("hover", Vector2i(-9999, -9999))
	return h is Vector2i and sim._in((h as Vector2i).x, (h as Vector2i).y)

static func _inspect_ghost(sim, kind: String, t: Vector2i, cell: int) -> Dictionary:
	var def: Dictionary = sim.building_def(kind)
	if def.is_empty():
		return INSPECT_HIDDEN
	var cost: Dictionary = def.get("cost", {})
	var lines: Array = ["ціна: %s" % GameData.cost_str(cost) if not bool(sim.get("use_catalog") == true) else "ціна: %s" % _catalog_cost(sim, cost)]
	var blurb := Fmt.building_blurb(kind, def, int(SimScript.EMITTER_RADIUS))
	if blurb != "":
		lines.append(blurb)
	var why := _ghost_refusal(sim, kind, def, t, cell)
	lines.append(("✖ " + why) if why != "" else "✔ можна ставити")
	var hint := "ЛКМ — поставити · ПКМ/Esc — скасувати"
	if WorldInputScript.WorldInput.paintable(kind, def):
		hint = "ЛКМ — поставити (затисни й веди — ряд) · ПКМ/Esc — скасувати"
	return {"shown": true, "state": (&"crit" if why != "" else &"good"), "title": "🏗 " + String(def.get("name", kind)),
		"lines": lines, "hint": hint}

# The FIRST reason a ghost cannot land here ("" == it can) — the same order try_build checks, so the
# tooltip predicts the click exactly instead of a generic «тут не можна».
static func _ghost_refusal(sim, kind: String, def: Dictionary, t: Vector2i, cell: int) -> String:
	var tile: int = int(sim.map.tiles[cell])
	if tile == WorldGen.WATER:
		return "вода — тут не збудуєш"
	if tile == WorldGen.ROCK:
		return "скеля — тут не збудуєш"
	if sim.bgrid.has(cell):
		return "зайнято: %s" % String(sim.building_def(String(sim.bgrid[cell].kind)).get("name", "будівля"))
	if sim.map.nodes.has(cell):
		return "тут ресурс — спершу добудь його"
	if sim.has_method("_kind_refusal"):   # the same per-kind refusal try_build raises (e.g. «Тут стоїть герой») — the ghost must not promise what the click refuses
		var kr := String(sim._kind_refusal(def, t.x, t.y))
		if kr != "":
			return kr.rstrip(".")
	if not bool(sim.research_ok(def)):
		var need := String(def.get("research", ""))
		return "🔒 потрібне дослідження: %s" % String(GameData.RESEARCH_LABEL.get(need, CatalogDefs.research_label(need)))
	if sim.get("use_inventory") == true:   # spec 0009: you place what you CARRY — the stock is not the question
		if int(InventoryMod.count(sim, InventoryMod.BLD + kind)) <= 0:
			return "нема в рюкзаку — скрафти (🎒 Tab)"
	elif not bool(sim.afford(def.get("cost", {}))):
		var have: Dictionary = {}
		for k in def.cost:
			have[k] = int(sim.res_amount(k))
		var miss: Dictionary = Fmt.shortfall(def.cost, have)
		return "бракує: %s" % (GameData.cost_str(miss) if not bool(sim.get("use_catalog") == true) else _catalog_cost(sim, miss))
	if not sim.build_valid(t.x, t.y):
		return "тут не можна будувати"
	return ""

static func _catalog_cost(_sim, cost: Dictionary) -> String:
	var parts: Array = []
	for k in cost:
		parts.append("%s%d" % [CatalogDefs.res_icon(str(k)), int(cost[k])])
	return " ".join(parts)

static func _count_kind(sim, kind: String) -> int:
	var c := 0
	for b in sim.buildings:
		if String(b.kind) == kind:
			c += 1
	return c

# --- nearby (RealGPS presence, spec 0013; session-owned, {available:false} on fakes / before the first tick) ---
static func _nearby_slice(session) -> Dictionary:
	if session == null or not session.has_method("nearby_view"):
		return {"available": false}
	return session.nearby_view()

# --- goals (onboarding tracker, session-owned; {available:false} on fakes / before a session) ---
static func _goals_slice(session) -> Dictionary:
	if session == null or not session.has_method("goals_view"):
		return {"available": false}
	return session.goals_view()

# --- death (the death screen's value data: cause + how long this pawn lived) ---
static func _death_slice(sim) -> Dictionary:
	var inv_on: bool = sim.get("use_inventory") == true
	var bag: int = _death_bag_items(sim) if inv_on else 0
	var ld: Variant = sim.get("last_death")
	if not (ld is Dictionary) or (ld as Dictionary).is_empty():
		return _death_capsule(sim, {"cause": "", "day": int(sim.time.day), "lived": 0, "inventory": inv_on, "bag_items": bag})
	var d: Dictionary = ld
	var out: Dictionary = {"cause": String(d.get("cause", "")), "day": int(d.get("day", 0)),
		"lived": maxi(0, int(d.get("day", 0)) - int(d.get("born", int(d.get("day", 0)))) + 1),
		"inventory": inv_on, "bag_items": bag}
	return _death_capsule(sim, out)

# spec 0010 REQ-0010-10: при ON слайс смерті несе capsule:true (екран смерті веде до капсули); ключ ЛИШЕ при ON — OFF-слайс як був.
static func _death_capsule(sim, out: Dictionary) -> Dictionary:
	if sim.get("use_main_capsule") == true:
		out["capsule"] = true
	return out

# spec 0009: the bag the pawn left where it fell (the newest multi-slot bag) — the death screen tells the truth about it
static func _death_bag_items(sim) -> int:
	var bags: Variant = sim.get("bags")
	if not (bags is Array) or (bags as Array).is_empty():
		return 0
	var n := 0
	for sl in ((bags as Array).back() as Dictionary).get("slots", []):
		n += int((sl as Dictionary).get("n", 0))
	return n
