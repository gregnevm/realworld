# RealWorld — sim/tool_wear.gd : spec 0012 REQ-0012-89 (OD-92, OD-5) — знос інструментів першого тіру (лише за use_realtime = ON).
#
# Одиниця — секунди АКТИВНОЇ роботи інструментом (час, коли герой справді добуває ним), а не UTC-мс: офлайн-час не зношує
# (догін видобутку не веде). Ліміт — Pacing.tool_wear_t1 (~5 год = 18 000 с). Знос лежить у player.tool_wear {id: секунди}
# (ключ з'являється лише після першої роботи ⇒ OFF-знімки, хеші й сейви байт-у-байт як були). Зламаний інструмент зникає з
# рюкзака й спорядження — скрафти новий у верстака (OD-5: ремонт = новий крафт). Інструменти вищих тірів (з `research`) не зношуються.
# Доменний модуль без стану: sim годинник не читає, RNG не споживає.
extends RefCounted

const Pacing = preload("res://scripts/pacing.gd")
const GameData = preload("res://scripts/data.gd")
const Inventory = preload("res://scripts/sim/inventory.gd")

const WARN_AT := 0.9   # з 90 % зносу герой бачить «тупиться»

# Інструмент першого тіру: слот tool без дослідницького гейта (сокира, кайло).
static func is_tier1(id: String) -> bool:
	return GameData.ITEMS.has(id) and String(GameData.ITEMS[id].slot) == "tool" and String(GameData.ITEMS[id].get("research", "")) == ""

# dt — секунди активної роботи (викликає sim у кроці добування, коли герой уже на місці). Повертає true, якщо інструмент зламався.
static func tick(s, dt: float) -> bool:
	if not s.use_realtime or dt <= 0.0:
		return false
	var id: String = String(s.player.equipped.get("tool", ""))
	if id == "" or not is_tier1(id):
		return false
	var limit: float = Pacing.seconds("tool_wear_t1")
	var wear: Dictionary = s.player.get("tool_wear", {})
	var before: float = float(wear.get(id, 0.0))
	var w: float = before + dt
	var name: String = String(GameData.ITEMS[id].name)
	if w >= limit:
		wear.erase(id)
		s.player["tool_wear"] = wear
		_break(s, id)
		s._log("🔧 %s зламалась — скрафти нову на верстаку." % name, "warn")
		return true
	wear[id] = w
	s.player["tool_wear"] = wear
	if before < limit * WARN_AT and w >= limit * WARN_AT:
		s._log("🔧 %s тупиться — скоро зламається." % name, "warn")
	return false

# Частка зносу 0..1 (HUD/тести); 0 за OFF і для не-першого тіру.
static func wear_fraction(s, id: String) -> float:
	if not s.use_realtime or not is_tier1(id):
		return 0.0
	return clampf(float((s.player.get("tool_wear", {}) as Dictionary).get(id, 0.0)) / Pacing.seconds("tool_wear_t1"), 0.0, 1.0)

static func _break(s, id: String) -> void:
	(s.player.items as Array).erase(id)
	if (s.player.equipped as Dictionary).get("tool", "") == id:
		s.player.equipped["tool"] = ""
	if s.get("use_inventory") == true:
		Inventory.take(s, id, 1)
