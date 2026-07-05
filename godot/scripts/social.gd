# RealWorld — social.gd : four-tier social graph as a gameplay layer (spec 0002)
#
#     Player ─▶ Clan ─▶ Alliance ─▶ Empire
#
# Offline, "the colony = other live players", so new_graph() deterministically simulates a roster of
# other players/clans/alliances/empires from a seed. Diplomacy (ally/neutral/hostile) feeds the sim:
# raids are attributed to a hostile clan, friends send capsule invites, death respawns at the clan
# base. SEAM: new_graph() is the single injection point a real social backend would replace; its
# output shape IS the wire format — nothing downstream assumes the roster is simulated.
extends RefCounted

const CLAN_NAMES := ["Вовки", "Залізний Кулак", "Північна Зоря", "Багряні", "Степові Хорти",
	"Кремінь", "Чорний Ліс", "Соколи", "Варта", "Дикі Гуси"]
const ALLIANCE_NAMES := ["Пакт Дніпра", "Союз Заходу", "Коаліція Степу", "Ліга Вільних"]
const EMPIRE_NAMES := ["Імперія Тризуба", "Володіння Півночі", "Домінія Сходу"]
const PERSON_NAMES := ["Остап", "Мирослав", "Богдан", "Ярина", "Лада", "Тарас", "Влад", "Оксана",
	"Дмитро", "Соломія", "Ігор", "Марта", "Северин", "Зоряна"]
# Friend outposts are NOT hardcoded cities — "координати — це seed" means the social geography is a
# pure function of where you actually are. new_graph() places friends at seeded bearings/distances
# around the home coordinate, within the capsule radius, so invites are reachable from any spawn on
# Earth (Київ, Кіото, Рейк'явік…), not just Ukraine.
const OUTPOST_NAMES := ["Форпост", "Табір", "Стоянка", "Редут", "Застава", "Схрон", "Хутір", "Кряж"]
const CARDINALS := ["Пн", "Пн-Сх", "Сх", "Пд-Сх", "Пд", "Пд-Зх", "Зх", "Пн-Зх"]

# ---------------- construction ----------------
static func new_graph(player_name: String, seed_val: int, home_lat: float = 50.4501, home_lon: float = 30.5234) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var g := {
		"me": {"id": "you", "name": player_name, "clan": "clan_0"},
		"clans": {}, "alliances": {}, "empires": {}, "friends": [],
	}
	# my empire / my alliance / my clan
	var my_empire := "emp_0"
	var rival_empire := "emp_1"
	g.empires[my_empire] = {"id": my_empire, "name": _pick(EMPIRE_NAMES, 0), "alliances": ["ali_0"]}
	g.empires[rival_empire] = {"id": rival_empire, "name": _pick(EMPIRE_NAMES, 1), "alliances": ["ali_1"]}
	g.alliances["ali_0"] = {"id": "ali_0", "name": _pick(ALLIANCE_NAMES, 0), "empire": my_empire, "clans": []}
	g.alliances["ali_1"] = {"id": "ali_1", "name": _pick(ALLIANCE_NAMES, 1), "empire": rival_empire, "clans": []}
	# clan roster: clan_0 is me (allied), a couple allied clans, some hostiles, a neutral
	var specs := [
		{"alliance": "ali_0", "stance": "ally"},     # clan_0 = you
		{"alliance": "ali_0", "stance": "ally"},     # ally in my alliance
		{"alliance": "ali_0", "stance": "ally"},     # ally in my alliance
		{"alliance": "ali_1", "stance": "hostile"},  # rival empire
		{"alliance": "ali_1", "stance": "hostile"},  # rival empire
		{"alliance": "",      "stance": "neutral"},  # unaligned
	]
	for i in specs.size():
		var cid := "clan_%d" % i
		var members := []
		var mcount := 2 + rng.randi() % 3
		for _m in mcount:
			members.append(_pick(PERSON_NAMES, rng.randi() % PERSON_NAMES.size()))
		var nm: String = ("Твій клан «%s»" % _pick(CLAN_NAMES, i)) if i == 0 else ("Клан «%s»" % _pick(CLAN_NAMES, i))
		g.clans[cid] = {
			"id": cid, "name": nm, "members": members,
			"alliance": specs[i].alliance, "stance": ("ally" if i == 0 else specs[i].stance),
		}
		if specs[i].alliance != "":
			g.alliances[specs[i].alliance].clans.append(cid)
	# friends: allied players at seed-placed outposts around home, all within the capsule radius
	# (reachable), so the coordinate-derived capsule/social loop is coherent for ANY spawn point.
	var coslat: float = maxf(0.05, cos(deg_to_rad(home_lat)))
	for i in 4:
		var dist_km: float = 16.0 + rng.randf() * 76.0        # 16..92 km — inside the 100 km radius
		var bearing: float = rng.randf() * TAU                # 0 = north, clockwise
		var flat: float = snappedf(home_lat + (dist_km / 111.32) * cos(bearing), 0.0001)
		var flon: float = snappedf(home_lon + (dist_km / (111.32 * coslat)) * sin(bearing), 0.0001)
		g.friends.append({
			"id": "fr_%d" % i,
			"name": _pick(PERSON_NAMES, (i * 5 + 3) % PERSON_NAMES.size()),
			"clan": "clan_%d" % (1 + i % 2),   # allied clans
			"place": "%s %s" % [_pick(OUTPOST_NAMES, rng.randi() % OUTPOST_NAMES.size()), CARDINALS[int(round(bearing / TAU * 8.0)) % 8]],
			"lat": flat, "lon": flon,
		})
	return g

