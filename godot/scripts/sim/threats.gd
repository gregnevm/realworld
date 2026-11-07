# RealWorld — sim/threats.gd : the THREAT domain of the live sim, extracted from the sim.gd monolith.
#
# Raids (clan pressure, waves, storage looting), patrol robots (лор: автоматика Старого світу —
# амбієнтний канал загрози поза рейд-циклом), shared enemy brain, turrets, death/permadeath-respawn.
# Static functions over the sim instance `s`: the module holds NO state (all state stays on sim.gd)
# and never preloads sim.gd (no preload cycle). sim.gd keeps one-line delegates, so every caller —
# session, tests, the frozen main.gd — sees the same sim API as before the split.
#
# Determinism contract: every roll here draws from s.threat_rng (its own seeded stream, salted apart
# from the weather stream) — the raid/patrol/loot history of a region replays from its coordinates.
extends RefCounted

const GameData = preload("res://scripts/data.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const Social = preload("res://scripts/social.gd")
const HeroHealth = preload("res://scripts/sim/hero_health.gd")
const MainCapsule = preload("res://scripts/sim/capsule.gd")

# ---------------- raids ----------------
static func update_raids(s, dt: float) -> void:
	if MainCapsule.holds_npc_threats(s):
		return   # ON (spec 0010): рейд на капсулу веде автомат MainCapsule.update (W3a), легасі-цикл не армується
	var r: Dictionary = s.raid
	if r.active:
		# рейд завершено, коли не лишилось РЕЙДЕРІВ: патрульний робот (kind "bot") живе в тому ж
		# enemies-масиві, але це амбієнтний канал — він не має тримати банер/цикл рейду вічно
		var raiders_left := false
		for e in s.enemies:
			if String(e.get("kind", "raider")) != "bot":
				raiders_left = true
				break
		if not raiders_left:
			r.active = false
			r.warned = false
			# the DIRECTOR owns the next raid now (sim/director.gd MTB roll) — the cycle idles
			r.next = s.RAID_IDLE
			r.timer = 0.0
			s.banner = ""
			s._log("✅ Рейд відбито!", "good")
		return
	r.timer += dt
	if not r.warned and r.timer > r.next - 12.0:
		r.warned = true
		s.banner = "⚠ НАБЛИЖАЄТЬСЯ РЕЙД"
		s._log("⚠ Рейдери на підході — укріплюй базу!", "warn")
	if r.timer >= r.next:
		spawn_wave(s)

static func spawn_wave(s) -> void:
	var r: Dictionary = s.raid
	r.active = true
	r.wave += 1
	# diplomacy: hostile clans raid harder; allied/empire clans never do (spec 0002)
	var pressure := 1.0
	var faction := "невідомі мародери"
	if s.social != null:
		pressure = Social.raid_pressure(s.social)
		faction = Social.raid_faction_name(s.social, r.wave)
	# a director-armed raid carries its Balance payload: the wave is sized by THREAT POINTS (wealth +
	# days + clan pressure through assess()) — the escalation the flat day-formula never had. A wave
	# forced without the director (tests/smoke lowering `next`) keeps the legacy day formula.
	var cnt: int
	if r.has("director"):
		cnt = clampi(int(r.director.get("count", 1)), 1, 20)
		faction = str(r.director.get("faction", faction))
		r.erase("director")
	else:
		cnt = clampi(int(ceil(float(GameData.raid_wave_size(s.time.day)) * pressure)), 1, 20)
	var edge: int = s.threat_rng.randi() % 4
	var placed := 0
	var guard := 0
	while placed < cnt and guard < 500:
		guard += 1
		var c := edge_cell(s, edge)
		if WorldGen.is_terrain_blocked(s.map.tiles[c.y * s.n + c.x]):
			continue
		s.enemies.append(GameData.make_raider(c.x + 0.5, c.y + 0.5, s.time.day))
		placed += 1
	s.banner = "⚔ РЕЙД! %d рейдерів — %s" % [cnt, faction]
	s._log("⚔ Рейд #%d: %d рейдерів (%s) атакують базу!" % [r.wave, cnt, faction], "bad")

# A random cell hugging the given map edge (shared by raids and robot patrols; threat_rng stream).
static func edge_cell(s, edge: int, rng: RandomNumberGenerator = null) -> Vector2i:
	var r: RandomNumberGenerator = rng if rng != null else s.threat_rng   # капсульний рейд тягне зі СВОГО потоку (REQ-0010-34); решта — threat_rng як раніше
	var x := 0
	var y := 0
	var o: int = 1 + r.randi() % 3
	match edge:
		0:
			x = o
			y = 2 + r.randi() % (s.n - 4)
		1:
			x = s.n - 1 - o
			y = 2 + r.randi() % (s.n - 4)
		2:
			x = 2 + r.randi() % (s.n - 4)
			y = o
		_:
			x = 2 + r.randi() % (s.n - 4)
			y = s.n - 1 - o
	return Vector2i(x, y)

# ---------------- patrol robots (лор: автоматика Старого світу) ----------------
# Постапокаліпсис: зрідка регіон перетинає патруль роботів — амбієнтна загроза поза рейд-циклом
# (без банера й ескалації хвиль). Бойовка тут — спеція, не основна страва: вікно ~2.8–4.8 ігрових
# діб тримає компонентний дріп живим, не перетворюючи гру на тир. Той самий seeded threat-потік.
static func update_patrols(s, dt: float) -> void:
	var pt: Dictionary = s.patrol
	pt.timer += dt
	if pt.timer < pt.next:
		return
	pt.timer = 0.0
	pt.next = 420.0 + s.threat_rng.randf() * 300.0
	if s.raid.active:
		return   # одна битва за раз: під час рейду патруль не накладаємо
	if MainCapsule.holds_npc_threats(s):
		return   # ON (critique-0010 #2): роботи, що довбуть неруйнівну капсулу, — до вимірювання/рішення власника; кидок RNG вище лишився
	spawn_patrol(s)

static func spawn_patrol(s) -> void:
	var pt: Dictionary = s.patrol
	pt.wave += 1
	var cnt: int = GameData.patrol_size(s.time.day)
	var edge: int = s.threat_rng.randi() % 4
	var placed := 0
	var guard := 0
	while placed < cnt and guard < 200:
		guard += 1
		var c := edge_cell(s, edge)
		if WorldGen.is_terrain_blocked(s.map.tiles[c.y * s.n + c.x]):
			continue
		s.enemies.append(GameData.make_patrol_bot(c.x + 0.5, c.y + 0.5, s.time.day))
		placed += 1
	if placed > 0:
		s._log("🤖 Патруль роботів увійшов у регіон: %d од. Розібрані роботи дають компоненти." % placed, "warn")

# ---------------- shared enemy brain + turrets ----------------
static func update_enemies(s, dt: float) -> void:
	var p: Dictionary = s.player
	var center: Vector2i = s.base_center()
	for k in range(s.enemies.size() - 1, -1, -1):
		var e: Dictionary = s.enemies[k]
		var destroyer := "роботом" if String(e.get("kind", "raider")) == "bot" else "рейдерами"
		e.atk_cd = max(0.0, e.atk_cd - dt)
		e.hit_flash = max(0.0, e.hit_flash - dt)
		# пастки: ціна проходу для ворога — data-capability `trap_dps` (data.gd), не hard-coded kind:
		# будь-яка майбутня будівля з trap_dps ранить воїв без правки цього мозку (як blocks/extra.heat)
		var ti: int = int(e.py) * s.n + int(e.px)
		if s.bgrid.has(ti):
			var trap_dps := float(s.building_def(String(s.bgrid[ti].kind)).get("trap_dps", 0.0))
			if trap_dps > 0.0:
				damage_enemy(s, e, trap_dps * dt)
				damage_building(s, s.bgrid[ti], 4.0 * dt, false, "")
				if e.dead:
					continue
		var step: float = e.speed * dt
		var dtp: float = s._dist(e.px, e.py, p.px, p.py)
		if dtp < 1.25:
			e.face = atan2(p.py - e.py, p.px - e.px)
			if e.atk_cd <= 0:
				# armor cuts the blow, then it lands as a LOCATED injury (sim/hero_health.gd picks
				# the body part off the same threat stream; a smashed vital part is death right there)
				HeroHealth.damage(s, e.dmg * s.armor_mult(), "удар робота" if String(e.get("kind", "raider")) == "bot" else "удар рейдера")
				e.atk_cd = 1.1
			continue
		var st: Variant = null
		for b in s.buildings:
			if b.kind == "storage" and s._dist(e.px, e.py, b.x + 0.5, b.y + 0.5) < 1.35:
				st = b
				break
		if st != null:
			if e.atk_cd <= 0:
				damage_building(s, st, e.dmg, true, destroyer)
				e.atk_cd = 1.0
			continue
		var tx: int = int(p.px) if dtp < 6 else center.x
		var ty: int = int(p.py) if dtp < 6 else center.y
		e.path_cd -= dt
		if e.path.is_empty() or e.path_cd <= 0 or e.tx != tx or e.ty != ty:
			e.tx = tx
			e.ty = ty
			e.path_cd = 0.9 + s.threat_rng.randf() * 0.5
			e.path = s._terrain_path(int(e.px), int(e.py), tx, ty)
		if not e.path.is_empty():
			var nx: Vector2i = e.path[0]
			var bi: int = nx.y * s.n + nx.x
			if s.bgrid.has(bi) and s.building_def(String(s.bgrid[bi].kind)).get("blocks", false):
				e.face = atan2(nx.y + 0.5 - e.py, nx.x + 0.5 - e.px)
				if e.atk_cd <= 0:
					damage_building(s, s.bgrid[bi], e.dmg, false, destroyer)
					e.atk_cd = 1.0
			else:
				if s._step_to(e, nx.x + 0.5, nx.y + 0.5, step):
					e.path.remove_at(0)
		else:
			s._step_to(e, center.x + 0.5, center.y + 0.5, step)

# Data-capability turret brain (the trap_dps pattern): ANY building whose def carries a range fires —
# data.gd's turret via {range, dps} (shot = dps×0.5 every 0.5s, exactly as shipped), catalogue turrets
# via {range, shot_dmg, shot_cool}. A def with `ammo_max` FIRES STOCK AMMO: it reloads one round per
# tick from the open stock and holds fire dry — the ammo chain (gunpowder -> ammo) has a real gun.
# Adding a turret def never edits this brain.
static func update_turrets(s, dt: float) -> void:
	for b in s.buildings:
		var def: Dictionary = s.building_def(String(b.kind))
		var reach := float(def.get("range", 0.0))
		if reach <= 0.0:
			continue
		if not s.device_active(b):
			continue   # a browned-out powered turret holds fire (Batch 8c)
		var ammo_max := int(def.get("ammo_max", 0))
		if ammo_max > 0 and int(b.get("ammo", 0)) < ammo_max and s.res_amount("ammo") >= 1:
			s.stock[s.res_key("ammo")] -= 1
			b["ammo"] = int(b.get("ammo", 0)) + 1
		b.cool = max(0.0, b.cool - dt)
		var e: Variant = s._nearest_enemy(b.x + 0.5, b.y + 0.5, reach)
		if e == null:
			continue
		b.aim = atan2(e.py - (b.y + 0.5), e.px - (b.x + 0.5))
		if b.cool <= 0:
			if ammo_max > 0:
				if int(b.get("ammo", 0)) < 1:
					continue   # dry magazine: the reload line above will feed it when stock has ammo
				b["ammo"] = int(b.get("ammo", 0)) - 1
				if int(b.ammo) == 0 and s.res_amount("ammo") == 0:
					s._log("🔫 %s: набої скінчились." % str(def.get("name", b.kind)), "warn")
			b.cool = 0.5 if def.has("dps") else float(def.get("shot_cool", 1.0))
			damage_enemy(s, e, float(def.dps) * 0.5 if def.has("dps") else float(def.get("shot_dmg", 0.0)))
			s.shots.append({"x1": b.x + 0.5, "y1": b.y + 0.5, "x2": e.px, "y2": e.py, "t": 0.12})

# ---------------- damage + death ----------------
# destroyer: хто зніс будівлю — для чесного фіда ("рейдерами"/"роботом"); "" = самозношення пастки.
static func damage_building(s, b, amt: float, steal: bool, destroyer: String = "рейдерами") -> void:
	if bool(s.building_def(String(b.kind)).get("indestructible", false)):
		MainCapsule.on_hit(s, amt)   # Основна капсула (spec 0010): без HP-до-видалення й без крадіжки складу; удар знижує HP ядра (лише в контакті рейду)
		return
	b.hp -= amt
	if steal and b.kind == "storage":
		var keys := []
		for kk in GameData.RES_ORDER:
			if s.res_amount(kk) > 0:
				keys.append(kk)
		if not keys.is_empty():
			var kk: String = keys[s.threat_rng.randi() % keys.size()]
			var lost: int = min(s.res_amount(kk), 1 + s.threat_rng.randi() % 2)
			s.stock[s.res_key(kk)] -= lost
	if b.hp <= 0:
		s._remove_building(b)
		var bname: String = str(s.building_def(String(b.kind)).get("name", b.kind))
		if destroyer == "":
			s._log("💥 %s зносилися від спрацьовувань." % bname, "bad")
		else:
			s._log("💥 %s зруйновано %s." % [bname, destroyer], "bad")

static func damage_enemy(s, e, amt: float) -> void:
	e.hp -= amt
	e.hit_flash = 0.12
	if e.hp <= 0 and not e.dead:
		e.dead = true
		s.enemies.erase(e)
		if String(e.get("kind", "raider")) == "bot":
			# розібраний робот: щедрий брухт + шанс на вцілілу електроніку; їжі в машини немає
			s.deposit("scrap", 3 + s.threat_rng.randi() % 2)
			if s.threat_rng.randf() < 0.6:
				s.deposit("components", 1)
		else:
			s.deposit("scrap", 2 + s.threat_rng.randi() % 2)
			if s.threat_rng.randf() < 0.25:
				s.deposit("components", 1)
			if s.threat_rng.randf() < 0.4:
				s.deposit("food", 1)

static func on_death(s) -> void:
	if s.get("use_inventory") == true:
		s._inv_drop_bag()   # spec 0009: the backpack stays where the pawn fell, as a bag
	s.dead = true
	s.banner = ""
	if s.get("use_main_capsule") == true:
		s._log(MainCapsule.MSG_DEATH, "bad")   # ON (REQ-0010-10): «з'явишся біля капсули», а не «новий виживальник у поселенні»
	elif s.get("use_inventory") == true:
		s._log("☠ Загибель. Торба лишилась на місці — новий виживальник може її забрати.", "bad")
	else:
		s._log("☠ Загибель. Усе, що було при собі, втрачено.", "bad")

# Permadeath (spec 0002): the pawn is gone entirely — skills, carried loot and items reset.
# You get a fresh un-leveled rookie at the clan base; the settlement (buildings + stock) persists.
static func respawn_new_pawn(s, anchor: Dictionary = {}) -> void:
	if MainCapsule.respawn(s, anchor):
		return   # ON (spec 0010): тіло з шва respawn_source, місце — landing біля капсули; ворогів/рейд не чіпаємо (REQ-0010-63)
	var sp: Vector2i = s.base_center()
	var open: Vector2i = s._nearest_free(s.astar, sp)
	if open == Vector2i(-1, -1):
		open = s.map.spawn
	s.player = s._default_player(open)
	if s.get("use_inventory") == true:
		s.player.inv = s._inv_empty()      # the rookie arrives empty-handed: the bag and the storage hold the rest
		s.player.hand = 0
	HeroHealth.reset(s)   # the rookie arrives in an unscarred body
	s.enemies = []
	s.raid.active = false
	s.raid.warned = false
	s.raid.timer = 0.0
	s.banner = ""
	s.dead = false
	s._log("Новий виживальник прибув у поселення — навички з нуля.", "warn")
