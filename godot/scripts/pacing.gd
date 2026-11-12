# RealWorld — scripts/pacing.gd : spec 0012 §5.3 — ОДНА таблиця темпу реального часу (use_realtime = ON).
#
# Дані, не код: ключ -> цільова тривалість у РЕАЛЬНИХ секундах + підстава (рішення власника) + sanity-діапазон.
# Агент чисел не обирає (P1): кожне значення — з docs/design/decisions.md; чого рішеннями не задано — `s: -1`
# із міткою TBD (споживач тоді лишає OFF-поведінку і REQ лишається `open · blocked`).
# Без стану, без class_name/autoload (AGENTS.md): споживачі `const Pacing = preload(...)`.
# За OFF цей файл НІХТО не читає (REQ-0012-1/3: OFF байт-у-байт).
extends RefCounted

const DAY_S := 86400.0
const VERSION := 1       # REQ-0012-73: версія таблиці темпу в сейві; новіша за збірку — відмова, не мовчазна підміна   # доба за ON (OD-35: реальний час 1:1)

# s  — тривалість у реальних секундах (-1 = не задано рішенням -> TBD);
# lo/hi — sanity-діапазон рядка (тест REQ-0012-22: кожне задане значення лежить у ньому);
# src — підстава; для діапазонних рішень (raid_mtb/raid_warn) s = нижня межа, hi = верхня.
const TABLE := {
	"hunger_to_critical": {"s": 36000.0, "lo": 28800.0, "hi": 43200.0, "src": "OD-55 (10 год до нуля шкали; OD-52: критичний = нуль)"},
	"rest_to_collapse":   {"s": 57600.0, "lo": 43200.0, "hi": 72000.0, "src": "OD-69 (~16 год без сну)"},
	"frostbite_onset":    {"s": 10800.0, "lo": 7200.0,  "hi": 14400.0, "src": "OD-70 (~3 год, київська зима без вогню/стін)"},
	"warmup_full":        {"s": 3600.0,  "lo": 1800.0,  "hi": 7200.0,  "src": "OD-49 (~1 год у теплі; стартове до плейтесту)"},
	"raid_grace":         {"s": 259200.0, "lo": 259200.0, "hi": 259200.0, "src": "OD-66 (3 доби від першої посадки)"},
	"raid_mtb":           {"s": 259200.0, "lo": 259200.0, "hi": 345600.0, "src": "OD-86 (~1 рейд на 3–4 доби)"},
	"raid_warn":          {"s": 600.0,   "lo": 600.0,   "hi": 1800.0,  "src": "OD-88 (10–30 хв до контакту)"},
	"tool_wear_t1":       {"s": 18000.0, "lo": 10800.0, "hi": 28800.0, "src": "OD-92 (~5 год активної роботи; blocked by OD-R27 — споживача нема)"},
	"sleep_full":         {"s": 3600.0,  "lo": 1800.0,  "hi": 28800.0, "src": "OD-143 (1 год у ліжку до повного; агент за делегуванням 2026-11-12)"},
	"starve_to_death":    {"s": 192000.0, "lo": 86400.0, "hi": 345600.0, "src": "OD-141 (~2.2 доби від нуля шкали: MALNUTRITION_GAIN 0.45/добу на реальній добі)"},
	"bleed_to_downed":    {"s": -1.0, "src": "OD-141: робочий темп (як OFF) — числа в kernel/health.gd, не тут"},
	"infection_course":   {"s": -1.0, "src": "OD-141: робочий темп (як OFF) — числа в kernel/health.gd, не тут"},
	"patrol_interval":    {"s": -1.0, "src": "OD-143: як OFF (амбієнт у секундах sim; sdt = dt за ON)"},
	"research_t1":        {"s": -1.0, "src": "OD-140: робочий темп (WORK_DAY_S 150 с, як OFF)"},
	"farm_grow":          {"s": -1.0, "src": "OD-140: робочий темп (WORK_DAY_S 150 с, як OFF)"},
}

# Тривалість рядка в секундах; -1.0 — не задано (TBD) або ключа нема.
static func seconds(key: String) -> float:
	return float((TABLE.get(key, {}) as Dictionary).get("s", -1.0))

static func is_set(key: String) -> bool:
	return seconds(key) > 0.0

# Швидкість спаду шкали `span` (за замовчуванням 0..100) за 1 реальну секунду так, щоб повна шкала
# дійшла до нуля рівно за `seconds(key)`. Для незаданого рядка — 0.0 (споживач мусить перевірити is_set).
static func per_sec(key: String, span: float = 100.0) -> float:
	var s: float = seconds(key)
	return span / s if s > 0.0 else 0.0

# Те саме в одиницях kernel/needs.gd (`fall_per_day`, 1.0 = повна шкала за добу DAY_S) — REQ-0012-14:
# темп іде через day_len, а не через захардкоджений `*0.42*dt`.
static func fall_per_day(key: String) -> float:
	var s: float = seconds(key)
	return DAY_S / s if s > 0.0 else 0.0