static func _pick(pool: Array, i: int) -> String:
	return pool[i % pool.size()]

# ---------------- diplomacy queries ----------------
static func my_clan(g: Dictionary) -> Dictionary:
	return g.clans[g.me.clan]

static func my_alliance(g: Dictionary) -> Dictionary:
	var a: String = my_clan(g).alliance
	return g.alliances.get(a, {})

static func my_empire(g: Dictionary) -> Dictionary:
	var al := my_alliance(g)
	if al.is_empty():
		return {}
	return g.empires.get(al.get("empire", ""), {})

static func stance_toward(g: Dictionary, clan_id: String) -> String:
	if not g.clans.has(clan_id):
		return "neutral"
	if clan_id == g.me.clan:
		return "ally"
	# same alliance or same empire => allied regardless of stored stance
	var mine := my_clan(g)
	var other: Dictionary = g.clans[clan_id]
	if mine.alliance != "" and mine.alliance == other.alliance:
		return "ally"
	var my_emp := my_empire(g)
	if not my_emp.is_empty():
		var other_ali: Dictionary = g.alliances.get(other.alliance, {})
		if not other_ali.is_empty() and other_ali.get("empire", "") == my_emp.id:
			return "ally"
	return other.stance

static func is_hostile(g: Dictionary, clan_id: String) -> bool:
	return stance_toward(g, clan_id) == "hostile"

static func hostiles(g: Dictionary) -> Array:
	var out := []
	for cid in g.clans:
		if is_hostile(g, cid):
			out.append(cid)
	return out

# More hostile clans => harder raids. 1.0 baseline, +0.12 per hostile clan.
static func raid_pressure(g: Dictionary) -> float:
	return 1.0 + 0.12 * hostiles(g).size()

# Deterministic pick of which hostile clan is behind a given raid wave.
static func raid_faction_name(g: Dictionary, wave: int) -> String:
	var hs := hostiles(g)
	if hs.is_empty():
		return "невідомі мародери"
	var cid: String = hs[wave % hs.size()]
	return g.clans[cid].name

# Build a capsule invite from friend #i (inviter, clan, target location).
static func friend_invite(g: Dictionary, i: int, radius_km: float) -> Dictionary:
	var fr = g.friends[i % g.friends.size()]
	return {
		"id": "inv_%s" % fr.id,
		"inviter": fr.name,
		"clan": g.clans.get(fr.clan, {}).get("name", "—"),
		"lat": fr.lat, "lon": fr.lon, "name": fr.place,
		"radius_km": radius_km, "allow_receive": true,
	}
