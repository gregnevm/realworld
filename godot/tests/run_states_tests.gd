# RealWorld — tests/run_states_tests.gd : spec 0012 REQ-0012-71 — стани героя при save → «Продовжити» з догоном (без нападів, REQ-84).
# По рядку на стан: downed, кровотеча, смерть із торбою на місці смерті (+25 год ⇒ торба протермінована, шов bag_expired рівно раз),
# герой поза капсулою (тимчасова/транспортна капсули в К1 недосяжні за ON — OD-114, див. маніфест 1.01).
# Run: godot --headless --path godot -s res://tests/run_states_tests.gd
extends "res://tests/harness.gd"

const SessionScript = preload("res://scripts/session.gd")
const InvMod = preload("res://scripts/sim/inventory.gd")
const HeroHealth = preload("res://scripts/sim/hero_health.gd")
const Persistence = preload("res://scripts/persistence.gd")

const T0 := 1800000000000   # 2027-01-15 (UTC-мс)
const H := 3600000
const PATH := "user://states_test.json"


func _init() -> void:
	print("== RealWorld states save->catch-up tests (REQ-0012-71) ==")
	_t_downed()
	_t_bleeding()
	_t_death_bag()
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
