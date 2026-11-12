# RealWorld — scripts/hints.gd : spec 0012 §3.8 / §5.5 — м'які діегетичні підказки FTUE відкритого світу (лише за use_realtime = ON).
#
# Замість послідовного ланцюга цілей (OD-31/50): одна підказка за раз, вибрана СИТУАЦІЄЮ, а не номером кроку.
# Перелік і частота — OD-146 (агент за делегуванням власника, 2026-11-12; закриває OD-113 для кроку 1).
#   evaluate(view, cooldowns, now_ms) -> id  — чиста функція (REQ-0012-48): той самий вхід ⇒ той самий id; стану порядку нема.
#   view_of(sim)                             — знімок ситуації з сима (лише читає; REQ-0012-51 observe-only).
# Sticky-стан (cooldowns: id -> until_ms) живе в Session і в сейві поза world_hash (REQ-0012-49/51).
extends RefCounted

const Gear = preload("res://scripts/kernel/gear.gd")
const MAIN_CAPSULE_KIND := "main_capsule"   # = MainCapsule.KIND (тест звіряє); без preload, щоб не тягнути sim/ у ui-шар

const SHOW_MS := 60000          # OD-146: підказка гасне сама за 60 с (або раніше — коли ситуація минула)
const COOLDOWN_MS := 600000     # OD-146: та сама підказка не повертається 10 хв після того, як згасла
const THREAT_RADIUS := 12.0     # клітинок: машина/патруль/рейдер «поруч»
const HUNGER_LOW := 35.0        # шкала 0..100

# Пріоритет — порядок у списку (загроза > холод > голод > ніч > порожній хотбар). `build` — слот, що дихає (REQ-0012-50).
const HINTS := [
	{"id": "threat", "title": "⚠ Машина поруч", "hint": "Стіна й двері зупинять її — постав їх із хотбару між собою й загрозою.", "build": "wall"},
	{"id": "cold", "title": "🥶 Холодно", "hint": "Багаття поруч зігріває — постав його з хотбару біля себе.", "build": "campfire"},
	{"id": "hunger", "title": "🍖 Голодно", "hint": "Ягоди з кущів і їжа зі складу втамують голод.", "build": ""},
	{"id": "night", "title": "🌇 Скоро ніч", "hint": "У темряві робота йде повільніше — смолоскип освітить місце.", "build": "torch"},
	{"id": "hotbar", "title": "🎒 Хотбар порожній", "hint": "Відкрий рюкзак і переклади потрібні речі в нижні слоти.", "build": ""},
	{"id": "gather", "title": "🌲 Розвідай околиці", "hint": "Дерево й камінь — основа стін і багаття. Торкнись дерева чи скелі поруч.", "build": ""},
]

static func def_of(id: String) -> Dictionary:
	for h in HINTS:
		if String(h.id) == id:
			return h
	return {}

# Чи ситуація для підказки `id` триває в цьому знімку.
static func applies(id: String, view: Dictionary) -> bool:
	match id:
		"threat": return bool(view.get("threat", false))
		"cold": return bool(view.get("cold", false)) and not bool(view.get("heat_near", false))
		"hunger": return float(view.get("hunger", 100.0)) < HUNGER_LOW
		"night": return bool(view.get("night_soon", false))
		"hotbar": return bool(view.get("hotbar_empty", false))
		"gather": return not bool(view.get("built", true))
	return false

# REQ-0012-48: перша за пріоритетом підказка, чия ситуація триває і яка не на cooldown; "" — нічого.
static func evaluate(view: Dictionary, cooldowns: Dictionary, now_ms: int) -> String:
	for h in HINTS:
		var id := String(h.id)
		if now_ms < int(cooldowns.get(id, 0)):
			continue
		if applies(id, view):
			return id
	return ""

# Знімок ситуації (лише читання сима). Ніч — вечір (frac > 0.5) і світло вже спадає (0.05 < daylight < 0.6).
static func view_of(sim) -> Dictionary:
	var p: Dictionary = sim.player
	var dl: float = float(sim.daylight_level())
	var heat := false
	for b in sim.buildings:
		if float(sim.building_def(String(b.kind)).get("extra", {}).get("heat", 0.0)) > 0.0 and sim.device_active(b) \
				and absi(int(b.x) - int(p.px)) + absi(int(b.y) - int(p.py)) <= sim.EMITTER_RADIUS:
			heat = true
			break
	var hotbar_empty := false
	if sim.use_inventory:
		hotbar_empty = true
		var inv: Array = p.get("inv", [])
		for i in mini(8, inv.size()):
			if inv[i] is Dictionary and String((inv[i] as Dictionary).get("id", "")) != "":
				hotbar_empty = false
				break
	var built := false
	for b in sim.buildings:
		var k := String(b.kind)
		if k != "storage" and k != MAIN_CAPSULE_KIND:
			built = true
			break
	return {
		"built": built,
		"threat": sim._nearest_enemy(float(p.px), float(p.py), THREAT_RADIUS) != null,
		"cold": float(sim.hero_felt_c()) < Gear.COMFORT_MIN_C,
		"heat_near": heat,
		"hunger": float(p.hunger),
		"night_soon": float(sim.time.frac) > 0.5 and dl > 0.05 and dl < 0.6,
		"hotbar_empty": hotbar_empty,
	}
