# RealWorld — sim/world_meta.gd : the WORLD-META domain of the live sim, extracted from the sim.gd
# monolith — everything that connects THIS region to the wider persistent world.
#
# Capsules & invites (spec 0002: the daily travel charge, reach checks, invite envelopes) and convoy
# logistics (dispatch/exchange/ambush/return between real-geography hubs). Static functions over the
# sim instance `s`: no state here, no sim.gd preload (no cycle) — sim.gd keeps delegating methods so
# session, panels (via the router) and tests keep the same sim API.
extends RefCounted

const GameData = preload("res://scripts/data.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const MainCapsule = preload("res://scripts/sim/capsule.gd")

# ---------------- capsules & invites (spec 0002) ----------------
static func grant_daily_capsule(s) -> void:
	if s.capsule.is_empty():
		s.capsule = s._default_capsule()
		return
	if int(s.time.day) != int(s.capsule.last_day):
		s.capsule.last_day = int(s.time.day)
		if int(s.capsule.charges) < GameData.CAPSULE_DAILY_CHARGES:
			s.capsule.charges = GameData.CAPSULE_DAILY_CHARGES
			s._log("🚀 Щоденна капсула готова (радіус %d км)." % int(s.capsule.radius_km), "good")

static func capsule_can_reach(s, lat: float, lon: float) -> Dictionary:
	var km := WorldGen.haversine_km(float(s.map.lat), float(s.map.lon), lat, lon)
	if int(s.capsule.get("charges", 0)) <= 0:
		return {"ok": false, "km": km, "msg": "Капсула вже використана — чекай нового дня."}
	if km > float(s.capsule.radius_km):
		return {"ok": false, "km": km, "msg": "Задалеко: %d км > ліміт %d км." % [int(km), int(s.capsule.radius_km)]}
	return {"ok": true, "km": km, "msg": "Готова до запуску (%d км)." % int(km)}

# Validate + consume a charge. Returns a travel intent for the session (main.travel_to).
static func try_launch_capsule(s, lat: float, lon: float, place_name: String) -> Dictionary:
	if s.get("use_main_capsule") == true:   # REQ-0010-41: при ON щоденного запуску нема (запуск = лише OFF)
		return {"ok": false, "msg": MainCapsule.MSG_NO_TRAVEL}
	var chk := capsule_can_reach(s, lat, lon)
	if not chk.ok:
		return {"ok": false, "msg": chk.msg}
	s.capsule.charges = int(s.capsule.charges) - 1
	s._log("🚀 Капсула запущена → %s (%d км)." % [place_name, int(chk.km)], "good")
	return {"ok": true, "lat": lat, "lon": lon, "name": place_name, "km": chk.km}

# `quiet`: the caller announces a batch itself (the landing summarises its seeded invites in one line
# instead of three feed cards burying the cold-start hint).
static func add_invite(s, inv: Dictionary, quiet: bool = false) -> void:
	for e in s.invites:
		if e.id == inv.id:
			return
	s.invites.append(inv)
	if not quiet:
		s._log("✉ Інвайт від %s (%s) → %s." % [inv.get("inviter", "?"), inv.get("clan", "—"), inv.get("name", "?")])

static func accept_invite(s, id: String) -> Dictionary:
	var inv: Variant = null
	for e in s.invites:
		if e.id == id:
			inv = e
			break
	if inv == null:
		return {"ok": false, "msg": "Інвайт не знайдено."}
	if not bool(inv.get("allow_receive", false)):
		return {"ok": false, "msg": "Інвайт не дозволяє прийом капсули."}
	var res := try_launch_capsule(s, float(inv.lat), float(inv.lon), str(inv.name))
	if res.ok:
		s.invites.erase(inv)
	return res

# ---------------- logistics ----------------
static func dispatch_convoy(s, hub_index: int, send_res: String, send_amt: int) -> Dictionary:
	if hub_index <= 0 or hub_index >= s.regions.size():
		return {"ok": false, "msg": "Невірний пункт."}
	var hub: Dictionary = s.regions[hub_index]
	if hub.get("home", false):
		return {"ok": false, "msg": "Невірний пункт."}
	send_amt = max(1, int(send_amt))
	if s.res_amount(send_res) < send_amt:
		return {"ok": false, "msg": "Недостатньо ресурсу на складі."}
	if send_res != hub.offer.buys:
		return {"ok": false, "msg": "%s приймає лише %s." % [hub.name, GameData.RES[hub.offer.buys].label]}
	s.stock[s.res_key(send_res)] -= send_amt
	var recv_res: String = hub.offer.sells
	var recv_amt: int = max(1, int(send_amt / int(hub.offer.rate)))
	var dist := WorldGen.haversine_km(s.regions[0].lat, s.regions[0].lon, hub.lat, hub.lon)
	var one_way := clampf(dist * 0.045, 7, 55)
	s.convoy_seq += 1
	s.convoys.append({
		"id": s.convoy_seq, "hub_index": hub_index, "hub_name": hub.name,
		"send_res": send_res, "send_amt": send_amt, "recv_res": recv_res, "recv_amt": recv_amt,
		"phase": "out", "t": 0.0, "dur": one_way, "dist": int(dist), "ambushed": false,
	})
	s._log("🚚 Конвой #%d вирушив до %s (%d км)." % [s.convoy_seq, hub.name, int(dist)], "good")
	return {"ok": true}

static func update_convoys(s, dt: float) -> void:
	for k in range(s.convoys.size() - 1, -1, -1):
		var c: Dictionary = s.convoys[k]
		c.t += dt
		if c.t < c.dur:
			continue
		if c.phase == "out":
			c.phase = "back"
			c.t = 0.0
			s._log("🔄 Конвой #%d обміняв вантаж у %s." % [c.id, c.hub_name])
			if s.threat_rng.randf() < 0.25:
				c.ambushed = true
				var lost: int = max(1, int(round(c.recv_amt * (0.3 + s.threat_rng.randf() * 0.4))))
				c.recv_amt = max(0, c.recv_amt - lost)
				s._log("⚔ Засідка на конвой #%d! −%d." % [c.id, lost], "bad")
		else:
			s.deposit(c.recv_res, c.recv_amt)
			s._log("📦 Конвой #%d повернувся: +%d %s." % [c.id, c.recv_amt, GameData.RES[c.recv_res].icon], "good")
			s.convoys.remove_at(k)
