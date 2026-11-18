# RealWorld — tests/run_states_tests.gd : spec 0012 REQ-0012-71 — стани героя при save → «Продовжити» з догоном (без нападів, REQ-84).
# По рядку на стан: downed, кровотеча, смерть із торбою на місці смерті (+25 год ⇒ торба протермінована, шов bag_expired рівно раз),
# герой поза капсулою (тимчасова/транспортна капсули в К1 недосяжні за ON — OD-114, див. маніфест 1.01).
# Run: godot --headless --path godot -s res://tests/run_states_tests.gd
extends "res://tests/harness.gd"

const SessionScript = preload("res://scripts/session.gd")
const InvMod = preload("res://scripts/sim/inventory.gd")
const HeroHealth = preload("res://scripts/sim/hero_health.gd")
const Persistence = preload("res://scripts/persistence.gd")
const ToolWear = preload("res://scripts/sim/tool_wear.gd")
const Pacing = preload("res://scripts/pacing.gd")
const Sim = preload("res://scripts/sim.gd")
const WorldGen = preload("res://scripts/world_gen.gd")

const T0 := 1800000000000   # 2027-01-15 (UTC-мс)
const H := 3600000
const PATH := "user://states_test.json"


func _init() -> void:
	print("== RealWorld states save->catch-up tests (REQ-0012-71) ==")
	_t_downed()
	_t_bleeding()
	_t_death_bag()
	_t_tool_wear_unit()
	_t_tool_wear_in_gather()
	_t_ftue_first_action()
	finish()


func _session() -> Variant:
	var s: Variant = SessionScript.new()
	s.use_inventory = true
	s.use_catalog = true
	s.use_main_capsule = true
	s.use_realtime = true
	s.autosave = false
	s.start(50.4501, 30.5234, "Київ", T0)
	return s


func _restore(now: int) -> Variant:
	var r: Variant = SessionScript.new()
	r.autosave = false
	if not r.restore_game(PATH, now):
		return null
	return r


func _cleanup() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


# REQ-0012-71 «downed»: непритомний герой зберігається, а після 6 год офлайну без нападів не вбитий і не розкрадений; повтор того самого входу — той самий стан
func _t_downed() -> void:
	var s: Variant = _session()
	HeroHealth.ensure(s.sim)
	s.sim.health.downed = true
	ok(s.sim.hero_downed(), "downed: передумова — герой непритомний")
	ok(s.save_game(PATH), "downed: сейв записано")
	var a: Variant = _restore(T0 + 6 * H)
	var b: Variant = _restore(T0 + 6 * H)
	ok(a != null and b != null, "downed: сейв відновлюється")
	if a == null or b == null:
		_cleanup()
		return
	ok(int(a.last_catch_up.attacks) == 0 and not bool(a.sim.dead), "downed: догін 6 год — 0 нападів, герой живий")
	ok(Persistence.world_hash(a.sim) == Persistence.world_hash(b.sim), "downed: той самий сейв і now ⇒ той самий world_hash")
	_cleanup()


# REQ-0012-71 «кровотеча»: поранення з кровотечею переживає save; догін детермінований і не нараховує нападів
func _t_bleeding() -> void:
	var s: Variant = _session()
	HeroHealth.ensure(s.sim)
	HeroHealth.damage(s.sim, 6.0, "тест")
	var bleed0: float = float(s.sim.health.total_bleed())
	ok(bleed0 > 0.0, "bleeding: передумова — рана кровоточить (%.3f)" % bleed0)
	ok(s.save_game(PATH), "bleeding: сейв записано")
	var a: Variant = _restore(T0 + 3 * H)
	var b: Variant = _restore(T0 + 3 * H)
	ok(a != null and b != null, "bleeding: сейв відновлюється")
	if a == null or b == null:
		_cleanup()
		return
	ok(int(a.last_catch_up.attacks) == 0, "bleeding: догін 3 год — 0 нападів")
	ok(Persistence.world_hash(a.sim) == Persistence.world_hash(b.sim), "bleeding: той самий сейв і now ⇒ той самий world_hash")
	_cleanup()


# REQ-0012-71 «смерть із торбою»: торба лишається з TTL 24 год (UTC-мс); save → догін +25 год ⇒ торба протермінована,
# шов bag_expired викликано рівно один раз; ліміт догону (24 год) TTL не подовжує
func _t_death_bag() -> void:
	var s: Variant = _session()
	InvMod.add(s.sim, "wood", 3)
	InvMod.drop_bag(s.sim)
	ok(not (s.sim.bags as Array).is_empty() and int((s.sim.bags[0] as Dictionary).get("expires_at", 0)) == T0 + 24 * H, "bag: торбу залишено, expires_at = смерть + 24 год")
	ok(s.save_game(PATH), "bag: сейв записано")
	var calls: Array = []
	InvMod.expired_sink = func(items: Array, pos: Vector2i) -> void: calls.append([items.size(), pos])
	var a: Variant = _restore(T0 + 25 * H)
	ok(a != null and not (a.sim.bags as Array).is_empty(), "bag: після відновлення торба ще лежить (протерміновується на тіку, не в догоні)")
	if a != null:
		a.sim.update(0.1)
		InvMod.pickup_bags(a.sim, {"px": -50.0, "py": -50.0})
		InvMod.pickup_bags(a.sim, {"px": -50.0, "py": -50.0})
	InvMod.expired_sink = Callable()
	ok(calls.size() == 1 and a != null and (a.sim.bags as Array).is_empty(), "bag: +25 год ⇒ торба зникла, bag_expired викликано рівно один раз (%d)" % calls.size())
	_cleanup()


