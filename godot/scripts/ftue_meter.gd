# RealWorld — ftue_meter.gd : хронометраж G4 (REQ-0010-42, REQ-0012-52) — два виміри першої хвилини.
#
#   1) екран старту -> посадка капсули (`wait_ms`; origin "app" = від старту застосунку, "menu" = від повернення в меню);
#   2) посадка -> перша осмислена дія (`action_ms`; ціль REQ-0012-52: <= 30 с).
#
# «Осмислена дія» тут — перша зміна світу рукою гравця: добута одиниця ресурсу (росте skills.gather)
# або поставлена споруда (росте кількість buildings). Це спостереження, не правило гри: модуль лише
# ЧИТАЄ sim (як goals.gd), нічого в нього не пише, rng не чіпає — world_hash і сейв не змінюються.
#
# View-рівень / рівень пристрою: файл user://ftue.json живе поруч із settings.json, поза сейвом світу.
# Годинник модуль не читає: тривалості (мс) передає викликач (newhud_main — монотонний Time.get_ticks_msec).
# Пороги для відрізка «до посадки» не задано (OD-31: TBD) — показуємо число без вердикту.
extends RefCounted

const PATH := "user://ftue.json"
const VERSION := 1
const KEEP := 10                  # скільки останніх вимірів тримаємо (сесія плейтесту: 3–7 гравців на одному телефоні)
const ACTION_TARGET_MS := 30000   # REQ-0012-52: перша осмислена дія <= 30 с від посадки

var runs: Array = []              # найновіший — останній: {origin, wait_ms, action_ms (-1 = ще не було), action, build, at}
var _base: Dictionary = {}
var _open := false                # іде вимір «посадка -> перша дія»

# Що вважаємо слідом дії гравця (чисте читання sim).
static func probe(sim) -> Dictionary:
	if sim == null:
		return {"gather": 0.0, "built": 0}
	return {"gather": float((sim.player as Dictionary).get("skills", {}).get("gather", 0.0)), "built": (sim.buildings as Array).size()}

# Посадка відбулась: фіксуємо перший вимір і починаємо другий.
func begin(origin: String, wait_ms: int, base: Dictionary, build: String, at: String) -> void:
	runs.append({"origin": "app" if origin == "app" else "menu", "wait_ms": maxi(0, wait_ms), "action_ms": -1, "action": "", "build": build, "at": at})
	while runs.size() > KEEP:
		runs.pop_front()
	_base = base.duplicate()
	_open = true

# Викликається щокадру після посадки; true — рівно один раз, коли зловлено першу дію (тоді викликач зберігає файл).
func observe(since_land_ms: int, now: Dictionary) -> bool:
	if not _open or runs.is_empty():
		return false
	var kind := ""
	if int(now.get("built", 0)) > int(_base.get("built", 0)):
		kind = "build"
	elif float(now.get("gather", 0.0)) > float(_base.get("gather", 0.0)) + 0.0001:
		kind = "gather"
	if kind == "":
		return false
	var r: Dictionary = runs[runs.size() - 1]
	r["action_ms"] = maxi(0, since_land_ms)
	r["action"] = kind
	_open = false
	return true

func is_open() -> bool:
	return _open

static func _secs(ms: int) -> String:
	return ("%.1f с" % (ms / 1000.0)) if ms < 10000 else ("%d с" % int(round(ms / 1000.0)))

static func row_text(r: Dictionary) -> String:
	var head: String = "посадка за %s від %s" % [_secs(int(r.get("wait_ms", 0))), "старту застосунку" if String(r.get("origin", "")) == "app" else "меню"]
	var a: int = int(r.get("action_ms", -1))
	if a < 0:
		return "%s · першої дії ще не було" % head
	var what: String = "споруда" if String(r.get("action", "")) == "build" else "збір"
	return "%s · перша дія (%s) за %s %s" % [head, what, _secs(a), "✓" if a <= ACTION_TARGET_MS else "✗ (ціль ≤ 30 с)"]

# Рядки для ☰ / налаштувань: найновіший вимір першим, не більше `limit`. Порожньо, якщо вимірів нема.
func lines(limit: int = 1) -> PackedStringArray:
	var out := PackedStringArray()
	var i: int = runs.size() - 1
	while i >= 0 and out.size() < limit:
		var r: Dictionary = runs[i]
		out.append("⏱ Плейтест-вимір: %s%s" % [row_text(r), (" · %s" % String(r.at)) if limit > 1 and String(r.get("at", "")) != "" else ""])
		i -= 1
	return out

func to_dict() -> Dictionary:
	return {"version": VERSION, "runs": runs.duplicate(true)}

# Чужий/зіпсований запис = порожній журнал (не падаємо й не показуємо сміття).
func from_dict(d: Variant) -> bool:
	runs = []
	_open = false
	if typeof(d) != TYPE_DICTIONARY or int((d as Dictionary).get("version", -1)) != VERSION or typeof((d as Dictionary).get("runs")) != TYPE_ARRAY:
		return false
	for r in ((d as Dictionary)["runs"] as Array):
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var w: Variant = (r as Dictionary).get("wait_ms")
		var a: Variant = (r as Dictionary).get("action_ms")
		if not (typeof(w) in [TYPE_INT, TYPE_FLOAT]) or not (typeof(a) in [TYPE_INT, TYPE_FLOAT]):
			continue
		var kind: String = String((r as Dictionary).get("action", ""))
		runs.append({"origin": "app" if String((r as Dictionary).get("origin", "")) == "app" else "menu", "wait_ms": maxi(0, int(w)),
			"action_ms": maxi(-1, int(a)), "action": kind if kind in ["build", "gather"] else "",
			"build": String((r as Dictionary).get("build", "")), "at": String((r as Dictionary).get("at", ""))})
	while runs.size() > KEEP:
		runs.pop_front()
	return true

func save(path: String = PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	return true

func load_file(path: String = PATH) -> bool:
	if not FileAccess.file_exists(path):
		runs = []
		_open = false
		return false
	return from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
