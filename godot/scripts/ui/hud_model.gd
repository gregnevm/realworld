# RealWorld — ui/hud_model.gd : the ViewModel (spec 0005 §2.5). The `Balance.assess()` analogue.
#
# PURE + Node-free: never extends Node, never calls get_node/queue_redraw/Color/add_child. It is the
# SINGLE place that reaches through session.sim, building one immutable presentation Dictionary per
# frame from read/derived surfaces only. It maps raw fields to ENUMS itself (R11) and holds only value
# data — ids, enums (StringName), numbers, Strings — never a live sim.player / enemy ref / Callable (R8).
extends RefCounted
const Fmt = preload("res://scripts/ui/format.gd")
const GameData = preload("res://scripts/data.gd")

# session: the SessionScript (has .sim). world/ctx: the same shapes the kernel consumes (built by HudRoot).
# balance: a Balance director constructed ONCE by HudRoot and reused (never new() per frame).
static func snapshot(session, world: Dictionary, ctx: Dictionary, balance) -> Dictionary:
	if session == null or session.sim == null:
		return {"alive": false}
	var sim = session.sim
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
	}

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

# --- stock (rows in RES_ORDER; total computed purely; cap from the sim) ---
static func _stock_slice(sim) -> Dictionary:
	var stock: Dictionary = sim.stock
	var rows := {}
	var total := 0
	for res in GameData.RES_ORDER:
		var amt: int = int(stock.get(res, 0))
		rows[res] = amt
		total += amt
	return {"rows": rows, "total": total, "cap": int(sim.storage_cap())}

# --- build palette (afford flag per building; locked reserved for the future research gate) ---
static func _build_slice(sim) -> Dictionary:
	var slots := []
	for key in GameData.BUILD_ORDER:
		var def: Dictionary = GameData.BUILDINGS[key]
		slots.append({
			"key": key,
			"name": String(def.name),
			"afford": GameData.can_afford(sim.stock, def.cost),
			"locked": false,
		})
	return {"slots": slots}

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

# --- raid (state enum for the banner; no live enemy refs — R8) ---
static func _raid_slice(sim) -> Dictionary:
	var r: Dictionary = sim.raid
	var state: StringName = &"none"
	if bool(r.get("active", false)):
		state = &"active"
	elif bool(r.get("warned", false)):
		state = &"incoming"
	return {"state": state, "wave": int(r.get("wave", 0)), "count": (sim.enemies as Array).size()}
