# RealWorld — goals.gd : the onboarding goal chain (playability — «що мені робити далі?»).
#
# A first session used to open on a frozen map with no hint beyond one feed line: the loop (fire →
# shelter → bed → bench → research → defence) existed but nothing TAUGHT it. This module is the
# teacher: an ordered list of goals, each a PURE check over live sim/session state returning progress
# 0..1. The session keeps completion STICKY (a goal done stays done even if the campfire later burns
# down) and logs the toast; the HUD reads goals_view() as value data. No sim state is added and no
# rng is consumed — goals observe, they never steer (twins/rejoin/world_hash untouched).
#
# Static functions only; never references res://scripts/ui (R1).
extends RefCounted

const GameData = preload("res://scripts/data.gd")

# Optional "build": the build-palette slot the goal is about — the HUD pulses that slot (contextual guidance:
# point at the control instead of only describing it). View metadata; checks never read it.
# Ordered: the panel shows the FIRST incomplete goal, but any goal completes whenever its check is
# met (out-of-order play is fine — a player who builds the bed first just sees it ticked).
const GOALS := [
	{"id": "fire", "build": "campfire", "title": "🔥 Розпали багаття",
		"hint": "Натисни 9 (Багаття) і клікни біля пішака. Вогонь гріє +4°C на 6 клітин і світить уночі."},
	{"id": "gather", "title": "🪵 Добудь ресурси",
		"hint": "Клікни по дереву 🌲 чи скелі 🪨 — пішак добуває сам, а повну торбу несе на склад (S)."},
	{"id": "shelter", "build": "wall", "title": "🏠 Збудуй укриття",
		"hint": "Обнеси клітинку стінами (1) і дверима (2) та стань усередину: у приміщенні тепло тримається. Затисни ЛКМ — стіна ляже рядом."},
	{"id": "bed", "build": "bed", "title": "🛏 Постав ліжко",
		"hint": "Ліжко (6) поруч — пішак сам лягає спати: сон відновлює сили й лікує рани. Найкраще — в укритті."},
	{"id": "tools", "build": "workbench", "title": "🛠 Верстак і сокира",
		"hint": "Верстак (5) сам пиляє дошки. Відкрий спорядження (I) і скрафти сокиру ⚒ — рубаєш у 1.6× швидше."},
	{"id": "food", "title": "🍖 Запас їжі",
		"hint": "Збирай ягоди з кущів 🫐: тримай на складі 30+ їжі. Біля складу пішак їсть сам."},
	{"id": "bench", "build": "research_bench", "title": "🔬 Дослідницький стіл",
		"hint": "Стіл (8) дає очки досліджень: нові будівлі, броня, пастки й турелі."},
	{"id": "tech", "title": "🔓 Перше відкриття",
		"hint": "Обери проєкт у панелі «Дослідження» — або зачекай: стіл сам бере найдешевший."},
	{"id": "defense", "build": "spike_trap", "title": "🛡 Оборона",
		"hint": "Шипи (Полювання) чи турель (Механіка) біля входу. Рейди можливі з 5-го дня."},
	{"id": "survive", "title": "🌅 Переживи 5 днів",
		"hint": "Тепло, їжа, сон. Стрілка часу: Space — пауза, +/− — швидкість."},
]
# spec 0009 (inventory world): buildings are ITEMS — craft them in the backpack (🎒 / Tab), hold, place.
const INV_HINT := {
	"fire": "Багаття вже в руці (слот 1). Клікни біля пішака — воно ляже. Вогонь гріє й світить уночі.",
	"shelter": "🎒 Tab → скрафти «Стіна» і «Двері» з каменю й дерева, візьми в руку (1–8) і обстав клітинку.",
	"bed": "🎒 Tab → скрафти «Ліжко», візьми в руку й постав поруч: сон лікує й відновлює сили.",
	"tools": "🎒 Tab → «Верстак» у руку й на землю. Біля верстака крафтиться сокира — рубаєш у 1.6× швидше.",
	"bench": "Біля верстака скрафти «Дослідницький стіл» і постав — він дає очки досліджень.",
	"defense": "Біля верстака скрафти шипи чи турель і постав біля входу. Рейди можливі з 5-го дня.",
}
const FOOD_TARGET := 30
const GATHER_TARGET := 15         # units gathered by this pawn (skills.gather grows 0.2 per unit)
const SURVIVE_DAY := 6            # «пережити 5 днів» == reach the morning of day 6

static func count() -> int:
	return GOALS.size()

static func title_of(id: String) -> String:
	for g in GOALS:
		if String(g.id) == id:
			return String(g.title)
	return id

# Progress 0..1 of one goal against live state. `session` may be a lean fake without progression.
static func progress(id: String, sim, session) -> float:
	match id:
		"fire":
			return 1.0 if sim.has_building("campfire") else 0.0
		"gather":
			return clampf(float(sim.player.skills.get("gather", 0.0)) / (0.2 * GATHER_TARGET), 0.0, 1.0)
		"shelter":
			if sim.is_indoor(int(sim.player.px), int(sim.player.py)):
				return 1.0
			return 0.6 if not (sim.indoor as Dictionary).is_empty() else _walls_progress(sim)
		"bed":
			return 1.0 if _has_capability(sim, "bed") else 0.0
		"tools":
			var tool_owned := false
			for it in sim.player.items:
				if GameData.ITEMS.has(it) and String(GameData.ITEMS[it].slot) == "tool":
					tool_owned = true
			if tool_owned:
				return 1.0
			return 0.5 if sim.has_workbench() else 0.0
		"food":
			return clampf(float(sim.res_amount("food")) / float(FOOD_TARGET), 0.0, 1.0)
		"bench":
			return 1.0 if sim.has_building("research_bench") else 0.0
		"tech":
			var prog: Variant = session.progression if (session != null and "progression" in session) else null
			if prog == null:
				return 0.0
			return 1.0 if prog.unlocked_count() > 0 else clampf(float(prog.active_pct()), 0.0, 0.99)
		"defense":
			return 1.0 if (_has_capability(sim, "trap_dps") or _has_capability(sim, "range")) else 0.0
		"survive":
			return clampf(float(int(sim.time.day) - 1) / float(SURVIVE_DAY - 1), 0.0, 1.0)
	return 0.0

# Partial credit for a room in progress: each wall/door counts toward the 4 sides of a 1-cell room.
static func _walls_progress(sim) -> float:
	var n := 0
	for b in sim.buildings:
		var k := String(b.kind)
		if k == "wall" or k.begins_with("door") or k.ends_with("_wall"):
			n += 1
	return clampf(float(n) / 4.0, 0.0, 0.5)

static func _has_capability(sim, cap: String) -> bool:
	for b in sim.buildings:
		var def: Dictionary = sim.building_def(String(b.kind))
		var v: Variant = def.get(cap, null)
		if v != null and (bool(v) if v is bool else float(v) > 0.0):
			return true
	return false