func _wear_sim(on: bool) -> Variant:
	var s: Variant = Sim.new()
	s.use_realtime = on
	s.set_clock(T0)
	s.new_game(WorldGen.generate_map(50.4501, 30.5234, 56), false)
	s.player.items.append("axe")
	s.player.equipped["tool"] = "axe"
	return s


# REQ-0012-89: темп — Pacing.tool_wear_t1 секунд активної роботи; зламаний інструмент зникає; ключ зносу з'являється лише ON
func _t_tool_wear_unit() -> void:
	var limit: float = Pacing.seconds("tool_wear_t1")
	ok(is_equal_approx(limit, 18000.0), "REQ-0012-89: ліміт зносу — 18 000 с активної роботи (~5 год)")
	ok(ToolWear.is_tier1("axe") and ToolWear.is_tier1("pick") and not ToolWear.is_tier1("sledge") and not ToolWear.is_tier1("club"), "REQ-0012-89: перший тір — сокира й кайло; кувалда (дослідження) і зброя не зношуються")
	var s: Variant = _wear_sim(true)
	ok(not ToolWear.tick(s, limit * 0.5) and is_equal_approx(ToolWear.wear_fraction(s, "axe"), 0.5), "REQ-0012-89: половина часу — половина зносу, інструмент цілий")
	ok(not ToolWear.tick(s, limit * 0.45) and s.player.items.has("axe"), "REQ-0012-89: 95 % — ще цілий (попередження в логу)")
	ok(ToolWear.tick(s, limit * 0.05 + 1.0), "REQ-0012-89: >= ліміту — інструмент ламається")
	ok(not s.player.items.has("axe") and String(s.player.equipped.get("tool", "")) == "" and not (s.player.get("tool_wear", {}) as Dictionary).has("axe"), "REQ-0012-89: зламана сокира зникла зі спорядження, знос скинуто")
	var off: Variant = _wear_sim(false)
	ToolWear.tick(off, limit * 2.0)
	ok(off.player.items.has("axe") and not off.player.has("tool_wear"), "REQ-0012-89: за OFF знос не діє й ключа в player нема (байт-у-байт як було)")
	var sled: Variant = _wear_sim(true)
	sled.player.items.append("sledge")
	sled.player.equipped["tool"] = "sledge"
	ToolWear.tick(sled, limit * 2.0)
	ok(sled.player.items.has("sledge"), "REQ-0012-89: інструмент вищого тіру не зношується")
	var rec: Dictionary = Persistence.serialize_region(_wear_sim(true))
	var w: Variant = _wear_sim(true)
	ToolWear.tick(w, 1234.0)
	var rec2: Dictionary = Persistence.serialize_region(w)
	ok(not (rec.player as Dictionary).has("tool_wear") and (rec2.player as Dictionary).has("tool_wear"), "REQ-0012-89: знос потрапляє в сейв лише коли є (OFF-сейви незмінні)")


# Інтеграція: справжній цикл добування (order_gather → update) зношує інструмент; офлайн-догін — ні
func _t_tool_wear_in_gather() -> void:
	var s: Variant = _wear_sim(true)
	var cell: int = -1
	for c in s.map.nodes:
		if String(s.map.nodes[c].kind) == "tree":
			cell = int(c)
			break
	ok(cell >= 0, "gather-wear: на мапі є дерево")
	if cell < 0:
		return
	s.player.px = float(cell % int(s.n)) + 0.5
	s.player.py = float(cell / int(s.n)) + 1.5
	s.order_gather(cell % int(s.n), cell / int(s.n))
	for i in 200:
		s.update(0.1)
	var f: float = ToolWear.wear_fraction(s, "axe")
	ok(f > 0.0, "gather-wear: 20 с добування сокирою зношують її (%.5f)" % f)
	ok(f < 0.01, "gather-wear: знос іде у секундах активної роботи, не стрибком (%.5f)" % f)
	var before: float = f
	var Realtime = load("res://scripts/sim/realtime.gd")
	Realtime.catch_up(s, T0, T0 + 20 * H)
	ok(is_equal_approx(ToolWear.wear_fraction(s, "axe"), before), "gather-wear: офлайн-догін 20 год не зношує інструмент")


# REQ-0012-52 (машинна частина G4): після посадки перша осмислена дія — одна й доступна одразу (≤ 30 с sim-часу, 1 дія):
# у руці стартове багаття, поруч є вільна клітинка, `build` ставить вогонь; без модального туторіалу (герой не заблокований).
# Людський вимір «від старту застосунку на телефоні» (REQ-0010-42, 0012-52) це НЕ замінює.
func _t_ftue_first_action() -> void:
	var s: Variant = _session()
	var sim: Variant = s.sim
	ok(not bool(sim.dead) and sim.player.get("action") == null, "ftue: після посадки герой живий і не заблокований (нема модального туторіалу)")
	ok(InvMod.count(sim, InvMod.BLD + "campfire") >= 1, "ftue: стартовий набір має багаття для першої дії")
	var placed := false
	var px: int = int(sim.player.px)
	var py: int = int(sim.player.py)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]:
		if sim.build_valid(px + d.x, py + d.y):
			var t0: float = float(sim.time.day) + float(sim.time.frac)
			sim.try_build("campfire", px + d.x, py + d.y)
			placed = sim.has_building("campfire")
			ok(float(sim.time.day) + float(sim.time.frac) - t0 < 30.0 / 86400.0, "ftue: перша дія виконується в тому ж тіку (≤ 30 с)")
			break
	ok(placed, "ftue: одна дія `build` ставить багаття поруч із героєм")
